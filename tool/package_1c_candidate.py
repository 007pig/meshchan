#!/usr/bin/env python3
"""Package one explicitly selected dev.3 software gate and verify final archive bytes."""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
from urllib.parse import unquote, urlparse

from candidate_common import (ROOT, TARGET_VERSION, dart_sdk_directory, digest, extract_verified, inventory,
    original_notices, production_closure, validate_gate, validate_runtime, verify_sums, versions, write_json)
from smoke_cli import Checks, archive_business_checks


def collect_materials(candidate, graph, dart):
    sdk = dart_sdk_directory(dart)
    packages, closure, first_party = production_closure(graph)
    config_file = ROOT / '.dart_tool/package_config.json'
    locations = {}
    for package in json.loads(config_file.read_text())['packages']:
        uri = urlparse(package['rootUri'])
        locations[package['name']] = (Path(unquote(uri.path)) if uri.scheme == 'file'
            else config_file.parent / unquote(package['rootUri'])).resolve()
    materials = []
    def copy(original, target, source):
        if not original.is_file():
            raise ValueError('Missing original material: ' + str(original))
        destination = candidate / target
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, destination)
        materials.append({'file': target, 'sha256': digest(destination),
            'originalPath': str(original), 'source': source})
    dependencies = []
    build_packages = {'hooks', 'code_assets', 'native_toolchain_c'}
    declared_runtime = set()
    def runtime_visit(name):
        if name in declared_runtime or name in build_packages:
            return
        declared_runtime.add(name)
        for dependency in packages[name].get('directDependencies', []):
            runtime_visit(dependency)
    runtime_visit('meshctl')
    for name in sorted(closure - first_party):
        package = packages[name]
        folder = locations[name]
        files = original_notices(folder)
        prefix = 'licenses/' + name + '-' + package['version'] + '/'
        for path in files:
            copy(path, prefix + path.name, 'https://pub.dev/packages/' + name + '/versions/' + package['version'])
        dependencies.append({'name': name, 'version': package['version'],
            'role': 'production-graph build-hook-only closure' if name not in declared_runtime else 'declared production dependency graph (AOT reachability not asserted)',
            'packageLocation': str(folder), 'sourceUrl': 'https://pub.dev/packages/' + name + '/versions/' + package['version'],
            'originalNotices': [prefix + p.name for p in files],
            'packageFilesSha256': {str(p.relative_to(folder)): digest(p) for p in sorted(folder.rglob('*'))
                if p.is_file() and p.suffix in ('.dart', '.yaml') and '.dart_tool' not in p.parts}})
    serial = locations['libserialport_plus']
    for name in ('COPYING', 'README'):
        copy(serial / 'src/libserialport' / name, 'licenses/libserialport-native/' + name,
             'Bundled libserialport source in locked libserialport_plus package')
    # Preserve the actual shipped native source/configuration and hook byte-for-byte.
    # These are notice/source materials, not a product source checkout or a relinking claim.
    for folder in ('src', 'hook'):
        for original in sorted((serial / folder).rglob('*')):
            if original.is_file():
                copy(original, 'source-materials/libserialport_plus-1.0.5/' + str(original.relative_to(serial)),
                     'Locked libserialport_plus 1.0.5 package')
    copy(serial / 'pubspec.yaml', 'source-materials/libserialport_plus-1.0.5/pubspec.yaml', 'Locked package metadata')
    sqlite = locations['sqlite3']
    for name in ('hook/build.dart', 'lib/src/hook/assets.dart', 'lib/src/hook/asset_hashes.dart',
                 'lib/src/hook/compile/description.dart', 'lib/src/hook/compile/used_symbols.dart'):
        copy(sqlite / name, 'source-materials/sqlite3-3.9.1/' + name, 'Locked sqlite3 3.9.1 native hook metadata')
    copy(sdk / 'LICENSE', 'licenses/dart-sdk/LICENSE', 'Installed Dart SDK')
    archive_notice = sdk.parent / 'LICENSE.dart_sdk_archive.md'
    if archive_notice.exists():
        copy(archive_notice, 'licenses/dart-sdk/LICENSE.dart_sdk_archive.md', 'Installed Flutter cache archive notice pointer')
    # Additional originals retrieved for this build are explicit, hashed inputs.
    extra = candidate.parent.parent / 'additional-materials'
    if extra.exists():
        origins = json.loads((extra.parent / 'additional-materials-provenance.json').read_text())
        for original in sorted(extra.rglob('*')):
            if original.is_file():
                origin = next((p['url'] for p in reversed(origins)
                    if p.get('name') == str(original.relative_to(extra)) and p.get('status') == 200),
                    'Locally recorded source-material provenance; see additional-materials-provenance.json')
                copy(original, 'licenses/additional/' + str(original.relative_to(extra)),
                     origin)
    exclusions = sorted(set(packages) - closure - first_party)
    return {'firstPartyWorkspace': sorted(first_party), 'productionClosure': sorted(closure),
        'declaredRuntimeGraphExcludingHookRoots': sorted(declared_runtime - first_party),
        'buildHookOnlyClosure': sorted(closure - declared_runtime),
        'thirdPartyProductionGraph': dependencies, 'devOnlyPackagesNotShippedAsRuntimeDependencies': exclusions,
        'materials': materials,
        'nativeComponents': {
            'serial': {'wrapper': 'libserialport_plus 1.0.5', 'nativeSource': 'Included original src/ and hook/ from locked package',
                'upstreamRevision': None, 'reason': 'config.h 0.1.1 and configure.ac 0.1.2 are inconsistent; no revision inferred'},
            'sqlite': {'wrapper': 'sqlite3 3.9.1 (MIT)',
                'nativeSource': 'Default hook precompiled binary from sqlite3.dart sqlite3-3.9.1 release; see asset_hashes.dart',
                'nativeUpstreamRevision': None, 'reason': 'Exact native source/build correspondence not established by local package metadata'},
            'dartRuntime': {'sdkLicense': 'Included', 'completeRuntimeThirdPartyCorrespondence': 'NOT_VERIFIED'}},
        'remainingDistributionGaps': ['Project license not selected',
            'Native corresponding source/build/relinking completeness not established',
            'Complete Dart AOT runtime notice correspondence not verified',
            'Developer ID signing/notarization and download quarantine not verified',
            'Independent clean environment not run', 'Final dev.3 CI not run (local uncommitted inputs)']}


def loader_review(bundle):
    result = {}
    for name, item in inventory(bundle).items():
        path = bundle / name
        description = subprocess.check_output(['file', str(path)], text=True).strip()
        entry = {**item, 'file': description, 'kind': 'runtime asset'}
        if 'Mach-O' in description:
            entry['kind'] = 'product executable' if name == 'bin/meshctl' else 'native library'
            dependencies = subprocess.check_output(['otool', '-L', str(path)], text=True)
            load_commands = subprocess.check_output(['otool', '-l', str(path)], text=True)
            for prefix in (str(ROOT), '/opt/homebrew', '/Users/', '/private/tmp/', '/var/folders/'):
                # otool's first line names the inspected file; only load entries matter.
                if prefix in '\n'.join(dependencies.splitlines()[1:]) or prefix in '\n'.join(load_commands.splitlines()[1:]):
                    raise ValueError('Nonportable loader binding: ' + name + ': ' + prefix)
            libs = [line.strip().split(' (', 1)[0] for line in dependencies.splitlines()[1:]]
            for lib in libs:
                if not lib.startswith(('/usr/lib/', '/System/Library/', '@rpath/', '@loader_path/', '@executable_path/')):
                    raise ValueError('Unclassified external dependency: ' + lib)
            entry['dependencies'] = [{'path': lib, 'scope': 'OS system' if lib.startswith('/') else 'bundle relative'} for lib in libs]
            entry['loadCommands'] = load_commands
            sign = subprocess.run(['codesign', '--verify', '--verbose=2', str(path)], capture_output=True, text=True)
            detail = subprocess.run(['codesign', '-dv', '--verbose=4', str(path)], capture_output=True, text=True)
            entry['signing'] = {'verifyExit': sign.returncode, 'details': detail.stderr,
                'meaning': 'Ad-hoc signatures are not Developer ID or notarization'}
        result[name] = entry
    return result


def asset_provenance(bundle):
    """Map bundled library bytes to actual hook outputs, retaining both hashes."""
    result = {}
    for output in sorted((ROOT / '.dart_tool/hooks_runner').rglob('output.json')):
        hook_input = json.loads((output.parent / 'input.json').read_text())
        if not hook_input.get('config', {}).get('linking_enabled'):
            continue  # VM/source outputs are a separate asset domain.
        data = json.loads(output.read_text())
        for asset in data.get('assets', []):
            encoding = asset.get('encoding', {})
            original = Path(encoding.get('file', ''))
            if not original.is_file():
                continue
            target = bundle / 'lib' / original.name
            if not target.is_file():
                continue
            name = str(target.relative_to(bundle))
            value = {'assetId': encoding.get('id'), 'hookOutput': str(output.relative_to(ROOT)),
                'hookOutputSha256': digest(output), 'originalAsset': str(original),
                'originalAssetSha256': digest(original), 'bundledAssetSha256': digest(target),
                'bundlerLayoutNote': 'Dart build cli copies native assets and adjusts Mach-O install names/signatures; original and delivered hashes are distinct.'}
            if 'sqlite3' in original.name:
                package = Path(hook_input['package_root'])
                hashes = (package / 'lib/src/hook/asset_hashes.dart').read_text()
                known = re.findall(r"'([^']+)': '([0-9a-f]{64})'", hashes)
                matched = [(p, h) for p, h in known if h == value['originalAssetSha256']]
                if not matched:
                    raise ValueError('SQLite hook asset hash is not in the locked package table')
                value['lockedAssetNames'] = [p for p, _ in matched]
                value['sourceRelease'] = 'https://github.com/simolus3/sqlite3.dart/releases/tag/sqlite3-3.9.1'
            result.setdefault(name, []).append(value)
    if not any('sqlite3' in p for p in result) or not any('serialport' in p for p in result):
        raise ValueError('Missing actual native hook source mapping')
    return result


def verify_archive(archive, archive_hash, candidate, runtime, fixture, version):
    expected = inventory(candidate)
    outside = Path(tempfile.mkdtemp(prefix='meshchan dev3 final archive ', dir='/tmp')).resolve()
    if outside.is_relative_to(ROOT):
        raise ValueError('Extraction must be outside checkout')
    extracted = extract_verified(archive, archive_hash, outside, candidate.name, expected)
    verify_sums(extracted)
    actual_runtime = {name: inventory(extracted)[name] for name in runtime}
    if actual_runtime != runtime:
        raise ValueError('Extracted native/runtime assets changed')
    info = json.loads((extracted / 'build-info.json').read_text())
    if info['version'] != version or info['runtimeInventory'] != runtime:
        raise ValueError('Extracted manifest mismatch')
    checks = Checks()
    archive_business_checks(checks, extracted / 'bin/meshctl', outside,
                            outside / 'isolated business data', fixture, version)
    if inventory(extracted) != expected or digest(archive) != archive_hash:
        raise ValueError('Archive or extracted bytes changed during execution')
    return {'status': 'PASS', 'archive': str(archive), 'archiveSha256': archive_hash,
        'extractedDirectory': str(extracted), 'memberChecksumsVerified': len(expected) - 1,
        'exactMemberSetAndModesVerified': True, 'runtimeInventoryVerified': runtime,
        'fixtureSource': str(fixture), 'fixtureSha256': digest(fixture / 'meshchan.sqlite'),
        'checks': checks.records, 'verifiedUtc': datetime.datetime.now(datetime.timezone.utc).isoformat()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-directory', type=Path, required=True)
    parser.add_argument('--acceptance-summary', type=Path, required=True)
    args = parser.parse_args()
    base = args.build_directory.resolve()
    record = json.loads((base / 'validation.json').read_text())
    validate_gate(record)
    compatibility = json.loads((base / 'schema-compatibility.json').read_text())
    if (compatibility['status'] != 'PASS' or compatibility['productCompilationInputHashes'] != record['productCompilationInputHashes']):
        raise ValueError('Schema compatibility is not bound to current product')
    bundle = base / 'cli/bundle'
    runtime = inventory(bundle)
    validate_runtime(runtime)
    if runtime != record['runtimeInventory']:
        raise ValueError('Runtime differs from tested bundle')
    candidate = base / 'delivery' / record['buildId']
    archive = candidate.with_suffix(candidate.suffix + '.tar.gz')
    if candidate.exists() or archive.exists() or (base / 'archive-verification.json').exists():
        raise ValueError('Preserve existing candidates/verification; use a new build ID')
    review = loader_review(bundle)
    write_json(base / 'loader-review.json', review)
    shutil.copytree(bundle, candidate)
    materials = collect_materials(candidate, json.loads((base / 'resolved-dependencies.json').read_text()),
                                  Path(record['toolchain']['dartExecutable']))
    acceptance = args.acceptance_summary.read_text()
    (candidate / 'acceptance-summary.md').write_text(acceptance)
    (candidate / 'README.md').write_text(
        f'# Meshchan {TARGET_VERSION} local development candidate\n\n'
        f'Platform: {record["toolchain"]["os"]}; {record["toolchain"]["architecture"]}.\n'
        'Status: development-with-known-limitations. Public distribution: NOT_READY.\n\n'
        'Keep the complete runtime layout. Run `bin/meshctl --version` or `--help`.\n'
        'Use an explicit data directory outside the bundle, for example:\n\n'
        '```sh\nbin/meshctl --data-dir "$HOME/meshchan-dev3-data" draft list --json\n```\n\n'
        'Offline drafts, profiles, settings and bounded history use SQLite schema 1.\n'
        'Device operations require current explicit selected-port authorization.\n'
        'The synthetic recording probe is excluded; it establishes no RF evidence.\n'
        'Read acceptance-summary.md, build-info.json and THIRD_PARTY_NOTICES.md.\n'
        'Historical USB issues remain unresolved; relay and physical unplug were not retested.\n')
    (candidate / 'THIRD_PARTY_NOTICES.md').write_text(
        '# Original third-party materials\n\n'
        'See build-info.json dependencyMaterials for exact versions, original paths, URLs,\n'
        'file hashes and the production dependency closure. All workspace members are first party.\n'
        'Production-graph hook support is identified separately from runtime libraries;\n'
        'development-only packages are not called product runtime dependencies.\n\n'
        'Original Dart-package notices are in licenses/. libserialport_plus is an MIT\n'
        'Dart wrapper; its bundled libserialport C source identifies LGPLv3-or-later.\n'
        'The original native COPYING/README are separate. Original serial source, config\n'
        'and build hook are in source-materials/; exact upstream revision is unknown.\n'
        'sqlite3 is an MIT Dart wrapper. Its default hook downloads a precompiled native\n'
        'SQLite asset; locked hook/hash metadata is retained separately. No system SQLite\n'
        'was substituted. Dart SDK LICENSE and the installed archive pointer are retained.\n\n'
        'These materials are not a complete legal-compliance determination. Remaining items:\n\n' +
        ''.join('- ' + item + '.\n' for item in materials['remainingDistributionGaps']))
    dirty = []
    for name, value in record['productCompilationInputHashes'].items():
        old = subprocess.run(['git', 'show', record['sourceCommit'] + ':' + name], cwd=ROOT, capture_output=True)
        import hashlib
        if old.returncode or hashlib.sha256(old.stdout).hexdigest() != value:
            dirty.append({'path': name, 'sha256': value})
    status = subprocess.check_output(['git', 'status', '--porcelain=v1', '--untracked-files=all'], cwd=ROOT, text=True)
    info = {**record, 'schemaVersion': 1, 'status': 'development-with-known-limitations',
        'worktreeClean': not bool(status.strip()), 'packagingWorktreeStatus': status,
        'uncommittedCompilationInputs': dirty, 'memberVersions': versions(),
        'lockfileSha256': digest(ROOT / 'pubspec.lock'),
        'formatDomains': {'databaseSchema': 1, 'diagnosticSummary': 1, 'cliSchema': 1, 'diagnosticWire': 1},
        'runtimeInventory': runtime, 'loaderReview': review, 'dependencyMaterials': materials,
        'nativeAssetProvenance': asset_provenance(bundle),
        'schemaCompatibility': compatibility,
        'ci': json.loads((base / 'ci-evidence.json').read_text()) if (base / 'ci-evidence.json').exists() else
            {'finalDev3': 'NOT_RUN: local uncommitted compilation inputs have no corresponding remote run'},
        'distribution': {'localNative': 'PASS', 'sameHostRelocation': 'PASS (shared smoke)',
            'cleanEnvironment': 'NOT_RUN', 'public': 'NOT_READY',
            'platforms': {'macos-arm64': 'Local build/runtime PASS; clean environment NOT_RUN',
                'linux-x64': 'Ownership implemented; final dev.3 NOT_RUN',
                'macos-x64': 'Ownership implemented; NOT_RUN', 'linux-arm64': 'Ownership implemented; NOT_RUN',
                'windows': 'Business ownership unsupported; native safety guards retained',
                'mobile-other': 'Outside delivery scope'}},
        'documentationHashes': {str(p.relative_to(ROOT)): digest(p) for p in
            [ROOT / 'README.md', ROOT / 'packages/meshchan_core/README.md',
             *[ROOT / ('docs/' + p) for p in ('cli.md', 'development.md', 'testing.md')]]},
        'preArchiveAcceptanceSha256': digest(args.acceptance_summary)}
    write_json(candidate / 'build-info.json', info)
    sums = {name: item['sha256'] for name, item in inventory(candidate).items()}
    (candidate / 'SHA256SUMS').write_text(''.join(v + '  ' + k + '\n' for k, v in sums.items()))
    validate_gate(record)  # Last input/tool/log check before issuing archive bytes.
    if inventory(bundle) != runtime:
        raise ValueError('Runtime changed during packaging')
    with tarfile.open(archive, 'x:gz') as tar:
        tar.add(candidate, arcname=candidate.name)
    archive_hash = digest(archive)
    archive.with_name(archive.name + '.sha256').write_text(archive_hash + '  ' + archive.name + '\n')
    result = verify_archive(archive, archive_hash, candidate, runtime,
        base / 'recording-evidence/native recorded database', TARGET_VERSION)
    write_json(base / 'archive-verification.json', result)
    print(json.dumps({k: v for k, v in result.items() if k not in ('checks', 'runtimeInventoryVerified')}, indent=2))


if __name__ == '__main__':
    main()
