"""Current candidate expectations reach manifests, processes and retained reports."""
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

import candidate_common as c
import regression_1d10 as runner
import smoke_cli

RC = '0.1.0-rc.1'
APP_BUILD = 10


class CandidateVersionTest(unittest.TestCase):
    def test_four_members_five_constraints_constant_and_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            names = [m + '/pubspec.yaml' for m in (*c.MEMBERS, 'apps/meshchan_app')]
            names += ['apps/meshctl/lib/src/version.dart',
                      'apps/meshchan_app/lib/runtime/build_version.dart']
            for name in names:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(c.ROOT / name, target)
            self.assertEqual(c.versions(root, RC, app_build=APP_BUILD)['meshchan_app'], f'{RC}+{APP_BUILD}')
            for name in names:
                target = root / name
                original = target.read_text()
                target.write_text(original.replace(RC, '0.1.0-dev.2'))
                with self.assertRaises(ValueError, msg=name):
                    c.versions(root, RC, app_build=APP_BUILD)
                target.write_text(original)
            for owner, dependency in [('meshchan_core', 'meshcore_link'),
                    ('meshctl', 'meshchan_core'), ('meshctl', 'meshcore_link'),
                    ('meshchan_app', 'meshchan_core'), ('meshchan_app', 'meshcore_link')]:
                member = next(m for m in (*c.MEMBERS, 'apps/meshchan_app') if m.endswith('/' + owner))
                target = root / member / 'pubspec.yaml'
                original = target.read_text()
                target.write_text(original.replace(dependency + ': ^' + RC, dependency + ': ^0.1.0-dev.2'))
                with self.assertRaisesRegex(ValueError, 'constraint'):
                    c.versions(root, RC, app_build=APP_BUILD)
                target.write_text(original)
            fallback = root / 'apps/meshchan_app/lib/runtime/build_version.dart'
            original = fallback.read_text()
            fallback.write_text(original.replace(f"appBuildNumber = '{APP_BUILD}'", "appBuildNumber = '8'"))
            with self.assertRaisesRegex(ValueError, 'App fallback'):
                c.versions(root, RC, app_build=APP_BUILD)
            fallback.write_text(original)
            manifest = root / 'packages/meshcore_link/pubspec.yaml'
            original = manifest.read_text()
            manifest.write_text(original.replace('version: ' + RC, 'missing-version: ' + RC))
            with self.assertRaisesRegex(ValueError, 'Missing or malformed version field'):
                c.versions(root, RC, app_build=APP_BUILD)
            manifest.write_text(original)
            with self.assertRaises(ValueError):
                c.versions(root)  # Historical default must not accept an RC checkout.
            with self.assertRaises(ValueError):
                c.versions(root, RC, app_build=1)
            for invalid in ('', 'anything', '0.1.0+2'):
                with self.assertRaises(ValueError):
                    c.versions(root, invalid)

    def test_runner_propagates_explicit_version_without_changing_historical_default(self):
        plan = runner.software_plan(Path('/tmp/evidence'), Path('/sdk/flutter'), Path('/sdk/dart'), RC, 6)
        for name in ('R01-versions', 'R13-smoke', 'R17-legacy'):
            argv = next(g['argv'] for g in plan if g['name'] == name)
            self.assertEqual(argv[argv.index('--expected-version') + 1], RC)
        self.assertEqual(plan[0]['argv'][plan[0]['argv'].index('--app-build') + 1], '6')
        historical = runner.software_plan(Path('/tmp/e'), Path('/sdk/f'), Path('/sdk/d'))
        self.assertNotIn('R01-versions', [g['name'] for g in historical])
        self.assertIn(c.TARGET_VERSION, next(g['argv'] for g in historical if g['name'] == 'R13-smoke'))

    def test_smoke_passes_rc_to_aot_recording_history_and_report_validation(self):
        records = []
        class Checks:
            count = 0
            def __init__(self):
                self.records = []
            def check(self, name, command, cwd, **kwargs):
                records.append((name, command, kwargs))
                if 'synthetic runCli/core recording' in name:
                    report = {'passed': True, 'closedBeforeReport': True,
                              'appVersion': RC, 'runIds': ['a', 'b', 'c']}
                    kwargs['validate'](json.dumps(report))
                    report['appVersion'] = c.TARGET_VERSION
                    with self_test.assertRaises(ValueError):
                        kwargs['validate'](json.dumps(report))
            def help(self, *args): pass
            def datagram_help(self, *args): pass
        self_test = self
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = ['smoke', '--dart', str(root), '--cli-bundle', str(root),
                    '--observation-bundle', str(root), '--datagram-acceptance-bundle', str(root),
                    '--expected-version', RC]
            with patch('sys.argv', args), patch.object(smoke_cli, 'executable', side_effect=Path), \
                    patch.object(smoke_cli, 'bundle', side_effect=Path), \
                    patch.object(smoke_cli, 'bundle_executable', return_value=root / 'product'), \
                    patch.object(smoke_cli, 'Checks', Checks), \
                    patch.object(smoke_cli, 'business_checks'), \
                    patch.object(smoke_cli, 'nonempty_history_checks') as history:
                self.assertEqual(smoke_cli.main(), 0)
            self.assertEqual(len(history.call_args_list), 3)
            self.assertTrue(all(call.args[-1] == RC for call in history.call_args_list))
            probes = [cmd for name, cmd, _ in records if 'synthetic runCli/core recording' in name]
            self.assertEqual(len(probes), 2)
            self.assertTrue(all(cmd[-2:] == ['--expected-version', RC] for cmd in probes))
            versions = [kw['out'] for name, _, kw in records if name.endswith(': version')]
            self.assertEqual(versions, ['meshctl ' + RC + '\n'] * 3)

    def test_rc_nonempty_history_rejects_wrong_recorded_version(self):
        validators = []
        class Checks:
            def check(self, name, command, cwd, **kwargs):
                validators.append(kwargs['validate'])
        smoke_cli.nonempty_history_checks(Checks(), 'beta', ['product'], Path('/tmp'), Path('/tmp'), RC)
        run = {'appVersion': RC, 'preparedAt': '2026-11-16T00:00:00.000001Z',
               'cleanup': {'core': None, 'hostSubscriptions': False, 'aggregate': 0}}
        report = {'diagnosticSummaryFormatVersion': 1, 'exportedAt': 'time', 'runs': [run]}
        validators[-1](json.dumps(report))
        run['appVersion'] = c.TARGET_VERSION
        with self.assertRaises(ValueError):
            validators[-1](json.dumps(report))


if __name__ == '__main__':
    unittest.main()
