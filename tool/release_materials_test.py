"""Distribution risks: graph edges, independent coverage, raw bytes and native binding."""
import copy
import contextlib
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
import zipfile
from unittest.mock import Mock, patch

from candidate_common import TARGET_VERSION, MEMBERS, production_closure
from release_materials import (Collector, FIRST_PARTY, FRAMEWORK_SHADERS, HOOK_CACHE, MATERIAL_ICONS_FONT, SHADER_INCLUDE_DIR,
                              flutter_package_notice_paths, flutter_shader_includes,
                              compatible_hook, compiler_hosted_inputs, encoded, graph_scope, hosted_notice_identity,
                              compilation_inputs, compilation_record_errors, repository_source_hashes, repository_source_metadata,
                              hook_dependencies_current, project_license_errors, sections,
                              product_inventory, serial_app_binding, sha, source_archive, verify_materials)
from release_materials import (flutter_framework_archive, main, native_source_hashes, verified_material_icon_source,
                              verify_build_receipt, verify_build_source)


class DeliveryTests(unittest.TestCase):
    def test_strict_command_binds_the_manifest_bytes_it_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root/'materials'
            output.mkdir()
            payload = output/'LICENSE'
            payload.write_bytes(b'license fixture')
            manifest_path = output/'materials-manifest.json'
            manifest = {'formatVersion': 1, 'materials': {'LICENSE': {'sha256': sha(payload.read_bytes())}},
                        'openGates': []}
            manifest_bytes = encoded(manifest)
            args = ['release_materials.py', 'check', '--repo', str(root), '--output', str(output),
                    '--app', str(root/'App.app'), '--cli', str(root/'cli'), '--flutter', str(root/'flutter'),
                    '--downloads', str(root/'downloads')]
            for changed in (True, False):
                with self.subTest(changed=changed):
                    manifest_path.write_bytes(manifest_bytes)

                    def collect():
                        if changed:
                            manifest_path.write_bytes(manifest_bytes+b'\n')
                        return manifest

                    with (patch('sys.argv', args), patch.object(Collector, 'collect', side_effect=collect),
                          contextlib.redirect_stdout(io.StringIO()) as report):
                        self.assertEqual(main(), 1 if changed else 0)
                    result = json.loads(report.getvalue())
                    self.assertEqual(result['manifestSha256'], sha(manifest_bytes))
                    if changed:
                        self.assertIn('Material manifest changed during verification', result['failures'])

    def test_source_delivery_contains_runnable_vm_harness_and_excludes_local_config(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, materials, unpacked = (root/name for name in ('source', 'materials', 'unpacked'))
            skill = '.agents/skills/macos-vm-gui-testing/'
            host = 'apps/meshchan_app/tool/macos_vm/host.py'
            files = (host, 'docs/macos-vm-gui-testing.md', *(skill+name for name in (
                'SKILL.md', 'config.example.json', 'scripts/vm.py', 'scripts/guest.sh', 'scripts/stop-guest.sh',
                'scripts/askpass.sh', 'scripts/pinyin.sh', 'scripts/native/Info.plist', 'scripts/native/Probe.m',
                'scripts/native/KeyInput.m', 'scripts/native/PlaceWindow.m', 'scripts/native/IMEInspect.m',
            )))
            repo = Path(__file__).resolve().parents[1]
            for name in files:
                target = source/name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(repo/name, target)
            private_config = skill+'config.json'
            (source/private_config).write_text('local-only config fixture')
            snapshot = {name: sha((source/name).read_bytes()) for name in (*files, private_config)}
            collector = Collector(SimpleNamespace(repo=source, flutter=root/'unused'), materials)
            with (patch('release_materials.flutter_framework_archive', side_effect=ValueError('Stop before SDK source')),
                  self.assertRaisesRegex(ValueError, 'Stop before SDK source')):
                collector.gpl_sources(snapshot, {'flutter': {'frameworkRevision': 'a'*40}}, {})
            archive = materials/'source-materials/meshchan/meshchan-source.tar.gz'
            with tarfile.open(archive) as tar:
                self.assertTrue(set(files) <= set(tar.getnames()))
                self.assertNotIn(private_config, tar.getnames())
                self.assertTrue(tar.getmember(skill+'scripts/askpass.sh').mode & 0o111)
                tar.extractall(unpacked, filter='data')
            result = subprocess.run([sys.executable, unpacked/host, '--help'], cwd=unpacked, check=True,
                                    text=True, capture_output=True)
            self.assertIn('prepare', result.stdout)

    def test_corresponding_source_delivers_and_strictly_checks_recorded_root_notices(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            source, output = root/'checkout', root/'materials'
            source.mkdir()
            subprocess.run(['git', 'init', '-q', source], check=True)
            notices = b'Exact root notices\r\n'
            (source/'NOTICES').write_bytes(notices)
            (source/'LICENSE').write_bytes(b'Fallback license\n')
            subprocess.run(['git', '-c', 'core.autocrlf=false', 'add', 'NOTICES', 'LICENSE'], cwd=source, check=True)
            self.assertEqual(subprocess.check_output(['git', 'show', ':NOTICES'], cwd=source), notices)
            snapshot = repository_source_hashes(source, [])
            required = {'NOTICES': sha(notices)}
            collector = Collector(SimpleNamespace(repo=source, flutter=root/'unused'), output)
            incomplete_snapshot = {'LICENSE': snapshot['LICENSE']}
            with self.assertRaisesRegex(ValueError, 'archive lacks recorded compilation inputs: NOTICES'):
                collector.gpl_sources(incomplete_snapshot, {}, required)
            with self.assertRaisesRegex(ValueError, 'archive differs from recorded compilation input: NOTICES'):
                collector.gpl_sources(snapshot, {}, {'NOTICES': sha(b'different bytes')})
            with (patch('release_materials.flutter_framework_archive', side_effect=ValueError('Stop before SDK source')),
                  self.assertRaisesRegex(ValueError, 'Stop before SDK source')):
                collector.gpl_sources(snapshot, {'flutter': {'frameworkRevision': 'a'*40}}, required)
            name = 'source-materials/meshchan/meshchan-source.tar.gz'
            with tarfile.open(output/name) as archive:
                self.assertEqual(archive.extractfile('NOTICES').read(), notices)
            fresh = {'formatVersion': 1, 'materials': collector.files, 'openGates': []}
            self.assertEqual(verify_materials(fresh, fresh, output), [])
            incomplete, _ = source_archive(source, ['LICENSE'])
            (output/name).write_bytes(incomplete)
            altered = copy.deepcopy(fresh)
            altered['materials'][name].update(sha256=sha(incomplete), size=len(incomplete))
            self.assertIn('Independent input/coverage drift: materials', verify_materials(altered, fresh, output))

    def test_new_material_output_rejects_case_aliased_cache_before_collection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            (root/'CaseProbe').mkdir()
            if not (root/'caseprobe').is_dir():
                self.skipTest('Fixture volume has case-sensitive names')
            output = root/'materials'
            for flag, cache in (('--downloads', 'downloads'), ('--sdk-source-workspace', 'sdk-source')):
                with self.subTest(flag=flag):
                    alias = root/'Materials'/cache
                    args = ['release_materials.py', 'collect', '--repo', str(root), '--flutter', str(root/'flutter'),
                            '--app', str(root/'Meshchan.app'), '--cli', str(root/'cli'), '--output', str(output)]
                    args.extend((flag, str(alias)))
                    if flag != '--downloads':
                        args.extend(('--downloads', str(root/'external-downloads')))
                    self.assertFalse(output.exists() or alias.exists())
                    with (patch('sys.argv', args), patch.object(Collector, 'collect') as collect,
                          contextlib.redirect_stderr(io.StringIO()) as errors):
                        self.assertEqual(main(), 2)
                    collect.assert_not_called()
                    self.assertIn('overlaps the materials output', errors.getvalue())
                    self.assertFalse(alias.exists() or output.exists())


class DownloadTests(unittest.TestCase):
    def test_material_download_cache_rejects_a_fifo(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'tool').mkdir()
            (root/'tool/release_materials_sources.json').write_text('{}')
            os.mkfifo(root/'archive.tar')
            collector = Collector(SimpleNamespace(repo=root, downloads=root), root/'materials', offline=True)
            with self.assertRaisesRegex(ValueError, 'Source cache entry must be a regular file'):
                collector.fetch('https://example.invalid/source', 'archive.tar', 'a'*64)

    def test_new_download_ignores_old_partial_links_and_requires_pinned_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'tool').mkdir()
            (root/'tool/release_materials_sources.json').write_text('{}')
            downloads = root/'downloads'
            downloads.mkdir()
            protected = root/'candidate-file'
            protected.write_bytes(b'protected candidate bytes')
            collector = Collector(SimpleNamespace(repo=root, downloads=downloads), root/'materials')
            expected, url = b'locked archive bytes', 'https://example.invalid/archive'
            for alias_kind in ('symbolic', 'hard'):
                with self.subTest(alias=alias_kind):
                    cache = downloads/(alias_kind+'.tar.gz')
                    alias = cache.with_suffix('.gz.partial')
                    if alias_kind == 'symbolic':
                        alias.symlink_to(protected)
                    else:
                        os.link(protected, alias)

                    def download(argv, check):
                        self.assertEqual(argv[-3:-1], [url, '--output'])
                        self.assertTrue(check)
                        temporary = Path(argv[-1])
                        self.assertEqual(temporary.parent.parent, downloads)
                        self.assertEqual(temporary.parent.stat().st_mode & 0o777, 0o700)
                        self.assertNotEqual(temporary, alias)
                        temporary.write_bytes(response)

                    with patch('release_sdk_sources.subprocess.run', side_effect=download):
                        response = b'wrong bytes'
                        with self.assertRaisesRegex(ValueError, 'Archive hash mismatch'):
                            collector.fetch(url, cache.name, sha(expected))
                        self.assertFalse(cache.exists())
                        self.assertEqual(list(downloads.glob('.download-*')), [])
                        response = expected
                        self.assertEqual(collector.fetch(url, cache.name, sha(expected)).read_bytes(), expected)
                        self.assertEqual(list(downloads.glob('.download-*')), [])
                    self.assertEqual(protected.read_bytes(), b'protected candidate bytes')
                    self.assertTrue(alias.samefile(protected))


class CompilationBindingTests(unittest.TestCase):
    def test_framework_archive_uses_pinned_bytes_despite_checkout_or_export_transformations(self):
        with tempfile.TemporaryDirectory() as directory:
            flutter = Path(directory).resolve()
            file = flutter/'packages/flutter/example.ps1'
            file.parent.mkdir(parents=True)
            original = b'Original line\n'
            file.write_bytes(original)
            (flutter/'.gitattributes').write_text('*.ps1 text eol=crlf\n')
            subprocess.run(['git', 'init', '-q'], cwd=flutter, check=True)
            subprocess.run(['git', 'add', '.'], cwd=flutter, check=True, capture_output=True)
            subprocess.run(['git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test',
                            'commit', '-qm', 'Pinned Flutter source'], cwd=flutter, check=True)
            revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=flutter, text=True).strip()
            name = file.relative_to(flutter).as_posix()
            subprocess.run(['git', 'update-index', '--assume-unchanged', name], cwd=flutter, check=True)
            file.write_bytes(b'Changed checkout bytes\n')
            payload, hashes = flutter_framework_archive(flutter, revision)
            self.assertEqual(hashes, {name: sha(original)})
            with tarfile.open(fileobj=io.BytesIO(payload)) as archive:
                self.assertEqual(archive.extractfile(name).read(), original)

    def test_shader_include_rejects_directory_symlink_followed_by_parent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            shader = root/'shader.frag'
            shader.write_text('#include "alias/../header.glsl"\n')
            actual = root/'actual'
            (actual/'deeper').mkdir(parents=True)
            (root/'alias').symlink_to(actual/'deeper', target_is_directory=True)
            (root/'header.glsl').write_text('// Lexical path')
            (actual/'header.glsl').write_text('// Opened path')
            with self.assertRaisesRegex(ValueError, 'Ambiguous Flutter shader include traversal'):
                flutter_shader_includes(shader, root, root, None)
            shader.write_text('#include "alias/header.glsl"\n')
            header = actual/'deeper/header.glsl'
            header.write_text('// Resolved file')
            self.assertEqual(flutter_shader_includes(shader, root, root, None), {header})

    def test_current_receipt_requires_original_source_evidence_and_legacy_remains_supported(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            receipt_path = root/'build-receipt.json'
            evidence = root/'prebuild-identities.json'
            commit = 'a'*40
            source_path = root/'guide.md'
            source_path.write_bytes(b'original')
            source = {source_path.name: sha(b'original')}
            metadata = repository_source_metadata(root, source)
            for receipt in ({}, {'recipeVersion': 8}, {'recipeVersion': 21}):
                self.assertIsNone(verify_build_source(root, receipt_path, receipt, commit, source))
            data = encoded({'source': source, 'sourceMetadata': metadata})
            receipt = {'recipeVersion': 33, 'sourceCommit': commit, 'engineeringDirtyMode': True,
                       'prebuildIdentitiesSha256': sha(data)}
            with self.assertRaises(FileNotFoundError):
                verify_build_source(root, receipt_path, receipt, commit, source)
            evidence.write_bytes(data)
            self.assertEqual(verify_build_source(root, receipt_path, receipt, commit, source), metadata)
            with self.assertRaisesRegex(ValueError, 'Checkout commit differs'):
                verify_build_source(root, receipt_path, receipt, 'b'*40, source)
            with self.assertRaisesRegex(ValueError, 'Repository source map differs'):
                verify_build_source(root, receipt_path, receipt, commit, {})
            evidence.write_bytes(encoded({'source': {}}))
            with self.assertRaisesRegex(ValueError, 'Prebuild source evidence differs'):
                verify_build_source(root, receipt_path, receipt, commit, {})

    def test_materials_bind_workspace_package_config_to_the_build_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            receipt_path = root/'build-receipt.json'
            commit = 'a'*40
            expected = sha(b'original package config')
            data = encoded({'source': {}, 'sourceMetadata': {},
                            'configuration': {'.dart_tool/package_config.json': expected}})
            (root/'prebuild-identities.json').write_bytes(data)
            receipt = {'recipeVersion': 47, 'sourceCommit': commit, 'engineeringDirtyMode': True,
                       'prebuildIdentitiesSha256': sha(data)}
            self.assertEqual(verify_build_source(root, receipt_path, receipt, commit, {},
                                                 package_config_hash=expected), {})
            with self.assertRaisesRegex(ValueError, 'Workspace package configuration differs'):
                verify_build_source(root, receipt_path, receipt, commit, {},
                                    package_config_hash=sha(b'different package config'))

    def test_frozen_and_engineering_materials_validate_executability_and_file_type(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            subprocess.run(['git', 'init', '-q'], cwd=root, check=True)
            helper = root/'helper.sh'
            helper.write_bytes(b'#!/bin/sh\nexit 0\n')
            helper.chmod(0o755)
            subprocess.run(['git', 'add', '--chmod=+x', helper.name], cwd=root, check=True)
            subprocess.run(['git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test',
                            'commit', '-qm', 'Fixture'], cwd=root, check=True)
            commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
            source = repository_source_hashes(root, [])
            metadata = repository_source_metadata(root, source)
            receipt_path = root/'build-receipt.json'

            for dirty, recipe in ((False, 22), (False, 33), (True, 33)):
                with self.subTest(dirty=dirty, recipe=recipe):
                    prebuild = {'source': source}
                    if recipe >= 33:
                        prebuild['sourceMetadata'] = metadata
                    data = encoded(prebuild)
                    (root/'prebuild-identities.json').write_bytes(data)
                    receipt = {'sourceCommit': commit, 'engineeringDirtyMode': dirty,
                               'recipeVersion': recipe, 'prebuildIdentitiesSha256': sha(data)}
                    verified = verify_build_source(root, receipt_path, receipt, commit, source)
                    archive, _ = source_archive(root, source, expected_hashes=source, expected_metadata=verified)
                    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
                        self.assertEqual(tar.getmember(helper.name).mode, 0o755)

                    # The bytes stay the same when permissions or file type drift.
                    helper.chmod(0o644)
                    with self.assertRaisesRegex(ValueError, 'source metadata differs'):
                        verify_build_source(root, receipt_path, receipt, commit, source)
                    with self.assertRaisesRegex(ValueError, 'source metadata changed during archiving'):
                        source_archive(root, source, expected_hashes=source, expected_metadata=verified)
                    helper.chmod(0o755)
                    replacement = root/'same-bytes'
                    helper.rename(replacement)
                    helper.symlink_to(replacement.name)
                    with self.assertRaisesRegex(ValueError, 'source metadata differs'):
                        verify_build_source(root, receipt_path, receipt, commit, source)
                    helper.unlink()
                    replacement.rename(helper)

            data = encoded({'source': source})
            (root/'prebuild-identities.json').write_bytes(data)
            legacy_dirty = {**receipt, 'recipeVersion': 32, 'prebuildIdentitiesSha256': sha(data)}
            with self.assertRaisesRegex(ValueError, 'lacks source metadata evidence'):
                verify_build_source(root, receipt_path, legacy_dirty, commit, source)

    def test_standalone_collector_rejects_graph_and_source_drift_before_calculating_scope(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            flutter, app, cli = (root/name for name in ('flutter', 'Meshchan.app', 'cli'))
            args = SimpleNamespace(repo=root, flutter=flutter, app=app, cli=cli, output=root/'materials',
                                   downloads=root/'downloads', build_inputs=root/'inputs.json',
                                   candidate_hashes=root/'checksums.txt', build_receipt=root/'build-receipt.json')
            commit = 'a'*40
            source_name = 'docs/releases/phase-1e4-build.md'
            files = {'docs/releases/project-license-decision.json': b'{}',
                     '.dart_tool/package_config.json': encoded({'packages': [{'name': 'example', 'rootUri': root.as_uri()}]}),
                     'flutter/bin/cache/flutter.version.json': encoded({'frameworkRevision': commit}),
                     'flutter/bin/cache/dart-sdk/version': b'version', 'flutter/bin/cache/dart-sdk/revision': b'revision',
                     'flutter/bin/cache/dart-sdk/bin/dartaotruntime': b'runtime', 'flutter/bin/cache/engine.stamp': b'engine',
                     source_name: b'edited guide', 'unchanged.dart': b'compiled code',
                     'inputs.json': encoded({'unchanged.dart': sha(b'compiled code')}),
                     'Meshchan.app/Contents/Info.plist': plistlib.dumps({'MeshchanProductVersion': '0.1.0-rc.1',
                                                                      'CFBundleVersion': '8', 'CFBundleShortVersionString': '0.1.0'}),
                     'Meshchan.app/Contents/MacOS/Meshchan': b'runner',
                     'Meshchan.app/Contents/Frameworks/App.framework/App': b'app payload',
                     'cli/bin/meshctl': b'cli executable',
                     'build-receipt.json': b'{}'}
            for name, content in files.items():
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
            shadow_config = root/'tool/.dart_tool/package_config.json'
            shadow_config.parent.mkdir(parents=True)
            shadow_config.write_text('stale nested configuration')
            args.candidate_hashes.write_text(''.join(f'{sha(content)}  {name}\n' for name, content in files.items()
                                                     if name.startswith(('Meshchan.app/', 'cli/'))))
            source = {source_name: sha(b'original guide')}
            prebuild = encoded({'source': source})
            (root/'prebuild-identities.json').write_bytes(prebuild)
            graph_file = root/'resolved-graph.json'
            graph = {'root': 'meshchan_app', 'packages': [
                {'name': 'meshchan_app', 'version': '0.1.0-rc.1+8', 'source': 'root', 'directDependencies': ['example']},
                {'name': 'example', 'version': '1.0.0', 'source': 'hosted', 'directDependencies': []},
            ]}
            graph_file.write_text(json.dumps(graph))
            changed_graph = copy.deepcopy(graph)
            changed_graph['packages'][0]['directDependencies'] = []
            receipt = {'recipeVersion': 22, 'sourceCommit': commit, 'prebuildIdentitiesSha256': sha(prebuild),
                       'candidateChecksumsSha256': sha(args.candidate_hashes.read_bytes()),
                       'resolvedGraphSha256': sha(graph_file.read_bytes())}
            companions = {graph_file.name: graph_file}
            inputs = encoded({'lock': {}, 'members': {'meshchan_app': {'spec': {'version': '0.1.0-rc.1+8'}}}}).decode()
            compile_inputs = json.loads(args.build_inputs.read_text())
            config = root/'.dart_tool/package_config.json'
            current_receipt = {**receipt, 'recipeVersion': 52}
            bound_config = encoded({'configuration': {'.dart_tool/package_config.json': sha(config.read_bytes())}})
            (root/'prebuild-identities.json').write_bytes(bound_config)
            current_receipt['prebuildIdentitiesSha256'] = sha(bound_config)
            original_config = config.read_bytes()

            def verify_candidate(*_):
                config.write_bytes(encoded({'packages': []}))
                return current_receipt, companions

            try:
                with (patch('release_materials.run') as commands,
                      patch('release_materials.verify_build_receipt', side_effect=verify_candidate),
                      self.assertRaisesRegex(ValueError, 'Workspace package configuration differs')):
                    Collector(args, args.output, offline=True).collect()
                commands.assert_not_called()
            finally:
                config.write_bytes(original_config)
                (root/'prebuild-identities.json').write_bytes(prebuild)

            with (patch('release_materials.run') as commands,
                  patch('release_materials.verify_build_receipt', side_effect=ValueError('changed candidate bytes')),
                  self.assertRaisesRegex(ValueError, 'Candidate build receipt verification: changed candidate bytes')):
                Collector(args, args.output, offline=True).collect()
            commands.assert_not_called()

            cli_binary = cli/'bin/meshctl'
            cli_binary.write_bytes(b'bytes that fail the recorded checksum')
            try:
                with (patch('release_materials.run', side_effect=[inputs, encoded(graph).decode(), commit]) as commands,
                      patch('release_materials.versions'),
                      patch('release_materials.repository_source_hashes', return_value=source),
                      patch('release_materials.compilation_inputs', return_value=compile_inputs),
                      patch('release_materials.verify_build_receipt', return_value=(receipt, companions)),
                      patch.object(Collector, 'copy'),
                      self.assertRaisesRegex(ValueError, 'Candidate files differ from independent build checksum record')):
                    Collector(args, args.output, offline=True).collect()
                self.assertEqual(commands.call_count, 3)
            finally:
                cli_binary.write_bytes(files['cli/bin/meshctl'])

            for offline in (False, True):
                for live, error in ((changed_graph, 'Current dependency graph differs'),
                                    (graph, 'Repository source map differs')):
                    with (
                        self.subTest(offline=offline, error=error),
                        patch('release_materials.run', side_effect=[
                            inputs, encoded(live).decode(), commit, commit]) as commands,
                        patch('release_materials.graph_scope') as scope,
                        patch('release_materials.versions'),
                        patch('release_materials.repository_source_hashes', return_value={source_name: sha((root/source_name).read_bytes())}),
                        patch('release_materials.compilation_inputs', return_value=compile_inputs),
                        patch('release_materials.verify_build_receipt', return_value=(receipt, companions)),
                        patch.object(Collector, 'copy'),
                    ):
                        collector = Collector(args, args.output, offline=offline)
                        with self.assertRaisesRegex(ValueError, error):
                            collector.collect()
                        self.assertEqual(commands.call_args_list[0].args, (
                            [flutter/'bin/cache/dart-sdk/bin/dart', '--packages='+str(root/'.dart_tool/package_config.json'),
                             root/'tool/release_materials_inputs.dart', root], root))
                        scope.assert_not_called()
                        self.assertEqual(collector.blockers, [])
            self.assertEqual(shadow_config.read_text(), 'stale nested configuration')

    def test_source_archive_rejects_bytes_changed_after_the_source_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            guide = root/'guide.md'
            guide.write_bytes(b'original guide')
            snapshot = {guide.name: sha(guide.read_bytes())}
            source_archive(root, snapshot, expected_hashes=snapshot)
            guide.write_bytes(b'edited guide')
            with self.assertRaisesRegex(ValueError, 'Corresponding source changed during archiving: guide.md'):
                source_archive(root, snapshot, expected_hashes=snapshot)

    def test_source_snapshot_and_archive_reject_aliased_source_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory).resolve()
            root, outside = parent/'checkout', parent/'separate directory'
            source = root/'tool'
            source.mkdir(parents=True)
            (source/'helper.py').write_text('original helper')
            subprocess.run(['git', 'init', '-q'], cwd=root, check=True)
            subprocess.run(['git', 'add', 'tool/helper.py'], cwd=root, check=True)
            # The indexed helper remains visible even when the replacement
            # directory entry itself is ignored.
            (root/'.git/info/exclude').write_text('/tool\n')
            original = repository_source_hashes(root, [])
            source.rename(outside)
            source.symlink_to(outside, target_is_directory=True)
            self.assertEqual((outside/'helper.py').read_text(), 'original helper')
            with self.subTest(stage='snapshot'), self.assertRaisesRegex(ValueError, 'Aliased source directory'):
                repository_source_hashes(root, [])
            with self.subTest(stage='archive'), self.assertRaisesRegex(ValueError, 'Aliased source directory'):
                source_archive(root, original, expected_hashes=original)

    def test_collector_rejects_nonregular_flutter_metadata_before_starting_dart(self):
        for name in ('flutter.version.json', 'engine.stamp'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                flutter = root/'flutter'
                cache = flutter/'bin/cache'
                (cache/'dart-sdk').mkdir(parents=True)
                (cache/'dart-sdk/version').write_text('version')
                (cache/'dart-sdk/revision').write_text('revision')
                if name == 'engine.stamp':
                    (cache/'flutter.version.json').write_text('{}')
                os.mkfifo(cache/name)
                license_decision = root/'docs/releases/project-license-decision.json'
                license_decision.parent.mkdir(parents=True)
                license_decision.write_text('{}')
                output = root/'materials'
                collector = Collector(SimpleNamespace(repo=root, flutter=flutter), output)
                with (patch('release_materials.run') as command,
                      self.assertRaisesRegex(ValueError, 'Flutter SDK metadata must be a regular file')):
                    collector.collect()
                command.assert_not_called()

    def test_source_archive_preserves_internal_relative_links_and_rejects_escaping_links(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()/'checkout'
            (root/'tool').mkdir(parents=True)
            guide = root/'guide.md'
            guide.write_text('source guide')
            link = root/'tool/guide.md'
            link.symlink_to('../guide.md')
            names = ['guide.md', 'tool/guide.md']
            payload, _ = source_archive(root, names)
            with tarfile.open(fileobj=io.BytesIO(payload)) as archive:
                self.assertEqual(archive.getmember(names[1]).linkname, '../guide.md')
                self.assertEqual(archive.extractfile(names[1]).read(), b'source guide')
            for target in (str(guide), '../../checkout/guide.md'):
                with self.subTest(target=target):
                    link.unlink()
                    link.symlink_to(target)
                    self.assertTrue(link.is_file())
                    with self.assertRaisesRegex(ValueError, 'corresponding-source symlink'):
                        source_archive(root, names)

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
                stderr = log.with_suffix('.stderr.log');stderr.write_bytes(b'actual diagnostics\n')
                steps.append({'name': name, 'exitCode': 0, 'log': log.name, 'logSha256': sha(log.read_bytes()),
                              'stderrLog': stderr.name, 'stderrLogSha256': sha(stderr.read_bytes())})
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
            path_open = Path.open
            for name in ('build-receipt.json', 'compilation-input-hashes.json', 'candidate-checksums.txt',
                         'inputs-after-cli.json', 'run_build.py', 'app-build.log', 'app-build.stderr.log'):
                fifo = root/name
                original = fifo.read_bytes()
                fifo.unlink()
                os.mkfifo(fifo)

                def open_regular(target, *args, **kwargs):
                    if target == fifo:
                        self.fail('Receipt verification tried to open a FIFO: '+name)
                    return path_open(target, *args, **kwargs)

                with (self.subTest(fifo=name), patch.object(Path, 'open', open_regular),
                      self.assertRaisesRegex(ValueError, 'Expected a regular file: .*'+name)):
                    check()
                fifo.unlink()
                fifo.write_bytes(original)
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

            app, cli = root/'Meshchan.app', root/'cli'
            for product in (app, cli):
                product.mkdir()
                (product/'bin').mkdir()
                (product/'bin/payload').write_text('contents')
                (product/'alias').symlink_to('bin/payload')
            files = {'candidateInventoriesSha256': ('candidate-inventories.json',
                                                   {'app': product_inventory(app), 'cli': product_inventory(cli)}),
                     'resolvedGraphSha256': ('resolved-graph.json', {'graph': 'original graph'}),
                     'productChecksSha256': ('product-checks.json', {'status': 'PASS'})}
            versioned = {**receipt, 'recipeVersion': 16}
            for key, (name, value) in files.items():
                data = encoded(value)
                (root/name).write_bytes(data)
                versioned[key] = sha(data)
            path.write_bytes(encoded(versioned))
            self.assertEqual(check()[0], versioned)
            recipe_eight = {**versioned, 'recipeVersion': 8}
            del recipe_eight['productChecksSha256']
            path.write_bytes(encoded(recipe_eight))
            self.assertEqual(check()[0], recipe_eight)
            for key in ('candidateInventoriesSha256', 'resolvedGraphSha256'):
                with self.subTest(recipe_eight_missing_binding=key):
                    path.write_bytes(encoded({name: value for name, value in recipe_eight.items() if name != key}))
                    with self.assertRaisesRegex(ValueError, 'Versioned build receipt.*'+key):
                        check()
            for key, (name, value) in files.items():
                with self.subTest(missing_binding=key):
                    incomplete = dict(versioned)
                    del incomplete[key]
                    path.write_bytes(encoded(incomplete))
                    with self.assertRaisesRegex(ValueError, 'Versioned build receipt.*'+key):
                        check()
                with self.subTest(changed_file=name):
                    path.write_bytes(encoded(versioned))
                    (root/name).write_bytes(b'changed')
                    with self.assertRaisesRegex(ValueError, 'Build receipt binding differs for '+name):
                        check()
                    (root/name).write_bytes(encoded(value))
            (cli/'bin').chmod(0o700 if (cli/'bin').stat().st_mode & 0o077 else 0o755)
            with self.assertRaisesRegex(ValueError, 'Identity drift during actual product inventory'):
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

    def test_release_inventory_rejects_unverifiable_flutter_asset_transformers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            members, _ = self.fixture(root)
            asset = {'path': 'images/icon.png', 'transformers': []}
            members['meshchan_app']['spec']['flutter']['assets'] = [asset]
            self.assertIn('apps/meshchan_app/images/icon.png', compilation_inputs(root, members))
            asset['transformers'] = [{'package': 'fixture_transformer', 'args': ['build/local-config.json']}]
            with self.assertRaisesRegex(ValueError, 'cannot bind transformed Flutter asset: images/icon.png'):
                compilation_inputs(root, members)

    def test_builtin_flutter_shaders_bind_project_local_header_overrides(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory).resolve()
            root, flutter = parent/'checkout', parent/'sdk'
            root.mkdir()
            members, _ = self.fixture(root)
            for relative, header in zip(FRAMEWORK_SHADERS, ('runtime_effect.glsl', 'other.glsl')):
                shader = flutter/relative
                shader.parent.mkdir(parents=True)
                shader.write_text(f'#include <flutter/{header}>\n')
                sdk_header = flutter/SHADER_INCLUDE_DIR/'flutter'/header
                sdk_header.parent.mkdir(parents=True, exist_ok=True)
                sdk_header.write_text('// SDK shader header\n')
            subprocess.run(['git', 'init', '-q', root], check=True)
            (root/'.gitignore').write_text('/apps/meshchan_app/flutter/\n')
            base = compilation_inputs(root, members, flutter=flutter)
            overrides = {}
            for header in ('runtime_effect.glsl', 'other.glsl'):
                name = 'apps/meshchan_app/flutter/'+header
                override = root/name
                override.parent.mkdir(exist_ok=True)
                data = f'// Local shader header {header}\n'.encode()
                override.write_bytes(data)
                overrides[name] = sha(data)
            expanded = compilation_inputs(root, members, flutter=flutter)
            self.assertEqual(expanded, base | overrides)
            snapshot = repository_source_hashes(root, [])
            self.assertFalse(overrides.keys() & snapshot.keys())
            collector = Collector(SimpleNamespace(repo=root, flutter=flutter), parent/'materials')
            with self.assertRaisesRegex(ValueError, 'archive lacks recorded compilation inputs: .*runtime_effect.glsl'):
                collector.gpl_sources(snapshot, {}, expanded)

    def test_git_ignored_root_and_member_notices_are_compilation_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            members, _ = self.fixture(root)
            subprocess.run(['git', 'init', '-q', root], check=True)
            (root/'.gitignore').write_text('NOTICES\n')
            names = {'NOTICES', *(m['path']+'/NOTICES' for m in members.values())}
            for name in names:
                (root/name).write_bytes(b'Package notices\r\n')
            self.assertFalse(names & repository_source_hashes(root, []).keys())
            before = compilation_inputs(root, members)
            self.assertEqual({name: before[name] for name in names},
                             dict.fromkeys(names, sha(b'Package notices\r\n')))
            (root/'apps/meshchan_app/NOTICES').write_bytes(b'Changed package notices\n')
            after = compilation_inputs(root, members)
            self.assertEqual({name for name in names if before[name] != after[name]},
                             {'apps/meshchan_app/NOTICES'})

    def test_corresponding_source_rejects_missing_recorded_dart_assets_and_shaders(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            source, output = root/'checkout', root/'materials'
            source.mkdir()
            members, _ = self.fixture(source)
            subprocess.run(['git', 'init', '-q', source], check=True)
            members['meshchan_app']['spec']['flutter']['shaders'] = [
                'shaders/ignored.frag', {'path': 'shaders/mapped.frag', 'flavors': ['production']}]
            members['meshchan_app']['spec']['flutter']['assets'].append('art/icon.png')
            shader = 'apps/meshchan_app/shaders/ignored.frag'
            members['meshchan_app']['resolvedShaders'] = [
                {'path': str(source/path), 'packageQualified': False, 'transformed': False}
                for path in (shader, 'apps/meshchan_app/shaders/mapped.frag')]
            header = 'apps/meshchan_app/shaders/include/colors.glsl'
            nested_header = 'apps/meshchan_app/shaders/palette.inc'
            variant = 'apps/meshchan_app/art/2.0x/icon.png'
            license_path = 'apps/meshchan_app/build/generated credits.txt'
            members['meshchan_app']['spec']['flutter']['licenses'] = ['build/generated%20credits.txt']
            shared_header = 'shared.glsl'
            (source/shared_header).write_bytes(b'// shared header\n')
            subprocess.run(['git', 'add', '--', shared_header], cwd=source, check=True)
            base = source/'apps/meshchan_app/art/icon.png'
            base.parent.mkdir()
            base.write_bytes(b'base icon')
            files = ('apps/meshchan_app/lib/ignored.dart', 'apps/meshchan_app/images/ignored.png',
                     shader, 'apps/meshchan_app/shaders/mapped.frag', header, nested_header, variant, license_path)
            (source/'.gitignore').write_text('\n'.join('/'+name for name in files)+'\n')
            for name in files:
                path = source/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(name)
            (source/shader).write_text('#include "include/colors.glsl"\n#include "../../shared.glsl"\n')
            (source/header).write_text('/* Fixture header */\n# include <palette.inc>\n')
            required = compilation_inputs(source, members)
            snapshot = repository_source_hashes(source, [])
            self.assertEqual(compilation_record_errors(source, required, required), [])
            self.assertTrue(set(files) <= required.keys())
            self.assertFalse(set(files) & snapshot.keys())
            self.assertEqual(required[shared_header], snapshot[shared_header])
            self.assertEqual(required[variant], sha((source/variant).read_bytes()))
            self.assertEqual(required[nested_header], sha((source/nested_header).read_bytes()))
            (source/nested_header).write_text('changed nested include')
            self.assertNotEqual(required[nested_header], compilation_inputs(source, members)[nested_header])
            (source/nested_header).write_text(nested_header)
            collector = Collector(SimpleNamespace(repo=source, flutter=root/'unused'), output)
            archive_path = output/'source-materials/meshchan/meshchan-source.tar.gz'
            with self.assertRaisesRegex(ValueError, 'archive lacks recorded compilation inputs:') as failure:
                collector.gpl_sources(snapshot, {}, required)
            for name in files:
                self.assertIn(name, str(failure.exception))
            self.assertFalse(archive_path.exists())

            subprocess.run(['git', 'add', '-f', '--', *files], cwd=source, check=True)
            snapshot = repository_source_hashes(source, [])
            with (patch('release_materials.flutter_framework_archive', side_effect=ValueError('Stop before SDK source')),
                  self.assertRaisesRegex(ValueError, 'Stop before SDK source')):
                collector.gpl_sources(snapshot, {'flutter': {'frameworkRevision': 'a'*40}}, required)
            with tarfile.open(archive_path) as archive:
                self.assertTrue(required.keys() <= set(archive.getnames()))
                for name in files:
                    with archive.extractfile(name) as payload:
                        self.assertEqual(sha(payload.read()), required[name])

    def test_shader_parser_matches_flutter_declarations_and_workspace_package_fallback(self):
        repo = Path(__file__).resolve().parents[1]
        bundled = Path('/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart')
        dart = bundled if bundled.is_file() else shutil.which('dart')
        config = repo/'.dart_tool/package_config.json'
        if not dart or not config.is_file():
            self.skipTest('Requires Dart and the resolved repository YAML parser')
        with tempfile.TemporaryDirectory(prefix='shader paths ') as directory:
            parent = Path(directory).resolve()
            root, hosted = parent/'repo', parent/'hosted package'
            root.mkdir()
            members, _ = self.fixture(root)
            app = root/members['meshchan_app']['path']
            resources = members['meshchan_app']['spec']['flutter']
            resources['shaders'] = ['packages/fixture/shaders/qualified.frag',
                                    {'path': 'packages/fixture/shaders/local.frag'}]
            local = app/'packages/fixture/shaders/local.frag'
            local.parent.mkdir(parents=True)
            local.write_text('// Local overrides package lookup')
            for name, member in members.items():
                (root/member['path']/'pubspec.yaml').write_bytes(encoded({'name': name, **member['spec']}))
            (root/'pubspec.yaml').write_bytes(encoded({'workspace': [m['path'] for m in members.values()]}))
            (root/'pubspec.lock').write_bytes(encoded({'packages': {'fixture': {'source': 'hosted'}}}))
            (root/'.dart_tool').mkdir()
            (root/'.dart_tool/package_config.json').write_bytes(encoded({'packages': [
                {'name': 'fixture', 'rootUri': hosted.as_uri(), 'packageUri': 'lib/'}]}))
            (hosted/'lib/shaders').mkdir(parents=True)
            transformer = [{'package': 'asset_transformer'}]
            (hosted/'pubspec.yaml').write_bytes(encoded({'name': 'fixture', 'flutter': {
                'shaders': ['lib/shaders/plain%20name.frag', {'path': 'lib/shaders/plain%20name.frag'}],
                'assets': [{'path': 'packages/fixture/shaders/', 'transformers': transformer, 'platforms': ['macos']},
                           {'path': 'assets/inactive.png', 'transformers': transformer, 'platforms': ['android']}]}}))
            qualified, escaped, literal, shadowed = [
                hosted/'lib/shaders'/name for name in ('qualified.frag', 'plain name.frag', 'plain%20name.frag', 'local.frag')]
            for shader in (qualified, escaped, literal, shadowed):
                shader.write_text('// Hosted shader')
            command = [dart, '--packages='+str(config), repo/'tool/release_materials_inputs.dart', root]
            parsed = json.loads(subprocess.check_output(command))
            required = compilation_inputs(root, parsed['members'])
            self.assertEqual(required[local.relative_to(root).as_posix()], sha(local.read_bytes()))
            plan = json.loads(subprocess.check_output([*command, '--asset-plan']))
            paths = {Path(entry['path']) for entry in plan['shaders']}
            self.assertEqual(paths, {local, qualified, escaped, literal})
            self.assertEqual([Path(entry['path']) for entry in plan['transformedAssets']], [hosted/'lib/shaders'])

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
            (out/'license.txt').unlink()
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
    def test_material_icon_archive_must_match_the_build_time_font(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            flutter = root/'sdk'
            source = flutter/MATERIAL_ICONS_FONT
            source.parent.mkdir(parents=True)
            license_path = source.parent/'MaterialIcons_LICENSE.txt'
            source.write_bytes(b'pinned font')
            license_path.write_bytes(b'pinned license')
            archive = root/'fonts.zip'
            with zipfile.ZipFile(archive, 'w') as originals:
                originals.write(source, source.name)
                originals.write(license_path, license_path.name)
            self.assertEqual(verified_material_icon_source(flutter, archive, {str(source): sha(source.read_bytes())}),
                             (source, license_path))
            with self.assertRaisesRegex(ValueError, 'Original Material Icons font differs from the candidate build receipt'):
                verified_material_icon_source(flutter, archive, {str(source): sha(b'different build-time font')})

    def test_hosted_notice_accepts_cache_root_alias_but_rejects_package_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            package = root/'real cache/hosted/fixture'
            package.mkdir(parents=True)
            alias = root/'pub cache'
            alias.symlink_to(root/'real cache', target_is_directory=True)
            uri = (alias/'hosted/fixture').as_uri()
            (package/'LICENSE').write_bytes(b'Original license')
            spec = {'packageUri': 'lib/'}
            self.assertEqual(hosted_notice_identity(uri, spec, package),
                             {'path': 'LICENSE', 'sha256': sha(b'Original license')})
            (package/'NOTICES').symlink_to('LICENSE')
            with self.assertRaisesRegex(ValueError, 'Aliased or invalid material file'):
                hosted_notice_identity(uri, spec, package)
            (package/'src').symlink_to(package, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'Aliased or invalid material directory'):
                hosted_notice_identity(uri, {'packageUri': 'src/lib/'}, package)

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

    def test_material_verification_rejects_identical_bytes_behind_aliases(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            output = root/'materials'
            licenses = output/'licenses'
            licenses.mkdir(parents=True)
            name = 'licenses/LICENSE'
            payload = output/name
            payload.write_bytes(b'license')
            manifest = {'formatVersion': 1, 'materials': {name: {'sha256': sha(b'license')}}, 'openGates': []}
            self.assertEqual(verify_materials(manifest, manifest, output), [])
            external = root/'external'
            payload.rename(external)
            for alias in (lambda: payload.symlink_to(external), lambda: os.link(external, payload)):
                alias()
                self.assertEqual(verify_materials(manifest, manifest, output), ['Missing/changed material: '+name])
                payload.unlink()
            (root/'directory').mkdir()
            external.rename(root/'directory/LICENSE')
            licenses.rmdir()
            licenses.symlink_to(root/'directory', target_is_directory=True)
            self.assertEqual(verify_materials(manifest, manifest, output), [
                'Missing/changed material: '+name, 'Unlisted material: licenses'])

    def test_strict_recheck_rejects_unlisted_entries_with_matching_manifests(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            output = root/'materials'
            output.mkdir()
            (output/'LICENSE').write_bytes(b'license')
            manifest = {'formatVersion': 1, 'materials': {'LICENSE': {'sha256': sha(b'license')}}, 'openGates': []}
            (output/'materials-manifest.json').write_bytes(encoded(manifest))
            self.assertEqual(verify_materials(manifest, manifest, output), [])
            external = root/'private'
            external.mkdir()
            (external/'local-only.txt').write_text('local-only')
            (output/'evidence').mkdir()
            (output/'evidence/stale.log').write_text('stale')
            (output/'private').symlink_to(external, target_is_directory=True)
            os.mkfifo(output/'local.pipe')
            self.assertEqual(verify_materials(manifest, manifest, output), [
                'Unlisted material: evidence/stale.log', 'Unlisted material: local.pipe', 'Unlisted material: private'])

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

    def test_compiled_hosted_files_must_match_the_locked_archive_even_with_matching_cache(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            package, downloads = root/'pub-cache', root/'downloads'
            (package/'lib').mkdir(parents=True)
            downloads.mkdir()
            (root/'tool').mkdir()
            (root/'tool/release_materials_sources.json').write_text('{}')
            name = 'fixture_dependency'
            original = 'lib/archived.dart'
            local = 'lib/extra.dart'
            shader_header = 'lib/shaders/flutter/runtime_effect.glsl'
            image = 'assets/cache-only.png'
            originals = {'LICENSE': b'MIT', original: b'const archive = 1;'}
            for relative, data in originals.items():
                (package/relative).write_bytes(data)
            archive = downloads/(name+'-1.0.0.tar.gz')
            with tarfile.open(archive, 'w:gz') as tar:
                for relative in originals:
                    tar.add(package/relative, arcname=relative)
            entry = {'version': '1.0.0', 'description': {'url': 'https://pub.dev', 'sha256': sha(archive.read_bytes())}}
            (package/local).write_text('const extra = 1;')
            (package/shader_header).parent.mkdir(parents=True)
            (package/shader_header).write_text('Cache-only shader input')
            (package/image).parent.mkdir()
            (package/image).write_bytes(b'Cache-only hosted asset')
            args = SimpleNamespace(repo=root, downloads=downloads)
            report = {'hosted': {'app': {name: {original: sha(originals[original])}}, 'cli': {}}}
            for offline in (False, True):
                with self.subTest(offline=offline):
                    collector = Collector(args, root/f'good-{offline}', offline=offline)
                    collector.project = {'licenseExpression': 'GPL-3.0-only'}
                    compiler_files = compiler_hosted_inputs(report)[name]
                    self.assertTrue(collector.archive(name, entry, package,
                                                      compiler_files=compiler_files)['cacheMatchesArchive'])
                    self.assertEqual((collector.output/'source-materials/archives'/archive.name).read_bytes(),
                                     archive.read_bytes())
                    for relative, recorded_sha, error in (
                        (local, sha((package/local).read_bytes()), 'absent from its locked archive'),
                        (shader_header, sha((package/shader_header).read_bytes()), 'absent from its locked archive'),
                        (image, sha((package/image).read_bytes()), 'absent from its locked archive'),
                        (original, sha(b'previously compiled modification'), 'differs from its locked archive'),
                    ):
                        with self.subTest(relative=relative):
                            output = root/f'rejected-{offline}'
                            collector = Collector(args, output, offline=offline)
                            with self.assertRaisesRegex(ValueError, error):
                                collector.archive(name, entry, package, compiler_files={relative: recorded_sha})
                            self.assertFalse(output.exists())

    def test_selected_hosted_notice_must_match_archive_even_outside_product_graph(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            package, downloads = root/'cache', root/'downloads'
            package.mkdir()
            downloads.mkdir()
            (root/'tool').mkdir()
            (root/'tool/release_materials_sources.json').write_text('{}')
            name = 'fixture_dependency'
            license_file = package/'LICENSE'
            license_file.write_bytes(b'Original license')
            archive = downloads/(name+'-1.0.0.tar.gz')
            with tarfile.open(archive, 'w:gz') as tar:
                tar.add(license_file, arcname='./LICENSE')
            entry = {'version': '1.0.0', 'description': {'url': 'https://pub.dev', 'sha256': sha(archive.read_bytes())}}
            args = SimpleNamespace(repo=root, downloads=downloads)
            package_config = {'packageUri': 'lib/'}
            notice_paths = tuple(flutter_package_notice_paths(package.as_uri(), 'lib/', package))
            original = hosted_notice_identity(package.as_uri(), package_config, package)
            self.assertEqual(original, {'path': 'LICENSE', 'sha256': sha(b'Original license')})
            override = package/'NOTICES'
            override.write_bytes(b'Untracked notice')
            selected = hosted_notice_identity(package.as_uri(), package_config, package)
            self.assertEqual(selected, {'path': 'NOTICES', 'sha256': sha(b'Untracked notice')})
            for offline in (False, True):
                with self.subTest(offline=offline):
                    collector = Collector(args, root/f'out-{offline}', offline=offline)
                    with self.assertRaisesRegex(ValueError, 'Selected hosted notice differs.*NOTICES'):
                        collector.archive(name, entry, package, notice=selected, notice_paths=notice_paths)
                    with self.assertRaisesRegex(ValueError, 'Selected hosted notice differs.*NOTICES'):
                        collector.archive_notice(name, entry, selected, notice_paths)
                    self.assertFalse(collector.output.exists())
                    collector.archive_notice(name, entry, original, notice_paths)
                    self.assertEqual(set(collector.files), {'licenses/'+name+'/LICENSE'})

    def test_hosted_notice_selection_matches_locked_precedence_and_absence(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            package, downloads = root/'cache', root/'downloads'
            (package/'src').mkdir(parents=True)
            downloads.mkdir()
            (root/'tool').mkdir()
            (root/'tool/release_materials_sources.json').write_text('{}')
            name = 'fixture_dependency'
            paths = tuple(flutter_package_notice_paths(package.as_uri(), 'src/lib/', package))
            self.assertEqual(paths, ('src/NOTICES', 'src/LICENSE'))
            fallback = {'path': 'src/LICENSE', 'sha256': sha(b'license')}
            args = SimpleNamespace(repo=root, downloads=downloads)
            for index, (members, recorded, expected_error) in enumerate((
                    (('src/LICENSE',), None, 'src/LICENSE'),
                    (('src/LICENSE', 'src/NOTICES'), fallback, 'src/NOTICES'),
                    ((), None, None))):
                archive = downloads/(name+f'-1.0.{index}.tar.gz')
                with tarfile.open(archive, 'w:gz') as tar:
                    for member in members:
                        info = tarfile.TarInfo(member)
                        info.size = len(b'license')
                        tar.addfile(info, io.BytesIO(b'license'))
                entry = {'version': f'1.0.{index}', 'description': {
                    'url': 'https://pub.dev', 'sha256': sha(archive.read_bytes())}}
                collector = Collector(args, root/f'out-{index}', offline=True)
                with self.subTest(members=members, recorded=recorded):
                    if expected_error is not None:
                        with self.assertRaisesRegex(ValueError, 'Selected hosted notice differs.*'+expected_error):
                            collector.archive_notice(name, entry, recorded, paths)
                        with self.assertRaisesRegex(ValueError, 'Selected hosted notice differs.*'+expected_error):
                            collector.archive(name, entry, package, notice=recorded, notice_paths=paths)
                    else:
                        collector.archive_notice(name, entry, recorded, paths)
                    self.assertFalse(collector.output.exists())

    def test_native_archive_requires_files_recorded_before_build_even_after_cache_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            package, downloads = root/'package', root/'downloads'
            package.mkdir()
            downloads.mkdir()
            (root/'tool').mkdir()
            (root/'tool/release_materials_sources.json').write_text('{}')
            (package/'LICENSE').write_bytes(b'MIT')
            archive = downloads/'libserialport_plus-1.0.5.tar.gz'
            with tarfile.open(archive, 'w:gz') as tar:
                tar.add(package/'LICENSE', arcname='LICENSE')
            entry = {'version': '1.0.5', 'description': {'url': 'https://pub.dev', 'sha256': sha(archive.read_bytes())}}
            prebuild = {'libserialport_plus': {'files': {
                'LICENSE': {'sha256': sha(b'MIT')},
                'src/include/local-only.h': {'sha256': sha(b'build-time header')},
            }}, 'sqlite3': {'files': {'LICENSE': {'sha256': sha(b'MIT')}}}}
            bound = native_source_hashes(prebuild)['libserialport_plus']
            args = SimpleNamespace(repo=root, downloads=downloads)
            collector = Collector(args, root/'missing-source', offline=True)
            with self.assertRaisesRegex(ValueError, 'Native hook source input is absent.*local-only.h'):
                collector.archive('libserialport_plus', entry, package, native_files=bound)
            with self.assertRaisesRegex(ValueError, 'Native hook source input differs.*LICENSE'):
                collector.archive('libserialport_plus', entry, package, native_files={'LICENSE': sha(b'edited')})
            self.assertFalse(collector.output.exists())
            clean = Collector(args, root/'original', offline=True)
            self.assertTrue(clean.archive('libserialport_plus', entry, package,
                                          native_files={'LICENSE': sha(b'MIT')})['cacheMatchesArchive'])

    def test_archived_notice_matches_case_insensitive_lookup_and_rejects_ambiguity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            package, downloads = root/'package', root/'downloads'
            package.mkdir()
            downloads.mkdir()
            (root/'tool').mkdir()
            (root/'tool/release_materials_sources.json').write_text('{}')
            name = 'fixture'
            paths = ('NOTICES', 'LICENSE')
            identity = {'path': 'LICENSE', 'sha256': sha(b'original')}
            args = SimpleNamespace(repo=root, downloads=downloads)
            for index, names in enumerate((('license',), ('license', 'LICENSE'))):
                archive = downloads/f'{name}-1.0.{index}.tar.gz'
                with tarfile.open(archive, 'w:gz') as tar:
                    for member in names:
                        info = tarfile.TarInfo(member)
                        info.size = len(b'original')
                        tar.addfile(info, io.BytesIO(b'original'))
                        (package/member).write_bytes(b'original')
                entry = {'version': f'1.0.{index}', 'description': {
                    'url': 'https://pub.dev', 'sha256': sha(archive.read_bytes())}}
                collector = Collector(args, root/f'out-{index}', offline=True)
                with self.subTest(names=names):
                    if index == 0:
                        collector.archive_notice(name, entry, identity, paths, case_sensitive=False)
                        self.assertEqual(set(collector.files), {f'licenses/{name}/license'})
                        self.assertTrue(collector.archive(name, entry, package, notice=identity,
                                                         notice_paths=paths, case_sensitive=False)['cacheMatchesArchive'])
                        with self.assertRaisesRegex(ValueError, 'Selected hosted notice differs'):
                            collector.archive_notice(name, entry, None, paths, case_sensitive=False)
                        sensitive = Collector(args, root/'case-sensitive', offline=True)
                        sensitive.archive_notice(name, entry, None, paths, case_sensitive=True)
                        self.assertEqual(sensitive.files, {})
                    else:
                        with self.assertRaisesRegex(ValueError, 'Ambiguous case aliases in locked notices'):
                            collector.archive_notice(name, entry, identity, paths, case_sensitive=False)
                        with self.assertRaisesRegex(ValueError, 'Ambiguous case aliases in locked notices'):
                            collector.archive(name, entry, package, notice=identity, notice_paths=paths, case_sensitive=False)


class NativeTests(unittest.TestCase):
    def test_candidate_native_mapping_reads_saved_outputs_and_relocates_dependencies(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            live, retained = root/HOOK_CACHE, root/'native-hooks'
            locations = {}
            for package, library in (('libserialport_plus', 'liblibserialport_plus.dylib'),
                                     ('sqlite3', 'libsqlite3.dylib')):
                locations[package] = root/'hosted'/package
                raw_path = Path('shared')/package/library
                raw = retained/raw_path
                raw.parent.mkdir(parents=True)
                raw.write_bytes(b'current native output')
                stale = live/raw_path
                stale.parent.mkdir(parents=True)
                stale.write_bytes(b'old')
                for bundled in (root/f'app/Contents/Frameworks/{package}.framework/{package}', root/'cli/lib'/library):
                    bundled.parent.mkdir(parents=True, exist_ok=True)
                    bundled.write_bytes(b'synthetic bundled output')
                evidence = retained/package/'fixture'
                evidence.mkdir(parents=True)
                code = {'target_os': 'macos', 'target_architecture': 'arm64', 'macos': {'target_version': 13}}
                (evidence/'input.json').write_bytes(encoded({'package_name': package,
                    'package_root': str(locations[package]), 'user_defines': {},
                    'config': {'linking_enabled': True, 'extensions': {'code_assets': code}}}))
                (evidence/'output.json').write_bytes(encoded({'status': 'success', 'assets': [
                    {'encoding': {'id': package, 'file': str(stale),
                                  'link_mode': {'type': 'dynamic_loading_bundle'}}}]}))
                (evidence/'dependencies.dependencies_hash_file.json').write_bytes(encoded({'file_system': [
                    {'path': str(stale), 'size': raw.stat().st_size, 'last_modified': raw.stat().st_mtime_ns//1000}]}))
                if package == 'sqlite3':
                    hashes = locations[package]/'lib/src/hook/asset_hashes.dart'
                    hashes.parent.mkdir(parents=True)
                    hashes.write_text(f"'libsqlite3.arm64.macos.dylib': '{sha(raw.read_bytes())}'")
            collector = Collector(SimpleNamespace(repo=root, app=root/'app', cli=root/'cli'), root/'materials')
            collector.hook_cache = retained

            def macho_sections(path):
                self.assertFalse(path.is_relative_to(live))
                return {'16777228': {'__TEXT,__text': 'fixture sections'}}

            with (patch('release_materials.sections', side_effect=macho_sections),
                  patch('release_materials.run', return_value='minos 13.0\n')):
                mappings = collector.native_mapping(locations)
            self.assertEqual(collector.blockers, [])
            for packages in mappings.values():
                for mapping in packages.values():
                    self.assertEqual(mapping['matches']['16777228'][0]['rawSha256'], sha(b'current native output'))

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
