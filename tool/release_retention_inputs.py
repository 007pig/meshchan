"""Validate and enumerate the receipt-bound local engineering handoff."""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import re
import stat
from types import SimpleNamespace

import build_release as build
import package_dmg as dmg
import package_dmg_image as disk
import package_release as package
import release_signed_runtime as runtime
import release_signing
import sign_release as signing
from package_release import equal, verify_report_fields
from release_materials import digest, encoded, product_inventory, safe, sha
from release_package_archive import check_payload
from release_signing import policy_object
from release_signed_replacement import APP_LIBRARY, CLI_LIBRARY, SOURCE_FILES

INPUTS = {'dmg', 'dmg_acceptance', 'signed_manifest', 'local_acceptance'}
IMAGE_GATES = ('workspaceStatus', 'imageIntegrityStatus', 'attachStatus', 'extractionStatus',
               'signatureStatus', 'detachStatus', 'staticStatus', 'finalIntegrityStatus',
               'localAcceptanceStatus')
CHECKS = ('check-inputs', 'check-products', 'materials-recheck', 'check-commit')


def original_path(value):
    """Validate a historical absolute path lexically, without touching it."""
    if not isinstance(value, (str, Path)):
        raise ValueError('Expected a historical path')
    path = Path(value)
    if (not path.is_absolute() or path.anchor != '/' or len(path.parts) < 2
            or '..' in path.parts or str(path) != str(value) or '\0' in str(path)):
        raise ValueError('Invalid historical path: '+str(value))
    return path


def relative_reference(root, value, *, scope=None):
    if type(value) is not str or not value or '\0' in value:
        raise ValueError('Invalid evidence path')
    if Path(value).is_absolute():
        path = original_path(value)
    else:
        path = root/safe(value)
        if path.relative_to(root).as_posix() != value:
            raise ValueError('Noncanonical evidence path: '+value)
    scope = root if scope is None else scope
    if path == scope or not path.is_relative_to(scope):
        raise ValueError('Evidence path is outside its selected root: '+value)
    return path


def verify_pin(pin):
    if type(pin) is not str or not package.SHA256.fullmatch(pin):
        raise ValueError('Expected a lowercase SHA-256 digest')


def json_object(raw):
    value = json.loads(raw, object_pairs_hook=policy_object)
    if type(value) is not dict:
        raise ValueError('Expected a JSON object in acceptance evidence')
    return value


class RetainedRead:
    def __init__(self, locate, *, live):
        self.locate = locate
        self.live = live
        self.selected = set()

    def path(self, original):
        path = original_path(self.locate(original_path(original)))
        # Reject aliased ancestors before following them. The historical name
        # is a lookup key and never gets resolved outside the selected copy.
        for parent in reversed(path.parents):
            if not stat.S_ISDIR(parent.lstat().st_mode):
                raise ValueError('Aliased evidence ancestor: '+str(parent))
        return path

    def directory(self, original):
        path = package.real_directory(self.path(original))
        self.selected.add(original)
        return path

    def file(self, original):
        path = self.path(original)
        metadata = path.lstat()
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            raise ValueError('Expected a single-link regular evidence file: '+str(original))
        self.selected.add(original)
        return path

    def bytes(self, original, pin=None):
        if pin is not None:
            verify_pin(pin)
        raw = self.file(original).read_bytes()
        if pin is not None:
            equal(pin, sha(raw), 'SHA-256 of '+str(original))
        return raw

    def entry(self, original, expected):
        path = self.file(original)
        verify_report_fields(package.file_entry(path), expected, 'File entry '+str(original))
        return path

    def reference(self, base, reference, expected, *, scope=None):
        equal(expected, relative_reference(base, reference['path'], scope=scope), 'Evidence location')
        verify_pin(reference['sha256'])
        return self.bytes(expected, reference['sha256'])

    def report(self, base, ref, expected, *, scope=None):
        return json_object(self.reference(base, ref, expected, scope=scope))

    def tree(self, original, expected):
        path = self.directory(original)
        check_payload(path, expected)
        return path

    def roots(self):
        return sorted(path for path in self.selected
                      if all(parent not in self.selected for parent in path.parents))


def read_ledger(reader, base, reference, evidence, *, status='PASS', unsigned_image=False):
    ledger = reader.report(base, reference, evidence/'build-receipt.json')
    return ledger, verify_steps(reader, ledger, base, evidence, status, unsigned_image=unsigned_image)


def verify_steps(reader, ledger, base, evidence, status, *, unsigned_image=False):
    verify_report_fields(ledger, {'status': status}, 'Owned process ledger')
    steps = ledger.get('steps')
    if type(steps) is not list or not steps:
        raise ValueError('Expected a nonempty owned process ledger')
    logs = {}
    for step in steps:
        name = step['name']
        if type(name) is not str or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', name) or name in logs:
            raise ValueError('Invalid or repeated owned process name')
        expected = 1 if unsigned_image and name == 'inspect-container-signature' else 0
        verify_report_fields(step, {'exitCode': expected}, 'Owned process '+name)
        if unsigned_image and name in {'attach-image', 'detach-image'}:
            verify_report_fields(step, {'childReaped': True}, 'Owned image operation '+name)
        else:
            verify_report_fields(step['processTree'], {'exited': True, 'childReaped': True}, 'Owned process tree '+name)
        logs[name] = {}
        for key, suffix in (('log', '.log'), ('stderrLog', '.stderr.log')):
            logs[name][key] = reader.reference(
                base, {'path': step[key], 'sha256': step[key+'Sha256']}, evidence/'logs'/(name+suffix))
    return logs


def verify_cli(reader, cli, bundle, workspace, identity, ledger, logs):
    """Bind the historical observer paths and vnodes to retained product bytes."""
    executable = bundle/'bin/meshctl'
    library = bundle/build.CLI_SQLITE_LIBRARY
    observer = workspace/'release-image-probe'
    data = workspace/'owned signed CLI data'
    database = data/'meshchan.sqlite'
    executable_sha = digest(reader.file(executable))
    library_file = reader.file(library)
    library_sha = digest(library_file)
    raw_db = reader.bytes(database, cli['databaseSha256'])
    version = 'meshctl '+identity['productVersion']
    verify_report_fields(cli, {'status': 'PASS', 'bundle': str(bundle), 'database': str(database),
                               'observerSha256': digest(reader.file(observer)), 'versionOutput': version},
                         'Signed CLI receipt')

    def step(name, argv):
        observed = signing.process_step(ledger, 'signed-cli-'+name)
        verify_report_fields(observed, {'cwd': str(workspace), 'argv': list(map(str, argv))},
                             'Signed CLI '+name)
        return observed

    step('version', [executable, '--version'])
    equal(version, logs['signed-cli-version']['log'].decode().strip(), 'Observed CLI version')
    vnodes, drafts, pids = [], [], set()
    for action, row in zip(('create', 'show'), cli['processes'], strict=True):
        image = workspace/(action+'-image.json')
        arguments = (['--title', runtime.CLI_TITLE, '--body', runtime.CLI_BODY] if action == 'create' else
                     ['--id', drafts[0]['id']])
        argv = [executable, '--data-dir', data, 'draft', action, *arguments, '--json']
        invocation = step(action, [observer, image, library, *argv])
        observed = runtime.image_report(reader.bytes(image), executable, library, executable_sha, library_sha, 0,
                                        observer_pid=runtime.cli_observer_pid(invocation, recorded=True))
        if {observed['pid'], observed['observerPid']} & pids:
            raise ValueError('Repeated historical CLI product or observer PID')
        pids.update((observed['pid'], observed['observerPid']))
        children = [entry for entry in invocation['processTree']['members']
                    if entry['ppid'] == observed['observerPid']]
        if children and not any(entry['pid'] == observed['pid'] and entry['exitObserved'] is True
                                and entry['pgid'] == observed['observerPid'] for entry in children):
            raise ValueError('Historical observer PID differs from its owned product')
        result = json_object(logs['signed-cli-'+action]['log'])
        verify_report_fields(row, {'name': action, 'cwd': str(workspace), 'argv': list(map(str, argv)),
                                  'pid': observed['pid'], 'pidAbsentAfterNormalExit': True,
                                  'sqliteMapping': observed, 'report': result}, 'Signed CLI '+action)
        mapping = observed['mapping']
        vnodes.append((mapping['device'], mapping['inode']))
        drafts.append(runtime.verified_cli_draft(result, action))
    equal(vnodes[0], vnodes[1], 'Historical SQLite vnode across CLI reopen')
    if reader.live:
        metadata = library_file.stat()
        equal(vnodes[0], (metadata.st_dev & 0xFFFFFFFF, metadata.st_ino), 'Original SQLite vnode')
    equal(drafts[0], drafts[1], 'Historical CLI draft after reopen')
    stored = runtime.validate_database(raw_db, drafts[1], runtime.CLI_TITLE, runtime.CLI_BODY)
    equal(encoded(stored), encoded(cli['storedDrafts']), 'Retained CLI SQLite fixture rows')


def historical_checkout(output, phase):
    if output.parent.name != phase or output.parent.parent.name != 'build':
        raise ValueError('Invalid historical '+phase+' output location')
    return output.parents[2]


def runtime_argv(step):
    argv = step.get('argv')
    if type(argv) is not list or len(argv) != 13 or not all(type(arg) is str for arg in argv):
        raise ValueError('Malformed historical runtime process arguments')
    return argv


def verify_vm_invocation(step, checkout, python, candidate, manifest_pin, evidence):
    # The staged VM configuration is deliberately not retained. Validate
    # its recorded argument lexically without trying to read the file.
    config = original_path(runtime_argv(step)[4])
    command = [original_path(python), '-B', checkout/'tool/package_release_vm.py', '--config', config,
               '--app', candidate/'Meshchan.app', '--signed-info', candidate/dmg.SIGNED_MANIFEST,
               '--expected-signed-info-sha256', manifest_pin, '--evidence', evidence]
    verify_report_fields(step, {'cwd': str(checkout), 'argv': list(map(str, command))}, 'Historical VM invocation')
    return config


def verify_replacement_invocation(step, checkout, python, candidate, manifest_pin, workspace, config):
    timeout = runtime_argv(step)[-1]
    try:
        build.command_timeout(timeout)
    except (ValueError, argparse.ArgumentTypeError) as error:
        raise ValueError('Invalid historical replacement timeout') from error
    command = [original_path(python), '-B', checkout/'tool/release_signed_replacement.py', '--signed-root', candidate,
               '--signed-info-sha256', manifest_pin, '--output', workspace, '--vm-config', config, '--timeout', timeout]
    verify_report_fields(step, {'cwd': str(checkout), 'argv': list(map(str, command))},
                         'Historical replacement invocation')


def verify_vm(reader, ref, base, evidence, result, root, info, manifest_pin):
    verify_report_fields(result, {'status': 'PASS', 'signingProfile': dmg.PROFILE,
                                   'receiptSha256': ref['sha256']}, 'Signed VM process result')
    vm = reader.report(base, ref, evidence/'runtime.json')
    inventory = signing.inventory_part(info['payloadInventory'], 'Meshchan.app')
    verify_report_fields(vm, {
        'status': 'PASS', 'signingProfile': dmg.PROFILE, 'guestRun': result['guestRun'],
        'app': str(root/'Meshchan.app'), 'signedInfoSha256': manifest_pin, 'identity': info['identity'],
        'appInventorySha256': sha(encoded(inventory)), 'guestSigningIdentity': info['signature']['identity'],
        **dict.fromkeys(('guestInventoryBefore', 'guestInventoryAfter', 'guestSignature', 'guestSignatureAfter',
                         'guestObserverTransfer', 'guestObserverAfter'), 'PASS'),
        'guestExecutorExit': 0, 'guestLockReleased': True,
    }, 'Retained signed VM receipt')
    runtime.verify_vm_runtime_evidence(vm, reader.directory(evidence), inventory)
    return vm


def verify_replacement(reader, root, workspace, receipt, result, info, manifest_pin):
    evidence = workspace/'evidence'
    path = evidence/'replacement-receipt.json'
    ref = receipt['modifiedLibraryReport']
    verify_report_fields(result, {'status': 'PASS', 'signingProfile': dmg.PROFILE, 'receipt': str(path),
                                   'receiptSha256': ref['sha256']}, 'Retained replacement process')
    replacement = reader.report(workspace, ref, path)
    verify_report_fields(replacement, {
        **signing.LOCAL_SCHEMA, 'status': 'PASS', 'signedInfoSha256': manifest_pin, 'signedRoot': str(root),
        'identity': info['identity'], 'finalIntegrity': 'PASS',
    }, 'Accepted local replacement')
    cli, app = replacement['cli'], replacement['app']
    verify_report_fields(cli, {'status': 'PASS', 'exitCode': 0}, 'Replacement CLI')
    verify_report_fields(app, {'status': 'PASS', 'exitCode': 0, 'guestExecutorExit': 0,
                               'guestLockReleased': True, 'pidAbsent': True}, 'Replacement App')
    verify_steps(reader, replacement, workspace, evidence, 'PASS')
    for field in ('log', 'stderrLog', 'pidReceipt'):
        scope = workspace/'cli working directory' if field == 'pidReceipt' else evidence/'logs'
        path = relative_reference(workspace, cli[field], scope=scope)
        reader.bytes(path, cli[field+'Sha256'])
    required = {'session.json', 'refresh-state.json', 'Release/app.stdout', 'Release/app.stderr',
                'Release/app.pid', 'Release/app.exit', 'Release/synthetic-ports.png'}
    equal(required, set(app['evidence']), 'Retained replacement VM evidence')
    for name, pin in app['evidence'].items():
        reader.bytes(evidence/'app-vm'/name, pin)
    # Select the replacement evidence by role. The executor's launch claim
    # is a transient link to an ownership token, outside the receipt's files.
    fixture = evidence/'app-vm/Release/fixture'
    reader.directory(fixture)
    reader.file(fixture/'meshchan.sqlite')
    reader.file(evidence/'app-vm/Release/app-supervisor.log')
    source_root = evidence/'libserialport-source'
    reader.directory(source_root)
    rebuilt = replacement['replacement']
    reader.entry(source_root/SOURCE_FILES[0], {'sha256': rebuilt['patch']['patchedSourceSha256']})
    equal({APP_LIBRARY, CLI_LIBRARY}, set(rebuilt['libraries']), 'Replacement library evidence set')
    for filename, name in (('app-library.dylib', APP_LIBRARY), ('cli-library.dylib', CLI_LIBRARY)):
        library = rebuilt['libraries'][name]
        verify_report_fields(library, {'path': name}, 'Replacement library path')
        reader.entry(source_root/filename, {'sha256': library['rebuiltSha256']})
    modified = product_inventory(reader.directory(workspace/'user products'))
    equal(replacement['modifiedInventorySha256'], sha(encoded(modified)), 'Modified product inventory')
    source = replacement['sourceArchive']
    verify_report_fields(source, {'materialsManifestSha256': info['upstream']['materialsManifestSha256']},
                         'Replacement material source')
    src = relative_reference(root, source['path'], scope=root/'materials')
    reader.entry(src, {'sha256': source['sha256'], 'size': source['size']})
    reader.entry(evidence/'libserialport-source.tar.gz', {'sha256': source['sha256'], 'size': source['size']})
    for name in ('user-app.entitlements', 'user-cli.entitlements'):
        reader.file(evidence/name)


def verify_tool_snapshot(reader, root, source, expected_names):
    if (type(source['gitCommit']) is not str or not re.fullmatch('[0-9a-f]{40}', source['gitCommit'])
            or type(source['workingTree']) is not list or any(type(name) is not str for name in source['workingTree'])):
        raise ValueError('Malformed engineering tool provenance')
    equal(set(expected_names), set(source['inputs']), 'Complete engineering tool input set')
    for name, entry in source['inputs'].items():
        if type(entry) is not dict or set(entry) != {'type', 'mode', 'size', 'sha256'}:
            raise ValueError('Incomplete engineering tool file identity: '+name)
        path = relative_reference(root, name)
        reader.entry(path, entry)


def accepted_local(reader, manifest_ref, acceptance_ref):
    manifest_file, manifest_pin = manifest_ref
    receipt_file, receipt_pin = acceptance_ref
    root = manifest_file.parent
    output = root.parent.parent
    evidence = receipt_file.parent
    if (manifest_file.name != dmg.SIGNED_MANIFEST or root.parent.name != 'signed'
            or receipt_file.name != 'signing-receipt.json' or evidence.parent != output/'evidence'
            or not evidence.name.startswith('check-')):
        raise ValueError('Use the independent check from the selected local signing run')
    raw_manifest = reader.bytes(manifest_file, manifest_pin)
    info = runtime.parse_signed_info(raw_manifest)
    verify_report_fields(info, {**signing.LOCAL_SCHEMA, 'inventoryExclusions': [dmg.SIGNED_MANIFEST]},
                         'Local manifest')
    full = signing.manifest_inventory(info, raw_manifest)
    receipt = json_object(reader.bytes(receipt_file, receipt_pin))
    bound = {
        **signing.LOCAL_SCHEMA, 'upstreamStatus': 'PASS', 'signedRoot': str(root),
        'signedInfo': {'path': manifest_file.relative_to(output).as_posix(), 'sha256': manifest_pin},
        'upstream': info['upstream'], 'identity': info['identity'], 'signingIdentity': info['signature']['identity'],
    }
    verify_report_fields(receipt, {
        **bound, 'command': 'check', 'status': 'PASS', **dict.fromkeys(signing.ACCEPTANCE_GATES, 'PASS'),
        'relocatedInventorySha256': sha(encoded(full)),
    }, 'Independent local acceptance')
    equal(info['signingTool']['inputs'], receipt['signingTool']['inputs'], 'Accepted local signing tools')
    reader.tree(root, full)
    verify_tool_snapshot(reader, root/'signing-source', info['signingTool'], signing.SIGNING_SOURCES)
    verify_report_fields(info['policy'], {
        'path': 'tool/release_signing_policy.json',
        'sha256': info['signingTool']['inputs']['tool/release_signing_policy.json']['sha256'],
    }, 'Accepted signing policy')

    signed = json_object(reader.bytes(output/'evidence/signing-receipt.json'))
    verify_report_fields(signed, {
        **bound, 'command': 'sign', 'status': 'SIGNED', 'signatureStatus': 'PASS',
        'materialTransformStatus': 'PASS', 'signingTool': info['signingTool'],
    }, 'Original signing result')
    read_ledger(reader, output, signed['processLedger'], output/'evidence', status='SIGNED')
    workspace = original_path(receipt['workspace'])
    relocated = workspace/'relocated products'
    cli_workspace = workspace/'cli workspace'
    reader.tree(relocated, full)
    reader.directory(cli_workspace)
    ledger, logs = read_ledger(reader, output, receipt['processLedger'], evidence)
    cli = reader.report(output, receipt['cliReport'], evidence/'cli-runtime.json')
    verify_report_fields(cli, {'signingProfile': dmg.PROFILE, 'signedInfoSha256': manifest_pin,
                               'relocatedRoot': str(relocated)}, 'Accepted local CLI')
    verify_cli(reader, cli, relocated/'meshctl', cli_workspace, info['identity'], ledger, logs)
    checkout = historical_checkout(output, 'phase-1e6')
    python = receipt['environment']['python']['path']
    config = verify_vm_invocation(signing.process_step(ledger, 'signed-vm-app-runtime'), checkout, python,
                                  relocated, manifest_pin, evidence/'vm-app')
    replacement = workspace/'user modified products'
    verify_replacement_invocation(signing.process_step(ledger, 'signed-user-replacement'), checkout, python,
                                  root, manifest_pin, replacement, config)
    verify_vm(reader, receipt['vmAppReport'], output, evidence/'vm-app',
              build.material_result(logs['signed-vm-app-runtime']['log'].decode()), relocated, info, manifest_pin)
    verify_replacement(reader, root, replacement, receipt,
                       build.material_result(logs['signed-user-replacement']['log'].decode()), info, manifest_pin)
    reader.directory(evidence)
    return info, full


def verify_package_runtime(reader, root, receipt, evidence, extracted, app_inventory, identity):
    ledger, logs = read_ledger(reader, root, receipt['processLedger'], evidence)
    static = reader.report(root, receipt['staticReport'], evidence/'relocated-products.json')
    cli = reader.report(root, receipt['cliReport'], evidence/'cli-runtime.json')
    vm = reader.report(root, receipt['vmAppReport'], evidence/'vm-app/runtime.json')
    verify_report_fields(static, {'status': 'PASS'}, 'Upstream static product report')
    equal(static, json_object(logs['relocated-products']['log']), 'Upstream static process output')
    app, bundle = extracted/'Meshchan.app', extracted/'meshctl'
    static_step = signing.process_step(ledger, 'relocated-products')
    equal([str(app), str(bundle)], static_step['argv'][-2:], 'Upstream static invocation')

    cwd = extracted.parent/'runtime workspace'
    data = cwd/'owned CLI data'
    database = data/'meshchan.sqlite'
    reader.directory(cwd)
    raw_db = reader.bytes(database, cli['databaseSha256'])
    verify_report_fields(cli, {'status': 'PASS', 'database': str(database)}, 'Upstream CLI report')
    executable, library = bundle/'bin/meshctl', bundle/build.CLI_SQLITE_LIBRARY
    version = signing.process_step(ledger, 'cli-version')
    verify_report_fields(version, {'cwd': str(cwd), 'argv': [str(executable), '--version']}, 'Upstream CLI version')
    equal('meshctl '+identity['productVersion'], logs['cli-version']['log'].decode().strip(), 'Upstream CLI version')
    title, body = 'Packaging smoke', 'Offline sample 中文\r\nsecond line\n'
    drafts = []
    for step, action, row in zip(('cli-write', 'cli-read'), ('create', 'show'), cli['processes'], strict=True):
        actual = json_object(logs[step]['log'])
        verify_report_fields(row, {'name': step, 'sqliteLoadedFrom': str(library), 'report': actual},
                             'Upstream CLI process result')
        arguments = ['--title', title, '--body', body] if action == 'create' else ['--id', drafts[0]['id']]
        invocation = [executable, '--data-dir', data, 'draft', action, *arguments, '--json']
        verify_report_fields(signing.process_step(ledger, step), {'argv': list(map(str, invocation)), 'cwd': str(cwd)},
                             'Upstream CLI '+step)
        verify_report_fields(actual, {'command': 'draft', 'action': action, 'exitCode': 0,
                                      'operationSucceeded': True, 'schemaVersion': 1}, 'Upstream CLI result')
        verify_report_fields(actual['storageClose'], {'state': 'closed'}, 'Upstream CLI storage close')
        loaded = re.findall(r'^dyld\[\d+\]: <[0-9A-Fa-f-]+> (/.+)$', logs[step]['stderrLog'].decode(), re.MULTILINE)
        if str(library) not in {name.removeprefix('/System/Volumes/Data') for name in loaded}:
            raise ValueError('Runtime trace lacks the upstream extracted SQLite: '+step)
        drafts.append(actual['draft'])
    equal(drafts[0], drafts[1], 'Upstream reopened CLI draft')
    equal(encoded(runtime.validate_database(raw_db, drafts[1], title, body)),
          encoded(cli['storedDrafts']), 'Upstream CLI fixture rows')

    vm_step = signing.process_step(ledger, 'vm-app-runtime')
    equal(['--app', str(app), '--package-info', str(extracted/'package-info.json'),
           '--evidence', str(evidence/'vm-app')], vm_step['argv'][-6:], 'Upstream VM product arguments')
    vm_entry = build.material_result(logs['vm-app-runtime']['log'].decode())
    verify_report_fields(vm_entry, {'status': 'PASS', 'guestRun': vm['guestRun']}, 'Upstream VM process')
    verify_report_fields(vm, {
        'status': 'PASS', 'app': str(app), 'identity': identity,
        'packageInfoSha256': receipt['packageInfo']['sha256'], 'appInventorySha256': sha(encoded(app_inventory)),
        'guestInventoryBefore': 'PASS', 'guestInventoryAfter': 'PASS', 'guestSignature': 'PASS',
        'guestExecutorExit': 0,
    }, 'Upstream VM report')
    # The original packager predates the lock field. The independent
    # recheck must have it and any supplied observation must match.
    if receipt['command'] == 'check' or 'guestLockReleased' in vm:
        verify_report_fields(vm, {'guestLockReleased': True}, 'Upstream VM lock release')
    write, read = vm['processes']
    for row in (write, read):
        verify_report_fields(row, {'exitCode': 0, 'pidAbsentAfterNormalExit': True}, 'Upstream VM App process')
    equal(write['draft'], read['draft'], 'Upstream reopened App draft')
    raw_vm_db = reader.bytes(evidence/'vm-app/vm-fixture.sqlite', vm['guestDatabaseSha256'])
    runtime.validate_database(raw_vm_db, read['draft'], runtime.APP_TITLE, runtime.APP_BODY)
    reader.directory(evidence/'vm-app')
    return static


def frozen_build(reader, upstream, identity):
    source = original_path(upstream['sourceCheckout'])
    run = relative_reference(source, upstream['buildRun'], scope=source/'build/phase-1e4')
    equal(upstream['buildRun'], run.relative_to(source).as_posix(), 'Frozen build run name')
    info = json_object(reader.bytes(run/'build-info.json', upstream['buildInfoSha256']))
    fields = {
        'formatVersion': 1, 'sourceCommit': upstream['sourceCommit'], 'recipeVersion': upstream['buildRecipeVersion'],
        'runIdentity': upstream['buildRun'], 'identity': identity, 'buildStatus': 'PASS', 'productChecksStatus': 'PASS',
        'engineeringDirtyMode': False, 'workingTree': '',
    }
    verify_report_fields(info, fields, 'Frozen build information')
    if type(info['recipeVersion']) is not int or info['recipeVersion'] < 55:
        raise ValueError('Retention requires the complete recipe 55 or newer source and runtime contract')
    proof = {name: reader.reference(source, ref, run/'evidence'/name, scope=run/'evidence')
             for name, ref in info['evidence'].items()}
    receipt = json_object(proof['build-receipt.json'])
    evidence = run/'evidence'
    verify_steps(reader, receipt, source, evidence, 'PASS')
    verify_report_fields(receipt, {
        'formatVersion': 1, 'sourceCommit': info['sourceCommit'], 'recipeVersion': info['recipeVersion'],
        'inputsUnchangedAcrossBuilds': True, 'app': info['app'], 'cli': info['cli'],
        'engineeringDirtyMode': False, 'workingTree': '',
        'runnerSha256': sha(proof['run_build.py']),
        'candidateInventoriesSha256': sha(proof['candidate-inventories.json']),
        'candidateChecksumsSha256': sha(proof['candidate-checksums.txt']),
        'prebuildIdentitiesSha256': sha(proof['prebuild-identities.json']),
        'resolvedGraphSha256': sha(proof['resolved-graph.json']),
        'compilationInputsSha256': sha(proof['compilation-input-hashes.json']),
        'compilerInputsSha256': sha(proof['compiler-inputs.json']),
        'productChecksSha256': sha(proof['product-checks.json']),
    }, 'Frozen build process ledger')
    equal(receipt['steps'], info['recipe'], 'Frozen build recipe')
    original_inputs = proof['compilation-input-hashes.json']
    for name in ('inputs-before-configuration.json', 'inputs-after-cli.json', 'inputs-after-app.json'):
        equal(original_inputs, proof[name], 'Frozen build snapshot '+name)
    compiler = json_object(proof['compiler-inputs.json'])
    for name, pin in compiler['depfileHashes'].items():
        reader.entry(relative_reference(evidence, name, scope=evidence/'compiler'), {'sha256': pin})
    native_hooks = reader.directory(run/'native-hooks')
    equal(receipt['nativeHookCacheSha256'], sha(encoded(product_inventory(native_hooks))), 'Frozen native hook evidence')

    prebuild = json_object(proof['prebuild-identities.json'])
    equal(set(prebuild['source']), set(prebuild['sourceMetadata']), 'Frozen source metadata set')
    equal(sha(encoded(prebuild['source'])), info['sourceInputIdentity'], 'Frozen source identity')
    # Recipe 55 has regular first-party source entries. Retain only the
    # explicit build inputs and let the snapshot carry the configuration.
    for name, pin in prebuild['source'].items():
        historical = relative_reference(source, name)
        path = reader.entry(historical, {'sha256': pin})
        equal(prebuild['sourceMetadata'][name], {
            'type': 'file', 'executable': bool(path.lstat().st_mode & 0o111),
        }, 'Frozen source executable bit for '+name)
    for name, pin in info['helperHashes'].items():
        reader.entry(relative_reference(source, name, scope=source/'tool'), {'sha256': pin})
    generated = prebuild['configuration']
    equal(generated, info['controlledConfiguration']['generated'], 'Frozen generated configuration identity')
    swift_packages = source/build.MACOS_EPHEMERAL/'Packages'
    for name, pin in generated.items():
        historical = relative_reference(source, name)
        entry = package.file_entry(reader.file(historical))
        actual = sha(encoded(entry)) if historical.is_relative_to(swift_packages) else entry['sha256']
        equal(pin, actual, 'Frozen configuration '+name)

    app, cli = build.product_paths(run)
    equal((app, cli), tuple(relative_reference(source, info[name], scope=run) for name in ('app', 'cli')),
          'Frozen product locations')
    inventories = json_object(proof['candidate-inventories.json'])
    reader.tree(app, inventories['app'])
    reader.tree(cli, inventories['cli'])
    verify_report_fields(info['materials'], {'status': 'PASS'}, 'Frozen materials phase')
    materials = original_path(info['materials']['arguments']['output'])
    if materials.parent != run:
        raise ValueError('Frozen materials output must be a direct child of the selected build')
    refs = info['materials']['references']
    equal(upstream['materialsManifestSha256'], refs['materials-manifest.json']['sha256'], 'Bound material manifest')
    for name, ref in refs.items():
        path = relative_reference(source, ref['path'], scope=run)
        equal(name, path.name, 'Frozen material evidence name')
        if name == 'materials-manifest.json':
            equal(materials/name, path, 'Frozen material manifest location')
        reader.entry(path, {'sha256': ref['sha256']})
    material = package.material_inventory(reader.directory(materials), upstream['materialsManifestSha256'],
                                          sha(proof['build-receipt.json']), info['sourceCommit'])
    return source, run, info, {'Meshchan.app': (app, inventories['app']), 'meshctl': (cli, inventories['cli']),
                               'materials': (materials, material)}


def verify_frozen_recheck(reader, source, run, receipt):
    verification = receipt['frozenVerification']
    verify_report_fields(verification, {
        'result': {'status': 'PASS', 'buildStatus': 'PASS', 'materialsStatus': 'PASS', 'run': receipt['buildRun']},
    }, 'Frozen product verification')
    equal(set(CHECKS), set(verification['ledgers']), 'Complete frozen verification gates')
    for name, reference in verification['ledgers'].items():
        path = relative_reference(source, reference['path'], scope=run/'evidence')
        if path.name != 'build-receipt.json' or path.parent.parent != run/'evidence' or not path.parent.name.startswith(name+'-'):
            raise ValueError('Frozen verification has an invalid process ledger path')
        ledger = reader.report(source, reference, path)
        verify_report_fields(ledger, {'formatVersion': 1}, 'Frozen verification ledger '+name)
        verify_steps(reader, ledger, source, path.parent, 'PASS')


def accepted_upstream(reader, signed_root, info, tool_snapshot):
    upstream = info['upstream']
    source, run, build_info, trees = frozen_build(reader, upstream, info['identity'])
    output = original_path(upstream['packageRun'])
    check_path = original_path(upstream['upstreamCheckReceipt'])
    original_pathname = output/'evidence/package-receipt.json'
    if (check_path.name != original_pathname.name or check_path.parent.parent != output/'evidence'
            or not check_path.parent.name.startswith('check-')):
        raise ValueError('Use the independent upstream package check receipt')
    original_pin, check_pin = upstream['originalPackageReceiptSha256'], upstream['upstreamCheckReceiptSha256']
    original = json_object(reader.bytes(original_pathname, original_pin))
    checked = json_object(reader.bytes(check_path, check_pin))
    signing.matching_package_receipts(original, checked, {
        'sourceCheckout': str(source), 'buildRun': upstream['buildRun'], 'sourceCommit': build_info['sourceCommit'],
        'identity': info['identity'],
    }, original_pin)
    verify_report_fields(original, {'archive': upstream['archive'], 'packageInfo': upstream['packageInfo'],
                                    'packagingTool': upstream['originalPackagingTool']}, 'Original package identity')
    verify_report_fields(checked, {'packagingTool': upstream['upstreamVerifier']}, 'Independent package tool identity')
    top, _, _ = dmg.volume_names(info)
    stage = output/'stage'/top
    equal(str(stage), original['stage'], 'Original package stage location')
    archive = upstream['archive']
    archive_path = output/'archives'/(top+'.tar')
    equal(archive_path, relative_reference(output, archive['path']), 'Original package archive location')
    reader.entry(archive_path, {name: value for name, value in archive.items() if name != 'path'})
    package_info = upstream['packageInfo']
    package_path = stage/'package-info.json'
    raw = reader.reference(output, package_info, package_path)
    reader.entry(package_path, {name: value for name, value in package_info.items() if name != 'path'})
    archive_info = json_object(raw)
    verify_report_fields(archive_info, {
        'formatVersion': 1, 'identity': info['identity'], 'sourceCommit': build_info['sourceCommit'],
        'buildRecipeVersion': build_info['recipeVersion'], 'sourceCheckout': str(source), 'buildRun': upstream['buildRun'],
        'inventoryExclusions': ['package-info.json'], 'toolInputs': original['packagingTool']['inputs'],
    }, 'Original engineering package manifest')
    package_inventory = archive_info['payloadInventory']
    equal(False, 'package-info.json' in package_inventory, 'Package inventory self-exclusion')
    full = package_inventory | {'package-info.json': package.bytes_entry(raw)}
    reader.tree(stage, full)
    verify_tool_snapshot(reader, stage/'packaging-source', original['packagingTool'], package.SOURCES)
    verify_tool_snapshot(reader, tool_snapshot, checked['packagingTool'], package.SOURCES)
    for role, (path, inventory) in trees.items():
        equal(inventory, signing.inventory_part(package_inventory, role), 'Upstream package '+role)
        verify_report_fields(archive_info['locations'][role], {
            'sourceRelativeToRun': path.relative_to(run).as_posix(),
            'stageRelativeToPackageRun': (stage/role).relative_to(output).as_posix(),
            'archiveMemberAndExtractionRelativePath': top+'/'+role,
        }, 'Upstream package location mapping')
    for name, pin in archive_info['upstreamSha256'].items():
        if name == 'materials-manifest.json':
            equal(upstream['materialsManifestSha256'], pin, 'Original package materials')
            continue
        equal(True, name in package.INDEXES, 'Original package build index name')
        reader.entry(relative_reference(run, name), {'sha256': pin})
        reader.entry(stage/'provenance'/Path(name).name, {'sha256': pin})
    equal(set((*package.INDEXES, 'materials-manifest.json')), set(archive_info['upstreamSha256']),
          'Original package build provenance scope')
    for name, pin in (('package-info.json', package_info['sha256']), ('package-receipt.json', original_pin),
                      ('package-check-receipt.json', check_pin)):
        reader.entry(signed_root/'upstream-provenance'/name, {'sha256': pin})
    reader.entry(signed_root/'materials/materials-manifest.json', {'sha256': upstream['materialsManifestSha256']})

    for record, receipt_path in ((original, original_pathname), (checked, check_path)):
        verify_frozen_recheck(reader, source, run, record)
        extract = original_path(record['extractRoot'])
        extracted = extract/top
        equal(str(extracted), record['extracted'], 'Package extraction location')
        reader.tree(extracted, full)
        verify_package_runtime(reader, output, record, receipt_path.parent, extracted,
                               trees['Meshchan.app'][1], info['identity'])
    return build_info


def verify_process_order(ledger, signatures):
    attach = signing.process_step(ledger, 'attach-image')
    detach = signing.process_step(ledger, 'detach-image')
    parse = datetime.fromisoformat
    attach_finished, detach_started, detach_finished = (
        parse(attach['finishedAt']), parse(detach['startedAt']), parse(detach['finishedAt']))
    names = {'verify-app-nested'}
    for seq, item in enumerate(signatures, start=1):
        step = f'verify-{seq:02d}-{item["role"]}'
        names.add(step+'-requirement')
        for architecture in item['slices']:
            names.update((step+'-'+architecture+'-display', step+'-'+architecture+'-entitlements'))
    equal(names, {step['name'] for step in ledger['steps'] if step['name'].startswith('verify-') and
                  step['name'] != 'verify-image'}, 'Complete extracted code signature process set')
    for name in names:
        step = signing.process_step(ledger, name)
        if not attach_finished <= parse(step['startedAt']) <= parse(step['finishedAt']) <= detach_started:
            raise ValueError('Extracted code signature verification escaped the owned mount window')
    for step in ledger['steps']:
        if step['name'].startswith(('signed-native-', 'signed-cli-', 'dmg-vm-', 'compile-cli-')):
            if parse(step['startedAt']) < detach_finished:
                raise ValueError('Extracted product check preceded owned image detach')


def verify_image_signatures(ledger, logs, candidate, signature, policy):
    """Bind the retained codesign observations to the extracted products."""
    codesign = '/usr/bin/codesign'
    verify = [codesign, '--verify', '--strict', '--all-architectures', '--verbose=2']

    def command(name, argv):
        verify_report_fields(signing.process_step(ledger, name), {'argv': argv},
                             'Historical codesign invocation '+name)

    if release_signing.policy_profile(policy) != dmg.PROFILE:
        raise ValueError('Expected the accepted local signing policy')
    command('verify-app-nested', [*verify, '--deep', str(candidate/'Meshchan.app')])
    for index, (item, recorded, order) in enumerate(zip(policy, signature['items'], signature['order'], strict=True), 1):
        prefix = f'verify-{index:02d}-{item.role}'
        target = str(candidate/item.path)
        verify_report_fields(recorded, item.record(), 'Historical codesign item')
        verify_report_fields(order, item.record(), 'Historical codesign order')
        slices = recorded['slices']
        equal(set(order['architectures']), set(slices), 'Historical codesign architecture set')
        if not slices:
            raise ValueError('Missing historical codesign architecture observations: '+target)
        command(prefix+'-requirement', [*verify, *item.bundle_args(), target])
        for arch, saved in slices.items():
            name = prefix+'-'+arch
            display = [codesign, '--display', '--architecture', arch, *item.bundle_args()]
            command(name+'-display', [*display, '--verbose=4', target])
            command(name+'-entitlements', [*display, '--entitlements', '-', '--xml', target])
            properties = logs[name+'-display']['stderrLog'].decode()

            def field(key):
                return release_signing.required_value(properties, key)

            for key, expected in (('Executable', str(candidate/item.binary)), ('Total signatures', '1'),
                                  ('Chosen signature', '1'), ('Signature', 'adhoc')):
                equal(expected, field(key), 'Historical codesign '+key)
            flags = re.findall(r'^CodeDirectory [^\n]*?\bflags=0x([a-fA-F0-9]+)\([^\n]*\)[^\n]*'
                               r'\blocation=embedded$', properties, re.MULTILINE)
            cdhash = field('CDHash')
            if (len(flags) != 1 or not re.fullmatch(r'[0-9a-f]{40}', cdhash)
                    or re.search(r'^(?:Authority|Timestamp)=', properties, re.MULTILINE)):
                raise ValueError('Invalid historical ad hoc CodeDirectory or signing metadata: '+target)
            flags = int(flags[0], 16)
            team = field('TeamIdentifier')
            raw = logs[name+'-entitlements']['log'].decode()
            observed = {'identifier': field('Identifier'), 'team': None if team == 'not set' else team,
                        'authorityChain': [], 'timestamp': None, 'signatureSlots': 1,
                        'flags': flags, 'runtime': bool(flags & release_signing.CS_RUNTIME),
                        'adhoc': bool(flags & release_signing.CS_ADHOC), 'cdhash': cdhash,
                        'entitlements': disk.parse_plist(raw, 'historical codesign entitlements') if raw.strip() else {}}
            release_signing.verify_signature_values(item, signature['identity'], observed)
            equal(set(observed), set(saved), 'Historical codesign slice fields '+name)
            verify_report_fields(observed, saved, 'Historical codesign slice '+name)


def verify_image_structure(ledger, logs, image, observation):
    for name, command in (('image-info', 'imageinfo'), ('verify-image', 'verify')):
        verify_report_fields(signing.process_step(ledger, name), {
            'argv': [disk.HDIUTIL, command, '-plist', image],
        }, 'Historical image structure process '+name)
    details = disk.parse_plist(logs['image-info']['log'].decode(), 'historical hdiutil imageinfo')
    verify_report_fields(details, {'Format': disk.IMAGE_FORMAT, 'Format Description': disk.IMAGE_TYPE,
                                   'Class Name': 'CUDIFDiskImage'}, 'Historical disk image information')
    verify_report_fields(details['Properties'], {'Checksummed': True, 'Compressed': True, 'Encrypted': False},
                         'Historical disk image properties')
    partitions = details['partitions']['partitions']
    if type(partitions) is not list or any(type(part) is not dict for part in partitions):
        raise ValueError('Invalid historical disk image partition information')
    equal([{disk.FILESYSTEM: ''}], [part['partition-filesystems'] for part in partitions
                                  if 'partition-filesystems' in part], 'Historical disk image data partition')
    checksum = disk.parse_plist(logs['verify-image']['log'].decode(), 'historical hdiutil verify')
    expected = checksum.get('expected')
    if (type(expected) is not dict or expected.get('Checksum Type') != 'CRC32'
            or type(expected.get('Checksum Value')) is not str
            or re.fullmatch(r'\$[0-9A-Fa-f]{8}', expected['Checksum Value']) is None):
        raise ValueError('Missing historical disk image structural checksum')
    verify_report_fields(checksum, {'calculated': expected}, 'Historical disk image verification')
    equal(expected, observation['checksum'], 'Historical disk image receipt checksum')
    container = 'inspect-container-signature'
    verify_report_fields(signing.process_step(ledger, container),
                         {'argv': ['/usr/bin/codesign', '--display', image]}, 'Historical unsigned container process')
    equal(os.fsencode(image)+b': code object is not signed at all', logs[container]['stderrLog'].strip(),
          'Historical unsigned container observation')


def verify_image_volume(ledger, logs, mount):
    command = signing.process_step(ledger, 'volume-info')
    verify_report_fields(command, {'argv': [disk.DISKUTIL, 'info', '-plist', mount['mountPoint']]},
                         'Historical image volume process')
    whole, volume = mount['wholeDevice'], mount['volumeDevice']
    if disk.WHOLE_DISK.fullmatch(whole) is None or re.fullmatch(re.escape(whole)+r's[0-9]+', volume) is None:
        raise ValueError('Invalid historical image volume devices')
    reported = disk.parse_plist(logs['volume-info']['log'].decode(), 'historical diskutil info')
    verify_report_fields(reported, {
        'BusProtocol': 'Disk Image', 'DeviceNode': volume, 'ParentWholeDisk': Path(whole).name,
        'MountPoint': mount['mountPoint'], 'FilesystemType': 'hfs', 'FilesystemName': disk.FILESYSTEM,
        'VolumeName': mount['name'], 'VolumeUUID': mount['volumeUuid'],
        'Writable': False, 'WritableVolume': False, 'WritableMedia': False,
    }, 'Historical read-only disk image volume')
    permissions = reported.get('GlobalPermissionsEnabled')
    if type(permissions) is not bool:
        raise ValueError('Missing historical disk image volume ownership information')
    verify_report_fields(mount['volumeRoot'], {'globalPermissionsEnabled': permissions},
                         'Historical disk image volume ownership')


def verify_image_record(reader, record, output, info, layout, expected, policy, *, independent):
    schema = {
        **dmg.SIGNATURE_POLICY, 'formatVersion': 1, **expected, 'dmgTool': layout.manifest['dmgTool'],
        **dict.fromkeys(IMAGE_GATES, 'PASS'),
        'command': 'check' if independent else 'create', 'status': 'PASS' if independent else 'CREATED',
        'stageStatus': 'NOT_RUN' if independent else 'PASS',
        **dict.fromkeys(('cliStatus', 'vmAppStatus'), 'PASS' if independent else 'NOT_RUN'),
        'residualAttachments': [],
    }
    if layout.manifest.get('payloadProfile') == dmg.PUBLIC_PAYLOAD:
        schema.update(payloadProfile=dmg.PUBLIC_PAYLOAD,
                      publicSignedInfoSha256=layout.manifest['signedInfoSha256'])
    verify_report_fields(record, schema, 'Independent DMG acceptance' if independent else 'DMG creation')
    if independent:
        verify_report_fields(record, {'selectedImage': {key: expected['image'][key] for key in ('path', 'sha256')}},
                             'Selected independent DMG')
    workspace = original_path(record['workspace'])
    owned = reader.directory(workspace)
    mount = workspace/'readonly volume'
    if 'readonly volume' in os.listdir(owned):
        raise ValueError('Retained DMG workspace still contains the historical mount point')
    verify_report_fields(record, {'mountPoint': str(mount)}, 'Owned DMG mount location')
    verify_report_fields(record['mount'], {
        'mountPoint': str(mount), 'readOnly': True, 'filesystem': expected['image']['filesystem'],
        'name': expected['image']['volumeName'],
    }, 'Owned image mount')
    verify_report_fields(record['ownedAttachment'], {'path': expected['image']['path'], 'writable': False},
                         'Owned image attachment')
    verify_report_fields(record['imageVerification'], {
        'filesystem': disk.FILESYSTEM, 'format': disk.IMAGE_FORMAT, 'formatDescription': disk.IMAGE_TYPE,
        'containerSignature': 'UNSIGNED',
    }, 'Historical image structure')
    candidate = workspace/'extracted payload'/layout.manifest['candidatePath']
    payload_pin = sha(encoded(layout.manifest))
    inventory_pin = sha(encoded(layout.inventory))
    verify_report_fields(record['extraction'], {
        'root': str(candidate.parent), 'candidateRoot': str(candidate), 'payloadManifestSha256': payload_pin,
        'inventorySha256': inventory_pin,
    }, 'Accepted DMG extraction')
    manifest = reader.reference(output, record['payloadManifest'], output/'evidence'/dmg.IMAGE_MANIFEST)
    equal(payload_pin, sha(manifest), 'Accepted image payload manifest')
    reader.tree(candidate.parent, layout.inventory)
    if not independent:
        reader.tree(output/'staging', layout.inventory)
    evidence = output/'evidence'
    ledger, logs = read_ledger(reader, output, record['processLedger'], evidence,
                               status=schema['status'], unsigned_image=True)
    signing.process_step(ledger, 'signed-native-mapping')
    verify_image_structure(ledger, logs, expected['image']['path'], record['imageVerification'])
    verify_image_volume(ledger, logs, record['mount'])
    verify_report_fields(signing.process_step(ledger, 'attach-image'), {
        'pid': record['attachChildPid'],
        'argv': [disk.HDIUTIL, 'attach', '-readonly', '-nobrowse', '-noautoopen',
                 '-mount', 'required', '-mountpoint', str(mount), '-plist', expected['image']['path']],
    }, 'Historical read-only image attachment')
    verify_report_fields(signing.process_step(ledger, 'detach-image'),
                         {'argv': [disk.HDIUTIL, 'detach', str(mount)]}, 'Historical owned image detach')
    static = reader.report(output, record['staticReport'], evidence/'static-products.json')
    verify_report_fields(static, {
        'status': 'PASS', 'signingProfile': dmg.PROFILE, 'productRoot': str(candidate),
        'inventorySha256': sha(encoded(signing.inventory_part(layout.inventory, layout.manifest['candidatePath']))),
        'signatures': info['signature']['items'], 'native': info['native'],
    }, 'Historical DMG static product report')
    verify_process_order(ledger, static['signatures'])
    verify_image_signatures(ledger, logs, candidate, info['signature'], policy)
    if independent:
        cli = reader.report(output, record['cliReport'], evidence/'cli-runtime.json')
        context = {'imageSha256': expected['image']['sha256'], 'signingProfile': dmg.PROFILE,
                   'signedInfoSha256': layout.manifest['signedInfoSha256']}
        verify_report_fields(cli, context, 'DMG CLI runtime binding')
        verify_cli(reader, cli, candidate/'meshctl', workspace/'cli workspace', info['identity'], ledger, logs)
        verify_vm_invocation(signing.process_step(ledger, 'dmg-vm-app-runtime'), historical_checkout(output, 'phase-1e7'),
                             record['environment']['pythonPath'], candidate, layout.manifest['signedInfoSha256'],
                             evidence/'vm-app')
        vm = verify_vm(reader, record['vmAppReport'], output, evidence/'vm-app',
                       build.material_result(logs['dmg-vm-app-runtime']['log'].decode()),
                       candidate, info, layout.manifest['signedInfoSha256'])
        binding = reader.report(output, record['vmImageBinding'], evidence/'vm-image-binding.json')
        verify_report_fields(binding, {**context, 'productRoot': str(candidate), 'guestRun': vm['guestRun'],
                                       'vmReceipt': record['vmAppReport']}, 'DMG VM image binding')
    reader.directory(evidence)
    return workspace


def accepted_image(reader, refs, info, full):
    asset, asset_pin = refs['dmg']
    acceptance_path, acceptance_pin = refs['dmg_acceptance']
    top, filename, volume = dmg.volume_names(info)
    if asset.name != filename or acceptance_path.name != 'dmg-acceptance.json' or acceptance_path.parent == asset.parent:
        raise ValueError('Use the selected image and its independent DMG acceptance receipt')
    accepted = json_object(reader.bytes(acceptance_path, acceptance_pin))
    verify_report_fields(accepted, {
        'formatVersion': 1, 'command': 'check', 'status': 'PASS', **dmg.SIGNATURE_POLICY,
        'selectedImage': {'path': str(asset), 'sha256': asset_pin},
    }, 'Selected independent DMG acceptance')
    asset_path = reader.file(asset)
    image_entry = package.file_entry(asset_path)
    equal(asset_pin, image_entry['sha256'], 'Externally selected DMG SHA-256')
    manifest_path, manifest_pin = refs['signed_manifest']
    receipt_path, receipt_pin = refs['local_acceptance']
    candidate = {'root': str(manifest_path.parent), 'manifestSha256': manifest_pin,
                 'localAcceptanceReceipt': str(receipt_path), 'localAcceptanceSha256': receipt_pin}
    expected = {
        'identity': info['identity'], 'upstream': info['upstream'], 'signingTool': info['signingTool'],
        'candidate': candidate, 'image': {'path': str(asset), **image_entry, 'volumeName': volume,
                                         'format': disk.IMAGE_FORMAT, 'filesystem': disk.FILESYSTEM},
    }
    output = asset.parent
    creation_path = output/'image-record.json'
    if 'image_record' in refs:
        equal(creation_path, refs['image_record'][0], 'Selected DMG creation record location')
    creation_pin = refs.get('image_record', (None, None))[1]
    created = json_object(reader.bytes(creation_path, creation_pin))
    snapshot = original_path(created['workspace'])/'extracted payload/dmg-source'
    tools = created['dmgTool']
    equal(accepted['dmgTool'], tools, 'Matching DMG tool identity')
    verify_tool_snapshot(reader, snapshot, tools, dmg.SOURCES)
    for name, entry in info['signingTool']['inputs'].items():
        equal(entry, tools['inputs'][name], 'Matching upstream signing source '+name)
    contents = {'dmg-source/'+name: reader.bytes(snapshot/name, entry['sha256'])
                for name, entry in tools['inputs'].items()}
    args = SimpleNamespace(candidate_sha256=manifest_pin, acceptance_sha256=receipt_pin)
    profile = accepted.get('payloadProfile')
    public = None
    if profile is not None:
        equal(dmg.PUBLIC_PAYLOAD, profile, 'Selected public payload profile')
        public_pin = accepted['publicSignedInfoSha256']
        verify_pin(public_pin)
        materials = reader.bytes(manifest_path.parent/dmg.MATERIAL_MANIFEST, info['upstream']['materialsManifestSha256'])
        public = dmg.public_candidate(info, full, materials, manifest_pin, retained_public_pin=public_pin)
    layout = dmg.layout(full, info, args, contents, tools, public=public)
    equal(top, layout.manifest['candidatePath'], 'Accepted DMG product location')
    payload_path = output/'evidence'/dmg.IMAGE_MANIFEST
    if 'image_payload' in refs:
        equal((payload_path, sha(encoded(layout.manifest))), refs['image_payload'], 'External image payload pin')
    policy = release_signing.parse_policy(contents['dmg-source/tool/release_signing_policy.json'])
    create_root = verify_image_record(reader, created, output, info, layout, expected, policy, independent=False)
    check_root = verify_image_record(reader, accepted, acceptance_path.parent, info, layout, expected, policy,
                                     independent=True)
    if create_root == check_root or create_root.is_relative_to(check_root) or check_root.is_relative_to(create_root):
        raise ValueError('Creation and independent acceptance must have distinct DMG workspaces')
    equal(created['imageVerification'], accepted['imageVerification'], 'Matching DMG structure observations')
    sums = output/'SHA256SUMS'
    if 'checksums' in refs:
        equal((sums, created['checksumFile']['sha256']), refs['checksums'], 'External SHA256SUMS pin')
    value = reader.reference(output, created['checksumFile'], sums)
    equal(f'{asset_pin}  {filename}\n'.encode(), value, 'Original SHA256SUMS bytes')
    return tools, expected['image']


def verify_chain(inputs, locate, *, live=False):
    """Return the required roots and independent identities for the pinned chain.

    The caller supplies an original-path map in both modes. Offline callers
    must map into the checked restoration and deny every unretained path.
    """
    optional = {'image_record', 'checksums', 'image_payload'}
    required = INPUTS | {'upstream_tool_snapshot'}
    if type(inputs) is not dict or not required <= inputs.keys() or inputs.keys() - required - optional:
        raise ValueError('Incomplete or unknown engineering handoff inputs')
    refs = {}
    for key in (inputs.keys() - {'upstream_tool_snapshot'}):
        reference = inputs[key]
        equal({'path', 'sha256'}, set(reference), 'Handoff pin fields for '+key)
        verify_pin(reference['sha256'])
        refs[key] = (original_path(reference['path']), reference['sha256'])
    snapshot = inputs['upstream_tool_snapshot']
    if set(snapshot) != {'path', 'commit'} or not re.fullmatch('[0-9a-f]{40}', snapshot['commit']):
        raise ValueError('Expected the independently reconstructed upstream tool snapshot identity')
    reader = RetainedRead(locate, live=live)
    info, full = accepted_local(reader, refs['signed_manifest'], refs['local_acceptance'])
    signed_root = refs['signed_manifest'][0].parent
    build_info = accepted_upstream(reader, signed_root, info, original_path(snapshot['path']))
    tools, image = accepted_image(reader, refs, info, full)
    return {'roots': reader.roots(), 'identities': {
        'product': info['identity'],
        'sourceCommit': build_info['sourceCommit'], 'buildRecipeVersion': build_info['recipeVersion'],
        'image': image,
        'originalPackagingTool': info['upstream']['originalPackagingTool'],
        'upstreamVerifier': info['upstream']['upstreamVerifier'],
        'upstreamVerifierSnapshotCommit': snapshot['commit'],
        'signingTool': info['signingTool'], 'dmgTool': tools,
    }}
