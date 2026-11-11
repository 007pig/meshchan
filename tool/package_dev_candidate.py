#!/usr/bin/env python3
"""Archive a pretested complete local product candidate and verify extraction."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
from urllib.parse import unquote, urlparse


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-directory', type=Path, required=True)
    parser.add_argument('--acceptance-summary', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    base = args.build_directory.resolve()
    latest = json.loads((root / 'build/phase-1b9/latest.json').read_text())
    if str(base) != latest['directory']:
        parser.error('Select the current explicitly recorded build directory.')
    build_id = latest['buildId']
    candidate = base / 'delivery' / build_id
    archive = candidate.parent / (build_id + '.tar.gz')
    if archive.exists():
        parser.error('Archive already exists; preserve it and use revise_dev_candidate.py.')
    native = {str(p.relative_to(candidate)): digest(p) for p in sorted(candidate.rglob('*'))
              if p.is_file() and p.parts[-2] in ('bin', 'lib')}
    tested = json.loads((base / 'hardware/execution-plan.json').read_text())['nativeHashes']
    if native != tested:
        parser.error('Candidate native assets differ from the hardware-plan hashes.')
    acceptance = args.acceptance_summary.read_text()
    (candidate / 'acceptance-summary.md').write_text(acceptance)
    (candidate / 'README.md').write_text(
        '# Meshchan 0.1.0-dev.2 local development candidate\n\n'
        'Keep the complete bin/ and lib/ layout. Run bin/meshctl --version or --help.\n'
        'The product supports explicit USB connections only. The openHop peer is a\n'
        'repository development tool and is excluded from this bundle.\n\n'
        'Status: development-with-known-limitations. Read acceptance-summary.md and\n'
        'build-info.json for this exact binary. Historical USB delivery issues remain\n'
        'unresolved. This is not a public release, clean-machine certification,\n'
        'Developer ID signing, notarization, or legal-compliance determination.\n')
    graph = json.loads((base / 'resolved-dependencies.json').read_text())
    packages = {p['name']: p for p in graph['packages']}
    closure = set()
    def visit(name):
        if name in closure:
            return
        closure.add(name)
        for dependency in packages[name].get('directDependencies', []):
            visit(dependency)
    visit('meshctl')
    config_file = root / '.dart_tool/package_config.json'
    config = json.loads(config_file.read_text())
    locations = {}
    for package in config['packages']:
        uri = urlparse(package['rootUri'])
        locations[package['name']] = (Path(unquote(uri.path)) if uri.scheme == 'file'
                                      else (config_file.parent / unquote(package['rootUri'])).resolve())
    notices = []
    for name in sorted(closure - {'meshctl', 'meshcore_link'}):
        folder = locations[name]
        originals = sorted(p for p in folder.iterdir() if p.is_file() and
                           p.name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE')))
        if not originals:
            parser.error('Missing original notice for ' + name)
        destination = candidate / 'licenses' / (name + '-' + packages[name]['version'])
        destination.mkdir(parents=True, exist_ok=True)
        for original in originals:
            shutil.copy2(original, destination / original.name)
        notices.append({'package': name, 'version': packages[name]['version'],
                        'files': [str((destination / p.name).relative_to(candidate)) for p in originals]})
    serial = locations['libserialport_plus']
    native_notices = candidate / 'licenses/libserialport-native'
    native_notices.mkdir(parents=True, exist_ok=True)
    for name in ('COPYING', 'README'):
        shutil.copy2(serial / 'src/libserialport' / name, native_notices / name)
    sdk = Path('/opt/homebrew/share/flutter/bin/cache/dart-sdk')
    (candidate / 'licenses/dart-sdk').mkdir(parents=True, exist_ok=True)
    shutil.copy2(sdk / 'LICENSE', candidate / 'licenses/dart-sdk/LICENSE')
    (candidate / 'THIRD_PARTY_NOTICES.md').write_text(
        '# Original third-party materials\n\n'
        f'This package includes original notices for {len(notices)} resolved external\n'
        'production-graph packages, including native build-hook dependencies.\n'
        'The libserialport_plus 1.0.5 wrapper is MIT; its bundled native C library\n'
        'is LGPLv3-or-later, with original COPYING and README included separately.\n'
        'The Dart SDK LICENSE is included. These files are not a complete compliance\n'
        'claim. Meshchan has no selected project license in this checkout.\n\n'
        'Before public redistribution, resolve the project license, corresponding\n'
        'native source/build/relinking materials and incorporated GPLv3 terms,\n'
        'and complete Dart runtime third-party notices. Native source metadata\n'
        'still differs (config.h 0.1.1 versus configure.ac 0.1.2); no exact upstream\n'
        'native revision is inferred. Developer ID/notarization, download quarantine\n'
        'behavior, and clean-machine validation remain unverified.\n')
    provenance = json.loads((base / 'compilation-inputs.json').read_text())
    prefixes = ('apps/meshctl/lib/', 'apps/meshctl/bin/', 'packages/meshcore_link/lib/')
    metadata = {'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml',
                'apps/meshctl/pubspec.yaml', 'packages/meshcore_link/pubspec.yaml'}
    product_inputs = {name: value for name, value in provenance['inputs'].items()
                      if name.startswith(prefixes) or name in metadata}
    for name, value in provenance['inputs'].items():
        if digest(root / name) != value:
            parser.error('A captured compilation input changed after the gate: ' + name)
    dirty_inputs = []
    for name, value in product_inputs.items():
        old = subprocess.run(['git', 'show', provenance['head'] + ':' + name], cwd=root, capture_output=True)
        if old.returncode or hashlib.sha256(old.stdout).hexdigest() != value:
            dirty_inputs.append({'path': name, 'sha256': value})
    gate = json.loads((base / 'software-gate.json').read_text())
    if any(s['exitCode'] for s in gate):
        parser.error('The recorded gate did not pass.')
    info = {
        'schemaVersion': 1, 'version': '0.1.0-dev.2', 'buildId': build_id,
        'status': 'development-with-known-limitations', 'sourceCommit': provenance['head'],
        'worktreeClean': False, 'uncommittedCompilationInputs': dirty_inputs,
        'productCompilationInputHashes': product_inputs,
        'peerCompilationInputHashes': {name: value for name, value in provenance['inputs'].items()
            if name.startswith(('apps/meshctl/tool/openhop_peer.dart', 'apps/meshctl/tool/support/')) or name in product_inputs},
        'lockfileSha256': digest(root / 'pubspec.lock'),
        'dartVersion': subprocess.check_output([str(sdk / 'bin/dart'), '--version'], text=True).strip(),
        'flutterMetadata': json.loads((sdk.parent / 'flutter.version.json').read_text()),
        'host': subprocess.check_output(['sw_vers'], text=True).strip(),
        'architecture': subprocess.check_output(['uname', '-m'], text=True).strip(),
        'compiler': subprocess.check_output(['/usr/bin/clang', '--version'], text=True).strip(),
        'processPathPrefix': '/opt/homebrew/share/flutter/bin:/usr/bin',
        'buildCommands': [s for s in gate if s['name'].endswith('-build')],
        'softwareGate': {'coreTests': 180, 'cliTests': 72, 'openHopBoundaryTests': 15,
                         'macOSSmokeChecks': 69, 'sourceAndAotSyntheticCasesEach': 5},
        'nativeHashes': native, 'dependencyNotices': notices,
        'hardwareEvidence': 'See acceptance-summary.md; H0 only, no RF datagrams sent.',
        'publicDistribution': 'NOT_READY: license/materials/signing/notarization/clean-machine work remains',
    }
    (candidate / 'build-info.json').write_text(json.dumps(info, indent=2) + '\n')
    sums = {str(p.relative_to(candidate)): digest(p) for p in sorted(candidate.rglob('*'))
            if p.is_file() and p.name != 'SHA256SUMS'}
    (candidate / 'SHA256SUMS').write_text(''.join(value + '  ' + name + '\n' for name, value in sums.items()))
    with tarfile.open(archive, 'w:gz') as tar:
        tar.add(candidate, arcname=build_id, recursive=True)
    archive_hash = digest(archive)
    archive.with_name(archive.name + '.sha256').write_text(archive_hash + '  ' + archive.name + '\n')
    extraction = Path(tempfile.mkdtemp(prefix='meshchan-dev2-extracted-', dir='/private/tmp'))
    with tarfile.open(archive) as tar:
        tar.extractall(extraction, filter='data')
    extracted = extraction / build_id
    actual_files = {str(p.relative_to(extracted)) for p in extracted.rglob('*') if p.is_file()}
    if actual_files != set(sums) | {'SHA256SUMS'}:
        raise RuntimeError('Extracted layout differs from the archive manifest.')
    for name, value in sums.items():
        if digest(extracted / name) != value:
            raise RuntimeError('Extracted checksum mismatch: ' + name)
    if (extracted / 'SHA256SUMS').read_bytes() != (candidate / 'SHA256SUMS').read_bytes():
        raise RuntimeError('Extracted checksum file differs.')
    for name, value in native.items():
        if digest(extracted / name) != value:
            raise RuntimeError('Tested native asset mismatch.')
    executable = extracted / 'bin/meshctl'
    if not os.access(executable, os.X_OK):
        raise RuntimeError('Execute permission was lost.')
    checks = []
    for arguments, expected in [(['--version'], 0), (['--help'], 0),
                                (['info'], 64), (['datagram', 'ping'], 64)]:
        run = subprocess.run([str(executable), *arguments], cwd=extraction, capture_output=True, text=True, timeout=30)
        if run.returncode != expected:
            raise RuntimeError('Extracted command exit mismatch.')
        if arguments == ['--version'] and run.stdout.strip() != 'meshctl 0.1.0-dev.2':
            raise RuntimeError('Extracted version mismatch.')
        if expected == 0 and run.stderr:
            raise RuntimeError('Unexpected extracted-command stderr.')
        if arguments == ['--help'] and 'datagram' not in run.stdout:
            raise RuntimeError('Incomplete extracted help.')
        if expected == 64 and (run.stdout or 'Error:' not in run.stderr):
            raise RuntimeError('Invalid arguments did not reject before hardware access.')
        checks.append({'argv': [str(executable), *arguments], 'expectedExit': expected,
                       'actualExit': run.returncode, 'stdout': run.stdout, 'stderr': run.stderr})
    record = {'status': 'PASS', 'archive': str(archive), 'archiveSha256': archive_hash,
              'extractedDirectory': str(extracted), 'memberChecksumsVerified': len(sums),
              'exactFileLayoutVerified': True, 'executePermissionVerified': True,
              'testedNativeHashesVerified': native, 'checks': checks,
              'verifiedUtc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    (base / 'archive-verification.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({k: v for k, v in record.items() if k != 'checks'}, indent=2))


if __name__ == '__main__':
    main()
