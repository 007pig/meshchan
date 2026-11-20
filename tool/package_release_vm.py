#!/usr/bin/env python3
"""Run the extracted App's offline write/normal-quit/reopen in the test VM."""
import argparse
from contextlib import closing
import importlib.util
import json
from pathlib import Path
import re
import shlex
import signal
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import time

import build_release as build
from release_materials import digest
from release_package_archive import archive_members, check_payload, prefixed

ROOT = build.ROOT
PRODUCT_RUNNER = 'apps/meshchan_app/tool/macos_vm/product.sh'
GUEST_LAUNCHER = '.agents/skills/macos-vm-gui-testing/scripts/guest.sh'
q = shlex.quote


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT/relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def guest_inventory(vm, guest, expected):
    with tempfile.TemporaryFile() as stream:
        # Restricted PAX extends USTAR only where needed, including long
        # paths and raw link targets. Compare the same data-only inventory
        # as the engineering archive.
        vm.remote('COPYFILE_DISABLE=1 /usr/bin/tar -cf - --format paxr '
                  '--no-acls --no-xattrs --no-fflags -C '+q(guest)+' Meshchan.app',
                  stdout=stream, timeout=90)
        stream.seek(0)
        with tarfile.open(fileobj=stream, mode='r:') as archive:
            archive_members(archive, prefixed('Meshchan.app', expected), ('Meshchan.app',))


def require_ready_connection(vm):
    # A user SSH config can also enable multiplexing for batch connections.
    # Reuse an existing socket without starting a master on fallback.
    vm.opts = ['-o', 'ControlMaster=no', '-o', 'ControlPersist=no', *vm.opts]
    if vm.c.get('credentials_file'):
        result = subprocess.run(['/usr/bin/ssh', *vm.opts, '-O', 'check', vm.target],
                                capture_output=True, timeout=10)
        if result.returncode:
            raise ValueError('Connect the test VM with the VM skill before packaging')
        # The packaging supervisor must never own a persistent SSH master.
        # Keep subsequent remote calls in batch mode even if this socket drops.
        del vm.c['credentials_file']


def require_absent_pid(vm, pid):
    if pid <= 1:
        raise ValueError('Unexpected guest App PID')
    vm.remote("set -o pipefail\n/bin/ps -axo pid= | /usr/bin/awk -v pid="
              +str(pid)+" '$1 == pid { found=1 } END { exit found }'", timeout=10)


def guest_session(vm):
    session = vm.remote('/usr/bin/mktemp -d '+q(vm.root+'/package.XXXXXXXX'),
                        capture_output=True, text=True, timeout=10).stdout.strip()
    if not re.fullmatch(re.escape(vm.root)+r'/package\.[A-Za-z0-9]{8}', session):
        raise ValueError('Guest did not return a fresh package session path')
    return session


def start_guest(vm, session):
    launcher = vm.root+'/guest.sh'
    runner = vm.root+'/product.sh'
    executor = vm.root+'/UTMUIProbe.app'
    args = [vm.c['uuid'], 'product', vm.root, session]
    # The existing signed executor supports the default root even on older
    # deployments. The final argument identifies this launch in its OS argv.
    script = f'''set -e
test "$(/usr/sbin/ioreg -a -n Root -d1 | /usr/bin/plutil -extract IOConsoleLocked raw -o - -)" = false ||
  {{ echo 'Unlock the guest desktop before packaging' >&2; exit 66; }}
test ! -e {q(vm.root+'/active.lock')} ||
  {{ echo 'Another guest test holds the shared lock' >&2; exit 67; }}
test "$(/usr/bin/shasum -a 256 < {q(launcher)})" = {q(digest(ROOT/GUEST_LAUNCHER)+'  -')} ||
  {{ echo 'Installed guest launcher differs from the reviewed script' >&2; exit 69; }}
test "$(/usr/bin/shasum -a 256 < {q(runner)})" = {q(digest(ROOT/PRODUCT_RUNNER)+'  -')} ||
  {{ echo 'Installed product runner differs from the reviewed script' >&2; exit 69; }}
/usr/bin/open -n {q(executor)} --args {shlex.join(args)}
'''
    vm.remote(script, timeout=10)


def owned_guest_run(vm, session):
    root = q(vm.root)
    runner_args = ' '+shlex.join([vm.root+'/product.sh', vm.c['uuid'], vm.root])
    executor = vm.root+'/UTMUIProbe.app/Contents/MacOS/UTMUIProbe'
    executor_args = ' '+shlex.join([vm.c['uuid'], 'product', vm.root, session])
    script = f'''root={root}
lock="$root/active.lock"
lock_identity=$(/usr/bin/stat -f '%d:%i' "$lock" 2>/dev/null) || exit 0
run=$(/bin/cat "$root/latest-run" 2>/dev/null) || exit 0
pid=$(/bin/cat "$lock/pid" 2>/dev/null) || exit 0
case "$pid" in ''|*[!0-9]*) exit 0;; esac
case "$run" in "$root"/runs/*-product-"$pid") ;; *) exit 0;; esac
case "$(/bin/ps -ww -p "$pid" -o command=)" in *{q(runner_args)}) ;; *) exit 0;; esac
parent=$(/bin/ps -p "$pid" -o ppid= | /usr/bin/tr -d '[:space:]')
case "$parent" in ''|*[!0-9]*) exit 0;; esac
case "$(/bin/ps -ww -p "$parent" -o command=)" in
  {q(executor)}*{q(executor_args)}) ;;
  *) exit 0;;
esac
test "$(/usr/bin/stat -f '%d:%i' "$lock" 2>/dev/null)" = "$lock_identity" || exit 0
printf '%s\\n' "$run" "$lock_identity"
'''
    lines = vm.remote(script, capture_output=True, text=True, timeout=5).stdout.splitlines()
    if not lines:
        return None
    if len(lines) != 2 or not re.fullmatch(r'[0-9]+:[0-9]+', lines[1]):
        raise ValueError('Owned guest runner reported an invalid lock identity')
    run, lock_identity = lines
    token = run.rsplit('/', 1)[-1]
    if vm.runpath(token) != run:
        raise ValueError('Owned guest runner reported an invalid run path')
    return {'run': token, 'lockIdentity': lock_identity}


def record_guest_run(product, session, timeout):
    vm = product.vm
    deadline = time.monotonic()+timeout
    while True:
        if owner := owned_guest_run(vm, session):
            product.state.update(owner)
            product.save()
            return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(0.1)


def finish_guest(product, session):
    # If startup was interrupted, recover only a runner attested to this
    # launch. A different process may have acquired the VM's shared lock.
    if 'run' not in product.state and not record_guest_run(product, session, timeout=2):
        return None
    product.finish()
    vm = product.vm
    receipt_path = q(vm.runpath(product.state['run'])+'/exit-code')
    # The executor opens the file before writing the status. A successful
    # read requires its terminating newline.
    try:
        result = vm.remote(f'''exit_receipt={receipt_path}
for attempt in {{1..60}}; do
    if test -f "$exit_receipt" && IFS= read -r code < "$exit_receipt"; then
        printf '%s\\n' "$code"
        exit 0
    fi
    sleep 0.1
done
exit 75
''', capture_output=True, text=True, timeout=10).stdout.rstrip('\n')
    except subprocess.CalledProcessError as error:
        if error.returncode == 75:
            raise ValueError('Timed out waiting for the guest executor exit receipt') from None
        raise
    if result != '0':
        raise ValueError('Guest executor did not finish normally')
    lock = q(vm.root+'/active.lock')
    owned_lock = q(product.state['lockIdentity'])
    # A subsequent guest run can acquire a new lock after this one exits.
    # Compare identities so that its lock is left alone.
    released = vm.remote(f'''lock={lock}
if current=$(/usr/bin/stat -f '%d:%i' "$lock" 2>/dev/null); then
    if test "$current" != {owned_lock}; then echo released; fi
elif test ! -e "$lock" && test ! -L "$lock"; then
    echo released
fi
''', capture_output=True, text=True, timeout=10).stdout.strip()
    if released != 'released':
        raise ValueError('Guest executor exit did not release its test lock')
    return 0


def runtime_command(args, cwd, prefix):
    # Wait for this shell's direct child. The guest deadline also covers an SSH
    # interruption while the job is running independently in the GUI session.
    return f'''cd {q(cwd)}
pid=
cleanup() {{
  if [[ -n "$pid" && $(jobs -pr) == "$pid" ]]; then
    kill -TERM "$pid" 2>/dev/null || true
    sleep 1
    if [[ $(jobs -pr) == "$pid" ]]; then kill -KILL "$pid" 2>/dev/null || true; fi
    wait "$pid" || true
  fi
}}
trap cleanup EXIT
trap 'exit 143' TERM INT
/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LANG=en_US.UTF-8 HOME="$HOME" \\
  TMPDIR={q(cwd)} DYLD_PRINT_LIBRARIES=1 {shlex.join(args)} \\
  > {q(prefix+'.stdout')} 2> {q(prefix+'.stderr')} < /dev/null &
pid=$!
printf '%s\\n' "$pid" > {q(prefix+'.pid')}
deadline=$((SECONDS + 14))
while [[ $(jobs -pr) == "$pid" ]]; do
  if ((SECONDS >= deadline)); then
    echo 'Owned App runtime deadline exceeded' >&2
    exit 124
  fi
  sleep 0.1
done
code=0
wait "$pid" || code=$?
printf '%s\\n' "$code" > {q(prefix+'.exit')}
'''


def run(args):
    host = load('phase_1e5_vm_host', 'apps/meshchan_app/tool/macos_vm/host.py')
    checker = load('phase_1e5_runtime_checker', 'apps/meshchan_app/tool/check_macos_runtime.py')
    package_info = args.package_info.read_bytes()
    info = json.loads(package_info)
    ident = info['identity']
    prefix = 'Meshchan.app'
    expected = {name.removeprefix(prefix+'/'): item
                for name, item in info['payloadInventory'].items() if name.startswith(prefix+'/')}
    expected['.'] = info['payloadInventory'][prefix]
    check_payload(args.app, expected)
    evidence = args.evidence.absolute()
    evidence.mkdir(mode=0o700)
    report = {'status': 'RUNNING', 'identity': ident, 'app': str(args.app),
              'packageInfoSha256': build.sha(package_info),
              'appInventorySha256': build.sha(build.encoded(expected)), 'processes': []}
    receipt = evidence/'runtime.json'
    build.write(receipt, report)
    product = None
    session = None

    def redacted(value):
        if product is None:
            return value
        return value.replace(vm.root, '$GUEST_ROOT').replace('/Users/'+vm.c['user'], '$GUEST_HOME')

    def guest_error(error):
        if isinstance(error, subprocess.CalledProcessError):
            return f'Guest command exit {error.returncode}'
        if isinstance(error, subprocess.TimeoutExpired):
            return 'Guest command deadline exceeded'
        return redacted(str(error))

    try:
        product = host.Product(str(args.config), evidence)
        vm = product.vm
        require_ready_connection(vm)
        report['guestOS'] = vm.remote('/usr/bin/sw_vers; /usr/bin/uname -m',
                                      capture_output=True, text=True, timeout=20).stdout.strip()
        session = guest_session(vm)
        report['guestSession'] = session.rsplit('/', 1)[1]
        start_guest(vm, session)
        if not record_guest_run(product, session, timeout=10):
            raise ValueError('Timed out waiting for the owned guest executor')
        run_id = product.state['run']
        report['guestRun'] = run_id
        guest = session+'/products phase 1E.5'
        vm.remote('umask 077; /bin/mkdir '+q(guest), timeout=10)
        product.upload([(args.app, prefix)], guest)
        guest_inventory(vm, guest, expected)
        app = guest+'/'+prefix
        vm.remote('/usr/bin/codesign --verify --deep --strict --all-architectures '+q(app), timeout=30)
        cwd = guest+'/runtime workspace'
        vm.remote('/bin/mkdir '+q(cwd), timeout=10)
        fixture = cwd+'/meshchan-1d3-package'
        report.update(guestApp=redacted(app), guestInventoryBefore='PASS', guestSignature='PASS')

        for mode in ('write', 'read'):
            argv = [app+'/Contents/MacOS/Meshchan', '--meshchan-runtime='+mode,
                    '--data-dir='+fixture, '--runtime-exit']
            base = cwd+'/'+mode
            product.job(runtime_command(argv, cwd, base))

            def read(suffix):
                return vm.remote('/bin/cat '+q(base+suffix), capture_output=True,
                                 text=True, timeout=10).stdout

            pid, exit_code = int(read('.pid')), int(read('.exit'))
            stdout, stderr = read('.stdout'), read('.stderr')
            row = {'argv': list(map(redacted, argv)), 'cwd': redacted(cwd), 'pid': pid,
                   'stdout': redacted(stdout), 'stderr': redacted(stderr), 'exitCode': exit_code}
            report['processes'].append(row)
            build.write(receipt, report)
            require_absent_pid(vm, pid)
            sqlite = app+'/Contents/Frameworks/sqlite3.framework/'
            loaded = {path.removeprefix('/System/Volumes/Data') for path in
                      re.findall(r'^dyld\[\d+\]: <[0-9A-Fa-f-]+> (/.+)$', stderr, re.MULTILINE)}
            observed = sorted(loaded & {sqlite+'sqlite3', sqlite+'Versions/A/sqlite3'})
            if not observed:
                raise ValueError('Guest App did not load its own extracted SQLite')
            row['sqliteLoadedFrom'] = redacted(observed[0])
            reports = [json.loads(line) for line in stdout.splitlines() if line.startswith('{')]
            runtime = [r for r in reports if r.get('verification') == 'meshchan.runtime.1d3']
            shutdown = [r for r in reports if r.get('runtime') == 'meshchan.shutdown.1d3']
            checker.validate_runtime_report(exit_code, runtime, shutdown, ident['productVersion'], int(ident['appBuild']))
            row['pidAbsentAfterNormalExit'] = True
            if runtime[0]['mode'] != mode:
                raise ValueError('Unexpected guest runtime mode')
            row['draft'] = runtime[0]['draft']
            build.write(receipt, report)

        if report['processes'][0]['draft'] != report['processes'][1]['draft']:
            raise ValueError('Guest draft changed after reopening')
        data = evidence/'vm-fixture.sqlite'
        with data.open('xb') as stream:
            vm.remote('/bin/cat '+q(fixture+'/meshchan.sqlite'), stdout=stream, timeout=15)
        with closing(sqlite3.connect(data.as_uri()+'?mode=ro&immutable=1', uri=True)) as connection:
            drafts = connection.execute('select id, revision from stored_drafts').fetchall()
            integrity = connection.execute('pragma quick_check').fetchall()
        draft = report['processes'][1]['draft']
        if drafts != [(draft['id'], draft['revision'])] or integrity != [('ok',)]:
            raise ValueError('Guest SQLite file did not retain the closed draft')
        report['guestDatabaseSha256'] = digest(data)
        guest_inventory(vm, guest, expected)
        report['guestInventoryAfter'] = 'PASS'
        check_payload(args.app, expected)
    except BaseException as error:
        report['status'] = 'FAIL'
        report['error'] = guest_error(error)
        raise ValueError(report['error']) from None
    finally:
        try:
            if session is not None:
                if (exit_code := finish_guest(product, session)) is not None:
                    report['guestExecutorExit'] = exit_code
                    report['guestLockReleased'] = True
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            report.update(status='FAIL', cleanupError='Could not confirm owned guest executor shutdown ('
                          +guest_error(error)+')')
            raise ValueError(report['cleanupError']) from None
        finally:
            build.write(receipt, report)
    report['status'] = 'PASS'
    build.write(receipt, report)
    print(json.dumps({'status': 'PASS', 'guestRun': report['guestRun']}))


def interrupted(signum, _frame):
    raise KeyboardInterrupt(f'Interrupted by signal {signum}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('config', 'app', 'package-info', 'evidence'):
        parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, interrupted)
    try:
        run(args)
    except (Exception, KeyboardInterrupt) as error:
        print('ERROR: '+str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
