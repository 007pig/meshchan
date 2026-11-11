#!/usr/bin/env python3
"""Archive updated acceptance metadata around an unchanged, tested native bundle."""
import argparse
from contextlib import contextmanager
import datetime
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import tarfile
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


@contextmanager
def verified_original_bundle(verification):
    """Yield only contents bound to the original external archive verification."""
    if verification.get('status') != 'PASS':
        raise ValueError('Original archive verification did not pass.')
    archive_bytes = Path(verification['archive']).read_bytes()
    if hashlib.sha256(archive_bytes).hexdigest() != verification['archiveSha256']:
        raise ValueError('Original archive hash changed.')
    with tempfile.TemporaryDirectory(prefix='meshchan-verified-original-') as directory:
        with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode='r:gz') as archive:
            roots, names = set(), set()
            for member in archive.getmembers():
                path = PurePosixPath(member.name)
                if (path.is_absolute() or not path.parts or '..' in path.parts
                        or not (member.isfile() or member.isdir()) or path in names):
                    raise ValueError('Original archive has unsupported members.')
                roots.add(path.parts[0]);names.add(path)
            if len(roots) != 1:
                raise ValueError('Original archive must contain one complete bundle.')
            archive.extractall(directory, filter='data')
        original = Path(directory) / roots.pop()
        info = json.loads((original / 'build-info.json').read_text())
        verified_native = verification['testedNativeHashesVerified']
        if info['nativeHashes'] != verified_native or 'bin/meshctl' not in verified_native:
            raise ValueError('Original native manifest differs from external verification.')
        sums = {}
        for line in (original / 'SHA256SUMS').read_text().splitlines():
            value, name = line.split('  ', 1)
            path = PurePosixPath(name)
            if (path.is_absolute() or '..' in path.parts or not path.parts
                    or name == 'SHA256SUMS' or name in sums or digest(original / name) != value):
                raise ValueError('Original member checksum validation failed.')
            sums[name] = value
        files = {str(path.relative_to(original)) for path in original.rglob('*') if path.is_file()}
        if files != set(sums) | {'SHA256SUMS'} or len(sums) != verification['memberChecksumsVerified']:
            raise ValueError('Original archive layout differs from its verification.')
        for name, value in verified_native.items():
            if name not in sums or digest(original / name) != value:
                raise ValueError('Original native bytes differ from external verification.')
        if not os.access(original / 'bin/meshctl', os.X_OK):
            raise ValueError('Original archive lost executable permission.')
        yield original


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-directory', type=Path, required=True)
    parser.add_argument('--rf-summary', type=Path, required=True)
    parser.add_argument('--acceptance-summary', type=Path, required=True)
    parser.add_argument('--software-followup', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    base = args.build_directory.resolve()
    original_verification = json.loads((base / 'archive-verification.json').read_text())
    original_archive = Path(original_verification['archive'])
    try:
        with verified_original_bundle(original_verification) as original:
            info = json.loads((original / 'build-info.json').read_text())
            rf = json.loads(args.rf_summary.read_text())
            if rf['buildId'] != info['buildId'] or rf['nativeHashes'] != info['nativeHashes']:
                parser.error('RF evidence must identify the original tested native bytes.')
            known_attempts = rf.get('knownApplicationSendAttempts', rf['actualApplicationSendAttempts'])
            if type(known_attempts) is not int or known_attempts < 0:
                parser.error('RF evidence must retain known application attempt accounting.')
            if rf['actualApplicationSendAttempts'] is None and rf['status'] != 'BLOCKED':
                parser.error('Unknown application sends must remain BLOCKED.')
            if known_attempts > rf['authorizedApplicationSendAttemptCeiling']:
                parser.error('Application attempts exceeded the recorded authorized ceiling.')
            for name, value in info['productCompilationInputHashes'].items():
                if digest(root / name) != value:
                    parser.error('A product compilation input changed: ' + name)
            for name, value in info['nativeHashes'].items():
                if digest(original / name) != value:
                    parser.error('Original native asset changed: ' + name)
            followup = None
            if args.software_followup is not None:
                followup = json.loads(args.software_followup.read_text())
                if (followup.get('status') != 'PASS' or followup.get('buildId') != info['buildId']
                        or not followup.get('checks') or any(c['exitCode'] for c in followup['checks'])):
                    parser.error('The software follow-up must identify a passing recorded gate.')
                for name, value in followup['sourceHashes'].items():
                    if digest(root / name) != value:
                        parser.error('A verified follow-up input changed: ' + name)
            # Validate the retained complete source bundle before copying any metadata.
            original_sums = {}
            for line in (original / 'SHA256SUMS').read_text().splitlines():
                value, name = line.split('  ', 1)
                path = Path(name)
                if path.is_absolute() or '..' in path.parts or name in original_sums:
                    parser.error('Invalid retained checksum path.')
                original_sums[name] = value
                if digest(original / name) != value:
                    parser.error('Retained bundle checksum mismatch: ' + name)
            original_files = {str(p.relative_to(original)) for p in original.rglob('*') if p.is_file()}
            if original_files != set(original_sums) | {'SHA256SUMS'}:
                parser.error('Retained complete bundle layout differs from its manifest.')
            now = datetime.datetime.now(datetime.timezone.utc)
            revision = info['buildId'] + '-rf-' + now.strftime('%Y%m%dT%H%M%SZ')
            candidate = base / 'delivery' / revision
            archive = candidate.with_name(revision + '.tar.gz')
            if candidate.exists() or archive.exists():
                parser.error('Preserve existing revisions; choose a fresh invocation time.')
            acceptance = args.acceptance_summary.read_text()
            shutil.copytree(original, candidate, copy_function=shutil.copy2)
            info['archiveRevision'] = revision
            info['archiveRevisionUtc'] = now.isoformat()
            info['nativeRebuiltForRevision'] = False
            info['originalArchiveSha256'] = original_verification['archiveSha256']
            info['originalBundleSource'] = 'Fresh extraction bound to the verified original archive'
            info['initialPeerCompilationInputHashes'] = info.pop('peerCompilationInputHashes')
            info['initialPeerInputsMeaning'] = 'Original H0 snapshot; later RF source inputs are recorded separately.'
            prefixes = ('apps/meshctl/tool/', 'packages/meshcore_link/lib/', 'apps/meshctl/lib/')
            current_inputs = {}
            for prefix in prefixes:
                for path in sorted((root / prefix).rglob('*.dart')):
                    current_inputs[str(path.relative_to(root))] = digest(path)
            for name in ('pubspec.yaml', 'pubspec.lock', 'apps/meshctl/pubspec.yaml',
                         'packages/meshcore_link/pubspec.yaml', 'tool/run_openhop_acceptance.py',
                         'tool/prepare_openhop_acceptance.py', 'tool/summarize_openhop_acceptance.py',
                         'tool/run_openhop_acceptance_test.py', 'tool/summarize_openhop_acceptance_test.py',
                         'tool/revise_dev_candidate.py', 'tool/revise_dev_candidate_test.py'):
                current_inputs[name] = digest(root / name)
            info['developmentSourceInputHashesAtArchiveRevision'] = current_inputs
            info['hardwareEvidence'] = 'Real Direct matrix; see acceptance-summary.md. Earlier failures retained.'
            info['rfAcceptance'] = {key: value for key, value in rf.items() if key not in ('allTrials',)}
            info['laterSoftwareVerification'] = followup if followup is not None else {
                'cliTests': 88,
                'scope': 'Source-only channel audit, WS cleanup and passive-window tools; product inputs unchanged.',
                'nativeBuildAndSmokeEvidence': 'Original complete gate, same native hashes; no rebuild inferred.',
            }
            (candidate / 'build-info.json').write_text(json.dumps(info, indent=2) + '\n')
            (candidate / 'acceptance-summary.md').write_text(acceptance)
            (candidate / 'README.md').write_text(
                '# Meshchan 0.1.0-dev.2 local development candidate\n\n'
                'Keep the complete bin/ and lib/ layout. Run bin/meshctl --version or --help.\n'
                'The product uses explicit USB connections. Development openHop tools are\n'
                'source-only repository tools and are excluded from this bundle.\n\n'
                'Status: development-with-known-limitations. This archive updates acceptance\n'
                'metadata around unchanged native files tested in the real Direct matrix.\n'
                'Read acceptance-summary.md and build-info.json for passes, retained failures,\n'
                'source provenance and distribution limits. The original archive is retained.\n'
                'This is not a public release, Developer ID/notarization, clean-machine\n'
                'certification, or a determination of complete license compliance.\n')
            sums = {str(p.relative_to(candidate)): digest(p) for p in sorted(candidate.rglob('*'))
                    if p.is_file() and p.name != 'SHA256SUMS'}
            (candidate / 'SHA256SUMS').write_text(''.join(v + '  ' + n + '\n' for n, v in sums.items()))
            with tarfile.open(archive, 'w:gz') as tar:
                tar.add(candidate, arcname=revision)
            archive_hash = digest(archive)
            sidecar = archive.with_name(archive.name + '.sha256')
            sidecar.write_text(archive_hash + '  ' + archive.name + '\n')
            extraction = Path(tempfile.mkdtemp(prefix='meshchan-rf-extracted-', dir='/private/tmp'))
            with tarfile.open(archive) as tar:
                tar.extractall(extraction, filter='data')
            extracted = extraction / revision
            members = list(extracted.rglob('*'))
            if any(p.is_symlink() or not (p.is_file() or p.is_dir()) for p in members):
                raise RuntimeError('Unexpected extracted member type.')
            actual_files = {str(p.relative_to(extracted)) for p in members if p.is_file()}
            if actual_files != set(sums) | {'SHA256SUMS'}:
                raise RuntimeError('Extracted layout differs from the expected complete bundle.')
            verified = {}
            for line in (extracted / 'SHA256SUMS').read_text().splitlines():
                value, name = line.split('  ', 1)
                if name in verified or name not in sums or value != sums[name] or digest(extracted / name) != value:
                    raise RuntimeError('Extracted manifest/member checksum mismatch.')
                verified[name] = value
            if verified != sums or 'SHA256SUMS' in verified:
                raise RuntimeError('Incomplete or self-referential extracted checksums.')
            native_modes = {}
            for name, value in info['nativeHashes'].items():
                mode = stat.S_IMODE((extracted / name).stat().st_mode)
                if digest(extracted / name) != value or mode != stat.S_IMODE((original / name).stat().st_mode):
                    raise RuntimeError('Tested native hash/mode changed.')
                native_modes[name] = oct(mode)
            executable = extracted / 'bin/meshctl'
            if not os.access(executable, os.X_OK):
                raise RuntimeError('Executable permission missing.')
            unchanged_notices = [name for name in sums if name.startswith('licenses/') or name == 'THIRD_PARTY_NOTICES.md']
            if any(digest(extracted / name) != original_sums[name] for name in unchanged_notices):
                raise RuntimeError('Original license/notice material changed.')
            checks = []
            for arguments, expected in [(['--version'], 0), (['--help'], 0), (['info'], 64), (['datagram', 'ping'], 64)]:
                run = subprocess.run([str(executable), *arguments], cwd=extraction, capture_output=True, text=True, timeout=30)
                if run.returncode != expected:
                    raise RuntimeError('Extracted process exit differs.')
                if arguments == ['--version'] and run.stdout.strip() != 'meshctl 0.1.0-dev.2':
                    raise RuntimeError('Extracted version differs.')
                if expected == 0 and run.stderr:
                    raise RuntimeError('Unexpected extracted stderr.')
                if arguments == ['--help'] and 'datagram' not in run.stdout:
                    raise RuntimeError('Extracted help incomplete.')
                if expected == 64 and (run.stdout or 'Error:' not in run.stderr):
                    raise RuntimeError('Missing-argument check did not reject before device access.')
                checks.append({'argv': [str(executable), *arguments], 'expectedExit': expected,
                               'actualExit': run.returncode, 'stdout': run.stdout, 'stderr': run.stderr})
            record = {'status': 'PASS', 'archiveRevision': revision, 'candidateDirectory': str(candidate),
                      'archive': str(archive), 'archiveSha256': archive_hash, 'sha256Sidecar': str(sidecar),
                      'originalArchivePreservedSha256': digest(original_archive),
                      'extractedDirectory': str(extracted), 'memberChecksumsVerified': len(verified),
                      'exactFileLayoutVerified': True, 'executePermissionVerified': True,
                      'testedNativeHashesVerified': info['nativeHashes'], 'nativeModesVerified': native_modes,
                      'originalNoticeFilesVerified': len(unchanged_notices), 'checks': checks,
                      'rfSummarySha256': digest(args.rf_summary),
                      'verifiedUtc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
            verification = base / ('archive-verification-' + revision.removeprefix(info['buildId'] + '-') + '.json')
            verification.write_text(json.dumps(record, indent=2) + '\n')
            (base / 'latest-archive.json').write_text(json.dumps({'verification': str(verification),
                                                              'archive': str(archive), 'candidate': str(candidate)}, indent=2) + '\n')
            print(json.dumps({k: v for k, v in record.items() if k != 'checks'} | {'verification': str(verification)}, indent=2))
    except (ValueError, KeyError, OSError, tarfile.TarError):
        parser.error('Original archive or revision provenance validation failed.')


if __name__ == '__main__':
    main()
