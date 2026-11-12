"""Small shared checks for the Phase 1C local candidate, not a release service."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]
TARGET_VERSION = '0.1.0-dev.3'
MEMBERS = ('packages/meshcore_link', 'packages/meshchan_core', 'apps/meshctl')
REQUIRED_GATES = ('pub-get', 'generate', 'schema', 'generated-diff', 'format', 'analyze',
                  'python-tests', 'core-tests', 'cli-tests', 'link-tests',
                  'cli-build', 'observation-build', 'acceptance-build', 'smoke', 'diff-check')


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')


def dart_sdk_directory(dart):
    """Find an installed SDK, accepting its binary or the standard Flutter launcher."""
    executable = Path(dart).expanduser().resolve(strict=True)
    sdk = executable.parent.parent
    markers = ('LICENSE', 'version', 'include/dart_api.h', 'lib/core/core.dart')
    def installed(folder):
        return all((folder / name).is_file() for name in markers)
    if installed(sdk):
        return sdk
    # Homebrew's dart symlink resolves to Flutter's launcher, not SDK/bin/dart.
    # A framework LICENSE alone must never qualify that root as the Dart SDK.
    bundled = executable.parent / 'cache/dart-sdk'
    if (executable.name in ('dart', 'dart.bat')
            and (executable.parent / 'internal/shared.sh').is_file()
            and (bundled / 'bin/dart').is_file() and installed(bundled)):
        return bundled.resolve()
    raise ValueError('Cannot locate an installed Dart SDK; use its bin/dart or the standard Flutter dart launcher: ' + str(dart))


def versions(root=ROOT):
    result = {}
    texts = {}
    for member in MEMBERS:
        value = (root / member / 'pubspec.yaml').read_text()
        name = re.search(r'^name: (\S+)$', value, re.M)[1]
        version = re.search(r'^version: (\S+)$', value, re.M)[1]
        if version != TARGET_VERSION:
            raise ValueError('Member version mismatch: ' + name)
        result[name] = version
        texts[name] = value
    for owner, dependency in [('meshchan_core', 'meshcore_link'),
                              ('meshctl', 'meshchan_core'), ('meshctl', 'meshcore_link')]:
        if re.search(r'^  ' + dependency + r': (\S+)$', texts[owner], re.M)[1] != '^' + TARGET_VERSION:
            raise ValueError('Internal constraint mismatch: ' + owner)
    constant = (root / 'apps/meshctl/lib/src/version.dart').read_text()
    if re.search(r"const String meshctlVersion = '([^']+)';", constant)[1] != TARGET_VERSION:
        raise ValueError('CLI constant version mismatch')
    return result


def product_inputs(root=ROOT):
    files = [root / p for p in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')]
    for member in MEMBERS:
        files.append(root / member / 'pubspec.yaml')
        files.extend(p for p in (root / member / 'lib').rglob('*') if p.is_file())
        for config in ('build.yaml', 'dart_defines.json'):
            if (root / member / config).exists():
                files.append(root / member / config)
    files.extend(p for p in (root / 'apps/meshctl/bin').rglob('*') if p.is_file())
    return {str(p.relative_to(root)): digest(p) for p in sorted(set(files))}


def verification_inputs(root=ROOT):
    files = []
    for folder in ('tool', 'apps/meshctl/tool', 'apps/meshctl/test',
                   'packages/meshchan_core/test', 'packages/meshchan_core/tool',
                   'packages/meshcore_link/test', 'packages/meshcore_link/example'):
        files.extend(p for p in (root / folder).rglob('*')
                     if p.is_file() and p.suffix in ('.py', '.dart', '.yaml', '.json'))
    files.extend(root / p for p in ('.github/workflows/ci.yml',
        'apps/meshctl/dart_test.yaml', 'packages/meshchan_core/dart_test.yaml',
        'packages/meshchan_core/drift_schemas/drift_schema_v1.json'))
    return {str(p.relative_to(root)): digest(p) for p in sorted(set(files)) if p.exists()}


def inventory(folder):
    result = {}
    for path in sorted(folder.rglob('*')):
        if path.is_symlink() or not (path.is_file() or path.is_dir()):
            raise ValueError('Unsupported runtime member: ' + str(path))
        if path.is_file():
            result[str(path.relative_to(folder))] = {
                'sha256': digest(path), 'size': path.stat().st_size,
                'mode': stat.S_IMODE(path.stat().st_mode),
            }
    return result


def validate_runtime(files):
    if 'bin/meshctl' not in files or not files['bin/meshctl']['mode'] & 0o111:
        raise ValueError('Missing executable or execute permission')
    for component in ('serialport', 'sqlite3'):
        if not any(component in name.lower() and item['size'] > 0 for name, item in files.items()):
            raise ValueError('Missing native asset: ' + component)
    if any(re.search(r'(\.sqlite|\.db|\.wal|\.shm|\.owner|\.py|\.dart)$', p) for p in files):
        raise ValueError('Unexpected non-runtime asset')


def verify_sums(folder):
    sums = {}
    for line in (folder / 'SHA256SUMS').read_text().splitlines():
        value, name = line.split('  ', 1)
        path = PurePosixPath(name)
        if (not re.fullmatch(r'[0-9a-f]{64}', value) or path.is_absolute()
                or '..' in path.parts or str(path) != name or name in sums
                or name == 'SHA256SUMS' or digest(folder / name) != value):
            raise ValueError('Invalid member checksum')
        sums[name] = value
    if set(sums) != set(inventory(folder)) - {'SHA256SUMS'}:
        raise ValueError('Checksum file set differs')


def validate_gate(record, root=ROOT):
    if record['productCompilationInputHashes'] != product_inputs(root):
        raise ValueError('Product compilation inputs changed after validation')
    if record['verificationInputHashes'] != verification_inputs(root):
        raise ValueError('Acceptance tools changed after validation')
    for name, value in record.get('nativeHookEvidenceHashes', {}).items():
        if digest(root / name) != value:
            raise ValueError('Native hook/package-resolution evidence changed: ' + name)
    effective = {gate['name']: gate for gate in record['gates']}
    for name in REQUIRED_GATES:
        gate = effective.get(name)
        if not gate or gate.get('status') != 'PASS' or gate.get('exitCode') != 0:
            raise ValueError('Required gate missing or failed: ' + name)
        if digest(Path(record['directory']) / gate['log']) != gate['logSha256']:
            raise ValueError('Gate log changed: ' + name)
    versions(root)


def production_closure(graph):
    packages = {p['name']: p for p in graph['packages']}
    first_party = {p['name'] for p in graph['packages'] if p.get('source') in ('root', 'workspace')}
    first_party.add('meshctl')
    visited = set()
    def visit(name):
        if name in visited:
            return
        visited.add(name)
        for dependency in packages[name].get('directDependencies', []):
            visit(dependency)
    visit('meshctl')
    return packages, visited, first_party


def original_notices(folder):
    files = sorted(p for p in folder.iterdir() if p.is_file() and
                   p.name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE')))
    if not files:
        raise ValueError('Missing original production notice: ' + str(folder))
    return files


def extract_verified(archive, archive_hash, destination, top, expected):
    """Inspect exact names/types/modes before extracting any archive member."""
    if digest(archive) != archive_hash:
        raise ValueError('Archive bytes changed')
    expected_files = {top + '/' + name: item for name, item in expected.items()}
    expected_dirs = {top}
    for name in expected_files:
        expected_dirs.update(str(p) for p in PurePosixPath(name).parents if str(p) != '.')
    with tarfile.open(archive, 'r:gz') as tar:
        names, files, dirs = set(), set(), set()
        for member in tar.getmembers():
            path = PurePosixPath(member.name)
            if (member.name != str(path) or path.is_absolute() or '..' in path.parts
                    or member.name in names or not (member.isfile() or member.isdir())):
                raise ValueError('Unsafe or duplicate archive member')
            names.add(member.name)
            if member.isfile():
                files.add(member.name)
                wanted = expected_files.get(member.name)
                if (wanted is None or member.mode != wanted['mode'] or member.size != wanted['size']
                        or hashlib.sha256(tar.extractfile(member).read()).hexdigest() != wanted['sha256']):
                    raise ValueError('Archive member bytes/mode/size mismatch')
            else:
                dirs.add(member.name)
        if files != set(expected_files) or dirs != expected_dirs:
            raise ValueError('Archive member set differs')
        tar.extractall(destination, filter='data')
    extracted = destination / top
    if inventory(extracted) != expected:
        raise ValueError('Extracted file inventory differs')
    return extracted
