"""Focused dev.3 provenance, material and archive regressions; no real devices."""
import copy
import io
import json
from pathlib import Path
import shutil
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import candidate_common as c
import package_1c_candidate as pack
import smoke_cli


class CandidateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='meshchan-candidate-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bundle = self.root / 'bundle'
        for name in ('bin/meshctl', 'lib/nested/libserialport.so', 'lib/nested/libsqlite3.so'):
            path = self.bundle / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'synthetic ' + name.encode())
            path.chmod(0o755)
        self.files = c.inventory(self.bundle)

    def archive(self, change=None):
        path = self.root / 'archive.tar.gz'
        with tarfile.open(path, 'w:gz') as tar:
            for name in ['bundle', 'bundle/bin', 'bundle/lib', 'bundle/lib/nested']:
                member = tarfile.TarInfo(name)
                member.type = tarfile.DIRTYPE
                tar.addfile(member)
            for name in self.files:
                member = tar.gettarinfo(self.bundle / name, arcname='bundle/' + name)
                content = (self.bundle / name).read_bytes()
                if change:
                    altered = change(member, content)
                    if altered is None:
                        continue
                    member, content = altered
                tar.addfile(member, io.BytesIO(content))
            if change and getattr(change, 'extra', None):
                member = tarfile.TarInfo(change.extra)
                member.size = 1
                tar.addfile(member, io.BytesIO(b'x'))
        return path

    def rejects(self, change):
        path = self.archive(change)
        with self.assertRaises(ValueError):
            c.extract_verified(path, c.digest(path), self.root / 'extracted', 'bundle', self.files)

    def test_exact_recursive_assets_and_safe_archive(self):
        c.validate_runtime(self.files)
        path = self.archive()
        extracted = c.extract_verified(path, c.digest(path), self.root / 'extracted', 'bundle', self.files)
        self.assertEqual(c.inventory(extracted), self.files)
        missing = copy.deepcopy(self.files)
        del missing['lib/nested/libsqlite3.so']
        with self.assertRaisesRegex(ValueError, 'sqlite3'):
            c.validate_runtime(missing)

    def test_archive_tamper_missing_extra_duplicate_traversal_link_mode_and_replaced_native(self):
        path = self.archive()
        expected = c.digest(path)
        path.write_bytes(path.read_bytes() + b'tamper')
        with self.assertRaisesRegex(ValueError, 'bytes'):
            c.extract_verified(path, expected, self.root / 'extract', 'bundle', self.files)
        self.rejects(lambda member, data: None if 'sqlite3' in member.name else (member, data))
        for extra in ('bundle/extra', 'bundle/bin/meshctl', '../escape', '/absolute'):
            def add(member, data):
                return member, data
            add.extra = extra
            self.rejects(add)
        def link(member, data):
            member.type = tarfile.SYMTYPE
            member.linkname = '/outside'
            member.size = 0
            return member, b''
        self.rejects(link)
        def mode(member, data):
            member.mode = 0o644
            return member, data
        self.rejects(mode)
        self.rejects(lambda m, b: (m, b'x' * len(b)))

    def test_workspace_classification_and_missing_originals(self):
        graph = {'packages': [
            {'name': name, 'source': 'root', 'directDependencies': deps}
            for name, deps in [('meshctl', ['meshchan_core']), ('meshchan_core', ['meshcore_link']),
                               ('meshcore_link', ['external'])]] +
            [{'name': 'external', 'source': 'hosted', 'directDependencies': []}]}
        _, closure, first = c.production_closure(graph)
        self.assertEqual(closure - first, {'external'})
        self.assertIn('meshchan_core', first)
        with self.assertRaisesRegex(ValueError, 'Missing original'):
            c.original_notices(self.bundle)
        notice = self.bundle / 'COPYING'
        notice.write_bytes(b'original legal text\r\n')
        self.assertEqual(c.original_notices(self.bundle), [notice])

    def test_actual_versions_and_core_input_invalidation(self):
        for name in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'):
            shutil.copy2(c.ROOT / name, self.root / name)
        for member in c.MEMBERS:
            shutil.copytree(c.ROOT / member / 'lib', self.root / member / 'lib')
            shutil.copy2(c.ROOT / member / 'pubspec.yaml', self.root / member / 'pubspec.yaml')
        shutil.copytree(c.ROOT / 'apps/meshctl/bin', self.root / 'apps/meshctl/bin')
        self.assertEqual(set(c.versions(self.root).values()), {c.TARGET_VERSION})
        before = c.product_inputs(self.root)
        generated = self.root / 'packages/meshchan_core/lib/src/storage/database.g.dart'
        generated.write_bytes(generated.read_bytes() + b'\n// changed\n')
        self.assertNotEqual(c.product_inputs(self.root), before)
        self.assertIn('packages/meshchan_core/lib/src/storage/database.g.dart', before)
        spec = self.root / 'packages/meshchan_core/pubspec.yaml'
        spec.write_text(spec.read_text().replace(c.TARGET_VERSION, '0.1.0-dev.2'))
        with self.assertRaisesRegex(ValueError, 'version mismatch'):
            c.versions(self.root)

    def test_required_gate_failure_missing_and_log_mutation_reject(self):
        log = self.root / 'ok.log'
        log.write_text('actual check result, no historical count')
        record = {'directory': str(self.root), 'productCompilationInputHashes': {},
            'verificationInputHashes': {}, 'gates': [
                {'name': n, 'exitCode': 0, 'status': 'PASS', 'log': 'ok.log', 'logSha256': c.digest(log)}
                for n in c.REQUIRED_GATES]}
        with patch.object(c, 'product_inputs', return_value={}), \
                patch.object(c, 'verification_inputs', return_value={}), patch.object(c, 'versions'):
            c.validate_gate(record)
            missing = copy.deepcopy(record)
            missing['gates'].pop()
            with self.assertRaisesRegex(ValueError, 'missing or failed'):
                c.validate_gate(missing)
            failed = copy.deepcopy(record)
            failed['gates'][0]['exitCode'] = 1
            with self.assertRaises(ValueError):
                c.validate_gate(failed)
            log.write_text('modified')
            with self.assertRaisesRegex(ValueError, 'log changed'):
                c.validate_gate(record)

    def test_final_extraction_invokes_shared_real_business_gate(self):
        info = {'version': c.TARGET_VERSION, 'runtimeInventory': self.files}
        (self.bundle / 'build-info.json').write_text(json.dumps(info))
        (self.bundle / 'SHA256SUMS').write_text(''.join(item['sha256'] + '  ' + name + '\n'
            for name, item in c.inventory(self.bundle).items()))
        path = self.root / 'complete.tar.gz'
        with tarfile.open(path, 'w:gz') as tar:
            tar.add(self.bundle, arcname='bundle')
        fixture = self.root / 'fixture'
        fixture.mkdir()
        (fixture / 'meshchan.sqlite').write_bytes(b'synthetic fixture; never opened')
        with patch.object(pack, 'archive_business_checks') as business:
            result = pack.verify_archive(path, c.digest(path), self.bundle, self.files, fixture, c.TARGET_VERSION)
            business.assert_called_once()
            self.assertIn('meshchan dev3 final archive', str(business.call_args.args[2]))
            self.assertEqual(result['status'], 'PASS')
        with patch.object(pack, 'archive_business_checks', side_effect=ValueError('business failed')):
            with self.assertRaisesRegex(ValueError, 'business failed'):
                pack.verify_archive(path, c.digest(path), self.bundle, self.files, fixture, c.TARGET_VERSION)

    def test_nonempty_export_rejects_leaks_or_lost_facts(self):
        class Capture:
            validators = []
            def check(inner, name, command, cwd, **kwargs):
                inner.validators.append(kwargs['validate'])
        checks = Capture()
        smoke_cli.nonempty_history_checks(checks, 'fixture', ['product'], self.root, self.root)
        export = checks.validators[-1]
        run = {'appVersion': c.TARGET_VERSION, 'preparedAt': '2026-11-12T00:00:00.000001Z',
               'cleanup': {'core': None, 'hostSubscriptions': False, 'aggregate': 0}}
        envelope = {'diagnosticSummaryFormatVersion': 1, 'exportedAt': 'time', 'runs': [run]}
        export(json.dumps(envelope))
        run['payload'] = 'secret'
        with self.assertRaisesRegex(ValueError, 'Unsafe'):
            export(json.dumps(envelope))


if __name__ == '__main__':
    unittest.main()
