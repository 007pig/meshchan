"""Runtime evidence for the 1E.6 Developer ID products."""
from contextlib import closing
import json
import os
from pathlib import Path
import re
import sqlite3

import build_release as build
from package_release import canonical, equal, verify_report_fields
from release_materials import digest, require_material_file

IMAGE_SOURCE = 'tool/release_image_probe.c'
APP_EXECUTABLE = 'Contents/MacOS/Meshchan'
APP_SQLITE = 'Contents/Frameworks/sqlite3.framework/Versions/A/sqlite3'
APP_TITLE = 'Runtime 中文 🛰️'
APP_BODY = 'First\r\n第二行 🙂\nLast\rEnd'
APP_PHASE_DIRECTORY = 'products phase 1E.6'
APP_FIXTURE = 'meshchan-1d3-package'
METHOD = 'proc_pidinfo/PROC_PIDREGIONPATHINFO'


def image_probe_command(executable):
    return ['/usr/bin/xcrun', '--sdk', 'macosx', 'clang', '-std=c17', '-D_DARWIN_C_SOURCE',
            '-Wall', '-Wextra', '-Werror', '-O2', build.ROOT/IMAGE_SOURCE, '-o', executable]


def image_report(data, executable, library, executable_sha, library_sha, exit_code, *, observer_pid):
    parsed = json.loads(data)
    if not isinstance(parsed, dict) or type(parsed.get('pid')) is not int or parsed['pid'] <= 1:
        raise ValueError('Image observer did not record an owned product PID')
    if type(observer_pid) is not int or observer_pid <= 1 or observer_pid == parsed['pid']:
        raise ValueError('Expected a distinct owned image observer PID')
    verify_report_fields(parsed, {'observerPid': observer_pid, 'exitCode': exit_code}, 'Image observer receipt')
    mapping = parsed.get('mapping')
    if mapping is None:
        errno = parsed.get('lastObservationErrno')
        raise ValueError(f'No executable SQLite mapping was observed for the owned process (libproc errno {errno})')
    if (set(parsed) != {'observerPid', 'pid', 'exitCode', 'mapping'} or not isinstance(mapping, dict)
            or set(mapping) != {'address', 'device', 'inode'}
            or type(mapping.get('inode')) is not int or mapping['inode'] <= 0
            or type(mapping.get('device')) is not int or mapping['device'] <= 0
            or not isinstance(mapping.get('address'), str)
            or not re.fullmatch(r'0x[1-9a-f][0-9a-f]*', mapping['address'])):
        raise ValueError('Malformed live SQLite mapping evidence')
    return {**parsed, 'method': METHOD, 'observedReceiptSha256': build.sha(data),
            'executable': str(executable), 'executableSha256': executable_sha,
            'library': str(library), 'librarySha256': library_sha}


def signed_info(path, pin):
    path = canonical(path)
    raw = require_material_file(path.parent, path.name).read_bytes()
    if build.sha(raw) != pin:
        raise ValueError('Signed product information differs from its expected SHA-256')
    info = json.loads(raw)
    if not isinstance(info, dict):
        raise ValueError('Signed product information must be a JSON object')
    verify_report_fields(info, {'formatVersion': 1}, 'Signed product information')
    identity = info.get('identity')
    signature = info.get('signature')
    if (not isinstance(identity, dict) or not isinstance(info.get('payloadInventory'), dict)
            or not isinstance(signature, dict) or not isinstance(signature.get('items'), list)):
        raise ValueError('Signed product identity, signature, or inventory is missing')
    app_build, version, apple = (identity.get(key) for key in ('appBuild', 'productVersion', 'apple'))
    if (not isinstance(app_build, str) or not re.fullmatch(r'[1-9][0-9]*', app_build)
            or not isinstance(version, str) or not version or not isinstance(apple, dict)):
        raise ValueError('Signed App version/build identity is malformed')
    verify_report_fields(identity, {'target': 'macos-arm64', 'appVersion': version+'+'+app_build},
                         'Signed product identity')
    verify_report_fields(apple, {'CFBundleIdentifier': 'org.meshchan.meshchan', 'CFBundleVersion': app_build,
                                 'MeshchanProductVersion': version}, 'Signed App identity')
    public = signature.get('identity')
    if not isinstance(public, dict):
        raise ValueError('Signed product is missing the public signing identity')
    sha1, team, authority = (public.get(key) for key in ('sha1', 'team', 'authority'))
    if (not isinstance(sha1, str) or not re.fullmatch(r'[a-fA-F0-9]{40}', sha1)
            or not isinstance(team, str) or not re.fullmatch(r'[A-Z0-9]{10}', team)
            or not isinstance(authority, str) or not authority.startswith('Developer ID Application: ')):
        raise ValueError('Signed product lacks a pinned Developer ID Application identity')
    return info


def developer_requirement(public):
    return (f'anchor apple generic and certificate leaf = H"{public["sha1"]}" '
            f'and certificate leaf[subject.OU] = "{public["team"]}" '
            'and certificate leaf[field.1.2.840.113635.100.6.1.13] exists')


def validate_app_shutdown(runtime, shutdown, mode):
    if 'error' not in runtime or 'error' not in shutdown:
        raise ValueError('Signed App shutdown receipt omitted its error field')
    shutdown_state = {'resourcesReleased': True, 'workerExited': True,
                      'pendingRequests': 0, 'receivePorts': 0, 'error': None}
    verify_report_fields(runtime, {**shutdown_state, 'mode': mode}, 'Signed App runtime')
    verify_report_fields(shutdown, {**shutdown_state, 'workerWasSpawned': True, 'owner': 'released',
                                    'quitPhase': 'closed'}, 'Signed App shutdown')
    phases = runtime.get('phases')
    ordered = ('opening', 'ready', 'closing', 'closed')
    if (not isinstance(phases, list) or not all(isinstance(phase, str) for phase in phases)
            or not phases or phases[-1] != 'closed'
            or tuple(phase for phase in phases if phase in ordered) != ordered):
        raise ValueError('Signed App runtime lost its ordered close phases')
    draft = runtime.get('draft')
    if not isinstance(draft, dict) or not isinstance(draft.get('id'), str) or not draft['id']:
        raise ValueError('Signed App runtime did not report a persisted draft')
    verify_report_fields(draft, {'revision': 1, 'bodyUtf8Bytes': len(APP_BODY.encode())}, 'Signed App draft')


def validate_database(data, draft, title, body):
    # Read the same closed rollback-journal database bytes used for the receipt
    # hash. An in-memory copy avoids re-opening an evidence path after pinning it.
    try:
        with closing(sqlite3.connect(':memory:')) as connection:
            connection.deserialize(data)
            equal([('ok',)], connection.execute('pragma quick_check').fetchall(), 'SQLite integrity')
            drafts = connection.execute('select id, title, body, revision from stored_drafts').fetchall()
    except sqlite3.Error as error:
        raise ValueError('Closed SQLite evidence could not be read: '+str(error)) from None
    equal(1, len(drafts), 'Persisted SQLite draft count')
    fields = {'id': draft['id'], 'title': title, 'body': body, 'revision': 1}
    verify_report_fields(dict(zip(fields, drafts[0])), fields, 'Persisted SQLite draft')
    return drafts


def verify_vm_runtime_evidence(report, evidence, inventory):
    """Re-read live mapping and closed database evidence bound to the VM receipt."""
    session, run = report.get('guestSession'), report.get('guestRun')
    if (not isinstance(session, str) or not re.fullmatch(r'package\.[A-Za-z0-9]{8}', session)
            or not isinstance(run, str) or not re.fullmatch(r'[0-9]{8}T[0-9]{6}Z-product-[1-9][0-9]*', run)):
        raise ValueError('Signed VM evidence did not identify its private session and run')
    ownership = require_material_file(evidence, 'session.json').read_bytes()
    observer = require_material_file(evidence, 'release-image-probe')
    verify_report_fields(report, {'guestOwnershipSha256': build.sha(ownership),
                                  'observerSha256': digest(observer)}, 'Signed VM receipt')
    owner = json.loads(ownership)
    lock_identity = owner.get('lockIdentity') if isinstance(owner, dict) else None
    if not isinstance(lock_identity, str) or not re.fullmatch(r'[0-9]+:[0-9]+', lock_identity):
        raise ValueError('Signed VM evidence lacks its guest lock identity')
    verify_report_fields(owner, {'run': run, 'products': {}}, 'Signed VM ownership')
    guest_app = '$GUEST_ROOT/'+session+'/'+APP_PHASE_DIRECTORY+'/Meshchan.app'
    verify_report_fields(report, {'guestApp': guest_app}, 'Signed VM receipt')
    cwd = guest_app.removesuffix('/Meshchan.app')+'/runtime workspace'
    executable, library = guest_app+'/'+APP_EXECUTABLE, guest_app+'/'+APP_SQLITE
    executable_sha, library_sha = inventory[APP_EXECUTABLE]['sha256'], inventory[APP_SQLITE]['sha256']
    processes = report.get('processes')
    if not isinstance(processes, list) or len(processes) != 2:
        raise ValueError('Signed VM evidence must cover distinct write and reopen processes')
    pids = set()
    drafts = []
    for mode, row in zip(('write', 'read'), processes):
        if not isinstance(row, dict) or not isinstance(row.get('stdout'), str):
            raise ValueError('Malformed signed App process evidence')
        expected = {'argv': [executable, '--meshchan-runtime='+mode,
                             '--data-dir='+cwd+'/'+APP_FIXTURE, '--runtime-exit'],
                    'cwd': cwd, 'exitCode': 0, 'pidAbsentAfterNormalExit': True,
                    'sqliteLoadedFrom': library}
        verify_report_fields(row, expected, 'Signed VM '+mode)
        raw = require_material_file(evidence, mode+'-image.json').read_bytes()
        observer_pid = row.get('observerPid')
        observed = image_report(raw, executable, library, executable_sha, library_sha, 0, observer_pid=observer_pid)
        verify_report_fields(row, {'pid': observed['pid']}, 'Signed VM App process')
        if {observer_pid, row['pid']} & pids:
            raise ValueError('Signed VM App or image observer PID is reused')
        pids.update((observer_pid, row['pid']))
        recorded = row.get('sqliteMapping')
        if not isinstance(recorded, dict) or not isinstance(recorded.get('mapping'), dict):
            raise ValueError('Signed VM receipt lacks its bound SQLite mapping observation')
        verify_report_fields(recorded, observed, 'Signed VM SQLite observation')
        verify_report_fields(recorded['mapping'], observed['mapping'], 'Signed VM SQLite vnode')
        logs = [json.loads(line) for line in row['stdout'].splitlines() if line.startswith('{')]
        if not all(isinstance(entry, dict) for entry in logs):
            raise ValueError('Malformed signed App runtime log')
        runtime = [entry for entry in logs if entry.get('verification') == 'meshchan.runtime.1d3']
        shutdown = [entry for entry in logs if entry.get('runtime') == 'meshchan.shutdown.1d3']
        if len(runtime) != 1 or len(shutdown) != 1:
            raise ValueError('Signed VM process lacks unique runtime and shutdown receipts')
        verify_report_fields(runtime[0], {'passed': True, 'appVersion': report['identity']['appVersion']},
                             'Signed VM compiled App')
        validate_app_shutdown(runtime[0], shutdown[0], mode)
        verify_report_fields(row, {'draft': runtime[0]['draft']}, 'Signed VM draft')
        drafts.append(runtime[0]['draft'])
    equal(drafts[0], drafts[1], 'Signed VM draft after process reopen')
    database = require_material_file(evidence, 'vm-fixture.sqlite').read_bytes()
    verify_report_fields(report, {'guestDatabaseSha256': build.sha(database)}, 'Signed VM closed fixture')
    stored = validate_database(database, drafts[1], APP_TITLE, APP_BODY)
    equal(build.encoded(stored), build.encoded(report.get('storedDrafts')), 'Signed VM SQLite receipt')


def require_absent_pid(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return
    raise ValueError(f'Owned runtime process PID {pid} was not absent after normal exit')


def cli_observer_pid(step):
    process_tree = step['processTree']
    verify_report_fields(process_tree, {'exited': True, 'childReaped': True}, 'CLI observer process tree')
    roots = [row for row in process_tree['members']
             if row['pid'] == row['pgid'] and row['ppid'] == os.getpid()]
    if len(roots) != 1 or type(roots[0]['pid']) is not int or roots[0]['pid'] <= 1:
        raise ValueError('CLI image observer did not identify one owned runner process')
    verify_report_fields(roots[0], {'exitObserved': True}, 'CLI observer process')
    return roots[0]['pid']


def accept_cli(bundle: Path, workspace: Path, runner, version: str):
    """Run the independently verified, relocated CLI in an owned empty workspace."""
    executable = require_material_file(bundle, 'bin/meshctl')
    library = require_material_file(bundle, build.CLI_SQLITE_LIBRARY)
    executable_sha, library_sha = digest(executable), digest(library)
    workspace = canonical(workspace)
    workspace.mkdir(mode=0o700)
    observer = workspace/'release-image-probe'

    previous_env = runner.env
    runner.env = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LANG': 'en_US.UTF-8',
                  'LC_ALL': 'en_US.UTF-8', 'HOME': str(workspace), 'TMPDIR': str(workspace)}
    try:
        runner.command('compile-cli-image-observer', image_probe_command(observer), workspace)
        observer_sha = digest(observer)
        equal('meshctl '+version, runner.command('signed-cli-version', [executable, '--version'], workspace).strip(),
              'Compiled signed CLI version')
        data = workspace/'owned signed CLI data'
        if os.path.lexists(data):
            raise ValueError('Signed CLI needs a fresh data fixture')
        title, body = 'Signed release smoke', 'Offline sample 中文\r\nsecond line\n'
        start = [executable, '--data-dir', data, 'draft']
        rows = []
        for action in ('create', 'show'):
            arguments = (['--title', title, '--body', body] if action == 'create' else
                         ['--id', rows[0]['report']['draft']['id']])
            image = workspace/(action+'-image.json')
            argv = [*start, action, *arguments, '--json']
            result = json.loads(runner.command('signed-cli-'+action,
                                               [observer, image, library, *argv], workspace))
            verify_report_fields(result, {'exitCode': 0, 'operationSucceeded': True, 'schemaVersion': 1,
                                          'command': 'draft', 'action': action, 'hostCleanup': 'succeeded'},
                                 'Signed CLI '+action)
            verify_report_fields(result['storageClose'], {'state': 'closed', 'error': None}, 'Signed CLI storage close')
            draft = result['draft']
            verify_report_fields(draft, {'title': title, 'body': body, 'revision': 1,
                                         'bodyUtf8ByteLength': len(body.encode())}, 'Signed CLI draft')
            if not isinstance(draft.get('id'), str) or not draft['id']:
                raise ValueError('Signed CLI did not report a persisted draft ID')
            observer_pid = cli_observer_pid(runner.receipt['steps'][-1])
            observed = image_report(require_material_file(workspace, image.name).read_bytes(),
                                    executable, library, executable_sha, library_sha, 0, observer_pid=observer_pid)
            stat = library.stat()
            verify_report_fields(observed['mapping'], {'device': stat.st_dev & 0xFFFFFFFF, 'inode': stat.st_ino},
                                 'Signed CLI SQLite vnode')
            require_absent_pid(observed['pid'])
            if any(row['pid'] == observed['pid'] for row in rows):
                raise ValueError('Signed CLI mapping receipt did not identify a fresh process')
            rows.append({'name': action, 'argv': list(map(str, argv)), 'cwd': str(workspace),
                         'pid': observed['pid'], 'pidAbsentAfterNormalExit': True,
                         'sqliteMapping': observed, 'report': result})

        equal(rows[0]['report']['draft'], rows[1]['report']['draft'], 'Draft after process reopen')
        database = require_material_file(data, 'meshchan.sqlite')
        database_bytes = database.read_bytes()
        drafts = validate_database(database_bytes, rows[1]['report']['draft'], title, body)
        equal(executable_sha, digest(executable), 'Signed CLI executable after runtime')
        equal(library_sha, digest(library), 'Signed CLI SQLite after runtime')
        equal(observer_sha, digest(observer), 'CLI image observer after runtime')
        return {'status': 'PASS', 'bundle': str(bundle), 'processes': rows, 'database': str(database),
                'databaseSha256': build.sha(database_bytes), 'storedDrafts': drafts, 'observerSha256': observer_sha}
    finally:
        runner.env = previous_env
