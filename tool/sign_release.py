#!/usr/bin/env python3
"""Prepare, sign, and independently accept an existing macOS arm64 package."""
import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace

import build_release as build
import package_release as package
from release_materials import (controlled_environment, digest, encoded, product_inventory,
                               release_reference, release_relative_path, release_run_path,
                               repository_source_hashes, require_material_file, sha)
from release_package_archive import check_payload, metadata_observations, new_extraction_root, prefixed
import release_signing

ROOT = build.ROOT
POLICY = ROOT/'tool/release_signing_policy.json'
PRODUCTS = ('Meshchan.app', 'meshctl')
RETAINED = (*PRODUCTS, 'materials', 'provenance', 'packaging-source')
UPSTREAM_GATES = ('frozenStatus', 'integrityStatus', 'cliStatus', 'vmAppStatus', 'postRuntimeIntegrityStatus')
ACCEPTANCE_GATES = ('signatureStatus', 'materialTransformStatus', 'cliStatus', 'vmAppStatus',
                    'modifiedLibraryStatus', 'postRuntimeIntegrityStatus')
LOCAL_SCHEMA = {'formatVersion': 2, 'signingProfile': release_signing.LOCAL_PROFILE}
SIGNING_SOURCES = tuple(sorted(set(package.SOURCES) | {
    'AGENTS.md', package.SKILL+'config.example.json',
    'tool/sign_release.py', 'tool/sign_release_test.py', 'tool/release_signing.py',
    'tool/release_signing_policy.json', 'tool/release_signed_runtime.py', 'tool/release_image_probe.c',
    'tool/release_signing_test.py', 'tool/release_signed_runtime_test.py',
    'tool/release_signed_replacement_test.py',
    'tool/release_signed_replacement.py', 'tool/rebuild_release_serial.py',
    'docs/releases/phase-1e3-licenses.md', 'docs/releases/phase-1e6-signing.md',
    'docs/releases/phase-1e6-user-library-replacement.md',
    'apps/meshchan_app/macos/Runner/Release.entitlements',
}))
SIGNATURE_METADATA = 'Record system-managed com.apple.provenance, if present. Reject other xattrs, ACLs, and file flags.'
SIGNED_README = b"""# Meshchan macOS local signing candidate

Keep Meshchan.app and the complete meshctl directory together with the
distribution materials. signed-product-info.json describes these candidate bytes.
The App and CLI carry local ad hoc code signatures. Apple notarization and
Developer ID distribution are deferred under the current engineering policy.
The indexes in upstream-provenance and provenance describe the upstream
engineering and build inputs. Follow the user library replacement guide in
signing-materials for a standalone test. The release signing guide assumes the
original checkout, which also contains the full documentation cited by the
archived signing-source files.
Release acceptance and later distribution steps use separate receipts.
"""

# Import the actual frozen checkout's validator. Its combined products() entry
# also runs an ad hoc DYLD probe, which belongs to the upstream check only.
NATIVE_VALIDATOR = """
import json, sys
from pathlib import Path
sys.path.insert(0, 'tool')
import build_release as b
from release_materials import sections

app, cli = map(Path, sys.argv[1:3])
env = b.controlled_environment()
b.check_app(app, sys.argv[3], int(sys.argv[4]))
app_loaders, assets = b.inspect_loaders(app, app/b.APP_RUNNER, env, app_assets=True)
cli_loaders = b.loader_check(cli, cli/'bin/meshctl', env)
native = {}
for name, bundle in (('meshchan_app', app), ('meshctl', cli)):
    native[name] = {}
    for stem, cli_name in (('libserialport_plus', 'liblibserialport_plus'), ('sqlite3', 'libsqlite3')):
        relative = (f'Contents/Frameworks/{stem}.framework/{stem}' if bundle == app
                    else f'lib/{cli_name}.dylib')
        binary = bundle/relative
        native[name][stem] = {'sections': sections(binary), 'sha256': b.digest(binary),
                              'path': relative}
print(json.dumps({'loaders': {'app': app_loaders, 'cli': cli_loaders},
                  'appNativeAssets': assets, 'appAotSnapshot': b.verify_app_aot(app, app_loaders, env),
                  'native': native}))
"""


@dataclass(frozen=True)
class Upstream:
    checkout: Path
    build_run: Path
    package_run: Path
    stage: Path
    top: str
    info: dict
    inventory: dict
    protected: tuple
    build_roots: tuple[Path, ...]
    provenance: dict
    historical_files: dict
    static_report: dict


def bound_json(root, relative, pin):
    path = require_material_file(root, relative)
    data = path.read_bytes()
    package.equal(pin, sha(data), 'Bound JSON SHA-256 for '+relative)
    result = json.loads(data, object_pairs_hook=release_signing.policy_object)
    if type(result) is not dict:
        raise ValueError('Expected JSON object: '+relative)
    return result, data


def matching_package_receipts(original, current, source_fields, original_pin):
    for command, data in (('package', original), ('check', current)):
        package.verify_report_fields(data, {
            'formatVersion': 1, 'command': command, 'status': 'PASS',
            **dict.fromkeys(UPSTREAM_GATES, 'PASS'), **source_fields,
        }, 'Upstream '+command+' receipt')
    package.verify_report_fields(current, {
        'originalPackageReceiptSha256': original_pin,
        **{key: original[key] for key in ('archive', 'packageInfo', 'stage')},
    }, 'Selected package recheck')


def evidence_json(root, reference):
    path = package.canonical(root/reference['path'])
    if not path.is_relative_to(root):
        raise ValueError('Evidence is outside its selected root: '+str(path))
    return bound_json(root, path.relative_to(root).as_posix(), reference['sha256'])[0]


def evidence_at(root, reference, path):
    package.equal(path, package.canonical(root/reference['path']), 'Evidence location for '+path.name)
    return evidence_json(root, reference)


def require_ref(root, path, expected_sha):
    reference = build.ref(root, path)
    package.equal(expected_sha, reference['sha256'], 'Published '+reference['path'])
    return reference


def publish_json(root, path, value):
    expected_sha = sha(encoded(value))
    build.write(path, value)
    return require_ref(root, path, expected_sha)


def verify_process_logs(root, ledger, *, evidence, physical_build=None):
    from release_signed_runtime import process_log

    scope = physical_build if physical_build is not None and evidence.is_relative_to(physical_build) else root
    for step in ledger['steps']:
        name = step['name']
        if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', name):
            raise ValueError('Invalid owned process name')
        package.verify_report_fields(step, {'exitCode': 0}, 'Owned process '+name)
        package.verify_report_fields(step['processTree'], {'exited': True, 'childReaped': True},
                                     'Owned process tree '+name)
        for field, suffix in (('log', '.log'), ('stderrLog', '.stderr.log')):
            path = release_reference(root, physical_build, step[field])
            package.equal(evidence/'logs'/(name+suffix), path, 'Owned process log path for '+name)
            process_log(scope, {**step, field: path.relative_to(scope).as_posix()}, field)


def process_step(ledger, name):
    matches = [step for step in ledger['steps'] if step['name'] == name]
    if len(matches) != 1:
        raise ValueError('Expected one recorded process for '+name)
    return matches[0]


def verify_upstream_reports(output, evidence, current, extracted, identity, package_info, app_inventory):
    from release_signed_runtime import APP_BODY, APP_TITLE, process_log, validate_database

    reports = {}
    for field, name in (
        ('staticReport', 'relocated-products.json'), ('cliReport', 'cli-runtime.json'),
        ('vmAppReport', 'vm-app/runtime.json'), ('processLedger', 'build-receipt.json'),
    ):
        report = evidence_at(output, current[field], evidence/name)
        package.verify_report_fields(report, {'status': 'PASS'}, 'Upstream '+field)
        reports[field] = report
    ledger = reports['processLedger']
    verify_process_logs(output, ledger, evidence=evidence)
    app, cli = extracted/'Meshchan.app', extracted/'meshctl'
    static_step = process_step(ledger, 'relocated-products')
    package.equal([str(app), str(cli)], static_step['argv'][-2:], 'Upstream static product arguments')
    static_output = json.loads(process_log(output, static_step, 'log'), object_pairs_hook=release_signing.policy_object)
    package.equal(encoded(reports['staticReport']), encoded(static_output), 'Upstream static process output')

    cwd = extracted.parent/'runtime workspace'
    fixture = cwd/'owned CLI data'
    cli_report = reports['cliReport']
    version_step = process_step(ledger, 'cli-version')
    executable, library = str(cli/'bin/meshctl'), str(cli/build.CLI_SQLITE_LIBRARY)
    package.verify_report_fields(version_step, {'cwd': str(cwd), 'argv': [executable, '--version']},
                                 'Upstream CLI version process')
    package.equal('meshctl '+identity['productVersion'], process_log(output, version_step, 'log').decode().strip(),
                  'Upstream CLI version')
    rows = cli_report.get('processes')
    if type(rows) is not list or len(rows) != 2:
        raise ValueError('Upstream CLI requires write and reopen evidence')
    for name, action, row in zip(('cli-write', 'cli-read'), ('create', 'show'), rows, strict=True):
        package.verify_report_fields(row, {'name': name, 'sqliteLoadedFrom': library}, 'Upstream CLI '+action)
        step = process_step(ledger, name)
        package.verify_report_fields(step, {'cwd': str(cwd)}, 'Upstream CLI process')
        package.equal([executable, '--data-dir', str(fixture), 'draft', action], step['argv'][:5],
                      'Upstream CLI arguments')
        cli_output = json.loads(process_log(output, step, 'log'), object_pairs_hook=release_signing.policy_object)
        package.equal(encoded(row['report']), encoded(cli_output), 'Upstream CLI process output')
        package.verify_report_fields(cli_output, {'schemaVersion': 1, 'command': 'draft', 'action': action,
                                                  'exitCode': 0, 'operationSucceeded': True},
                                     'Upstream CLI result')
        package.verify_report_fields(cli_output['storageClose'], {'state': 'closed'}, 'Upstream CLI close')
        trace = process_log(output, step, 'stderrLog').decode()
        loaded = {path.removeprefix('/System/Volumes/Data') for path in
                  re.findall(r'^dyld\[\d+\]: <[0-9A-Fa-f-]+> (/.+)$', trace, re.MULTILINE)}
        if library not in loaded:
            raise ValueError('Upstream CLI trace does not identify its extracted SQLite: '+name)
    draft = rows[1]['report']['draft']
    package.equal(encoded(rows[0]['report']['draft']), encoded(draft), 'Upstream CLI reopened draft')
    database = require_material_file(fixture, 'meshchan.sqlite')
    raw_db = database.read_bytes()
    package.verify_report_fields(cli_report, {'database': str(database), 'databaseSha256': sha(raw_db)},
                                 'Upstream CLI database')
    stored = validate_database(raw_db, draft, draft['title'], draft['body'])
    package.equal(encoded(stored), encoded(cli_report['storedDrafts']), 'Upstream CLI database receipt')

    vm = reports['vmAppReport']
    vm_step = process_step(ledger, 'vm-app-runtime')
    package.equal(['--app', str(app), '--package-info', str(extracted/'package-info.json'),
                   '--evidence', str(evidence/'vm-app')], vm_step['argv'][-6:], 'Upstream VM product arguments')
    vm_entry = build.material_result(process_log(output, vm_step, 'log').decode())
    package.verify_report_fields(vm_entry, {'status': 'PASS', 'guestRun': vm['guestRun']}, 'Upstream VM process')
    package.verify_report_fields(vm, {
        'app': str(app), 'identity': identity, 'packageInfoSha256': package_info['sha256'],
        'appInventorySha256': sha(encoded(app_inventory)),
        'guestInventoryBefore': 'PASS', 'guestInventoryAfter': 'PASS', 'guestSignature': 'PASS',
        'guestExecutorExit': 0, 'guestLockReleased': True,
    }, 'Upstream VM evidence')
    vm_rows = vm.get('processes')
    if type(vm_rows) is not list or len(vm_rows) != 2:
        raise ValueError('Upstream VM App requires write and reopen evidence')
    for row in vm_rows:
        package.verify_report_fields(row, {'exitCode': 0, 'pidAbsentAfterNormalExit': True}, 'Upstream VM App process')
    package.equal(encoded(vm_rows[0]['draft']), encoded(vm_rows[1]['draft']), 'Upstream VM reopened draft')
    vm_db = require_material_file(evidence/'vm-app', 'vm-fixture.sqlite').read_bytes()
    package.equal(vm['guestDatabaseSha256'], sha(vm_db), 'Upstream VM database')
    validate_database(vm_db, vm_rows[1]['draft'], APP_TITLE, APP_BODY)
    return reports['staticReport']


def verify_frozen_ledgers(source, source_build, run, ledgers):
    for name in ('check-inputs', 'check-products', 'materials-recheck', 'check-commit'):
        reference = ledgers[name]
        ledger = release_reference(source, source_build, reference['path'])
        if (ledger.name != 'build-receipt.json' or ledger.parent.parent != run/'evidence'
                or not ledger.parent.name.startswith(name+'-')):
            raise ValueError('Frozen ledger is outside the selected build verification run: '+name)
        result, _ = bound_json(run, ledger.relative_to(run).as_posix(), reference['sha256'])
        package.verify_report_fields(result, {'formatVersion': 1, 'status': 'PASS'}, 'Frozen ledger '+name)
        verify_process_logs(source, result, evidence=ledger.parent, physical_build=source_build)


def read_upstream(args, *, output_build=None):
    from package_release_vm import DEFAULT_DATA_SUBDIR

    source = package.real_directory(package.canonical(args.source_checkout))
    output_build = package.build_directory(ROOT) if output_build is None else output_build
    source_build = output_build if source == ROOT else package.build_directory(source)
    run, info = package.selected_info(source, args.build_run, args.expected_build_info_sha256,
                                      physical_build=source_build)
    output = package.output_path(args.package_run, new=False, physical_build=output_build)
    receipt = release_run_path(ROOT, output_build, args.upstream_check_receipt, 'phase-1e5')
    if (receipt.name != 'package-receipt.json' or receipt.parent.parent != output/'evidence'
            or not receipt.parent.name.startswith('check-')):
        raise ValueError('Use the independent check receipt in the selected package run')
    original, original_bytes = bound_json(output, 'evidence/package-receipt.json',
                                          args.expected_package_receipt_sha256)
    current, current_bytes = bound_json(output, receipt.relative_to(output).as_posix(),
                                        args.expected_upstream_check_sha256)
    matching_package_receipts(original, current, {
        'sourceCheckout': str(source), 'buildRun': args.build_run, 'sourceCommit': info['sourceCommit'],
        'identity': info['identity'],
    }, args.expected_package_receipt_sha256)
    with build.checkout_lock(source):
        package.verify_frozen_helpers(source, info)
        snapshot = package.snapshot(source, run, info, args.expected_build_info_sha256)
        trees, indexes, _ = snapshot
        prebuild_name = 'evidence/prebuild-identities.json'
        prebuild = package.read_bound_index(run, prebuild_name, indexes[prebuild_name])
        package.equal(prebuild['source'], repository_source_hashes(source, [run]), 'Frozen source snapshot')
        if info['recipeVersion'] >= 33:
            package.equal(prebuild['sourceMetadata'], build.repository_source_metadata(source, prebuild['source']),
                          'Frozen source metadata')
        package.equal(prebuild['configuration'], build.configuration(source), 'Frozen generated configuration')
        caches = package.protected_caches(source, info,
                                          package_config_sha256=prebuild['configuration'][build.PACKAGE_CONFIG])
        identity = info['identity']
        top = package.safe('Meshchan-'+identity['productVersion']+'-'+identity['target'])
        _, package_info, inventory = package.layout(source, run, info, trees, indexes, original['packagingTool'], top)
        stage = package.real_directory(package.canonical(output/'stage'/top))
        package.equal(str(stage), original['stage'], 'Upstream stage path')
        check_payload(stage, inventory)
        metadata_observations(stage, inventory)
        archive_path = output/'archives'/(top+'.tar')
        package.equal({'path': archive_path.relative_to(output).as_posix(), **package.file_stamp(archive_path)[0]},
                      original['archive'], 'Upstream engineering archive')
        package.equal({'path': (stage/'package-info.json').relative_to(output).as_posix(),
                       **inventory['package-info.json']}, original['packageInfo'], 'Upstream package manifest')
        package.equal(package_info, (stage/'package-info.json').read_bytes(), 'Original package inventory bytes')
        verification = current['frozenVerification']
        package.equal({'status': 'PASS', 'buildStatus': 'PASS', 'materialsStatus': 'PASS', 'run': args.build_run},
                      verification['result'], 'Frozen check')
        verify_frozen_ledgers(source, source_build, run, verification['ledgers'])
        external_source = (source, source_build) if source != ROOT else ()
        build_roots = (output_build, source_build) if source != ROOT else (output_build,)
        protected = (*external_source, run, output, *caches, *package.git_metadata(source),
                     *package.git_metadata(ROOT), Path.home()/DEFAULT_DATA_SUBDIR)
        extracted = package.real_directory(package.canonical(current['extracted']))
        package.equal(top, extracted.name, 'Upstream extracted product name')
        package.verify_report_fields(current, {'extractRoot': str(extracted.parent)}, 'Upstream extraction')
        package.disjoint(extracted.parent, (ROOT, *build_roots, *protected))
        check_payload(extracted, inventory)
        metadata_observations(extracted, inventory)
        static_report = verify_upstream_reports(output, receipt.parent, current, extracted, identity,
                                               original['packageInfo'], trees['Meshchan.app'][1])
        protected = (*protected, extracted.parent)
    provenance = {
        'sourceCheckout': str(source), 'buildRun': args.build_run, 'packageRun': str(output),
        'sourceCommit': info['sourceCommit'], 'buildRecipeVersion': info['recipeVersion'],
        'buildInfoSha256': args.expected_build_info_sha256,
        'originalPackageReceiptSha256': args.expected_package_receipt_sha256,
        'upstreamCheckReceipt': str(receipt),
        'upstreamCheckReceiptSha256': args.expected_upstream_check_sha256,
        'packageInfo': original['packageInfo'], 'archive': original['archive'],
        'materialsManifestSha256': trees['materials'][1]['materials-manifest.json']['sha256'],
        'originalPackagingTool': original['packagingTool'], 'upstreamVerifier': current['packagingTool'],
    }
    if source_build != source/'build':
        provenance['buildRunPath'] = str(run)
    historical = {'package-info.json': package_info, 'package-receipt.json': original_bytes,
                  'package-check-receipt.json': current_bytes, 'engineering-README.md': package.README}
    return Upstream(source, run, output, stage, top, info, inventory, protected, build_roots, provenance,
                    historical, static_report)


def accepted_upstream(info):
    """Re-read the original engineering package and all five pinned admission gates."""
    source = info['upstream']
    inputs = SimpleNamespace(
        source_checkout=Path(source['sourceCheckout']), build_run=source['buildRun'],
        package_run=Path(source['packageRun']), upstream_check_receipt=Path(source['upstreamCheckReceipt']),
        expected_build_info_sha256=source['buildInfoSha256'],
        expected_package_receipt_sha256=source['originalPackageReceiptSha256'],
        expected_upstream_check_sha256=source['upstreamCheckReceiptSha256'],
    )
    upstream = read_upstream(inputs)
    package.equal(source, upstream.provenance, 'Selected original engineering package')
    return upstream


def output_path(value, new, *, physical_build=None):
    physical_build = package.build_directory(ROOT) if physical_build is None else physical_build
    path = release_run_path(ROOT, physical_build, value, 'phase-1e6', direct=True)
    name = 'build' if physical_build != ROOT/'build' else release_relative_path(ROOT, physical_build, path)
    package.require_ignored_run(ROOT, name)
    if new and os.path.lexists(path):
        raise ValueError('Preserve the existing signing run and use a fresh output')
    if not new:
        package.real_directory(path)
    return path


def tool_identity():
    inputs = {name: package.file_entry(require_material_file(ROOT, name)) for name in SIGNING_SOURCES}
    return {
        'gitCommit': package.git(ROOT, 'rev-parse', 'HEAD').strip(),
        'workingTree': package.git(ROOT, 'status', '--porcelain=v1', '--untracked-files=all',
                                   '--', *SIGNING_SOURCES).splitlines(),
        'inputs': inputs,
    }


def platform_identity(runner):
    return {
        'macOS': runner.command('macos', ['/usr/bin/sw_vers']).strip(),
        'architecture': platform.machine(),
        'xcode': runner.command('xcode-version', ['/usr/bin/xcodebuild', '-version']).strip(),
        'xcodePath': runner.command('xcode-path', ['/usr/bin/xcode-select', '-p']).strip(),
        'tools': {'/usr/bin/codesign': digest(Path('/usr/bin/codesign'))},
        'python': {'path': sys.executable, 'resolvedPath': str(Path(sys.executable).resolve()),
                   'version': sys.version, 'sha256': digest(Path(sys.executable))},
    }


def source_payload(upstream, tools):
    payload = {'.': package.DIR, 'README.md': package.bytes_entry(SIGNED_README)}
    payload.update({name: entry for name, entry in upstream.inventory.items()
                    if name.split('/', 1)[0] in RETAINED})
    for name, data in upstream.historical_files.items():
        payload['upstream-provenance/'+name] = package.bytes_entry(data)
    payload.update(prefixed('signing-source', tools['inputs']))
    for name in ('phase-1e6-signing.md', 'phase-1e6-user-library-replacement.md'):
        payload['signing-materials/'+name] = tools['inputs']['docs/releases/'+name]
    for name in ('LICENSE', 'COPYRIGHT'):
        payload['signing-materials/'+name] = tools['inputs'][name]
    for name in tuple(payload):
        for parent in Path(name).parents:
            payload.setdefault(parent.as_posix(), package.DIR)
    return payload


def copy_source(root, upstream, tools):
    root.mkdir(mode=0o755)
    root.chmod(0o755)
    for name in RETAINED:
        shutil.copytree(upstream.stage/name, root/name, symlinks=True, copy_function=shutil.copy)
    for name, entry in source_payload(upstream, tools).items():
        target = root/name
        group, _, relative = name.partition('/')
        if group in RETAINED or name == '.':
            continue
        if entry['type'] == 'directory':
            target.mkdir(parents=True, exist_ok=True)
            target.chmod(entry['mode'])
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        if group in ('signing-source', 'signing-materials'):
            source = relative
            if group == 'signing-materials' and relative not in ('LICENSE', 'COPYRIGHT'):
                source = 'docs/releases/'+relative
            # These are repository source snapshots. Git identifies their
            # data and mode independently of local working-copy xattrs.
            data = require_material_file(ROOT, source).read_bytes()
        else:
            data = SIGNED_README if name == 'README.md' else upstream.historical_files[relative]
        with target.open('xb') as stream:
            stream.write(data)
        target.chmod(entry['mode'])
    expected = source_payload(upstream, tools)
    check_payload(root, expected)
    metadata_observations(root, expected)
    return expected


def inventory_part(inventory, prefix):
    return {'.' if name == prefix else name.removeprefix(prefix+'/'): value
            for name, value in inventory.items() if name == prefix or name.startswith(prefix+'/')}


def signed_payload(root, expected):
    observed = product_inventory(root)
    materials = {name: entry for name, entry in expected.items() if name.split('/', 1)[0] not in PRODUCTS}
    package.compare(materials, {name: entry for name, entry in observed.items()
                                if name.split('/', 1)[0] not in (*PRODUCTS, 'signed-product-info.json')},
                    'Signed candidate preserved material and source files')
    observed.pop('signed-product-info.json', None)
    return observed


def native_report(upstream, root, runner):
    identity = upstream.info['identity']
    with build.checkout_lock(upstream.checkout):
        package.verify_frozen_helpers(upstream.checkout, upstream.info)
        result = json.loads(runner.command('signed-native-mapping',
            [sys.executable, '-B', '-c', NATIVE_VALIDATOR, root/'Meshchan.app', root/'meshctl',
             identity['productVersion'], identity['appBuild']], cwd=upstream.checkout))
    for name in ('loaders', 'appNativeAssets', 'appAotSnapshot'):
        package.equal(upstream.static_report[name], result[name], 'Relocated signed '+name)
    for product, libraries in result['native'].items():
        for name, library in libraries.items():
            original = upstream.static_report['native'][product][name]
            package.equal(original['sections'], library['sections'], 'Signed native section mapping '+product+'/'+name)
            library['acceptedUpstreamMatch'] = original
    return result


def candidate_fields(upstream, tools):
    return {
        **LOCAL_SCHEMA, 'identity': upstream.info['identity'], 'upstream': upstream.provenance,
        'signingTool': tools, 'policy': {'path': POLICY.relative_to(ROOT).as_posix(),
                                       'sha256': tools['inputs'][POLICY.relative_to(ROOT).as_posix()]['sha256']},
        'metadataPolicy': SIGNATURE_METADATA, 'inventoryExclusions': ['signed-product-info.json'],
    }


def manifest_inventory(info, raw):
    payload = info['payloadInventory']
    name = 'signed-product-info.json'
    if type(payload) is not dict or name in payload:
        raise ValueError('Signed product inventory must exclude its own manifest')
    return payload | {name: {'type': 'file', 'size': len(raw), 'sha256': sha(raw), 'mode': 0o600}}


def signed_vm_arguments(python, config, relocated, manifest_pin, evidence):
    return list(map(str, [python, '-B', ROOT/'tool/package_release_vm.py', '--config', config,
                          '--app', relocated/'Meshchan.app', '--signed-info', relocated/'signed-product-info.json',
                          '--expected-signed-info-sha256', manifest_pin, '--evidence', evidence]))


def replacement_arguments(python, config, root, manifest_pin, replacement, timeout):
    return list(map(str, [python, '-B', ROOT/'tool/release_signed_replacement.py', '--signed-root', root,
                          '--signed-info-sha256', manifest_pin, '--output', replacement,
                          '--vm-config', config, '--timeout', timeout]))


def verify_local_runtime_invocations(ledger, python, root, relocated, manifest_pin, evidence, replacement):
    vm_step = process_step(ledger, 'signed-vm-app-runtime')
    replacement_step = process_step(ledger, 'signed-user-replacement')
    vm_argv, replacement_argv = vm_step.get('argv'), replacement_step.get('argv')
    if (type(vm_argv) is not list or len(vm_argv) != 13 or type(replacement_argv) is not list
            or len(replacement_argv) != 13 or not all(type(arg) is str for arg in vm_argv+replacement_argv)):
        raise ValueError('Malformed local VM or replacement process arguments')
    config = vm_argv[4]
    if not Path(config).is_absolute():
        raise ValueError('Local VM process did not use its staged configuration path')
    try:
        build.command_timeout(replacement_argv[-1])
    except (ValueError, argparse.ArgumentTypeError) as error:
        raise ValueError('Invalid replacement process timeout') from error
    package.verify_report_fields(vm_step, {
        'cwd': str(ROOT), 'argv': signed_vm_arguments(python, config, relocated, manifest_pin, evidence/'vm-app'),
    }, 'Local VM process')
    package.verify_report_fields(replacement_step, {
        'cwd': str(ROOT),
        'argv': replacement_arguments(python, config, root, manifest_pin, replacement, replacement_argv[-1]),
    }, 'Local replacement process')
    return vm_step, replacement_step


def read_local_acceptance(candidate_root, manifest_pin, receipt_path, receipt_pin):
    """Bind independent acceptance and retained runtime evidence to one local candidate."""
    from package_release_vm import DEFAULT_DATA_SUBDIR
    from release_signed_runtime import parse_signed_info, process_log, verify_cli_runtime_evidence

    physical_build = package.build_directory(ROOT)
    root = package.real_directory(release_run_path(ROOT, physical_build, candidate_root, 'phase-1e6'))
    receipt = release_run_path(ROOT, physical_build, receipt_path, 'phase-1e6')
    output = output_path(root.parent.parent, new=False, physical_build=physical_build)
    if (root.parent != output/'signed' or receipt.name != 'signing-receipt.json'
            or receipt.parent.parent != output/'evidence' or not receipt.parent.name.startswith('check-')):
        raise ValueError('Use the independent check receipt from the selected local signing run')
    name = 'signed-product-info.json'
    raw = require_material_file(root, name).read_bytes()
    package.equal(manifest_pin, sha(raw), 'Selected local candidate manifest SHA-256')
    info = parse_signed_info(raw)
    package.verify_report_fields(info, LOCAL_SCHEMA, 'Local candidate manifest')
    full = manifest_inventory(info, raw)
    report, _ = bound_json(output, receipt.relative_to(output).as_posix(), receipt_pin)
    package.verify_report_fields(report, {
        **LOCAL_SCHEMA, 'command': 'check', 'status': 'PASS', 'upstreamStatus': 'PASS',
        **dict.fromkeys(ACCEPTANCE_GATES, 'PASS'),
        'signedRoot': str(root), 'signedInfo': {'path': (root/name).relative_to(output).as_posix(), 'sha256': manifest_pin},
        'upstream': info['upstream'], 'identity': info['identity'], 'signingIdentity': info['signature']['identity'],
        'relocatedInventorySha256': sha(encoded(full)),
    }, 'Independent local acceptance')
    if 'producerCheckout' in report:
        package.verify_report_fields(report, {'producerCheckout': str(ROOT)}, 'Independent local acceptance')
    package.equal(info['signingTool']['inputs'], report['signingTool']['inputs'], 'Accepted signing tool inputs')
    package.equal(info['signingTool']['inputs'], tool_identity()['inputs'], 'Current signing tool inputs')
    check_payload(root, full)
    metadata_observations(root, full)
    workspace = package.real_directory(package.canonical(Path(report['workspace'])))
    package.disjoint(workspace, [ROOT, physical_build, root, Path.home()/DEFAULT_DATA_SUBDIR])
    relocated = workspace/'relocated products'
    check_payload(relocated, full)
    metadata_observations(relocated, full)
    evidence = receipt.parent
    ledger = evidence_at(output, report['processLedger'], evidence/'build-receipt.json')
    package.verify_report_fields(ledger, {'status': 'PASS'}, 'Process ledger')
    verify_process_logs(output, ledger, evidence=evidence)
    cli = evidence_at(output, report['cliReport'], evidence/'cli-runtime.json')
    package.verify_report_fields(cli, {'signingProfile': release_signing.LOCAL_PROFILE,
                                      'signedInfoSha256': manifest_pin,
                                      'relocatedRoot': str(relocated)}, 'Accepted local CLI')
    verify_cli_runtime_evidence(cli, relocated/'meshctl', workspace/'cli workspace',
                                info['identity']['productVersion'], ledger=ledger, evidence_root=output)
    replacement = workspace/'user modified products'
    vm_step, replacement_step = verify_local_runtime_invocations(
        ledger, report['environment']['python']['path'], root, relocated, manifest_pin, evidence, replacement)
    vm_reference = vm_report(output, evidence/'vm-app/runtime.json',
                             build.material_result(process_log(output, vm_step, 'log').decode()),
                             relocated, info, raw)
    package.equal(report['vmAppReport'], vm_reference, 'Accepted local VM process receipt')
    replacement_result = build.material_result(process_log(output, replacement_step, 'log').decode())
    package.verify_report_fields(replacement_result, {
        'status': 'PASS', 'signingProfile': release_signing.LOCAL_PROFILE,
        'receipt': str(replacement/'evidence/replacement-receipt.json'),
        'receiptSha256': report['modifiedLibraryReport']['sha256'],
    }, 'Accepted local replacement process')
    verify_replacement_evidence(replacement, report['modifiedLibraryReport'], root, info, manifest_pin)
    return info, raw, report


def verify_replacement_evidence(workspace, reference, root, info, manifest_pin):
    evidence = workspace/'evidence'
    replacement = evidence_at(workspace, reference, evidence/'replacement-receipt.json')
    package.verify_report_fields(replacement, {**LOCAL_SCHEMA, 'status': 'PASS', 'signedInfoSha256': manifest_pin,
                                               'signedRoot': str(root), 'identity': info['identity'],
                                               'finalIntegrity': 'PASS'}, 'Accepted local library replacement')
    package.verify_report_fields(replacement['cli'], {'status': 'PASS', 'exitCode': 0}, 'Accepted replacement CLI')
    package.verify_report_fields(replacement['app'], {'status': 'PASS', 'exitCode': 0, 'guestExecutorExit': 0,
                                                      'guestLockReleased': True, 'pidAbsent': True},
                                 'Accepted replacement App')
    verify_process_logs(workspace, replacement, evidence=evidence)
    cli = replacement['cli']
    for field in ('log', 'stderrLog', 'pidReceipt'):
        require_ref(workspace, require_material_file(workspace, cli[field]), cli[field+'Sha256'])
    app_evidence = replacement['app']['evidence']
    required = {'session.json', 'refresh-state.json', 'Release/app.stdout', 'Release/app.stderr',
                'Release/app.pid', 'Release/app.exit', 'Release/synthetic-ports.png'}
    if type(app_evidence) is not dict or set(app_evidence) != required:
        raise ValueError('Incomplete retained replacement App evidence')
    guest = evidence/'app-vm'
    for name, pin in app_evidence.items():
        require_ref(guest, require_material_file(guest, name), pin)
    modified = workspace/'user products'
    package.equal(replacement['modifiedInventorySha256'], sha(encoded(product_inventory(modified))),
                  'Retained modified product inventory')


def selection(profile, policy):
    if profile != release_signing.LOCAL_PROFILE or release_signing.policy_profile(policy) != profile:
        raise ValueError('Select the explicit local-adhoc signing profile and matching policy')
    return release_signing.local_identity()


def sign(args, upstream, output, evidence, runner, record, tools, signing, policy):
    record['signatureStatus'] = 'RUNNING'
    identity = selection(args.signing_profile, policy)
    record['signingIdentity'] = identity
    partial = output/'in-progress'
    copy_source(partial, upstream, tools)
    order = signing.discover_code(partial, policy)
    record['codeOrder'] = order
    signing.sign_products(partial, policy, identity, runner.command, scratch=evidence)
    original = source_payload(upstream, tools)
    payload = signed_payload(partial, original)
    signatures = signing.verify_signatures(partial, policy, identity, runner.command, evidence)
    record['signatureStatus'] = 'PASS'
    record['materialTransformStatus'] = 'RUNNING'
    transform = signing.verify_transform(upstream.stage, partial, policy)
    native = native_report(upstream, partial, runner)
    candidate = {
        **candidate_fields(upstream, tools), 'signingEnvironment': record['environment'],
        'signature': {'identity': identity, 'items': signatures, 'order': order},
        'beforeSigningInventory': original,
        'payloadInventory': payload,
        'transform': transform, 'native': native,
    }
    candidate['metadata'] = metadata_observations(partial, candidate['payloadInventory'])
    build.raise_if_interrupted(runner.interrupted)
    require_original(args, upstream)
    package.equal(tools, tool_identity(), 'Signing inputs during sealing')
    manifest = partial/'signed-product-info.json'
    entry = {**package.bytes_entry(encoded(candidate)), 'mode': 0o600}
    build.write(manifest, candidate)
    check_payload(partial, candidate['payloadInventory'] | {manifest.name: entry})
    signed = output/'signed'/upstream.top
    signed.parent.mkdir()
    partial.rename(signed)
    record.update(signedRoot=str(signed), signedInfo=require_ref(output, signed/manifest.name, entry['sha256']),
                  materialTransformStatus='PASS')
    return 'SIGNED'


def require_original(args, upstream):
    current = read_upstream(args)
    package.equal(upstream, current, 'Accepted upstream after the signing operation')


def repeat_check(args, upstream, output, evidence, runner, record, tools, signing, policy):
    from package_release_vm import DEFAULT_DATA_SUBDIR, checked_vm_configuration
    from release_signed_runtime import accept_cli, parse_signed_info, verify_cli_runtime_evidence

    root = package.real_directory(package.canonical(output/'signed'/upstream.top))
    record['signatureStatus'] = 'RUNNING'
    info_name = 'signed-product-info.json'
    _, info_bytes = bound_json(root, info_name, args.expected_signed_info_sha256)
    info = parse_signed_info(info_bytes)
    sealing_receipt = package.real_directory(package.canonical(output/'evidence'))/'signing-receipt.json'
    result = json.loads(require_material_file(output, sealing_receipt.relative_to(output).as_posix()).read_bytes(),
                        object_pairs_hook=release_signing.policy_object)
    package.verify_report_fields(result, {
        **LOCAL_SCHEMA, 'command': 'sign', 'status': 'SIGNED', 'signedRoot': str(root),
        'signatureStatus': 'PASS', 'materialTransformStatus': 'PASS',
        'signedInfo': {'path': (root/info_name).relative_to(output).as_posix(), 'sha256': sha(info_bytes)},
        'signingIdentity': info['signature']['identity'], 'identity': info['identity'], 'upstream': info['upstream'],
        'signingTool': info['signingTool'],
    }, 'Original signing completion')
    sealed_tools = info['signingTool']
    package.equal(tools['inputs'], sealed_tools['inputs'], 'Signing inputs used for the sealed product')
    package.verify_report_fields(info, candidate_fields(upstream, sealed_tools), 'Signed product manifest')
    expected = source_payload(upstream, tools)
    package.equal(expected, info['beforeSigningInventory'], 'Pre-signing payload')
    identity = selection(args.signing_profile, policy)
    package.equal(identity, info['signature']['identity'], 'Sealed local signing identity')
    payload = info['payloadInventory']
    full = manifest_inventory(info, info_bytes)
    check_payload(root, full)
    metadata_observations(root, full)
    package.equal(payload, signed_payload(root, expected), 'Signed product bytes')
    signatures = signing.verify_signatures(root, policy, identity, runner.command, evidence)
    package.equal(info['signature']['items'], signatures, 'Sealed signature records')
    package.equal(info['signature']['order'], signing.discover_code(upstream.stage, policy), 'Pre-signing code order')
    record['signatureStatus'] = 'PASS'
    record['materialTransformStatus'] = 'RUNNING'
    transform = signing.verify_transform(upstream.stage, root, policy)
    # The OS may add its managed provenance after a file has been observed.
    package.equal({key: value for key, value in info['transform'].items() if key != 'filesystemMetadata'},
                  {key: value for key, value in transform.items() if key != 'filesystemMetadata'},
                  'Independent signature transform')
    package.equal(info['native'], native_report(upstream, root, runner), 'Signed native and AOT graph')
    record.update(signedRoot=str(root), signedInfo=require_ref(output, root/info_name, sha(info_bytes)),
                  signingIdentity=identity, materialTransformStatus='PASS')

    parent = package.real_directory(package.canonical(args.workspace_parent))
    workspace = package.canonical(parent/'Meshchan signing runtime')
    protected = [ROOT, *upstream.build_roots, *upstream.protected, Path.home()/DEFAULT_DATA_SUBDIR]
    package.disjoint(workspace, protected)
    vm = checked_vm_configuration(args.vm_config, [*protected, workspace], cwd=ROOT)
    with new_extraction_root(workspace) as fd:
        stamp = os.fstat(fd)
    record['workspace'] = str(workspace)
    relocated = workspace/'relocated products'
    shutil.copytree(root, relocated, symlinks=True, copy_function=shutil.copy)
    check_payload(relocated, full)
    metadata_observations(relocated, full)
    record['relocatedInventorySha256'] = sha(encoded(full))

    def relocated_command(name, argv, cwd=None, *, return_stderr=False):
        return runner.command('relocated-'+name, argv, cwd, return_stderr=return_stderr)

    relocated_signatures = signing.verify_signatures(relocated, policy, identity, relocated_command,
                                                     evidence/'relocation-certs')
    package.equal(signatures, relocated_signatures, 'Relocated signature identities')
    record['cliStatus'] = 'RUNNING'
    cli = accept_cli(relocated/'meshctl', workspace/'cli workspace', runner, info['identity']['productVersion'])
    package.equal('PASS', cli['status'], 'Signed CLI runtime')
    cli_report = evidence/'cli-runtime.json'
    record['cliReport'] = publish_json(output, cli_report, {**cli, 'signingProfile': args.signing_profile,
                                                           'signedInfoSha256': sha(info_bytes),
                                                           'relocatedRoot': str(relocated)})
    record['cliStatus'] = 'PASS'
    record['vmAppStatus'] = 'RUNNING'
    with vm as vm_config:
        vm_evidence = evidence/'vm-app'
        vm_args = signed_vm_arguments(sys.executable, vm_config, relocated, sha(info_bytes), vm_evidence)
        guest = build.material_result(runner.command('signed-vm-app-runtime', vm_args, cwd=ROOT))
        record['vmAppReport'] = vm_report(output, vm_evidence/'runtime.json', guest, relocated, info, info_bytes)
        record['vmAppStatus'] = 'PASS'

        record['modifiedLibraryStatus'] = 'RUNNING'
        replacement_root = workspace/'user modified products'
        args_replacement = replacement_arguments(sys.executable, vm_config, root, sha(info_bytes),
                                                 replacement_root, args.timeout)
        replacement_result = build.material_result(runner.command('signed-user-replacement', args_replacement, cwd=ROOT))
    record['modifiedLibraryReport'] = replacement_report(replacement_root, replacement_result, root,
                                                        info, info_bytes, signing, policy, runner.command)
    record['modifiedLibraryStatus'] = 'PASS'
    record['postRuntimeIntegrityStatus'] = 'RUNNING'
    package.require_extraction_root(workspace, stamp)
    check_payload(relocated, full)
    check_payload(root, full)
    metadata_observations(relocated, full)
    metadata_observations(root, full)
    package.equal(payload, signed_payload(root, expected), 'Original signed product after runtime')
    package.equal(payload, signed_payload(relocated, expected), 'Relocated signed product after runtime')
    require_original(args, upstream)
    package.equal(tools, tool_identity(), 'Signing inputs during acceptance')
    verify_cli_runtime_evidence(evidence_json(output, record['cliReport']), relocated/'meshctl',
                                workspace/'cli workspace', info['identity']['productVersion'],
                                ledger=runner.receipt, evidence_root=output)
    vm_report(output, vm_evidence/'runtime.json', guest, relocated, info, info_bytes)
    verify_replacement_evidence(replacement_root, record['modifiedLibraryReport'], root, info, sha(info_bytes))
    record['postRuntimeIntegrityStatus'] = 'PASS'
    return 'PASS'


def replacement_report(workspace, result, root, info, data, signing, policy, command):
    from release_signed_replacement import (
        APP_LIBRARY, CLI_LIBRARY, APP_BINARY, CLI_BINARY, APP, APP_FRAMEWORK,
        APP_EMPTY, APP_NOT_REFRESHED, MARKER_START, read_owned_exit, read_owned_pid, require_marker, snapshot_has,
        verify_cli_output, verify_local_signatures, verify_shutdown,
    )

    path = workspace/'evidence/replacement-receipt.json'
    package.verify_report_fields(result, {'status': 'PASS', 'receipt': str(path),
                                         'signingProfile': info['signingProfile']}, 'Replacement entry')
    reference = {'path': str(path), 'sha256': result['receiptSha256']}
    report = evidence_json(workspace, reference)
    package.verify_report_fields(report, {
        **LOCAL_SCHEMA, 'status': 'PASS', 'signedInfoSha256': sha(data), 'identity': info['identity'],
        'signedRoot': str(root), 'finalIntegrity': 'PASS',
    }, 'User replacement acceptance')
    cli, app = report['cli'], report['app']
    package.verify_report_fields(cli, {'status': 'PASS', 'exitCode': 0,
                                       'pidReceipt': 'cli working directory/child.pid'}, 'User replacement CLI')
    package.verify_report_fields(app, {'status': 'PASS', 'exitCode': 0, 'guestExecutorExit': 0,
                                       'guestLockReleased': True, 'pidAbsent': True,
                                       'inventoryBefore': 'PASS', 'inventoryAfter': 'PASS',
                                       'result': APP_EMPTY}, 'User replacement App')
    marker = report['marker']
    if not re.fullmatch(re.escape(MARKER_START)+r'[a-f0-9]{32}', marker):
        raise ValueError('Replacement report does not identify the synthetic marker')
    logs = {}
    for key in ('log', 'stderrLog'):
        logs[key] = require_material_file(workspace, cli[key]).read_bytes()
        package.equal(cli[key+'Sha256'], sha(logs[key]), 'User replacement CLI '+key)
    raw_pid = require_material_file(workspace, cli['pidReceipt']).read_bytes()
    package.equal(cli['pidReceiptSha256'], sha(raw_pid), 'User replacement CLI PID receipt')
    cli_pid = read_owned_pid(raw_pid.decode())
    package.verify_report_fields(cli, verify_cli_output(logs['log'].decode(), logs['stderrLog'].decode(),
                                                         marker, pid=cli_pid),
                                 'User replacement CLI evidence')
    guest_files = {}
    for name in ('session.json', 'refresh-state.json', 'Release/app.stdout', 'Release/app.stderr',
                 'Release/app.pid', 'Release/app.exit', 'Release/synthetic-ports.png'):
        guest_files[name] = require_material_file(workspace/'evidence/app-vm', name).read_bytes()
        package.equal(app['evidence'][name], sha(guest_files[name]), 'User replacement App '+name)
    package.verify_report_fields(app, {
        'pid': read_owned_pid(guest_files['Release/app.pid'].decode()),
        'exitCode': read_owned_exit(guest_files['Release/app.exit'].decode()),
        'shutdown': verify_shutdown(guest_files['Release/app.stdout'].decode()),
    }, 'User replacement App process')
    guest_run = app['guestRun']
    if not isinstance(guest_run, str) or not re.fullmatch(r'[0-9]{8}T[0-9]{6}Z-product-[1-9][0-9]*', guest_run):
        raise ValueError('User replacement did not identify its guest run')
    session = json.loads(guest_files['session.json'])
    package.verify_report_fields(session, {'run': guest_run}, 'User replacement guest session')
    lock_identity = session.get('lockIdentity')
    if not isinstance(lock_identity, str) or not re.fullmatch(r'[0-9]+:[0-9]+', lock_identity):
        raise ValueError('User replacement did not record its guest lock identity')
    guest_product = session['products']['Release']
    guest_path = guest_product['root']
    guest_root = PurePosixPath(guest_path)
    if (guest_root.as_posix() != guest_path or len(guest_root.parts) != 6
            or guest_root.parts[:2] != ('/', 'Users') or guest_root.parts[2] == '..'
            or guest_root.parts[3:] != ('utm-ui-isolation', 'products', guest_run+'-Release')):
        raise ValueError('User replacement guest product path differs from the recorded run')
    require_marker(guest_files['Release/app.stderr'].decode(), marker, app['pid'])
    snapshots = json.loads(guest_files['refresh-state.json'])
    if (not snapshot_has(snapshots['before'], APP_NOT_REFRESHED) or snapshot_has(snapshots['before'], APP_EMPTY)
            or not snapshot_has(snapshots['after'], APP_EMPTY) or snapshot_has(snapshots['after'], APP_NOT_REFRESHED)):
        raise ValueError('User replacement did not preserve the synthetic Refresh transition')
    screenshot = guest_files['Release/synthetic-ports.png']
    if (not screenshot.startswith(b'\x89PNG\r\n\x1a\n\0\0\0\rIHDR')
            or not screenshot.endswith(b'\0\0\0\0IEND\xaeB`\x82')):
        raise ValueError('User replacement screenshot is missing its PNG framing')
    copies = package.real_directory(package.canonical(workspace/'user products'))
    actual = product_inventory(copies)
    package.equal(report['modifiedInventorySha256'], sha(encoded(actual)), 'Modified product inventory')
    package.verify_report_fields(guest_product, {
        'pid': app['pid'], 'sourceApp': str(copies/APP), 'executableSha256': actual[APP_BINARY]['sha256'],
    }, 'User replacement guest product')
    libraries = report['replacement']['libraries']
    for name in (APP_LIBRARY, CLI_LIBRARY):
        package.equal(libraries[name]['signedReplacementSha256'], actual[name]['sha256'],
                      'Actual replacement library '+name)
    package.equal(app['guestLibrarySha256'], actual[APP_LIBRARY]['sha256'], 'Guest replacement library')
    package.equal(app['appInventorySha256'], sha(encoded(inventory_part(actual, APP))), 'Guest replacement inventory')
    transform = signing.verify_transform(root, copies, policy, replacements=(APP_LIBRARY, CLI_LIBRARY))
    permitted = {APP_LIBRARY, CLI_LIBRARY, APP_BINARY, CLI_BINARY}
    permitted.update(item.seal for item in policy if item.path in (APP, APP_FRAMEWORK))
    if {entry['path'] for entry in transform['changedFiles']} - permitted:
        raise ValueError('User replacement altered an unrelated signed file')
    signatures = verify_local_signatures(copies, policy, command, prefix='replacement-final')
    package.equal(encoded(report['replacement']['localSignatures']), encoded(signatures),
                  'User replacement local signature evidence')
    check_payload(copies, actual)
    metadata_observations(copies, actual)
    return reference


def vm_report(output, path, candidate, root, info, data):
    from release_signed_runtime import manifest_profile, verify_vm_runtime_evidence

    profile = manifest_profile(info)
    package.verify_report_fields(candidate, {'status': 'PASS', 'signingProfile': profile}, 'Signed VM entry')
    reference = {'path': path.relative_to(output).as_posix(), 'sha256': candidate['receiptSha256']}
    result = evidence_json(output, reference)
    guest_run = candidate['guestRun']
    if type(guest_run) is not str or not guest_run:
        raise ValueError('Signed VM acceptance has no current run ID')
    inventory = inventory_part(info['payloadInventory'], 'Meshchan.app')
    package.verify_report_fields(result, {
        'status': 'PASS', 'signingProfile': profile, 'guestRun': guest_run, 'app': str(root/'Meshchan.app'),
        'signedInfoSha256': sha(data), 'identity': info['identity'],
        'appInventorySha256': sha(encoded(inventory)),
        'guestInventoryBefore': 'PASS', 'guestInventoryAfter': 'PASS', 'guestSignature': 'PASS',
        'guestSigningIdentity': info['signature']['identity'], 'guestSignatureAfter': 'PASS',
        'guestObserverTransfer': 'PASS', 'guestObserverAfter': 'PASS',
        'guestExecutorExit': 0, 'guestLockReleased': True,
    }, 'Signed VM receipt')
    verify_vm_runtime_evidence(result, path.parent, inventory)
    return reference


def run(args):
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise ValueError('Use a macOS arm64 signing host')
    new = args.command != 'check'
    output_build = package.build_directory(ROOT)
    output = output_path(args.output, new, physical_build=output_build)
    if not new:
        output_stamp = output.lstat()
    upstream = read_upstream(args, output_build=output_build)
    package.disjoint(output, upstream.protected)
    if new:
        output.parent.mkdir(parents=True, exist_ok=True)
        with new_extraction_root(output) as fd:
            output_stamp = os.fstat(fd)
        evidence = output/'evidence'
        evidence.mkdir(mode=0o700)
    else:
        package.require_extraction_root(output, output_stamp)
        evidence = Path(tempfile.mkdtemp(prefix='check-', dir=package.real_directory(package.canonical(output/'evidence'))))
    evidence_stamp = evidence.lstat()
    receipt_path = evidence/'signing-receipt.json'
    record = {
        **LOCAL_SCHEMA, 'command': args.command, 'startedAt': build.now(), 'status': 'RUNNING',
        'producerCheckout': str(ROOT),
        'upstreamStatus': 'PASS', 'upstream': upstream.provenance, 'identity': upstream.info['identity'],
        **dict.fromkeys(ACCEPTANCE_GATES, 'NOT_RUN'),
    }

    with build.DeferredInterrupts() as interrupted:
        scratch = evidence/'tool scratch'
        scratch.mkdir(mode=0o700)
        env = {**controlled_environment(), 'LC_ALL': 'C', 'TZ': 'UTC', 'TMPDIR': str(scratch)}
        runner = build.Runner(output, evidence, {'status': 'RUNNING', 'steps': []}, env,
                              args.timeout, interrupted)

        def finish(status):
            package.require_extraction_root(output, output_stamp)
            package.require_extraction_root(evidence, evidence_stamp)
            runner.receipt['status'] = status
            ledger_sha = sha(encoded(runner.receipt))
            runner.save()
            record.update(status=status, finishedAt=build.now(),
                          processLedger=require_ref(output, evidence/'build-receipt.json', ledger_sha))
            return publish_json(output, receipt_path, record)

        build.write(receipt_path, record)
        try:
            record['environment'] = platform_identity(runner)
            tools = tool_identity()
            record['signingTool'] = tools
            policy = release_signing.load_policy(POLICY)
            selection(args.signing_profile, policy)
            if args.command == 'prepare':
                prepared = output/'prepared'
                inventory = copy_source(prepared, upstream, tools)
                record['codeOrder'] = release_signing.discover_code(prepared, policy)
                native_path = evidence/'prepared-native.json'
                record['preparedNative'] = publish_json(output, native_path, native_report(upstream, prepared, runner))
                index = evidence/'prepared-inventory.json'
                record['preparedInventory'] = publish_json(output, index, inventory)
                record['preparedRoot'] = str(prepared)
                require_original(args, upstream)
                package.equal(tools, tool_identity(), 'Signing inputs during preparation')
                check_payload(prepared, inventory)
                metadata_observations(prepared, inventory)
                evidence_json(output, record['preparedNative'])
                evidence_json(output, record['preparedInventory'])
                status = 'PREPARED'
            elif args.command == 'sign':
                status = sign(args, upstream, output, evidence, runner, record, tools, release_signing, policy)
            else:
                (evidence/'relocation-certs').mkdir(mode=0o700)
                status = repeat_check(args, upstream, output, evidence, runner, record, tools, release_signing, policy)
            verify_process_logs(output, runner.receipt, evidence=evidence)
            build.raise_if_interrupted(interrupted)
            final_ref = finish(status)
            while not interrupted.seal_if_unchanged(0):
                build.raise_if_interrupted(interrupted)
        except BaseException as error:
            status = 'FAIL'
            for key, value in record.items():
                if key.endswith('Status') and value == 'RUNNING':
                    record[key] = status
            record['error'] = build.failure_message(error)
            if interrupted:
                record['interruptSignal'] = int(interrupted[0])
            finish(status)
            raise
    return {'status': record['status'], 'signingProfile': record['signingProfile'],
            'receipt': str(receipt_path), 'receiptSha256': final_ref['sha256'],
            **{key: record[key] for key in ('signedRoot', 'signedInfo', 'preparedRoot') if key in record}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for name in ('prepare', 'sign', 'check'):
        command = commands.add_parser(name)
        command.add_argument('--source-checkout', type=Path, required=True)
        command.add_argument('--build-run', required=True)
        command.add_argument('--expected-build-info-sha256', required=True)
        command.add_argument('--package-run', type=Path, required=True)
        command.add_argument('--expected-package-receipt-sha256', required=True)
        command.add_argument('--upstream-check-receipt', type=Path, required=True)
        command.add_argument('--expected-upstream-check-sha256', required=True)
        command.add_argument('--output', type=Path, required=True)
        command.add_argument('--timeout', type=build.command_timeout, default=900)
        command.add_argument('--signing-profile', choices=[release_signing.LOCAL_PROFILE],
                             default=release_signing.LOCAL_PROFILE)
        if name == 'check':
            command.add_argument('--expected-signed-info-sha256', required=True)
            command.add_argument('--workspace-parent', type=Path, required=True)
            command.add_argument('--vm-config', type=Path, required=True)
    args = parser.parse_args()
    if sys.version_info < (3, 15) or sys.version_info.releaselevel != 'final':
        parser.error('Use a stable Python 3.15 or newer')
    for name, value in vars(args).items():
        if name.endswith('_sha256') and not package.SHA256.fullmatch(value):
            parser.error('Use a lowercase SHA-256 for --'+name.replace('_', '-'))
    try:
        record = run(args)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError, KeyboardInterrupt, build.GateInterrupted) as error:
        print('ERROR: '+build.failure_message(error), file=sys.stderr)
        return 1
    print(json.dumps(record, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
