#!/usr/bin/env python3
"""Collect and independently recheck macOS App/CLI distribution review materials.

No release publication, dependency resolution, SDK mutation, or hardware access.
A review package may be collected with open gates; check always fails those gates.
"""
import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from urllib.parse import unquote, urljoin, urlparse

from release_sdk_sources import (cached_source_file, dart_sdk_metadata_file, flutter_cache_metadata_file,
                                 publish_verified_download)

from candidate_common import ROOT, digest, production_closure, versions

PRODUCTS = ('meshchan_app', 'meshctl')
FIRST_PARTY = {'meshchan_app', 'meshctl', 'meshchan_core', 'meshcore_link'}
NOTICE = re.compile(r'^(license|copying|notice|copyright)([._-].*)?$', re.I)
VM_SKILL = '.agents/skills/macos-vm-gui-testing/'
RELEASE_ENTRY_SOURCE_FILES = ('.gitignore', 'tool/build_release.py', 'docs/releases/phase-1e4-build.md',
                              'docs/macos-vm-gui-testing.md',
                              *(VM_SKILL+name for name in (
                                  'SKILL.md', 'config.example.json', 'scripts/vm.py', 'scripts/askpass.sh',
                                  'scripts/guest.sh', 'scripts/stop-guest.sh', 'scripts/pinyin.sh',
                                  'scripts/check_tooling.py', 'scripts/native/Info.plist', 'scripts/native/Probe.m',
                                  'scripts/native/KeyInput.m', 'scripts/native/PlaceWindow.m', 'scripts/native/IMEInspect.m',
                              )))
VALIDATION_REPORTS = {'docs/validation/phase-1e3-materials.md', 'docs/validation/phase-1e4-build.md'}
MATERIAL_ICONS_FONT = 'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
SHADER_INCLUDE_DIR = 'bin/cache/artifacts/engine/darwin-x64/shader_lib'
SHADER_INCLUDE_SOURCE = 'engine/src/flutter/impeller/compiler/shader_lib'
FRAMEWORK_SHADERS = ('packages/flutter/lib/src/material/shaders/ink_sparkle.frag',
                     'packages/flutter/lib/src/widgets/shaders/stretch_effect.frag')
PACKAGE_CONFIG = '.dart_tool/package_config.json'
HOOK_CACHE = '.dart_tool/hooks_runner'
NATIVE_HOOK_SNAPSHOT = 'native-hooks'
FRESH_HOOK_RECIPE = 45
ASSET_INPUT_RECIPE = 47
COMPLETE_ASSET_RECIPE = 49
NATIVE_SOURCE_PACKAGES = frozenset(('libserialport_plus', 'sqlite3'))


def is_notice_declaration(name):
    return name.casefold() == 'notices' or NOTICE.match(name) is not None


def controlled_environment():
    # Only OS/user-location variables are inherited. Git, compiler, Flutter,
    # Dart, dyld, signing and version overrides cannot change the recipe.
    env = {k: os.environ[k] for k in ('HOME', 'TMPDIR', 'USER', 'LOGNAME') if k in os.environ}
    env.update(PATH='/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin', LANG='en_US.UTF-8', LC_ALL='en_US.UTF-8',
               GIT_NO_REPLACE_OBJECTS='1')
    return env


def run(argv, cwd=None, *, env=None):
    return subprocess.check_output([str(a) for a in argv], cwd=cwd, env=env, text=True)


def encoded(value):
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + '\n').encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def safe(name):
    p = PurePosixPath(name)
    if p.is_absolute() or '..' in p.parts or str(p) != name:
        raise ValueError('Unsafe material path: ' + name)
    return name


def directory_identity(path):
    try:
        stat = path.stat()
    except (FileNotFoundError, NotADirectoryError):
        return None
    return stat.st_dev, stat.st_ino


def ancestor_identities(path):
    # resolve() does not restore filesystem spelling on case-insensitive Macs.
    # Include existing ancestors of a cache or destination not yet created.
    return {identity for ancestor in (path, *path.parents)
            if (identity := directory_identity(ancestor)) is not None}


def require_product_disjoint(paths, products, *, protected='a candidate product'):
    """Keep material writers and their cache roots separate from products."""
    products = [product.resolve() for product in products]
    product_details = [(product, directory_identity(product), ancestor_identities(product))
                       for product in products]
    for label, path in paths.items():
        if path is None:
            continue
        path = path.resolve()
        identity, ancestors = directory_identity(path), ancestor_identities(path)
        if any(path.is_relative_to(product) or product.is_relative_to(path)
               or product_identity in ancestors or identity in product_ancestors
               for product, product_identity, product_ancestors in product_details):
            raise ValueError(f'{label} overlaps {protected}: {path}')


def repository_source_path(root, name):
    path = root/safe(name)
    if path.parent.resolve() != path.parent:
        raise ValueError('Aliased source directory: '+name)
    return path


def verify_source_link(root, path):
    name = path.relative_to(root).as_posix()
    verify_product_path_steps(root, path.parent, os.readlink(path), 'corresponding-source symlink: '+name, {path})


def repository_source_hashes(root, generated, *, command=None, label='repository-source'):
    """Exclude declared staging/cache trees in both collect and fresh check."""
    root = root.resolve()
    generated = [p.resolve() for p in generated if p is not None]
    # Enumerate the index and filesystem directly. An optional Git monitor
    # can run an external process even for ls-files.
    ls_files = ['git', '-c', 'core.fsmonitor=false', 'ls-files']

    def enumerate_files(kind, args):
        argv = [*ls_files, *args, '-z']
        if command is None:
            return run(argv, root, env=controlled_environment()).split('\0')
        return command(f'{label}-{kind}', argv, root).split('\0')

    tracked = enumerate_files('tracked', ['--cached'])
    if any(p == root or p.is_relative_to(root/'.git') for p in generated):
        raise ValueError('Generated directories must not contain the repository or Git metadata')
    for name in filter(None, tracked):
        if any((root/name).is_relative_to(p) for p in generated):
            raise ValueError('Generated directory overlaps tracked source: '+name)
    names = enumerate_files('all', ['--cached', '--others', '--exclude-standard'])
    files = {}
    for name in sorted(set(filter(None, names)) - VALIDATION_REPORTS):
        if any((root/name).is_relative_to(path) for path in generated):
            continue
        source = repository_source_path(root, name)
        if source.is_file():
            if source.is_symlink():
                verify_source_link(root, source)
            files[name] = digest(source)
    return files


def flutter_asset_files(path):
    """Find file declarations and variants selected by Flutter's asset cache."""
    if path.is_dir():
        return [path, *(variant for child in path.iterdir() if child.is_file()
                        for variant in flutter_asset_files(child))]
    files = [path] if path.is_file() else []
    if path.parent.is_dir():
        for directory in path.parent.iterdir():
            if re.search(r'[0-9]+(?:\.[0-9]*)?x$', directory.name) and directory.is_dir():
                variant = directory/path.name
                if variant.is_file():
                    files.append(variant)
    return files or [path]  # Keep the missing-input diagnostic.


def flutter_shader_includes(shader, app, root, sdk_includes, *, external_roots=()):
    """Find literal include dependencies using the pinned Impeller search order."""
    include_dirs = (app, shader.parent)
    if sdk_includes is not None:
        include_dirs += (sdk_includes,)
    pending = [shader]
    seen, local = set(), set()
    while pending:
        source = pending.pop()
        if source in seen:
            continue
        seen.add(source)
        content = source.read_text(encoding='utf-8').replace('\\\n', '')
        content = re.sub(r'"[^"\n]*"|/\*.*?\*/|//[^\n]*',
                         lambda match: match[0] if match[0].startswith('"') else ' '+'\n'*match[0].count('\n'),
                         content, flags=re.DOTALL)
        for directive in re.findall(r'^\s*#\s*include\b([^\n]*)', content, re.MULTILINE):
            operand = re.fullmatch(r'\s*(?:"([^"]+)"|<([^>]+)>)\s*', directive)
            if not operand:
                raise ValueError('Cannot bind nonliteral Flutter shader include: '+str(source))
            name = operand[1] or operand[2]
            if Path(name).is_absolute():
                raise ValueError('Flutter shader includes must use relative paths: '+name)
            for directory in include_dirs:
                candidate = directory/name
                if not candidate.is_file():
                    continue  # An inactive preprocessor branch may name an absent file.
                resolved = candidate.resolve()
                if resolved != Path(os.path.abspath(candidate)).resolve():
                    raise ValueError('Ambiguous Flutter shader include traversal: '+str(candidate))
                if directory == sdk_includes and resolved.is_relative_to(sdk_includes.resolve()):
                    pending.append(resolved)
                    break  # The SDK shader include tree is fingerprinted separately.
                if not any(resolved.is_relative_to(folder) for folder in (root, *external_roots)):
                    raise ValueError('Flutter shader include outside verified source roots: '+str(candidate))
                local.add(resolved)
                pending.append(resolved)
                break
    return local


def compilation_inputs(root, members, *, flutter=None):
    """Derive product inputs from source layout/pubspecs, never a build record.

    SDK, hosted native hooks and generated build settings have separate identity
    checks. This inventory covers first-party source, generation configuration,
    declared resources and stable native project inputs for both macOS products.
    """
    if set(members) != FIRST_PARTY:
        raise ValueError('Compilation inventory requires four workspace members')
    app = root/safe(members['meshchan_app']['path'])
    sdk_includes = flutter/SHADER_INCLUDE_DIR if flutter is not None else None
    files = {root/p for p in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')}
    ignored = {'ephemeral', 'xcuserdata', 'Pods', '.symlinks', '.dart_tool', 'build', 'RunnerTests'}

    def add(path, native=False):
        if not path.resolve().is_relative_to(root.resolve()):
            raise ValueError('Compilation input outside repository: '+str(path))
        if path.is_file():
            files.add(path)
        elif path.is_dir():
            for child in path.rglob('*'):
                parts = child.relative_to(path).parts
                if native and (set(parts) & ignored or child.name in (
                        '.gitignore', '.DS_Store', 'IDEWorkspaceChecks.plist')):
                    continue
                if child.is_file():
                    add(child)
        else:
            raise ValueError('Missing compilation input: '+str(path))

    def add_declarations(folder):
        # Flutter prefers the package's NOTICES file over LICENSE. Capture
        # both, as well as the other first-party license declarations.
        for declaration in folder.iterdir():
            if is_notice_declaration(declaration.name) and declaration.is_file():
                add(declaration)

    add_declarations(root)
    for name, member in sorted(members.items()):
        folder = root/safe(member['path'])
        files.add(folder/'pubspec.yaml')
        add_declarations(folder)
        add(folder/'lib')
        for subdir in ('bin', 'hook', 'macos'):
            if (folder/subdir).exists():
                add(folder/subdir, native=subdir == 'macos')
        for config in ('build.yaml', 'dart_defines.json', '.metadata'):
            if (folder/config).is_file():
                files.add(folder/config)
        resources = member['spec'].get('flutter', {})
        for entry in resources.get('assets') or []:
            asset = entry if isinstance(entry, str) else entry['path']
            if isinstance(entry, dict) and entry.get('transformers'):
                raise ValueError('Release input inventory cannot bind transformed Flutter asset: '+asset)
            for path in flutter_asset_files(folder/safe(asset.rstrip('/'))):
                add(path)
        for declaration in member['resolvedShaders'] if resources.get('shaders') else ():
            shader = Path(declaration['path'])
            if declaration['transformed']:
                raise ValueError('Release input inventory cannot bind transformed Flutter shader: '+str(shader))
            if declaration['packageQualified'] and not shader.is_relative_to(root):
                continue  # External shader files are bound through the App asset depfile.
            for path in flutter_asset_files(shader):
                add(path)
                for dependency in flutter_shader_includes(path, app, root, sdk_includes):
                    add(dependency)
        for family in resources.get('fonts') or []:
            for font in family['fonts']:
                add(folder/safe(font['asset']))
        for license_path in resources.get('licenses') or []:
            uri = urlparse(urljoin(folder.as_uri()+'/', license_path))
            if uri.scheme != 'file' or uri.netloc or uri.query or uri.fragment:
                raise ValueError('Flutter license must resolve to a local file: '+license_path)
            path = Path(unquote(uri.path))
            if not path.is_relative_to(root) or '..' in path.parts or not path.is_file():
                raise ValueError('Missing or out-of-repository Flutter license: '+license_path)
            add(path)
        if name == 'meshchan_app':
            files.update(folder/p for p in ('lib/main.dart', 'macos/Runner/Info.plist',
                                           'macos/Runner.xcodeproj/project.pbxproj'))
        elif name == 'meshctl':
            files.add(folder/'bin/meshctl.dart')
    if flutter is not None:
        for relative in FRAMEWORK_SHADERS:
            shader = flutter/relative
            if shader.parent.is_dir():  # Same inclusion condition as the pinned Flutter tool.
                for dependency in flutter_shader_includes(shader, app, root, sdk_includes):
                    add(dependency)
    return {p.relative_to(root).as_posix(): digest(p) for p in sorted(files)}


def compilation_record_errors(root, required, observed):
    if not isinstance(observed, dict):
        return ['Candidate compilation input record must be a path-to-SHA-256 object']
    failures = []
    missing = sorted(required.keys()-observed.keys())
    if missing:
        failures.append('Candidate compilation input record is incomplete; missing: '+', '.join(missing))
    for name, value in sorted(observed.items()):
        try:
            safe(name)
        except ValueError:
            failures.append('Unsafe compilation input record path: '+name)
            continue
        path = root/name
        if (not isinstance(value, str) or not re.fullmatch('[a-f0-9]{64}', value)
                or not path.resolve().is_relative_to(root.resolve()) or not path.is_file()
                or digest(path) != value):
            failures.append('Candidate compilation input missing/changed or malformed: '+name)
    return failures


def require_regular_file(path):
    if not stat.S_ISREG(path.lstat().st_mode):
        raise ValueError('Expected a regular file: '+str(path))
    return path


def compiler_hosted_inputs(report):
    """Merge the receipt-bound, package-relative compiler inputs for both products."""
    phases = report.get('hosted') if isinstance(report, dict) else None
    if not isinstance(phases, dict) or set(phases) != {'app', 'cli'}:
        raise ValueError('Compiler input report lacks hosted archive evidence; prepare a new candidate')
    combined = {}
    for phase, packages in phases.items():
        if not isinstance(packages, dict):
            raise ValueError('Invalid hosted compiler input inventory for '+phase)
        for name, files in packages.items():
            if not isinstance(files, dict) or not files:
                raise ValueError('Invalid hosted compiler file inventory for '+name)
            verified = combined.setdefault(name, {})
            for relative, expected in files.items():
                safe(relative)
                if not isinstance(expected, str) or not re.fullmatch('[0-9a-f]{64}', expected):
                    raise ValueError(f'Invalid hosted compiler input hash: {name}/{relative}')
                if verified.setdefault(relative, expected) != expected:
                    raise ValueError(f'Hosted compiler input changed between App and CLI: {name}/{relative}')
    return combined


def build_hosted_notices(report):
    notices = report.get('hostedNotices')
    if not isinstance(notices, dict):
        raise ValueError('Compiler input report lacks hosted notice evidence; prepare a new candidate')
    for name, notice in notices.items():
        if notice is None:
            continue
        if (not isinstance(notice, dict) or not isinstance(notice.get('path'), str)
                or PurePosixPath(safe(notice['path'])).name not in ('NOTICES', 'LICENSE')
                or not isinstance(notice.get('sha256'), str) or not re.fullmatch('[0-9a-f]{64}', notice['sha256'])):
            raise ValueError('Invalid build-time hosted notice for '+name)
    return notices


def verify_build_receipt(root, path, inputs, checksums, app, cli):
    """Verify an optional contemporaneous build ledger and its local evidence."""
    receipt = json.loads(require_regular_file(path).read_text())
    require_regular_file(inputs)
    require_regular_file(checksums)
    if (receipt.get('formatVersion') != 1 or receipt.get('status') != 'PASS'
            or receipt.get('inputsUnchangedAcrossBuilds') is not True
            or receipt.get('compilationInputsSha256') != digest(inputs)
            or receipt.get('candidateChecksumsSha256') != digest(checksums)
            or (root/safe(receipt['app'])).resolve() != app.resolve()
            or (root/safe(receipt['cli'])).resolve() != cli.resolve()):
        raise ValueError('Build receipt does not bind candidate inputs/checksums/products')
    before = json.loads(inputs.read_text())
    companions = {}
    for name in ('compilation-input-hashes.json', 'inputs-after-cli.json', 'inputs-after-app.json'):
        companion = require_regular_file(path.parent/name)
        if json.loads(companion.read_text()) != before:
            raise ValueError('Build input snapshot differs: '+name)
        companions[name] = companion
    script = require_regular_file(path.parent/'run_build.py')
    if digest(script) != receipt.get('runnerSha256'):
        raise ValueError('Build ledger runner source changed')
    companions['run_build.py'] = script
    bindings = {'candidateInventoriesSha256': 'candidate-inventories.json',
                'resolvedGraphSha256': 'resolved-graph.json',
                'productChecksSha256': 'product-checks.json'}
    compiler_binding = 'compilerInputsSha256'
    # Verify every supplied binding. Recipe 8 predates the product report;
    # unversioned format-1 receipts predate the required complete bindings.
    if 'recipeVersion' in receipt:
        recipe = receipt['recipeVersion']
        if type(recipe) is not int or recipe < 1:
            raise ValueError('Invalid build receipt recipe version')
        required = set(bindings) - {'productChecksSha256'} if recipe == 8 else set(bindings)
        if recipe >= 40:
            required.add(compiler_binding)
        if missing := required - receipt.keys():
            raise ValueError('Versioned build receipt lacks required bindings: '+', '.join(sorted(missing)))
    bindings[compiler_binding] = 'compiler-inputs.json'
    for key, name in bindings.items():
        if key in receipt:
            companion = path.parent/name
            if not stat.S_ISREG(companion.lstat().st_mode) or digest(companion) != receipt[key]:
                raise ValueError('Build receipt binding differs for '+name)
            companions[name] = companion
    if compiler := companions.get('compiler-inputs.json'):
        report = json.loads(compiler.read_text())
        if receipt.get('recipeVersion', 0) >= 41:
            compiler_hosted_inputs(report)
        if receipt.get('recipeVersion', 0) >= 42:
            build_hosted_notices(report)
        depfiles = report['depfileHashes']
        app_depfiles = [match[1] for name in depfiles if (match := re.fullmatch(r'compiler/app-(\d+)\.d', name))]
        if 'compiler/cli.d' not in depfiles or not app_depfiles:
            raise ValueError('Build receipt lacks actual CLI and App compiler depfiles')
        if receipt.get('recipeVersion', 0) >= 43 and any(
                f'compiler/app-assets-{number}.d' not in depfiles for number in app_depfiles):
            raise ValueError('Build receipt lacks actual Flutter asset depfiles')
        for name, expected in depfiles.items():
            if digest(require_material_file(path.parent, name)) != expected:
                raise ValueError('Build receipt compiler depfile changed: '+name)
    if inventory := companions.get('candidate-inventories.json'):
        if json.loads(inventory.read_text()) != {'app': product_inventory(app), 'cli': product_inventory(cli)}:
            raise ValueError('Identity drift during actual product inventory')
    verify_native_hook_cache(path, receipt)
    steps = receipt.get('steps', [])
    if not {'cli-build', 'app-build'} <= {s.get('name') for s in steps}:
        raise ValueError('Build receipt lacks actual App/CLI build steps')
    for step in steps:
        log = root/safe(step['log'])
        if step.get('exitCode') != 0 or digest(require_regular_file(log)) != step.get('logSha256'):
            raise ValueError('Build command failed or log changed: '+str(step.get('name')))
        if 'stderrLog' in step and digest(require_regular_file(root/safe(step['stderrLog']))) != step.get('stderrLogSha256'):
            raise ValueError('Build command stderr log changed: '+str(step.get('name')))
    return receipt, companions


def source_entry_metadata(path):
    mode = path.lstat().st_mode
    if stat.S_ISREG(mode):
        return {'type': 'file', 'executable': bool(mode & 0o111)}
    if stat.S_ISLNK(mode):
        return {'type': 'symlink', 'target': os.readlink(path)}
    raise ValueError('Unsupported corresponding-source input: '+str(path))


def repository_source_metadata(root, source_hashes):
    root = root.resolve()
    return {name: source_entry_metadata(repository_source_path(root, name)) for name in source_hashes}


def verify_frozen_source_metadata(root, commit, metadata):
    tree = run(['git', 'ls-tree', '-r', '-z', '--full-tree', commit], root, env=controlled_environment())
    modes = {}
    for entry in filter(None, tree.split('\0')):
        header, name = entry.split('\t', 1)
        modes[name] = header.split(' ', 1)[0]
    # Frozen Release builds only accept regular source files from the Git tree.
    for name, item in metadata.items():
        expected = {'100644': {'type': 'file', 'executable': False},
                    '100755': {'type': 'file', 'executable': True}}.get(modes.get(name))
        if item != expected:
            raise ValueError('Corresponding source metadata differs from the recorded commit: '+name)


def receipt_prebuild_identities(receipt_path, receipt):
    path = require_material_file(receipt_path.parent, 'prebuild-identities.json')
    data = path.read_bytes()
    if sha(data) != receipt.get('prebuildIdentitiesSha256'):
        raise ValueError('Prebuild source evidence differs from the candidate build receipt')
    prebuild = json.loads(data)
    if not isinstance(prebuild, dict):
        raise ValueError('Invalid prebuild source evidence')
    return prebuild


def verify_build_package_config(receipt, prebuild, config_hash):
    if receipt['recipeVersion'] < ASSET_INPUT_RECIPE:
        return
    config = prebuild.get('configuration')
    if not isinstance(config, dict) or config_hash is None or config.get(PACKAGE_CONFIG) != config_hash:
        raise ValueError('Workspace package configuration differs from the candidate build receipt')


def verify_build_source(root, receipt_path, receipt, commit, source_hashes, *, package_config_hash=None):
    if receipt.get('recipeVersion', 0) < 22:
        return None  # Preserve the historical materials contract.
    if receipt.get('sourceCommit') != commit:
        raise ValueError('Checkout commit differs from the candidate build receipt')
    prebuild = receipt_prebuild_identities(receipt_path, receipt)
    if prebuild.get('source') != source_hashes:
        raise ValueError('Repository source map differs from the candidate build receipt')
    verify_build_package_config(receipt, prebuild, package_config_hash)
    metadata = repository_source_metadata(root, source_hashes)
    recorded = prebuild.get('sourceMetadata')
    dirty = receipt.get('engineeringDirtyMode')
    if dirty is not False or receipt['recipeVersion'] >= 33:
        if not isinstance(recorded, dict):
            raise ValueError('Build receipt lacks source metadata evidence; prepare a new candidate')
    if recorded is not None and metadata != recorded:
        raise ValueError('Repository source metadata differs from the candidate build receipt')
    if dirty is False:
        verify_frozen_source_metadata(root, commit, metadata)
    return metadata


def source_archive(folder, names, *, expected_hashes=None, expected_metadata=None):
    """Deterministic source snapshot; never traverses ignored build/cache trees."""
    folder = folder.resolve()
    data = io.BytesIO()
    hashes = {}
    with gzip.GzipFile(fileobj=data, mode='wb', filename='', mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode='w') as archive:
            for name in sorted(set(names)):
                path = repository_source_path(folder, name)
                metadata = source_entry_metadata(path)
                if expected_metadata is not None and metadata != expected_metadata.get(name):
                    raise ValueError('Corresponding source metadata changed during archiving: '+name)
                if metadata['type'] == 'symlink':
                    verify_source_link(folder, path)
                    if expected_hashes is not None and digest(path) != expected_hashes[name]:
                        raise ValueError('Corresponding source changed during archiving: '+name)
                    target = metadata['target']
                    info = tarfile.TarInfo(name)
                    info.type, info.linkname, info.mode = tarfile.SYMTYPE, target, 0o777
                    archive.addfile(info)
                    hashes[name] = sha(encoded({'symlink': target}))
                    continue
                content = path.read_bytes()
                content_sha = sha(content)
                if expected_hashes is not None and content_sha != expected_hashes[name]:
                    raise ValueError('Corresponding source changed during archiving: '+name)
                info = tarfile.TarInfo(name)
                info.size = len(content)
                info.mode = 0o755 if metadata['executable'] else 0o644
                archive.addfile(info, io.BytesIO(content))
                hashes[name] = content_sha
    return data.getvalue(), hashes


def flutter_framework_archive(flutter, revision):
    """Archive and verify the selected framework files from the pinned Git tree."""
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('Expected a full Flutter framework revision for corresponding source')
    paths = ['packages/flutter', 'packages/flutter_localizations', 'packages/flutter_tools',
             'packages/flutter_web_plugins', 'bin/internal', 'bin/flutter', 'bin/dart',
             'DEPS', 'LICENSE', 'AUTHORS']
    env = controlled_environment()
    tree = run(['git', 'ls-tree', '-r', '-z', revision, '--', *paths], flutter, env=env)
    expected = {}
    for entry in filter(None, tree.split('\0')):
        header, name = entry.split('\t', 1)
        mode, kind, blob = header.split()
        if kind != 'blob' or mode not in ('100644', '100755', '120000'):
            raise ValueError('Unsupported Flutter framework source entry: '+name)
        expected[safe(name)] = mode, blob
    if not expected:
        raise ValueError('Pinned Flutter framework source tree is empty')
    # Read raw blobs, avoiding Git archive's EOL and export transformations.
    batch = subprocess.run(['git', 'cat-file', '--batch'], cwd=flutter, env=env, check=True,
                           input=''.join(blob+'\n' for _, blob in expected.values()).encode(),
                           stdout=subprocess.PIPE)
    blobs = io.BytesIO(batch.stdout)
    packed = io.BytesIO()
    hashes = {}
    with gzip.GzipFile(fileobj=packed, mode='wb', filename='', mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode='w') as archive:
            for name, (mode, blob) in expected.items():
                header = blobs.readline().split()
                if len(header) != 3 or header[:2] != [blob.encode(), b'blob']:
                    raise ValueError('Missing pinned Flutter framework blob: '+name)
                data = blobs.read(int(header[2]))
                if blobs.read(1) != b'\n' or hashlib.sha1(f'blob {len(data)}\0'.encode()+data).hexdigest() != blob:
                    raise ValueError('Flutter framework archive differs from pinned blob: '+name)
                member = tarfile.TarInfo(name)
                if mode == '120000':
                    member.type, member.linkname = tarfile.SYMTYPE, os.fsdecode(data)
                    archive.addfile(member)
                else:
                    member.mode, member.size = int(mode, 8) & 0o777, len(data)
                    archive.addfile(member, io.BytesIO(data))
                hashes[name] = sha(data)
    return packed.getvalue(), hashes


def project_license_errors(root, decision):
    license_path = root/'LICENSE'
    if decision.get('status') != 'approved' or not license_path.is_file():
        return ['Project license requires maintainer approval and root LICENSE']
    if decision.get('licenseSha256') != digest(license_path) or not decision.get('authorization'):
        return ['Project license decision is not bound to authorized LICENSE bytes']
    pins = json.loads(Path(__file__).with_name('release_materials_sources.json').read_text())
    canonical_gpl = digest(license_path) == pins['GPL-3.0.txt']['sha256']
    if canonical_gpl != (decision.get('licenseExpression') == 'GPL-3.0-only'):
        return ['Project GPL license expression differs from the canonical LICENSE text']
    if decision.get('licenseExpression') == 'GPL-3.0-only':
        notice = root/'COPYRIGHT'
        if (not notice.is_file() or digest(notice) != decision.get('copyrightNoticeSha256')
                or decision.get('copyrightNotice', '') not in notice.read_text()
                or 'SPDX-License-Identifier: GPL-3.0-only' not in notice.read_text()
                or decision.get('authorityOverAllFirstPartyContributions') is not True
                or decision.get('exceptions') != []):
            return ['GPL project attribution/authorization is missing or differs from the decision']
    policy = decision.get('contributionPolicy')
    if policy:
        if policy.get('agreement') != 'CLA.md' or policy.get('guide') != 'CONTRIBUTING.md':
            return ['Unsupported contribution policy document mapping']
        for name, field in (('CLA.md', 'agreementSha256'), ('CONTRIBUTING.md', 'guideSha256')):
            path = root/name
            if not path.is_file() or digest(path) != policy.get(field):
                return ['Missing/changed contribution policy document: '+name]
    return []


def tree(folder):
    """Read-only inventory; preserve framework symlinks without following directories."""
    result = {}
    for p in sorted(folder.rglob('*')):
        name = str(p.relative_to(folder))
        if p.is_symlink():
            if not p.resolve().is_relative_to(folder.resolve()):
                raise ValueError('External product symlink: ' + str(p))
            result[name] = {'symlink': str(p.readlink())}
        elif p.is_file():
            result[name] = {'sha256': digest(p), 'size': p.stat().st_size}
    if not result:
        raise ValueError('Empty or missing product: ' + str(folder))
    return result


def verify_product_path_steps(folder, parent, raw, description, active=frozenset()):
    path = PurePosixPath(raw)
    if path.is_absolute():
        raise ValueError('Absolute '+description)
    if not parent.is_relative_to(folder):
        raise ValueError('External '+description)
    for part in path.parts:
        if part == '..':
            if parent == folder:
                raise ValueError('External '+description)
            parent = parent.parent
            continue
        child = parent/part
        if child.is_symlink():
            if child in active:
                raise ValueError('Cyclic '+description)
            parent = verify_product_path_steps(folder, parent, os.readlink(child), description, active | {child})
        else:
            parent = child
    return parent


def validate_product_link(folder, link):
    target = os.readlink(link)
    verify_product_path_steps(folder, link.parent, target, 'product symlink: '+str(link), {link})
    # Let the filesystem check raw semantics, such as a required directory
    # for a slash-terminated target, after validating every containment step.
    try:
        link.stat()
    except OSError as error:
        raise ValueError('Invalid product symlink: '+str(link)) from error
    return target


def product_inventory(folder):
    """Record all product modes and bytes without opening special entries."""
    root_mode = folder.lstat().st_mode
    if not stat.S_ISDIR(root_mode):
        raise ValueError('Product root is not a real directory: '+str(folder))
    result = {'.': {'type': 'directory', 'mode': stat.S_IMODE(root_mode)}}

    def fail_scan(error):
        raise ValueError('Cannot scan product directory: '+str(error.filename)) from error

    for directory, dirs, files in folder.walk(on_error=fail_scan):
        dirs.sort()
        for name in sorted(dirs + files):
            path = directory/name
            metadata = path.lstat()
            mode = metadata.st_mode
            if stat.S_ISLNK(mode):
                entry = {'type': 'symlink', 'symlink': validate_product_link(folder, path)}
            elif stat.S_ISDIR(mode):
                entry = {'type': 'directory'}
            elif stat.S_ISREG(mode):
                entry = {'type': 'file', 'sha256': digest(path), 'size': metadata.st_size}
            else:
                raise ValueError('Unsupported product entry type: '+str(path))
            result[path.relative_to(folder).as_posix()] = {**entry, 'mode': stat.S_IMODE(mode)}
    if all(entry['type'] == 'directory' for entry in result.values()):
        raise ValueError('Empty product: '+str(folder))
    return result


def verified_shader_includes(flutter, revision, command=None):
    """Verify the cached Impeller include tree copied by build/archives/BUILD.gn."""
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('Expected a full Flutter framework revision for shader includes')
    cache = flutter/SHADER_INCLUDE_DIR
    if not (cache/'flutter/runtime_effect.glsl').is_file():
        raise ValueError('Selected SDK lacks required Release runtime effect shader header')
    inventory = product_inventory(cache)
    argv = ['git', 'ls-tree', '-r', '-z', revision, '--', SHADER_INCLUDE_SOURCE+'/']
    output = run(argv, flutter, env=controlled_environment()) if command is None else command(argv, flutter)
    prefix = SHADER_INCLUDE_SOURCE+'/'
    originals = {}
    for record in filter(None, output.split('\0')):
        header, name = record.split('\t', 1)
        mode, kind, blob = header.split()
        if kind != 'blob' or mode not in ('100644', '100755') or not name.startswith(prefix):
            raise ValueError('Unsupported pinned shader include source: '+name)
        originals[safe(name.removeprefix(prefix))] = blob
    cached_files = {name: entry for name, entry in inventory.items() if entry['type'] != 'directory'}
    if originals.keys() != cached_files.keys():
        raise ValueError('Cached Impeller shader include paths differ from pinned source: '+
                         ', '.join(sorted(originals.keys() ^ cached_files.keys())))
    for name, blob in originals.items():
        data = require_material_file(cache, name).read_bytes()
        actual = hashlib.sha1(f'blob {len(data)}\0'.encode()+data).hexdigest()
        if actual != blob or sha(data) != cached_files[name]['sha256']:
            raise ValueError('Cached Impeller shader include differs from pinned source: '+name)
    return {'path': str(cache), 'inventory': inventory}


def verify_native_hook_cache(receipt_path, receipt):
    expected = receipt.get('nativeHookCacheSha256')
    if expected is None and receipt.get('recipeVersion', 0) < FRESH_HOOK_RECIPE:
        return None
    if not isinstance(expected, str) or not re.fullmatch('[0-9a-f]{64}', expected):
        raise ValueError('Versioned build receipt lacks a valid native hook cache digest')
    cache = receipt_path.parent.parent/NATIVE_HOOK_SNAPSHOT
    if cache.resolve() != cache or sha(encoded(product_inventory(cache))) != expected:
        raise ValueError('Saved native hook cache differs from the build receipt')
    return cache


def sections(path):
    """Hash all file-backed Mach-O sections by architecture, excluding load commands.

    Used to establish bundling section correspondence, not signature acceptance.
    Zero-fill sections have no file contents. All other section bytes must match.
    """
    data = Path(path).read_bytes()
    def thin(base):
        if data[base:base+4] != b'\xcf\xfa\xed\xfe':
            raise ValueError('Expected 64-bit little-endian Mach-O: ' + str(path))
        cpu, _, _, ncmds = struct.unpack_from('<IIII', data, base+4)
        pos, found = base+32, {}
        for _ in range(ncmds):
            cmd, size = struct.unpack_from('<II', data, pos)
            if size < 8 or pos+size > len(data):
                raise ValueError('Malformed Mach-O load command')
            if cmd == 0x19:
                nsects = struct.unpack_from('<I', data, pos+64)[0]
                for i in range(nsects):
                    s = pos+72+i*80
                    sect, seg = [data[o:o+16].split(b'\0')[0].decode() for o in (s, s+16)]
                    length, offset = struct.unpack_from('<QI', data, s+40)
                    flags = struct.unpack_from('<I', data, s+64)[0] & 0xff
                    if length and flags not in (1, 0xc, 0x12):
                        found[seg+'/'+sect] = sha(data[base+offset:base+offset+length])
            pos += size
        if not found:
            raise ValueError('No Mach-O sections')
        return str(cpu), found
    if data[:4] == b'\xca\xfe\xba\xbe':
        count = struct.unpack_from('>I', data, 4)[0]
        return dict(thin(struct.unpack_from('>I', data, 8+i*20+8)[0]) for i in range(count))
    cpu, found = thin(0)
    return {cpu: found}


def serial_app_binding(report, app):
    """Bind the observed replacement copy to its unchanged original candidate."""
    runner = 'Contents/MacOS/Meshchan'
    if report.get('appOriginalSha256') != digest(app/runner):
        raise ValueError('Serial replacement original App binding changed')
    prepared = Path(report['appPreparedCopy'])
    original, replaced = tree(app), tree(prepared)

    def payload(items):
        return {p: v for p, v in items.items() if p != runner
                and not p.startswith(('Contents/_CodeSignature/',
                                      'Contents/Frameworks/libserialport_plus.framework/'))}

    if payload(original) != payload(replaced) or sections(app/runner) != sections(prepared/runner):
        raise ValueError('Serial replacement prepared App does not match original candidate payload')


def graph_scope(graph, lock, members, locations):
    packages, all_prod, _ = production_closure(graph, PRODUCTS)
    if set(members) != FIRST_PARTY:
        raise ValueError('Expected exactly four first-party workspace members')
    closures = {p: sorted(production_closure(graph, (p,))[1]) for p in PRODUCTS}
    for name, p in packages.items():
        if name in members:
            if p['version'] != members[name]['spec']['version'] or p['source'] not in ('root', 'workspace'):
                raise ValueError('Workspace identity mismatch: ' + name)
        elif name != graph['root']:
            entry = lock['packages'].get(name)
            if not entry or entry['version'] != p['version'] or entry['source'] != p['source']:
                raise ValueError('Lock version/source mismatch: ' + name)
        if name not in locations:
            raise ValueError('Missing package configuration: ' + name)
    # Annotate build edges without pruning named packages from the production graph.
    # These exact hook imports are also archived and checked against locked archives.
    build_edges = {'libserialport_plus': {'code_assets', 'hooks', 'native_toolchain_c'},
                   'sqlite3': {'code_assets', 'hooks', 'native_toolchain_c'}}
    runtime = set()
    def visit(name):
        if name in runtime:
            return
        runtime.add(name)
        for dep in packages[name].get('directDependencies', []):
            if dep not in build_edges.get(name, set()):
                visit(dep)
    for name in PRODUCTS:
        visit(name)
    components = []
    for name in sorted(all_prod - FIRST_PARTY):
        p = packages[name]
        owners = [root for root in PRODUCTS if name in closures[root]]
        components.append({'name': name, 'version': p['version'], 'source': p['source'],
                           'products': owners, 'ownership': 'shared' if len(owners) == 2 else owners[0],
                           'role': 'declared-production' if name in runtime else 'build-helper',
                           'licenseStatus': 'original declarations retained; see notices',
                           'reachability': 'Conservative graph coverage; no symbol-level AOT claim'})
    return {'roots': list(PRODUCTS), 'closures': closures, 'firstParty': sorted(FIRST_PARTY),
            'buildEdges': {k: sorted(v) for k, v in build_edges.items()},
            'devOnly': sorted(set(packages) - all_prod - FIRST_PARTY - {graph['root']}),
            'components': components}


def require_material_file(output, name):
    """Require a physically contained, non-aliased material file."""
    path = output/safe(name)
    for directory in reversed(path.parents):
        if directory.is_relative_to(output) and not stat.S_ISDIR(directory.lstat().st_mode):
            raise ValueError('Aliased or invalid material directory: '+str(directory))
    metadata = path.lstat()
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
        raise ValueError('Aliased or invalid material file: '+str(path))
    return path


def input_parser_argv(root, dart):
    config = require_material_file(root, PACKAGE_CONFIG)
    return [dart, '--packages='+str(config), root/'tool/release_materials_inputs.dart', root]


def flutter_package_notice_paths(root_uri, package_uri, scope):
    root_url = urlparse(root_uri)
    if root_url.scheme != 'file' or root_url.netloc:
        raise ValueError('Flutter notice source must be local: '+root_uri)
    configured_root = Path(unquote(root_url.path))
    package_root = configured_root.resolve()
    if not package_root.is_relative_to(scope):
        raise ValueError('Flutter notice package escapes its source root: '+str(configured_root))
    package_uri = urljoin(root_uri.rstrip('/')+'/', package_uri)
    for filename in ('NOTICES', 'LICENSE'):
        uri = urlparse(urljoin(package_uri, '../'+filename))
        if uri.scheme != 'file':
            raise ValueError('Flutter notice source must be local: '+uri.geturl())
        notice = Path(unquote(uri.path))
        if uri.netloc or not notice.is_relative_to(configured_root):
            raise ValueError('Flutter notice path escapes its source root: '+str(notice))
        relative = safe(notice.relative_to(configured_root).as_posix())
        yield (package_root/relative).relative_to(scope).as_posix()


def flutter_package_notice(root_uri, package_uri, scope):
    for path in flutter_package_notice_paths(root_uri, package_uri, scope):
        if os.path.lexists(scope/path):
            return require_material_file(scope, path)
    return None


def hosted_notice_identity(root_uri, package, folder):
    notice = flutter_package_notice(root_uri, package.get('packageUri', ''), folder)
    if notice is not None:
        return {'path': notice.relative_to(folder).as_posix(), 'sha256': digest(notice)}
    return None


def hosted_notice_case_sensitive(folder):
    """Probe the package volume using its manifest without writing to the cache."""
    manifest = require_material_file(folder, 'pubspec.yaml')
    try:
        alternate = manifest.with_name('PUBSPEC.YAML').lstat()
    except FileNotFoundError:
        return True
    return not os.path.samestat(manifest.lstat(), alternate)


def verify_hosted_notice(name, notice, notice_paths, originals, *, case_sensitive=True):
    key = str if case_sensitive else str.casefold
    selected = None
    for lookup in notice_paths:
        matches = sorted(path for path in originals if key(path) == key(lookup))
        if len(matches) > 1:
            raise ValueError(f'Ambiguous case aliases in locked notices for {name}: '+', '.join(matches))
        if selected is None and matches:
            selected = lookup, matches[0]
    expected = None
    if selected is not None:
        lookup, member = selected
        expected = {'path': lookup, 'sha256': sha(originals[member])}
    if expected != notice:
        raise ValueError(f'Selected hosted notice differs from its locked archive for {name}. '
                         f'Recorded {notice}, expected {expected}')
    return selected[1] if selected is not None else None


def native_source_hashes(external):
    """All files in the pinned native packages are potential hook inputs."""
    result = {}
    for name in sorted(NATIVE_SOURCE_PACKAGES):
        records = external.get(name, {}).get('files')
        if not isinstance(records, dict) or not records:
            raise ValueError('Missing prebuild native source inventory for '+name)
        files = {}
        for path, entry in records.items():
            safe(path)
            value = entry.get('sha256') if isinstance(entry, dict) else None
            if not isinstance(value, str) or not re.fullmatch('[0-9a-f]{64}', value):
                raise ValueError(f'Unbound native source input: {name}/{path}')
            files[path] = value
        result[name] = files
    return result


def verified_sdk_notices(root, flutter, config, identity, command=None):
    """Resolve Flutter's selected SDK notices and verify their pinned origins."""
    selected = {}
    tracked = {}
    for package in config['packages']:
        root_uri = urljoin((root/PACKAGE_CONFIG).as_uri(), package['rootUri'])
        folder = Path(unquote(urlparse(root_uri).path)).resolve()
        if not folder.is_relative_to(flutter):
            continue
        notice = flutter_package_notice(root_uri, package.get('packageUri', ''), flutter)
        if notice is not None:
            relative = notice.relative_to(flutter).as_posix()
            data = notice.read_bytes()
            value = sha(data)
            if relative == 'bin/cache/pkg/sky_engine/LICENSE':
                archive_name = 'sky_engine-'+identity['engineRevision']+'.zip'
                pin = json.loads((root/'tool/release_materials_sources.json').read_text()).get(archive_name, {})
                if pin.get('licenseMember') != 'sky_engine/LICENSE' or pin.get('licenseSha256') != value:
                    raise ValueError('SDK notice differs from pinned artifact member: '+relative)
            else:
                tracked[relative] = data
            selected[package['name']] = {'path': str(folder),
                                         'sdkNotice': {'path': str(notice), 'sha256': value}}
        if folder == flutter/'bin/cache/pkg/sky_engine' and package['name'] not in selected:
            raise ValueError('Missing SDK notice from the pinned sky_engine artifact')
    if tracked:
        revision = identity['frameworkRevision']
        if not re.fullmatch(r'[0-9a-f]{40}', revision):
            raise ValueError('Expected a full Flutter framework revision')
        argv = ['git', '--literal-pathspecs', 'ls-tree', '-r', '-z', revision, '--', *sorted(tracked)]
        output = run(argv, flutter, env=controlled_environment()) if command is None else command(argv, flutter)
        blobs = {name: header.split()[2] for header, name in
                 (entry.split('\t', 1) for entry in output.split('\0') if entry)}
        for name, data in tracked.items():
            blob = hashlib.sha1(f'blob {len(data)}\0'.encode()+data).hexdigest()
            if blobs.get(name) != blob:
                raise ValueError('SDK notice differs from pinned Flutter source: '+name)
    return selected


def unlisted_material_files(output, materials):
    """Enumerate file entries without following symlinks or opening payloads."""
    def fail_scan(error):
        raise error

    allowed = set(materials) | {'materials-manifest.json'}
    actual = {(directory/name).relative_to(output).as_posix()
              for directory, _, files in output.walk(on_error=fail_scan) for name in files}
    return sorted(actual - allowed)


def verify_materials(manifest, fresh, output):
    """Compare independently regenerated coverage and bytes, keeping open gates fatal."""
    failures = []
    if manifest.get('formatVersion') != 1 or not manifest.get('materials'):
        failures.append('Missing/unsupported material inventory')
    for name, item in manifest.get('materials', {}).items():
        try:
            matches = digest(require_material_file(output, name)) == item['sha256']
        except (OSError, ValueError):
            matches = False
        if not matches:
            failures.append('Missing/changed material: '+name)
    failures.extend('Unlisted material: '+name for name in unlisted_material_files(output, manifest.get('materials', {})))
    failures += ['Independent input/coverage drift: '+k for k in sorted(set(manifest)|set(fresh))
                 if manifest.get(k) != fresh.get(k)]
    failures += fresh['openGates']
    return failures


def compatible_hook(inp, out, package, location, architecture, minimum):
    """Product IDs are deliberately irrelevant for reusable compatible hook caches."""
    conf = inp.get('config', {})
    code = conf.get('extensions', {}).get('code_assets', {})
    return (conf.get('linking_enabled') is True and code.get('target_os') == 'macos'
            and code.get('target_architecture') == architecture
            and inp.get('package_name') == package
            and Path(inp.get('package_root', '')).resolve() == location.resolve()
            and out.get('status') == 'success' and inp.get('user_defines') == {}
            and (package != 'libserialport_plus' or code.get('macos', {}).get('target_version') == minimum))


def hook_dependencies_current(metadata, relocate=Path):
    if not metadata.is_file():
        return False
    deps = json.loads(metadata.read_text()).get('file_system', [])
    for dependency in deps:
        try:
            observed = relocate(dependency['path']).stat()
        except FileNotFoundError:
            return False
        if (not stat.S_ISREG(observed.st_mode) or observed.st_size != dependency['size']
                or abs(observed.st_mtime_ns//1000 - dependency['last_modified']) > 1):
            return False
    return bool(deps)


def font_names(path):
    """Read original SFNT name records for attribution, without editing the font."""
    data = path.read_bytes()
    result = {}
    for i in range(struct.unpack_from('>H', data, 4)[0]):
        tag, _, offset, _ = struct.unpack_from('>4sIII', data, 12+i*16)
        if tag != b'name':
            continue
        _, count, start = struct.unpack_from('>HHH', data, offset)
        for j in range(count):
            platform, _, _, name, size, pos = struct.unpack_from('>HHHHHH', data, offset+6+j*12)
            if name in (0, 1, 5, 7, 8, 9, 13, 14):
                value = data[offset+start+pos:offset+start+pos+size].decode(
                    'utf-16-be' if platform in (0, 3) else 'mac_roman')
                result.setdefault(str(name), set()).add(value)
    return {key: sorted(values) for key, values in sorted(result.items())}


def verified_material_icon_source(flutter, archive, tool_hashes):
    source = flutter/MATERIAL_ICONS_FONT
    license_path = source.parent/'MaterialIcons_LICENSE.txt'
    with zipfile.ZipFile(archive) as originals:
        for path in (source, license_path):
            data = originals.read(path.name)
            if data != require_regular_file(path).read_bytes():
                raise ValueError('Installed font material differs from original SDK archive: '+path.name)
            if path == source and tool_hashes is not None and tool_hashes.get(str(path)) != sha(data):
                raise ValueError('Original Material Icons font differs from the candidate build receipt')
    return source, license_path


class Collector:
    def __init__(self, args, output, offline=False):
        self.args, self.output, self.offline = args, output, offline
        self.files, self.blockers = {}, []
        self.hook_cache = None

    def put(self, name, data, source, original):
        name = safe(name)
        p = self.output / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
        self.files[name] = {'sha256': sha(data), 'size': len(data), 'source': source, 'originalPath': str(original)}
        return name

    def copy(self, path, name, source):
        return self.put(name, path.read_bytes(), source, path)

    def fetch(self, url, name, expected=None):
        pins = json.loads((self.args.repo/'tool/release_materials_sources.json').read_text())
        if expected is None:
            pin = pins.get(name)
            if not pin or pin['url'] != url:
                raise ValueError('Unreviewed external source; add fixed URL/hash: '+url)
            expected = pin['sha256']
        cache = self.args.downloads / safe(name)
        mismatch = 'Archive hash mismatch: ' + url
        if not cached_source_file(cache):
            if self.offline:
                raise ValueError('Missing verified download: ' + str(cache))
            publish_verified_download(cache, ['curl', '--fail', '--location', '--silent', '--show-error',
                                              '--retry', '2', url], expected, mismatch)
        elif expected and digest(cache) != expected:
            raise ValueError(mismatch)
        return cache

    def pub_archive(self, name, entry):
        expected_archive = entry['description']['sha256']
        if not isinstance(expected_archive, str) or not re.fullmatch('[0-9a-f]{64}', expected_archive):
            raise ValueError('Invalid locked Pub archive hash: '+name)
        url = entry['description']['url'].rstrip('/') + '/api/archives/' + name + '-' + entry['version'] + '.tar.gz'
        return url, self.fetch(url, name+'-'+entry['version']+'.tar.gz', expected_archive)

    def archive(self, name, entry, folder, *, compiler_files=None, native_files=None, notice=None, notice_paths=(),
                case_sensitive=True):
        url, archive = self.pub_archive(name, entry)
        originals, mismatches = {}, []
        with tarfile.open(archive, 'r:gz') as tar:
            for member in tar.getmembers():
                rel = member.name.removeprefix('./').rstrip('/')
                if not rel:
                    continue
                safe(rel)
                if member.isdir():
                    continue
                if not member.isfile() or rel in originals:
                    raise ValueError('Unsupported or duplicate pub archive member: ' + rel)
                data = tar.extractfile(member).read()
                originals[rel] = data
                if not (folder/rel).is_file() or digest(folder/rel) != sha(data):
                    mismatches.append(rel)
        for description, selected in (('Compiled hosted input', compiler_files), ('Native hook source input', native_files)):
            for relative, expected in (selected or {}).items():
                if relative not in originals:
                    raise ValueError(f'{description} is absent from its locked archive: {name}/{relative}')
                if sha(originals[relative]) != expected:
                    raise ValueError(f'{description} differs from its locked archive: {name}/{relative}')
        verify_hosted_notice(name, notice, notice_paths, originals, case_sensitive=case_sensitive)
        if mismatches:
            self.blockers.append('Modified/missing pub cache files in '+name+': '+', '.join(mismatches))
        notices = [p for p in sorted(originals) if is_notice_declaration(PurePosixPath(p).name)]
        if not any('/' not in p for p in notices):
            self.blockers.append('Missing package-root original license: '+name)
        for p in notices:
            self.put('licenses/'+name+'/'+p, originals[p], url, p)
        # Keep exact locked archives for native sources and reproducible hook prerequisites.
        # Helper archives are source/build evidence, not a runtime source obligation.
        if (getattr(self, 'project', {}).get('licenseExpression') == 'GPL-3.0-only'
                or name in ('libserialport_plus', 'sqlite3', 'hooks', 'code_assets', 'native_toolchain_c')):
            self.copy(archive, 'source-materials/archives/'+archive.name, url)
            for p, data in sorted(originals.items()):
                if (name == 'libserialport_plus' and (p.startswith(('src/', 'hook/')) or p == 'pubspec.yaml')
                        or name == 'sqlite3' and (p.startswith(('hook/', 'lib/src/hook/')) or p == 'pubspec.yaml')):
                    self.put('source-materials/'+name+'/'+p, data, url, p)
        return {'url': url, 'sha256': digest(archive), 'cacheMatchesArchive': not mismatches,
                'noticeFiles': ['licenses/'+name+'/'+p for p in notices]}

    def archive_notice(self, name, entry, notice, notice_paths, *, case_sensitive=True):
        """Retain only the selected notice for a package outside the product graph."""
        url, archive = self.pub_archive(name, entry)
        originals = {}
        key = str if case_sensitive else str.casefold
        requested = {key(path) for path in notice_paths}
        with tarfile.open(archive, 'r:gz') as tar:
            for member in tar:
                relative = member.name.removeprefix('./').rstrip('/')
                if key(relative) not in requested:
                    continue
                if not member.isfile() or relative in originals:
                    raise ValueError(f'Unsupported or duplicate Pub notice archive member: {name}/{relative}')
                originals[relative] = tar.extractfile(member).read()
        relative = verify_hosted_notice(name, notice, notice_paths, originals, case_sensitive=case_sensitive)
        if relative is not None:
            self.put('licenses/'+name+'/'+relative, originals[relative], url, relative)

    def collect(self):
        a, root, flutter = self.args, self.args.repo, self.args.flutter
        self.project = json.loads((root/'docs/releases/project-license-decision.json').read_text())
        dart = flutter / 'bin/cache/dart-sdk'
        dart_version = dart_sdk_metadata_file(flutter, 'version').read_text().strip()
        dart_revision = dart_sdk_metadata_file(flutter, 'revision').read_text().strip()
        identity = json.loads(flutter_cache_metadata_file(flutter, 'flutter.version.json').read_text())
        engine_stamp = flutter_cache_metadata_file(flutter, 'engine.stamp').read_text().strip()
        record, sums = a.build_inputs, a.candidate_hashes
        receipt_path = getattr(a, 'build_receipt', None)
        if receipt_path:
            try:
                receipt, companions = verify_build_receipt(root, receipt_path, record, sums, a.app, a.cli)
            except (OSError, ValueError, KeyError) as error:
                raise ValueError('Candidate build receipt verification: '+str(error)) from error
        config_path = require_material_file(root, PACKAGE_CONFIG)
        config_bytes = config_path.read_bytes()
        config_hash = sha(config_bytes)
        if receipt_path and receipt.get('recipeVersion', 0) >= ASSET_INPUT_RECIPE:
            verify_build_package_config(receipt, receipt_prebuild_identities(receipt_path, receipt), config_hash)
        config = json.loads(config_bytes)
        inputs = json.loads(run(input_parser_argv(root, dart/'bin/dart'), root))
        graph = json.loads(run([dart/'bin/dart', 'pub', 'deps', '--json'], root))
        locations = {p['name']: Path(unquote(urlparse(urljoin(config_path.as_uri(), p['rootUri'])).path)).resolve()
                     for p in config['packages']}
        locked_packages = inputs['lock'].get('packages', {})
        hosted_notices, hosted_notice_paths, notice_case = {}, {}, {}
        for p in config['packages']:
            name = p['name']
            if locked_packages.get(name, {}).get('source') == 'hosted':
                uri = urljoin(config_path.as_uri(), p['rootUri'])
                hosted_notices[name] = hosted_notice_identity(uri, p, locations[name])
                hosted_notice_paths[name] = tuple(flutter_package_notice_paths(uri, p.get('packageUri', ''), locations[name]))
                notice_case[name] = hosted_notice_case_sensitive(locations[name])
        app_version = inputs['members']['meshchan_app']['spec']['version']
        product, build = app_version.rsplit('+', 1)
        versions(root, product, app_build=int(build))
        if run(['git', 'rev-parse', 'HEAD'], flutter, env=controlled_environment()).strip() != identity['frameworkRevision']:
            raise ValueError('Flutter revision differs from cached identity')
        verified_sdk_notices(root, flutter, config, identity)
        sdk = {'flutter': identity, 'dartVersion': dart_version,
               'dartRevision': dart_revision,
               'runtimeSha256': digest(dart/'bin/dartaotruntime'),
               'engineStamp': engine_stamp}
        generated = [a.output, a.downloads, getattr(a, 'sdk_source_workspace', None)]
        source_hashes = repository_source_hashes(root, generated)
        products = {p: {'inventory': tree(path)} for p, path in zip(PRODUCTS, (a.app, a.cli))}
        for name, bundle in zip(PRODUCTS, (a.app, a.cli)):
            known_native = ({'Contents/MacOS/Meshchan',
                'Contents/Frameworks/App.framework/Versions/A/App',
                'Contents/Frameworks/FlutterMacOS.framework/Versions/A/FlutterMacOS',
                'Contents/Frameworks/libserialport_plus.framework/Versions/A/libserialport_plus',
                'Contents/Frameworks/sqlite3.framework/Versions/A/sqlite3'} if name == 'meshchan_app'
                else {'bin/meshctl', 'lib/liblibserialport_plus.dylib', 'lib/libsqlite3.dylib'})
            for path in products[name]['inventory']:
                if 'sha256' not in products[name]['inventory'][path]:
                    continue
                with (bundle/path).open('rb') as stream:
                    magic = stream.read(4)
                if magic in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe') and path not in known_native:
                    self.blockers.append('Unreviewed native product component: '+name+'/'+path)
        import plistlib
        plist = plistlib.loads((a.app/'Contents/Info.plist').read_bytes())
        expected = {'MeshchanProductVersion': product, 'CFBundleVersion': build,
                    'CFBundleShortVersionString': product.split('-')[0]}
        if any(plist.get(k) != v for k, v in expected.items()):
            raise ValueError('App candidate version mismatch')
        # Bind candidate inputs to independently recorded build-time hashes.
        required_inputs = compilation_inputs(root, inputs['members'], flutter=flutter)
        archive_inputs = required_inputs
        products['requiredCompilationInputs'] = required_inputs
        if record.exists():
            observed = json.loads(require_regular_file(record).read_text())
            input_errors = compilation_record_errors(root, required_inputs, observed)
            self.blockers.extend(input_errors)
            if not input_errors:
                archive_inputs = required_inputs | observed
            products['inputRecord'] = {'sha256': digest(record), 'value': observed}
            self.copy(record, 'evidence/compilation-input-hashes.json', 'Independent candidate build record')
        else:
            self.blockers.append('Candidate compilation input record unavailable; rebuild/bind in 1E.4')
        if sums.is_file():
            expected_files = {(a.app/p).resolve() for p in ('Contents/Info.plist', 'Contents/MacOS/Meshchan',
                              'Contents/Frameworks/App.framework/App')} | {(a.cli/'bin/meshctl').resolve()}
            checksum_bytes = require_regular_file(sums).read_bytes()
            if receipt_path and sha(checksum_bytes) != receipt['candidateChecksumsSha256']:
                raise ValueError('Candidate checksum record changed during material verification')
            recorded = {}
            for line in checksum_bytes.decode().splitlines():
                value, name = line.split('  ', 1)
                path = (root/name).resolve()
                if not re.fullmatch('[a-f0-9]{64}', value) or path in recorded:
                    raise ValueError('Malformed candidate checksum record')
                recorded[path] = value
            if not expected_files <= recorded.keys() or any(not p.is_file() or digest(p) != h for p, h in recorded.items()):
                error = 'Candidate files differ from independent build checksum record'
                if receipt_path:
                    raise ValueError(error)
                self.blockers.append(error)
            self.copy(sums, 'evidence/candidate-checksums.txt', 'Independent candidate build record')
        else:
            error = 'Independent candidate build checksums unavailable; bind in 1E.4'
            if receipt_path:
                raise ValueError(error)
            self.blockers.append(error)
        bound_commit = None
        source_metadata = None
        hosted_inputs, native_inputs = {}, {}
        tool_hashes = None
        if receipt_path:
            if receipt.get('nativeHookCacheSha256') is not None:
                self.hook_cache = receipt_path.parent.parent/NATIVE_HOOK_SNAPSHOT
            graph_name = 'resolved-graph.json'
            if graph_path := companions.get(graph_name):
                data = require_regular_file(graph_path).read_bytes()
                if sha(data) != receipt['resolvedGraphSha256'] or json.loads(data) != graph:
                    raise ValueError('Current dependency graph differs from the candidate build receipt')
                self.put('evidence/candidate-build/'+graph_name, data,
                         'Original build input snapshots and runner source', graph_path)
            products['buildReceipt'] = {'sha256': digest(receipt_path), 'value': receipt}
            self.copy(receipt_path, 'evidence/candidate-build/build-receipt.json',
                      'Contemporaneous candidate input/build/output ledger')
            for name, path in sorted(companions.items()):
                if name != graph_name:
                    self.copy(path, 'evidence/candidate-build/'+name, 'Original build input snapshots and runner source')
            # Raw local build logs stay private; their checked hashes and argv
            # are retained in the receipt instead of copying the environment.
            commit = run(['git', 'rev-parse', 'HEAD'], root, env=controlled_environment()).strip()
            source_metadata = verify_build_source(root, receipt_path, receipt, commit, source_hashes,
                                                  package_config_hash=config_hash)
            if source_metadata is not None:
                bound_commit = commit
            if compiler := companions.get('compiler-inputs.json'):
                if receipt.get('recipeVersion', 0) < COMPLETE_ASSET_RECIPE:
                    raise ValueError('Candidate build receipt predates complete Flutter asset evidence')
                from release_sdk_sources import SPEC
                prebuild = receipt_prebuild_identities(receipt_path, receipt)
                pins = json.loads(SPEC.read_text())
                if any(identity.get(key) != pins[key] for key in ('frameworkRevision', 'engineRevision')):
                    raise ValueError('Cached Flutter identity differs from the shader source pins')
                if prebuild['toolchain'].get('shaderIncludes') != verified_shader_includes(flutter, pins['frameworkRevision']):
                    raise ValueError('Verified Impeller shader includes differ from the candidate build receipt')
                tool_hashes = prebuild['toolchain']['toolHashes']
                external = prebuild['externalSources']
                native_inputs = native_source_hashes(external)
                if any(external.get(name, {}).get('noticeCaseSensitive') is not sensitive
                       for name, sensitive in notice_case.items()):
                    raise ValueError('Hosted notice filesystem casing differs from the candidate build receipt')
                report = json.loads(compiler.read_text())
                hosted_inputs = compiler_hosted_inputs(report)
                if hosted_notices != build_hosted_notices(report):
                    raise ValueError('Selected hosted notices differ from the candidate build receipt')
                phases = report['firstParty']
                if set(phases) != {'app', 'cli'} or any(not isinstance(files, dict) or not files
                                                        for files in phases.values()):
                    raise ValueError('Build receipt lacks first-party compiler inputs')
                for files in phases.values():
                    for name, value in files.items():
                        if source_hashes.get(name) != value:
                            raise ValueError('Compiler input differs from the verified source map: '+name)
                    archive_inputs |= files
        if run([a.cli/'bin/meshctl', '--version']).strip() != 'meshctl '+product:
            raise ValueError('CLI candidate version mismatch')
        scope = graph_scope(graph, inputs['lock'], inputs['members'], locations)
        hosted_components = {component['name'] for component in scope['components'] if component['source'] == 'hosted'}
        if uncovered := sorted((hosted_inputs.keys() | native_inputs.keys())-hosted_components):
            raise ValueError('Compiled hosted packages are outside the reviewed dependency scope: '+', '.join(uncovered))
        for component in scope['components']:
            name = component['name']
            folder = locations[name]
            if component['source'] == 'hosted':
                component['archive'] = self.archive(name, locked_packages[name], folder,
                                                    compiler_files=hosted_inputs.get(name), native_files=native_inputs.get(name),
                                                    notice=hosted_notices[name], notice_paths=hosted_notice_paths[name],
                                                    case_sensitive=notice_case[name])
            elif component['source'] == 'sdk':
                if not folder.is_relative_to(flutter):
                    raise ValueError('SDK package outside selected Flutter SDK: '+name)
                files = [p for p in folder.iterdir() if p.is_file() and NOTICE.match(p.name)]
                if not files and name == 'flutter_localizations':
                    # This framework package has no independent root LICENSE;
                    # the Flutter repository license covers its source tree.
                    files = [flutter/'LICENSE']
                    component['licenseBasis'] = 'Flutter repository LICENSE; packages/flutter_localizations has no separate root license'
                elif not files:
                    self.blockers.append('Missing SDK package license: '+name)
                component['noticeFiles'] = [self.copy(p, 'licenses/'+name+'/'+p.name,
                    'Flutter '+identity['frameworkRevision']) for p in sorted(files)]
            else:
                raise ValueError('Unreviewed dependency source: '+name)
            component['licenseExpression'] = {'libserialport_plus': 'MIT', 'sqlite3': 'MIT',
                'material_ui': 'BSD-3-Clause', 'flutter': 'BSD-3-Clause',
                'flutter_localizations': 'BSD-3-Clause'}.get(name)
            if name in ('libserialport_plus', 'sqlite3') and component['version'] != {'libserialport_plus': '1.0.5', 'sqlite3': '3.9.1'}[name]:
                raise ValueError('Native hook version requires review: '+name)
        # Flutter's automatic license collector processes the entire package
        # config, including packages outside the declared production closure.
        for name in sorted(hosted_notices.keys()-hosted_components):
            self.archive_notice(name, locked_packages[name], hosted_notices[name], hosted_notice_paths[name],
                                case_sensitive=notice_case[name])
        for path, target in ((flutter/'LICENSE', 'flutter/LICENSE'), (dart/'LICENSE', 'dart/LICENSE'),
                             (flutter/'bin/cache/LICENSE.dart_sdk_archive.md', 'dart/archive-origin.md'),
                             (flutter/'bin/cache/artifacts/engine/darwin-x64-release/LICENSE.artifacts.md', 'engine/artifact-origin.md')):
            self.copy(path, 'licenses/'+target, 'Installed SDK '+identity['engineRevision'])
        engine_root = flutter/'engine/src/flutter'
        for rel in ('build/archives/BUILD.gn', 'sky/packages/sky_engine/BUILD.gn'):
            self.copy(engine_root/rel, 'source-materials/flutter/'+rel, 'Flutter '+identity['frameworkRevision'])
        self.copy(flutter/'DEPS', 'source-materials/flutter/DEPS', 'Flutter '+identity['frameworkRevision'])
        sqlite_evidence = self.sqlite_materials()
        assets = a.app/'Contents/Frameworks/App.framework/Resources/flutter_assets'
        raw_notices = (assets/'NOTICES.Z').read_bytes()
        decoded = gzip.decompress(raw_notices)
        notice_coverage = []
        normalized_notices = decoded.decode().replace('\r\n', '\n')
        for component in scope['components']:
            if 'meshchan_app' not in component['products']:
                continue
            originals = component.get('archive', {}).get('noticeFiles', component.get('noticeFiles', []))
            for original in originals:
                text = (self.output/original).read_text().replace('\r\n', '\n').strip()
                notice_coverage.append({'component': component['name'], 'original': original,
                    'exactTextPresentInGeneratedNotices': text in normalized_notices,
                    'distributionSupplement': original,
                    'meaning': 'Generated registry can merge aggregate entries; independent originals are retained regardless of this textual comparison'})
        self.put('licenses/app/NOTICES.Z', raw_notices, 'Current complete App', str(assets/'NOTICES.Z'))
        self.put('licenses/app/NOTICES', decoded, 'Decoded current App NOTICES.Z', 'gzip decompression')
        for name in ('FontManifest.json', 'NativeAssetsManifest.json'):
            self.copy(assets/name, 'evidence/'+name, 'Current complete App')
        fonts = json.loads((assets/'FontManifest.json').read_text())
        font_stamp = require_regular_file(flutter/'bin/cache/material_fonts.stamp').read_text().strip()
        font_url = 'https://storage.googleapis.com/'+font_stamp
        font_archive = self.fetch(font_url, 'fonts-'+font_stamp.split('/')[-2]+'.zip')
        source, license_path = verified_material_icon_source(flutter, font_archive, tool_hashes)
        font_evidence = []
        for family in fonts:
            for font in family['fonts']:
                asset = font['asset']
                if family['family'] != 'MaterialIcons' or asset != 'fonts/MaterialIcons-Regular.otf':
                    self.blockers.append('Unreviewed font: '+asset)
                    continue
                self.copy(license_path, 'licenses/fonts/'+license_path.name, 'SDK material_fonts.stamp '+font_stamp)
                font_evidence.append({'asset': asset, 'bundledSha256': digest(assets/asset),
                    'sourceSha256': digest(source), 'transform': 'Flutter font subsetting; FontManifest identifies family',
                    'licenseExpression': 'CC-BY-4.0', 'originalNameRecords': font_names(source),
                    'sourceArchiveUrl': font_url, 'sourceArchiveSha256': digest(font_archive),
                    'licenseInAppNotices': license_path.read_text().strip() in decoded.decode()})
                font_evidence[-1]['supplement'] = 'licenses/fonts/'+license_path.name
        self.copy(root/'docs/releases/phase-1e3-licenses.md', 'rebuild/README.md', 'Repository distribution/rebuild contract')
        self.copy(root/'tool/rebuild_release_serial.py', 'rebuild/rebuild_release_serial.py', 'Repository isolated rebuild/probe tool')
        # GNU license texts are immutable originals, additionally bound by reviewed hashes.
        gpl = self.fetch('https://www.gnu.org/licenses/gpl-3.0.txt', 'GPL-3.0.txt')
        self.copy(gpl, 'licenses/libserialport-native/GPL-3.0.txt', 'https://www.gnu.org/licenses/gpl-3.0.txt')
        # Retrieve the exact artifact named by the SDK's own archive-license pointer.
        sky_url = 'https://storage.googleapis.com/flutter_infra_release/flutter/'+identity['engineRevision']+'/sky_engine.zip'
        sky = self.fetch(sky_url, 'sky_engine-'+identity['engineRevision']+'.zip')
        with zipfile.ZipFile(sky) as archive:
            candidates = [n for n in archive.namelist() if n in ('sky_engine/LICENSE', 'LICENSE')]
            if len(candidates) != 1 or archive.read(candidates[0]) != (locations['sky_engine']/'LICENSE').read_bytes():
                raise ValueError('Installed engine aggregate differs from exact official artifact')
        self.put('evidence/engine-notice-origin.json', encoded({'url': sky_url, 'archiveSha256': digest(sky),
                 'member': candidates[0], 'licenseSha256': digest(locations['sky_engine']/'LICENSE')}), sky_url, candidates[0])
        for name in ('COPYING', 'README'):
            self.copy(locations['libserialport_plus']/'src/libserialport'/name,
                      'licenses/libserialport-native/'+name, 'Locked libserialport_plus archive (cross-checked)')
        native = self.native_mapping(locations)
        # The official engine-wide aggregate includes Dart entries and engine dependencies.
        # CLI correspondence is separately tested against the SDK runtime sections below.
        engine_binary = a.app/'Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS'
        sdk_engine = flutter/'bin/cache/artifacts/engine/darwin-x64-release/FlutterMacOS.xcframework/macos-arm64_x86_64/FlutterMacOS.framework/FlutterMacOS'
        engine_match = sections(engine_binary) == sections(sdk_engine)
        if not engine_match:
            self.blockers.append('App engine does not match installed SDK engine sections')
        runtime_sections = sections(dart/'bin/dartaotruntime')
        cli_sections = sections(a.cli/'bin/meshctl')
        runtime_match = all(cli_sections.get(cpu) == values for cpu, values in runtime_sections.items())
        if not runtime_match:
            self.blockers.append('CLI AOT runtime section correspondence not verified')
        deps = (flutter/'DEPS').read_text()
        dart_revision_matches = "'dart_revision': '"+sdk['dartRevision']+"'" in deps
        if not dart_revision_matches:
            self.blockers.append('Dart SDK revision does not match Flutter DEPS runtime input')
        project_license = root/'LICENSE'
        decision = root/'docs/releases/project-license-decision.json'
        project = json.loads(decision.read_text())
        self.copy(decision, 'rebuild/project-license-decision.json', 'Repository maintainer decision record')
        project_errors = project_license_errors(root, project)
        self.blockers.extend(project_errors)
        if not project_errors:
            self.copy(project_license, 'licenses/meshchan/LICENSE', project['authorization'])
            if (root/'COPYRIGHT').is_file():
                self.copy(root/'COPYRIGHT', 'licenses/meshchan/COPYRIGHT', project['authorization'])
        gpl_source = (self.gpl_sources(source_hashes, sdk, archive_inputs, source_metadata=source_metadata)
                      if project.get('licenseExpression') == 'GPL-3.0-only' else None)
        probe = a.probe
        probe_result = None
        if probe and probe.is_file():
            probe_result = json.loads(probe.read_text())
            self.copy(probe, 'evidence/serial-rebuild.json', 'Isolated rebuild/modified-library probe')
            if probe_result.get('sourceArchiveSha256') != inputs['lock']['packages']['libserialport_plus']['description']['sha256']:
                self.blockers.append('Serial rebuild source does not match locked archive')
            workspace = Path(probe_result['workspace'])
            for name, key in (('rebuilt-original.dylib', 'originalRebuiltSha256'),
                              ('rebuilt-modified.dylib', 'modifiedSha256')):
                path = workspace/name
                if not path.is_file() or digest(path) != probe_result[key]:
                    self.blockers.append('Serial rebuild output unavailable/changed: '+name)
                else:
                    self.copy(path, 'evidence/serial/'+name, 'Isolated native source rebuild')
            if probe_result.get('cliOriginalSha256') != digest(a.cli/'bin/meshctl'):
                self.blockers.append('Serial replacement probe does not bind current CLI')
            try:
                serial_app_binding(probe_result, a.app)
            except (OSError, ValueError, KeyError) as error:
                self.blockers.append('Serial replacement probe does not bind current App: '+str(error))
            calls = [c for c in probe_result.get('commands', []) if c['argv'][1:] == ['ports', '--json']]
            if not any(c['exitCode'] == 0 and 'MESHCHAN_MODIFIED_SERIAL_EMPTY_LIST' in c['stderr']
                       and json.loads(c['stdout']).get('ports') == [] for c in calls):
                self.blockers.append('Missing CLI modified-library product call evidence')
            for name, info in sorted(probe_result.get('appEvidence', {}).items()):
                path = Path(info['path'])
                if not path.is_file() or digest(path) != info['sha256']:
                    self.blockers.append('Missing/changed App replacement evidence: '+name)
                else:
                    self.copy(path, 'evidence/serial/app-'+name, 'Identity-checked VM replacement observation')
            app_proof = probe_result.get('appEvidence', {})
            if probe_result.get('appModifiedLibraryLoaded') and not {'session.json', 'stdout.log', 'stderr.log'} <= set(app_proof):
                self.blockers.append('App replacement boolean lacks actual VM evidence')
        else:
            self.blockers.append('Serial corresponding-source rebuild and modified-library verification missing')
        if not probe_result or not probe_result.get('appModifiedLibraryLoaded'):
            self.blockers.append('App modified serial library runtime loading not observed (static mapping only)')
        for rel in ('licenses/sky_engine/LICENSE', 'licenses/libserialport-native/COPYING'):
            if rel not in self.files:
                self.blockers.append('Missing mandatory nested/SDK material: '+rel)
        notices = ('# Meshchan third-party distribution review\n\n'
                   'Native libserialport is used by both products under LGPL-3.0-or-later; '
                   'its Dart wrapper is MIT. See licenses/libserialport-native, source-materials/libserialport_plus, '
                   'and rebuild/README.md. Preserve library modification and reverse engineering for debugging '
                   'such modifications when distributing the combined work.\n\n'
                   'These are conservative declared production closures, including explicitly labeled build helpers. '
                   'They do not establish symbol-level AOT inclusion. Four workspace members are first party.\n\n'
                   '| Component | Version | Products | Role | Original declarations |\n| --- | --- | --- | --- | --- |\n')
        if not project_errors:
            notices = notices.replace('\n\nNative libserialport', '\n\n'+project.get('copyrightNotice', 'Meshchan')+
                '. First-party license: '+project.get('licenseExpression', 'see LICENSE')+
                '; see licenses/meshchan/LICENSE and licenses/meshchan/COPYRIGHT. '
                'Third-party licenses remain applicable.\n\nNative libserialport')
        for c in scope['components']:
            notices += f"| {c['name']} | {c['version']} | {', '.join(c['products'])} | {c['role']} | licenses/{c['name']}/ |\n"
        notices += ('\nApp engine/Dart aggregate: licenses/sky_engine/LICENSE. CLI uses the same official '
                    'SDK-wide aggregate, separately bound to AOT runtime sections and SDK revision.\n')
        notices += ('\nMaterial Icons font: Copyright 2019 Google LLC. All Rights Reserved. '
                    'Source: https://fonts.google.com/icons and the SDK material_fonts archive identified in the manifest. '
                    'Licensed under Creative Commons Attribution 4.0 International '
                    '(https://creativecommons.org/licenses/by/4.0/). '
                    'The bundled font is a subset generated by Flutter for Meshchan; this modifies the source font. '
                    'The complete original license is in licenses/fonts/MaterialIcons_LICENSE.txt.\n')
        notices += '\nOpen gates:\n'+''.join('- '+b+'\n' for b in sorted(set(self.blockers)))
        self.put('THIRD_PARTY_NOTICES.md', notices.encode(), 'Generated from locked graph and actual products', 'release_materials.py')
        source_commit = run(['git', 'rev-parse', 'HEAD'], root, env=controlled_environment()).strip()
        if bound_commit is not None and (source_commit != bound_commit
                or repository_source_hashes(root, generated) != source_hashes
                or repository_source_metadata(root, source_hashes) != source_metadata):
            raise ValueError('Checkout commit, source map or source metadata changed during material collection')
        if digest(require_material_file(root, PACKAGE_CONFIG)) != config_hash:
            raise ValueError('Workspace package configuration changed during material collection')
        return {'formatVersion': 1, 'sourceCommit': source_commit,
                'sourceInputHashes': source_hashes, 'productVersion': product, 'appBuild': build,
                'lockSha256': digest(root/'pubspec.lock'), 'graphSha256': sha(encoded(graph)),
                'packageConfigSha256': config_hash, 'sdk': sdk, 'scope': scope,
                'products': products, 'native': native, 'sqlite': sqlite_evidence,
                'fonts': font_evidence, 'appNoticesCoverage': notice_coverage, 'projectLicense': project,
                'gplCorrespondingSource': gpl_source,
                'runtime': {'appEngineSectionsMatch': engine_match, 'cliAotSectionsMatch': runtime_match,
                            'aggregate': 'licenses/sky_engine/LICENSE',
                            'dartRevisionMatchesFlutterDeps': dart_revision_matches,
                            'cliScope': 'Official SDK-wide aggregate, conservatively retained; exact runtime sections and DEPS binding'},
                'serialProbe': probe_result,
                'serialNative': {'licenseExpression': 'LGPL-3.0-or-later',
                    'upstreamTag': None, 'upstreamTagStatus': 'Not established; config.h 0.1.1 versus configure.ac 0.1.2',
                    'sourceIdentity': 'Exact locked pub archive and complete embedded source tree',
                    'lgplPath': '4(d)(1), shared replacement; local evidence only, repeat at 1E.6'},
                'materials': dict(sorted(self.files.items())),
                'openGates': sorted(set(self.blockers)),
                'rebinding': 'Recollect after lock, graph, SDK/engine/runtime, native, resource, product, or signing changes; final DMG is outside this review.'}

    def gpl_sources(self, source_hashes, sdk, required_inputs, *, source_metadata=None):
        root, flutter = self.args.repo, self.args.flutter
        names = [n for n in source_hashes if n in ('README.md', 'CLA.md', 'CONTRIBUTING.md', 'pubspec.yaml',
            'pubspec.lock', 'analysis_options.yaml') or n.startswith(('apps/', 'packages/', 'tool/', '.github/'))
            or ('/' not in n and is_notice_declaration(n))
            or n in RELEASE_ENTRY_SOURCE_FILES
            or n in ('docs/development.md', 'docs/releases/phase-1e3-licenses.md',
                     'docs/releases/project-license-decision.json', 'docs/releases/phase-1e3-sdk-sources.md')
            or n in required_inputs]
        archive, hashes = source_archive(root, names, expected_hashes=source_hashes, expected_metadata=source_metadata)
        if missing := required_inputs.keys()-hashes.keys():
            raise ValueError('Corresponding source archive lacks recorded compilation inputs: '+', '.join(sorted(missing)))
        with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as source:
            for name, expected in required_inputs.items():
                if hashes[name] == expected:
                    continue
                # The archive hash of a symlink identifies the link itself.
                # A compilation input's hash identifies the bytes it supplied.
                member = source.getmember(name)
                if member.issym():
                    try:
                        with source.extractfile(member) as payload:
                            if sha(payload.read()) == expected:
                                continue
                    except KeyError as error:
                        raise ValueError('Recorded compilation input link target is missing from the source archive: '+name) from error
                raise ValueError('Corresponding source archive differs from recorded compilation input: '+name)
        self.put('source-materials/meshchan/meshchan-source.tar.gz', archive,
                 'Actual repository input bytes, including authorized license', 'Repository source snapshot')
        framework, framework_hashes = flutter_framework_archive(flutter, sdk['flutter']['frameworkRevision'])
        self.put('source-materials/flutter/framework-build-source.tar.gz', framework,
                 'Flutter '+sdk['flutter']['frameworkRevision'], 'Selected framework and build-source files')
        from release_sdk_sources import SPEC, sdk_workspace_lock, verify
        workspace = getattr(self.args, 'sdk_source_workspace', None)
        missing, native = [], None
        try:
            if workspace is None:
                raise ValueError('GPL native SDK sources require --sdk-source-workspace; prepare with tool/release_sdk_sources.py')
            with sdk_workspace_lock(workspace):
                native = verify(workspace, flutter)
                spec = json.loads(SPEC.read_text())
                self.copy(SPEC, 'source-materials/sdk/source-inputs.json', 'Reviewed SDK source acquisition and identity rules')
                for item in [spec['engineArchive'], *spec['archives'], *spec['files']]:
                    self.copy(workspace/'downloads'/item['archive'], 'source-materials/sdk/archives/'+item['archive'], item['url'])
                for package in spec['toolPackages']:
                    for name, info in package['files'].items():
                        self.copy(workspace/'checkout'/info['path'], 'source-materials/sdk/'+info['path'],
                                  package['url']+' (original member '+name+')')
                for name in ('sdk-source-report.json', 'app-arm64-graph.json', 'app-x64-graph.json', 'cli-arm64-graph.json'):
                    self.copy(workspace/'evidence'/name, 'evidence/sdk/'+name, 'Fresh original GN graph and independently checked source inputs')
            for name in ('release_sdk_sources.py', 'release_sdk_sources.json'):
                self.copy(root/'tool'/name, 'rebuild/'+name, 'Repository reproducible SDK source rules')
            self.copy(root/'docs/releases/phase-1e3-sdk-sources.md', 'rebuild/sdk-sources.md', 'Native SDK source reconstruction and build instructions')
        except (OSError, ValueError, KeyError, tarfile.TarError, subprocess.CalledProcessError) as error:
            missing.append('GPL native SDK source verification: '+str(error))
        self.blockers.extend(missing)
        return {'status': 'REVIEW_REQUIRED' if missing else 'PASS', 'firstPartySnapshot': 'source-materials/meshchan/meshchan-source.tar.gz',
                'firstPartyInputHashes': hashes, 'frameworkInputHashes': framework_hashes,
                'nativeSdkSources': native,
                'hostedSourcePolicy': 'All declared production/helper pub archives retained at locked hashes',
                'missing': missing,
                'reason': 'Separate App engine slices and CLI runtime native source/build closures are checked from original archives, DEPS pins, Git trees and fresh GN graphs. Unmodified general-purpose compilers and operating-system libraries are separate from supplied runtime library sources.'}

    def sqlite_materials(self):
        revision = 'f144d1c56b22d5772d164c7c3f20eb1df482fcf3'
        url = 'https://codeload.github.com/simolus3/sqlite3.dart/tar.gz/'+revision
        archive = self.fetch(url, 'sqlite3.dart-'+revision+'.tar.gz')
        recipes = {}
        with tarfile.open(archive, 'r:gz') as tar:
            for rel in ('.github/workflows/compile_sqlite.yml', 'tool/download_sqlite.dart',
                        'tool/build_sqlite.dart', 'tool/generate_sbom.dart', 'LICENSE'):
                members = [m for m in tar.getmembers() if m.name.endswith('/'+rel)]
                # Match only the repository root, not nested LICENSE files.
                members = [m for m in members if m.name.count('/') == rel.count('/')+1]
                if len(members) != 1:
                    raise ValueError('Missing exact SQLite release recipe: '+rel)
                data = tar.extractfile(members[0]).read()
                recipes[rel] = self.put('source-materials/sqlite-native/'+rel, data, url, members[0].name)
        source_url = 'https://sqlite.org/2026/sqlite-amalgamation-3540100.zip'
        source = self.fetch(source_url, 'sqlite-amalgamation-3540100.zip')
        self.copy(source, 'source-materials/sqlite-native/'+source.name, source_url)
        with zipfile.ZipFile(source) as z:
            header = z.read('sqlite-amalgamation-3540100/sqlite3.h')
        self.put('licenses/sqlite-native/sqlite3.h', header, source_url, 'sqlite-amalgamation-3540100/sqlite3.h')
        # Version functions only; no database or extension loading.
        import ctypes
        binary = self.args.cli/'lib/libsqlite3.dylib'
        lib = ctypes.CDLL(str(binary))
        lib.sqlite3_libversion.restype = ctypes.c_char_p
        lib.sqlite3_sourceid.restype = ctypes.c_char_p
        lib.sqlite3_compileoption_get.restype = ctypes.c_char_p
        opts = []
        for i in range(1000):
            value = lib.sqlite3_compileoption_get(i)
            if value is None:
                break
            opts.append(value.decode())
        version, sourceid = lib.sqlite3_libversion().decode(), lib.sqlite3_sourceid().decode()
        if version != '3.54.1' or sourceid.encode() not in header:
            self.blockers.append('Native SQLite version/sourceid differs from fixed release amalgamation')
        return {'wrapper': 'sqlite3 3.9.1 (MIT)', 'variant': 'default SQLite; no SQLCipher or multiple-ciphers asset',
                'releaseRevision': revision, 'releaseArchiveSha256': digest(archive), 'recipes': recipes,
                'sourceUrl': source_url, 'sourceSha256': digest(source), 'nativeVersion': version,
                'sourceId': sourceid, 'compileOptions': opts,
                'sourceApplicability': 'Public-domain SQLite; source archive retained as provenance evidence, not a wrapper MIT source-distribution requirement'}

    def native_mapping(self, locations):
        live = self.args.repo/HOOK_CACHE
        cache = self.hook_cache or live

        def relocate(value):
            path = Path(value)
            if path.is_relative_to(live):
                return cache/safe(path.relative_to(live).as_posix())
            return path

        result = {}
        for product, bundle in zip(PRODUCTS, (self.args.app, self.args.cli)):
            result[product] = {}
            for package, stem in (('libserialport_plus', 'libserialport_plus'), ('sqlite3', 'sqlite3')):
                target = (bundle/f'Contents/Frameworks/{stem}.framework/{stem}' if product == 'meshchan_app'
                          else bundle/'lib'/('liblibserialport_plus.dylib' if package == 'libserialport_plus' else 'libsqlite3.dylib'))
                wanted = sections(target)
                matches = {cpu: [] for cpu in wanted}
                for output in sorted((cache/package).glob('*/output.json')):
                    input_file = output.parent/'input.json'
                    inp, out = json.loads(input_file.read_text()), json.loads(output.read_text())
                    conf = inp.get('config', {})
                    code = conf.get('extensions', {}).get('code_assets', {})
                    if (not conf.get('linking_enabled') or code.get('target_os') != 'macos'
                            or inp.get('package_name') != package
                            or Path(inp.get('package_root', '')).resolve() != locations[package]
                            or out.get('status') != 'success' or inp.get('user_defines') != {}):
                        continue
                    cpu = {'arm64': '16777228', 'x64': '16777223'}.get(code.get('target_architecture'))
                    if cpu not in matches:
                        continue
                    target_arch = 'arm64' if cpu == '16777228' else 'x86_64'
                    loads = run(['/usr/bin/otool', '-arch', target_arch, '-l', target])
                    minos = re.search(r'\bminos (\d+)\.', loads)
                    if not minos or not compatible_hook(inp, out, package, locations[package], code.get('target_architecture'), int(minos[1])):
                        continue
                    # Recorded dependency size and modification time must still agree.
                    deps_file = output.parent/'dependencies.dependencies_hash_file.json'
                    if not hook_dependencies_current(deps_file, relocate):
                        continue
                    for asset in out.get('assets', []):
                        enc = asset.get('encoding', {})
                        asset_path = Path(enc.get('file', ''))
                        if self.hook_cache is not None and not asset_path.is_relative_to(live):
                            continue
                        original = relocate(asset_path)
                        if (not original.is_file() or enc.get('link_mode', {}).get('type') != 'dynamic_loading_bundle'
                                or sections(original).get(cpu) != wanted[cpu]):
                            continue
                        if package == 'sqlite3':
                            hashes = (locations[package]/'lib/src/hook/asset_hashes.dart').read_text()
                            expected_name = 'libsqlite3.'+code['target_architecture']+'.macos.dylib'
                            if not re.search(re.escape(expected_name)+r"': '"+digest(original)+"'", hashes):
                                continue
                            origin = 'https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.9.1/'+expected_name
                        else:
                            origin = 'Locked libserialport_plus archive source, hook and current input configuration'
                        prefix = f'evidence/hooks/{package}/{output.parent.name}/'
                        self.copy(input_file, prefix+'input.json', 'Actual compatible hook input')
                        self.copy(output, prefix+'output.json', 'Actual compatible hook output')
                        self.copy(deps_file, prefix+'dependencies.json', 'Current dependency metadata for selected hook')
                        self.copy(original, prefix+original.name, origin)
                        matches[cpu].append({'input': prefix+'input.json', 'output': prefix+'output.json',
                            'rawAsset': prefix+original.name, 'rawSha256': digest(original),
                            'config': code, 'assetId': enc['id'], 'source': origin,
                            'rawLoader': run(['/usr/bin/otool', '-L', original]).splitlines()[1:]})
                for cpu, candidates in matches.items():
                    if not candidates:
                        self.blockers.append(f'No compatible current hook section mapping: {product}/{package}/{cpu}')
                    if len({c['rawSha256'] for c in candidates}) > 1:
                        self.blockers.append(f'Ambiguous raw native asset mapping: {product}/{package}/{cpu}')
                loader = run(['/usr/bin/otool', '-L', target]).splitlines()[1:]
                result[product][package] = {'bundledSha256': digest(target), 'sections': wanted,
                    'matches': matches, 'loader': loader,
                    'systemLibrariesNotBundled': sorted({v.strip().split(' (')[0] for v in loader
                        if v.strip().startswith(('/usr/lib/', '/System/Library/'))}),
                    'meaning': 'Matching file-backed sections per slice; bundlers change install names and signatures. Shared compatible hook caches are permitted.'}
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('collect', 'check'))
    parser.add_argument('--repo', type=Path, default=ROOT)
    parser.add_argument('--flutter', type=Path, required=True)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--cli', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--downloads', type=Path, required=True)
    parser.add_argument('--probe', type=Path)
    parser.add_argument('--build-inputs', type=Path)
    parser.add_argument('--build-receipt', type=Path)
    parser.add_argument('--candidate-hashes', type=Path)
    parser.add_argument('--sdk-source-workspace', type=Path)
    args = parser.parse_args()
    if args.output.is_symlink():
        parser.error('Material output must be a real directory')
    args.build_inputs = args.build_inputs or args.repo/'build/phase-1e2/compilation-input-hashes.json'
    args.candidate_hashes = args.candidate_hashes or args.repo/'build/phase-1e2/product-hashes.txt'
    for key in ('repo', 'flutter', 'app', 'cli', 'output', 'downloads', 'probe', 'build_inputs', 'candidate_hashes', 'sdk_source_workspace', 'build_receipt'):
        if getattr(args, key) is not None:
            setattr(args, key, getattr(args, key).resolve())
    try:
        caches = {'Download cache': args.downloads, 'SDK source workspace': args.sdk_source_workspace}
        protected = (args.app, args.cli)
        if args.build_receipt is not None:
            protected += (args.build_receipt.parent.parent/NATIVE_HOOK_SNAPSHOT,)
        require_product_disjoint({'Material output': args.output, **caches}, protected)
        require_product_disjoint(caches, (args.output,), protected='the materials output')
        if args.sdk_source_workspace is not None:
            from release_sdk_sources import validate_probe_write_paths
            validate_probe_write_paths(args.sdk_source_workspace)
        if args.output == args.repo:
            raise ValueError('Output must not overwrite repository')
        if args.command == 'collect':
            if args.output.exists():
                raise ValueError('Preserve existing review materials; choose a new output directory')
            args.output.mkdir(parents=True)
            try:
                # A new directory now has an inode. A cache whose spelling
                # differs only by case can resolve through that inode.
                require_product_disjoint(caches, (args.output,), protected='the materials output')
            except ValueError:
                args.output.rmdir()
                raise
            manifest = Collector(args, args.output).collect()
            manifest_bytes = encoded(manifest)
            (args.output/'materials-manifest.json').write_bytes(manifest_bytes)
            print(json.dumps({'status': 'REVIEW_REQUIRED' if manifest['openGates'] else 'PASS',
                              'manifestSha256': sha(manifest_bytes),
                              'materials': len(manifest['materials']), 'openGates': manifest['openGates']}, indent=2))
        else:
            manifest_path = require_material_file(args.output, 'materials-manifest.json')
            manifest_bytes = manifest_path.read_bytes()
            manifest = json.loads(manifest_bytes)
            # Recompute the expected coverage from independent graph, lock, SDK, hooks,
            # products and source files. Removing manifest entries cannot bypass checks.
            with tempfile.TemporaryDirectory(prefix='meshchan-material-check-') as temp:
                fresh = Collector(args, Path(temp), offline=True).collect()
            failures = verify_materials(manifest, fresh, args.output)
            manifest_changed = require_material_file(args.output, 'materials-manifest.json').read_bytes() != manifest_bytes
            if manifest_changed:
                failures.append('Material manifest changed during verification')
            integrity_failure = manifest_changed or any('material:' in f or 'drift:' in f for f in failures)
            print(json.dumps({'status': 'FAIL' if failures else 'PASS',
                              'manifestSha256': sha(manifest_bytes),
                              'integrityAndCoverage': 'FAIL' if integrity_failure else 'PASS',
                              'thirdPartyMaterials': 'FAIL' if any(f != 'Project license requires maintainer approval and root LICENSE' for f in failures) else 'PASS',
                              'failures': failures}, indent=2))
            return 1 if failures else 0
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, tarfile.TarError) as error:
        print('Materials error: '+str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
