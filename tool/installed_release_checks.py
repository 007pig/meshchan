"""Observe guest network reachability and an installed CLI's live SQLite image."""

from datetime import UTC, datetime
import ipaddress
import json
from pathlib import Path
import re
import shlex
import subprocess
import tempfile

import installed_release_files as files
import package_release_vm as guest
from package_release import verify_report_fields
from release_materials import controlled_environment, digest, encoded
from release_signing import policy_object
import release_signed_runtime as runtime


PUBLIC_ENDPOINTS = (
    (4, '1.1.1.1'), (4, '8.8.8.8'),
    (6, '2606:4700:4700::1111'), (6, '2001:4860:4860::8888'),
)
CURL_DETAILS = r'%{remote_ip}\n%{time_connect}\n%{http_code}\n'
CURL_RESULT = re.compile(r'([^\n]*)\n([0-9]+(?:\.[0-9]+)?)\n([0-9]{3})\n')
CLI_ARGUMENTS = ('draft', 'list', '--json')
DRAFT_ROW_FIELDS = {'id', 'title', 'bodyUtf8ByteLength', 'revision', 'createdAt', 'updatedAt'}
DRAFT_ID = re.compile(r'[0-9a-f]{32}')


def probe_url(family, address):
    return 'https://' + (f'[{address}]' if family == 6 else address) + '/'


def transport_output(value):
    # TimeoutExpired can return bytes even when the command requested text.
    return value.decode('utf-8', errors='replace') if isinstance(value, bytes) else value or ''


def network_command(vm, argv, *, timeout):
    try:
        result = vm.remote(shlex.join(argv), capture_output=True, text=True, timeout=timeout)
    except subprocess.CalledProcessError as error:
        result = error
    except subprocess.TimeoutExpired as error:
        return {'exitCode': None, 'stdout': transport_output(error.stdout), 'stderr': transport_output(error.stderr),
                'transportError': type(error).__name__}
    except (OSError, ValueError) as error:
        return {'exitCode': None, 'stdout': '', 'stderr': '', 'transportError': type(error).__name__}
    return {'exitCode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}


def probe_status(probe, family, address):
    if type(probe) is not dict or probe.get('target') != probe_url(family, address):
        return 'UNVERIFIED'
    code, stdout, stderr = (probe.get(key) for key in ('exitCode', 'stdout', 'stderr'))
    if type(code) is int and code == 0:
        return 'REACHABLE'
    if type(stdout) is not str:
        return 'UNVERIFIED'
    result = CURL_RESULT.fullmatch(stdout)
    if result is None:
        return 'UNVERIFIED'
    peer, connect_time, http_status = result.groups()
    if peer:
        try:
            if ipaddress.ip_address(peer) != ipaddress.ip_address(address):
                return 'UNVERIFIED'
        except ValueError:
            return 'UNVERIFIED'
        return 'REACHABLE'
    # TLS or HTTP errors, including a timeout after TCP connected, must never
    # be used as evidence that the guest could not reach the public endpoint.
    if float(connect_time) > 0 or http_status != '000':
        return 'REACHABLE'
    if ('transportError' not in probe and type(code) is int and code in (7, 28)
            and type(stderr) is str and stderr.startswith(f'curl: ({code}) ')):
        return 'BLOCKED'
    return 'UNVERIFIED'


def network_status(report):
    if type(report) is not dict:
        return 'UNVERIFIED'
    probes = report.get('probes')
    if type(probes) is not dict:
        return 'UNVERIFIED'
    statuses = {probe_status(probes[address], family, address)
                for family, address in PUBLIC_ENDPOINTS if address in probes}
    if 'REACHABLE' in statuses:
        return 'REACHABLE'
    routes = report.get('routeObservation')
    if ('interrupted' in report or set(probes) != {address for _, address in PUBLIC_ENDPOINTS}
            or statuses != {'BLOCKED'} or type(routes) is not dict or 'transportError' in routes
            or type(routes.get('exitCode')) is not int or routes.get('stderr') != ''
            or routes['exitCode'] != 0 or type(routes.get('stdout')) is not str
            or routes['stdout'] != report.get('guestRoutes')
            or not {'Internet:', 'Internet6:'} <= set(routes['stdout'].splitlines())):
        return 'UNVERIFIED'
    return 'PASS'


def observe_network(vm):
    """Preserve timed direct probe results, including failures and transport errors."""
    probes = {}
    route = None
    interrupted = False
    try:
        for family, address in PUBLIC_ENDPOINTS:
            target = probe_url(family, address)
            result = network_command(
                vm, ['/usr/bin/curl', '--disable', f'-{family}', '--noproxy', '*', '--connect-timeout', '5',
                     '--max-time', '5', '--fail', '--silent', '--show-error', '--output', '/dev/null',
                     '--write-out', CURL_DETAILS, target], timeout=12)
            probes[address] = {'target': target, **result}
        route = network_command(vm, ['/usr/sbin/netstat', '-rn'], timeout=12)
    except KeyboardInterrupt:
        interrupted = True
    report = {'time': datetime.now(UTC).isoformat(timespec='seconds'), 'guestRoutes': route['stdout'] if route else '',
              'routeObservation': route, 'probes': probes}
    if interrupted:
        report['interrupted'] = True
    return {**report, 'status': network_status(report)}


def require_offline(report):
    status = network_status(report)
    if status == 'REACHABLE':
        raise ValueError('At least one direct public IPv4 or IPv6 endpoint was reachable')
    if status != 'PASS' or report.get('status') != 'PASS':
        raise ValueError('Direct public IPv4 and IPv6 isolation could not be verified')


def verify_cli_draft_list(body):
    if (type(body) is not dict or type(body.get('items')) is not list
            or not {'committed', 'failure', 'nextCursor'} <= body.keys()):
        raise ValueError('Installed CLI did not return a draft list envelope')
    verify_report_fields(body, {'schemaVersion': 1, 'command': 'draft', 'action': 'list', 'exitCode': 0,
                                'operationSucceeded': True, 'reason': 'completed', 'committed': None,
                                'failure': None, 'hostCleanup': 'succeeded',
                                'additionalFailures': [], 'storageClose': {'state': 'closed', 'error': None}},
                         'Installed CLI draft list and storage close')
    items, cursor = body['items'], body['nextCursor']
    order, ids = [], set()
    for row in items:
        if (type(row) is not dict or set(row) != DRAFT_ROW_FIELDS
                or type(row['id']) is not str or DRAFT_ID.fullmatch(row['id']) is None
                or row['id'] in ids or type(row['title']) is not str
                or type(row['bodyUtf8ByteLength']) is not int or row['bodyUtf8ByteLength'] < 0
                or type(row['revision']) is not int or row['revision'] < 1
                or any(type(row[key]) is not str for key in ('createdAt', 'updatedAt'))):
            raise ValueError('Invalid installed CLI draft list row')
        created, updated = map(files.parse_time, (row['createdAt'], row['updatedAt']))
        if created > updated:
            raise ValueError('Installed CLI draft list has inconsistent timestamps')
        ids.add(row['id'])
        order.append((updated, row['id']))
    if order != sorted(order, reverse=True) or len(items) > 50:
        raise ValueError('Invalid installed CLI draft list order or page size')
    if cursor is not None and (len(items) != 50
                               or cursor != {key: items[-1][key] for key in ('updatedAt', 'id')}):
        raise ValueError('Invalid installed CLI draft list cursor')


def cli_image(raw, cli_stamp, library_stamp, *, observer_pid):
    image = runtime.image_report(raw, cli_stamp['path'], library_stamp['path'],
                                 cli_stamp['sha256'], library_stamp['sha256'], 0,
                                 observer_pid=observer_pid)
    verify_report_fields(image['mapping'], {'device': library_stamp['device'] & 0xFFFFFFFF,
                                            'inode': library_stamp['inode']}, 'Installed CLI SQLite vnode')
    return image


def read_attempt(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError('Expected a case-owned CLI mapping attempt receipt')
    return json.loads(path.read_bytes(), object_pairs_hook=policy_object)


def verify_cli_mapping_receipt(evidence, report, *, expected_cli, expected_library, cli_sha, library_sha, guest_root):
    """Rebind a saved PASS to the exact case attempt, process and installed paths."""
    expected_cli, expected_library = map(str, (expected_cli, expected_library))
    if type(report) is not dict:
        raise ValueError('Expected a complete CLI image observation receipt')
    session = report.get('guestSession')
    if type(session) is not str or not re.fullmatch(re.escape(str(guest_root))+r'/package\.[A-Za-z0-9]{8}', session):
        raise ValueError('CLI mapping did not identify an owned guest session')
    name = 'cli-mapping-attempt-'+Path(session).name
    attempt = Path(evidence)/name
    argv = [expected_cli, *CLI_ARGUMENTS]
    verify_report_fields(report, {'status': 'PASS', 'cwd': session, 'argv': argv, 'attemptEvidence': name,
                                  'pidAbsentAfterNormalExit': True, 'observerPidAbsentAfterNormalExit': True},
                         'CLI image observation')
    if attempt.is_symlink() or not attempt.is_dir():
        raise ValueError('Expected the case-owned CLI mapping attempt directory')
    started = read_attempt(attempt/'started.json')
    if type(started) is not dict:
        raise ValueError('Invalid CLI mapping attempt start')
    verify_report_fields(started, {'status': 'STARTED', 'guestSession': session,
                                   'guestLogPrefix': session+'/cli-mapping', 'argv': argv},
                         'CLI mapping attempt start')
    if encoded(read_attempt(attempt/'result.json')) != encoded(report):
        raise ValueError('CLI mapping differs from the original attempt result')

    cli_stamp, library_stamp = (report.get(key) for key in ('cliFile', 'libraryFile'))
    for stamp, path, pin in ((cli_stamp, expected_cli, cli_sha), (library_stamp, expected_library, library_sha)):
        if (type(stamp) is not dict or type(stamp.get('inode')) is not int or stamp['inode'] <= 0
                or type(stamp.get('device')) is not int or stamp['device'] <= 0):
            raise ValueError('Invalid recorded CLI file vnode')
        verify_report_fields(stamp, {'path': path, 'sha256': pin}, 'Observed CLI file')
    raw, recorded, observer_sha = (report.get(key) for key in ('rawObservation', 'sqliteMapping', 'observerSha256'))
    if (type(raw) is not str or type(recorded) is not dict or type(report.get('stderr')) is not str
            or type(observer_sha) is not str or files.HEX_SHA.fullmatch(observer_sha) is None):
        raise ValueError('Missing native CLI image observation')
    actual = cli_image(raw.encode('utf-8'), cli_stamp, library_stamp, observer_pid=recorded.get('observerPid'))
    if encoded(actual) != encoded(recorded):
        raise ValueError('Recorded CLI mapping differs from native image evidence')
    verify_cli_draft_list(report.get('stdout'))


def require_cli_file(vm, path, expected):
    metadata = {key: value for key, value in expected.items() if key != 'sha256'}
    pin = expected.get('sha256')
    if (type(pin) is not str or files.HEX_SHA.fullmatch(pin) is None
            or files.guest_file_stamp(vm, path) != metadata):
        raise ValueError(f'Installed CLI file identity changed: {path}')
    observed = files.remote_text(vm, ['/usr/bin/shasum', '-a', '256', path]).split()
    if not observed or observed[0] != pin or files.guest_file_stamp(vm, path) != metadata:
        raise ValueError(f'Installed CLI file differs from the accepted bytes: {path}')


def transfer_observer(vm, session, scratch):
    observer = session+'/release-image-probe'
    with tempfile.TemporaryDirectory(dir=scratch, prefix='cli-observer-') as temporary:
        local = Path(temporary)/'release-image-probe'
        env = {**controlled_environment(), 'TMPDIR': temporary}
        subprocess.run([*runtime.image_probe_command(local), '-arch', 'arm64'], check=True,
                       capture_output=True, timeout=60, env=env)
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', local], check=True,
                       capture_output=True, timeout=30, env=env)
        pin = digest(local)
        target = shlex.quote(observer)
        with local.open('rb') as handle:
            vm.remote(f'set -e\nset -C\numask 077\n/bin/cat > {target}\n/bin/chmod 700 {target}',
                      stdin=handle, timeout=30)
    vm.remote(shlex.join(['/usr/bin/codesign', '--verify', '--strict', observer]), timeout=30)
    return observer, {**files.guest_file_stamp(vm, observer), 'sha256': pin}


def write_attempt(path, report):
    with path.open('x', encoding='utf-8') as handle:
        json.dump(report, handle, indent=2)
        handle.write('\n')


def observe_cli_mapping(vm, cli, library, *, scratch, cli_stamp, library_stamp):
    """Read the guest's ordinary default data via its exact installed CLI and dylib."""
    cli, library = files.guest_path(cli), files.guest_path(library)
    bundle = cli.parent.parent
    if cli != bundle/'bin/meshctl' or library != bundle/'lib/libsqlite3.dylib':
        raise ValueError('Expected a complete installed CLI with its bundled SQLite dylib')
    session = guest.guest_session(vm)
    attempt = Path(scratch)/('cli-mapping-attempt-'+Path(session).name)
    attempt.mkdir(mode=0o700)
    argv = [str(cli), *CLI_ARGUMENTS]
    prefix = session+'/cli-mapping'
    write_attempt(attempt/'started.json', {
        'status': 'STARTED', 'guestSession': session, 'guestLogPrefix': prefix, 'argv': argv,
        'time': datetime.now(UTC).isoformat(timespec='seconds'),
    })
    try:
        report = collect_cli_mapping(vm, cli, library, scratch=scratch, session=session, prefix=prefix,
                                     argv=argv, cli_stamp=cli_stamp, library_stamp=library_stamp)
    except (OSError, ValueError, subprocess.SubprocessError, KeyboardInterrupt) as error:
        failure = {
            'status': 'INTERRUPTED' if isinstance(error, KeyboardInterrupt) else 'FAIL',
            'guestSession': session, 'errorType': type(error).__name__,
            'time': datetime.now(UTC).isoformat(timespec='seconds'),
        }
        if isinstance(error, subprocess.CalledProcessError):
            failure['commandExitCode'] = error.returncode
        try:
            write_attempt(attempt/'result.json', failure)
        except OSError as write_error:
            error.add_note(f'Could not write the CLI mapping failure receipt: {write_error}')
        raise
    report['attemptEvidence'] = attempt.name
    write_attempt(attempt/'result.json', report)
    return report


def collect_cli_mapping(vm, cli, library, *, scratch, session, prefix, argv, cli_stamp, library_stamp):
    observer, observer_stamp = transfer_observer(vm, session, scratch)
    targets = ((cli, cli_stamp), (library, library_stamp), (observer, observer_stamp))
    for path, stamp in targets:
        require_cli_file(vm, path, stamp)

    script = guest.runtime_command(argv, session, prefix, observer, str(library))
    vm.remote(shlex.join(['/bin/bash', '-c', 'set -e\n'+script]), timeout=30)

    def read(suffix, *, binary=False):
        return vm.remote(shlex.join(['/bin/cat', prefix+suffix]), capture_output=True,
                         text=not binary, timeout=10).stdout

    exit_code = int(read('.exit'))
    if exit_code != 0:
        raise ValueError(f'Installed CLI image observation exited with {exit_code}; see {prefix}.stderr')
    raw = read('.image.json', binary=True)
    observer_pid = int(read('.pid'))
    image = cli_image(raw, cli_stamp, library_stamp, observer_pid=observer_pid)
    guest.require_absent_pid(vm, observer_pid)
    guest.require_absent_pid(vm, image['pid'])
    body = json.loads(read('.stdout'), object_pairs_hook=policy_object)
    verify_cli_draft_list(body)
    for path, stamp in targets:
        require_cli_file(vm, path, stamp)
    return {'status': 'PASS', 'guestSession': session, 'cwd': session, 'argv': argv,
            'observerSha256': observer_stamp['sha256'], 'cliFile': cli_stamp, 'libraryFile': library_stamp,
            'sqliteMapping': image, 'rawObservation': raw.decode('utf-8'),
            'pidAbsentAfterNormalExit': True, 'observerPidAbsentAfterNormalExit': True,
            'stdout': body, 'stderr': read('.stderr')}
