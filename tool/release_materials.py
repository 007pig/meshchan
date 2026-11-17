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
from pathlib import Path, PurePosixPath
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from urllib.parse import unquote, urljoin, urlparse

from candidate_common import ROOT, digest, production_closure, versions

PRODUCTS = ('meshchan_app', 'meshctl')
FIRST_PARTY = {'meshchan_app', 'meshctl', 'meshchan_core', 'meshcore_link'}
NOTICE = re.compile(r'^(license|copying|notice|copyright)([._-].*)?$', re.I)


def run(argv, cwd=None):
    return subprocess.check_output([str(a) for a in argv], cwd=cwd, text=True)


def encoded(value):
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + '\n').encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def safe(name):
    p = PurePosixPath(name)
    if p.is_absolute() or '..' in p.parts or str(p) != name:
        raise ValueError('Unsafe material path: ' + name)
    return name


def repository_source_hashes(root, generated):
    """Exclude declared staging/cache trees in both collect and fresh check."""
    root = root.resolve()
    generated = [p.resolve() for p in generated if p is not None]
    tracked = run(['git', 'ls-files', '--cached', '-z'], root).split('\0')
    if any(p == root or p.is_relative_to(root/'.git') for p in generated):
        raise ValueError('Generated directories must not contain the repository or Git metadata')
    for name in filter(None, tracked):
        if any((root/name).is_relative_to(p) for p in generated):
            raise ValueError('Generated directory overlaps tracked source: '+name)
    names = run(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], root).split('\0')
    return {n: digest(root/n) for n in sorted(set(filter(None, names)))
            if n != 'docs/validation/phase-1e3-materials.md' and (root/n).is_file()
            and not any((root/n).is_relative_to(p) for p in generated)}


def compilation_inputs(root, members):
    """Derive product inputs from source layout/pubspecs, never a build record.

    SDK, hosted native hooks and generated build settings have separate identity
    checks. This inventory covers first-party source, generation configuration,
    declared assets and stable native project inputs for both macOS products.
    """
    if set(members) != FIRST_PARTY:
        raise ValueError('Compilation inventory requires four workspace members')
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

    # Flutter's license collector reads workspace/package-root declarations into
    # the actual NOTICES asset, so these bytes are also candidate build inputs.
    for declaration in root.iterdir():
        if declaration.is_file() and NOTICE.match(declaration.name):
            files.add(declaration)
    for name, member in sorted(members.items()):
        folder = root/safe(member['path'])
        files.add(folder/'pubspec.yaml')
        for declaration in folder.iterdir():
            if declaration.is_file() and NOTICE.match(declaration.name):
                files.add(declaration)
        add(folder/'lib')
        for subdir in ('bin', 'hook', 'macos'):
            if (folder/subdir).exists():
                add(folder/subdir, native=subdir == 'macos')
        for config in ('build.yaml', 'dart_defines.json', '.metadata'):
            if (folder/config).is_file():
                files.add(folder/config)
        flutter = member['spec'].get('flutter', {})
        assets = [v if isinstance(v, str) else v['path'] for v in flutter.get('assets', [])]
        assets += [font['asset'] for family in flutter.get('fonts', []) for font in family['fonts']]
        for asset in assets:
            add(folder/safe(asset.rstrip('/')))
        if name == 'meshchan_app':
            files.update(folder/p for p in ('lib/main.dart', 'macos/Runner/Info.plist',
                                           'macos/Runner.xcodeproj/project.pbxproj'))
        elif name == 'meshctl':
            files.add(folder/'bin/meshctl.dart')
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


def verify_build_receipt(root, path, inputs, checksums, app, cli):
    """Verify an optional contemporaneous build ledger and its local evidence."""
    receipt = json.loads(path.read_text())
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
        companion = path.parent/name
        if json.loads(companion.read_text()) != before:
            raise ValueError('Build input snapshot differs: '+name)
        companions[name] = companion
    script = path.parent/'run_build.py'
    if digest(script) != receipt.get('runnerSha256'):
        raise ValueError('Build ledger runner source changed')
    companions['run_build.py'] = script
    steps = receipt.get('steps', [])
    if not {'cli-build', 'app-build'} <= {s.get('name') for s in steps}:
        raise ValueError('Build receipt lacks actual App/CLI build steps')
    for step in steps:
        log = root/safe(step['log'])
        if step.get('exitCode') != 0 or digest(log) != step.get('logSha256'):
            raise ValueError('Build command failed or log changed: '+str(step.get('name')))
    return receipt, companions


def source_archive(folder, names):
    """Deterministic source snapshot; never traverses ignored build/cache trees."""
    data = io.BytesIO()
    hashes = {}
    with gzip.GzipFile(fileobj=data, mode='wb', filename='', mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode='w') as archive:
            for name in sorted(set(names)):
                safe(name)
                path = folder/name
                if path.is_symlink():
                    if not path.resolve().is_relative_to(folder.resolve()):
                        raise ValueError('External corresponding-source symlink: '+name)
                    target = str(path.readlink())
                    info = tarfile.TarInfo(name)
                    info.type, info.linkname, info.mode = tarfile.SYMTYPE, target, 0o777
                    archive.addfile(info)
                    hashes[name] = sha(encoded({'symlink': target}))
                    continue
                if not path.is_file():
                    raise ValueError('Unsupported corresponding-source input: '+name)
                content = path.read_bytes()
                info = tarfile.TarInfo(name)
                info.size = len(content)
                info.mode = 0o755 if path.stat().st_mode & 0o111 else 0o644
                archive.addfile(info, io.BytesIO(content))
                hashes[name] = sha(content)
    return data.getvalue(), hashes


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


def verify_materials(manifest, fresh, output):
    """Compare independently regenerated coverage and bytes, keeping open gates fatal."""
    failures = []
    if manifest.get('formatVersion') != 1 or not manifest.get('materials'):
        failures.append('Missing/unsupported material inventory')
    for name, item in manifest.get('materials', {}).items():
        path = output/safe(name)
        if not path.is_file() or digest(path) != item['sha256']:
            failures.append('Missing/changed material: '+name)
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


def hook_dependencies_current(metadata):
    if not metadata.is_file():
        return False
    deps = json.loads(metadata.read_text()).get('file_system', [])
    return bool(deps) and all(Path(d['path']).is_file() and Path(d['path']).stat().st_size == d['size']
        and abs(Path(d['path']).stat().st_mtime_ns//1000 - d['last_modified']) <= 1 for d in deps)


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


class Collector:
    def __init__(self, args, output, offline=False):
        self.args, self.output, self.offline = args, output, offline
        self.files, self.blockers = {}, []

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
        if not cache.exists():
            if self.offline:
                raise ValueError('Missing verified download: ' + str(cache))
            cache.parent.mkdir(parents=True, exist_ok=True)
            # curl reports HTTP failures and leaves the existing user caches untouched.
            temporary = cache.with_suffix(cache.suffix + '.partial')
            subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error',
                            '--retry', '2', url, '--output', str(temporary)], check=True)
            temporary.replace(cache)
        if expected and digest(cache) != expected:
            raise ValueError('Archive hash mismatch: ' + url)
        return cache

    def archive(self, name, entry, folder):
        url = entry['description']['url'].rstrip('/') + '/api/archives/' + name + '-' + entry['version'] + '.tar.gz'
        archive = self.fetch(url, name+'-'+entry['version']+'.tar.gz', entry['description']['sha256'])
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
        if mismatches:
            self.blockers.append('Modified/missing pub cache files in '+name+': '+', '.join(mismatches))
        notices = [p for p in sorted(originals) if NOTICE.match(PurePosixPath(p).name)]
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

    def collect(self):
        a, root, flutter = self.args, self.args.repo, self.args.flutter
        self.project = json.loads((root/'docs/releases/project-license-decision.json').read_text())
        dart = flutter / 'bin/cache/dart-sdk'
        inputs = json.loads(run([dart/'bin/dart', root/'tool/release_materials_inputs.dart', root], root))
        graph = json.loads(run([dart/'bin/dart', 'pub', 'deps', '--json'], root))
        config_path = root / '.dart_tool/package_config.json'
        config = json.loads(config_path.read_text())
        locations = {p['name']: Path(unquote(urlparse(urljoin(config_path.as_uri(), p['rootUri'])).path)).resolve()
                     for p in config['packages']}
        scope = graph_scope(graph, inputs['lock'], inputs['members'], locations)
        app_version = inputs['members']['meshchan_app']['spec']['version']
        product, build = app_version.rsplit('+', 1)
        versions(root, product, app_build=int(build))
        identity = json.loads((flutter/'bin/cache/flutter.version.json').read_text())
        if run(['git', 'rev-parse', 'HEAD'], flutter).strip() != identity['frameworkRevision']:
            raise ValueError('Flutter revision differs from cached identity')
        sdk = {'flutter': identity, 'dartVersion': (dart/'version').read_text().strip(),
               'dartRevision': (dart/'revision').read_text().strip(),
               'runtimeSha256': digest(dart/'bin/dartaotruntime'),
               'engineStamp': (flutter/'bin/cache/engine.stamp').read_text().strip()}
        source_hashes = repository_source_hashes(root, [a.output, a.downloads,
            getattr(a, 'sdk_source_workspace', None)])
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
        if run([a.cli/'bin/meshctl', '--version']).strip() != 'meshctl '+product:
            raise ValueError('CLI candidate version mismatch')
        # Bind candidate inputs to independently recorded build-time hashes.
        record = a.build_inputs
        required_inputs = compilation_inputs(root, inputs['members'])
        products['requiredCompilationInputs'] = required_inputs
        if record.exists():
            observed = json.loads(record.read_text())
            self.blockers.extend(compilation_record_errors(root, required_inputs, observed))
            products['inputRecord'] = {'sha256': digest(record), 'value': observed}
            self.copy(record, 'evidence/compilation-input-hashes.json', 'Independent candidate build record')
        else:
            self.blockers.append('Candidate compilation input record unavailable; rebuild/bind in 1E.4')
        sums = a.candidate_hashes
        if sums.is_file():
            expected_files = {(a.app/p).resolve() for p in ('Contents/Info.plist', 'Contents/MacOS/Meshchan',
                              'Contents/Frameworks/App.framework/App')} | {(a.cli/'bin/meshctl').resolve()}
            recorded = {}
            for line in sums.read_text().splitlines():
                value, name = line.split('  ', 1)
                path = (root/name).resolve()
                if not re.fullmatch('[a-f0-9]{64}', value) or path in recorded:
                    raise ValueError('Malformed candidate checksum record')
                recorded[path] = value
            if not expected_files <= recorded.keys() or any(not p.is_file() or digest(p) != h for p, h in recorded.items()):
                self.blockers.append('Candidate files differ from independent build checksum record')
            self.copy(sums, 'evidence/candidate-checksums.txt', 'Independent candidate build record')
        else:
            self.blockers.append('Independent candidate build checksums unavailable; bind in 1E.4')
        receipt_path = getattr(a, 'build_receipt', None)
        if receipt_path:
            try:
                receipt, companions = verify_build_receipt(root, receipt_path, record, sums, a.app, a.cli)
                products['buildReceipt'] = {'sha256': digest(receipt_path), 'value': receipt}
                self.copy(receipt_path, 'evidence/candidate-build/build-receipt.json',
                          'Contemporaneous candidate input/build/output ledger')
                for name, path in sorted(companions.items()):
                    self.copy(path, 'evidence/candidate-build/'+name, 'Original build input snapshots and runner source')
                # Raw local build logs stay private; their checked hashes and argv
                # are retained in the receipt instead of copying the environment.
            except (OSError, ValueError, KeyError) as error:
                self.blockers.append('Candidate build receipt verification: '+str(error))
        for component in scope['components']:
            name = component['name']
            folder = locations[name]
            if component['source'] == 'hosted':
                component['archive'] = self.archive(name, inputs['lock']['packages'][name], folder)
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
        font_stamp = (flutter/'bin/cache/material_fonts.stamp').read_text().strip()
        font_url = 'https://storage.googleapis.com/'+font_stamp
        font_archive = self.fetch(font_url, 'fonts-'+font_stamp.split('/')[-2]+'.zip')
        font_evidence = []
        for family in fonts:
            for font in family['fonts']:
                asset = font['asset']
                if family['family'] != 'MaterialIcons' or asset != 'fonts/MaterialIcons-Regular.otf':
                    self.blockers.append('Unreviewed font: '+asset)
                    continue
                source = flutter/'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
                license_path = source.parent/'MaterialIcons_LICENSE.txt'
                with zipfile.ZipFile(font_archive) as original_fonts:
                    for path in (source, license_path):
                        if original_fonts.read(path.name) != path.read_bytes():
                            raise ValueError('Installed font material differs from original SDK archive: '+path.name)
                self.copy(license_path, 'licenses/fonts/'+license_path.name, 'SDK material_fonts.stamp '+(flutter/'bin/cache/material_fonts.stamp').read_text().strip())
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
        gpl_source = self.gpl_sources(source_hashes, sdk) if project.get('licenseExpression') == 'GPL-3.0-only' else None
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
        return {'formatVersion': 1, 'sourceCommit': run(['git', 'rev-parse', 'HEAD'], root).strip(),
                'sourceInputHashes': source_hashes, 'productVersion': product, 'appBuild': build,
                'lockSha256': digest(root/'pubspec.lock'), 'graphSha256': sha(encoded(graph)),
                'packageConfigSha256': digest(config_path), 'sdk': sdk, 'scope': scope,
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

    def gpl_sources(self, source_hashes, sdk):
        root, flutter = self.args.repo, self.args.flutter
        names = [n for n in source_hashes if n in ('LICENSE', 'COPYRIGHT', 'README.md', 'CLA.md', 'CONTRIBUTING.md', 'pubspec.yaml',
            'pubspec.lock', 'analysis_options.yaml') or n.startswith(('apps/', 'packages/', 'tool/', '.github/'))
            or n in ('docs/development.md', 'docs/releases/phase-1e3-licenses.md',
                     'docs/releases/project-license-decision.json', 'docs/releases/phase-1e3-sdk-sources.md')]
        archive, hashes = source_archive(root, names)
        self.put('source-materials/meshchan/meshchan-source.tar.gz', archive,
                 'Actual repository input bytes, including authorized license', 'Repository source snapshot')
        framework_paths = ['packages/flutter', 'packages/flutter_localizations', 'packages/flutter_tools',
                           'packages/flutter_web_plugins', 'bin/internal', 'bin/flutter', 'bin/dart',
                           'DEPS', 'LICENSE', 'AUTHORS']
        framework_names = run(['git', 'ls-files', '--', *framework_paths], flutter).splitlines()
        if subprocess.run(['git', 'diff', '--quiet', 'HEAD', '--', *framework_paths], cwd=flutter).returncode:
            raise ValueError('Flutter framework/build source differs from its recorded revision')
        framework, framework_hashes = source_archive(flutter, framework_names)
        self.put('source-materials/flutter/framework-build-source.tar.gz', framework,
                 'Flutter '+sdk['flutter']['frameworkRevision'], 'Selected framework and build-source files')
        from release_sdk_sources import SPEC, verify
        workspace = getattr(self.args, 'sdk_source_workspace', None)
        missing, native = [], None
        try:
            if workspace is None:
                raise ValueError('GPL native SDK sources require --sdk-source-workspace; prepare with tool/release_sdk_sources.py')
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
        result = {}
        for product, bundle in zip(PRODUCTS, (self.args.app, self.args.cli)):
            result[product] = {}
            for package, stem in (('libserialport_plus', 'libserialport_plus'), ('sqlite3', 'sqlite3')):
                target = (bundle/f'Contents/Frameworks/{stem}.framework/{stem}' if product == 'meshchan_app'
                          else bundle/'lib'/('liblibserialport_plus.dylib' if package == 'libserialport_plus' else 'libsqlite3.dylib'))
                wanted = sections(target)
                matches = {cpu: [] for cpu in wanted}
                for output in sorted((self.args.repo/'.dart_tool/hooks_runner'/package).glob('*/output.json')):
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
                    if not hook_dependencies_current(deps_file):
                        continue
                    for asset in out.get('assets', []):
                        enc = asset.get('encoding', {})
                        original = Path(enc.get('file', ''))
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
    args.build_inputs = args.build_inputs or args.repo/'build/phase-1e2/compilation-input-hashes.json'
    args.candidate_hashes = args.candidate_hashes or args.repo/'build/phase-1e2/product-hashes.txt'
    for key in ('repo', 'flutter', 'app', 'cli', 'output', 'downloads', 'probe', 'build_inputs', 'candidate_hashes', 'sdk_source_workspace', 'build_receipt'):
        if getattr(args, key) is not None:
            setattr(args, key, getattr(args, key).resolve())
    try:
        if args.output == args.repo or args.output.is_relative_to(args.app) or args.output.is_relative_to(args.cli):
            raise ValueError('Output must not overwrite repository or products')
        if args.command == 'collect':
            if args.output.exists():
                raise ValueError('Preserve existing review materials; choose a new output directory')
            args.output.mkdir(parents=True)
            manifest = Collector(args, args.output).collect()
            (args.output/'materials-manifest.json').write_bytes(encoded(manifest))
            print(json.dumps({'status': 'REVIEW_REQUIRED' if manifest['openGates'] else 'PASS',
                              'manifestSha256': digest(args.output/'materials-manifest.json'),
                              'materials': len(manifest['materials']), 'openGates': manifest['openGates']}, indent=2))
        else:
            manifest = json.loads((args.output/'materials-manifest.json').read_text())
            # Recompute the expected coverage from independent graph, lock, SDK, hooks,
            # products and source files. Removing manifest entries cannot bypass checks.
            with tempfile.TemporaryDirectory(prefix='meshchan-material-check-') as temp:
                fresh = Collector(args, Path(temp), offline=True).collect()
            failures = verify_materials(manifest, fresh, args.output)
            print(json.dumps({'status': 'FAIL' if failures else 'PASS',
                              'integrityAndCoverage': 'FAIL' if any('material:' in f or 'drift:' in f for f in failures) else 'PASS',
                              'thirdPartyMaterials': 'FAIL' if any(f != 'Project license requires maintainer approval and root LICENSE' for f in failures) else 'PASS',
                              'failures': failures}, indent=2))
            return 1 if failures else 0
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, tarfile.TarError) as error:
        print('Materials error: '+str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
