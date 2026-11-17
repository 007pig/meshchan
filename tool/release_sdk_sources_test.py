"""Native SDK source coverage must be proved independently of a PASS flag."""
import copy
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from release_sdk_sources import (archive_inventory, deps_data, git_hash, graph_coverage,
                                 fetch, source_identity, source_inputs, target_closure,
                                 verify_stale_headers)


class SdkSourceTests(unittest.TestCase):
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

    def test_native_runtime_source_set_cannot_be_downgraded_to_empty(self):
        with patch('release_sdk_sources.source_identity'):
            with self.assertRaisesRegex(ValueError, 'LLVM runtime source/build inputs'):
                source_inputs({'archives': []}, Path('/unused'), Path('/unused'))

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
