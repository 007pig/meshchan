#!/usr/bin/env python3
"""Generate a new external, locked macOS Companion BLE validation project."""

import argparse
import hashlib
import io
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path
from urllib.parse import unquote, urljoin, urlsplit
from urllib.request import urlopen


ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = Path('tool/ble_probe')
LINK = Path('packages/meshcore_link')
HOST_NAME = 'meshchan_ble_probe'
DISPLAY_NAME = 'Meshchan BLE Probe'
BUNDLE_ID = 'org.meshchan.probe.ble2a3'
PURPOSE = 'Scan for and check a Companion device you select with Bluetooth.'
BLE_VERSION = '6.2.1'
DARWIN = 'bluetooth_low_energy_darwin'
DARWIN_URL = f'https://pub.dev/api/archives/{DARWIN}-{BLE_VERSION}.tar.gz'
DARWIN_SHA256 = '63243add2f57ad201f09d42878a31bad6e5b93291c6ae3c36de24b5213178a0d'
HOSTED_PINS = {
    'bluetooth_low_energy':
        'ac70d6f95c54df943b40d58b0be6cce1ed49ae8b76219d03386cb6c56e06ba5a',
    'bluetooth_low_energy_platform_interface':
        '430a137fe0a662e2dd632390aa6e020a1c91335a5821ae07dacc9f319f9e590a',
}
MAX_ARCHIVE_BYTES = 8 * 1024 * 1024


def sha256(content):
    return hashlib.sha256(content).hexdigest()


def digest(path):
    return sha256(path.read_bytes())


def inventory(directory):
    return {file.relative_to(directory).as_posix(): digest(file)
            for file in sorted(directory.rglob('*')) if file.is_file()}


def git(root, *args):
    return subprocess.check_output(['git', '--no-optional-locks', *args], cwd=root)


def external_destination(root, path):
    lexical = Path(os.path.abspath(path))
    resolved = lexical.resolve()
    for candidate in (lexical, resolved):
        if candidate.is_relative_to(root) or root.is_relative_to(candidate):
            raise ValueError('Probe destination must be outside the product checkout')
    if lexical.is_symlink() or resolved.exists():
        raise ValueError('Probe destination must be a new directory')
    return resolved


def remove_workspace_resolution(original):
    lines = original.splitlines(keepends=True)
    workspace_line = b'resolution: workspace'
    if sum(line.rstrip(b'\r\n') == workspace_line for line in lines) != 1:
        raise ValueError('Expected exactly one workspace resolution in meshcore_link')
    return b''.join(line for line in lines if line.rstrip(b'\r\n') != workspace_line)


def copy_meshcore(root, source, destination):
    fixed_paths = ('LICENSE', 'COPYRIGHT', str(LINK / 'pubspec.yaml'))
    entries = git(root, 'ls-tree', '-r', '-z', source, '--', *fixed_paths,
                  str(LINK / 'lib')).split(b'\0')
    records = {}
    for entry in filter(None, entries):
        metadata, filename = entry.decode().split('\t', maxsplit=1)
        mode, kind, object_id = metadata.split()
        if kind != 'blob' or mode not in ('100644', '100755'):
            raise ValueError(f'Expected a regular tracked file at {filename}')
        original = git(root, 'cat-file', 'blob', object_id)
        repository_path = Path(filename)
        relative = (repository_path.relative_to(LINK)
                    if repository_path.is_relative_to(LINK) else repository_path)
        contents = (remove_workspace_resolution(original)
                    if relative == Path('pubspec.yaml') else original)
        output = destination / relative
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(contents)
        checkout_file = root / repository_path
        working_hash = (digest(checkout_file)
                        if checkout_file.is_file() and not checkout_file.is_symlink() else None)
        records[filename] = {'vendorPath': relative.as_posix(), 'gitBlob': object_id,
                             'sourceSha256': sha256(original), 'vendorSha256': sha256(contents),
                             'worktreeSha256': working_hash}
    if not {*fixed_paths, str(LINK / 'lib/meshcore_link.dart')} <= records.keys():
        raise ValueError('The selected source is missing required meshcore_link inputs')
    return records


def read_darwin_archive(local_archive):
    with (local_archive.open('rb') if local_archive else urlopen(DARWIN_URL, timeout=30)) as stream:
        archive = stream.read(MAX_ARCHIVE_BYTES + 1)
    if len(archive) > MAX_ARCHIVE_BYTES or sha256(archive) != DARWIN_SHA256:
        raise ValueError('Darwin release archive does not match the pinned SHA-256')
    return archive


def copy_darwin(archive, destination, observation_patch, lifecycle_patch):
    destination.mkdir()
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as source:
        members = source.getmembers()
        if any(not (entry.isfile() or entry.isdir()) for entry in members):
            raise ValueError('The Darwin release archive contains a non-regular entry')
        source.extractall(destination, members=members, filter='data')
    original = inventory(destination)
    # The release digest fixes the exact base for the ordered patches.
    apply_patch = ['git', 'apply', '--unidiff-zero', '--whitespace=nowarn']
    for patch in (observation_patch, lifecycle_patch):
        subprocess.run([*apply_patch, '--check', str(patch)], cwd=destination, check=True)
        subprocess.run([*apply_patch, str(patch)], cwd=destination, check=True)
    patched = inventory(destination)
    if any(original[name] != patched.get(name) for name in ('LICENSE', 'pubspec.yaml')):
        raise ValueError('Darwin patches changed license or dependency inputs')
    if patched == original:
        raise ValueError('No Darwin observation changes were applied')
    return {'archiveUrl': DARWIN_URL, 'archiveSha256': DARWIN_SHA256, 'version': BLE_VERSION,
            'upstreamCommit': 'b97633b24405ace7dea0f0b30a08c0599aece19e',
            'observationPatchSha256': digest(observation_patch),
            'lifecyclePatchSha256': digest(lifecycle_patch),
            'originalFiles': original, 'patchedFiles': patched}


def configure_macos(host):
    macos = host / 'macos'
    runner = macos / 'Runner'
    app_info = runner / 'Configs/AppInfo.xcconfig'
    app_info.write_text(f'PRODUCT_NAME = {DISPLAY_NAME}\n'
                        f'PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID}\n'
                        'PRODUCT_COPYRIGHT = Copyright © Meshchan contributors.\n'
                        'CODE_SIGN_IDENTITY = -\n'
                        'CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO\n')
    info_path = runner / 'Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info.update(CFBundleDisplayName=DISPLAY_NAME, NSBluetoothAlwaysUsageDescription=PURPOSE)
    info_path.write_bytes(plistlib.dumps(info, sort_keys=False))
    (runner / 'DebugProfile.entitlements').write_bytes(plistlib.dumps({
        'com.apple.security.cs.allow-jit': True,
    }))
    (runner / 'Release.entitlements').write_bytes(plistlib.dumps({}))
    project = macos / 'Runner.xcodeproj/project.pbxproj'
    contents = project.read_text()
    if 'CODE_SIGN_STYLE = Automatic;' not in contents or 'DEVELOPMENT_TEAM' in contents:
        raise ValueError('Unexpected macOS signing settings in SDK template')
    project.write_text(contents.replace('CODE_SIGN_STYLE = Automatic;', 'CODE_SIGN_STYLE = Manual;'))


def template_overlays(directory):
    files = {Path('pubspec.lock'): directory / 'pubspec.lock'}
    for name in ('pubspec.yaml', 'analysis_options.yaml'):
        files[Path(name)] = directory / f'{name}.template'
    for folder in ('lib', 'test', 'macos'):
        pattern = '*.swift' if folder == 'macos' else '*.dart.txt'
        for path in sorted((directory / folder).rglob(pattern)):
            if path.is_file():
                relative = path.relative_to(directory)
                files[relative if folder == 'macos' else relative.with_suffix('')] = path
    if Path('lib/main.dart') not in files or not any(path.parts[0] == 'test' for path in files):
        raise ValueError('Probe main and test templates are required')
    if any(not path.is_file() or path.is_symlink() for path in files.values()):
        raise ValueError('Probe templates must be regular files')
    return files


def verify_resolution(host, root, expected_lock):
    actual_lock = (host / 'pubspec.lock').read_bytes()
    if expected_lock != actual_lock:
        raise ValueError('Enforced Pub resolution changed the supplied lockfile')
    for name, checksum in HOSTED_PINS.items():
        # Verify the release archive pins in Pub's canonical generated lock format.
        entry = re.search(rf'^  {name}:\n((?: {{4}}[^\n]*\n)+)', actual_lock.decode(), re.M)
        if entry is None or not re.search(rf'^      sha256: "?{checksum}"?$', entry[1], re.M):
            raise ValueError(f'Resolved hosted archive does not match the release pin for {name}')

    dart_tool = host / '.dart_tool'
    graph_path = dart_tool / 'package_graph.json'
    graph = json.loads(graph_path.read_bytes())
    versions = {item['name']: item['version'] for item in graph['packages']}
    for name in (*HOSTED_PINS, DARWIN):
        if versions.get(name) != BLE_VERSION:
            raise ValueError(f'Expected {name} {BLE_VERSION} in the resolved probe graph')
    config_path = dart_tool / 'package_config.json'
    config = json.loads(config_path.read_bytes())
    package_paths = {}
    for item in config['packages']:
        uri = urlsplit(urljoin(config_path.as_uri(), item['rootUri']))
        if uri.scheme != 'file' or uri.netloc:
            raise ValueError('Expected local package roots in the probe package configuration')
        path = Path(unquote(uri.path)).resolve()
        if path.is_relative_to(root):
            raise ValueError('Probe dependency resolves inside the live product checkout')
        package_paths[item['name']] = path
    for name in ('meshcore_link', DARWIN):
        if package_paths.get(name) != host.parent / 'vendor' / name:
            raise ValueError(f'{name} is not resolved from its private vendor copy')
    return {'versions': versions, 'packageConfigSha256': digest(config_path),
            'packageGraphSha256': digest(graph_path),
            'lockSha256': sha256(actual_lock)}


def prepare(root, path, flutter, source, local_archive, offline):
    target = external_destination(root, path)
    if not flutter.is_absolute() or not flutter.is_file() or not os.access(flutter, os.X_OK):
        raise ValueError('Provide the installed Flutter executable as an absolute path')
    head = git(root, 'rev-parse', 'HEAD').decode().strip()
    source_commit = git(root, 'rev-parse', '--verify', '--end-of-options',
                        f'{source}^{{commit}}').decode().strip()
    status_paths = ('tool/prepare_ble_probe.py', str(TEMPLATE), str(LINK), 'LICENSE', 'COPYRIGHT')
    inputs_status = git(root, 'status', '--short', '--untracked-files=all', '--', *status_paths)
    worktree_has_changes = bool(git(root, 'status', '--short'))
    root_lock_sha = digest(root / 'pubspec.lock')
    overlay = template_overlays(root / TEMPLATE)
    expected_lock = overlay[Path('pubspec.lock')].read_bytes()
    archive = read_darwin_archive(local_archive)
    target.mkdir(mode=0o700)
    host = target / 'host'
    evidence = target / 'evidence'
    evidence.mkdir()
    observation_patch = evidence / 'darwin-observation.patch'
    lifecycle_patch = evidence / 'darwin-lifecycle.patch'
    for patch in (observation_patch, lifecycle_patch):
        shutil.copyfile(root / TEMPLATE / patch.name, patch)
    vendor = target / 'vendor'
    vendor.mkdir()
    link = copy_meshcore(root, source_commit, vendor / 'meshcore_link')
    darwin = copy_darwin(archive, vendor / DARWIN, observation_patch, lifecycle_patch)

    commands = []
    flutter_env = {**os.environ, 'FLUTTER_SUPPRESS_ANALYTICS': 'true'}

    def flutter_run(*args, cwd, capture=False):
        argv = [str(flutter), '--no-version-check', *args]
        commands.append({'argv': argv, 'cwd': str(cwd)})
        return subprocess.run(argv, cwd=cwd, env=flutter_env, check=True,
                              stdout=subprocess.PIPE if capture else None).stdout

    sdk = json.loads(flutter_run('--version', '--machine', cwd=target, capture=True))
    flutter_run('create', '--platforms=macos', '--no-pub', '--empty',
                f'--project-name={HOST_NAME}', '--org=org.meshchan.probe', str(host), cwd=target)
    for folder in ('lib', 'test'):
        stock_folder = host / folder
        if stock_folder.is_dir():
            shutil.rmtree(stock_folder)
    template_hashes = {}
    for relative, template in overlay.items():
        contents = template.read_bytes()
        output = host / relative
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(contents)
        template_hashes[template.relative_to(root).as_posix()] = sha256(contents)
    configure_macos(host)
    before_pub = inventory(host)
    pub_flags = ('--offline',) if offline else ()
    flutter_run('pub', 'get', '--enforce-lockfile', *pub_flags, cwd=host)
    resolution = verify_resolution(host, root, expected_lock)
    if digest(root / 'pubspec.lock') != root_lock_sha:
        raise ValueError('The product root lockfile changed during generation')

    receipt = {
        'sourceHead': head, 'meshcoreSourceCommit': source_commit,
        'sourceBranch': git(root, 'rev-parse', '--abbrev-ref', 'HEAD').decode().strip(),
        'worktreeHasChanges': worktree_has_changes,
        'worktreeProbeInputStatus': inputs_status.decode().splitlines(),
        'rootLockSha256': root_lock_sha,
        'meshcoreLinkFiles': link, 'darwinObservation': darwin,
        'probeTemplateSha256s': template_hashes,
        'generatorSha256': digest(root / 'tool/prepare_ble_probe.py'),
        'hostInputsBeforePub': before_pub, 'sdk': sdk,
        'python': {'path': sys.executable, 'version': sys.version.split()[0]},
        'generatorInputs': {'destination': str(target), 'sourceReference': source,
                            'offlinePub': offline, 'darwinArchiveProvidedLocally': bool(local_archive)},
        'commands': commands, 'dependencies': resolution,
        'probeOnlyChanges': ['remove resolution: workspace from copied meshcore_link manifest',
                             'apply the observation patch to the private Darwin release copy',
                             'apply the connection lifecycle fixes to the observed Darwin copy',
                             'replace stock Dart files, add tests, and configure the probe runner'],
    }
    (evidence / 'probe-source.json').write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', required=True, type=Path, help='New external directory')
    parser.add_argument('--flutter', required=True, type=Path, help='Absolute SDK Flutter executable')
    parser.add_argument('--source', default='HEAD', help='Git commit for the meshcore_link snapshot')
    parser.add_argument('--darwin-archive', type=Path, help='Local copy of the pinned pub.dev release')
    parser.add_argument('--offline', action='store_true', help='Resolve the locked Pub cache offline')
    args = parser.parse_args()
    try:
        target = prepare(ROOT, args.destination, args.flutter, args.source,
                         args.darwin_archive, args.offline)
    except (OSError, ValueError, subprocess.CalledProcessError, tarfile.TarError) as error:
        parser.exit(1, f'BLE probe preparation failed: {error}\n')
    print(json.dumps({'prepared': str(target), 'receipt': str(target / 'evidence/probe-source.json')}))


if __name__ == '__main__':
    main()
