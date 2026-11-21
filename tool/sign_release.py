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

import build_release as build
import package_release as package
from release_materials import (controlled_environment, digest, encoded, product_inventory,
                               repository_source_hashes, require_material_file, sha)
from release_package_archive import check_payload, metadata_observations, new_extraction_root, prefixed

ROOT = build.ROOT
POLICY = ROOT/'tool/release_signing_policy.json'
PRODUCTS = ('Meshchan.app', 'meshctl')
RETAINED = (*PRODUCTS, 'materials', 'provenance', 'packaging-source')
UPSTREAM_GATES = ('frozenStatus', 'integrityStatus', 'cliStatus', 'vmAppStatus', 'postRuntimeIntegrityStatus')
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
SIGNED_README = b"""# Meshchan macOS signing candidate

Keep Meshchan.app and the complete meshctl directory together with the
distribution materials. signed-product-info.json describes these candidate bytes.
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


class Blocked(ValueError):
    """A prerequisite for actual release acceptance is unavailable."""


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
    provenance: dict
    historical_files: dict
    static_report: dict


def bound_json(root, relative, pin):
    path = require_material_file(root, relative)
    data = path.read_bytes()
    package.equal(pin, sha(data), 'Bound JSON SHA-256 for '+relative)
    result = json.loads(data)
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


def require_ref(root, path, expected_sha):
    reference = build.ref(root, path)
    package.equal(expected_sha, reference['sha256'], 'Published '+reference['path'])
    return reference


def publish_json(root, path, value):
    expected_sha = sha(encoded(value))
    build.write(path, value)
    return require_ref(root, path, expected_sha)


def read_upstream(args):
    source = package.real_directory(package.canonical(args.source_checkout))
    run, info = package.selected_info(source, args.build_run, args.expected_build_info_sha256)
    output = package.output_path(args.package_run, new=False)
    receipt = package.canonical(args.upstream_check_receipt)
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
        for name in ('check-inputs', 'check-products', 'materials-recheck', 'check-commit'):
            result = evidence_json(source, verification['ledgers'][name])
            package.equal('PASS', result['status'], 'Frozen ledger '+name)
        reports = {name: evidence_json(output, current[name])
                   for name in ('staticReport', 'cliReport', 'vmAppReport', 'processLedger')}
        for name, report in reports.items():
            package.equal('PASS', report['status'], 'Upstream '+name)
        package.verify_report_fields(reports['vmAppReport'], {
            'identity': identity, 'packageInfoSha256': original['packageInfo']['sha256'],
            'appInventorySha256': sha(encoded(trees['Meshchan.app'][1])),
            'guestExecutorExit': 0, 'guestLockReleased': True,
        }, 'Upstream VM evidence')
        external_source = (source,) if source != ROOT else ()
        protected = (*external_source, run, output, *caches,
                     *package.git_metadata(source), *package.git_metadata(ROOT))
    provenance = {
        'sourceCheckout': str(source), 'buildRun': args.build_run, 'packageRun': str(output),
        'sourceCommit': info['sourceCommit'], 'buildRecipeVersion': info['recipeVersion'],
        'buildInfoSha256': args.expected_build_info_sha256,
        'originalPackageReceiptSha256': args.expected_package_receipt_sha256,
        'upstreamCheckReceiptSha256': args.expected_upstream_check_sha256,
        'packageInfo': original['packageInfo'], 'archive': original['archive'],
        'materialsManifestSha256': trees['materials'][1]['materials-manifest.json']['sha256'],
        'originalPackagingTool': original['packagingTool'], 'upstreamVerifier': current['packagingTool'],
    }
    historical = {'package-info.json': package_info, 'package-receipt.json': original_bytes,
                  'package-check-receipt.json': current_bytes, 'engineering-README.md': package.README}
    return Upstream(source, run, output, stage, top, info, inventory, protected, provenance,
                    historical, reports['staticReport'])


def output_path(value, new):
    path = package.canonical(value)
    if path.parent != ROOT/'build/phase-1e6':
        raise ValueError('Use a direct child of the signing checkout build/phase-1e6 directory')
    name = path.relative_to(ROOT).as_posix()
    if (package.git(ROOT, '--literal-pathspecs', 'ls-files', '-z', '--', name)
            or not package.git(ROOT, 'check-ignore', '--', name)):
        raise ValueError('Signing output must be ignored and disjoint from tracked source')
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
        'tools': {path: digest(Path(path)) for path in ('/usr/bin/codesign', '/usr/bin/security')},
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
        'formatVersion': 1, 'identity': upstream.info['identity'], 'upstream': upstream.provenance,
        'signingTool': tools, 'policy': {'path': POLICY.relative_to(ROOT).as_posix(),
                                       'sha256': tools['inputs'][POLICY.relative_to(ROOT).as_posix()]['sha256']},
        'metadataPolicy': SIGNATURE_METADATA, 'inventoryExclusions': ['signed-product-info.json'],
    }


def selection(args, signing, runner):
    if args.identity and args.expected_team:
        try:
            return signing.select_identity(args.identity, args.expected_team, runner.command)
        except signing.IdentityUnavailable as error:
            raise Blocked(str(error)) from error
    output = runner.command('signing-identities', ['/usr/bin/security', 'find-identity', '-p', 'codesigning', '-v'])
    if 'Developer ID Application:' not in output:
        raise Blocked('No valid Developer ID Application identity is available in the signing keychains.')
    raise Blocked('Specify the exact Developer ID Application certificate SHA-1 and expected Team ID.')


def sign(args, upstream, output, evidence, runner, record, tools, signing, policy):
    record['signatureStatus'] = 'RUNNING'
    identity = selection(args, signing, runner)
    record['signingIdentity'] = identity
    partial = output/'in-progress'
    copy_source(partial, upstream, tools)
    order = signing.discover_code(partial, policy)
    record['codeOrder'] = order
    try:
        signing.sign_products(partial, policy, identity, runner.command, scratch=evidence)
    except subprocess.CalledProcessError as error:
        diagnostics = error.stderr or b''
        if isinstance(diagnostics, bytes):
            diagnostics = diagnostics.decode(errors='replace')
        if any(reason in diagnostics.lower() for reason in (
                'user interaction is not allowed', 'errsecinteractionnotallowed',
                'cssmerr_csp_no_user_interaction')):
            raise Blocked('The selected identity needs operator interaction in the signing keychain.') from error
        raise
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
    from package_release_vm import checked_vm_configuration
    from release_signed_runtime import accept_cli

    root = package.real_directory(package.canonical(output/'signed'/upstream.top))
    record['signatureStatus'] = 'RUNNING'
    info_name = 'signed-product-info.json'
    info, info_bytes = bound_json(root, info_name, args.expected_signed_info_sha256)
    sealing_receipt = package.real_directory(package.canonical(output/'evidence'))/'signing-receipt.json'
    result = json.loads(require_material_file(output, sealing_receipt.relative_to(output).as_posix()).read_bytes())
    package.verify_report_fields(result, {
        'formatVersion': 1, 'command': 'sign', 'status': 'SIGNED', 'signedRoot': str(root),
        'signatureStatus': 'PASS', 'materialTransformStatus': 'PASS',
        'signedInfo': {'path': (root/info_name).relative_to(output).as_posix(), 'sha256': sha(info_bytes)},
    }, 'Original signing completion')
    sealed_tools = info['signingTool']
    package.equal(tools['inputs'], sealed_tools['inputs'], 'Signing inputs used for the sealed product')
    package.verify_report_fields(info, candidate_fields(upstream, sealed_tools), 'Signed product manifest')
    expected = source_payload(upstream, tools)
    package.equal(expected, info['beforeSigningInventory'], 'Pre-signing payload')
    identity = info['signature']['identity']
    package.verify_report_fields(identity, {'sha1': args.identity.upper(), 'team': args.expected_team},
                                 'Externally selected signing identity')
    payload = info['payloadInventory']
    full = payload | {info_name: {'type': 'file', 'size': len(info_bytes), 'sha256': sha(info_bytes),
                                  'mode': 0o600}}
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
    package.disjoint(workspace, [ROOT, *upstream.protected])
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
    record['cliReport'] = publish_json(output, cli_report, {**cli, 'signedInfoSha256': sha(info_bytes),
                                                         'relocatedRoot': str(relocated)})
    record['cliStatus'] = 'PASS'
    record['vmAppStatus'] = 'RUNNING'
    runner.env = {**controlled_environment(), 'LC_ALL': 'C', 'TZ': 'UTC'}
    with checked_vm_configuration(args.vm_config, [ROOT, *upstream.protected, workspace], cwd=ROOT) as vm_config:
        vm_evidence = evidence/'vm-app'
        vm_args = [sys.executable, '-B', ROOT/'tool/package_release_vm.py', '--config', vm_config,
                   '--app', relocated/'Meshchan.app', '--signed-info', relocated/info_name,
                   '--expected-signed-info-sha256', sha(info_bytes), '--evidence', vm_evidence]
        guest = build.material_result(runner.command('signed-vm-app-runtime', vm_args, cwd=ROOT))
        record['vmAppReport'] = vm_report(output, vm_evidence/'runtime.json', guest, relocated, info, info_bytes)
        record['vmAppStatus'] = 'PASS'

        record['modifiedLibraryStatus'] = 'RUNNING'
        replacement_root = workspace/'user modified products'
        replacement_result = build.material_result(runner.command('signed-user-replacement', [
            sys.executable, '-B', ROOT/'tool/release_signed_replacement.py', '--signed-root', root,
            '--signed-info-sha256', sha(info_bytes), '--output', replacement_root,
            '--vm-config', vm_config, '--timeout', str(args.timeout),
        ], cwd=ROOT))
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
    evidence_json(output, record['cliReport'])
    evidence_json(output, record['vmAppReport'])
    evidence_json(replacement_root, record['modifiedLibraryReport'])
    record['postRuntimeIntegrityStatus'] = 'PASS'
    return 'PASS'


def replacement_report(workspace, result, root, info, data, signing, policy, command):
    from release_signed_replacement import (
        APP_LIBRARY, CLI_LIBRARY, APP_BINARY, CLI_BINARY, APP, APP_FRAMEWORK,
        APP_EMPTY, APP_NOT_REFRESHED, MARKER_START, read_owned_exit, read_owned_pid, require_marker, snapshot_has,
        verify_cli_output, verify_local_signatures, verify_shutdown,
    )

    path = workspace/'evidence/replacement-receipt.json'
    package.verify_report_fields(result, {'status': 'PASS', 'receipt': str(path)}, 'Replacement entry')
    reference = {'path': str(path), 'sha256': result['receiptSha256']}
    report = evidence_json(workspace, reference)
    package.verify_report_fields(report, {
        'formatVersion': 1, 'status': 'PASS', 'signedInfoSha256': sha(data), 'identity': info['identity'],
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
    from release_signed_runtime import verify_vm_runtime_evidence

    package.verify_report_fields(candidate, {'status': 'PASS'}, 'Signed VM entry')
    reference = {'path': path.relative_to(output).as_posix(), 'sha256': candidate['receiptSha256']}
    result = evidence_json(output, reference)
    guest_run = candidate['guestRun']
    if type(guest_run) is not str or not guest_run:
        raise ValueError('Signed VM acceptance has no current run ID')
    inventory = inventory_part(info['payloadInventory'], 'Meshchan.app')
    package.verify_report_fields(result, {
        'status': 'PASS', 'guestRun': guest_run, 'app': str(root/'Meshchan.app'),
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
    import release_signing as signing

    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise ValueError('Use a macOS arm64 signing host')
    new = args.command != 'check'
    output = output_path(args.output, new)
    if not new:
        output_stamp = output.lstat()
    upstream = read_upstream(args)
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
        'formatVersion': 1, 'command': args.command, 'startedAt': build.now(), 'status': 'RUNNING',
        'upstreamStatus': 'PASS', 'upstream': upstream.provenance, 'identity': upstream.info['identity'],
        **dict.fromkeys(('signatureStatus', 'materialTransformStatus', 'cliStatus', 'vmAppStatus',
                         'modifiedLibraryStatus', 'postRuntimeIntegrityStatus'), 'NOT_RUN'),
    }

    with build.DeferredInterrupts() as interrupted:
        env = {**controlled_environment(), 'LC_ALL': 'C', 'TZ': 'UTC'}
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
            policy = signing.load_policy(POLICY)
            if args.command == 'prepare':
                prepared = output/'prepared'
                inventory = copy_source(prepared, upstream, tools)
                record['codeOrder'] = signing.discover_code(prepared, policy)
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
                status = sign(args, upstream, output, evidence, runner, record, tools, signing, policy)
            else:
                (evidence/'relocation-certs').mkdir(mode=0o700)
                status = repeat_check(args, upstream, output, evidence, runner, record, tools, signing, policy)
            build.raise_if_interrupted(interrupted)
            final_ref = finish(status)
            while not interrupted.seal_if_unchanged(0):
                build.raise_if_interrupted(interrupted)
        except BaseException as error:
            status = 'BLOCKED' if isinstance(error, Blocked) and not interrupted else 'FAIL'
            for key, value in record.items():
                if key.endswith('Status') and value == 'RUNNING':
                    record[key] = status
            record['error'] = build.failure_message(error)
            if interrupted:
                record['interruptSignal'] = int(interrupted[0])
            finish(status)
            raise
    return {'status': record['status'], 'receipt': str(receipt_path), 'receiptSha256': final_ref['sha256'],
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
        if name != 'prepare':
            command.add_argument('--identity', required=name == 'check', help='Developer ID Application certificate SHA-1')
            command.add_argument('--expected-team', required=name == 'check')
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
    identity = getattr(args, 'identity', None)
    team = getattr(args, 'expected_team', None)
    if bool(identity) != bool(team) or (identity and not (
            re.fullmatch('[0-9a-fA-F]{40}', identity) and re.fullmatch('[A-Z0-9]{10}', team))):
        parser.error('Specify both a 40-digit certificate SHA-1 and a 10-character Team ID')
    try:
        record = run(args)
    except Blocked as error:
        print('BLOCKED: '+str(error), file=sys.stderr)
        return 2
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError, KeyboardInterrupt, build.GateInterrupted) as error:
        print('ERROR: '+build.failure_message(error), file=sys.stderr)
        return 1
    print(json.dumps(record, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
