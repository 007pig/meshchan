#!/usr/bin/env python3
"""Record the sequential Phase 1C software/native gate in a new build directory."""
import argparse
import datetime
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

from candidate_common import (ROOT, TARGET_VERSION, dart_sdk_directory, digest, inventory, product_inputs,
                              verification_inputs, versions, write_json)


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dart', type=Path, required=True)
    parser.add_argument('--build-directory', type=Path, required=True)
    parser.add_argument('--refresh-packaging-tools', action='store_true',
                        help='Revalidate only changed packaging tools around unchanged tested product/bundles.')
    args = parser.parse_args()
    base = args.build_directory.resolve()
    if args.refresh_packaging_tools:
        record = json.loads((base / 'validation.json').read_text())
        current = verification_inputs()
        previous = record['verificationInputHashes']
        changed = {p for p in set(previous) | set(current) if previous.get(p) != current.get(p)}
        allowed = {'tool/candidate_common.py', 'tool/candidate_common_test.py',
                   'tool/package_1c_candidate.py', 'tool/validate_dev_candidate.py'}
        if not changed or not changed <= allowed or product_inputs() != record['productCompilationInputHashes']:
            raise ValueError('Refresh is limited to packaging tools with unchanged product inputs')
        if any(inventory(base / name / 'bundle') != value for name, value in record['allBundleInventories'].items()):
            raise ValueError('A tested bundle changed')
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        retained = base / ('validation-before-tools-' + stamp + '.json')
        if retained.exists():
            raise ValueError('Preserve existing validation revisions')
        shutil.copy2(base / 'validation.json', retained)
        argv = [sys.executable, '-m', 'unittest', 'discover', '-s', 'tool', '-p', '*_test.py']
        log = base / ('python-tools-' + stamp + '.log')
        gate = {'name': 'python-tests', 'argv': argv, 'cwd': str(ROOT), 'startedUtc': utc(), 'log': log.name}
        with log.open('x') as stream:
            result = subprocess.run(argv, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
        gate.update(endedUtc=utc(), exitCode=result.returncode,
                    status='PASS' if result.returncode == 0 else 'FAIL', logSha256=digest(log))
        record['gates'].append(gate)
        record.setdefault('packagingToolRevisions', []).append({'changedInputs': sorted(changed),
            'previousValidation': retained.name, 'newHashes': current, 'gate': gate,
            'productAndAllBundleBytesUnchanged': True})
        if result.returncode == 0:
            record['verificationInputHashes'] = current
        write_json(base / 'validation.json', record)
        return result.returncode
    sdk = dart_sdk_directory(args.dart)
    base.mkdir(parents=True, exist_ok=False)
    dart = str(args.dart.absolute())
    env = {**os.environ, 'PATH': '/usr/bin:/bin:/opt/homebrew/bin:' + os.environ.get('PATH', '')}
    def output(argv):
        return subprocess.check_output(argv, cwd=ROOT, env=env, text=True).strip()
    record = {'buildId': base.name, 'directory': str(base), 'version': TARGET_VERSION,
        'createdUtc': utc(), 'sourceCommit': output(['git', 'rev-parse', 'HEAD']),
        'branch': output(['git', 'branch', '--show-current']),
        'worktreeStatus': output(['git', 'status', '--porcelain=v1', '--untracked-files=all']),
        'productCompilationInputHashes': product_inputs(),
        'verificationInputHashes': verification_inputs(), 'memberVersions': versions(),
        'toolchain': {'dart': output([dart, '--version']), 'dartExecutable': dart,
            'dartSdkDirectory': str(sdk), 'dartSdkVersion': (sdk / 'version').read_text().strip(),
            'python': sys.version, 'pythonExecutable': sys.executable,
            'os': platform.platform(), 'architecture': platform.machine(),
            'compiler': output(['/usr/bin/clang', '--version']), 'processPath': env['PATH']},
        'gates': []}
    flutter = sdk.parent / 'flutter.version.json'
    if flutter.exists():
        record['toolchain']['flutterCache'] = json.loads(flutter.read_text())
    write_json(base / 'validation.json', record)
    commands = [
        ('pub-get', '.', [dart, 'pub', 'get', '--enforce-lockfile']),
        ('generate', 'packages/meshchan_core', [dart, 'run', 'build_runner', 'build']),
        ('schema', 'packages/meshchan_core', [dart, 'run', 'tool/check_schema.dart']),
        ('generated-diff', '.', ['git', 'diff', '--exit-code', '--',
            'packages/meshchan_core/lib/src/storage/database.g.dart',
            'packages/meshchan_core/test/support/dependency_probe_database.g.dart',
            'packages/meshchan_core/drift_schemas', 'packages/meshchan_core/test/storage/generated']),
        ('format', '.', [dart, 'format', '--output=none', '--set-exit-if-changed', '.']),
        ('analyze', '.', [dart, 'analyze', '--fatal-infos']),
        ('python-tests', '.', [sys.executable, '-m', 'unittest', 'discover', '-s', 'tool', '-p', '*_test.py']),
        ('core-tests', 'packages/meshchan_core', [dart, 'test', '--reporter=expanded']),
        ('cli-tests', 'apps/meshctl', [dart, 'test', '--reporter=expanded']),
        ('link-tests', 'packages/meshcore_link', [dart, 'test', '--reporter=expanded']),
    ]
    for name, cwd, target in [('cli', 'apps/meshctl', 'bin/meshctl.dart'),
            ('observation', 'packages/meshcore_link', 'example/serial_transport_check.dart'),
            ('acceptance', 'apps/meshctl', 'tool/datagram_acceptance.dart')]:
        commands.append((name + '-build', cwd, [dart, 'build', 'cli', '--target=' + target,
            '--output=' + str(base / name)]))
    commands += [('smoke', '.', [sys.executable, 'tool/smoke_cli.py', '--dart', dart,
        '--cli-bundle', str(base / 'cli/bundle'), '--observation-bundle', str(base / 'observation/bundle'),
        '--datagram-acceptance-bundle', str(base / 'acceptance/bundle'),
        '--evidence-directory', str(base / 'recording-evidence')]),
        ('diff-check', '.', ['git', 'diff', '--check'])]
    for name, cwd, argv in commands:
        if name == 'smoke':
            record['allBundleInventories'] = {bundle: inventory(base / bundle / 'bundle')
                for bundle in ('cli', 'observation', 'acceptance')}
            record['runtimeInventory'] = record['allBundleInventories']['cli']
        log = base / (name + '.log')
        gate = {'name': name, 'argv': argv, 'cwd': str(ROOT / cwd), 'startedUtc': utc(), 'log': log.name}
        print('START ' + name, flush=True)
        with log.open('w') as stream:
            run = subprocess.run(argv, cwd=ROOT / cwd, env=env, stdout=stream, stderr=subprocess.STDOUT)
        gate.update(endedUtc=utc(), exitCode=run.returncode,
                    status='PASS' if run.returncode == 0 else 'FAIL', logSha256=digest(log))
        record['gates'].append(gate)
        write_json(base / 'validation.json', record)
        print(gate['status'] + ' ' + name + ': ' + str(log), flush=True)
        if run.returncode:
            return run.returncode
    if any(inventory(base / name / 'bundle') != value for name, value in record['allBundleInventories'].items()):
        raise ValueError('Bundle bytes changed during smoke')
    record['generationMapping'] = {'input': 'packages/meshchan_core/lib/src/storage/schema.drift',
        'database': 'packages/meshchan_core/lib/src/storage/database.dart',
        'output': 'packages/meshchan_core/lib/src/storage/database.g.dart',
        'schemaSnapshot': 'packages/meshchan_core/drift_schemas/drift_schema_v1.json'}
    record['nativeHookEvidenceHashes'] = {str(p.relative_to(ROOT)): digest(p)
        for p in sorted((ROOT / '.dart_tool/hooks_runner').rglob('*.json'))
        if p.name in ('input.json', 'output.json', 'dependencies.dependencies_hash_file.json')}
    record['nativeHookEvidenceHashes']['.dart_tool/package_config.json'] = digest(ROOT / '.dart_tool/package_config.json')
    record['inputsUnchanged'] = (product_inputs() == record['productCompilationInputHashes'] and
                                 verification_inputs() == record['verificationInputHashes'])
    record['endedUtc'] = utc()
    write_json(base / 'validation.json', record)
    graph = output([dart, 'pub', 'deps', '--json'])
    (base / 'resolved-dependencies.json').write_text(graph + '\n')
    return 0 if record['inputsUnchanged'] else 1


if __name__ == '__main__':
    sys.exit(main())
