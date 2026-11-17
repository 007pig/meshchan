#!/usr/bin/env python3
"""Prepare and verify the native SDK source supplement to release_materials.

DEPS is parsed as data, never executed. Original archives and Git object identities
are verified before running the original GN build definitions in an owned checkout.
This checks source/build-input coverage, not a bit-identical engine rebuild.
"""
import argparse
import ast
import base64
import hashlib
import importlib.machinery
import importlib.util
import json
from pathlib import Path, PurePosixPath
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
import zlib

SPEC = Path(__file__).with_suffix('.json')
DART = 'engine/src/flutter/third_party/dart'
FRAMEWORK_TARGET = '//flutter/shell/platform/darwin/macos:flutter_framework_dylib'
RUNTIME_TARGET = '//runtime/bin:dartaotruntime'


def encoded(value):
    return (json.dumps(value, sort_keys=True, indent=2) + '\n').encode()


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def safe(name):
    p = PurePosixPath(name)
    if p.is_absolute() or '..' in p.parts or str(p) != name or not name:
        raise ValueError('Unsafe SDK source path: ' + name)
    return name


def deps_data(text):
    """Accept only the literal DEPS subset used by these fixed revisions."""
    result = {}

    def value(node):
        if isinstance(node, ast.Constant):
            return node.value
        if isinstance(node, ast.Dict):
            return {value(k): value(v) for k, v in zip(node.keys, node.values)}
        if isinstance(node, (ast.List, ast.Tuple)):
            return [value(n) for n in node.elts]
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
            return value(node.left) + value(node.right)
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                and node.func.id == 'Var' and len(node.args) == 1 and not node.keywords):
            return result['vars'][value(node.args[0])]
        raise ValueError('Unsupported DEPS expression: ' + ast.dump(node))

    for node in ast.parse(text).body:
        if (isinstance(node, ast.Assign) and len(node.targets) == 1
                and isinstance(node.targets[0], ast.Name)
                and node.targets[0].id in ('vars', 'deps')):
            result[node.targets[0].id] = value(node.value)
    if not result.get('vars') or not result.get('deps'):
        raise ValueError('Missing DEPS vars/deps')
    return result


def git_hash(kind, data):
    return hashlib.sha1(kind.encode() + b' ' + str(len(data)).encode() + b'\0' + data).hexdigest()


def archive_inventory(path, gitlinks=None):
    """Reconstruct Git trees including archive-omitted gitlinks; keep raw bytes."""
    files, dirs = {}, {(): {}}
    with tarfile.open(path) as archive:
        for entry in archive:
            name = entry.name.removeprefix('./').rstrip('/')
            if not name or entry.isdir():
                continue
            safe(name)
            if name in files or not (entry.isfile() or entry.issym()):
                raise ValueError('Unsupported/duplicate source archive entry: ' + name)
            data = entry.linkname.encode() if entry.issym() else archive.extractfile(entry).read()
            mode = '120000' if entry.issym() else '100755' if entry.mode & 0o111 else '100644'
            parts = tuple(name.split('/'))
            for i in range(len(parts)):
                dirs.setdefault(parts[:i], {})
            dirs[parts[:-1]][parts[-1]] = (mode, git_hash('blob', data))
            files[name] = {'sha256': hashlib.sha256(data).hexdigest(), 'mode': mode}
    for name, revision in (gitlinks or {}).items():
        parts = tuple(safe(name).split('/'))
        if name in files or parts in dirs or len(revision) != 40:
            raise ValueError('Invalid omitted gitlink: ' + name)
        for i in range(len(parts)):
            dirs.setdefault(parts[:i], {})
        dirs[parts[:-1]][parts[-1]] = ('160000', revision)
    root = None
    for path in sorted(dirs, key=len, reverse=True):
        data = b''.join(mode.encode() + b' ' + name.encode() + b'\0' + bytes.fromhex(sha)
                        for name, (mode, sha) in sorted(dirs[path].items(),
                        key=lambda item: item[0] + ('/' if item[1][0] == '40000' else '')))
        tree = git_hash('tree', data)
        if path:
            dirs[path[:-1]][path[-1]] = ('40000', tree)
        else:
            root = tree
    if not files:
        raise ValueError('Empty source archive')
    return files, root


def command(argv, cwd=None):
    result = subprocess.run([str(v) for v in argv], cwd=cwd, capture_output=True, text=True)
    if result.returncode:
        raise ValueError('Source command failed: ' + shlex.join([str(v) for v in argv])
                         + '\n' + result.stdout + result.stderr)
    return result.stdout


def fetch(item, downloads, offline=False):
    path = downloads / safe(item['archive'])
    if not path.exists():
        if offline:
            raise ValueError('Missing SDK source material: ' + str(path))
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + '.partial')
        command(['curl', '-fLsS', '--retry', '3', '--max-time', '600', item['url'], '-o', temporary])
        if item.get('encoding') == 'base64':
            temporary.write_bytes(base64.b64decode(temporary.read_bytes()))
        temporary.replace(path)
    if digest(path) != item['sha256']:
        raise ValueError('SDK source hash mismatch: ' + str(path))
    return path


def load_upstream(path, name):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def source_identity(spec, flutter):
    identity = json.loads((flutter / 'bin/cache/flutter.version.json').read_text())
    for field in ('frameworkRevision', 'engineRevision', 'engineContentHash'):
        if identity[field] != spec[field]:
            raise ValueError('SDK source identity drift: ' + field)
    if (flutter / 'bin/cache/dart-sdk/revision').read_text().strip() != spec['dartRevision']:
        raise ValueError('SDK source identity drift: dartRevision')
    # The framework and engine commits are distinct; prove equality of this tree.
    trees = {r: command(['git', 'rev-parse', r + ':engine/src'], flutter).strip()
             for r in (spec['engineRevision'], spec['frameworkRevision'])}
    if set(trees.values()) != {spec['engineSourceTree']}:
        raise ValueError('Engine revision/source tree mismatch')
    return trees


def source_inputs(spec, workspace, flutter, prepare=False):
    """Verify all original bytes against reviewed pins and their DEPS identities."""
    downloads, checkout = workspace / 'downloads', workspace / 'checkout'
    if prepare:
        downloads.mkdir(parents=True, exist_ok=True)
        checkout.mkdir(parents=True, exist_ok=True)
    source_identity(spec, flutter)
    required_runtime_parts = {'libcxx', 'libcxxabi', 'libunwind', 'compiler-rt',
                              'cmake', 'runtimes', 'llvm/cmake', 'llvm/include', 'llvm/utils'}
    for product in ('app', 'cli'):
        parts = [i['subtree'] for i in spec['archives'] if i.get('toolRuntime') == product]
        if len(parts) != len(set(parts)) or set(parts) != required_runtime_parts:
            raise ValueError('Missing/duplicate LLVM runtime source/build inputs: ' + product)
    if {i['archive'] for i in spec['artifactInputs']} != {'flutter-dart-sdk.zip', 'engine-framework.zip'}:
        raise ValueError('Missing exact official SDK artifact correspondence inputs')
    for artifact in spec['artifactInputs']:
        path = fetch(artifact, downloads, offline=not prepare)
        with zipfile.ZipFile(path) as archive:
            for member, info in artifact['members'].items():
                data = archive.read(member)
                if (hashlib.sha256(data).hexdigest() != info['sha256']
                        or (flutter / safe(info['sdkPath'])).read_bytes() != data):
                    raise ValueError('SDK runtime differs from exact official artifact: ' + member)
    base = spec['engineArchive']
    original = downloads / base['archive']
    if prepare and not original.exists():
        with original.open('wb') as stream:
            subprocess.run(['git', 'archive', '--format=tar', spec['engineRevision'],
                            *base['paths']], cwd=flutter, stdout=stream, check=True)
    if digest(original) != base['sha256']:
        raise ValueError('Engine source archive mismatch')
    items = [(base, original)]
    for item in spec['archives']:
        path = fetch(item, downloads, offline=not prepare)
        items.append((item, path))
    originals = {}
    for item, path in sorted(items, key=lambda pair: (pair[0]['path'].count('/'), pair[0]['path'])):
        print('Verifying SDK source archive: ' + item['archive'], file=sys.stderr, flush=True)
        files, tree = archive_inventory(path, item.get('gitlinks'))
        if tree != item['gitTree']:
            raise ValueError('Source Git tree mismatch: ' + item['archive'])
        if prepare:
            target = checkout / item['path']
            target.mkdir(parents=True, exist_ok=True)
            with tarfile.open(path) as archive:
                archive.extractall(target, filter='data')
        for name, info in files.items():
            dest = name if item['path'] == '.' else item['path'] + '/' + name
            if dest in originals and originals[dest] != info:
                raise ValueError('Conflicting SDK source overlays: ' + dest)
            originals[dest] = info
    for item in spec['files']:
        path = fetch(item, downloads, offline=not prepare)
        if git_hash(item.get('gitKind', 'blob'), path.read_bytes()) != item['gitBlob']:
            raise ValueError('Dart source Git blob mismatch: ' + item['path'])
        dest = checkout / item['path']
        if prepare:
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(path.read_bytes())
        originals[item['path']] = {'sha256': item['sha256'], 'mode': '100644'}
    for package in spec['toolPackages']:
        selected = downloads / 'package-files'
        supplied = all((selected / info['path']).is_file() for info in package['files'].values())
        if supplied:
            members = {name: (selected / info['path']).read_bytes() for name, info in package['files'].items()}
        else:
            archive = fetch(package, downloads, offline=not prepare)
            with zipfile.ZipFile(archive) as content:
                members = {name: content.read(name) for name in package['files']}
        for name, info in package['files'].items():
            data = members[name]
            if hashlib.sha256(data).hexdigest() != info['sha256']:
                raise ValueError('Compiler build input mismatch: ' + name)
            dest = checkout / safe(info['path'])
            if prepare:
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(data)
            if not dest.is_file() or dest.read_bytes() != data:
                raise ValueError('Modified/missing compiler configuration: ' + info['path'])
            originals[info['path']] = {'sha256': info['sha256'], 'mode': '100644'}
        provenance = json.loads((checkout / package['files']['source_manifest.json']['path']).read_text())
        versions = [v['git_checkout']['revision'] for v in provenance['directories'].values()
                    if v.get('git_checkout', {}).get('repo_url', '').endswith('/llvm-project')]
        if versions != [spec['toolRuntimeRevisions'][package['product']]]:
            raise ValueError('Compiler package/source revision mismatch')
    # Archives above verify all supplied source/license bytes. Verify executable
    # build definitions before running GN; graph-selected code is checked below.
    # Avoid opening tens of thousands of unrelated upstream test fixtures.
    for name, info in originals.items():
        if not (name.endswith(('.gn', '.gni', '.py', '.sh', '.pl')) or info['mode'] == '100755'):
            continue
        path = checkout / name
        if info['mode'] == '120000':
            actual = hashlib.sha256(str(path.readlink()).encode()).hexdigest() if path.is_symlink() else None
        else:
            actual = digest(path) if path.is_file() and not path.is_symlink() else None
        if actual != info['sha256']:
            raise ValueError('Modified/missing prepared SDK source: ' + name)
        if info['mode'] in ('100644', '100755') and bool(path.stat().st_mode & 0o111) != (info['mode'] == '100755'):
            raise ValueError('Prepared SDK source executable mode differs: ' + name)
    engine_deps = deps_data((checkout / 'DEPS').read_text())
    dart_deps = deps_data((checkout / DART / 'DEPS').read_text())
    if engine_deps['vars']['dart_revision'] != spec['dartRevision']:
        raise ValueError('Engine DEPS/Dart source revision mismatch')
    if (engine_deps['vars']['clang_version'] != 'git_revision:' + spec['toolRuntimeRevisions']['app']
            or dart_deps['vars']['clang_version'] != 'git_revision:' + spec['toolRuntimeRevisions']['cli']):
        raise ValueError('Compiler runtime source identity differs from DEPS')
    for item in spec['archives']:
        if item.get('toolRuntime'):
            deps = engine_deps if item['toolRuntime'] == 'app' else dart_deps
            if deps['vars']['clang_version'] != 'git_revision:' + item['revision']:
                raise ValueError('LLVM runtime/compiler DEPS revision mismatch')
            continue
        if item.get('subtree'):
            if item['revision'] != spec['dartRevision']:
                raise ValueError('Dart subtree revision mismatch')
            continue
        deps, path = (dart_deps, 'sdk/' + item['path'][len(DART) + 1:]) if item.get('deps') == 'dart' else (engine_deps, item['path'])
        selected = deps['deps'].get(path)
        if isinstance(selected, dict):
            selected = selected.get('url')
        if selected != item['repository'] + '@' + item['revision']:
            raise ValueError('Source does not match pinned DEPS: ' + item['path'])
    return originals


def dart_git_metadata(checkout, spec):
    """Install the authentic commit object for upstream version scripts only."""
    content = (checkout / 'source-metadata/dart-commit.raw').read_bytes()
    revision = git_hash('commit', content)
    if revision != spec['dartRevision']:
        raise ValueError('Dart version metadata is not the exact source commit')
    folder = checkout / DART / '.git'
    if folder.exists():
        if command(['git', 'rev-parse', 'HEAD'], folder.parent).strip() != revision:
            raise ValueError('Unexpected Git metadata in owned Dart source checkout')
        return
    objects = folder / 'objects' / revision[:2]
    objects.mkdir(parents=True)
    (objects / revision[2:]).write_bytes(zlib.compress(b'commit ' + str(len(content)).encode() + b'\0' + content))
    (folder / 'refs/heads').mkdir(parents=True)
    (folder / 'refs/heads/source').write_text(revision + '\n')
    (folder / 'HEAD').write_text('ref: refs/heads/source\n')
    (folder / 'shallow').write_text(revision + '\n')
    (folder / 'config').write_text('[core]\n\trepositoryformatversion = 0\n\tbare = false\n')


def target_closure(graph, root):
    seen, pending = set(), [root]
    while pending:
        name = pending.pop()
        if name in seen:
            continue
        if name not in graph:
            raise ValueError('Missing native build target: ' + name)
        seen.add(name)
        pending.extend(graph[name].get('deps', []))
    if len(seen) < 2:
        raise ValueError('Empty native build dependency closure')
    return sorted(seen)


def graph_coverage(graph, root, root_prefix, originals, generated_files, exceptions):
    targets = target_closure(graph, root)
    outputs = {name: target for target in targets for name in graph[target].get('outputs', [])}
    inputs, generated, stale = {}, {}, {}
    for target in targets:
        for field in ('sources', 'inputs', 'public', 'script'):
            values = graph[target].get(field, [])
            for path in ([values] if isinstance(values, str) else values):
                if path == '*':
                    continue
                if not path.startswith('//'):
                    raise ValueError('External native source input: ' + path)
                name = root_prefix + path[2:]
                if name in originals:
                    inputs[name] = originals[name]['sha256']
                elif path in outputs:
                    generated[path] = outputs[path]
                elif name in generated_files:
                    inputs[name] = generated_files[name]
                elif name in exceptions and field in ('sources', 'public'):
                    stale[name] = exceptions[name]
                else:
                    raise ValueError('Uncovered native build input: ' + name)
    if not inputs:
        raise ValueError('Empty native source coverage')
    return {'root': root, 'targets': targets, 'inputHashes': dict(sorted(inputs.items())),
            'generatedInputs': dict(sorted(generated.items())), 'staleHeaderDeclarations': stale}


def normalized(value, checkout, alias=None):
    if isinstance(value, str):
        value = value.replace(str(checkout), '@CHECKOUT@')
        return value.replace(*alias) if alias else value
    if isinstance(value, list):
        return [normalized(v, checkout, alias) for v in value]
    if isinstance(value, dict):
        return {normalized(k, checkout, alias): normalized(v, checkout, alias) for k, v in value.items()}
    return value


def probe(spec, workspace, flutter, originals):
    checkout, evidence = workspace / 'checkout', workspace / 'evidence'
    evidence.mkdir(exist_ok=True)
    gn_zip = fetch(spec['gn'], workspace / 'downloads', offline=True)
    gn = workspace / 'bin/gn'
    if not gn.exists():
        gn.parent.mkdir(exist_ok=True)
        with zipfile.ZipFile(gn_zip) as archive:
            gn.write_bytes(archive.read('gn'))
        gn.chmod(0o755)
    if digest(gn) != spec['gn']['executableSha256']:
        raise ValueError('GN executable differs from pinned tool')
    engine, dart = checkout / 'engine/src', checkout / DART
    dart_git_metadata(checkout, spec)
    for relative, data in spec['generatedConfiguration'].items():
        path = checkout / safe(relative)
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists() and path.read_bytes() != data.encode():
            raise ValueError('Modified generated source configuration: ' + relative)
        path.write_bytes(data.encode())
    # These are bootstrap compiler tools, never runtime source or product files.
    for cpu in ('arm64', 'x64'):
        path = engine / ('flutter/prebuilts/macos-' + cpu + '/dart-sdk')
        path.parent.mkdir(parents=True, exist_ok=True)
        expected = flutter / 'bin/cache/dart-sdk'
        if path.is_symlink() and path.resolve() != expected.resolve():
            raise ValueError('Unexpected bootstrap SDK link')
        if not path.exists():
            path.symlink_to(expected, target_is_directory=True)
    for name in ('SDKs', 'Platforms'):
        (engine / 'flutter/prebuilts' / name).mkdir(exist_ok=True)
    upstream = load_upstream(engine / 'flutter/tools/gn', 'meshchan_engine_gn')
    upstream.setup_git_versions = lambda: dict(spec['gitVersionArgs'])
    sys.path.insert(0, str(dart / 'tools'))
    try:
        dart_gn = load_upstream(dart / 'tools/gn.py', 'meshchan_dart_gn')
        dart_gn.DART_ROOT = str(dart)
        options = dart_gn.parse_args(['gn.py', '--mode=release', '--arch=arm64', '--os=host', '--no-rbe'])
        dart_args = dart_gn.ToGnArgs(options, 'release', 'arm64', 'host', 'none', True, True)
    finally:
        sys.path.pop(0)
    configs = []
    for cpu in ('arm64', 'x64'):
        args = upstream.to_gn_args(upstream.parse_args(spec['engineArgv'] + ['--mac-cpu', cpu]))
        configs.append(('app-' + cpu, engine, FRAMEWORK_TARGET, args, upstream.to_command_line, 'engine/src/'))
    configs.append(('cli-arm64', dart, RUNTIME_TARGET, dart_args, dart_gn.ToCommandLine, DART + '/'))
    exceptions = verify_stale_headers(spec, checkout, originals)
    generated = {p: hashlib.sha256(v.encode()).hexdigest() for p, v in spec['generatedConfiguration'].items()}
    reports = {}
    for name, root, target, args, serialize, prefix in configs:
        (root / 'out').mkdir(exist_ok=True)
        # A fresh directory distinguishes GN write_file output from stale files.
        # Only this owned scratch output is removed; source/products are preserved.
        with tempfile.TemporaryDirectory(prefix='materials-' + name + '-', dir=root / 'out') as temporary:
            out = Path(temporary)
            norm = lambda value: normalized(value, checkout, (out.name, 'materials-' + name))
            common = ['--root=' + str(root), '--root-target=' + target, '--script-executable=' + sys.executable]
            argv = [gn, 'gen', out, *common, '--args=' + ' '.join(serialize(args))]
            log = command(argv)
            (evidence / (name + '-gn.log')).write_text(log)
            graph_text = command([gn, 'desc', out, '*', *common, '--format=json'])
            # GN can emit an upstream unused-argument warning before JSON.
            start = re.search(r'^\{\s*$', graph_text, re.M)
            if not start:
                raise ValueError('GN did not emit a build graph')
            graph = json.loads(graph_text[start.start():])
            coverage = graph_coverage(graph, target, prefix, originals, generated, exceptions)
            for relative, expected in coverage['inputHashes'].items():
                if digest(checkout / relative) != expected:
                    raise ValueError('Modified/missing native source input: ' + relative)
            build_inputs, gn_generated = {}, {}
            for p in shlex.split((out / 'build.ninja.d').read_text().split(': ', 1)[1]):
                path = (out / p).resolve()
                if not path.is_relative_to(checkout):
                    raise ValueError('External GN regeneration input: ' + str(path))
                relative = path.relative_to(checkout).as_posix()
                if path.is_relative_to(out):
                    # Fresh GN-generated text, with checkout/output path identity
                    # normalized separately from original material byte hashes.
                    gn_generated[relative] = hashlib.sha256(norm(path.read_text()).encode()).hexdigest()
                    continue
                expected = originals.get(relative, {}).get('sha256') or generated.get(relative)
                if not expected or digest(path) != expected:
                    raise ValueError('Uncovered GN build definition: ' + relative)
                build_inputs[relative] = expected
            coverage['buildDefinitionHashes'] = dict(sorted(build_inputs.items()))
            coverage['gnGeneratedDefinitionHashes'] = dict(sorted(gn_generated.items()))
            coverage['gnArgs'] = args
            coverage['graphSha256'] = hashlib.sha256(encoded(norm(graph))).hexdigest()
            (evidence / (name + '-graph.json')).write_bytes(encoded(norm(graph)))
            reports[name] = norm(coverage)
    report = {'formatVersion': 1, 'sourceSpecSha256': digest(SPEC),
              'engineRevision': spec['engineRevision'], 'engineSourceTree': spec['engineSourceTree'],
              'dartRevision': spec['dartRevision'], 'gnVersion': command([gn, '--version']).strip(),
              'targets': reports, 'scope': spec['scope'],
              'officialArtifactInputs': spec['artifactInputs'],
              'toolRuntimeRevisions': spec['toolRuntimeRevisions'],
              'verification': 'Original source archives, DEPS pins, Git objects and native GN input closure; no engine/runtime compilation or bit-identical rebuild claimed'}
    if SPEC.read_bytes() != encoded(spec):
        raise ValueError('SDK source rules changed during verification or are not canonically encoded')
    (evidence / 'sdk-source-report.json').write_bytes(encoded(report))
    return report


def verify_stale_headers(spec, checkout, originals):
    """Narrow, revision-bound upstream metadata defects, never missing code."""
    exceptions, includes = {}, set()
    prefixes = tuple(spec.get('staleHeaderScanRoots', ()))
    if spec['staleHeaders'] and not prefixes:
        raise ValueError('Stale headers require explicit source include scan roots')
    for name in originals:
        if name.startswith(prefixes) and name.endswith(('.cc', '.cpp', '.c', '.h', '.hpp', '.mm')):
            includes.update(re.findall(r'^\s*#\s*include\s*[<"]([^>"\n]+)',
                                       (checkout / name).read_text(errors='replace'), re.M))
    for entry in spec['staleHeaders']:
        missing, replacement = entry['path'], entry['replacement']
        if (checkout / missing).exists() or missing in originals or replacement not in originals:
            raise ValueError('Stale-header exception no longer applies: ' + missing)
        if not missing.endswith(('.h', '.hpp')) or not entry['reason']:
            raise ValueError('Only reviewed unused header declarations may be excluded')
        if entry['obsoleteInclude'] in includes:
            raise ValueError('Obsolete header is still a compiler include: ' + missing)
        declaration = checkout / entry['declaration']
        if entry['declaration'] not in originals or entry['literal'] not in declaration.read_text():
            raise ValueError('Stale header declaration changed: ' + missing)
        for path in entry['includeUsers']:
            if path not in originals or entry['replacementInclude'] not in (checkout / path).read_text():
                raise ValueError('Actual replacement header include changed: ' + path)
        exceptions[missing] = entry
    return exceptions


def restore_materials(materials, workspace):
    """Restore original sources offline; compiler/GN executables remain tools."""
    source = materials / 'source-materials/sdk'
    if (source / 'source-inputs.json').read_bytes() != SPEC.read_bytes():
        raise ValueError('Delivered SDK source rules differ from the reviewed specification')
    dest = workspace / 'downloads'
    dest.mkdir(parents=True, exist_ok=True)
    for path in sorted((source / 'archives').iterdir()):
        if not path.is_file() or path.is_symlink():
            raise ValueError('Invalid delivered SDK source archive')
        target = dest / path.name
        if target.exists() and digest(target) != digest(path):
            raise ValueError('Conflicting restored SDK source input')
        if not target.exists():
            shutil.copyfile(path, target)
    spec = json.loads(SPEC.read_text())
    for package in spec['toolPackages']:
        for info in package['files'].values():
            path = source / safe(info['path'])
            if digest(path) != info['sha256']:
                raise ValueError('Delivered compiler configuration hash mismatch')
            target = dest / 'package-files' / info['path']
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)


def configure_build(spec, workspace, report, targets):
    """Install pinned unmodified compiler tools only into the owned checkout."""
    checkout = workspace / 'checkout'
    sdk = command(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path']).strip()
    platform = command(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-platform-path']).strip()
    developer = command(['/usr/bin/xcode-select', '-p']).strip()
    result = {}
    for name in targets:
        product = 'app' if name.startswith('app-') else 'cli'
        package = next(p for p in spec['toolPackages'] if p['product'] == product)
        archive = fetch(package, workspace / 'downloads')
        root = checkout / ('engine/src' if product == 'app' else DART)
        compiler = root / ('flutter/buildtools/mac-arm64/clang' if product == 'app' else 'buildtools/mac-arm64/clang')
        compiler.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive) as content:
            for member in content.namelist():
                safe(member.rstrip('/'))
        command(['/usr/bin/unzip', '-qo', archive, '-d', compiler])
        args = json.loads(json.dumps(report['targets'][name]['gnArgs']).replace('@CHECKOUT@', str(checkout)))
        if product == 'app':
            args.update(mac_sdk_path=sdk, mac_platform_path=platform,
                        mac_host_toolchain_path=developer + '/Toolchains/XcodeDefault.xctoolchain')
        values = [k + '=' + json.dumps(v).lower() if isinstance(v, bool)
                  else k + '=' + json.dumps(v) for k, v in args.items()]
        out = root / 'out' / ('rebuild-' + name)
        target = FRAMEWORK_TARGET if product == 'app' else RUNTIME_TARGET
        command([workspace / 'bin/gn', 'gen', out, '--root=' + str(root),
                 '--root-target=' + target, '--script-executable=' + sys.executable,
                 '--args=' + ' '.join(values)])
        ninja_target = target[2:] if product == 'app' else 'dartaotruntime'
        result[name] = {'output': str(out), 'ninjaArgv': ['ninja', '-C', str(out), ninja_target],
                        'compilerArchiveSha256': package['sha256'], 'macosSdk': sdk}
    (workspace / 'evidence/build-configuration.json').write_bytes(encoded(result))
    return result


def verify(workspace, flutter, prepare=False, materials=None):
    spec = json.loads(SPEC.read_text())
    if prepare and (workspace / 'checkout').exists():
        raise ValueError('Preserve existing source kit; choose a new workspace')
    if materials:
        if not prepare:
            raise ValueError('--materials applies only to prepare')
        restore_materials(materials, workspace)
    originals = source_inputs(spec, workspace, flutter, prepare)
    if prepare:
        fetch(spec['gn'], workspace / 'downloads')
    return probe(spec, workspace, flutter, originals)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('prepare', 'check', 'configure-build'))
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--flutter', type=Path, required=True)
    parser.add_argument('--materials', type=Path, help='Restore original sources from an existing collected materials directory')
    parser.add_argument('--target', action='append', choices=('app-arm64', 'app-x64', 'cli-arm64'),
                        help='Native target for configure-build; may be repeated')
    args = parser.parse_args()
    try:
        result = verify(args.workspace.resolve(), args.flutter.resolve(), args.command == 'prepare',
                        args.materials.resolve() if args.materials else None)
        if args.command == 'configure-build':
            if not args.target:
                raise ValueError('configure-build requires at least one --target')
            print(json.dumps(configure_build(json.loads(SPEC.read_text()), args.workspace.resolve(), result,
                                             sorted(set(args.target))), indent=2))
            return 0
        print(json.dumps({'status': 'PASS', 'sourceSpecSha256': result['sourceSpecSha256'],
                          'targets': {k: {'targets': len(v['targets']), 'inputs': len(v['inputHashes']),
                                         'buildDefinitions': len(v['buildDefinitionHashes'])}
                                      for k, v in result['targets'].items()}}, indent=2))
        return 0
    except (OSError, ValueError, KeyError, tarfile.TarError, subprocess.CalledProcessError) as error:
        print('SDK source error: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
