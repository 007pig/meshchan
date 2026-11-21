#!/usr/bin/env python3
"""Collect bounded macOS engineering-install acceptance evidence."""
import argparse
from contextlib import contextmanager
from datetime import UTC, datetime
import fcntl
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import ipaddress
from itertools import count
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
from types import SimpleNamespace
from urllib.parse import quote

import installed_release_beta as beta
import installed_release_checks as checks
import installed_release_files as files
import installed_release_inputs as inputs
import installed_release_workflow as workflow
import package_release_vm as guest
from package_release import verify_report_fields
from release_materials import digest, encoded
from release_package_archive import directory_fd, open_archive
from release_signing import load_policy, policy_object
from retain_release import publish_seal

ROOT = guest.ROOT
DMG_NAME = inputs.DMG_FILENAME
DMG_SIZE = inputs.DMG_SIZE
DMG_SHA = inputs.DMG_SHA256
SUMS_SHA = inputs.CHECKSUM_SHA256
SUMS_SIZE = 115
VOLUME = 'Meshchan 0.1.0-rc.1 build 8'
CANDIDATE = 'Meshchan-0.1.0-rc.1-macos-arm64'
PREVIOUS_RC_RUN = '20261121T142918Z-product-56504'
EXECUTABLE = 'Contents/MacOS/Meshchan'
SQLITE = 'Contents/Frameworks/sqlite3.framework/Versions/A/sqlite3'
# From the independently pinned Build 8 signed-product-info.json. The full
# install check also checks these launch/runtime pins against that manifest.
APP_FILE_PINS = {
    EXECUTABLE: 'cb62c913631b974c28bc756defb0478a947bdf13756b8ff6ec95dcffe29cfc91',
    SQLITE: '78592666674972ed235cb50387acf37905d9017d8dd6dc35d2b83b62a83fb60f',
}
APP_CODE_PINS = {
    'arm64': 'a7caf7391c09f5a28123e7f473a41dde9278ec54',
    'x86_64': 'a0c9dfc633088c28b36f67ee3af0ba7b86433a95',
}
CLI_FILE_PINS = {
    'bin/meshctl': '0805f4657cc9d751941d71c4a8eae7de423dee760c3564946c9f348c53ecf463',
    'lib/liblibserialport_plus.dylib': 'bc2c88312a762642fea3a9fcd1d4152838662d07d5970ccda556623bd920eb53',
    'lib/libsqlite3.dylib': 'a735fd46f627cc0677ce674bf0dee8d4e325547f94ba1e5764bdbab6a6b7a003',
}
CLI = 'bin/meshctl'
CLI_SQLITE = 'lib/libsqlite3.dylib'
APP_IDENTIFIER = 'org.meshchan.meshchan'
BASELINE = 'diskimages-before-download.plist'
DOWNLOAD_GUI_ACCESS = 'Guest GUI executor with native Downloads permission'
SYSTEM_PROTECTION = {'sip': 'enabled', 'gatekeeper': 'enabled'}
PROTECTION_CHECK = r'''export LC_ALL=C
sip=$(/usr/bin/csrutil status)
assessment=$(/usr/sbin/spctl --status)
printf 'SIP\t%s\nGatekeeper\t%s\n' "$sip" "$assessment"'''
RUN = re.compile(r'[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}')
MESHCHAN_COMMAND = re.compile(
    r'^[ \t]*(\d+)[ \t]+(/[^\n]+/Meshchan\.app/Contents/MacOS/Meshchan(?: [^\n]*)?)$',
    re.MULTILINE)
SYSTEM_MAPPED_DATA = re.compile(
    r'(?:/Library/Caches/com\.apple\.iconservices\.store/[0-9A-F-]{36}\.isdata'
    r'|/private/var/db/analyticsd/events\.allowlist'
    r'|/private/var/db/diagnostics/logd/\.plist-cache\.[a-zA-Z0-9]+'
    r'|/private/var/folders/[a-z0-9_/]+/0/com\.apple\.LaunchServices\.dv/'
    r'com\.apple\.LaunchServices-[0-9]+-v[0-9]+\.csstore'
    r'|/private/var/folders/[a-z0-9_/]+/C/com\.apple\.iconservices/store\.index'
    r'|/private/var/folders/[a-z0-9_/]+/C/org\.meshchan\.meshchan/com\.apple\.metal/'
    r'[0-9_]+/(?:functions|libraries)\.data'
    r'|/usr/share/icu/icudt[0-9]+l\.dat)')
q = shlex.quote


def now():
    return datetime.now(UTC).isoformat(timespec='seconds')


def write_new(path, data):
    # Publish a complete receipt exclusively. An interrupted serialization
    # must not reserve the canonical name with incomplete JSON.
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.receipt-',
                                     mode='w', encoding='utf-8') as file:
        json.dump(data, file, indent=2)
        file.write('\n')
        file.flush()
        os.link(file.name, path)


def read_record(path):
    with path.open(encoding='utf-8') as file:
        return json.load(file, object_pairs_hook=policy_object)


def bound_record(path):
    raw = path.read_bytes()
    return json.loads(raw, object_pairs_hook=policy_object), hashlib.sha256(raw).hexdigest()


def require_fresh(path):
    if os.path.lexists(path):
        raise FileExistsError(f'Case already has {path.name}; use a new run to repeat it')


@contextmanager
def keep_case_failure(evidence, action, run):
    try:
        yield
    except (Exception, KeyboardInterrupt) as error:
        if isinstance(error, KeyboardInterrupt):
            status = 'INTERRUPTED'
        elif isinstance(error, (OSError, subprocess.TimeoutExpired)):
            status = 'BLOCKED'
        else:
            status = 'FAIL'
        report = {'action': action, 'run': run, 'status': status, 'time': now(),
                  'errorType': type(error).__name__}
        if isinstance(error, subprocess.CalledProcessError):
            report['commandExitCode'] = error.returncode
        try:
            for attempt in count(1):
                try:
                    write_new(evidence/f'{action}-failure-{attempt}.json', report)
                except FileExistsError:
                    continue
                break
        except OSError as write_error:
            error.add_note(f'Could not retain the {action} failure receipt: {type(write_error).__name__}')
        raise


def is_network_retry(receipt, label):
    if not os.path.lexists(receipt):
        return False
    if receipt.is_symlink() or not receipt.is_file():
        raise ValueError('Expected a regular network receipt')
    previous = read_record(receipt)
    verify_report_fields(previous, {'label': label}, 'Prior network observation')
    if previous.get('status') != 'UNVERIFIED' or checks.network_status(previous) != 'UNVERIFIED':
        require_fresh(receipt)
    return True


def preserve_network_attempt(receipt):
    for attempt in count(1):
        archive = receipt.with_name(f'{receipt.stem}-attempt-{attempt}{receipt.suffix}')
        try:
            os.link(receipt, archive, follow_symlinks=False)
        except FileExistsError:
            continue
        receipt.unlink()
        return


@contextmanager
def case_lock(evidence):
    """Keep concurrent commands from observing or mutating a half-written case."""
    if evidence.resolve(strict=True) != evidence.absolute():
        raise ValueError('Expected a canonical installation evidence directory')
    flags = os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK
    with os.fdopen(os.open(evidence/'.case.lock', flags, 0o600),
                   'rb') as lock:
        stamp = os.fstat(lock.fileno())
        if not stat.S_ISREG(stamp.st_mode) or stamp.st_nlink != 1 or stamp.st_uid != os.getuid():
            raise ValueError('Expected an owned installation case lock')
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError('Another command is using this installation case') from error
        yield


@contextmanager
def checked_asset(path, expected_sha, expected_size):
    """Serve a private copy of exactly the bytes that were verified."""
    if not path.is_absolute() or path.resolve(strict=True) != path:
        raise ValueError('Asset must be an absolute regular path without symlinks')
    with open_archive(path) as source, tempfile.TemporaryFile() as snapshot:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size != expected_size:
            raise ValueError(f'Wrong size or type for {path.name}')
        remaining = expected_size
        checksum = hashlib.sha256()
        while remaining and (block := source.read(min(1024 * 1024, remaining))):
            snapshot.write(block)
            checksum.update(block)
            remaining -= len(block)
        if remaining or source.read(1) or checksum.hexdigest() != expected_sha:
            raise ValueError(f'Asset differs from the pinned size or SHA-256: {path.name}')
        snapshot.seek(0)
        yield snapshot


def lan_address(value):
    address = ipaddress.IPv4Address(value)
    if not any(address in ipaddress.IPv4Network(network) for network in
               ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')):
        raise ValueError('Provide a private host or guest IPv4 address')
    return str(address)


def serve(assets, bind, client, port):
    bind, client = lan_address(bind), lan_address(client)
    if bind == client:
        raise ValueError('Use distinct host and guest addresses')
    with checked_asset(assets / DMG_NAME, DMG_SHA, DMG_SIZE) as dmg, \
         checked_asset(assets / 'SHA256SUMS', SUMS_SHA, SUMS_SIZE) as sums:
        routes = {f'/{quote(DMG_NAME)}': (dmg, DMG_NAME, DMG_SIZE),
                  '/SHA256SUMS': (sums, 'SHA256SUMS', SUMS_SIZE)}

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                route = routes.get(self.path)
                if self.client_address[0] != client or route is None:
                    self.send_error(404)
                    return
                stream, name, size = route
                self.send_response(200)
                self.send_header('Content-Type', 'application/octet-stream')
                self.send_header('Content-Disposition', f'attachment; filename="{name}"')
                self.send_header('Content-Length', str(size))
                self.send_header('Cache-Control', 'no-store')
                self.end_headers()
                try:
                    stream.seek(0)
                    shutil.copyfileobj(stream, self.wfile)
                except OSError as error:
                    print(json.dumps({'request': self.path, 'time': now(), 'result': 'INTERRUPTED',
                                      'error': type(error).__name__}), flush=True)
                else:
                    print(json.dumps({'request': self.path, 'time': now(), 'result': 'SENT',
                                      'client': client, 'size': size}), flush=True)

            def setup(self):
                self.request.settimeout(60)
                super().setup()

        with HTTPServer((bind, port), Handler) as server:
            print(json.dumps({'url': f'http://{bind}:{server.server_port}/{quote(DMG_NAME)}',
                              'allowedClient': client, 'time': now()}), flush=True)
            server.serve_forever()


def path_layout(user, token):
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_-]*', user) or not RUN.fullmatch(token):
        raise ValueError('Invalid test user or run ID')
    home = PurePosixPath('/Users', user)
    product = home / 'Library/Application Support/meshchan-engineering' / token
    return {
        'home': str(home),
        'app': str(home / 'Applications/Meshchan.app'),
        'data': str(home / guest.DEFAULT_DATA_SUBDIR.as_posix()),
        'product': str(product),
        'cli': str(product / CANDIDATE / 'meshctl/bin/meshctl'),
        'download': str(home / 'Downloads' / DMG_NAME),
    }


def output(vm, command, *, timeout=20):
    return vm.remote(command, capture_output=True, text=True, timeout=timeout).stdout


def verify_system_protection(inventory):
    if not isinstance(inventory, str):
        raise ValueError('Missing guest system protection inventory')
    lines = inventory.splitlines()
    for name, expected in (('SIP', 'System Integrity Protection status: enabled.'),
                           ('Gatekeeper', 'assessments enabled')):
        prefix = name+'\t'
        if [line for line in lines if line.startswith(prefix)] != [prefix+expected]:
            raise ValueError(f'Guest must report enabled {name} for the acceptance case')
    return SYSTEM_PROTECTION.copy()


def measure_system_protection(vm):
    return verify_system_protection(output(vm, 'set -e\n'+PROTECTION_CHECK))


def verify_preflight_environment(inventory):
    verify_system_protection(inventory)
    os_rows = [line.split('\t') for line in inventory.splitlines() if line.startswith('OS\t')]
    if (len(os_rows) != 1 or len(os_rows[0]) != 4 or not all(os_rows[0][1:3])
            or os_rows[0][-1] != 'arm64'):
        raise ValueError('Expected a verified macOS arm64 guest and OS build')


def preflight(vm, token):
    layout = path_layout(vm.c['user'], token)
    paths = [layout[key] for key in ('app', 'data', 'product', 'download')]
    paths.extend(['/Applications/Meshchan.app', str(PurePosixPath(layout['download']).with_suffix('.dmg.download'))])
    paths = shlex.join(paths)
    script = f'''set -e
test "$(/usr/bin/id -un)" = {q(vm.c['user'])}
test "$(/usr/bin/dscl . -read /Users/{vm.c['user']} NFSHomeDirectory)" = {q('NFSHomeDirectory: ' + layout['home'])}
test "$(/usr/sbin/ioreg -a -n Root -d1 | /usr/bin/plutil -extract IOConsoleLocked raw -o - -)" = false
os_version=$(/usr/bin/sw_vers -productVersion)
os_build=$(/usr/bin/sw_vers -buildVersion)
architecture=$(/usr/bin/uname -m)
printf 'OS\t%s\t%s\t%s\n' "$os_version" "$os_build" "$architecture"
{PROTECTION_CHECK}
for item in {paths}; do
    state=absent
    if test -e "$item" || test -L "$item"; then state=present; fi
    printf 'target\t%s\t%s\n' "$state" "$item"
done
for item in /opt/homebrew /usr/local/bin/brew /Applications/Xcode.app /Library/Developer/CommandLineTools "$HOME/.pub-cache" "$HOME/.dart-tool" "$HOME/flutter" "$HOME/Development/flutter"; do
    state=absent
    if test -e "$item" || test -L "$item"; then state=present; fi
    printf 'developer\t%s\t%s\n' "$state" "$item"
done
echo '--- PATH and tools ---'
printf '%s\n' "$PATH"
/usr/bin/which flutter dart brew python3 || :
echo '--- mounts ---'
/sbin/mount
echo '--- existing Meshchan processes ---'
/bin/ps -ww -axo pid=,command= | /usr/bin/grep -E '^[[:space:]]*[0-9]+[[:space:]]+/.*Meshchan[.]app/Contents/MacOS/Meshchan( |$)' || :
if test -d {q(vm.runpath(PREVIOUS_RC_RUN))}; then
    printf 'priorRC\t%s\n' {q(PREVIOUS_RC_RUN)}
fi
echo '--- Safari ---'
/usr/bin/defaults read /Applications/Safari.app/Contents/Info CFBundleShortVersionString
/usr/bin/defaults read /Applications/Safari.app/Contents/Info CFBundleVersion
'''
    report = output(vm, script)
    verify_preflight_environment(report)
    targets = {}
    for line in report.splitlines():
        if line.startswith('target\t'):
            _, status, path = line.split('\t')
            targets[path] = status
    if set(targets) != set(shlex.split(paths)) or any(state not in ('absent', 'present') for state in targets.values()):
        raise ValueError('Incomplete guest path inventory')
    exposed = 'priorRC\t' + PREVIOUS_RC_RUN in report.splitlines()
    return {'formatVersion': 1, 'run': token, 'createdAt': now(), 'modelVerifiedBySsh': True,
            'guestUuid': vm.c['uuid'], 'consoleUser': vm.c['user'], 'paths': layout,
            'targets': targets, 'firstExposure': 'PREVIOUSLY_EXPOSED' if exposed else 'UNVERIFIED',
            'inventory': report}


def checked_case(vm, token, evidence):
    record = read_record(evidence/'preflight.json')
    layout = path_layout(vm.c['user'], token)
    verify_report_fields(record, {'formatVersion': 1, 'run': token, 'modelVerifiedBySsh': True,
                                  'guestUuid': vm.c['uuid'], 'consoleUser': vm.c['user'],
                                  'paths': layout}, 'Installation case')
    verify_preflight_environment(record.get('inventory'))
    for key in ('app', 'data', 'product', 'download'):
        if record['targets'].get(layout[key]) != 'absent':
            raise ValueError(f'Guest {key} target was not vacant at case preflight')
    partial = str(PurePosixPath(layout['download']).with_suffix('.dmg.download'))
    if record['targets'].get(partial) != 'absent':
        raise ValueError('A partial Safari download was present at case preflight')
    if record['targets'].get('/Applications/Meshchan.app') != 'absent':
        raise ValueError('Global Meshchan install was present at case preflight')
    return layout


def require_case_download_window(preflight_time, baseline_time, started_at, finished_at, collected_at):
    case, baseline, start, end, observation = map(
        files.parse_time, (preflight_time, baseline_time, started_at, finished_at, collected_at))
    if not case <= baseline <= start <= end <= observation:
        raise ValueError('Download timestamps do not belong to this preflight and mount baseline')


def check_download_timing(evidence, baseline, started_at, finished_at):
    require_case_download_window(read_record(evidence/'preflight.json')['createdAt'],
                                 baseline['capturedAt'], started_at, finished_at, now())


def record_baseline(vm, layout, evidence):
    require_fresh(evidence/'mount-baseline.json')
    # This command runs after preflight and immediately before exposure.
    download = PurePosixPath(layout['download'])
    paths = (download, download.with_suffix('.dmg.download'))
    script = '\n'.join(f'test ! -e {q(str(item))} && test ! -L {q(str(item))} || exit 1'
                       for item in paths)
    raw = output(vm, script+'\n/usr/bin/hdiutil info -plist')
    snapshot = files.parse_mount_snapshot(raw)
    if any(image.path == download for image in snapshot.images):
        raise ValueError('The expected Safari download was already mounted')
    return {'capturedAt': now(), 'sha256': hashlib.sha256(raw.encode('utf-8')).hexdigest(),
            'diskImagesPlist': raw}


def read_baseline(evidence, alternate=None):
    receipt = read_record(evidence/'mount-baseline.json')
    if 'diskImagesPlist' in receipt:
        raw = receipt['diskImagesPlist']
        if type(raw) is not str:
            raise ValueError('Expected the native disk-image inventory in the mount baseline')
        original = raw.encode('utf-8')
    else:
        original = (evidence/BASELINE).read_bytes()
    if alternate is not None and alternate.read_bytes() != original:
        raise ValueError('Alternate before snapshot differs from the captured case baseline')
    verify_report_fields(receipt, {'sha256': hashlib.sha256(original).hexdigest()}, 'Case mount baseline')
    return files.parse_mount_snapshot(original.decode('utf-8')), receipt


def product_executor(config, state):
    if state.is_symlink():
        raise ValueError('Expected an owned case executor directory')
    product = guest.load('installed_release_executor', 'apps/meshchan_app/tool/macos_vm/host.py').Product
    session = product(config, state)
    guest.require_ready_connection(session.vm)
    return session


def launch_executor(product):
    launch = product.out/'launch.json'
    if os.path.lexists(launch):
        # An earlier SSH call may have submitted the launch without receiving
        # its response. Attest that recorded run before considering it started.
        executor_session(product)
        return {'run': product.state['run'], 'status': 'RUNNING'}
    lock = q(product.vm.root+'/active.lock')
    product.vm.remote(f'test ! -e {lock} && test ! -L {lock}', timeout=10)
    runner = ROOT/guest.PRODUCT_RUNNER
    product.upload([(runner, 'product.sh')], product.vm.root)
    session = guest.guest_session(product.vm)
    write_new(launch, {'guestSession': session, 'time': now()})
    guest.start_guest(product.vm, session)
    if not guest.record_guest_run(product, session, timeout=12):
        raise ValueError(f'Guest executor did not bind; see {launch}')
    return {'run': product.state['run'], 'status': 'RUNNING'}


def executor_identity(product):
    session = read_record(product.out/'launch.json')['guestSession']
    if not re.fullmatch(re.escape(product.vm.root)+r'/package\.[A-Za-z0-9]{8}', session):
        raise ValueError('Invalid guest executor session path')
    if 'run' not in product.state and not guest.record_guest_run(product, session, timeout=2):
        raise ValueError('The recorded guest executor has not bound to this case')
    expected = {key: product.state[key] for key in ('run', 'lockIdentity')}
    return session, expected


def executor_session(product):
    session, expected = executor_identity(product)
    if guest.owned_guest_run(product.vm, session) != expected:
        raise ValueError('Guest executor is no longer the owned case run')
    return session


def finish_executor(product, *, expected_run=None):
    session, expected = executor_identity(product)
    if expected_run is not None:
        verify_report_fields(expected, {'run': expected_run}, 'Download executor ownership')
    current = guest.owned_guest_run(product.vm, session)
    if current is None:
        # The previous finish request may have completed after its SSH
        # response was lost. Read the original run's exit and lock receipts.
        exit_code = guest.confirm_guest_exit(product)
    elif current == expected:
        exit_code = guest.finish_guest(product, session)
    else:
        raise ValueError('Guest executor is no longer the owned case run')
    return {'run': expected['run'], 'status': 'PASS', 'exitCode': exit_code}


def download_executor_run(download):
    if 'observationSession' not in download:
        return None
    observation = download['observationSession']
    if type(observation) is not dict or observation.get('access') != DOWNLOAD_GUI_ACCESS:
        raise ValueError('Expected the recorded GUI download observation session')
    runner = observation.get('runner')
    if type(runner) is not str or not RUN.fullmatch(runner):
        raise ValueError('Invalid GUI download executor run')
    return runner


def require_finished_download_executor(evidence, download):
    runner = download_executor_run(download)
    started = evidence/'executor-start.json'
    launch = evidence/'executor/launch.json'
    if runner is None and not os.path.lexists(started) and not os.path.lexists(launch):
        return
    try:
        finished = read_record(evidence/'executor-finish.json')
    except FileNotFoundError as error:
        raise ValueError('Run executor-finish for the case download before continuing') from error
    if os.path.lexists(started):
        start = read_record(started)
        if runner is None:
            runner = start['run']
        verify_report_fields(start, {'run': runner, 'status': 'RUNNING'}, 'Download executor start')
    elif runner is None:
        runner = read_record(evidence/'executor/session.json')['run']
    if type(runner) is not str or not RUN.fullmatch(runner):
        raise ValueError('Invalid GUI download executor run')
    verify_report_fields(finished, {'run': runner, 'status': 'PASS', 'exitCode': 0}, 'Download executor finish')


class DownloadReader:
    """Route only the download verifier's read commands via the authorized GUI."""

    def __init__(self, executor):
        self.executor = executor

    def remote(self, command, *, capture_output, text, timeout):
        return SimpleNamespace(stdout=self.executor.job(command, timeout=timeout))


def verify_runtime_argv(pid, executable, command, uid, expected_uid):
    if type(pid) is not int or pid <= 1 or type(uid) is not int or uid != expected_uid:
        raise ValueError('Unexpected PID or guest process owner')
    allowed = re.fullmatch(re.escape(executable) + r'(?: -psn_[0-9]+_[0-9]+)?', command)
    if not allowed:
        raise ValueError('Expected exactly the installed ordinary App with no product arguments')


def live_vnodes(raw, pid):
    rows = raw.splitlines()
    if not rows or rows[0] != f'p{pid}' or sum(row.startswith('p') for row in rows) != 1:
        raise ValueError('Open-file observation does not identify one owned App process')
    entries = []
    current = None
    for row in rows[1:]:
        if row.startswith('f'):
            current = {'descriptor': row[1:]}
            entries.append(current)
        elif current is not None and row and row[0] in 'nDit':
            current[row[0]] = row[1:]
    return [entry for entry in entries if 'n' in entry]


def file_vnode(entry, stamp):
    if (entry.get('t') != 'REG' or int(entry.get('D', '0'), 16) != stamp['device']
            or int(entry.get('i', '0')) != stamp['inode']):
        raise ValueError('Live file vnode differs from the current installed file')


def runtime_observation(vm, layout, pid, *, pins=APP_FILE_PINS):
    if type(pid) is not int or pid <= 1:
        raise ValueError('Expected an observed installed App PID')
    app = PurePosixPath(layout['app'])
    executable, library = str(app/EXECUTABLE), str(app/SQLITE)
    active = output(vm, '/bin/ps -ww -axo pid=,command=')
    candidates = MESHCHAN_COMMAND.findall(active)
    if len(candidates) != 1 or candidates[0][0] != str(pid):
        raise ValueError('Expected one Meshchan process at the requested PID')
    command = candidates[0][1].removeprefix('/System/Volumes/Data')
    uid = int(output(vm, f'/bin/ps -p {pid} -o uid=').strip())
    expected_uid = int(output(vm, '/usr/bin/id -u').strip())
    verify_runtime_argv(pid, executable, command, uid, expected_uid)
    raw = output(vm, f'/usr/sbin/lsof -nP -a -p {pid} -FpcfnDit')
    entries = live_vnodes(raw, pid)
    database = layout['data'] + '/meshchan.sqlite'
    lock = layout['data'] + '/.meshchan.owner.lock'
    stamps = {}
    for path, pin in ((executable, pins[EXECUTABLE]), (library, pins[SQLITE]),
                      (database, None), (lock, None)):
        matches = [entry for entry in entries if entry['n'].removeprefix('/System/Volumes/Data') == path
                   and (entry['descriptor'] == 'txt') == (pin is not None)]
        if not matches:
            raise ValueError(f'Expected live App file is missing from the process: {path}')
        stamp = files.guest_file_stamp(vm, path)
        for match in matches:
            file_vnode(match, stamp)
        if pin is not None:
            stamp = verify_installed_file(vm, path, pin, stamp=stamp)
        stamps[path] = stamp
    mapped = {entry['n'].removeprefix('/System/Volumes/Data') for entry in entries
              if entry['descriptor'] == 'txt'}
    system_roots = ('/System/Library/', '/usr/lib/', '/Library/Apple/System/Library/')
    system_data = sorted(path for path in mapped if SYSTEM_MAPPED_DATA.fullmatch(path))
    external = sorted(path for path in mapped if not path.startswith((*system_roots, str(app)+'/'))
                      and path not in system_data)
    if external:
        raise ValueError('Unexpected non-system text mappings: ' + repr(external))
    marker = read_guest_marker(vm, layout['data'])
    verify_report_fields(marker, {'pid': pid}, 'Default-directory owner marker')
    return {'pid': pid, 'uid': uid, 'executable': executable, 'app': str(app),
            'dataDirectory': layout['data'], 'argv': command, 'ownerMarker': marker,
            'files': stamps, 'method': 'lsof text mappings and file vnodes', 'openFiles': raw,
            'systemMappedData': system_data,
            'time': now()}


def read_guest_marker(vm, data):
    path = PurePosixPath(data)/'.meshchan.owner.json'
    return json.loads(output(vm, '/bin/cat '+q(str(path))), object_pairs_hook=policy_object)


def checked_install(vm, layout, evidence, archive):
    admitted = inputs.verify_rc_inputs(archive)
    verify_product_pins(admitted.signed_info)
    return files.verify_installation(vm, encoded(admitted.image_manifest),
                                     inputs.CANDIDATE_PINS['image_payload'],
                                     layout['app'], layout['product'], scratch=evidence,
                                     policy=load_policy(ROOT/'tool/release_signing_policy.json'),
                                     signed_info=admitted.signed_info)


def verify_product_pins(signed_info):
    for root, pins in ((files.APP, APP_FILE_PINS), ('meshctl', CLI_FILE_PINS)):
        for relative, pin in pins.items():
            verify_report_fields(signed_info['payloadInventory'][f'{root}/{relative}'],
                                 {'sha256': pin}, 'Frozen runtime file')
    app, = (item for item in signed_info['signature']['items'] if item['path'] == files.APP)
    verify_report_fields(app, {'identifier': APP_IDENTIFIER}, 'Frozen App identity')
    verify_report_fields({arch: entry['cdhash'] for arch, entry in app['slices'].items()},
                         APP_CODE_PINS, 'Frozen App CodeDirectory hashes')
    if app['slices'].keys() != APP_CODE_PINS.keys():
        raise ValueError('Frozen App architecture set differs')


def verify_installed_file(vm, path, pin, *, stamp=None):
    if stamp is None:
        stamp = files.guest_file_stamp(vm, path)
    sha = files.remote_text(vm, ['/usr/bin/shasum', '-a', '256', path]).split()
    if not sha or sha[0] != pin or files.guest_file_stamp(vm, path) != stamp:
        raise ValueError(f'Installed file differs from the frozen candidate: {path}')
    return {**stamp, 'sha256': pin}


def verify_launch_app(vm, app):
    strict = ['/usr/bin/codesign', '--verify', '--deep', '--strict']
    files.remote_text(vm, [*strict, '--all-architectures', app])
    for arch, pin in APP_CODE_PINS.items():
        requirement = f'identifier "{APP_IDENTIFIER}" and cdhash H"{pin}"'
        files.remote_text(vm, [*strict, '--architecture', arch, '-R='+requirement, app])
    for relative, pin in APP_FILE_PINS.items():
        verify_installed_file(vm, str(PurePosixPath(app)/relative), pin)


def ordinary_open_command(app, session):
    stdout, stderr = (session+'/'+name for name in ('app.stdout', 'app.stderr'))
    launch = shlex.join(['/usr/bin/open', '--stdout', stdout, '--stderr', stderr, app])
    return f'''(
    result=0
    {launch} || result=$?
    printf '%s\\n' "$result" > {q(session+'/open-exit')}
) </dev/null > {q(session+'/open-log')} 2>&1 &'''


def require_verified_install_before(evidence, layout, mount_pin):
    try:
        installed = read_record(evidence/'install-before.json')
    except FileNotFoundError as error:
        raise ValueError('Run install --label before while the verified image is still mounted') from error
    verify_report_fields(installed, {'imageManifestSha256': inputs.CANDIDATE_PINS['image_payload'],
                                     'mountSha256': mount_pin, 'systemProtection': SYSTEM_PROTECTION},
                         'Installed image inventory')
    verify_report_fields(installed['layout'], {'app': layout['app'], 'cli': layout['cli'],
                                              'volumeMaterials': layout['product']},
                         'Installed paths')


def require_detached_case(evidence, layout):
    _, baseline = read_baseline(evidence)
    download = read_case_download(evidence, layout, baseline)
    require_finished_download_executor(evidence, download)
    mounted, mount_pin = read_case_mount(evidence, baseline['sha256'])
    verify_report_fields(mounted, {'download': download['file']}, 'Mounted download')
    verify_report_fields(mounted['attachment'], {'path': layout['download']}, 'Mounted download')
    require_verified_install_before(evidence, layout, mount_pin)
    detached = read_record(evidence/'detach.json')
    verify_report_fields(detached, {'status': 'PASS', 'mountSha256': mount_pin,
                                    'attachment': mounted['attachment'],
                                    'beforeSha256': mounted['beforeSha256']}, 'Case detach')
    return baseline


def require_unmounted(vm, layout):
    if any(str(item.path) == layout['download'] for item in files.mount_snapshot(vm).images):
        raise ValueError('Case download has been remounted')


def request_open(vm, layout, evidence, label):
    require_detached_case(evidence, layout)
    require_unmounted(vm, layout)
    record = evidence/('launch-'+label+'.json')
    require_fresh(record)
    require_launch_milestones(vm, layout, evidence, label)
    app = layout['app']
    if MESHCHAN_COMMAND.search(output(vm, '/bin/ps -ww -axo pid=,command=')):
        raise ValueError('A Meshchan App process is already present in this guest')
    verify_launch_app(vm, app)
    protection = measure_system_protection(vm)
    session = guest.guest_session(vm)
    # Preserve the session if the request stalls in a system dialog or SSH drops.
    write_new(record, {'status': 'REQUESTED', 'time': now(), 'app': app,
                       'guestSession': session, 'method': 'LaunchServices', 'arguments': [],
                       'systemProtection': protection})
    vm.remote(ordinary_open_command(app, session), timeout=10)


def read_launch(vm, evidence, label, app):
    launch, sha = bound_record(evidence/('launch-'+label+'.json'))
    verify_report_fields(launch, {'status': 'REQUESTED', 'method': 'LaunchServices', 'arguments': [],
                                  'app': app, 'systemProtection': SYSTEM_PROTECTION}, 'Ordinary launch receipt')
    session = launch['guestSession']
    if not re.fullmatch(re.escape(vm.root)+r'/package\.[A-Za-z0-9]{8}', session):
        raise ValueError('Unexpected guest launch log directory')
    return {'guestSession': session, 'launchSha256': sha}


def require_launch_streams(vm, runtime, session):
    entries = live_vnodes(runtime['openFiles'], runtime['pid'])
    for fd, filename in (('1', 'app.stdout'), ('2', 'app.stderr')):
        path = session+'/'+filename
        matches = [entry for entry in entries if entry['descriptor'] == fd
                   and entry['n'].removeprefix('/System/Volumes/Data') == path]
        if len(matches) != 1:
            raise ValueError(f'Installed App descriptor {fd} is outside the measured launch session')
        file_vnode(matches[0], files.guest_file_stamp(vm, path))


def observe_launched_runtime(vm, layout, evidence, label, pid):
    binding = read_launch(vm, evidence, label, layout['app'])
    session = binding['guestSession']
    log = session+'/open-exit'
    if output(vm, '/bin/cat '+q(log)).strip() != '0':
        raise ValueError('The requested ordinary LaunchServices command did not open successfully')
    runtime = runtime_observation(vm, layout, pid)
    require_launch_streams(vm, runtime, session)
    return {**runtime, **binding}


def capture_installed_close(vm, evidence, label):
    runtime, runtime_pin = bound_record(evidence/('runtime-'+label+'.json'))
    app = str(PurePosixPath('/Users', vm.c['user'], 'Applications', files.APP))
    binding = read_launch(vm, evidence, label, app)
    verify_report_fields(runtime, {'app': app, **binding}, 'Runtime launch binding')
    if label == 'initial':
        verify_case_cli_contention(evidence, runtime)
    return capture_shutdown(vm, runtime, {**binding, 'runtimeSha256': runtime_pin}, evidence/('closed-'+label))


def capture_shutdown(vm, runtime, binding, destination):
    pid = runtime['pid']
    if type(pid) is not int or pid <= 1:
        raise ValueError('Expected an observed installed App PID')
    expected = {'formatVersion': 1, 'status': 'PASS', 'pid': pid, **binding}
    if os.path.lexists(destination):
        report = read_shutdown_receipt(destination)
        verify_report_fields(report, expected, 'Archived App shutdown')
        verify_shutdown_snapshot(destination, report)
        return report
    session = binding['guestSession']
    guest.require_absent_pid(vm, pid)
    require_launch_streams(vm, runtime, session)
    lines = output(vm, '/bin/cat '+q(session+'/app.stdout')).splitlines()
    reports = [json.loads(line, object_pairs_hook=policy_object) for line in lines if line.startswith('{')]
    if len(reports) != 1:
        raise ValueError('Expected one normal shutdown report from the ordinary App launch')
    with tempfile.TemporaryDirectory(prefix='.shutdown-', dir=destination.parent) as temporary:
        stage = Path(temporary)
        captured = beta.capture_guest_closed(vm.remote, vm.c['user'], pid, reports[0], stage/'database')
        report = {**expected, 'capturedAt': now(), 'shutdown': reports[0], 'snapshot': captured}
        write_new(stage/'receipt.json', report)
        with directory_fd(destination.parent) as parent:
            publish_seal(stage, destination, parent, stage.lstat())
    return report


def read_shutdown_receipt(destination):
    path = destination/'receipt.json'
    beta.regular(path)
    return read_record(path)


def verify_shutdown_snapshot(destination, report):
    beta.verify_shutdown(report['shutdown'])
    if 'formatVersion' in report:
        verify_report_fields(report, {'formatVersion': 1}, 'Closed snapshot receipt')
        beta.same(report, read_shutdown_receipt(destination), 'Closed snapshot receipt')
        destination = destination/'database'
    return beta.verify_archived_snapshot(destination, report['snapshot'])


def verify_cli_files(vm, root, pins):
    return {name: verify_installed_file(vm, str(root/name), pin) for name, pin in pins.items()}


def invoke_cli(vm, cwd, executable, *args):
    command = ('/usr/bin/env', '-i', f'HOME={cwd}', 'PATH=/usr/bin:/bin:/usr/sbin:/sbin',
               'LANG=en_US.UTF-8', str(executable), *args)
    cmd = f'cd {q(cwd)} && ' + shlex.join(command)
    try:
        return vm.remote(cmd, capture_output=True, text=True, timeout=30)
    except subprocess.CalledProcessError as error:
        return error


def require_no_app(vm):
    if MESHCHAN_COMMAND.search(output(vm, '/bin/ps -ww -axo pid=,command=')):
        raise ValueError('Quit Meshchan normally before continuing')


def require_final_guest_state(vm, layout):
    require_unmounted(vm, layout)
    require_no_app(vm)
    beta.require_guest_storage_released(vm.remote, vm.c['user'])


def collect_cli(vm, evidence, layout, label):
    read_case_network(evidence, 'before')
    if label in ('before', 'mapping'):
        if os.path.lexists(evidence/'launch-initial.json'):
            raise ValueError(f'Collect CLI {label} evidence before requesting the initial measured launch')
    elif label == 'after':
        if os.path.lexists(evidence/'launch-reopen.json'):
            raise ValueError('Collect the settled CLI evidence before requesting the measured reopen')
        verify_case_close(vm, layout, evidence, 'initial')
    if label == 'busy':
        runtime = read_record(evidence/'runtime-initial.json')
        owner = observe_launched_runtime(vm, layout, evidence, 'initial', runtime['pid'])
        verify_report_fields(owner, {'ownerMarker': runtime['ownerMarker']}, 'Recorded App owner')
    else:
        require_no_app(vm)
    cli = PurePosixPath(layout['cli'])
    root = cli.parents[1]
    stamps = verify_cli_files(vm, root, CLI_FILE_PINS)
    if label == 'mapping':
        return checks.observe_cli_mapping(vm, cli, root/CLI_SQLITE, scratch=evidence,
                                          cli_stamp=stamps[CLI], library_stamp=stamps[CLI_SQLITE])
    if label == 'busy':
        result = invoke_cli(vm, layout['home'], cli, 'draft', 'list', '--json')
        beta.verify_busy(result)
        after = observe_launched_runtime(vm, layout, evidence, 'initial', owner['pid'])
        verify_report_fields(after, {'ownerMarker': owner['ownerMarker']}, 'App owner after CLI contention')
        return {'exitCode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr,
                'appPid': owner['pid'], 'ownerMarker': owner['ownerMarker']}
    return beta.capture_cli(lambda *args: invoke_cli(vm, layout['home'], cli, *args))


def collect_beta(args, vm, layout, evidence):
    admitted = beta.verify_beta(args.beta_evidence)
    product = PurePosixPath(layout['product'])
    cli_root = product.parent/'beta-reference'/product.name/'meshctl'
    if args.action == 'beta-stage':
        require_fresh(evidence/'download.json')
        return {**workflow.stage_beta(vm, layout, cli_root, admitted, evidence), 'betaInputs': admitted}

    stage = read_record(evidence/'beta-stage.json')
    cli = cli_root/CLI
    verify_report_fields(stage, {'status': 'PASS', 'app': layout['app'], 'cli': str(cli),
                                 'dataDirectory': layout['data']}, 'Owned Beta installation')
    if args.action == 'beta-observe':
        session = args.guest_session
        if not re.fullmatch(re.escape(vm.root)+r'/package\.[A-Za-z0-9]{8}', session):
            raise ValueError('Expected a fresh guest Beta log session')
        source = Path(admitted['app'])
        pins = {name: digest(source/name) for name in APP_FILE_PINS}
        report = runtime_observation(vm, layout, args.pid, pins=pins)
        require_launch_streams(vm, report, session)
        return {**report, 'guestSession': session}

    require_no_app(vm)
    active, runtime_pin = bound_record(evidence/'beta-observe.json')
    verify_report_fields(active, {'app': layout['app'], 'dataDirectory': layout['data']},
                         'Owned Beta runtime')
    session = active['guestSession']
    if not re.fullmatch(re.escape(vm.root)+r'/package\.[A-Za-z0-9]{8}', session):
        raise ValueError('Expected the recorded guest Beta log session')
    source = Path(admitted['cli'])
    pins = {name: digest(source/name) for name in CLI_FILE_PINS}
    verify_cli_files(vm, cli_root, pins)
    source_snapshot = evidence/'beta-source-closed'
    source_data = beta.verify_archived_snapshot(source_snapshot, stage['sourceClosedSnapshot'])
    report = capture_beta_close(vm, evidence, active, session, runtime_pin)
    beta.compare_sqlite(source_data['database'], report['snapshot']['database'])
    public = beta.capture_cli(lambda *args: invoke_cli(vm, layout['home'], cli, *args))
    reference = workflow.project_beta_reference(admitted, source_snapshot)
    beta.compare_cli(reference, public)
    return {**report, 'public': public}


def capture_beta_close(vm, evidence, active, session, runtime_pin):
    path = evidence/'beta-close.json'
    binding = {'guestSession': session, 'runtimeSha256': runtime_pin}
    expected = {'status': 'PASS', 'pid': active['pid'], **binding}
    destination = evidence/'closed-beta'
    if os.path.lexists(path):
        report = read_record(path)
        verify_report_fields(report, expected, 'Measured Beta shutdown')
        snapshot = verify_shutdown_snapshot(destination, report)
        return {**report, 'snapshot': snapshot}
    report = capture_shutdown(vm, active, binding, destination)
    write_new(path, report)
    return report


def read_case_network(evidence, label):
    report = read_record(evidence/f'network-{label}.json')
    verify_report_fields(report, {'label': label}, 'Case network observation')
    checks.require_offline(report)
    return files.parse_time(report['time'])


def verify_case_close(vm, layout, evidence, label):
    runtime, runtime_pin = bound_record(evidence/f'runtime-{label}.json')
    binding = read_launch(vm, evidence, label, layout['app'])
    verify_report_fields(runtime, {'app': layout['app'], 'dataDirectory': layout['data'], **binding},
                         'Case runtime launch binding')
    pid = runtime['pid']
    if type(pid) is not int or pid <= 1:
        raise ValueError('Expected an observed installed App PID')
    closed = read_record(evidence/f'closed-{label}.json')
    verify_report_fields(closed, {'status': 'PASS', 'pid': pid, **binding}, 'Case App shutdown')
    if 'formatVersion' in closed:
        verify_report_fields(closed, {'runtimeSha256': runtime_pin}, 'Case App shutdown')
    snapshot = verify_shutdown_snapshot(evidence/f'closed-{label}', closed)
    return runtime, closed, snapshot['database']


def verify_beta_baseline(layout, evidence):
    active, runtime_pin = bound_record(evidence/'beta-observe.json')
    verify_report_fields(active, {'app': layout['app'], 'dataDirectory': layout['data']}, 'Owned Beta runtime')
    baseline = read_record(evidence/'beta-baseline.json')
    verify_report_fields(baseline, {'status': 'PASS', 'pid': active['pid'],
                                    'guestSession': active['guestSession'], 'runtimeSha256': runtime_pin},
                         'Closed Beta baseline')
    stage = read_record(evidence/'beta-stage.json')
    verify_report_fields(stage, {'status': 'PASS', 'app': layout['app'],
                                 'dataDirectory': layout['data']}, 'Owned Beta installation')
    source = beta.verify_archived_snapshot(evidence/'beta-source-closed', stage['sourceClosedSnapshot'])
    beta.same(beta.DATABASE_PIN, source['files'][beta.DATABASE]['sha256'], 'Historical Beta database pin')
    closed = {key: value for key, value in baseline.items() if key != 'public'}
    snapshot = verify_shutdown_snapshot(evidence/'closed-beta', closed)
    beta.compare_sqlite(source['database'], snapshot['database'])
    return {**baseline, 'snapshot': snapshot}


def verify_case_cli_contention(evidence, initial_runtime):
    busy = read_record(evidence/'cli-busy.json')
    verify_report_fields(busy, {'appPid': initial_runtime['pid'],
                               'ownerMarker': initial_runtime['ownerMarker']}, 'CLI contention owner')
    beta.verify_busy(SimpleNamespace(returncode=busy['exitCode'], stdout=busy['stdout']))


def verify_case_cli_mapping(vm, layout, evidence):
    cli = PurePosixPath(layout['cli'])
    checks.verify_cli_mapping_receipt(evidence, read_record(evidence/'cli-mapping.json'),
                                      expected_cli=cli, expected_library=cli.parents[1]/CLI_SQLITE,
                                      cli_sha=CLI_FILE_PINS[CLI], library_sha=CLI_FILE_PINS[CLI_SQLITE],
                                      guest_root=vm.root)


def require_launch_milestones(vm, layout, evidence, label):
    read_case_network(evidence, 'before')
    if label == 'initial':
        baseline = read_record(evidence/'cli-before.json')
        if os.path.lexists(evidence/'beta-stage.json'):
            expected = verify_beta_baseline(layout, evidence)['public']
        else:
            expected = workflow.EMPTY_PUBLIC
        beta.same(expected, baseline, 'Installed CLI baseline before measuring the App')
        verify_case_cli_mapping(vm, layout, evidence)
    else:
        runtime, _, database = verify_case_close(vm, layout, evidence, 'initial')
        verify_case_cli_contention(evidence, runtime)
        projection = read_record(evidence/'cli-after.json')
        verify_report_fields(projection, {'schemaVersion': 1}, 'Settled CLI observation')
        beta.verify_history_export(projection, database)


def compare_case(args, vm, layout, evidence):
    return compare_evidence(vm, layout, evidence, title=args.title,
                            body=args.body_file.read_bytes().decode('utf-8'),
                            history_limit=args.history_limit, beta_case=args.beta)


def compare_evidence(vm, layout, evidence, *, title, body, history_limit, beta_case):
    baseline = require_detached_case(evidence, layout)
    before = read_case_network(evidence, 'before')
    if before > files.parse_time(baseline['capturedAt']):
        raise ValueError('The first network observation must precede the download baseline')
    after = read_case_network(evidence, 'after')
    initial_runtime, first, initial_db = verify_case_close(vm, layout, evidence, 'initial')
    reopen_runtime, reopen, reopened_db = verify_case_close(vm, layout, evidence, 'reopen')
    phases = (before, files.parse_time(initial_runtime['time']), files.parse_time(first['capturedAt']),
              files.parse_time(reopen_runtime['time']), files.parse_time(reopen['capturedAt']), after)
    if before >= after or first['guestSession'] == reopen['guestSession'] or list(phases) != sorted(phases):
        raise ValueError('Network and close evidence does not bracket two ordinary launches')
    verify_case_cli_contention(evidence, initial_runtime)
    verify_case_cli_mapping(vm, layout, evidence)
    reference = verify_beta_baseline(layout, evidence) if beta_case else None
    if reference is not None and files.parse_time(reference['capturedAt']) > phases[1]:
        raise ValueError('The closed Beta baseline must precede the installed RC run')
    if not beta_case and os.path.lexists(evidence/'beta-stage.json'):
        raise ValueError('Use --beta to compare a case that staged Beta')
    report = workflow.compare_business(
        read_record(evidence/'cli-before.json'), read_record(evidence/'cli-after.json'),
        initial_db, reopened_db,
        title=title, body=body, history_limit=history_limit, beta_baseline=reference)
    return {**report, 'baseline': 'beta' if beta_case else 'empty'}


def read_case_download(evidence, layout, baseline=None):
    download = read_record(evidence/'download.json')
    verify_report_fields(download, {'browser': 'Safari', 'sha256': DMG_SHA}, 'Case download')
    verify_report_fields(download['file'], {'path': layout['download'], 'size': DMG_SIZE}, 'Case download file')
    files.verify_safari_download_receipt(download)
    if baseline is None:
        _, baseline = read_baseline(evidence)
    check_download_timing(evidence, baseline, download['startedAt'], download['finishedAt'])
    return download


def read_case_mount(evidence, before_sha):
    mounted, pin = bound_record(evidence/'mount.json')
    verify_report_fields(mounted, {'volumeName': VOLUME, 'readOnly': True,
                                   'volumeUuid': inputs.DMG_VOLUME_UUID,
                                   'beforeSha256': before_sha}, 'Case image mount')
    return mounted, pin


def beta_input_identity(report):
    source = dict(report['source'])
    # The verifier recomputes this explanatory list from the pinned manifests.
    source.pop('nonbuildHandoffChanges', None)
    return {**report, 'source': source}


def recheck_beta_inputs(evidence):
    stage = read_record(evidence/'beta-stage.json')
    before = stage['betaInputs'] if 'betaInputs' in stage else read_record(evidence/'beta-inputs.json')
    fixture = Path(before['closedFixture'])
    if not fixture.is_absolute() or fixture.parts[-3:] != (
            'hardware', 'run-09-rf-restart', 'vm-source-closed-fixture'):
        raise ValueError('Unexpected path for the admitted historical Beta fixture')
    after = beta.verify_beta(fixture.parents[2])
    beta.same(beta_input_identity(before), beta_input_identity(after), 'Beta inputs before and after upgrade')
    return after


def verify_case_install(vm, layout, evidence, archive, label):
    protection = measure_system_protection(vm)
    if label == 'after':
        require_final_guest_state(vm, layout)
        comparison, comparison_pin = bound_record(evidence/'compare.json')
        if (type(comparison) is not dict or comparison.get('status') != 'PASS'
                or comparison.get('baseline') not in ('empty', 'beta')
                or type(comparison.get('newDraft')) is not dict
                or any(type(comparison['newDraft'].get(key)) is not str for key in ('title', 'body'))
                or type(comparison.get('historyLimitAfter')) is not int):
            raise ValueError('Expected a complete closed App and CLI comparison')
        draft = comparison['newDraft']
        actual = compare_evidence(vm, layout, evidence, title=draft['title'], body=draft['body'],
                                  history_limit=comparison['historyLimitAfter'],
                                  beta_case=comparison['baseline'] == 'beta')
        beta.same(comparison, actual, 'Closed App and CLI comparison')
        beta_inputs = {'betaInputs': recheck_beta_inputs(evidence)} if comparison['baseline'] == 'beta' else {}
        report = checked_install(vm, layout, evidence, archive)
        require_final_guest_state(vm, layout)
        protection = measure_system_protection(vm)
        return {**report, 'compareSha256': comparison_pin, 'systemProtection': protection, **beta_inputs,
                'finalGuestState': {'caseImageAttached': False, 'appRunning': False,
                                    'defaultDirectoryOwned': False}}

    before, baseline = read_baseline(evidence)
    download = read_case_download(evidence, layout, baseline)
    require_finished_download_executor(evidence, download)
    mounted, mount_pin = read_case_mount(evidence, baseline['sha256'])
    del mounted['beforeSha256']

    def require_live_mount():
        if files.observe_download_mount(vm, before, download, VOLUME) != mounted:
            raise ValueError('Selected guest mount changed during installed-file verification')

    require_live_mount()
    report = checked_install(vm, layout, evidence, archive)
    require_live_mount()
    return {**report, 'mountSha256': mount_pin, 'systemProtection': protection}


def collect_case(args, vm, layout, evidence):
    action = args.action
    if action == 'mount-baseline':
        read_case_network(evidence, 'before')
        return record_baseline(vm, layout, evidence)
    if action == 'network':
        if args.label == 'after':
            verify_report_fields(read_record(evidence/'closed-reopen.json'), {'status': 'PASS'},
                                 'Reopened App shutdown')
        return {**checks.observe_network(vm), 'label': args.label}
    if action.startswith('beta-'):
        return collect_beta(args, vm, layout, evidence)
    if action == 'compare':
        return compare_case(args, vm, layout, evidence)
    if action == 'download':
        _, baseline = read_baseline(evidence)
        check_download_timing(evidence, baseline, args.started_at, args.finished_at)
        reader = vm
        if args.gui:
            executor = product_executor(args.vm_config, evidence/'executor')
            checked_case(executor.vm, args.run, evidence)
            executor_session(executor)
            reader = DownloadReader(executor)
        report = files.verify_safari_download(
            reader, layout['download'], expected_asset={'filename': DMG_NAME, 'size': DMG_SIZE, 'sha256': DMG_SHA},
            url=args.url, started_at=args.started_at, finished_at=args.finished_at, user_home=layout['home'])
        if args.gui:
            report['observationSession'] = {'runner': executor.state['run'],
                                            'access': DOWNLOAD_GUI_ACCESS}
        return report
    if action in ('mount', 'detach'):
        before, baseline = read_baseline(evidence, args.before)
        download = read_case_download(evidence, layout, baseline)
        require_finished_download_executor(evidence, download)
        before_sha = baseline['sha256']
        if action == 'mount':
            if os.path.lexists(evidence/'beta-stage.json'):
                verify_beta_baseline(layout, evidence)
            report = files.observe_download_mount(vm, before, download, VOLUME)
        else:
            mounted, mount_pin = read_case_mount(evidence, before_sha)
            require_verified_install_before(evidence, layout, mount_pin)
            del mounted['beforeSha256']
            report = files.detach_download_mount(vm, before, download, mounted)
            report = {**report, 'mountSha256': mount_pin}
        return {**report, 'beforeSha256': before_sha}
    if action == 'install':
        return verify_case_install(vm, layout, evidence, args.archive, args.label)
    if action in ('executor-start', 'executor-finish'):
        expected_run = None
        if action == 'executor-start':
            require_fresh(evidence/'download.json')
            read_baseline(evidence)
        elif not args.abort:
            expected_run = download_executor_run(read_case_download(evidence, layout))
        executor = product_executor(args.vm_config, evidence/'executor')
        checked_case(executor.vm, args.run, evidence)
        if action == 'executor-start':
            return launch_executor(executor)
        report = finish_executor(executor, expected_run=expected_run)
        return {**report, 'status': 'ABORTED'} if args.abort else report
    require_detached_case(evidence, layout)
    require_unmounted(vm, layout)
    if action == 'cli':
        return collect_cli(vm, evidence, layout, args.label)
    if action == 'runtime':
        return observe_launched_runtime(vm, layout, evidence, args.label, args.pid)
    return capture_installed_close(vm, evidence, args.label)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    server = sub.add_parser('serve', help='Serve only the pinned DMG and original checksum to one guest')
    server.add_argument('--assets', type=Path, required=True)
    server.add_argument('--bind', required=True)
    server.add_argument('--client', required=True)
    server.add_argument('--port', type=int, default=0)
    status = sub.add_parser('inputs', help='Authenticate the frozen release or original Beta inputs')
    status.add_argument('--archive', type=Path, default=inputs.DEFAULT_ARCHIVE)
    status.add_argument('--beta-evidence', type=Path)
    status.add_argument('--output', type=Path, required=True)

    def vm_command(name, description):
        command = sub.add_parser(name, help=description)
        command.add_argument('--vm-config', type=Path, required=True)
        command.add_argument('--run', required=True)
        command.add_argument('--evidence', type=Path, required=True)
        return command

    vm_command('preflight', 'Capture identity and owned-path prerequisites before candidate exposure')
    vm_command('mount-baseline', 'Record the case disk-image inventory before Safari downloads the candidate')
    vm_command('executor-start', 'Start the case-owned GUI executor for scoped Downloads reads')
    finish = vm_command('executor-finish', 'Finish the case-owned GUI executor and check its exit')
    finish.add_argument('--abort', action='store_true',
                        help='Stop the owned executor and record that the acceptance case was abandoned')
    network = vm_command('network', 'Record direct IPv4/IPv6 offline evidence over the private SSH session')
    network.add_argument('--label', choices=('before', 'after'), required=True)
    cli = vm_command('cli', 'Verify ordinary installed CLI data, ownership contention, or its loaded SQLite')
    cli.add_argument('--label', choices=('before', 'busy', 'after', 'mapping'), required=True)
    for action, description in (('beta-stage', 'Stage only the authenticated Beta and closed data into vacant paths'),
                                ('beta-observe', 'Bind an ordinary logged Beta launch to its live process'),
                                ('beta-baseline', 'Verify the closed Beta default directory before replacement')):
        command = vm_command(action, description)
        command.add_argument('--beta-evidence', type=Path, required=True)
        if action == 'beta-observe':
            command.add_argument('--guest-session', required=True)
            command.add_argument('--pid', type=int, required=True)
    compare = vm_command('compare', 'Compare reopened App state and settled CLI and SQLite observations')
    compare.add_argument('--title', required=True)
    compare.add_argument('--body-file', type=Path, required=True)
    compare.add_argument('--history-limit', type=int, required=True)
    compare.add_argument('--beta', action='store_true', help='Compare against the recorded owned Beta baseline')
    download = vm_command('download', 'Verify an already observed Safari download')
    download.add_argument('--url', required=True)
    download.add_argument('--started-at', required=True)
    download.add_argument('--finished-at', required=True)
    download.add_argument('--gui', action='store_true',
                          help='Read through the case executor with the native scoped Downloads grant')
    mount = vm_command('mount', 'Bind a Finder-mounted image to the pinned Safari download')
    mount.add_argument('--before', type=Path, help='Optional copy of the case pre-download disk-image inventory')
    detach = vm_command('detach', 'Normally detach the exact attested Finder mount')
    detach.add_argument('--before', type=Path, help='Optional copy of the case pre-download disk-image inventory')
    install = vm_command('install', 'Verify existing installed files and signatures without launching')
    install.add_argument('--archive', type=Path, default=inputs.DEFAULT_ARCHIVE)
    install.add_argument('--label', choices=('before', 'after'), required=True)
    runtime = vm_command('runtime', 'Bind the live ordinary installed App, SQLite and default-directory owner')
    runtime.add_argument('--pid', type=int, required=True)
    runtime.add_argument('--label', choices=('initial', 'reopen'), required=True)
    request = vm_command('open-request', 'Request ordinary LaunchServices opening of the exact detached install')
    request.add_argument('--label', choices=('initial', 'reopen'), required=True)
    close = vm_command('closed', 'Check normal Quit and capture the closed default-directory SQLite snapshot')
    close.add_argument('--label', choices=('initial', 'reopen'), required=True)
    args = parser.parse_args()
    if args.action == 'serve':
        serve(args.assets, args.bind, args.client, args.port)
        return
    if args.action == 'inputs':
        report = (inputs.verify_rc_inputs(args.archive).report if args.beta_evidence is None
                  else beta.verify_beta(args.beta_evidence))
        write_new(args.output, report)
        return
    vm = guest.load('meshchan_installed_vm', '.agents/skills/macos-vm-gui-testing/scripts/vm.py').VM(args.vm_config)
    evidence = args.evidence.expanduser()
    if evidence.is_symlink():
        raise ValueError('Expected an owned installation evidence directory')
    evidence = evidence.resolve()
    if args.action == 'preflight':
        evidence.mkdir(mode=0o700, parents=False, exist_ok=False)
        try:
            record = preflight(vm, args.run)
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            write_new(evidence/'preflight-error.json', {'status': 'BLOCKED', 'time': now(),
                                                        'errorType': type(error).__name__})
            raise
        write_new(evidence/'preflight.json', record)
        return

    with case_lock(evidence):
        layout = checked_case(vm, args.run, evidence)
        finished = evidence/'executor-finish.json'
        if os.path.lexists(finished) and read_record(finished).get('status') == 'ABORTED':
            raise ValueError('This acceptance case was abandoned. Use a fresh case to repeat it.')
        if args.action == 'open-request':
            with keep_case_failure(evidence, 'launch-'+args.label, args.run):
                request_open(vm, layout, evidence, args.label)
            return
        label = getattr(args, 'label', None)
        key = args.action if label is None else f'{args.action}-{label}'
        receipt = evidence/(key+'.json')
        retry = args.action == 'network' and is_network_retry(receipt, label)
        if not retry:
            require_fresh(receipt)
        with keep_case_failure(evidence, key, args.run):
            report = collect_case(args, vm, layout, evidence)
            if retry:
                preserve_network_attempt(receipt)
            write_new(receipt, report)
        if args.action == 'network':
            if report.get('interrupted') is True:
                raise KeyboardInterrupt
            checks.require_offline(report)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
