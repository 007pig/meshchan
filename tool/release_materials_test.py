"""Distribution risks: graph edges, independent coverage, raw bytes and native binding."""
import copy
import json
from pathlib import Path
import struct
import subprocess
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from candidate_common import TARGET_VERSION, MEMBERS, production_closure
from release_materials import (Collector, FIRST_PARTY, compatible_hook, encoded, graph_scope,
                              compilation_inputs, compilation_record_errors, repository_source_hashes,
                              hook_dependencies_current, project_license_errors, sections,
                              serial_app_binding, sha, source_archive, verify_materials)
from release_materials import verify_build_receipt


class CompilationBindingTests(unittest.TestCase):
    def test_build_receipt_binds_snapshots_products_runner_and_actual_logs(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d);before = {'source.dart': 'a'*64}
            for name in ('compilation-input-hashes.json', 'inputs-after-cli.json', 'inputs-after-app.json'):
                (root/name).write_bytes(encoded(before))
            (root/'candidate-checksums.txt').write_bytes(b'candidate bytes')
            (root/'run_build.py').write_bytes(b'# contemporaneous runner\n')
            steps = []
            for name in ('cli-build', 'app-build'):
                log = root/(name+'.log');log.write_bytes(b'actual build output\n')
                steps.append({'name': name, 'exitCode': 0, 'log': log.name, 'logSha256': sha(log.read_bytes())})
            receipt = {'formatVersion': 1, 'status': 'PASS', 'inputsUnchangedAcrossBuilds': True,
                'compilationInputsSha256': sha((root/'compilation-input-hashes.json').read_bytes()),
                'candidateChecksumsSha256': sha((root/'candidate-checksums.txt').read_bytes()),
                'runnerSha256': sha((root/'run_build.py').read_bytes()),
                'app': 'Meshchan.app', 'cli': 'cli', 'steps': steps}
            path = root/'build-receipt.json';path.write_bytes(encoded(receipt))
            def check():
                return verify_build_receipt(root, path, root/'compilation-input-hashes.json',
                                            root/'candidate-checksums.txt', root/'Meshchan.app', root/'cli')
            self.assertEqual(check()[0], receipt)
            for name in ('inputs-after-app.json', 'run_build.py', 'app-build.log'):
                original = (root/name).read_bytes();(root/name).write_bytes(b'changed')
                with self.subTest(input=name), self.assertRaises((ValueError, json.JSONDecodeError)):
                    check()
                (root/name).write_bytes(original)
            for changes in ({'status': 'RUNNING'}, {'app': 'different.app'}, {'steps': []},
                            {'candidateChecksumsSha256': '0'*64}):
                path.write_bytes(encoded({**receipt, **changes}))
                with self.subTest(receipt=changes), self.assertRaises(ValueError):
                    check()

    def test_first_party_declarations_that_feed_notices_are_build_inputs(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d);members, _ = self.fixture(root)
            declarations = ('LICENSE', 'COPYRIGHT', 'apps/meshchan_app/NOTICE.txt')
            for name in declarations:
                (root/name).write_bytes(b'Original declaration\r\n')
            before = compilation_inputs(root, members)
            self.assertTrue(set(declarations) <= before.keys())
            (root/'LICENSE').write_bytes(b'Updated notice content\n')
            failures = compilation_record_errors(root, compilation_inputs(root, members), before)
            self.assertTrue(any('LICENSE' in error and 'changed' in error for error in failures))

    def fixture(self, root):
        members = {name: {'path': ('apps/' if name in ('meshchan_app', 'meshctl') else 'packages/')+name,
                          'spec': {}} for name in FIRST_PARTY}
        names = ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml']
        for name, member in members.items():
            names += [member['path']+'/pubspec.yaml', member['path']+'/lib/main.dart']
        names += ['apps/meshctl/bin/meshctl.dart',
                  'apps/meshchan_app/macos/Runner/Info.plist',
                  'apps/meshchan_app/macos/Runner.xcodeproj/project.pbxproj',
                  'apps/meshchan_app/macos/Flutter/Flutter-Release.xcconfig',
                  'apps/meshchan_app/macos/Flutter/GeneratedPluginRegistrant.swift',
                  'packages/meshchan_core/build.yaml',
                  'apps/meshchan_app/images/icon.png', 'apps/meshchan_app/fonts/body.ttf']
        members['meshchan_app']['spec']['flutter'] = {
            'assets': [{'path': 'images/'}], 'fonts': [{'fonts': [{'asset': 'fonts/body.ttf'}]}]}
        for name in names:
            path = root/name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(name.encode())
        return members, names

    def test_empty_partial_and_added_production_inputs_cannot_pass(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d);members, names = self.fixture(root)
            required = compilation_inputs(root, members)
            self.assertEqual(set(required), set(names))
            self.assertEqual(compilation_record_errors(root, required, dict(required)), [])
            self.assertIn('incomplete', compilation_record_errors(root, required, {})[0])
            for name in names:
                with self.subTest(omitted=name):
                    partial = dict(required);partial.pop(name)
                    self.assertIn(name, compilation_record_errors(root, required, partial)[0])
            extra = root/'apps/meshchan_app/macos/Runner/Added.swift';extra.write_bytes(b'new source')
            self.assertIn('Added.swift', compilation_record_errors(root, compilation_inputs(root, members), required)[0])
            changed = root/'packages/meshchan_core/lib/main.dart';changed.write_bytes(b'changed')
            self.assertTrue(any('missing/changed' in e for e in compilation_record_errors(root, required, required)))

    def test_generated_native_cache_and_tests_are_separate_from_compilation_inventory(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d);members, _ = self.fixture(root)
            before = compilation_inputs(root, members)
            for name in ('apps/meshchan_app/macos/Flutter/ephemeral/generated.xcconfig',
                         'apps/meshchan_app/macos/RunnerTests/Test.swift',
                         'apps/meshctl/test/cli_test.dart', 'docs/note.md'):
                path = root/name;path.parent.mkdir(parents=True, exist_ok=True);path.write_bytes(b'auxiliary')
            self.assertEqual(compilation_inputs(root, members), before)
            for record in ([], {'../outside': '0'*64}, {'pubspec.yaml': 'not a hash'}):
                self.assertTrue(compilation_record_errors(root, before, record))

    def test_nonignored_output_downloads_and_sdk_workspace_do_not_enter_source_snapshot(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            subprocess.run(['git', 'init', '-q', root], check=True)
            (root/'source.dart').write_bytes(b'product')
            subprocess.run(['git', '-C', root, 'add', 'source.dart'], check=True)
            destinations = [root/'dist/materials', root/'download cache', root/'sdk-source']
            before = repository_source_hashes(root, destinations)
            for folder in destinations:
                folder.mkdir(parents=True)
                (folder/'materials-manifest.json').write_bytes(b'generated')
                (folder/'license.txt').write_bytes(b'original notice')
            after = repository_source_hashes(root, destinations)
            self.assertEqual(before, after)
            out = destinations[0]
            (out/'source-snapshot.json').write_bytes(encoded(after))
            manifest = {'formatVersion': 1, 'sourceInputHashes': before, 'openGates': [],
                        'materials': {'source-snapshot.json': {'sha256': sha(encoded(after))}}}
            fresh = {**manifest, 'sourceInputHashes': repository_source_hashes(root, destinations)}
            self.assertEqual(verify_materials(manifest, fresh, out), [])
            # Excluding generated output must never conceal a tracked input.
            with self.assertRaisesRegex(ValueError, 'overlaps tracked source'):
                repository_source_hashes(root, [root/'source.dart'])
            (root/'source.dart').write_bytes(b'changed')
            fresh['sourceInputHashes'] = repository_source_hashes(root, destinations)
            self.assertIn('Independent input/coverage drift: sourceInputHashes', verify_materials(manifest, fresh, out))


class AppBindingTests(unittest.TestCase):
    def app(self, root, name, runner=b'runner', payload=b'dart code'):
        folder = root/name
        for path, data in {'Contents/MacOS/Meshchan': runner,
                           'Contents/Frameworks/App.framework/App': payload}.items():
            dest = folder/path;dest.parent.mkdir(parents=True, exist_ok=True);dest.write_bytes(data)
        return folder

    def test_binding_rejects_rebuilt_runner_and_changed_framework_with_same_runner(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d);app = self.app(root, 'original');prepared = self.app(root, 'prepared')
            report = {'appOriginalSha256': sha(b'runner'), 'appPreparedCopy': str(prepared)}
            # Runner section comparison is exercised independently by the Mach-O
            # tests; this fixture isolates candidate/payload correspondence.
            with patch('release_materials.sections', return_value={'arm64': {'text': 'same'}}):
                serial_app_binding(report, app)
                (app/'Contents/Frameworks/App.framework/App').write_bytes(b'new Dart code')
                with self.assertRaisesRegex(ValueError, 'payload'):
                    serial_app_binding(report, app)
                (app/'Contents/MacOS/Meshchan').write_bytes(b'rebuilt')
                with self.assertRaisesRegex(ValueError, 'original App binding changed'):
                    serial_app_binding(report, app)

    def test_attachment_rejects_new_candidate_before_vm_access_without_rewriting_report(self):
        from rebuild_release_serial import attach_vm
        with tempfile.TemporaryDirectory() as d:
            root = Path(d);app = self.app(root, 'new', runner=b'rebuilt')
            report = root/'probe.json';report.write_bytes(encoded({'appOriginalSha256': sha(b'original')}))
            original = report.read_bytes()
            args = SimpleNamespace(output=report, app=app)
            with patch('rebuild_release_serial.importlib.util.spec_from_file_location') as vm:
                with self.assertRaisesRegex(ValueError, 'original App binding changed'):
                    attach_vm(args)
                vm.assert_not_called()
            self.assertEqual(report.read_bytes(), original)

    def test_valid_attachment_preserves_original_binding_and_requires_observed_prepared_runner(self):
        import contextlib
        import io
        from rebuild_release_serial import attach_vm
        with tempfile.TemporaryDirectory() as d:
            root = Path(d);app = self.app(root, 'original');prepared = self.app(root, 'prepared')
            library = prepared/'Contents/Frameworks/libserialport_plus.framework/Versions/A/libserialport_plus'
            library.parent.mkdir(parents=True);library.write_bytes(b'modified library')
            evidence = root/'vm';(evidence/'Release').mkdir(parents=True)
            (evidence/'session.json').write_bytes(b'VM identity')
            (evidence/'Release/app.stderr').write_text('MESHCHAN_MODIFIED_SERIAL_EMPTY_LIST')
            (evidence/'Release/app.stdout').write_text('normal close')
            path = root/'probe.json';original = {'appOriginalSha256': sha(b'runner'), 'appPreparedCopy': str(prepared)}
            path.write_bytes(encoded(original))
            observed = {'sourceApp': str(prepared), 'executableSha256': sha(b'runner'),
                        'shutdown': {'resourcesReleased': True, 'workerExited': True, 'owner': 'released'},
                        'root': '/owned-vm-product'}
            remote = Mock(return_value=SimpleNamespace(stdout=sha(b'modified library')+'  library'))
            product = SimpleNamespace(state={'products': {'Release': observed}}, vm=SimpleNamespace(remote=remote))
            host = SimpleNamespace(Product=lambda *_: product)
            args = SimpleNamespace(output=path, app=app, vm_config=root/'config', attach_vm_evidence=evidence)
            loader = SimpleNamespace(loader=SimpleNamespace(exec_module=lambda _: None))
            with patch('rebuild_release_serial.importlib.util.spec_from_file_location', return_value=loader), \
                    patch('rebuild_release_serial.importlib.util.module_from_spec', return_value=host), \
                    patch('release_materials.sections', return_value={'arm64': {'text': 'same'}}), \
                    contextlib.redirect_stdout(io.StringIO()):
                attach_vm(args)
                self.assertEqual(json.loads(path.read_text())['appOriginalSha256'], original['appOriginalSha256'])
                before = path.read_bytes();observed['executableSha256'] = 'wrong'
                with self.assertRaisesRegex(ValueError, 'prepared App executable'):
                    attach_vm(args)
                self.assertEqual(path.read_bytes(), before)


class GraphTests(unittest.TestCase):
    def setUp(self):
        edges = {'meshchan_app': ['meshchan_core', 'flutter', 'app'],
                 'meshctl': ['meshcore_link', 'cli', 'libserialport_plus'],
                 'meshchan_core': ['shared', 'hooks'], 'meshcore_link': ['shared'],
                 'libserialport_plus': ['hooks', 'native_toolchain_c', 'code_assets'],
                 'hooks': ['helper_shared'], 'native_toolchain_c': ['helper_shared'],
                 'code_assets': [], 'helper_shared': [], 'shared': [], 'app': [],
                 'cli': [], 'flutter': [], 'dev': []}
        self.graph = {'root': 'workspace', 'packages': [
            {'name': n, 'version': '1', 'source': 'root' if n in FIRST_PARTY else 'hosted',
             'directDependencies': d, 'devDependencies': ['dev'] if n in FIRST_PARTY else []}
            for n, d in edges.items()]}
        self.members = {n: {'spec': {'version': '1'}} for n in FIRST_PARTY}
        self.lock = {'packages': {p['name']: {'version': '1', 'source': 'hosted'}
                                 for p in self.graph['packages'] if p['name'] not in FIRST_PARTY}}
        self.locations = {p['name']: Path('/tmp')/p['name'] for p in self.graph['packages']}

    def scope(self):
        return graph_scope(self.graph, self.lock, self.members, self.locations)

    def test_dual_roots_and_runtime_helper_shared_path(self):
        scope = self.scope()
        c = {p['name']: p for p in scope['components']}
        self.assertEqual(c['shared']['ownership'], 'shared')
        self.assertEqual(c['app']['products'], ['meshchan_app'])
        self.assertEqual(c['cli']['products'], ['meshctl'])
        self.assertEqual(c['native_toolchain_c']['role'], 'build-helper')
        # hooks is also reachable through a runtime edge; never globally prune it.
        self.assertEqual(c['hooks']['role'], 'declared-production')
        self.assertEqual(scope['devOnly'], ['dev'])
        self.assertEqual(set(scope['firstParty']), FIRST_PARTY)
        self.assertFalse(FIRST_PARTY & c.keys())

    def test_missing_root_dependency_and_duplicate_node_fail(self):
        for roots in (('unknown',), ()):
            with self.assertRaises(ValueError):
                production_closure(self.graph, roots)
        self.graph['packages'][0]['directDependencies'].append('missing')
        with self.assertRaisesRegex(ValueError, 'Missing'):
            self.scope()
        self.graph['packages'].append(self.graph['packages'][0])
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            self.scope()

    def test_lock_source_version_and_workspace_mismatch(self):
        for field, value in (('version', '2'), ('source', 'git')):
            with self.subTest(field=field):
                lock = copy.deepcopy(self.lock)
                self.lock['packages']['app'][field] = value
                with self.assertRaisesRegex(ValueError, 'version/source'):
                    self.scope()
                self.lock = lock
        self.members.pop('meshchan_core')
        with self.assertRaisesRegex(ValueError, 'four'):
            self.scope()

    def test_historical_defaults(self):
        self.assertEqual(TARGET_VERSION, '0.1.0-dev.3')
        self.assertEqual(len(MEMBERS), 3)
        self.assertNotIn('flutter', production_closure(self.graph)[1])


class MaterialsTests(unittest.TestCase):
    def test_contribution_policy_cannot_reference_missing_or_changed_documents(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root/'LICENSE').write_bytes((Path(__file__).resolve().parents[1]/'LICENSE').read_bytes())
            notice = b'Copyright (c) 2026 Meshchan Contributors\nSPDX-License-Identifier: GPL-3.0-only\n'
            (root/'COPYRIGHT').write_bytes(notice)
            documents = {'CLA.md': b'Contributor retains copyright; proprietary sublicensing to 007pig.\n',
                         'CONTRIBUTING.md': b'Explicit acceptance before merge.\n'}
            for name, content in documents.items():
                (root/name).write_bytes(content)
            decision = {'status': 'approved', 'licenseExpression': 'GPL-3.0-only',
                'authorization': '007pig confirmed GPL authority; no exceptions',
                'licenseSha256': sha((root/'LICENSE').read_bytes()),
                'copyrightNoticeSha256': sha(notice),
                'copyrightNotice': 'Copyright (c) 2026 Meshchan Contributors',
                'authorityOverAllFirstPartyContributions': True, 'exceptions': [],
                'contributionPolicy': {'agreement': 'CLA.md', 'guide': 'CONTRIBUTING.md',
                    'agreementSha256': sha(documents['CLA.md']),
                    'guideSha256': sha(documents['CONTRIBUTING.md'])}}
            self.assertEqual(project_license_errors(root, decision), [])
            for name, original in documents.items():
                with self.subTest(document=name):
                    (root/name).unlink()
                    self.assertIn(name, project_license_errors(root, decision)[0])
                    (root/name).write_bytes(b'changed policy')
                    self.assertIn(name, project_license_errors(root, decision)[0])
                    (root/name).write_bytes(original)
            self.assertEqual(project_license_errors(root, decision), [])

    def test_gpl_approval_requires_bound_attribution_and_authority(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root/'LICENSE').write_bytes((Path(__file__).resolve().parents[1]/'LICENSE').read_bytes())
            copyright = b'Copyright (c) 2026 Meshchan Contributors\nSPDX-License-Identifier: GPL-3.0-only\n'
            (root/'COPYRIGHT').write_bytes(copyright)
            decision = {'status': 'approved', 'licenseExpression': 'GPL-3.0-only',
                'authorization': '007pig confirmed all first-party contributions; no exceptions',
                'licenseSha256': sha((root/'LICENSE').read_bytes()),
                'copyrightNoticeSha256': sha(copyright),
                'copyrightNotice': 'Copyright (c) 2026 Meshchan Contributors',
                'authorityOverAllFirstPartyContributions': True, 'exceptions': []}
            self.assertEqual(project_license_errors(root, decision), [])
            for key, value in (('status', 'pending-maintainer'), ('authorization', None),
                               ('licenseExpression', 'MIT'),
                               ('authorityOverAllFirstPartyContributions', False), ('exceptions', ['unknown'])):
                bad = {**decision, key: value}
                self.assertTrue(project_license_errors(root, bad))
            (root/'COPYRIGHT').write_bytes(copyright.replace(b'2026', b'2027'))
            self.assertTrue(project_license_errors(root, decision))
            (root/'COPYRIGHT').write_bytes(copyright)
            (root/'LICENSE').write_bytes(b'changed')
            self.assertTrue(project_license_errors(root, decision))

    def test_corresponding_source_snapshot_is_stable_and_preserves_bytes(self):
        import io
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root/'LICENSE').write_bytes(b'GPL\r\n')
            (root/'source.dart').write_bytes(b'// original bytes\r\n')
            (root/'ignored-secret').write_bytes(b'not a selected input')
            first, hashes = source_archive(root, ['source.dart', 'LICENSE'])
            second, other = source_archive(root, ['LICENSE', 'source.dart'])
            self.assertEqual(first, second)
            self.assertEqual(hashes, other)
            with tarfile.open(fileobj=io.BytesIO(first), mode='r:gz') as tar:
                self.assertEqual(tar.getnames(), ['LICENSE', 'source.dart'])
                self.assertEqual(tar.extractfile('source.dart').read(), b'// original bytes\r\n')
            (root/'source.dart').write_bytes(b'changed')
            self.assertNotEqual(source_archive(root, ['LICENSE', 'source.dart'])[0], first)

    def test_independent_coverage_and_strict_open_gates(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d)
            required = ('licenses/app/LICENSE', 'licenses/native/COPYING',
                        'source-materials/src/config.h', 'source-materials/hook/build.dart',
                        'licenses/engine/LICENSE', 'licenses/fonts/LICENSE')
            items = {}
            for n in required:
                p = out/n; p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(b'Copyright\r\n\xff')
                items[n] = {'sha256': sha(p.read_bytes())}
            fresh = {'formatVersion': 1, 'materials': items, 'openGates': [], 'lockSha256': 'old',
                     'serialNative': {'upstreamTag': None}}
            self.assertEqual(verify_materials(fresh, fresh, out), [])
            for n in required:
                with self.subTest(n=n):
                    altered = copy.deepcopy(fresh); del altered['materials'][n]
                    self.assertTrue(verify_materials(altered, fresh, out))
                    p = out/n; original = p.read_bytes(); p.write_bytes(b'changed')
                    self.assertTrue(verify_materials(fresh, fresh, out)); p.write_bytes(original)
            stale = copy.deepcopy(fresh); stale['lockSha256'] = 'changed'
            self.assertTrue(verify_materials(fresh, stale, out))
            open_gate = copy.deepcopy(fresh); open_gate['openGates'] = ['Project license pending', 'Required material unverified']
            self.assertIn('Project license pending', verify_materials(open_gate, open_gate, out))
            self.assertTrue(verify_materials({'materials': {}}, fresh, out))
            self.assertEqual(encoded(fresh), encoded(copy.deepcopy(fresh)))

    def test_exact_archive_bytes_nested_source_and_tampered_cache(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); package = root/'cache'; package.mkdir()
            members = {'LICENSE': b'MIT\r\n\xff', 'src/libserialport/COPYING': b'LGPL\r\n',
                       'src/include/config.h': b'#define V 1\r\n', 'hook/build.dart': b'// hook\r\n',
                       'pubspec.yaml': b'name: libserialport_plus\n'}
            for name, value in members.items():
                path = package/name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(value)
            archive = root/'archive.tar.gz'
            with tarfile.open(archive, 'w:gz') as tar:
                for path in sorted(package.rglob('*')):
                    if path.is_file(): tar.add(path, arcname=str(path.relative_to(package)))
            args = SimpleNamespace()
            c = Collector(args, root/'out')
            entry = {'version': '1.0.5', 'description': {'url': 'https://pub.dev', 'sha256': sha(archive.read_bytes())}}
            with patch.object(c, 'fetch', return_value=archive):
                result = c.archive('libserialport_plus', entry, package)
            self.assertTrue(result['cacheMatchesArchive'])
            self.assertEqual((root/'out/licenses/libserialport_plus/LICENSE').read_bytes(), members['LICENSE'])
            self.assertIn('source-materials/libserialport_plus/src/include/config.h', c.files)
            self.assertIn('licenses/libserialport_plus/src/libserialport/COPYING', c.files)
            (package/'src/include/config.h').write_bytes(b'patched')
            c2 = Collector(args, root/'out2')
            with patch.object(c2, 'fetch', return_value=archive): c2.archive('libserialport_plus', entry, package)
            self.assertTrue(c2.blockers)
            # GPL product source preparation retains archives outside the old five-package list.
            c3 = Collector(args, root/'out3')
            c3.project = {'licenseExpression': 'GPL-3.0-only'}
            with patch.object(c3, 'fetch', return_value=archive):
                c3.archive('ordinary_dependency', entry, package)
            self.assertIn('source-materials/archives/archive.tar.gz', c3.files)


class NativeTests(unittest.TestCase):
    def test_stale_or_unbound_hook_dependencies_fail(self):
        with tempfile.TemporaryDirectory() as d:
            file = Path(d)/'source.c'; file.write_bytes(b'original')
            meta = Path(d)/'dependencies.json'
            self.assertFalse(hook_dependencies_current(meta))
            meta.write_text(json.dumps({'file_system': [{'path': str(file),
                'size': file.stat().st_size, 'last_modified': file.stat().st_mtime_ns//1000}]}))
            self.assertTrue(hook_dependencies_current(meta))
            file.write_bytes(b'modified source')
            self.assertFalse(hook_dependencies_current(meta))
            file.unlink()
            self.assertFalse(hook_dependencies_current(meta))

    def test_compatible_cross_product_and_reject_wrong_target(self):
        location = Path('/tmp/libserialport_plus')
        inp = {'package_name': 'libserialport_plus', 'package_root': str(location), 'user_defines': {},
               'config': {'linking_enabled': True, 'extensions': {'code_assets': {
                   'target_os': 'macos', 'target_architecture': 'arm64', 'macos': {'target_version': 13}}}}}
        out = {'status': 'success'}
        self.assertTrue(compatible_hook(inp, out, 'libserialport_plus', location, 'arm64', 13))
        for key, value in (('target_os', 'linux'), ('target_architecture', 'x64'), ('macos', {'target_version': 12})):
            bad = copy.deepcopy(inp); bad['config']['extensions']['code_assets'][key] = value
            self.assertFalse(compatible_hook(bad, out, 'libserialport_plus', location, 'arm64', 13))
        self.assertFalse(compatible_hook(inp, {'status': 'failure'}, 'libserialport_plus', location, 'arm64', 13))
        inp['user_defines'] = {'source': 'sqlcipher'}
        self.assertFalse(compatible_hook(inp, out, 'libserialport_plus', location, 'arm64', 13))

    def test_section_identity_survives_metadata_but_rejects_code_change(self):
        def macho(payload, metadata):
            data = bytearray(192+len(payload))
            struct.pack_into('<IIIIIIII', data, 0, 0xfeedfacf, 0x100000c, 0, 6, 1, 152, metadata, 0)
            struct.pack_into('<II', data, 32, 0x19, 152)
            struct.pack_into('<I', data, 32+64, 1)
            s = 32+72; data[s:s+6] = b'__text'; data[s+16:s+22] = b'__TEXT'
            struct.pack_into('<QI', data, s+40, len(payload), 192)
            data[192:] = payload
            return data
        with tempfile.TemporaryDirectory() as d:
            a, b = Path(d)/'raw', Path(d)/'bundled'
            a.write_bytes(macho(b'CODE', 0)); b.write_bytes(macho(b'CODE', 1))
            self.assertEqual(sections(a), sections(b))
            b.write_bytes(macho(b'EDIT', 1))
            self.assertNotEqual(sections(a), sections(b))


if __name__ == '__main__':
    unittest.main()
