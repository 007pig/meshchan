#!/usr/bin/env python3
"""Run the extracted App's offline write/normal-quit/reopen in the test VM."""
import argparse
from contextlib import closing, contextmanager
import importlib.util
import json
import os
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
from release_materials import (
    ancestor_identities, digest, directory_identity, require_material_file, require_product_disjoint,
)
from release_package_archive import archive_members, check_payload, prefixed

ROOT = build.ROOT
PRODUCT_RUNNER = 'apps/meshchan_app/tool/macos_vm/product.sh'
GUEST_LAUNCHER = '.agents/skills/macos-vm-gui-testing/scripts/guest.sh'
DEFAULT_DATA_SUBDIR = Path('Library/Application Support/meshchan')
q = shlex.quote


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT/relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def guest_inventory(vm, guest, expected, *, scratch):
    with tempfile.TemporaryFile(dir=scratch) as stream:
        # Restricted PAX extends USTAR only where needed, including long
        # paths and raw link targets. Compare the same data-only inventory
        # as the engineering archive.
        vm.remote('COPYFILE_DISABLE=1 /usr/bin/tar -cf - --format paxr '
                  '--no-acls --no-xattrs --no-fflags -C '+q(guest)+' Meshchan.app',
                  stdout=stream, timeout=90)
        stream.seek(0)
        with tarfile.open(fileobj=stream, mode='r:') as archive:
            archive_members(archive, prefixed('Meshchan.app', expected), ('Meshchan.app',))


def checked_vm_configuration(path, protected_paths, *, cwd=None):
    """Read and check now, staging exact private bytes only on context entry."""
    cwd = Path.cwd() if cwd is None else Path(cwd).absolute()
    data = (cwd/Path(path).expanduser()).read_bytes()
    config = json.loads(data)
    runtime = config.get('runtime_dir') if isinstance(config, dict) else None
    if not isinstance(runtime, str) or not runtime:
        raise ValueError('VM configuration requires a nonempty runtime_dir')
    protected = tuple(protected_paths)
    runtime_path = {'VM runtime_dir': cwd/Path(runtime).expanduser()}
    require_product_disjoint(runtime_path, protected, protected='a selected release input')

    @contextmanager
    def staged():
        # A deferred constructor can run after the host path layout changes.
        # Recheck that layout while retaining the originally validated bytes.
        require_product_disjoint(runtime_path, protected, protected='a selected release input')
        # Ignore a caller TMPDIR pointing into published evidence or a candidate.
        temporary = Path('/private/tmp' if sys.platform == 'darwin' else '/tmp').resolve()
        parents = ancestor_identities(temporary)
        if any(temporary.is_relative_to(path.resolve()) or directory_identity(path) in parents for path in protected):
            raise ValueError('Private VM configuration temporary location overlaps a selected release input')
        with tempfile.NamedTemporaryFile(prefix='meshchan-private-vm-', suffix='.json', dir=temporary) as snapshot:
            os.fchmod(snapshot.fileno(), 0o600)
            snapshot.write(data)
            snapshot.flush()
            yield Path(snapshot.name)

    return staged()


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


def finish_guest(product, session, *, check_product_shutdown=True):
    # If startup was interrupted, recover only a runner attested to this
    # launch. A different process may have acquired the VM's shared lock.
    if 'run' not in product.state and not record_guest_run(product, session, timeout=2):
        return None
    vm = product.vm
    if check_product_shutdown:
        product.finish()
    else:
        # A failed child can leave valid executor ownership but no normal App
        # shutdown receipt. The caller must establish child exit separately.
        expected = {key: product.state[key] for key in ('run', 'lockIdentity')}
        if owned_guest_run(vm, session) != expected:
            raise ValueError('Failed App cleanup could not attest the owned guest runner')
        vm.remote('/usr/bin/touch '+q(vm.runpath(expected['run'])+'/finish'), timeout=10)
    return confirm_guest_exit(product)


def confirm_guest_exit(product):
    """Verify the already attested test executor exited and released its lock."""
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


def runtime_command(args, cwd, prefix, observer=None, library=None):
    # Wait for this shell's direct child. The guest deadline also covers an SSH
    # interruption while the job is running independently in the GUI session.
    if observer is None:
        trace_env = ' DYLD_PRINT_LIBRARIES=1'
    else:
        trace_env = ''
        args = [observer, prefix+'.image.json', library, *args]
    return f'''cd {q(cwd)}
pid=
cleanup() {{
  trap '' HUP INT TERM
  trap - EXIT
  if [[ -n "$pid" && $(jobs -pr) == "$pid" ]]; then
    kill -TERM "$pid" 2>/dev/null || true
    sleep 1
    if [[ $(jobs -pr) == "$pid" ]]; then kill -KILL "$pid" 2>/dev/null || true; fi
    wait "$pid" || true
  fi
}}
trap cleanup EXIT
# Latch an interrupt through the fork and registration of the owned child.
pending=
trap 'pending=${{pending:-129}}' HUP
trap 'pending=${{pending:-143}}' TERM INT
/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LANG=en_US.UTF-8 HOME="$HOME" \\
  TMPDIR={q(cwd)}{trace_env} {shlex.join(args)} \\
  > {q(prefix+'.stdout')} 2> {q(prefix+'.stderr')} < /dev/null &
pid=$!
trap 'exit 129' HUP
trap 'exit 143' TERM INT
[[ -z "$pending" ]] || exit "$pending"
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
    signed = getattr(args, 'signed_info', None) is not None
    if signed:
        import release_signed_runtime as runtime_probe

        args.app = runtime_probe.canonical(args.app)
        args.evidence = runtime_probe.canonical(args.evidence)
        manifest = runtime_probe.canonical(args.signed_info)
        info = runtime_probe.signed_info(manifest, args.expected_signed_info_sha256)
        info_binding = {'signedInfoSha256': args.expected_signed_info_sha256,
                        'signingProfile': runtime_probe.manifest_profile(info)}
    else:
        manifest = args.package_info
        package_info = manifest.read_bytes()
        info = json.loads(package_info)
        info_binding = {'packageInfoSha256': build.sha(package_info)}
    ident = info['identity']
    prefix = 'Meshchan.app'
    inventory = info['payloadInventory']
    protected = [args.app, manifest, Path.home()/DEFAULT_DATA_SUBDIR]
    # Protect the complete tree in the documented App-plus-CLI layout,
    # including a pinned tree whose declared CLI is missing.
    if 'meshctl' in inventory:
        app_parent = args.app.parent
        candidate = manifest.parent
        if (directory_identity(app_parent) == directory_identity(candidate)
                or (candidate/prefix).is_dir() or (candidate/'meshctl').is_dir()):
            protected.append(candidate)
        if (app_parent/'meshctl').is_dir():
            protected.append(app_parent)
    evidence = args.evidence.absolute()
    require_product_disjoint({'VM evidence': evidence}, protected, protected='a selected runtime input')
    configuration = checked_vm_configuration(args.config, [*protected, evidence])
    expected = {name.removeprefix(prefix+'/'): item
                for name, item in inventory.items() if name.startswith(prefix+'/')}
    expected['.'] = inventory[prefix]
    check_payload(args.app, expected)
    if signed and info_binding['signingProfile'] == runtime_probe.LOCAL_PROFILE:
        runtime_probe.verify_local_app(args.app, info)
    evidence.mkdir(mode=0o700)
    report = {'status': 'RUNNING', 'identity': ident, 'app': str(args.app),
              **info_binding,
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

    def finish_and_record_guest():
        if session is not None:
            if (exit_code := finish_guest(product, session)) is not None:
                if type(exit_code) is not int or exit_code != 0:
                    raise ValueError('Guest executor did not finish normally')
                report['guestExecutorExit'] = exit_code
                report['guestLockReleased'] = True

    try:
        if signed:
            local_probe = evidence/'release-image-probe'
            with (evidence/'image-observer-build.log').open('xb') as compilation:
                subprocess.run(runtime_probe.image_probe_command(local_probe), check=True, timeout=60,
                               stdout=compilation, stderr=subprocess.STDOUT,
                               env={**build.controlled_environment(), 'TMPDIR': str(evidence)})
            probe_sha = digest(local_probe)
            report['observerSha256'] = probe_sha
        with configuration as vm_config:
            product = host.Product(str(vm_config), evidence)
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
        if signed:
            report['guestOwnershipSha256'] = digest(require_material_file(evidence, 'session.json'))
        guest = session+'/'+(runtime_probe.APP_PHASE_DIRECTORY if signed else 'products phase 1E.5')
        vm.remote('umask 077; /bin/mkdir '+q(guest), timeout=10)
        product.upload([(args.app, prefix)], guest)
        guest_inventory(vm, guest, expected, scratch=evidence)
        app = guest+'/'+prefix
        verify = ['/usr/bin/codesign', '--verify', '--strict']

        def verify_app_signature():
            vm.remote(shlex.join([*verify, '--deep', '--all-architectures', app]), timeout=30)
            if signed:
                for architecture, requirement in runtime_probe.app_requirements(info):
                    scope = ['--architecture', architecture] if architecture else ['--all-architectures']
                    vm.remote(shlex.join([*verify, *scope, '-R='+requirement, app]), timeout=30)

        verify_app_signature()
        cwd = guest+'/runtime workspace'
        vm.remote('/bin/mkdir '+q(cwd), timeout=10)
        fixture = cwd+'/'+(runtime_probe.APP_FIXTURE if signed else 'meshchan-1d3-package')
        observer, library = None, None
        seen_pids = set()
        if signed:
            product.upload([(local_probe, local_probe.name)], cwd)
            observer = cwd+'/'+local_probe.name
            library = app+'/'+runtime_probe.APP_SQLITE

            def check_observer():
                vm.remote('test "$(/usr/bin/shasum -a 256 < '+q(observer)+')" = '
                          +q(probe_sha+'  -'), timeout=10)

            check_observer()
            sqlite_device, sqlite_inode = map(int, vm.remote(
                '/usr/bin/stat -f "%d:%i" '+q(library), capture_output=True, text=True,
                timeout=10).stdout.strip().split(':'))
            report.update(guestSigningIdentity=info['signature']['identity'], guestObserverTransfer='PASS')
        report.update(guestApp=redacted(app), guestInventoryBefore='PASS', guestSignature='PASS')

        for mode in ('write', 'read'):
            argv = [app+'/Contents/MacOS/Meshchan', '--meshchan-runtime='+mode,
                    '--data-dir='+fixture, '--runtime-exit']
            base = cwd+'/'+mode
            product.job(runtime_command(argv, cwd, base, observer, library))

            def read(suffix, *, binary=False):
                return vm.remote('/bin/cat '+q(base+suffix), capture_output=True,
                                 text=not binary, timeout=10).stdout

            wrapper_pid, exit_code = int(read('.pid')), int(read('.exit'))
            stdout, stderr = read('.stdout'), read('.stderr')
            row = {'argv': list(map(redacted, argv)), 'cwd': redacted(cwd),
                   'stdout': redacted(stdout), 'stderr': redacted(stderr), 'exitCode': exit_code}
            report['processes'].append(row)
            if signed:
                row['observerPid'] = wrapper_pid
            else:
                row['pid'] = wrapper_pid
            build.write(receipt, report)
            observed = None
            pid = wrapper_pid
            if signed:
                observation = read('.image.json', binary=True)
                (evidence/(mode+'-image.json')).write_bytes(observation)
                observed = runtime_probe.image_report(
                    observation, argv[0], library, expected[runtime_probe.APP_EXECUTABLE]['sha256'],
                    expected[runtime_probe.APP_SQLITE]['sha256'], exit_code, observer_pid=wrapper_pid)
                pid = observed['pid']
                if {pid, wrapper_pid} & seen_pids:
                    raise ValueError('Guest mapping receipt did not identify a fresh App child')
                require_absent_pid(vm, wrapper_pid)
                if (observed['mapping']['device'], observed['mapping']['inode']) != (
                        sqlite_device & 0xFFFFFFFF, sqlite_inode):
                    raise ValueError('Guest SQLite mapping did not match the transferred file vnode')
                seen_pids.update((pid, wrapper_pid))
            row['pid'] = pid
            require_absent_pid(vm, pid)
            if signed:
                row['sqliteMapping'] = {**observed, 'library': redacted(library),
                                        'executable': redacted(argv[0])}
                row['sqliteLoadedFrom'] = redacted(library)
            else:
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
            if signed:
                runtime_probe.validate_app_shutdown(runtime[0], shutdown[0], mode)
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
        draft = report['processes'][1]['draft']
        if signed:
            database_bytes = data.read_bytes()
            report['storedDrafts'] = runtime_probe.validate_database(
                database_bytes, draft, runtime_probe.APP_TITLE, runtime_probe.APP_BODY)
            report['guestDatabaseSha256'] = build.sha(database_bytes)
            check_observer()
            report['guestObserverAfter'] = 'PASS'
            verify_app_signature()
            report['guestSignatureAfter'] = 'PASS'
        else:
            with closing(sqlite3.connect(data.as_uri()+'?mode=ro&immutable=1', uri=True)) as connection:
                drafts = connection.execute('select id, revision from stored_drafts').fetchall()
                integrity = connection.execute('pragma quick_check').fetchall()
            if drafts != [(draft['id'], draft['revision'])] or integrity != [('ok',)]:
                raise ValueError('Guest SQLite file did not retain the closed draft')
            report['guestDatabaseSha256'] = digest(data)
        guest_inventory(vm, guest, expected, scratch=evidence)
        report['guestInventoryAfter'] = 'PASS'
        check_payload(args.app, expected)
    except BaseException as error:
        report['status'] = 'FAIL'
        report['error'] = guest_error(error)
        # The parent can reach its local kill deadline while the guest still
        # owns cleanup. Preserve the primary failure before waiting on it.
        build.write(receipt, report)
        raise ValueError(report['error']) from None
    finally:
        try:
            finish_and_record_guest()
        except KeyboardInterrupt as error:
            with build.DeferredInterrupts():
                report.update(status='FAIL', cleanupError='Interrupted while finishing owned guest executor ('
                              +guest_error(error)+')')
                build.write(receipt, report)
                # The finish marker is idempotent in the attested run. Retry
                # that cleanup without starting another executor or App.
                try:
                    finish_and_record_guest()
                except (OSError, ValueError, subprocess.SubprocessError) as retry_error:
                    report['cleanupError'] += ('\nCould not confirm owned guest executor shutdown ('
                                               +guest_error(retry_error)+')')
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            report.update(status='FAIL', cleanupError='Could not confirm owned guest executor shutdown ('
                          +guest_error(error)+')')
        finally:
            build.write(receipt, report)
        if 'cleanupError' in report:
            details = [report[key] for key in ('error', 'cleanupError') if key in report]
            raise ValueError('\n'.join(details)) from None
    if report.get('guestLockReleased') is not True:
        report.update(status='FAIL', error='No completed owned guest executor and lock release')
        build.write(receipt, report)
        raise ValueError(report['error'])
    report['status'] = 'PASS'
    build.write(receipt, report)
    result = {'status': 'PASS', 'guestRun': report['guestRun']}
    if signed:
        result.update(receiptSha256=build.sha(build.encoded(report)),
                      signingProfile=info_binding['signingProfile'])
    print(json.dumps(result))


def interrupted(signum, _frame):
    raise KeyboardInterrupt(f'Interrupted by signal {signum}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('config', 'app', 'evidence'):
        parser.add_argument('--'+name, type=Path, required=True)
    info = parser.add_mutually_exclusive_group(required=True)
    info.add_argument('--package-info', type=Path)
    info.add_argument('--signed-info', type=Path)
    parser.add_argument('--expected-signed-info-sha256')
    args = parser.parse_args()
    if (args.signed_info is None) != (args.expected_signed_info_sha256 is None):
        parser.error('Signed product information and its expected SHA-256 must be specified together')
    signal.signal(signal.SIGTERM, interrupted)
    try:
        run(args)
    except (Exception, KeyboardInterrupt) as error:
        print('ERROR: '+str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
