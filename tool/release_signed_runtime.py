"""Runtime evidence for inventory-pinned macOS products."""
from contextlib import closing
from dataclasses import replace
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess

import build_release as build
from package_release import canonical, equal, verify_report_fields
from product_identity import BUNDLE_ID, check_app, expected_identity
from release_materials import controlled_environment, digest, require_material_file
from release_signing import (DEVELOPER_PROFILE, LOCAL_PROFILE, CodeItem, policy_object,
                             display_signature, macho_layout, require_local_identity, verify_signature_values)

IMAGE_SOURCE = 'tool/release_image_probe.c'
APP_EXECUTABLE = 'Contents/MacOS/Meshchan'
APP_SQLITE = 'Contents/Frameworks/sqlite3.framework/Versions/A/sqlite3'
LOCAL_APP = CodeItem('Meshchan.app', 'Meshchan.app/'+APP_EXECUTABLE, 'app', BUNDLE_ID,
                     True, signing_profile=LOCAL_PROFILE)
APP_TITLE = 'Runtime 中文 🛰️'
APP_BODY = 'First\r\n第二行 🙂\nLast\rEnd'
APP_PHASE_DIRECTORY = 'products phase 1E.6'
APP_FIXTURE = 'meshchan-1d3-package'
CLI_TITLE = 'Signed release smoke'
CLI_BODY = 'Offline sample 中文\r\nsecond line\n'
METHOD = 'proc_pidinfo/PROC_PIDREGIONPATHINFO'


def image_probe_command(executable):
    return ['/usr/bin/xcrun', '--sdk', 'macosx', 'clang', '-std=c17', '-D_DARWIN_C_SOURCE',
            '-Wall', '-Wextra', '-Werror', '-O2', build.ROOT/IMAGE_SOURCE, '-o', executable]


def image_report(data, executable, library, executable_sha, library_sha, exit_code, *, observer_pid):
    parsed = json.loads(data, object_pairs_hook=policy_object)
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


PUBLIC_PAYLOAD = 'public-engineering-v1'


def signed_info(path, pin):
    path = canonical(path)
    raw = require_material_file(path.parent, path.name).read_bytes()
    if build.sha(raw) != pin:
        raise ValueError('Signed product information differs from its expected SHA-256')
    return parse_signed_info(raw)


def manifest_profile(info):
    if (type(info.get('formatVersion')) is int and info['formatVersion'] == 1
            and 'signingProfile' not in info):
        return DEVELOPER_PROFILE
    verify_report_fields(info, {'formatVersion': 2, 'signingProfile': LOCAL_PROFILE}, 'Signed product information')
    return LOCAL_PROFILE


def parse_signed_info(raw):
    info = json.loads(raw, object_pairs_hook=policy_object)
    if not isinstance(info, dict):
        raise ValueError('Signed product information must be a JSON object')
    profile = manifest_profile(info)
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
    if profile == LOCAL_PROFILE:
        verify_report_fields(apple, expected_identity(version, int(app_build)), 'Local App identity')
        require_local_identity(public)
        local_app_code_hashes(info)
        return info
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


def local_app_code_hashes(info):
    items = info['signature']['items']
    if (any(type(row) is not dict or row.get('signingProfile') != LOCAL_PROFILE
            or not isinstance(row.get('path'), str) for row in items)
            or len({row['path'] for row in items}) != len(items)):
        raise ValueError('Local manifest has duplicate, missing, or conflicting code items')
    apps = [row for row in items if row.get('role') == 'app']
    if len(apps) != 1:
        raise ValueError('Local manifest must identify the App signature')
    app = apps[0]
    verify_report_fields(app, LOCAL_APP.record(), 'Local App signature')
    slices = app.get('slices')
    if type(slices) is not dict or 'arm64' not in slices or set(slices) - {'arm64', 'x86_64'}:
        raise ValueError('Local manifest has no supported App signature architectures')
    result = {}
    for arch, observed in slices.items():
        if type(observed) is not dict:
            raise ValueError('Malformed local App signature for '+arch)
        verify_signature_values(LOCAL_APP, info['signature']['identity'], observed)
        verify_report_fields(observed, {'signatureSlots': 1}, 'Local App signature slots')
        cdhash = observed.get('cdhash')
        if not isinstance(cdhash, str) or not re.fullmatch(r'[a-f0-9]{40}', cdhash):
            raise ValueError('Local App signature has no valid CodeDirectory hash')
        result[arch] = cdhash
    return result


def app_requirements(info):
    if manifest_profile(info) == DEVELOPER_PROFILE:
        return [(None, developer_requirement(info['signature']['identity']))]
    return [(arch, f'identifier "{LOCAL_APP.identifier}" and cdhash H"{cdhash}"')
            for arch, cdhash in local_app_code_hashes(info).items()]


def verify_local_app(app, info):
    """Bind the guest requirements to all actual App architectures and signature facts."""
    hashes = local_app_code_hashes(info)
    product = info['identity']
    check_app(app, product['productVersion'], int(product['appBuild']))
    item = replace(LOCAL_APP, path=app.name, binary=app.name+'/'+APP_EXECUTABLE)
    equal(set(hashes), set(macho_layout(app/APP_EXECUTABLE)['slices']), 'Local App signature architectures')
    env = controlled_environment()
    env.pop('TMPDIR', None)

    def display_command(_name, argv, *, return_stderr=False):
        result = subprocess.run(argv, check=True, timeout=30, capture_output=True, text=True, env=env)
        return result.stderr if return_stderr else result.stdout

    for arch, cdhash in hashes.items():
        displayed = display_signature(app.parent, item, arch, display_command, 'local-app-'+arch)
        verify_signature_values(item, info['signature']['identity'], displayed)
        equal(cdhash, displayed['cdhash'], 'Local App CodeDirectory hash for '+arch)


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
    owner = json.loads(ownership, object_pairs_hook=policy_object)
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
    vnodes = []
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
        vnodes.append((observed['mapping']['device'], observed['mapping']['inode']))
        logs = [json.loads(line, object_pairs_hook=policy_object)
                for line in row['stdout'].splitlines() if line.startswith('{')]
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
    equal(vnodes[0], vnodes[1], 'Signed VM SQLite vnode after process reopen')
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


def cli_observer_pid(step, *, recorded=False):
    process_tree = step['processTree']
    verify_report_fields(process_tree, {'exited': True, 'childReaped': True}, 'CLI observer process tree')
    roots = [row for row in process_tree['members']
             if type(row['pid']) is int and type(row['pgid']) is int and row['pid'] == row['pgid']
             and type(row['ppid']) is int and row['ppid'] > 1
             and (recorded or row['ppid'] == os.getpid())]
    if len(roots) != 1 or roots[0]['pid'] <= 1:
        raise ValueError('CLI image observer did not identify one owned runner process')
    verify_report_fields(roots[0], {'exitObserved': True}, 'CLI observer process')
    return roots[0]['pid']


def process_log(root, step, key):
    path = require_material_file(root, step[key])
    raw = path.read_bytes()
    equal(step[key+'Sha256'], build.sha(raw), 'Owned process log '+step[key])
    return raw


def verify_cli_runtime_evidence(report, bundle, workspace, version, *, ledger, evidence_root):
    """Revalidate the closed SQLite fixture and observations from both CLI commands."""
    executable = require_material_file(bundle, 'bin/meshctl')
    library = require_material_file(bundle, build.CLI_SQLITE_LIBRARY)
    observer = require_material_file(workspace, 'release-image-probe')
    data = workspace/'owned signed CLI data'
    database = require_material_file(data, 'meshchan.sqlite')
    raw_db = database.read_bytes()
    verify_report_fields(report, {'status': 'PASS', 'bundle': str(bundle),
                                  'versionOutput': 'meshctl '+version,
                                  'database': str(database), 'databaseSha256': build.sha(raw_db),
                                  'observerSha256': digest(observer)}, 'Signed CLI receipt')
    processes = report.get('processes')
    if type(processes) is not list or len(processes) != 2:
        raise ValueError('Signed CLI evidence requires distinct write and reopen processes')

    def cli_step(name, argv):
        selected = [step for step in ledger['steps'] if step['name'] == 'signed-cli-'+name]
        if len(selected) != 1:
            raise ValueError('Expected one owned CLI process step for '+name)
        step = selected[0]
        verify_report_fields(step, {'cwd': str(workspace), 'argv': list(map(str, argv)), 'exitCode': 0},
                             'Signed CLI process '+name)
        return step, process_log(evidence_root, step, 'log')

    _, output = cli_step('version', [executable, '--version'])
    equal('meshctl '+version, output.decode().strip(), 'Observed signed CLI version')
    executable_sha, library_sha = digest(executable), digest(library)
    filesystem = library.stat()
    pids, drafts = set(), []
    for action, row in zip(('create', 'show'), processes, strict=True):
        arguments = (['--title', CLI_TITLE, '--body', CLI_BODY] if action == 'create' else
                     ['--id', drafts[0]['id']])
        image = require_material_file(workspace, action+'-image.json')
        argv = [executable, '--data-dir', data, 'draft', action, *arguments, '--json']
        step, output = cli_step(action, [observer, image, library, *argv])
        result = json.loads(output, object_pairs_hook=policy_object)
        equal(build.encoded(result), build.encoded(row['report']), 'Observed CLI output for '+action)
        raw = image.read_bytes()
        observer_pid = cli_observer_pid(step, recorded=True)
        observed = image_report(raw, executable, library, executable_sha, library_sha, 0,
                                observer_pid=observer_pid)
        children = [member for member in step['processTree']['members'] if member['ppid'] == observer_pid]
        if children:
            matches = [child for child in children if child.get('pid') == observed['pid']]
            if len(matches) != 1:
                raise ValueError('CLI image observer named a different product process')
            verify_report_fields(matches[0], {'pid': observed['pid'], 'ppid': observer_pid,
                                               'pgid': observer_pid, 'exitObserved': True}, 'CLI child process')
        verify_report_fields(observed['mapping'], {'device': filesystem.st_dev & 0xFFFFFFFF,
                                                   'inode': filesystem.st_ino}, 'Signed CLI SQLite vnode')
        verify_report_fields(row, {
            'name': action, 'argv': list(map(str, argv)),
            'cwd': str(workspace), 'pid': observed['pid'], 'pidAbsentAfterNormalExit': True,
            'sqliteMapping': observed,
        }, 'Signed CLI '+action)
        verify_report_fields(row['sqliteMapping']['mapping'], observed['mapping'], 'Signed CLI SQLite observation')
        if {observed['observerPid'], observed['pid']} & pids:
            raise ValueError('Signed CLI or image observer PID is reused')
        pids.update((observed['observerPid'], observed['pid']))
        drafts.append(verified_cli_draft(result, action))
    equal(drafts[0], drafts[1], 'Draft after signed CLI process reopen')
    stored = validate_database(raw_db, drafts[1], CLI_TITLE, CLI_BODY)
    equal(build.encoded(stored), build.encoded(report.get('storedDrafts')), 'Signed CLI SQLite receipt')


def verified_cli_draft(result, action):
    if type(result) is not dict:
        raise ValueError('Signed CLI did not return a JSON object')
    verify_report_fields(result, {'exitCode': 0, 'operationSucceeded': True, 'schemaVersion': 1,
                                  'command': 'draft', 'action': action, 'hostCleanup': 'succeeded'},
                         'Signed CLI '+action)
    storage = result.get('storageClose')
    if type(storage) is not dict or 'error' not in storage:
        raise ValueError('Signed CLI storage close omitted its error field')
    verify_report_fields(storage, {'state': 'closed', 'error': None}, 'Signed CLI storage close')
    draft = result['draft']
    verify_report_fields(draft, {'title': CLI_TITLE, 'body': CLI_BODY, 'revision': 1,
                                 'bodyUtf8ByteLength': len(CLI_BODY.encode())}, 'Signed CLI draft')
    if not isinstance(draft.get('id'), str) or not draft['id']:
        raise ValueError('Signed CLI did not report a persisted draft ID')
    return draft


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
        version_output = runner.command('signed-cli-version', [executable, '--version'], workspace).strip()
        equal('meshctl '+version, version_output, 'Compiled signed CLI version')
        data = workspace/'owned signed CLI data'
        if os.path.lexists(data):
            raise ValueError('Signed CLI needs a fresh data fixture')
        start = [executable, '--data-dir', data, 'draft']
        rows = []
        for action in ('create', 'show'):
            arguments = (['--title', CLI_TITLE, '--body', CLI_BODY] if action == 'create' else
                         ['--id', rows[0]['report']['draft']['id']])
            image = workspace/(action+'-image.json')
            argv = [*start, action, *arguments, '--json']
            result = json.loads(runner.command('signed-cli-'+action,
                                               [observer, image, library, *argv], workspace),
                                object_pairs_hook=policy_object)
            verified_cli_draft(result, action)
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
        drafts = validate_database(database_bytes, rows[1]['report']['draft'], CLI_TITLE, CLI_BODY)
        equal(executable_sha, digest(executable), 'Signed CLI executable after runtime')
        equal(library_sha, digest(library), 'Signed CLI SQLite after runtime')
        equal(observer_sha, digest(observer), 'CLI image observer after runtime')
        return {'status': 'PASS', 'bundle': str(bundle), 'versionOutput': version_output,
                'processes': rows, 'database': str(database),
                'databaseSha256': build.sha(database_bytes), 'storedDrafts': drafts, 'observerSha256': observer_sha}
    finally:
        runner.env = previous_env
