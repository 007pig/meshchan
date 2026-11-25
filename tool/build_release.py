#!/usr/bin/env python3
"""Traceable local macOS arm64 Release builds and strict candidate materials.

Builds own new ignored directories below the checkout's build root and share the 1D.10 lock.
No GUI, hardware, version allocation, signing-policy change, or publication.
"""
import argparse
from contextlib import ExitStack, contextmanager, nullcontext
import ctypes
import datetime
import errno
import fcntl
import hashlib
import io
import json
import math
import os
from pathlib import Path
import platform
import posixpath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
from urllib.parse import unquote, urljoin, urlparse

from candidate_common import ROOT, versions
from product_identity import check_app, check_source_identity, config_values
from regression_1d10 import DeferredInterrupts, GateInterrupted, OwnedGate, process_table
from release_materials import (HOOK_CACHE, MATERIAL_ICONS_FONT, NATIVE_HOOK_SNAPSHOT, NATIVE_SOURCE_PACKAGES, PACKAGE_CONFIG,
                               RELEASE_ENTRY_SOURCE_FILES, SHADER_INCLUDE_DIR, VALIDATION_REPORTS,
                               Collector, compilation_inputs, contains_macho_local_path, controlled_environment, digest,
                               encoded, flutter_asset_files,
                               flutter_shader_includes, hosted_notice_identity,
                               hosted_notice_case_sensitive, input_parser_argv, native_source_hashes,
                               product_inventory as full_inventory, release_build_root, release_reference,
                               release_relative_path, release_run_path, release_tracked_pathspec,
                               repository_source_hashes, repository_source_metadata, require_material_file, require_product_disjoint,
                               require_regular_file, safe, sha, tree, unlisted_material_files,
                               verified_sdk_notices, verified_shader_includes,
                               verify_build_receipt, verify_native_hook_cache, verify_product_path_steps)
from release_sdk_sources import SPEC, dart_sdk_metadata_file, source_identity, validate_probe_write_paths

RECIPE_VERSION = 57
PRIVATE_PATH_AUDIT_RECIPE = 56
REPORT = 'docs/validation/phase-1e4-build.md'
MACOS_FLUTTER = 'apps/meshchan_app/macos/Flutter'
MACOS_EPHEMERAL = MACOS_FLUTTER+'/ephemeral'
MACOS_PLUGIN_REGISTRANT = MACOS_FLUTTER+'/GeneratedPluginRegistrant.swift'
APP_FLUTTER_CACHE = 'apps/meshchan_app/.dart_tool/flutter_build'
APP_KERNEL_DEPFILE = 'kernel_snapshot_program.d'
APP_ASSET_DEPFILE = 'flutter_assets.d'
GENERATED = ('Flutter-Generated.xcconfig', 'flutter_export_environment.sh')
PACKAGE_METADATA = (PACKAGE_CONFIG, '.dart_tool/package_graph.json')
PUB_WRITE_FILES = (*PACKAGE_METADATA, '.dart_tool/version')
SWIFT_MANIFESTS = ('FlutterGeneratedPluginSwiftPackage/Package.swift', '.packages/FlutterFramework/Package.swift')
RELEASE_PLATFORM_KERNEL = 'bin/cache/artifacts/engine/common/flutter_patched_sdk_product/platform_strong.dill'
CLI_PRODUCT_KERNEL = 'lib/_internal/vm_platform_product.dill'
FLUTTER_TOOL_SNAPSHOT = 'bin/cache/flutter_tools.snapshot'
FLUTTER_TOOL_STAMP = 'bin/cache/flutter_tools.stamp'
FLUTTER_VERSION_CACHE = 'bin/cache/flutter.version.json'
FLUTTER_TOOL_PUBSPEC = 'packages/flutter_tools/pubspec.yaml'
FLUTTER_TOOL_LOCK = 'packages/flutter_tools/pubspec.lock'
FLUTTER_TOOL_PACKAGE_CONFIG = 'packages/flutter_tools/.dart_tool/package_config.json'
FLUTTER_LAUNCHER_CACHE = (FLUTTER_TOOL_SNAPSHOT, FLUTTER_TOOL_STAMP, FLUTTER_TOOL_LOCK)
# The pinned launcher checks informative artifacts on every call. Pub and
# assemble also check universal artifacts, and macOS builds check desktop ones.
FLUTTER_ENGINE_ARTIFACTS = {
    'engine_stamp': (),
    'flutter_sdk': ('pkg/sky_engine', 'pkg/flutter_gpu', 'artifacts/engine/common', 'artifacts/engine/darwin-x64'),
    'font-subset': ('artifacts/engine/darwin-x64',),
    'macos-sdk': ('artifacts/engine/darwin-x64', 'artifacts/engine/darwin-x64-profile',
                  'artifacts/engine/darwin-x64-release'),
}
FLUTTER_UNIVERSAL_ARTIFACTS = {
    'material_fonts': (),
    'gradle_wrapper': ('gradlew', 'gradlew.bat', 'gradle/wrapper/gradle-wrapper.jar'),
    'libimobiledevice': ('idevicesyslog',),
    'libusbmuxd': ('iproxy',),
    'libplist': (),
    'openssl': (),
    'libimobiledeviceglue': (),
    'ios-deploy': (),
}
ICON_SUBSETTER = 'bin/cache/artifacts/engine/darwin-x64/font-subset'
SHADER_COMPILER = 'bin/cache/artifacts/engine/darwin-x64/impellerc'
RELEASE_FRAMEWORK = ('bin/cache/artifacts/engine/darwin-x64-release/FlutterMacOS.xcframework/'
                     'macos-arm64_x86_64/FlutterMacOS.framework')
MACH_O_THIN_32 = (b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xce')
MACH_O_64_OR_FAT = (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe',
                    b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca')
MH_DYLIB = 6
HELPERS = ('build_release.py', 'candidate_common.py', 'product_identity.py',
           'check_product_version.py', 'regression_1d10.py', 'release_materials.py',
           'release_materials_inputs.dart', 'release_sdk_sources.py', 'release_sdk_sources.json')
CLI_SQLITE_LIBRARY = 'lib/libsqlite3.dylib'
CLI_LIBRARIES = ('lib/liblibserialport_plus.dylib', CLI_SQLITE_LIBRARY)
CLI_RELEASE_ENTRY = 'lib/src/meshctl.dart'
CLI_SNAPSHOT_LAUNCHER = '''#!/bin/sh
set -eu
if [ "$#" -ne 3 ] || [ "$1" != '--snapshot-kind=app-aot-macho-dylib' ]; then
    echo 'Unexpected Dart CLI snapshot invocation' >&2
    exit 2
fi
case "$2" in
    --macho=/*/snapshot.aot) snapshot=${2#--macho=} ;;
    *) echo 'Unexpected Dart CLI snapshot output' >&2; exit 2 ;;
esac
compiler=${0%/*}/gen_snapshot-sdk
directory=${snapshot%/*}
kernel=$3
case "${directory##*/}" in
    ''|.|..) echo 'Unexpected Dart CLI snapshot directory' >&2; exit 2 ;;
esac
if [ "${directory%/*}" != "$TMPDIR" ] || [ -L "$directory" ] ||
   [ "$kernel" != "$directory/kernel.dill" ] || [ ! -f "$kernel" ] || [ -L "$kernel" ]; then
    echo 'Unexpected Dart CLI snapshot workspace' >&2
    exit 2
fi
cd "$directory"
exec "$compiler" "$1" --macho=snapshot.aot "$kernel"
'''
CLI_SDK_RUNPATH = '@loader_path/../../..'
APP_RUNNER = 'Contents/MacOS/Meshchan'
APP_AOT_BINARY = 'Contents/Frameworks/App.framework/App'
APP_AOT_EXPORTS = ('_kDartSnapshotData', '_kDartSnapshotText')
APP_ENGINE = 'Contents/Frameworks/FlutterMacOS.framework'
APP_ENGINE_BINARY = APP_ENGINE+'/Versions/A/FlutterMacOS'
APP_ENGINE_HOST_RUNPATH = '/usr/local/lib/.'
RELATIVE_LOADER_ANCHORS = ('@loader_path', '@executable_path')
APP_NATIVE_ASSETS = {
    'package:libserialport_plus/libserialport_plus_bindings.g.dart': 'libserialport_plus.framework/libserialport_plus',
    'package:sqlite3/src/ffi/libsqlite3.g.dart': 'sqlite3.framework/sqlite3',
}
WINDOWS_CHECKOUT_SUFFIXES = ('.bat', '.ps1', '.rc', '.sln', '.props', '.vcxproj',
                             '.vcxproj.filters', '.sln.tmpl', '.props.tmpl', '.vcxproj.tmpl')


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def write(path, value):
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.'+path.name+'-',
                                     delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(encoded(value))
            stream.close()
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)


def read(path):
    return json.loads(path.read_text())


def read_flutter_json(path, label):
    def invalid_constant(_):
        raise ValueError('Invalid JSON constant')

    # Flutter rejects nonstandard JSON constants that Python accepts by default.
    try:
        values = json.loads(path.read_text(encoding='utf-8'), parse_constant=invalid_constant)
    except (OSError, ValueError) as error:
        raise ValueError(f'Invalid Flutter {label}: {path}') from error
    if not isinstance(values, dict):
        raise ValueError(f'Invalid Flutter {label}: {path}')
    return values


def failure_message(error):
    message = repr(error)
    if isinstance(error, subprocess.CalledProcessError) and error.stderr:
        stderr = error.stderr
        if isinstance(stderr, bytes):
            stderr = stderr.decode(errors='replace')
        message += '\nCommand stderr:\n'+stderr.rstrip()
    for note in getattr(error, '__notes__', ()):
        message += '\n'+note
    return message


def raise_if_interrupted(interrupted):
    if interrupted:
        raise GateInterrupted(interrupted[0])


def capture(argv, cwd=ROOT, env=None):
    return subprocess.check_output([str(v) for v in argv], cwd=cwd, env=env, text=True).strip()


def output_path(root, value, new=False, *, timeout=3600):
    # The requested run is untrusted until Git verifies ownership. Keep the
    # supervisor's temporary logs outside it and preserve CLI stdout for JSON.
    with tempfile.TemporaryDirectory(prefix='meshchan-output-preflight-') as temporary:
        scratch = Path(temporary)
        runner = Runner(scratch, scratch, {'steps': []}, controlled_environment(), timeout, show_progress=False)
        git = ['git', '-c', 'core.fsmonitor=false']
        metadata = []
        redirected = (root/'build').is_symlink()
        if redirected:
            for label, option in (('output-git-dir', '--git-dir'), ('output-git-common-dir', '--git-common-dir')):
                path = runner.command(label, [*git, 'rev-parse', '--path-format=absolute', option],
                                      cwd=root, return_bytes=True)
                metadata.append(Path(os.fsdecode(path.removesuffix(b'\n'))))
        physical_build = release_build_root(root, metadata)
        path = release_run_path(root, physical_build, value, 'phase-1e4')
        base = physical_build/'phase-1e4'
        if any((parent/'build-info.json').exists() for parent in path.parents if parent.is_relative_to(base)):
            raise ValueError('Output overlaps an existing run')
        if new and path.exists():
            raise ValueError('Preserve existing output; choose a new run directory')
        # Git refuses pathspecs below a worktree symlink. In redirected mode
        # require the root link to be ignored and its entire tree untracked.
        relative = 'build' if redirected else release_relative_path(root, physical_build, path)
        tracked = runner.command('output-tracked-files',
                                 [*git, 'ls-files', '--cached', '-z', '--', release_tracked_pathspec(root, relative)],
                                 cwd=root)
        if tracked:
            raise ValueError('Output overlaps tracked source: '+tracked.split('\0', 1)[0])
        try:
            runner.command('output-git-ignore', [*git, 'check-ignore', '-q', '--', relative], cwd=root)
        except subprocess.CalledProcessError as error:
            if error.returncode == 1:
                raise ValueError('Output must be ignored by Git') from error
            raise
    return path


@contextmanager
def checkout_lock(root):
    folder = root/'.dart_tool'
    try:
        folder.mkdir(exist_ok=True)
        directory = os.open(folder, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except OSError as error:
        raise ValueError('Checkout requires a real .dart_tool directory: '+str(folder)) from error
    try:
        name = 'meshchan-1d10.lock'
        try:
            lock = os.open(name, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o666, dir_fd=directory)
        except OSError as error:
            raise ValueError('Cannot open a checkout-local build lock: '+str(folder/name)) from error
        try:
            metadata = os.fstat(lock)
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
                raise ValueError('Checkout build lock is not an owned regular file: '+str(folder/name))
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise ValueError('Checkout build lock is held; use a separate checkout or wait') from error
            yield
        finally:
            os.close(lock)
    finally:
        os.close(directory)


class Runner:
    def __init__(self, root, evidence, receipt, env, timeout=3600, interrupted=None, *,
                 show_progress=True, physical_build=None):
        self.root, self.evidence, self.receipt, self.env = root, evidence, receipt, env
        self.timeout = timeout
        self.interrupted = interrupted
        self.show_progress = show_progress
        self.physical_build = physical_build

    def save(self):
        write(self.evidence/'build-receipt.json', self.receipt)

    def command(self, name, argv, cwd=None, *, return_stderr=False, return_bytes=False):
        log = self.evidence/'logs'/(name+'.log')
        stderr_log = log.with_suffix('.stderr.log')
        log.parent.mkdir(exist_ok=True)
        step = {'name': name, 'argv': [str(v) for v in argv], 'cwd': str(cwd or self.root),
                'startedAt': now(), 'log': release_relative_path(self.root, self.physical_build, log),
                'stderrLog': release_relative_path(self.root, self.physical_build, stderr_log)}
        self.receipt['steps'].append(step)
        self.save()
        child = owned = None
        failure = None
        returned_log = stderr_log if return_stderr else log
        captured = {}

        def log_digest(path):
            if path in captured:
                return sha(captured[path])
            return digest(path) if path.exists() else None

        started = time.monotonic()
        if self.show_progress:
            print('START '+name, flush=True)
        interrupts = DeferredInterrupts() if self.interrupted is None else nullcontext(self.interrupted)
        with interrupts as interrupted:
            try:
                raise_if_interrupted(interrupted)
                process_table()  # Fail closed before creating children.
                with log.open('xb') as stream, stderr_log.open('xb') as diagnostics:
                    child = subprocess.Popen(step['argv'], cwd=step['cwd'], env=self.env,
                                             stdout=stream, stderr=diagnostics, start_new_session=True)
                    owned = OwnedGate(child)
                    while True:
                        live = owned.observe()
                        code = child.poll()
                        raise_if_interrupted(interrupted)
                        if code:
                            # The finally block stops owned helpers before the
                            # checkout lock is released and preserves this exit.
                            failure = subprocess.CalledProcessError(code, step['argv'])
                            raise failure
                        if time.monotonic()-started > self.timeout:
                            raise TimeoutError('Command deadline exceeded: '+name)
                        if code == 0 and not live:
                            break
                        time.sleep(0.05)
                step['exitCode'] = code
                step['processTree'] = owned.exit_receipt()
                captured[returned_log] = returned_log.read_bytes()
            finally:
                # Remain under both the checkout lock and deferred signals until
                # the isolated group and observed descendants have stopped.
                if child is not None and 'processTree' not in step:
                    step['processTree'] = (owned or OwnedGate(child)).stop()
                    step['exitCode'] = child.returncode
                if failure is not None:
                    failure.stderr = captured[stderr_log] = stderr_log.read_bytes()
                step.update(finishedAt=now(), elapsedSeconds=round(time.monotonic()-started, 3),
                            logSha256=log_digest(log), stderrLogSha256=log_digest(stderr_log))
                self.save()
            raise_if_interrupted(interrupted)
            if self.interrupted is None:
                while not interrupted.seal_if_unchanged(0):
                    raise_if_interrupted(interrupted)
        if self.show_progress:
            print('PASS '+name, flush=True)
        if return_bytes:
            return captured[returned_log]
        # Match Path.read_text's default encoding and universal newlines.
        with io.TextIOWrapper(io.BytesIO(captured[returned_log])) as result:
            return result.read()


def identity(root, expected_version=None, expected_build=None):
    values = config_values(root)
    version, build = values['MESHCHAN_PRODUCT_VERSION'], int(values['MESHCHAN_APP_BUILD'])
    if ((expected_version is not None and expected_version != version)
            or (expected_build is not None and expected_build != build)):
        raise ValueError('Explicit expectation differs from the source version/build decision')
    versions(root, version, app_build=build)
    return {'productVersion': version, 'appBuild': str(build),
            'appVersion': version+'+'+str(build), 'apple': check_source_identity(root, version, build),
            'target': 'macos-arm64'}


def require_no_sdk_bootstrap(flutter):
    bootstrap = flutter/'bin/internal/bootstrap.sh'
    if os.path.lexists(bootstrap):
        raise ValueError('Unexpected unpinned Flutter SDK bootstrap: '+str(bootstrap))


def require_ready_flutter_artifacts(flutter, cache, engine_revision):
    """Reject the conditions that make pinned Flutter refresh stamped artifacts."""
    stamps = []

    def require_stamp(name, expected):
        stamp = cache/(name+'.stamp')
        validate_mutable_file(stamp, 'Flutter SDK artifact stamp '+name)
        if not expected or not stamp.is_file() or stamp.read_text().strip() != expected:
            raise ValueError(f'Flutter artifact stamp {name} is missing or stale; release commands require a prepared SDK')
        stamps.append(stamp)

    def require_directory(relative):
        folder = existing_checkout_directory(flutter, cache.relative_to(flutter)/relative, 'Flutter SDK artifact')
        if folder is None:
            raise ValueError('Flutter artifact cache directory is missing: '+str(cache/relative))
        return folder

    for name, directories in FLUTTER_ENGINE_ARTIFACTS.items():
        require_stamp(name, engine_revision)
        for directory in directories:
            require_directory(directory)
    for name, files in FLUTTER_UNIVERSAL_ARTIFACTS.items():
        version = (flutter/'bin/internal'/(name+'.version')).read_text().strip()
        require_stamp(name, version)
        directory = require_directory('artifacts/'+name)
        for relative in files:
            if not (directory/relative).is_file():
                raise ValueError('Flutter artifact cache file is missing: '+str(directory/relative))
    return stamps


def require_flutter_tool_dependencies(flutter):
    """Check Flutter's universal PubDependencies artifact without running Pub."""
    config = flutter/FLUTTER_TOOL_PACKAGE_CONFIG
    if existing_checkout_directory(flutter, config.parent.relative_to(flutter), 'Flutter tool package config') is None:
        raise ValueError('Flutter tool package config is missing: '+str(config))
    validate_mutable_file(config, 'Flutter tool package config')
    if not config.is_file():
        raise ValueError('Flutter tool package config is missing: '+str(config))
    data = read_flutter_json(config, 'tool package config')
    if (type(data.get('configVersion')) is not int
            or data['configVersion'] != 2 or not isinstance(data.get('packages'), list) or not data['packages']):
        raise ValueError('Invalid Flutter tool package config: '+str(config))
    manifests = {}
    for package in data['packages']:
        if not isinstance(package, dict):
            raise ValueError('Invalid package entry in Flutter tool package config: '+str(config))
        name, uri = package.get('name'), package.get('rootUri')
        if (not isinstance(name, str) or not name or name in manifests
                or not isinstance(uri, str) or not uri):
            raise ValueError('Invalid package name or root in Flutter tool package config: '+str(config))
        root = urlparse(urljoin(config.as_uri(), uri))
        if root.scheme != 'file' or root.netloc or root.query or root.fragment or not root.path.startswith('/'):
            raise ValueError('Flutter tool package requires a local root URI: '+name)
        folder = Path(unquote(root.path))
        manifest = folder/'pubspec.yaml'
        if not manifest.is_file():
            raise ValueError(f'Missing Flutter tool dependency manifest for {name}: {manifest}')
        manifests[name] = manifest
    if manifests.get('flutter_tools') != flutter/FLUTTER_TOOL_PUBSPEC:
        raise ValueError('Flutter tool package config does not resolve the selected flutter_tools package')
    return [config, *manifests.values()]


def validate_flutter_version_cache(path):
    version = read_flutter_json(path, 'version cache')
    # Match the pinned _FlutterVersionFromFile parser. Flutter can delete an
    # invalid record or regenerate one that is not from a standard remote.
    required = ('frameworkVersion', 'channel', 'repositoryUrl', 'frameworkRevision', 'frameworkCommitDate',
                'engineRevision', 'dartSdkVersion', 'devToolsVersion', 'flutterVersion')
    optional = ('engineCommitDate', 'engineContentHash', 'engineBuildDate')
    for field in required:
        if not isinstance(version.get(field), str):
            raise ValueError(f'Invalid Flutter version cache field {field}: {path}')
    for field in optional:
        if version.get(field) is not None and not isinstance(version[field], str):
            raise ValueError(f'Invalid Flutter version cache field {field}: {path}')
    # The controlled environment does not provide a custom FLUTTER_GIT_URL.
    # The version command refreshes tags and metadata on these channels.
    if (version['channel'] in ('main', 'master')
            or version['frameworkVersion'] == '0.0.0-unknown'
            or version['repositoryUrl'].removesuffix('.git') not in (
                'https://github.com/flutter/flutter', 'git@github.com:flutter/flutter',
                'ssh://git@github.com/flutter/flutter')):
        raise ValueError('Flutter version cache would require regeneration: '+str(path))


def require_ready_flutter_launcher(flutter, pins=None):
    require_no_sdk_bootstrap(flutter)
    validate_mutable_file(flutter/'version', 'Flutter SDK legacy version file')
    pins = read(SPEC) if pins is None else pins
    cache = existing_checkout_directory(flutter, 'bin/cache', 'Flutter SDK cache')
    version = flutter/FLUTTER_VERSION_CACHE
    if cache is not None:
        # The launcher updates these paths even when its tool snapshot is fresh.
        validate_mutable_file(cache/'engine.stamp', 'Flutter SDK engine stamp')
        validate_mutable_file(cache/'engine.realm', 'Flutter SDK realm stamp')
        validate_mutable_file(cache/'lockfile', 'Flutter SDK cache lock')
        validate_mutable_file(version, 'Flutter SDK version cache')
    snapshot, stamp, lock = (flutter/name for name in FLUTTER_LAUNCHER_CACHE)
    pubspec = flutter/FLUTTER_TOOL_PUBSPEC
    # Mirror the pinned shared.sh rebuild conditions. The controlled child
    # environment leaves FLUTTER_TOOL_ARGS unset, so the key ends in a colon.
    if (cache is None or not all(path.is_file() for path in (snapshot, stamp, pubspec, lock, version))
            or stamp.read_bytes().rstrip(b'\n') != (pins['frameworkRevision']+':').encode()
            or pubspec.stat().st_mtime_ns > lock.stat().st_mtime_ns):
        raise ValueError('Flutter tool cache is missing or stale; release commands require a prepared SDK')
    validate_flutter_version_cache(version)
    return [snapshot, stamp, lock, version, *require_ready_flutter_artifacts(flutter, cache, pins['engineRevision']),
            *require_flutter_tool_dependencies(flutter)]


def require_sdk_checkout(flutter, pins, probe):
    require_no_sdk_bootstrap(flutter)
    pinned = pins['frameworkRevision']
    if probe('sdk-head', ['git', 'rev-parse', 'HEAD'], flutter) != pinned:
        raise ValueError('SDK HEAD differs from the pinned framework revision')
    if probe('sdk-status', ['git', 'status', '--porcelain', '--untracked-files=no'], flutter):
        raise ValueError('SDK has tracked modifications')
    tree = probe('sdk-tracked-tree', ['git', 'ls-tree', '-r', '-z', '--full-tree', pinned], flutter)
    windows_crlf = verify_git_tree(flutter, pinned, tree, 'SDK tracked source')
    if windows_crlf:
        attributes = probe('sdk-windows-eol', ['git', '-c', 'core.attributesFile=/dev/null', 'check-attr',
                                               '--source='+pinned, '-z', 'eol', '--', *windows_crlf], flutter)
        expected = '\0'.join(part for name in windows_crlf for part in (name, 'eol', 'crlf'))+'\0'
        require_equal(expected, attributes, 'SDK Windows checkout line endings')


def release_framework_identity(flutter):
    framework = flutter/RELEASE_FRAMEWORK
    xcframework = framework.parent.parent
    if existing_checkout_directory(flutter, xcframework.relative_to(flutter), 'Release FlutterMacOS XCFramework') is None:
        raise ValueError('Selected SDK lacks the Release FlutterMacOS XCFramework')
    # This Flutter version takes the first directory with a macos- prefix.
    # Accept only the pinned layout so filesystem iteration cannot change it.
    platforms = [path for path in xcframework.iterdir() if path.name.startswith('macos-') and path.is_dir()]
    if platforms != [framework.parent]:
        raise ValueError('Unexpected or ambiguous Release FlutterMacOS platform directories: '+
                         ', '.join(sorted(path.name for path in platforms)))
    if not framework.is_dir() or framework.resolve() != framework:
        raise ValueError('Missing or aliased Release FlutterMacOS framework: '+str(framework))
    for name in ('FlutterMacOS', 'Headers/FlutterMacOS.h', 'Modules/module.modulemap'):
        if not (framework/name).is_file():
            raise ValueError('Selected SDK lacks required Release FlutterMacOS framework input: '+name)
    return {'path': str(framework), 'inventory': full_inventory(framework)}


def toolchain(flutter, command, probe_name='flutter-version', *, root=ROOT, env=None):
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise ValueError('This recipe requires a native macOS arm64 host')
    if sys.version_info < (3, 15) or sys.version_info.releaselevel != 'final':
        raise ValueError('This host recipe requires stable Python 3.15 or newer')
    dart = flutter/'bin/cache/dart-sdk'
    pins = read(SPEC)

    def probe(label, argv, cwd=None):
        return command(f'{probe_name}-{label}', argv, cwd).strip()

    def verify_sdk(phase):
        def sdk_probe(label, argv, cwd):
            return probe(phase+'-'+label, argv, cwd)

        require_sdk_checkout(flutter, pins, sdk_probe)
        cache = require_ready_flutter_launcher(flutter, pins)
        source_identity(pins, flutter, lambda revision: sdk_probe(
            'sdk-tree-'+revision, ['git', 'rev-parse', revision+':engine/src'], flutter))
        metadata = [dart_sdk_metadata_file(flutter, name) for name in ('version', 'revision')]
        return [*cache, *metadata]

    cache = verify_sdk('before')
    cached_hashes = {str(path): digest(path) for path in cache}
    read_flutter_settings(root, controlled_environment() if env is None else env)
    observed = json.loads(command(probe_name, [flutter/'bin/flutter', '--version', '--machine']))
    for field in ('frameworkRevision', 'engineRevision', 'engineContentHash'):
        if observed.get(field) != pins[field]:
            raise ValueError('Observed Flutter identity differs from the pin: '+field)
    if observed.get('dartSdkVersion') != dart_sdk_metadata_file(flutter, 'version').read_text().strip():
        raise ValueError('Observed Flutter Dart version differs from the bundled SDK')
    current_cache = verify_sdk('after')
    require_equal(cached_hashes, {str(path): digest(path) for path in current_cache}, 'Flutter launcher version probe')
    paths = [flutter/'bin/flutter', dart/'bin/dart', dart/'bin/dartvm', dart/'bin/dartaotruntime',
             dart/'bin/utils/gen_snapshot', dart/'bin/snapshots/gen_kernel_aot.dart.snapshot',
             dart/CLI_PRODUCT_KERNEL,
             dart/'bin/snapshots/dartdev_aot.dart.snapshot', dart/'bin/snapshots/frontend_server_aot.dart.snapshot',
             flutter/RELEASE_PLATFORM_KERNEL, flutter/ICON_SUBSETTER, flutter/MATERIAL_ICONS_FONT,
             flutter/SHADER_COMPILER,
             flutter/'bin/cache/artifacts/engine/darwin-x64-release/gen_snapshot_arm64',
             flutter/'bin/cache/artifacts/engine/darwin-x64-release/gen_snapshot_x64']
    if any(not p.is_file() for p in paths):
        raise ValueError('Selected SDK lacks required Release engine/snapshot tools')
    framework = release_framework_identity(flutter)
    shader_includes = verified_shader_includes(flutter, pins['frameworkRevision'],
                                               lambda argv, cwd: probe('shader-source-tree', argv, cwd))
    compiler = probe('clang-path', ['/usr/bin/xcrun', '--find', 'clang'])
    xcode = probe('xcode', ['/usr/bin/xcodebuild', '-version'])
    paths.extend((Path(probe('install-name-tool', ['/usr/bin/xcrun', '--find', 'install_name_tool'])),
                  Path('/usr/bin/codesign')))
    return {'python': {'path': sys.executable, 'version': sys.version, 'sha256': digest(Path(sys.executable))},
            'flutterPath': str(flutter), 'flutter': observed,
            'dart': {'path': str(dart/'bin/dart'), 'version': probe('dart', [dart/'bin/dart', '--version']),
                     'revision': dart_sdk_metadata_file(flutter, 'revision').read_text().strip()},
            'xcode': xcode,
            'clang': {'path': compiler, 'version': probe('clang', [compiler, '--version']), 'sha256': digest(Path(compiler))},
            'macosSdk': {'path': probe('sdk-path', ['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path']),
                         'version': probe('sdk-version', ['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-version'])},
            'host': {'os': platform.system(), 'version': probe('host', ['/usr/bin/sw_vers']), 'architecture': platform.machine()},
            'toolHashes': cached_hashes | {str(p): digest(p) for p in paths},
            'releaseFramework': framework,
            'shaderIncludes': shader_includes,
            'sourcePinsSha256': digest(SPEC)}


def inputs(root, dart, command, name, *, flutter=None):
    parsed = json.loads(command(name, input_parser_argv(root, dart)))
    return compilation_inputs(root, parsed['members'], flutter=flutter)


def validate_flutter_outputs(root):
    """Check Flutter's mutable configuration and App build cache paths."""
    validate_flutter_tree(root, MACOS_EPHEMERAL, 'configuration')
    validate_mutable_file(root/MACOS_PLUGIN_REGISTRANT, 'Flutter plugin registrant')
    validate_flutter_tree(root, APP_FLUTTER_CACHE, 'App build cache')


def existing_checkout_directory(root, relative, label):
    folder = root
    for name in Path(relative).parts:
        folder /= name
        try:
            metadata = folder.lstat()
        except FileNotFoundError:
            return None  # The caller can create a missing branch under real parents.
        if not stat.S_ISDIR(metadata.st_mode):
            raise ValueError(f'Aliased or invalid {label} directory: {folder}')
    return folder


def validate_flutter_tree(root, relative, purpose):
    folder = existing_checkout_directory(root, relative, 'Flutter '+purpose)
    if folder is None:
        return

    def scan_error(error):
        raise error

    for directory, dirs, files in folder.walk(on_error=scan_error):
        for name in dirs + files:
            entry = directory/name
            metadata = entry.lstat()
            if not (stat.S_ISDIR(metadata.st_mode) or
                    (stat.S_ISREG(metadata.st_mode) and metadata.st_nlink == 1)):
                raise ValueError(f'Aliased or invalid Flutter {purpose} output: {entry}')


@contextmanager
def fresh_native_hook_cache(root, out):
    """Give both compilers a fresh cache and preserve the developer's cache."""
    validate_flutter_tree(root, HOOK_CACHE, 'native hook cache')
    cache = root/HOOK_CACHE
    snapshot = out/NATIVE_HOOK_SNAPSHOT
    staging = Path(tempfile.mkdtemp(prefix='.meshchan-native-hooks-', dir=cache.parent))
    previous = staging/'previous'
    fresh = staging/'fresh'
    had_cache = cache.exists()

    def finish_cache():
        try:
            try:
                if os.path.lexists(cache):
                    cache.rename(fresh)
            finally:
                if had_cache:
                    previous.rename(cache)
            validate_flutter_tree(staging, 'fresh', 'native hook cache snapshot')
            if fresh.exists():
                try:
                    fresh.rename(snapshot)
                except OSError as error:
                    if error.errno != errno.EXDEV:
                        raise
                    # Native provenance compares dependency size and mtime.
                    shutil.copytree(fresh, snapshot, copy_function=shutil.copy2)
        finally:
            # Leave the original developer cache recoverable if restoration failed.
            if not os.path.lexists(previous):
                shutil.rmtree(staging)

    if had_cache:
        try:
            cache.rename(previous)
        except OSError:
            staging.rmdir()
            raise
    try:
        cache.mkdir()
        yield snapshot
    except BaseException as error:
        try:
            finish_cache()
        except Exception as cleanup_error:
            error.add_note('Native hook cache cleanup failed: '+str(cleanup_error))
        raise
    else:
        finish_cache()


def read_flutter_settings(cwd, env):
    home = cwd/env.get('HOME', '.')
    # Pinned Flutter prefers the legacy file when it exists. The controlled
    # environment omits XDG_CONFIG_HOME.
    settings = home/'.flutter_settings'
    if not settings.is_file():
        settings = home/'.config/flutter/settings'
    try:
        mode = settings.stat().st_mode
    except FileNotFoundError:
        return {}
    if not stat.S_ISREG(mode):
        raise ValueError('Flutter settings path is not a regular file: '+str(settings))
    # Flutter can delete a malformed file while loading preferences.
    return read_flutter_json(settings, 'settings file')


def validate_swift_package_cache(root, env):
    app = root/'apps/meshchan_app'
    values = read_flutter_settings(app, env)
    build_dir = values.get('build-dir')
    if build_dir is None:
        build_dir = 'build'
    if not isinstance(build_dir, str) or not build_dir or '\x00' in build_dir:
        raise ValueError('Invalid Flutter build-dir setting')
    relative = Path(build_dir)
    if relative.is_absolute() or '..' in relative.parts:
        raise ValueError('Flutter build-dir must stay within the App checkout: '+build_dir)
    validate_flutter_tree(root, app.relative_to(root)/relative/'macos/SourcePackages', 'SwiftPM cache')


def validate_mutable_file(path, label):
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        return
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
        raise ValueError(f'Aliased or invalid {label}: {path}')


def validate_package_metadata(root):
    for name in PUB_WRITE_FILES:
        validate_mutable_file(root/name, 'Pub package metadata')


def validate_workspace_pub_metadata(root, dart, command):
    # Pub can list the workspace before package resolution and supplies the
    # paths in its effective workspace, including any nested members.
    workspace = json.loads(command('list-pub-workspace', [dart, 'pub', 'workspace', 'list', '--json']))
    cleanup_folders = set()
    for package in workspace['packages']:
        folder = Path(package['path'])
        if not folder.is_relative_to(root) or '..' in folder.parts:
            raise ValueError('Pub workspace package is outside the checkout: '+str(folder))
        relative = folder.relative_to(root)
        cache = existing_checkout_directory(root, relative/'.dart_tool/pub', 'workspace Pub metadata')
        if cache is not None:
            validate_mutable_file(cache/'workspace_ref.json', 'workspace Pub metadata')
        cleanup_folders.update((relative, *relative.parents))
    # Pub removes stray package configs at member roots and intermediate
    # directories. The root config is checked separately because Pub rewrites it.
    for relative in sorted(cleanup_folders - {Path('.')}):
        cache = existing_checkout_directory(root, relative/'.dart_tool', 'workspace Pub metadata')
        if cache is not None:
            validate_mutable_file(cache/'package_config.json', 'workspace Pub metadata')


def configuration(root):
    validate_flutter_outputs(root)
    validate_package_metadata(root)
    folder = root/MACOS_EPHEMERAL
    result = {str((folder/n).relative_to(root)): digest(folder/n) for n in GENERATED}
    for name in PACKAGE_METADATA:
        result[name] = digest(root/name)
    packages = folder/'Packages'
    if not packages.is_dir() or packages.resolve() != packages:
        raise ValueError('Missing or aliased generated Swift packages: '+str(packages))
    inventory = full_inventory(packages)
    for name in SWIFT_MANIFESTS:
        if inventory.get(name, {}).get('type') != 'file':
            raise ValueError('Missing generated Swift package manifest: '+name)
    for name, entry in inventory.items():
        if entry['type'] != 'directory':
            result[(packages/name).relative_to(root).as_posix()] = sha(encoded(entry))
    return result


def external_sources(root, flutter, command=None):
    """Record hosted package bytes and the resolved SDK package notices.

    Package resolution and SDK source have separate identities. Build-hook
    outputs are deliberately not included here: they are generated by the build
    and mapped back to these sources by the existing native provenance checker.
    """
    config = root/PACKAGE_CONFIG
    packages = read(config)
    result = verified_sdk_notices(root, flutter, packages, read(SPEC), command)
    for package in packages['packages']:
        name = package['name']
        root_uri = urljoin(config.as_uri(), package['rootUri'])
        configured = Path(unquote(urlparse(root_uri).path))
        folder = configured.resolve()
        if not folder.is_relative_to(flutter) and not folder.is_relative_to(root):
            if name in NATIVE_SOURCE_PACKAGES:
                # For native hooks the entire package is a potential input.
                # Inventory scanning must propagate errors under every directory.
                files = {path: entry for path, entry in full_inventory(folder).items() if entry['type'] != 'directory'}
            else:
                files = tree(folder)
            result[name] = {'path': str(folder), 'files': files,
                            'hostedNotice': hosted_notice_identity(root_uri, package, folder),
                            'noticeCaseSensitive': hosted_notice_case_sensitive(folder)}
            if configured != folder:
                result[name]['configuredPath'] = str(configured)
    if not {'libserialport_plus', 'sqlite3', 'native_toolchain_c', 'hooks', 'code_assets'} <= result.keys():
        raise ValueError('Resolved external native hook/source packages are incomplete')
    native_source_hashes(result)
    return result


def helpers(root):
    return {'tool/'+name: digest(root/'tool'/name) for name in HELPERS}


def require_equal(before, after, phase):
    if before != after:
        raise ValueError('Identity drift during '+phase)


def verify_git_tree(root, commit, tree, label, source=None):
    """Compare actual bytes, modes and tracked links with Git blobs, bypassing the index."""
    object_format = {40: 'sha1', 64: 'sha256'}.get(len(commit))
    if object_format is None or not re.fullmatch('[0-9a-f]+', commit):
        raise ValueError('Expected a full source commit identity')

    def blob_id(content):
        blob = hashlib.new(object_format, f'blob {len(content)}\0'.encode())
        blob.update(content)
        return blob.hexdigest()

    names = set()
    windows_crlf = []
    for entry in filter(None, tree.split('\0')):
        metadata, name = entry.split('\t', 1)
        if source is not None and name in VALIDATION_REPORTS:
            continue
        mode, kind, oid = metadata.split()
        path = root/safe(name)
        drift = f'{label} differs from recorded commit: {name}'
        if kind != 'blob' or path.parent.resolve() != path.parent:
            raise ValueError(drift)
        try:
            actual_mode = path.lstat().st_mode
        except FileNotFoundError as error:
            raise ValueError(drift) from error
        if source is None and mode == '120000' and stat.S_ISLNK(actual_mode):
            content = os.fsencode(os.readlink(path))
        elif (mode in ('100644', '100755') and stat.S_ISREG(actual_mode)
              and bool(actual_mode & stat.S_IXUSR) == (mode == '100755')
              and (source is None or bool(actual_mode & 0o111) == (mode == '100755'))):
            content = path.read_bytes()
        else:
            raise ValueError(f'{label} mode differs from recorded commit: {name}')
        if blob_id(content) != oid:
            normalized = content.replace(b'\r\n', b'\n')
            if (source is None and stat.S_ISREG(actual_mode) and name.endswith(WINDOWS_CHECKOUT_SUFFIXES)
                    and normalized.replace(b'\n', b'\r\n') == content and blob_id(normalized) == oid):
                windows_crlf.append(name)
            else:
                raise ValueError(drift)
        if source is not None and sha(content) != source.get(name):
            raise ValueError(drift)
        names.add(name)
    if source is not None and (extra := sorted(source.keys()-names)):
        raise ValueError(label+' is absent from recorded commit: '+', '.join(extra))
    return windows_crlf


def verify_committed_source(root, commit, source, command, name='checkout-tree'):
    tree = command(name, ['git', 'ls-tree', '-r', '-z', '--full-tree', commit])
    verify_git_tree(root, commit, tree, 'Clean source', source)


def require_committed_compilation(source, inputs):
    if changed := sorted(name for name, value in inputs.items() if source.get(name) != value):
        raise ValueError('Clean compilation inputs differ from recorded commit: '+', '.join(changed))


def depfile_paths(path, description):
    """Read the escaped paths in a Dart or Flutter depfile."""
    target, separator, deps = require_regular_file(path).read_text().rstrip('\n').partition(': ')
    if not target or not separator or not deps or '\n' in deps or '\n' in target:
        raise ValueError(f'Invalid {description} depfile: {path}')

    def paths(value):
        tokens = re.findall(r'(?:\\[\\ ]|[^\\ \t])+|\\', value)
        return [Path(re.sub(r'\\([\\ ])', r'\1', token)) for token in tokens]

    targets, dependencies = paths(target), paths(deps)
    if not targets or not dependencies or any(not item.is_absolute() or '..' in item.parts
                                               for item in targets+dependencies):
        raise ValueError(f'Noncanonical path in {description} depfile: {path}')
    return targets, dependencies


def compiler_depfile(path):
    targets, dependencies = depfile_paths(path, 'Dart compiler')
    if len(targets) != 1:
        raise ValueError('Invalid Dart compiler depfile: '+str(path))
    return targets[0], dependencies


def bind_compiler_inputs(root, dependencies, source, config, flutter, sdk_files, external, description):
    """Bind the reported files to the identities captured before compilation."""
    first_party = {}
    hosted_inputs = {}
    hosted = [(name, Path(package['path']), Path(package.get('configuredPath', package['path'])), package['files'])
              for name, package in external.items() if 'files' in package]
    for dep in dependencies:
        actual = dep.resolve(strict=True)
        for file in {dep, actual}:
            value = digest(file) if file.is_file() else None
            if file.is_relative_to(root):
                name = file.relative_to(root).as_posix()
                if name == PACKAGE_CONFIG and value == config.get(name):
                    continue
                if value is None or source.get(name) != value:
                    raise ValueError(f'{description} input is missing or differs from the prebuild source snapshot: {name}')
                first_party[name] = value
            elif file.is_relative_to(flutter):
                if value is None or file.relative_to(flutter).as_posix() not in sdk_files:
                    raise ValueError(f'{description} input is outside pinned Flutter source: {file}')
            else:
                matches = []
                for name, folder, configured, files in hosted:
                    for spelling in {folder, configured}:
                        if not file.is_relative_to(spelling):
                            continue
                        relative = file.relative_to(spelling).as_posix()
                        if actual == folder/relative and value is not None and files.get(relative, {}).get('sha256') == value:
                            matches.append((name, relative))
                if len(matches) != 1:
                    raise ValueError(f'{description} input has no unique verified hosted source: {file}')
                name, relative = matches[0]
                hosted_inputs.setdefault(name, {})[relative] = value
    return first_party, hosted_inputs


def compiler_inputs(root, depfiles, entry, source, config, flutter, sdk_files, external):
    dependencies = set()
    for path, expected_target in depfiles:
        target, inputs = compiler_depfile(path)
        if target != expected_target or entry not in inputs:
            raise ValueError('Dart compiler depfile does not identify this build: '+str(path))
        dependencies.update(inputs)
    return bind_compiler_inputs(root, dependencies, source, config, flutter, sdk_files, external, 'Dart compiler')


def app_asset_dependencies(root, assets, depfiles, flutter, external):
    """Return asset inputs, excluding only entries verified by separate gates."""
    notices = set()
    for package in external.values():
        if notice := package.get('sdkNotice'):
            notices.add(Path(notice['path']))
        if notice := package.get('hostedNotice'):
            paths = {Path(package['path']), Path(package.get('configuredPath', package['path']))}
            notices.update(path/notice['path'] for path in paths)
    generated = {depfile.with_name('native_assets.json') for depfile in depfiles}
    font = flutter/MATERIAL_ICONS_FONT
    app = root/'apps/meshchan_app'
    relevant = set()
    for path in assets-notices-generated-{font}:
        # Flutter records an intentionally missing prerequisite for wildcards.
        if (path.parent == app and re.fullmatch(r'DOES_NOT_EXIST_RERUN_FOR_WILDCARD\d+', path.name)
                and not os.path.lexists(path)):
            continue
        relevant.add(path)
    return relevant


def app_shader_inputs(root, assets, shader_plan, flutter, external):
    """Resolve includes for shader declarations selected by Flutter."""
    external_roots = (flutter, *(Path(package['path']) for package in external.values() if 'files' in package))
    inputs = set()
    for declaration in shader_plan:
        shader = Path(declaration['path'])
        for candidate in flutter_asset_files(shader):
            selected = candidate if candidate in assets else candidate.resolve()
            if selected not in assets:
                continue
            if declaration['transformed']:
                raise ValueError('Release input inventory cannot bind transformed Flutter shader: '+str(selected))
            inputs.add(selected)
            inputs.update(flutter_shader_includes(selected, root/'apps/meshchan_app', root,
                                                  flutter/SHADER_INCLUDE_DIR, external_roots=external_roots))
    return inputs


def reject_asset_transformers(assets, declarations):
    for declaration in declarations:
        for candidate in flutter_asset_files(Path(declaration['path'])):
            if candidate in assets or candidate.resolve() in assets:
                raise ValueError('Release input inventory cannot bind transformed Flutter asset: '+str(candidate))


def app_kernel_depfiles(root):
    validate_flutter_tree(root, APP_FLUTTER_CACHE, 'App build cache')
    return set((root/APP_FLUTTER_CACHE).glob('*/'+APP_KERNEL_DEPFILE))


def product_loader_path(bundle, value, binary, executable):
    anchor, _, relative = value.partition('/')
    bases = {'@loader_path': binary.parent, '@executable_path': executable.parent}
    if anchor not in bases:
        raise ValueError('External loader path: '+value)
    parent = bases[anchor]
    verify_product_path_steps(bundle, parent, relative, 'product loader path: '+value)
    # Path joining would discard terminal "/" or "/." before the OS lookup.
    return str(parent)+'/'+relative


def resolve_load(bundle, value, binary, executable, rpaths):
    # The image declaring an inherited LC_RPATH supplies its @loader_path.
    candidates = ([(path+'/'+value[len('@rpath/'):], owner) for path, owner in rpaths]
                  if value.startswith('@rpath/') else [(value, binary)])
    locations = [(path if path.startswith('/') else product_loader_path(bundle, path, owner, executable),
                  path.startswith('/')) for path, owner in candidates]
    for location, absolute in locations:
        if absolute:
            # Xcode supplies this Apple system runpath for the Swift runtime.
            # Skip it only if it cannot provide this product dependency.
            if (location.startswith('/usr/lib/swift/') and is_system_library_path(location)
                    and str(Path(location).resolve()) == location and system_library_location(location) is None):
                continue
            raise ValueError('Host-dependent loader resolution: '+value+' via '+location)
        if os.path.isfile(location):
            return Path(location).resolve(strict=True)
    return None


def is_system_library_path(path):
    return path.startswith(('/usr/lib/', '/System/Library/')) and posixpath.normpath(path) == path


def system_library_location(path):
    if Path(path).is_file():
        return 'filesystem'
    # Query the validation host without loading the library or running AppKit.
    try:
        contains = ctypes.CDLL(None)._dyld_shared_cache_contains_path
    except AttributeError as error:
        raise ValueError('Cannot query the macOS dyld shared cache') from error
    contains.argtypes = (ctypes.c_char_p,)
    contains.restype = ctypes.c_bool
    return 'dyld shared cache' if contains(os.fsencode(path)) else None


def macho_file_type(loads, binary, arch):
    header = re.search(r'^Mach header\n[^\n]*\bfiletype\b[^\n]*\n([^\n]+)', loads, re.MULTILINE)
    fields = header[1].split() if header else []
    if len(fields) < 8 or not fields[4].isdigit():
        raise ValueError(f'Cannot determine Mach-O file type for {arch}: {binary}')
    return int(fields[4])


def inspect_loaders(bundle, executable, env, *, app_assets=False):
    architectures = {}
    # Index every real Mach-O before resolving loads through framework symlinks.
    for name, item in full_inventory(bundle).items():
        if item['type'] != 'file':
            continue
        binary = bundle/name
        with binary.open('rb') as stream:
            magic = stream.read(4)
        if magic in MACH_O_THIN_32:
            raise ValueError('32-bit Mach-O cannot contain arm64: '+name)
        if magic not in MACH_O_64_OR_FAT:
            continue
        arches = capture(['/usr/bin/lipo', '-archs', binary], env=env).split()
        if 'arm64' not in arches:
            raise ValueError('Mach-O lacks arm64: '+name)
        architectures[binary] = arches
    if executable not in architectures:
        raise ValueError('Product executable is not Mach-O: '+str(executable))

    def commands(binary, arch):
        return capture(['/usr/bin/otool', '-arch', arch, '-h', '-l', binary], env=env)

    all_loads = {(binary, arch): commands(binary, arch)
                 for binary, arches in architectures.items() for arch in arches}
    file_types = {key: macho_file_type(loads, *key) for key, loads in all_loads.items()}
    runpaths = {key: re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset', loads)
                for key, loads in all_loads.items()}
    install_names = {key: match[1] for key, loads in all_loads.items()
                     if (match := re.search(r'cmd LC_ID_DYLIB\s+cmdsize \d+\s+name (.*?) \(offset', loads))}
    named_images = {}
    result = {binary.relative_to(bundle).as_posix(): {
        'architectures': arches,
        'slices': {arch: {'fileType': file_types[binary, arch], 'rpaths': runpaths[binary, arch]} for arch in arches},
    } for binary, arches in architectures.items()}
    visited = set()

    def remember_image(target, arch, path):
        # dyld can reuse a mapped image by its @rpath install name.
        for load_name in (path, install_names.get((target, arch), '')):
            if load_name.startswith('@rpath/'):
                previous = named_images.setdefault((arch, load_name), target)
                if previous != target:
                    raise ValueError(f'Ambiguous dylib install name for {arch}: {load_name}: '
                                     f'{previous.relative_to(bundle)} and {target.relative_to(bundle)}')

    def visit(binary, arch, inherited):
        if (binary, arch) in visited:
            return
        visited.add((binary, arch))
        name = binary.relative_to(bundle).as_posix()
        own = runpaths[binary, arch]
        chain = [(path, binary) for path in own] + inherited
        for r in own:
            if r.partition('/')[0] in RELATIVE_LOADER_ANCHORS:
                product_loader_path(bundle, r, binary, executable)
            # The pinned Flutter engine has an unused factory search path.
            elif not is_system_library_path(r) and r != APP_ENGINE_HOST_RUNPATH:
                raise ValueError('External runpath: '+r)
        # LC_ID_DYLIB is the binary's install ID. Only load commands
        # describe dependencies, including weak and re-exported loads.
        dependencies = re.findall(
            r'cmd (LC_(?:LOAD(?:_WEAK|_UPWARD)?|REEXPORT|LAZY_LOAD)_DYLIB)'
            r'\s+cmdsize \d+\s+name (.*?) \(offset', all_loads[binary, arch])
        classified, targets = [], []
        for command, dep in dependencies:
            if is_system_library_path(dep):
                location = system_library_location(dep)
                if location is None and command != 'LC_LOAD_WEAK_DYLIB':
                    raise ValueError(f'Missing required system dylib for {arch}: {name}: {dep}')
                classified.append({'path': dep, 'scope': 'OS system', 'loadCommand': command,
                                   'availability': location or 'missing weak load'})
                continue
            if not dep.startswith(('@rpath/', '@loader_path/', '@executable_path/')):
                raise ValueError('External loader path: '+dep)
            target = resolve_load(bundle, dep, binary, executable, chain)
            if target is None or not target.is_relative_to(bundle):
                raise ValueError('Unresolved product loader path: '+name+': '+dep)
            if arch not in architectures.get(target, ()):
                raise ValueError(f'Product loader target lacks {arch}: {name}: {dep}')
            if file_types[target, arch] != MH_DYLIB:
                raise ValueError(f'Product loader target is not a Mach-O dylib for {arch}: {name}: {dep}')
            remember_image(target, arch, dep)
            classified.append({'path': dep, 'scope': 'product', 'resolved': [target.relative_to(bundle).as_posix()]})
            targets.append(target)
        result[name]['slices'][arch].update(
            dependencies=classified,
            rpathChain=[{'path': path, 'owner': owner.relative_to(bundle).as_posix()} for path, owner in chain],
        )
        # Resolve direct loads in command order before walking their children.
        # A slice's first traversal establishes its context and breaks cycles.
        for target in targets:
            visit(target, arch, chain)

    for arch in architectures[executable]:
        visit(executable, arch, [])

    def load_native_asset(target, arch, rpaths, path):
        remember_image(target, arch, path)
        visit(target, arch, rpaths)

    native_assets = app_native_assets(bundle, result, load=load_native_asset) if app_assets else None
    # Inspect any remaining images with no known caller after walking both
    # the static graph and the manifest-loaded dependency graphs.
    for binary, arches in architectures.items():
        for arch in arches:
            visit(binary, arch, [(r, executable) for r in runpaths.get((executable, arch), ())])
    return result, native_assets


def loader_check(bundle, executable, env):
    return inspect_loaders(bundle, executable, env)[0]


def app_native_assets(app, loaders, *, load=None):
    frameworks = app/'Contents/Frameworks'
    manifest = frameworks/'App.framework/Resources/flutter_assets/NativeAssetsManifest.json'
    if not manifest.is_file() or not manifest.resolve().is_relative_to(app):
        raise ValueError('Missing or external App native asset manifest: '+str(manifest))
    spec = read(manifest)
    if (not isinstance(spec, dict) or spec.get('format-version') != [1, 0, 0]
            or not isinstance(spec.get('native-assets'), dict)):
        raise ValueError('Unsupported App native asset manifest format')
    executable = app/APP_RUNNER
    engine = app/APP_ENGINE_BINARY
    slices = loaders[APP_RUNNER]['slices']
    target_names = {'arm64': 'macos_arm64', 'x86_64': 'macos_x64'}
    require_equal({target_names[arch] for arch in slices}, set(spec['native-assets']),
                  'App native asset targets')
    result = {}
    for arch, details in slices.items():
        engine_slice = loaders.get(APP_ENGINE_BINARY, {}).get('slices', {}).get(arch)
        if (engine_slice is None or engine_slice['fileType'] != MH_DYLIB
                or not any(APP_ENGINE_BINARY in dep.get('resolved', ()) for dep in details['dependencies'])):
            raise ValueError('App native asset caller is not a linked Flutter engine for '+arch)
        # dyld starts an explicit dlopen lookup with the calling image, then
        # the main executable. This is separate from linked dependency walks.
        rpaths = [(rpath, engine) for rpath in engine_slice['rpaths']]
        rpaths.extend((rpath, executable) for rpath in details['rpaths'])
        key = target_names[arch]
        mappings = spec['native-assets'][key]
        if isinstance(mappings, dict) and (unknown := mappings.keys() - APP_NATIVE_ASSETS.keys()):
            raise ValueError(f'Unreviewed App native asset IDs for {key}: '+', '.join(sorted(unknown)))
        result[key] = {}
        for asset, framework in APP_NATIVE_ASSETS.items():
            path = '@rpath/'+framework
            if not isinstance(mappings, dict) or mappings.get(asset) != ['absolute', path]:
                raise ValueError(f'Invalid App native asset mapping for {key}: {asset}')
            expected = (frameworks/framework).resolve()
            target = resolve_load(app, path, engine, executable, rpaths)
            if target != expected or not expected.is_relative_to(app):
                raise ValueError(f'Unresolved App native asset for {key}: {asset}')
            relative = expected.relative_to(app).as_posix()
            if arch not in loaders.get(relative, {}).get('architectures', ()):
                raise ValueError(f'App native asset target lacks {arch}: {asset}')
            if loaders[relative]['slices'][arch]['fileType'] != MH_DYLIB:
                raise ValueError(f'App native asset target is not a Mach-O dylib for {arch}: {asset}')
            if load is not None:
                load(target, arch, rpaths, path)
            result[key][asset] = {'mapping': path, 'target': relative, 'caller': APP_ENGINE_BINARY,
                                  'rpathChain': [{'path': rpath, 'owner': owner.relative_to(app).as_posix()}
                                                 for rpath, owner in rpaths]}
    return result


def verify_cli_sqlite(bundle, executable, env):
    library = bundle/CLI_SQLITE_LIBRARY
    with tempfile.TemporaryDirectory(prefix='meshchan-cli-sqlite-') as directory:
        data = Path(directory)/'data'
        result = subprocess.run([str(executable), '--data-dir', str(data), 'settings', 'show', '--json'],
                                cwd=directory, env={**env, 'DYLD_PRINT_LIBRARIES': '1'},
                                text=True, capture_output=True, check=True)
        report = json.loads(result.stdout)
        if (report.get('schemaVersion') != 1 or report.get('operationSucceeded') is not True
                or report.get('exitCode') != 0 or report.get('storageClose', {}).get('state') != 'closed'):
            raise ValueError('CLI SQLite probe did not complete and close storage')
        database = data/'meshchan.sqlite'
        if not database.is_file():
            raise ValueError('CLI SQLite probe did not create a database')
        with database.open('rb') as stream:
            if stream.read(16) != b'SQLite format 3\0':
                raise ValueError('CLI SQLite probe did not produce a SQLite database')
        # The process can also load the OS SQLite through system frameworks.
        # Require the exact bundled library in this storage command's trace.
        loaded = set(re.findall(r'^dyld\[\d+\]: <[0-9A-Fa-f-]+> (/.+)$', result.stderr, re.MULTILINE))
        if not loaded.intersection((str(library), str(library.resolve()))):
            raise ValueError('CLI SQLite probe did not load its bundled '+CLI_SQLITE_LIBRARY)
    return {'operation': 'settings show', 'loadedLibrary': CLI_SQLITE_LIBRARY, 'storageClose': 'closed'}


def verify_app_aot(app, loaders, env):
    binary = app/APP_AOT_BINARY
    name = binary.resolve().relative_to(app).as_posix()
    arm64 = loaders.get(name, {}).get('slices', {}).get('arm64', {})
    if arm64.get('fileType') != MH_DYLIB:
        raise ValueError('App.framework AOT snapshot is not an arm64 dylib: '+name)
    report = capture(['/usr/bin/xcrun', 'dyld_info', '-arch', 'arm64', '-exports', binary], env=env)
    # Require exports with their own addresses. A reexport cannot supply the
    # data and text embedded in this framework's Dart snapshot.
    exports = set(re.findall(r'^\s+0x[0-9a-fA-F]+\s+(\S+)\s*$', report, re.MULTILINE))
    if missing := set(APP_AOT_EXPORTS)-exports:
        raise ValueError('App.framework arm64 lacks Dart AOT exports: '+', '.join(sorted(missing)))
    return {'binary': name, 'architecture': 'arm64', 'exports': list(APP_AOT_EXPORTS)}


def audit_macho_paths(bundle, binary_names, *roots):
    paths = [os.fsencode(root) for root in roots]
    paths.extend(root.as_uri().encode() for root in roots)
    names = sorted(binary_names)
    for name in names:
        data = (bundle/name).read_bytes()
        if contains_macho_local_path(data) or any(path+b'/' in data or path+b'\0' in data for path in paths):
            raise ValueError('Local build path remains in '+name)
    return names


def products(root, app, cli, ident, env, *, hook_cache=None, path_audit=False):
    check_app(app, ident['productVersion'], int(ident['appBuild']))
    required = {app: [APP_AOT_BINARY,
                      'Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS',
                      'Contents/Frameworks/libserialport_plus.framework/libserialport_plus',
                      'Contents/Frameworks/sqlite3.framework/sqlite3'],
                cli: ('bin/meshctl', *CLI_LIBRARIES)}
    for bundle, names in required.items():
        for name in names:
            if not (bundle/name).is_file() or not (bundle/name).stat().st_size:
                raise ValueError('Incomplete product: '+str(bundle/name))
    executable = cli/'bin/meshctl'
    # The loader walks the complete bundle and rejects escaping symlinks
    # before the validator executes any candidate code.
    cli_loaders = loader_check(cli, executable, env)
    app_loaders, app_assets = inspect_loaders(app, app/APP_RUNNER, env, app_assets=True)
    app_aot = verify_app_aot(app, app_loaders, env)
    loaders = {'cli': cli_loaders, 'app': app_loaders}
    audit = {}
    if path_audit:
        audit_roots = (root, release_build_root(root))
        audit = {'pathAudit': {'app': audit_macho_paths(app, app_loaders, *audit_roots),
                               'cli': audit_macho_paths(cli, cli_loaders, *audit_roots)}}
    signatures = {}
    signed_products = {'app': app, 'cli': executable,
                       **{'cli/'+name: cli/name for name in CLI_LIBRARIES}}
    for label, path in signed_products.items():
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', '--all-architectures', str(path)], check=True, env=env, capture_output=True)
        detail = subprocess.run(['/usr/bin/codesign', '-d', '--verbose=4', '--entitlements', ':-', str(path)], env=env, text=True, capture_output=True, check=True)
        signatures[label] = {'details': detail.stderr, 'entitlements': detail.stdout,
                             'condition': 'Local build signature only; Developer ID and notarization NOT_RUN'}
    if capture([executable, '--version'], root, env) != 'meshctl '+ident['productVersion']:
        raise ValueError('CLI compiled version mismatch')
    sqlite = verify_cli_sqlite(cli, executable, env)
    config = root/'.dart_tool/package_config.json'
    locations = {p['name']: Path(unquote(urlparse(urljoin(config.as_uri(), p['rootUri'])).path)).resolve() for p in read(config)['packages']}
    # Reuse the strict per-slice hook/source/loader provenance check without
    # collecting licenses or rerunning the 1D regression matrix.
    with tempfile.TemporaryDirectory(prefix='meshchan-build-provenance-') as temporary:
        collector = Collector(SimpleNamespace(repo=root, app=app, cli=cli), Path(temporary))
        collector.hook_cache = hook_cache
        native = collector.native_mapping(locations)
        if collector.blockers:
            raise ValueError('; '.join(collector.blockers))
    return {'status': 'PASS', 'loaders': loaders, 'native': native, 'signatures': signatures,
            'appAotSnapshot': app_aot, 'appNativeAssets': app_assets, 'cliSQLite': sqlite, **audit}


def product_paths(out):
    return out/'app-derived/Build/Products/Release/Meshchan.app', out/'cli/bundle'


def cli_dart_sdk(dart, overlay):
    """Use the pinned SDK while giving its snapshot output a portable name."""
    sdk = dart.parent.parent
    launchers = ('dart', 'dartvm', 'dartaotruntime')
    for directory, replaced in (('.', ('bin',)), ('bin', (*launchers, 'utils')),
                                ('bin/utils', ('gen_snapshot',))):
        target = overlay/directory
        target.mkdir(exist_ok=True)
        for entry in sorted((sdk/directory).iterdir()):
            if entry.name not in replaced:
                (target/entry.name).symlink_to(entry)
    # DartDev derives the SDK root from the physical launcher location.
    for name in launchers:
        shutil.copy2(sdk/'bin'/name, overlay/'bin'/name)
    utils = overlay/'bin/utils'
    (utils/'gen_snapshot-sdk').symlink_to(sdk/'bin/utils/gen_snapshot')
    compiler = utils/'gen_snapshot'
    compiler.write_text(CLI_SNAPSHOT_LAUNCHER, encoding='utf-8')
    compiler.chmod(0o700)
    return overlay/'bin/dart'


def candidate_inventories(out):
    app, cli = product_paths(out)
    return {'app': full_inventory(app), 'cli': full_inventory(cli)}


def normalize_app_engine_runpath(app, out, command):
    owned_path(app, out)
    engine = owned_path(app/APP_ENGINE_BINARY, app)
    for name, entry in full_inventory(app).items():
        if entry['type'] == 'file' and (app/name).stat().st_nlink != 1:
            raise ValueError('App runpath normalization requires an owned file: '+name)
    # This recipe reseals the exact local Xcode signature condition. Stop
    # before editing if Xcode selected a certificate identity.
    for label, bundle, binary in (('engine', app/APP_ENGINE, engine), ('app', app, app/APP_RUNNER)):
        arches = command(f'{label}-signature-architectures', ['/usr/bin/lipo', '-archs', binary]).split()
        if not arches:
            raise ValueError('Missing Mach-O architectures for '+label)
        for arch in arches:
            details = command(f'{label}-signature-before-normalization-{arch}',
                              ['/usr/bin/codesign', '-d', '--verbose=2', '--arch', arch, bundle],
                              return_stderr=True)
            if 'Signature=adhoc' not in details.splitlines():
                raise ValueError('App runpath normalization requires existing local ad hoc signatures: '+label)
    command('app-engine-normalize-runpath', ['/usr/bin/xcrun', 'install_name_tool', '-delete_rpath',
                                              APP_ENGINE_HOST_RUNPATH, engine])
    for label, bundle in (('app-engine', app/APP_ENGINE), ('app', app)):
        command(f'{label}-reseal-ad-hoc', ['/usr/bin/codesign', '--force', '--sign', '-',
                                            '--preserve-metadata=identifier,entitlements,flags,requirements,runtime', bundle])


def run_product_checks(root, out, command):
    # Isolate the full validator, including tools invoked inside native mapping.
    # The child never acquires the checkout lock held by the parent.
    output = command('validate-products', [sys.executable, root/'tool/build_release.py',
                                          '_validate-products', '--output', out])
    report = json.loads(output)
    require_equal('PASS', report.get('status'), 'product validator outcome')
    return report


def ref(root, path):
    if path.is_relative_to(root):
        return {'path': safe(path.relative_to(root).as_posix()), 'sha256': digest(owned_file(path, root))}
    physical_build = release_build_root(root)
    return {'path': release_relative_path(root, physical_build, path),
            'sha256': digest(owned_file(path, physical_build))}


def build(args):
    root = ROOT.resolve()
    with checkout_lock(root), DeferredInterrupts() as interrupted, ExitStack() as hooks:
        out = output_path(root, args.output, new=True, timeout=args.timeout)
        physical_build = release_build_root(root)
        run_identity = release_relative_path(root, physical_build, out)
        env, flutter = controlled_environment(), args.flutter.expanduser().resolve()
        raise_if_interrupted(interrupted)
        out.mkdir(parents=True)
        evidence = out/'evidence';evidence.mkdir()
        shutil.copyfile(root/'tool/build_release.py', evidence/'run_build.py')
        receipt = {'formatVersion': 1, 'recipeVersion': RECIPE_VERSION, 'status': 'RUNNING', 'startedAt': now(),
                   'engineeringDirtyMode': args.allow_dirty, 'runnerSha256': digest(evidence/'run_build.py'), 'steps': []}
        runner = Runner(root, evidence, receipt, env, args.timeout, interrupted, physical_build=physical_build)
        info = {'formatVersion': 1, 'runIdentity': run_identity,
                'buildStatus': 'RUNNING', 'productChecksStatus': 'NOT_RUN', 'materials': {'status': 'NOT_RUN'},
                'laterReleaseValidation': 'NOT_RUN: staging, formal signing, notarization, DMG, installation, upgrade, hardware, remote CI, publication'}
        try:
            runner.save()
            write(out/'build-info.json', info)
            raise_if_interrupted(interrupted)
            status = runner.command('checkout-status', ['git', 'status', '--porcelain=v1',
                                                        '--untracked-files=all']).rstrip('\n')
            receipt['workingTree'] = status
            if status and not args.allow_dirty:
                raise ValueError('Stable source required; review changes and explicitly use --allow-dirty for engineering validation')
            receipt['sourceCommit'] = runner.command('checkout-commit', ['git', 'rev-parse', 'HEAD']).strip()
            validate_flutter_outputs(root)
            # This source snapshot needs no package configuration, so it can
            # guard the lockfile and source even on the first pub get.
            source = repository_source_hashes(root, [out], command=runner.command, label='source-before-resolution')
            source_metadata = repository_source_metadata(root, source)
            if not args.allow_dirty:
                verify_committed_source(root, receipt['sourceCommit'], source, runner.command)
            ident = identity(root, args.expected_version, args.app_build)
            helper_hashes = helpers(root)
            tools = toolchain(flutter, runner.command, root=root, env=env)
            runner.command('source-version', [sys.executable, root/'tool/check_product_version.py', '--expected-version', ident['productVersion'], '--app-build', ident['appBuild']])
            validate_package_metadata(root)
            validate_swift_package_cache(root, env)
            dart = flutter/'bin/cache/dart-sdk/bin/dart'
            validate_workspace_pub_metadata(root, dart, runner.command)
            require_ready_flutter_launcher(flutter)
            read_flutter_settings(root, env)
            runner.command('locked-resolution', [flutter/'bin/flutter', '--no-version-check', 'pub', 'get', '--enforce-lockfile'])
            require_equal(source, repository_source_hashes(root, [out], command=runner.command,
                                                           label='source-after-resolution'), 'locked resolution')
            require_equal(source_metadata, repository_source_metadata(root, source), 'source metadata after locked resolution')
            # The Dart YAML parser can now use the freshly resolved workspace.
            before_config = inputs(root, dart, runner.command, 'snapshot-before-configuration', flutter=flutter)
            write(evidence/'inputs-before-configuration.json', before_config)
            validate_package_metadata(root)
            validate_flutter_outputs(root)
            validate_swift_package_cache(root, env)
            require_equal(tools['releaseFramework'], release_framework_identity(flutter), 'Release FlutterMacOS framework before configuration')
            require_ready_flutter_launcher(flutter)
            runner.command('configure-release', [flutter/'bin/flutter', '--no-version-check', 'build', 'macos',
                                                 '--release', '--no-pub', '--config-only'], root/'apps/meshchan_app')
            before = inputs(root, dart, runner.command, 'snapshot-before-build', flutter=flutter)
            require_equal(before_config, before, 'Release configuration')
            require_equal(source, repository_source_hashes(root, [out], command=runner.command,
                                                           label='source-after-configuration'), 'source preparation')
            require_equal(source_metadata, repository_source_metadata(root, source), 'source metadata after Release configuration')
            if not args.allow_dirty:
                require_committed_compilation(source, before)
            compiler_source = before | source if args.allow_dirty else source
            write(evidence/'compilation-input-hashes.json', before)
            config = configuration(root)
            external = external_sources(root, flutter, lambda argv, cwd: runner.command('sdk-notices-before-build', argv, cwd))
            sdk_dart_sources = set(runner.command('sdk-dart-source-paths',
                ['git', 'ls-tree', '-r', '-z', '--name-only', tools['flutter']['frameworkRevision'], '--', 'packages'],
                flutter).split('\0'))
            graph = json.loads(runner.command('resolved-graph', [flutter/'bin/cache/dart-sdk/bin/dart', 'pub', 'deps', '--json']))
            write(evidence/'resolved-graph.json', graph)
            write(evidence/'prebuild-identities.json', {'toolchain': tools, 'helpers': helper_hashes, 'configuration': config, 'source': source,
                                                       'sourceMetadata': source_metadata, 'externalSources': external})
            app, cli = product_paths(out)
            native_hooks = hooks.enter_context(fresh_native_hook_cache(root, out))
            compiler_dir = evidence/'compiler'
            compiler_dir.mkdir()
            cli_depfile = compiler_dir/'cli.d'
            cli_project = root/'apps/meshctl'
            # Dart embeds the AOT scratch filename in the executable's debug map.
            # Keep an absolute temporary directory for native hooks, which run
            # in other working directories, and change only the snapshot name.
            with tempfile.TemporaryDirectory(prefix='cli-sdk-', dir=compiler_dir) as scratch:
                cli_tmp = Path(scratch)/'tmp'
                cli_tmp.mkdir(mode=0o700)
                cli_dart = cli_dart_sdk(dart, Path(scratch)/'dart-sdk')
                runner.command('cli-build', ['/usr/bin/env', 'TMPDIR='+str(cli_tmp), cli_dart,
                                             'build', 'cli', '--packages', root/PACKAGE_CONFIG,
                                             '--target', CLI_RELEASE_ENTRY, '--output', out/'cli',
                                             '--depfile', cli_depfile], cli_project)
            after_cli = inputs(root, dart, runner.command, 'snapshot-after-cli', flutter=flutter)
            write(evidence/'inputs-after-cli.json', after_cli)
            require_equal(before, after_cli, 'CLI build')
            cli_sources, cli_hosted = compiler_inputs(
                root, [(cli_depfile, cli/'bin/meshctl')], root/'apps/meshctl'/CLI_RELEASE_ENTRY,
                compiler_source, config, flutter, sdk_dart_sources, external)
            cli_executable = owned_path(cli/'bin/meshctl', out)
            if not cli_executable.is_file() or cli_executable.stat().st_nlink != 1:
                raise ValueError('CLI runpath normalization requires an owned executable: '+str(cli_executable))
            runner.command('cli-normalize-runpath', ['/usr/bin/xcrun', 'install_name_tool', '-delete_rpath',
                                                     CLI_SDK_RUNPATH, cli_executable])
            runner.command('cli-sign-ad-hoc', ['/usr/bin/codesign', '--force', '--sign', '-',
                                               '--preserve-metadata=identifier,entitlements,flags', cli_executable])
            require_equal(config, configuration(root), 'generated configuration before App build')
            derived = out/'app-derived'
            validate_flutter_tree(root, HOOK_CACHE, 'native hook cache')
            require_equal(external, external_sources(root, flutter, lambda argv, cwd: runner.command(
                'sdk-notices-before-app', argv, cwd)), 'external package sources before App build')
            require_equal(tools['releaseFramework'], release_framework_identity(flutter), 'Release FlutterMacOS framework before App build')
            require_ready_flutter_launcher(flutter)
            asset_plan = json.loads(runner.command('app-asset-plan',
                [*input_parser_argv(root, dart), '--asset-plan']))
            previous_app_depfiles = app_kernel_depfiles(root)
            runner.command('app-build', [
                '/usr/bin/xcrun', 'xcodebuild', '-workspace', 'Runner.xcworkspace', '-scheme', 'Runner',
                '-configuration', 'Release', '-destination', 'generic/platform=macOS', '-derivedDataPath', derived,
                'OBJROOT='+str(derived/'Build/Intermediates.noindex'), 'SYMROOT='+str(derived/'Build/Products'),
                'COMPILER_INDEX_STORE_ENABLE=NO', 'MESHCHAN_BUILD_PYTHON='+sys.executable,
            ], root/'apps/meshchan_app/macos')
            validate_flutter_tree(root, HOOK_CACHE, 'native hook cache')
            hooks.close()
            receipt['nativeHookCacheSha256'] = sha(encoded(full_inventory(native_hooks)))
            runner.save()
            after_app = inputs(root, dart, runner.command, 'snapshot-after-app', flutter=flutter)
            write(evidence/'inputs-after-app.json', after_app)
            require_equal(before, after_app, 'App build')
            app_depfiles = sorted(app_kernel_depfiles(root)-previous_app_depfiles)
            if not app_depfiles:
                raise ValueError('Release App build did not produce a fresh Dart kernel depfile')
            app_sources, app_hosted = compiler_inputs(
                root, [(path, path.with_name('app.dill')) for path in app_depfiles], root/'apps/meshchan_app/lib/main.dart',
                compiler_source, config, flutter, sdk_dart_sources, external)
            asset_depfiles = [path.with_name(APP_ASSET_DEPFILE) for path in app_depfiles]
            assets = {path for depfile in asset_depfiles for path in depfile_paths(depfile, 'Flutter asset')[1]}
            reject_asset_transformers(assets, asset_plan['transformedAssets'])
            asset_sources, asset_hosted = bind_compiler_inputs(root,
                app_asset_dependencies(root, assets, asset_depfiles, flutter, external)
                | app_shader_inputs(root, assets, asset_plan['shaders'], flutter, external),
                compiler_source, config, flutter, sdk_dart_sources, external, 'Flutter asset')
            app_sources.update(asset_sources)
            for name, files in asset_hosted.items():
                app_hosted.setdefault(name, {}).update(files)
            raw_depfiles = [cli_depfile]
            for label, depfiles in (('app', app_depfiles), ('app-assets', asset_depfiles)):
                for number, path in enumerate(depfiles):
                    copied = compiler_dir/f'{label}-{number}.d'
                    shutil.copyfile(path, copied)
                    raw_depfiles.append(copied)
            write(evidence/'compiler-inputs.json', {'firstParty': {'cli': cli_sources, 'app': app_sources},
                'hosted': {'cli': cli_hosted, 'app': app_hosted},
                'hostedNotices': {name: package['hostedNotice'] for name, package in external.items()
                                  if 'hostedNotice' in package},
                'depfileHashes': {path.relative_to(evidence).as_posix(): digest(path) for path in raw_depfiles}})
            normalize_app_engine_runpath(app, out, runner.command)
            require_equal(config, configuration(root), 'generated configuration')
            require_equal(tools, toolchain(flutter, runner.command, 'flutter-version-after-build', root=root, env=env), 'toolchain')
            require_equal(helper_hashes, helpers(root), 'build helpers')
            require_equal(source, repository_source_hashes(root, [out], command=runner.command,
                                                           label='source-after-build'), 'repository source')
            verified_inventories = candidate_inventories(out)
            checks = run_product_checks(root, out, runner.command)
            raise_if_interrupted(interrupted)
            require_equal(external, external_sources(root, flutter, lambda argv, cwd: runner.command(
                'sdk-notices-after-build', argv, cwd)), 'external package sources')
            write(evidence/'product-checks.json', checks)
            write(evidence/'candidate-inventories.json', verified_inventories)
            lines = [item['sha256']+'  '+release_relative_path(root, physical_build, bundle/name)
                     for label, bundle in (('app', app), ('cli', cli))
                     for name, item in verified_inventories[label].items() if item['type'] == 'file']
            (evidence/'candidate-checksums.txt').write_text('\n'.join(sorted(lines))+'\n')
            require_equal(before, inputs(root, dart, runner.command, 'snapshot-before-publication', flutter=flutter),
                          'compilation inputs before publication')
            require_equal(source, repository_source_hashes(root, [out], command=runner.command,
                                                           label='source-before-publication'),
                          'repository source before publication')
            if not args.allow_dirty:
                verify_committed_source(root, receipt['sourceCommit'], source, runner.command, 'checkout-tree-after-build')
            require_equal(source_metadata, repository_source_metadata(root, source), 'source metadata after build')
            require_equal(config, configuration(root), 'generated configuration before publication')
            require_equal(verified_inventories, candidate_inventories(out), 'products during validation')
            verify_native_hook_cache(evidence/'build-receipt.json', receipt)
            final_commit = runner.command('checkout-commit-after-build', ['git', 'rev-parse', 'HEAD']).strip()
            require_equal(receipt['sourceCommit'], final_commit, 'checkout commit')
            raise_if_interrupted(interrupted)
            receipt.update(status='PASS', finishedAt=now(),
                           app=release_relative_path(root, physical_build, app),
                           cli=release_relative_path(root, physical_build, cli),
                           inputsUnchangedAcrossBuilds=True, inputCount=len(before),
                           compilationInputsSha256=digest(evidence/'compilation-input-hashes.json'),
                           candidateChecksumsSha256=digest(evidence/'candidate-checksums.txt'),
                           candidateInventoriesSha256=digest(evidence/'candidate-inventories.json'),
                           compilerInputsSha256=digest(evidence/'compiler-inputs.json'),
                           prebuildIdentitiesSha256=digest(evidence/'prebuild-identities.json'),
                           resolvedGraphSha256=digest(evidence/'resolved-graph.json'),
                           productChecksSha256=digest(evidence/'product-checks.json'))
            runner.save()
            info.update(buildStatus='PASS', productChecksStatus='PASS', identity=ident, sourceCommit=receipt['sourceCommit'],
                        workingTree=status, engineeringDirtyMode=args.allow_dirty, toolchain=tools, helperHashes=helper_hashes,
                        sourceInputIdentity=sha(encoded(source)), compilationInputIdentity=receipt['compilationInputsSha256'],
                        lockSha256=before['pubspec.lock'], resolvedGraphSha256=receipt['resolvedGraphSha256'],
                        controlledConfiguration={'environment': {k: env[k] for k in ('PATH', 'LANG', 'LC_ALL',
                                                                                     'GIT_NO_REPLACE_OBJECTS')},
                                                 'generated': config},
                        recipeVersion=RECIPE_VERSION, recipe=receipt['steps'], app=receipt['app'], cli=receipt['cli'],
                        signatures=checks['signatures'], evidence={p.name: ref(root, p) for p in evidence.iterdir() if p.is_file()})
            write(out/'build-info.json', info)
            # A signal arriving while either PASS file was being written
            # invalidates both. Keep holding the lock through publication.
            while not interrupted.seal_if_unchanged(0):
                raise_if_interrupted(interrupted)
        except BaseException as error:
            # Record any cache cleanup error as a note on the build failure.
            hooks.__exit__(*sys.exc_info())
            failure = failure_message(error)
            receipt.update(status='FAIL', finishedAt=now(), error=failure)
            info.update(buildStatus='FAIL', error=failure)
            if interrupted:
                receipt['interruptSignal'] = info['interruptSignal'] = int(interrupted[0])
            runner.save()
            write(out/'build-info.json', info)
            raise
    return info


def owned_path(path, parent):
    if path == parent or not path.is_relative_to(parent) or path.resolve() != path:
        raise ValueError('Path is not owned by the selected run: '+str(path))
    return path


def owned_file(path, parent):
    return require_regular_file(owned_path(path, parent))


def require_checkout_commit(expected, command, name):
    require_equal(expected, command(name, ['git', 'rev-parse', 'HEAD']).strip(), 'checkout commit')


def verify_evidence(root, out, info):
    physical_build = release_build_root(root)
    require_equal(release_relative_path(root, physical_build, out), info.get('runIdentity'), 'selected run')
    if info.get('buildStatus') != 'PASS' or info.get('productChecksStatus') != 'PASS':
        raise ValueError('Build is incomplete or failed')
    app, cli = (owned_path(path, out) for path in product_paths(out))
    require_equal((app, cli), tuple(release_reference(root, physical_build, info[k]) for k in ('app', 'cli')),
                  'selected run products')
    evidence = owned_path(out/'evidence', out)
    required = {'build-receipt.json', 'compilation-input-hashes.json', 'inputs-after-cli.json',
                'inputs-after-app.json', 'run_build.py', 'candidate-checksums.txt',
                'candidate-inventories.json', 'prebuild-identities.json', 'resolved-graph.json',
                'product-checks.json'}
    if info['recipeVersion'] >= 40:
        required.add('compiler-inputs.json')
    if not required <= info['evidence'].keys():
        raise ValueError('Selected run lacks required build evidence')
    for name, value in info['evidence'].items():
        path = owned_path(release_reference(root, physical_build, value['path']), evidence)
        if path.parent != evidence or path.name != name or not path.is_file() or digest(path) != value['sha256']:
            raise ValueError('Evidence file changed: '+value['path'])
    receipt_path = evidence/'build-receipt.json'
    receipt = read(receipt_path)
    for key, name, label in (
        ('candidateInventoriesSha256', 'candidate-inventories.json', 'product inventory'),
        ('prebuildIdentitiesSha256', 'prebuild-identities.json', 'prebuild identities'),
        ('resolvedGraphSha256', 'resolved-graph.json', 'resolved dependency graph'),
        ('productChecksSha256', 'product-checks.json', 'product check report'),
    ):
        require_equal(info['evidence'][name]['sha256'], receipt.get(key), label+' receipt')
    require_equal(info['sourceCommit'], receipt['sourceCommit'], 'build receipt commit')
    require_equal((info['app'], info['cli']), (receipt['app'], receipt['cli']), 'build receipt products')
    steps = receipt['steps']
    for step in steps:
        owned_path(release_reference(root, physical_build, step['log']), evidence)
        if 'stderrLog' in step:
            owned_path(release_reference(root, physical_build, step['stderrLog']), evidence)
    verify_build_receipt(root, receipt_path, evidence/'compilation-input-hashes.json',
                         evidence/'candidate-checksums.txt', app, cli)
    before = read(evidence/'compilation-input-hashes.json')
    prebuild = read(evidence/'prebuild-identities.json')
    for key, expected in (
        ('workingTree', receipt['workingTree']),
        ('engineeringDirtyMode', receipt['engineeringDirtyMode']),
        ('recipeVersion', receipt['recipeVersion']),
        ('recipe', steps),
        ('compilationInputIdentity', receipt['compilationInputsSha256']),
        ('sourceInputIdentity', sha(encoded(prebuild['source']))),
        ('lockSha256', before['pubspec.lock']),
        ('resolvedGraphSha256', receipt['resolvedGraphSha256']),
    ):
        require_equal(expected, info[key], 'indexed build provenance '+key)
    names = [s['name'] for s in steps]
    if not names.index('configure-release') < names.index('cli-build') < names.index('app-build') < names.index('validate-products'):
        raise ValueError('Build phase order mismatch')
    report = read(evidence/'product-checks.json')
    require_equal('PASS', report.get('status'), 'product check outcome')
    validator = steps[names.index('validate-products')]
    require_equal(report, read(release_reference(root, physical_build, validator['log'])), 'product validator output')
    require_equal(report['signatures'], info['signatures'], 'indexed product signatures')
    for line in (evidence/'candidate-checksums.txt').read_text().splitlines():
        expected, name = line.split('  ', 1)
        path = release_reference(root, physical_build, name)
        if not path.is_relative_to(app) and not path.is_relative_to(cli):
            raise ValueError('Checksum path is outside the selected products: '+name)
        if digest(owned_file(path, app if path.is_relative_to(app) else cli)) != expected:
            raise ValueError('Product checksum mismatch: '+name)
    return evidence


def bound_material_output(root, out, value):
    """Find the physical material directory named by a checkout-local receipt."""
    output = Path(value)
    logical_run = root/release_relative_path(root, release_build_root(root), out)
    if output.parent == logical_run:
        output = out/output.name
    if output.parent != out:
        raise ValueError('Materials directory does not belong to the selected run')
    return owned_path(output, out)


def verify_material_binding(root, out, materials):
    physical_build = release_build_root(root)
    output = bound_material_output(root, out, materials['arguments']['output'])
    references = materials['references']
    expected = {'materials-manifest.json': output,
                **{name: out/'evidence' for name in ('collect.log', 'collect.stderr.log', 'check.log', 'check.stderr.log')}}
    if set(references) != expected.keys():
        raise ValueError('Missing material binding for selected run')
    for name, parent in expected.items():
        value = references[name]
        path = owned_file(release_reference(root, physical_build, value['path']), parent)
        if (path.name != name or (parent == output and path.parent != output)
                or digest(path) != value['sha256']):
            raise ValueError('Material binding changed: '+value['path'])
    manifest = read(require_material_file(output, 'materials-manifest.json'))
    for name in manifest['materials']:
        require_material_file(output, name)
    if unlisted := unlisted_material_files(output, manifest['materials']):
        raise ValueError('Unlisted material: '+', '.join(unlisted))


def bind_prebuild_index(info, prebuild):
    require_equal(prebuild['toolchain'], info['toolchain'], 'indexed toolchain')
    require_equal(prebuild['helpers'], info['helperHashes'], 'indexed helpers')
    require_equal(prebuild['configuration'], info['controlledConfiguration']['generated'],
                  'indexed generated configuration')


def check(args, locked=False):
    timeout = getattr(args, 'timeout', 3600)
    root = ROOT.resolve();out = output_path(root, args.output, timeout=timeout)
    if not locked:
        with checkout_lock(root):
            return check(args, locked=True)
    info = read(owned_file(out/'build-info.json', out))
    evidence = verify_evidence(root, out, info)
    receipt_path = evidence/'build-receipt.json'
    receipt = read(owned_file(receipt_path, evidence))
    inventories = read(evidence/'candidate-inventories.json')
    recorded_inputs = read(evidence/'compilation-input-hashes.json')
    env = controlled_environment()
    with verification_runner(root, out, 'check-inputs', env, timeout) as runner:
        require_checkout_commit(info['sourceCommit'], runner.command, 'checkout-commit-before-check')
        if getattr(args, 'require_frozen', False):
            if info['engineeringDirtyMode'] is not False or info['workingTree']:
                raise ValueError('Handoff requires a build from a frozen source commit')
            if info['materials']['status'] != 'PASS':
                raise ValueError('Handoff requires accepted candidate materials')
        if info['materials']['status'] == 'PASS':
            verify_material_binding(root, out, info['materials'])
        prebuild = read(owned_file(evidence/'prebuild-identities.json', evidence))
        bind_prebuild_index(info, prebuild)
        flutter = Path(prebuild['toolchain']['flutterPath'])
        require_equal(info['identity'], identity(root), 'current product identity')
        require_equal(prebuild['helpers'], helpers(root), 'current helpers')
        if not info['engineeringDirtyMode']:
            verify_committed_source(root, info['sourceCommit'], prebuild['source'], runner.command)
        require_equal(prebuild['toolchain'], toolchain(flutter, runner.command, root=root, env=env), 'current toolchain')
        package_config = require_material_file(root, PACKAGE_CONFIG)
        require_equal(prebuild['configuration'].get(PACKAGE_CONFIG), digest(package_config),
                      'current workspace package configuration')
        dart = flutter/'bin/cache/dart-sdk/bin/dart'
        observed = inputs(root, dart, runner.command, 'snapshot-check', flutter=flutter)
        require_equal(recorded_inputs, observed, 'current compilation inputs')
        if not info['engineeringDirtyMode']:
            require_committed_compilation(prebuild['source'], observed)
        require_equal(prebuild['source'], repository_source_hashes(root, [out], command=runner.command,
                                                                   label='source-check'), 'current source')
        if info['recipeVersion'] >= 33:
            require_equal(prebuild.get('sourceMetadata'), repository_source_metadata(root, prebuild['source']),
                          'current source metadata')
        require_equal(prebuild['configuration'], configuration(root), 'current generated configuration')
        require_equal(prebuild['externalSources'], external_sources(root, flutter, lambda argv, cwd: runner.command(
            'sdk-notices-check', argv, cwd)), 'current external package sources')
    with verification_runner(root, out, 'check-products', env, timeout) as runner:
        live = run_product_checks(root, out, runner.command)
        require_equal(info['signatures'], live['signatures'], 'current product signatures')
    if info['materials']['status'] == 'PASS':
        _, checked = strict_materials(root, out, info, info['materials']['arguments'], 'check', 'recheck', timeout)
        require_equal(info['materials']['references']['materials-manifest.json']['sha256'], checked,
                      'accepted material manifest')
    with verification_runner(root, out, 'check-commit', env, timeout) as runner:
        require_equal(prebuild['configuration'], configuration(root), 'generated configuration during verification')
        require_equal(recorded_inputs, inputs(root, dart, runner.command, 'snapshot-after-check', flutter=flutter),
                      'compilation inputs during verification')
        require_equal(prebuild['source'], repository_source_hashes(root, [out], command=runner.command,
                                                                   label='source-after-check'), 'source during verification')
        if info['recipeVersion'] >= 33:
            require_equal(prebuild.get('sourceMetadata'), repository_source_metadata(root, prebuild['source']),
                          'source metadata during verification')
        require_equal(inventories, candidate_inventories(out), 'products during verification')
        verify_native_hook_cache(receipt_path, receipt)
        require_checkout_commit(info['sourceCommit'], runner.command, 'checkout-commit-after-check')
        if info['materials']['status'] == 'PASS':
            verify_material_binding(root, out, info['materials'])
    return {'status': 'PASS', 'buildStatus': 'PASS', 'materialsStatus': info['materials']['status'], 'run': info['runIdentity']}


def material_argv(root, out, info, options, command):
    app, cli = product_paths(out);evidence = out/'evidence'
    return [sys.executable, root/'tool/release_materials.py', command, '--repo', root,
            '--flutter', info['toolchain']['flutterPath'], '--app', app, '--cli', cli,
            '--output', bound_material_output(root, out, options['output']),
            '--downloads', options['downloads'], '--probe', options['probe'],
            '--sdk-source-workspace', options['sdkSourceWorkspace'],
            '--build-inputs', evidence/'compilation-input-hashes.json',
            '--candidate-hashes', evidence/'candidate-checksums.txt', '--build-receipt', evidence/'build-receipt.json']


def material_result(output):
    """Read the final JSON object if an SDK subprocess emitted stdout progress."""
    start = output.rfind('\n{')
    return json.loads(output[start+1:] if start >= 0 else output)


@contextmanager
def verification_runner(root, out, label, env, timeout=3600, *, interrupted=None):
    # Verification ledgers cannot rewrite the immutable compilation receipt.
    signals = DeferredInterrupts() if interrupted is None else nullcontext(interrupted)
    with signals as pending:
        phase = out/'evidence'/(label+'-'+datetime.datetime.now().strftime('%Y%m%dT%H%M%S%f'))
        phase.mkdir()
        ledger = {'formatVersion': 1, 'status': 'RUNNING', 'steps': []}
        runner = Runner(root, phase, ledger, env, timeout, pending, physical_build=release_build_root(root))
        try:
            runner.save()
            raise_if_interrupted(pending)
            yield runner
            raise_if_interrupted(pending)
            ledger['status'] = 'PASS'
            runner.save()
            if interrupted is None:
                while not pending.seal_if_unchanged(0):
                    raise_if_interrupted(pending)
            else:
                raise_if_interrupted(pending)
        except BaseException as error:
            ledger.update(status='FAIL', error=failure_message(error))
            if pending:
                ledger['interruptSignal'] = int(pending[0])
            runner.save()
            raise


def strict_materials(root, out, info, options, command, label, timeout=3600, *, interrupted=None):
    destination = bound_material_output(root, out, options['output'])
    manifest_path = owned_path(destination/'materials-manifest.json', destination)
    require_material_caches(options, out)
    commit = info['sourceCommit']
    with verification_runner(root, out, 'materials-'+label, controlled_environment(), timeout,
                             interrupted=interrupted) as runner:
        require_checkout_commit(commit, runner.command, 'checkout-commit-before-materials')
        result = material_result(runner.command(command, material_argv(root, out, info, options, command)))
        if result['status'] != 'PASS' or result.get('openGates') or result.get('failures'):
            raise ValueError('Strict materials gate is not PASS: '+json.dumps(result))
        require_checkout_commit(commit, runner.command, 'checkout-commit-after-materials')
        manifest_data = owned_file(manifest_path, destination).read_bytes()
        manifest_sha = sha(manifest_data)
        require_equal(result.get('manifestSha256'), manifest_sha, 'material manifest subprocess result')
        manifest = json.loads(manifest_data)
        require_equal(commit, manifest['sourceCommit'], 'material manifest commit')
        embedded = manifest['products']['buildReceipt']
        evidence = owned_path(out/'evidence', out)
        receipt_data = owned_file(evidence/'build-receipt.json', evidence).read_bytes()
        receipt_sha = sha(receipt_data)
        require_equal(info['evidence']['build-receipt.json']['sha256'], receipt_sha, 'original build receipt')
        require_equal(receipt_sha, embedded['sha256'], 'material build receipt digest')
        receipt = json.loads(receipt_data)
        require_equal(commit, receipt['sourceCommit'], 'material build receipt commit')
        require_equal(receipt, embedded['value'], 'material build receipt contents')
        prebuild = owned_file(evidence/'prebuild-identities.json', evidence).read_bytes()
        require_equal(receipt['prebuildIdentitiesSha256'], sha(prebuild), 'material source evidence')
        require_equal(json.loads(prebuild)['source'], manifest.get('sourceInputHashes'), 'material source map')
        if manifest['openGates']:
            raise ValueError('Collected materials retain open gates')
        return runner.evidence/'logs'/(command+'.log'), manifest_sha


def require_material_caches(options, out):
    workspace = Path(options['sdkSourceWorkspace'])
    require_product_disjoint({'Download cache': Path(options['downloads']),
                              'SDK source workspace': workspace},
                             (*product_paths(out), out/NATIVE_HOOK_SNAPSHOT, Path(options['output'])))
    validate_probe_write_paths(workspace)


def material_destination(out, name):
    safe(name)
    destination = out/name
    if (len(Path(name).parts) != 1 or name.casefold() in (
            'evidence', 'cli', 'app-derived', 'build-info.json', 'build-info.json.tmp')
            or destination.is_symlink() or destination.exists() or destination.resolve() != destination):
        raise ValueError('Materials require a new dedicated directory in this run')
    return destination


def materials(args):
    root = ROOT.resolve()
    with checkout_lock(root):
        out = output_path(root, args.output, timeout=getattr(args, 'timeout', 3600))
        physical_build = release_build_root(root)
        index = owned_file(out/'build-info.json', out)
        info = read(index)
        if info['materials']['status'] == 'PASS':
            raise ValueError('Materials already accepted for this run; use check to reverify them')
        destination = material_destination(out, args.materials_name)
        options = {'output': str(root/release_relative_path(root, physical_build, destination)),
                   'downloads': str(args.downloads.resolve()),
                   'probe': str(args.probe.resolve()), 'sdkSourceWorkspace': str(args.sdk_source_workspace.resolve())}
        require_material_caches(options, out)
        check(args, locked=True)
        material_destination(out, args.materials_name)
        with DeferredInterrupts() as interrupted:
            info['materials'] = {'status': 'RUNNING', 'arguments': options}
            try:
                write(index, info)
                raise_if_interrupted(interrupted)
                collect_log, collected = strict_materials(root, out, info, options, 'collect', 'collect', args.timeout,
                                                          interrupted=interrupted)
                check_log, checked = strict_materials(root, out, info, options, 'check', 'strict', args.timeout,
                                                      interrupted=interrupted)
                require_equal(collected, checked, 'collected and checked material manifest')
                verify_evidence(root, out, info)
                raise_if_interrupted(interrupted)
                manifest = destination/'materials-manifest.json'
                # Check the delivered builder and instructions against the source.
                import tarfile
                source_archive_path = require_material_file(destination, 'source-materials/meshchan/meshchan-source.tar.gz')
                with tarfile.open(source_archive_path) as archive:
                    for name in RELEASE_ENTRY_SOURCE_FILES:
                        raise_if_interrupted(interrupted)
                        member = archive.extractfile(name)
                        if member is None or sha(member.read()) != digest(root/name):
                            raise ValueError('Corresponding source lacks current release input: '+name)
                raise_if_interrupted(interrupted)
                references = {p.name: ref(root, p) for p in (collect_log, collect_log.with_suffix('.stderr.log'),
                                                            check_log, check_log.with_suffix('.stderr.log'))}
                references[manifest.name] = {'path': release_relative_path(root, physical_build, manifest),
                                             'sha256': checked}
                accepted = {'status': 'PASS', 'arguments': options, 'references': references}
                verify_material_binding(root, out, accepted)
                info['materials'] = accepted
                write(index, info)
                while not interrupted.seal_if_unchanged(0):
                    raise_if_interrupted(interrupted)
            except BaseException as error:
                info['materials'] = {'status': 'FAIL', 'arguments': options, 'error': failure_message(error)}
                if interrupted:
                    info['materials']['interruptSignal'] = int(interrupted[0])
                write(index, info)
                raise
        return info['materials']


def command_timeout(value):
    seconds = float(value)
    if not math.isfinite(seconds) or seconds <= 0:
        raise argparse.ArgumentTypeError('command deadline must be a finite, positive number of seconds')
    return seconds


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    b = sub.add_parser('build');b.add_argument('--flutter', type=Path, default=Path('/opt/homebrew/share/flutter'))
    b.add_argument('--allow-dirty', action='store_true');b.add_argument('--expected-version');b.add_argument('--app-build', type=int)
    c = sub.add_parser('check')
    c.add_argument('--require-frozen', action='store_true',
                   help='Require a clean-source build with accepted strict materials for handoff')
    m = sub.add_parser('materials')
    validator = sub.add_parser('_validate-products')
    for p in (b, c, m, validator):
        p.add_argument('--output', type=Path, required=True)
    for p in (b, c, m):
        p.add_argument('--timeout', type=command_timeout, default=3600, help='Per-command deadline in seconds')
    m.add_argument('--downloads', type=Path, required=True);m.add_argument('--probe', type=Path, required=True)
    m.add_argument('--sdk-source-workspace', type=Path, required=True);m.add_argument('--materials-name', default='materials')
    args = parser.parse_args()
    try:
        if args.command == '_validate-products':
            root = ROOT.resolve()
            out = output_path(root, args.output)
            app, cli = (owned_path(path, out) for path in product_paths(out))
            path = owned_file(out/'evidence/build-receipt.json', out)
            receipt = read(path)
            hooks = verify_native_hook_cache(path, receipt)
            report = products(root, app, cli, identity(root), controlled_environment(), hook_cache=hooks,
                              path_audit=receipt['recipeVersion'] >= PRIVATE_PATH_AUDIT_RECIPE)
            print(json.dumps(report))
            return 0
        result = {'build': build, 'check': check, 'materials': materials}[args.command](args)
        if args.command == 'build':
            result = {k: result[k] for k in ('runIdentity', 'buildStatus', 'productChecksStatus', 'materials', 'compilationInputIdentity')}
        print(json.dumps(result, indent=2))
        return 0
    except (Exception, KeyboardInterrupt) as error:
        print('ERROR: '+failure_message(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
