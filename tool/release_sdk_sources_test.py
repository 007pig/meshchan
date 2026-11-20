"""Native SDK source coverage must be proved independently of a PASS flag."""
import copy
import io
import json
import os
from pathlib import Path
import py_compile
import socket
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from release_sdk_sources import (DART, archive_inventory, command, configure_build, deps_data, digest, git_hash, graph_coverage,
                                 sdk_workspace_lock, fetch, load_upstream, probe, restore_materials,
                                 source_identity, source_inputs, target_closure,
                                 validate_probe_write_paths, verify_stale_headers)


class SdkSourceTests(unittest.TestCase):
    def test_configure_build_rejects_aliased_write_destinations(self):
        for name, kind in (
            ('evidence/build-configuration.json', 'hardlink'),
            ('checkout/engine/src/out/rebuild-app-arm64', 'directory link'),
            ('checkout/engine/src/out/rebuild-app-arm64/build.ninja', 'hardlink'),
            ('checkout/engine/src/flutter/buildtools/mac-arm64/clang', 'directory link'),
            ('checkout/engine/src/flutter/buildtools/mac-arm64/clang/bin/llvm', 'hardlink'),
        ):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as folder:
                base = Path(folder).resolve()
                workspace, outside = base/'workspace', base/'outside'
                outside.mkdir()
                original = outside/'original'
                original.write_bytes(b'preserve')
                destination = workspace/name
                destination.parent.mkdir(parents=True)
                (workspace/'evidence').mkdir(exist_ok=True)
                if kind == 'hardlink':
                    os.link(original, destination)
                else:
                    destination.symlink_to(outside, target_is_directory=True)
                archive = workspace/'compiler.zip'
                with zipfile.ZipFile(archive, 'w') as payload:
                    payload.writestr('bin/llvm', b'pinned compiler')
                spec = {'toolPackages': [{'product': 'app', 'sha256': digest(archive)}]}
                report = {'targets': {'app-arm64': {'gnArgs': {}}}}
                with (patch('release_sdk_sources.command', return_value='/Xcode/Developer') as invoke,
                      patch('release_sdk_sources.fetch', return_value=archive),
                      self.assertRaisesRegex(ValueError, 'write (?:path|file)')):
                    configure_build(spec, workspace, report, ['app-arm64'])
                self.assertTrue(all(argv.args[0][0] in ('/usr/bin/xcrun', '/usr/bin/xcode-select')
                                    for argv in invoke.call_args_list))
                self.assertEqual(original.read_bytes(), b'preserve')

    def test_configure_build_preserves_pinned_compiler_and_xcode_links_on_reuse(self):
        with tempfile.TemporaryDirectory() as folder:
            workspace = Path(folder).resolve()
            developer = workspace/'Xcode/Contents/Developer'
            out = workspace/'checkout'/DART/'out/rebuild-cli-arm64'
            sdk_links = out/'sdk/xcode_links'
            sdk_links.mkdir(parents=True)
            for platform in ('MacOSX', 'iPhoneOS'):
                sdk = f'{platform}27.2.sdk'
                target = developer/'Platforms'/f'{platform}.platform/Developer/SDKs'/sdk
                (sdk_links/sdk).symlink_to(target, target_is_directory=True)
            (workspace/'evidence').mkdir()
            archive = workspace/'compiler.zip'
            link = zipfile.ZipInfo('bin/clang')
            link.create_system = 3
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            with zipfile.ZipFile(archive, 'w') as payload:
                payload.writestr('bin/llvm', b'pinned compiler fixture')
                payload.writestr(link, 'llvm')
            spec = {'toolPackages': [{'product': 'cli', 'sha256': digest(archive)}]}
            report = {'targets': {'cli-arm64': {'gnArgs': {}}}}

            def run(argv):
                if argv[0] == '/usr/bin/unzip':
                    return command(argv)
                return str(developer)

            with (patch('release_sdk_sources.command', side_effect=run),
                  patch('release_sdk_sources.fetch', return_value=archive)):
                first = configure_build(spec, workspace, report, ['cli-arm64'])
                self.assertEqual(configure_build(spec, workspace, report, ['cli-arm64']), first)
                clang = out.parents[1]/'buildtools/mac-arm64/clang/bin/clang'
                self.assertEqual(os.readlink(clang), 'llvm')
                self.assertEqual(clang.read_bytes(), b'pinned compiler fixture')
                clang.unlink()
                clang.symlink_to(workspace/'external compiler')
                with self.assertRaisesRegex(ValueError, 'write path differs from the pinned symlink'):
                    configure_build(spec, workspace, report, ['cli-arm64'])

    def test_probe_rejects_special_files_and_wrong_destination_types_before_work(self):
        spec = {'generatedConfiguration': {}}
        for name, kind, expected in (
            ('evidence/app-arm64-gn.log', 'fifo', 'write file must be a regular file'),
            ('bin/gn', 'socket', 'write file must be a regular file'),
            ('evidence/sdk-source-report.json', 'directory', 'write file must be a regular file'),
            ('evidence', 'fifo', 'write directory must be a real directory'),
            ('checkout/engine/src/out', 'file', 'write directory must be a real directory'),
        ):
            with self.subTest(name=name, kind=kind), tempfile.TemporaryDirectory() as folder:
                workspace = Path(folder).resolve()
                target = workspace/name
                target.parent.mkdir(parents=True, exist_ok=True)
                if kind == 'fifo':
                    os.mkfifo(target)
                elif kind == 'socket':
                    with socket.socket(socket.AF_UNIX) as channel:
                        channel.bind(str(target))
                elif kind == 'directory':
                    target.mkdir()
                else:
                    target.touch()
                with patch('release_sdk_sources.fetch') as fetch_input, self.assertRaisesRegex(ValueError, expected):
                    probe(spec, workspace, workspace/'flutter', {})
                fetch_input.assert_not_called()

    def test_probe_paths_allow_owned_directories_and_single_link_regular_files(self):
        with tempfile.TemporaryDirectory() as folder:
            workspace = Path(folder).resolve()
            log = workspace/'evidence/app-arm64-gn.log'
            log.parent.mkdir()
            log.touch()
            (workspace/'checkout/engine/src/out').mkdir(parents=True)
            spec = {'generatedConfiguration': {}}
            validate_probe_write_paths(workspace, spec)
            os.link(log, workspace/'other-log')
            with self.assertRaisesRegex(ValueError, 'write file has multiple hard links'):
                validate_probe_write_paths(workspace, spec)

    def test_workspace_lock_excludes_an_independent_process_until_evidence_is_read(self):
        code = """
import fcntl
import sys
from pathlib import Path
with Path(sys.argv[1]).open('rb') as lock:
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print('busy')
    else:
        print('available')
"""
        with tempfile.TemporaryDirectory() as folder:
            workspace = Path(folder).resolve()
            lock = workspace/'.meshchan-sdk-sources.lock'

            def probe():
                return subprocess.check_output([sys.executable, '-c', code, str(lock)], text=True, timeout=10).strip()

            with sdk_workspace_lock(workspace):
                report = workspace/'report.json'
                report.write_text('{"complete": true}')
                self.assertEqual(probe(), 'busy')
                self.assertEqual(report.read_text(), '{"complete": true}')
                self.assertEqual(probe(), 'busy')
            self.assertEqual(probe(), 'available')

    def test_required_original_download_missing_or_tampered_fails_offline(self):
        import hashlib
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            item = {'archive': 'native-source.tar.gz', 'url': 'https://example.invalid/fixed-source',
                    'sha256': hashlib.sha256(b'original\r\n').hexdigest()}
            with self.assertRaisesRegex(ValueError, 'Missing SDK source material'):
                fetch(item, root, offline=True)
            (root/item['archive']).write_bytes(b'original\r\n')
            self.assertEqual(fetch(item, root, offline=True).read_bytes(), b'original\r\n')
            (root/item['archive']).write_bytes(b'changed\n')
            with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                fetch(item, root, offline=True)

    def test_download_cache_rejects_fifo_and_dangling_link_before_read_or_fetch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root/'sources.tar'
            item = {'archive': path.name, 'url': 'https://example.invalid/source',
                    'sha256': 'a'*64}
            os.mkfifo(path)
            with self.assertRaisesRegex(ValueError, 'Source cache entry must be a regular file'):
                fetch(item, root, offline=True)
            path.unlink()
            target = root/'missing'
            path.symlink_to(target)
            with (patch('release_sdk_sources.subprocess.run') as curl,
                  self.assertRaisesRegex(ValueError, 'Source cache entry must be a regular file')):
                fetch(item, root)
            curl.assert_not_called()
            self.assertFalse(target.exists())

    def test_source_kit_restore_preserves_existing_files_and_rejects_aliased_parents(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            materials, workspace = root/'materials', root/'workspace'
            kit = materials/'source-materials/sdk'
            (kit/'archives').mkdir(parents=True)
            source = kit/'clang/source_manifest.json'
            source.parent.mkdir()
            source.write_bytes(b'original compiler config')
            spec = {'toolPackages': [{'files': {'source_manifest.json': {
                'path': 'clang/source_manifest.json', 'sha256': digest(source)}}}]}
            rules = root/'spec.json'
            rules.write_text(json.dumps(spec))
            (kit/'source-inputs.json').write_bytes(rules.read_bytes())
            downloads = workspace/'downloads/package-files'
            downloads.mkdir(parents=True)
            protected = root/'outside'
            protected.mkdir()
            sentinel = protected/'source_manifest.json'
            sentinel.write_bytes(b'other config')
            parent = downloads/'clang'
            parent.symlink_to(protected, target_is_directory=True)
            with patch('release_sdk_sources.SPEC', rules):
                with self.assertRaisesRegex(ValueError, 'uses a symlink'):
                    restore_materials(materials, workspace)
                parent.unlink()
                parent.mkdir()
                target = parent/sentinel.name
                os.link(sentinel, target)
                with self.assertRaisesRegex(ValueError, 'Conflicting restored SDK source input'):
                    restore_materials(materials, workspace)
                self.assertEqual(sentinel.read_bytes(), b'other config')
                target.unlink()
                restore_materials(materials, workspace)
                self.assertEqual(target.read_bytes(), source.read_bytes())

    def test_upstream_modules_and_commands_ignore_stale_bytecode(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            path = root/'fixture_source.py'
            path.write_text('VALUE = 1\n')
            timestamp = path.stat()
            py_compile.compile(str(path), doraise=True)
            path.write_text('VALUE = 2\n')
            os.utime(path, ns=(timestamp.st_atime_ns, timestamp.st_mtime_ns))
            self.assertEqual(load_upstream(path, 'fixture_source').VALUE, 2)
            self.assertEqual(command([sys.executable, '-c', 'from fixture_source import VALUE; print(VALUE)'],
                                     cwd=root).strip(), '2')

    def test_deps_literals_preserve_distinct_native_pins_without_execution(self):
        data = deps_data("vars={'root':'sdk','icu':'abc'}\ndeps={Var('root')+'/icu':'url@'+Var('icu')}\n")
        self.assertEqual(data['deps'], {'sdk/icu': 'url@abc'})
        with self.assertRaisesRegex(ValueError, 'Unsupported'):
            deps_data("vars={'root':'sdk'}\ndeps=__import__('os').system('false')\n")
        with self.assertRaisesRegex(ValueError, 'Missing'):
            deps_data('vars={}\ndeps={}\n')

    def test_archive_preserves_bytes_modes_links_and_omitted_gitlinks(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'source.tar.gz'
            with tarfile.open(path, 'w:gz') as tar:
                info = tarfile.TarInfo('LICENSE');data = b'Copyright\r\nOriginal\x00bytes\r\n'
                info.size = len(data);tar.addfile(info, io.BytesIO(data))
                info = tarfile.TarInfo('build.sh');info.mode = 0o755;info.size = 2
                tar.addfile(info, io.BytesIO(b'#!'))
                info = tarfile.TarInfo('link');info.type = tarfile.SYMTYPE;info.linkname = 'LICENSE'
                tar.addfile(info)
            files, plain = archive_inventory(path)
            self.assertEqual(files['build.sh']['mode'], '100755')
            self.assertEqual(files['link']['mode'], '120000')
            _, linked = archive_inventory(path, {'optional/test': '1'*40})
            self.assertNotEqual(plain, linked)
            with self.assertRaisesRegex(ValueError, 'gitlink'):
                archive_inventory(path, {'LICENSE': '1'*40})
            self.assertEqual(git_hash('blob', b'test\n'), '9daeafb9864cf43055ae93beb0afd6c7d144bfa4')

    def test_graph_requires_every_node_and_source_and_generated_producer(self):
        graph = {'//:runtime': {'deps': ['//:code', '//:generate'],
                                 'sources': ['//out/generated.cc']},
                 '//:code': {'sources': ['//runtime.cc', '//LICENSE']},
                 '//:generate': {'script': '//generate.py', 'inputs': ['//schema'],
                                   'outputs': ['//out/generated.cc']}}
        originals = {p: {'sha256': p} for p in ('sdk/runtime.cc', 'sdk/LICENSE',
                                                'sdk/generate.py', 'sdk/schema')}
        result = graph_coverage(graph, '//:runtime', 'sdk/', originals, {}, {})
        self.assertEqual(result['generatedInputs'], {'//out/generated.cc': '//:generate'})
        for p in originals:
            bad = dict(originals);bad.pop(p)
            with self.subTest(missing=p), self.assertRaisesRegex(ValueError, 'Uncovered'):
                graph_coverage(graph, '//:runtime', 'sdk/', bad, {}, {})
        bad = copy.deepcopy(graph);bad['//:runtime']['deps'].remove('//:generate')
        with self.assertRaisesRegex(ValueError, 'Uncovered'):
            graph_coverage(bad, '//:runtime', 'sdk/', originals, {}, {})
        for root in ('//:missing', '//:empty'):
            with self.assertRaises(ValueError):
                target_closure({**graph, '//:empty': {}}, root)

    def test_installed_engine_tree_and_dart_revision_must_match_independently(self):
        with tempfile.TemporaryDirectory() as folder:
            flutter = Path(folder);cache = flutter/'bin/cache';(cache/'dart-sdk').mkdir(parents=True)
            spec = {'frameworkRevision': 'framework', 'engineRevision': 'engine',
                    'engineContentHash': 'content', 'dartRevision': 'dart', 'engineSourceTree': 'tree'}
            (cache/'flutter.version.json').write_text(json.dumps(spec))
            (cache/'dart-sdk/revision').write_text('dart\n')
            with patch('release_sdk_sources.command', return_value='tree\n'):
                self.assertEqual(set(source_identity(spec, flutter).values()), {'tree'})
                (cache/'dart-sdk/revision').write_text('different\n')
                with self.assertRaisesRegex(ValueError, 'dartRevision'):
                    source_identity(spec, flutter)
            (cache/'dart-sdk/revision').write_text('dart\n')
            with patch('release_sdk_sources.command', side_effect=['tree\n', 'other\n']):
                with self.assertRaisesRegex(ValueError, 'tree mismatch'):
                    source_identity(spec, flutter)
            revision = cache/'dart-sdk/revision'
            revision.unlink()
            os.mkfifo(revision)
            read_text = Path.read_text
            def guarded_read(path, *args, **kwargs):
                self.assertNotEqual(path, revision, 'A FIFO must be rejected before reading')
                return read_text(path, *args, **kwargs)
            with (patch.object(Path, 'read_text', guarded_read),
                  self.assertRaisesRegex(ValueError, 'Dart SDK metadata must be a regular file')):
                source_identity(spec, flutter)

    def test_native_runtime_source_set_cannot_be_downgraded_to_empty(self):
        with patch('release_sdk_sources.source_identity'):
            with self.assertRaisesRegex(ValueError, 'LLVM runtime source/build inputs'):
                source_inputs({'archives': []}, Path('/unused'), Path('/unused'))

    def test_sdk_identity_rejects_nonregular_flutter_version_cache_before_reading(self):
        with tempfile.TemporaryDirectory() as directory:
            flutter = Path(directory)
            version = flutter/'bin/cache/flutter.version.json'
            version.parent.mkdir(parents=True)
            os.mkfifo(version)
            original = Path.read_text

            def guarded_read(path, *args, **kwargs):
                self.assertNotEqual(path, version, 'Do not open a FIFO')
                return original(path, *args, **kwargs)

            with (patch.object(Path, 'read_text', guarded_read),
                  self.assertRaisesRegex(ValueError, 'Flutter SDK metadata must be a regular file')):
                source_identity({}, flutter)

    def test_stale_header_exception_requires_real_replacement_and_include_evidence(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            contents = {'BUILD.gn': 'sources=["old.h"]', 'new.h': '// original header\n',
                        'user.cc': '#include "new.h"\n'}
            for p, text in contents.items():
                (root/p).write_text(text)
            originals = {p: {'sha256': p} for p in contents}
            spec = {'staleHeaderScanRoots': [''], 'staleHeaders': [{'path': 'old.h', 'replacement': 'new.h', 'reason': 'Pinned obsolete declaration',
                'obsoleteInclude': 'old.h', 'declaration': 'BUILD.gn', 'literal': '"old.h"',
                'includeUsers': ['user.cc'], 'replacementInclude': '#include "new.h"'}]}
            self.assertEqual(set(verify_stale_headers(spec, root, originals)), {'old.h'})
            (root/'user.cc').write_text('#include "old.h"\n#include "new.h"\n')
            with self.assertRaisesRegex(ValueError, 'compiler include'):
                verify_stale_headers(spec, root, originals)
            (root/'user.cc').write_text(contents['user.cc'])
            originals.pop('new.h')
            with self.assertRaisesRegex(ValueError, 'no longer applies'):
                verify_stale_headers(spec, root, originals)


if __name__ == '__main__':
    unittest.main()
