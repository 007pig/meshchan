from contextlib import chdir, redirect_stderr
import gzip
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

import ci_evidence as evidence


class CIEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.job = 'check'
        self.workflow = b'name: CI\n'
        self.sha = 'a' * 40
        self.ref = 'refs/heads/codex/phase-1e8'
        self.identity = {
            'repository': '007pig/meshchan', 'event': 'push', 'job': self.job,
            'checkout_sha': self.sha, 'requested_sha': self.sha,
            'requested_ref': self.ref, 'run_id': 123, 'attempt': 1,
            'workflow_sha256': evidence.sha256(self.workflow),
        }
        self.report = {
            **self.identity, 'schema': 1, 'kind': 'meshchan-ci-job',
            'job_id': 456, 'scope': evidence.SCOPE[self.job],
            'workflow_path': evidence.WORKFLOW, 'workflow_sha': self.sha,
            'workflow_ref': f"007pig/meshchan/{evidence.WORKFLOW}@{self.ref}",
            'checkout_parents': ['b' * 40], 'pull_request': None,
            'runner': {'label': 'ubuntu-latest', 'os': 'Linux', 'arch': 'X64',
                       'uname_machine': 'x86_64', 'os_version': 'Runner OS', 'kernel': 'Kernel'},
            'toolchain': {
                'compiler': 'Compiler version', 'compiler_path': '/usr/bin/cc',
                'python': {'version': '3.15.2', 'executable': '/sdk/python3'},
                'flutter': {'executable': '/sdk/flutter/bin/flutter',
                            'version': {'frameworkVersion': '3.50.0', 'dartSdkVersion': '3.14.0',
                                        'channel': 'stable'}},
                'dart': {'version': 'Dart SDK version: 3.14.0 (stable)',
                         'executable': '/sdk/flutter/bin/dart'},
            },
            'checkout_inputs': {evidence.CAPTURE_TOOL: 'c' * 64, 'pubspec.lock': 'd' * 64},
            'artifact_retention_days_requested': evidence.RETENTION_DAYS,
            'evidence_errors': [],
            'steps': [],
        }
        self.logs = {}
        for name in evidence.SETUP + evidence.CHECKS[self.job]:
            row = {'id': name, 'outcome': 'success', 'conclusion': 'success',
                   'exit_code': None, 'log': None}
            if name in evidence.CHECKS[self.job]:
                log = ((json.dumps(self.report['toolchain']) if name == 'runner_toolchain' else name) + '\n').encode()
                path = name + '.log'
                self.logs[path] = log
                row['log'] = {'path': path, 'sha256': evidence.sha256(log), 'size': len(log)}
                row['exit_code'] = 0
            self.report['steps'].append(row)

    def verify(self, *, extra_log=None, extra_zip_member=None, log_payload=None, report_payload=None):
        bundle = io.BytesIO()
        with tarfile.open(fileobj=bundle, mode='w:gz') as archive:
            members = list(self.logs.items())
            if extra_log:
                members.append(extra_log)
            for name, data in members:
                entry = tarfile.TarInfo(name)
                entry.size = len(data)
                archive.addfile(entry, io.BytesIO(data))
        download = io.BytesIO()
        with zipfile.ZipFile(download, 'w') as archive:
            archive.writestr('workflow.yml', self.workflow)
            archive.writestr('report.json', json.dumps(self.report) if report_payload is None else report_payload)
            archive.writestr('logs.tar.gz', bundle.getvalue() if log_payload is None else log_payload(bundle.getvalue()))
            if extra_zip_member is not None:
                with warnings.catch_warnings():
                    warnings.simplefilter('ignore', UserWarning)
                    archive.writestr(extra_zip_member, b'extra')
        with zipfile.ZipFile(download) as archive:
            return evidence.verify_job_zip(archive, **self.identity)

    def test_pinned_job_log_and_workflow_bytes_pass(self):
        self.assertEqual(self.report, self.verify())

    def test_mismatched_attempt_source_and_workflow(self):
        for field, value in {'attempt': 2, 'workflow_path': '.github/workflows/unrelated.yml',
                             'checkout_sha': 'f' * 40}.items():
            with self.subTest(field=field), patch.dict(self.report, {field: value}):
                with self.assertRaisesRegex(ValueError, 'identity'):
                    self.verify()
        self.workflow = b'name: Replaced workflow\n'
        with self.assertRaisesRegex(ValueError, 'workflow bytes'):
            self.verify()

    def test_pull_request_preserves_head_and_merge_identities(self):
        head = 'b' * 40
        base = 'c' * 40
        self.ref = 'refs/pull/47/merge'
        self.identity.update(event='pull_request', requested_ref=self.ref)
        self.report.update(
            **self.identity,
            workflow_ref=f"007pig/meshchan/{evidence.WORKFLOW}@{self.ref}",
            checkout_parents=[base, head],
            pull_request={'number': 47, 'head_sha': head, 'base_sha': base, 'merge_sha': self.sha},
        )
        self.assertEqual(self.verify()['pull_request']['head_sha'], head)
        with patch.dict(self.report, {'checkout_parents': [head, base]}):
            with self.assertRaisesRegex(ValueError, 'merge checkout and PR head'):
                self.verify()
        for field, value in [('head_sha', self.sha), ('merge_sha', head)]:
            with self.subTest(field=field), patch.dict(self.report['pull_request'], {field: value}):
                with self.assertRaisesRegex(ValueError, 'merge checkout and PR head'):
                    self.verify()

    def test_pending_failed_or_skipped_check_cannot_be_successful_artifact(self):
        for outcome in ('not_run', 'skipped', 'failure', 'cancelled'):
            with self.subTest(outcome=outcome), patch.dict(
                self.report['steps'][-1], {'outcome': outcome},
            ):
                with self.assertRaisesRegex(ValueError, 'did not complete successfully'):
                    self.verify()
        self.report['steps'].pop()
        with self.assertRaisesRegex(ValueError, 'missing required steps'):
            self.verify()

    def test_log_archive_rejects_changed_missing_and_extra_content(self):
        log_name = next(iter(self.logs))
        changed = b'!' * len(self.logs[log_name])
        with patch.dict(self.logs, {log_name: changed}):
            with self.assertRaisesRegex(ValueError, 'log digest'):
                self.verify()
        for path in (log_name, '../outside.log'):
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, 'log archive'):
                self.verify(extra_log=(path, b''))
        with self.assertRaisesRegex(ValueError, 'ZIP'):
            self.verify(extra_zip_member='report.json')
        self.logs.pop(log_name)
        with self.assertRaisesRegex(ValueError, 'missing required logs'):
            self.verify()

    def test_log_archive_checks_the_tar_terminator_and_gzip_footer(self):
        def missing_end_block(data):
            raw = gzip.decompress(data)
            payload_end = len(raw.rstrip(b'\0'))
            size = (payload_end + tarfile.BLOCKSIZE - 1) // tarfile.BLOCKSIZE * tarfile.BLOCKSIZE
            return gzip.compress(raw[:size + tarfile.BLOCKSIZE])

        with self.assertRaisesRegex(ValueError, 'terminator or trailing data'):
            self.verify(log_payload=lambda data: gzip.compress(gzip.decompress(data) + b'trailing content'))
        with self.assertRaisesRegex(ValueError, 'terminator or trailing data'):
            self.verify(log_payload=missing_end_block)
        with self.assertRaisesRegex(ValueError, 'incomplete or malformed'):
            self.verify(log_payload=lambda data: data[:-4])

    def test_report_rejects_duplicate_json_fields(self):
        with self.assertRaisesRegex(ValueError, 'Duplicate JSON field: schema'):
            self.verify(report_payload='{"schema":2,' + json.dumps(self.report)[1:])

    def test_toolchain_requires_observed_versions_and_paths(self):
        toolchain = self.report['toolchain']
        with patch.dict(toolchain['python'], {'executable': 'python3'}):
            with self.assertRaisesRegex(ValueError, 'actual python executable path'):
                self.verify()
        with patch.dict(toolchain['dart'], {'version': 'Dart SDK version: 3.13.0 (stable)'}):
            with self.assertRaisesRegex(ValueError, 'Dart version differs from the Flutter SDK'):
                self.verify()

    def test_report_toolchain_matches_captured_probe(self):
        with patch.dict(self.report['toolchain']['python'], {'version': '3.15.1'}):
            with self.assertRaisesRegex(ValueError, 'toolchain differs from the captured probe'):
                self.verify()

    def test_wrapper_captures_pipeline_failure_and_skips_later_commands(self):
        with tempfile.TemporaryDirectory(prefix='meshchan CI ') as directory:
            root = Path(directory)
            capture = root / 'meshchan-ci-capture'
            capture.mkdir()
            script = root / 'check commands'
            script.write_text(
                "printf '%s\\n' beginning\n"
                "(printf '%s\\n' failing; exit 31) | cat\n"
                "printf '%s\\n' must-not-execute\n",
                encoding='utf-8',
            )
            env = dict(os.environ, RUNNER_TEMP=directory, GITHUB_JOB=self.job, GITHUB_ACTION='format')
            run = subprocess.run(
                [sys.executable, str(Path(evidence.__file__).resolve()), 'run', str(script)],
                env=env, capture_output=True, check=False,
            )
            self.assertEqual(run.returncode, 31)
            self.assertEqual(run.stdout, b'beginning\nfailing\n')
            self.assertEqual((capture / 'format.log').read_bytes(), run.stdout)
            self.assertEqual(json.loads((capture / 'format.json').read_bytes()), {'exit_code': 31})

    def test_missing_log_for_reported_success_includes_capture_error(self):
        with tempfile.TemporaryDirectory() as directory:
            steps, errors = evidence.step_report(
                self.job, {'format': {'outcome': 'success', 'conclusion': 'success'}}, Path(directory),
            )
        self.assertEqual(errors, ['Successful step is missing complete capture: format'])
        self.assertEqual(steps[0]['outcome'], 'not_run')

    def test_malformed_capture_preserves_log_for_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'format.log').write_bytes(b'captured output')
            (root / 'format.json').write_text('{"exit_code":false}', encoding='utf-8')
            steps, errors = evidence.step_report(
                self.job, {'format': {'outcome': 'success', 'conclusion': 'success'}}, root,
            )
        self.assertIn('Malformed step exit code capture: format', errors)
        row = next(step for step in steps if step['id'] == 'format')
        self.assertIsNone(row['exit_code'])
        self.assertEqual(row['log']['sha256'], evidence.sha256(b'captured output'))

    def test_unreadable_log_preserves_other_step_diagnostics_and_exit_code(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'format.log').write_bytes(b'format output')
            (root / 'format.json').write_text('{"exit_code":0}', encoding='utf-8')
            (root / 'analyze.log').write_bytes(b'analyzer failure')
            (root / 'analyze.json').write_text('{"exit_code":1}', encoding='utf-8')
            open_path = Path.open

            def open_log(path, *args, **kwargs):
                if path == root / 'format.log':
                    raise PermissionError('Unreadable capture')
                return open_path(path, *args, **kwargs)

            with patch.object(Path, 'open', open_log):
                steps, errors = evidence.step_report(self.job, {
                    'format': {'outcome': 'success', 'conclusion': 'success'},
                    'analyze': {'outcome': 'failure', 'conclusion': 'failure'},
                }, root)
        self.assertIn('Could not read captured step log: format', errors)
        self.assertIn('Successful step is missing complete capture: format', errors)
        rows = {row['id']: row for row in steps}
        self.assertIsNone(rows['format']['log'])
        self.assertEqual(rows['format']['exit_code'], 0)
        self.assertEqual(rows['analyze']['log']['sha256'], evidence.sha256(b'analyzer failure'))
        self.assertEqual(rows['analyze']['exit_code'], 1)

    def test_malformed_toolchain_metadata_can_be_reported_with_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'toolchain.json'
            errors = []
            self.assertIsNone(evidence.toolchain_report(path, self.job, 'failure', errors))
            self.assertEqual(errors, [])
            path.write_text('{')
            self.assertIsNone(evidence.toolchain_report(path, self.job, 'failure', errors))
            self.assertIn('Malformed toolchain probe report', errors[0])
            path.write_text(json.dumps(self.report['toolchain']))
            self.assertEqual(evidence.toolchain_report(path, self.job, 'success', []), self.report['toolchain'])

    def test_missing_lockfile_still_publishes_failed_job_diagnostics(self):
        capture_bytes = b'capture source'
        capture_log = b'Flutter could not resolve locked dependencies\n'
        for missing_from in ('checked-out commit', 'worktree'):
            with self.subTest(missing_from=missing_from), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                capture = root / 'meshchan-ci-capture'
                capture.mkdir()
                (capture / 'locked_dependencies.log').write_bytes(capture_log)
                checkout = root / 'worktree'
                source = checkout / evidence.CAPTURE_TOOL
                source.parent.mkdir(parents=True)
                source.write_bytes(capture_bytes)
                output = root / 'outputs'
                context = {'locked_dependencies': {'outcome': 'failure', 'conclusion': 'failure'}}
                env = {
                    'GITHUB_JOB': self.job, 'RUNNER_TEMP': str(root), 'GITHUB_OUTPUT': str(output),
                    'GITHUB_WORKFLOW_SHA': self.sha, 'GITHUB_WORKFLOW_REF': self.report['workflow_ref'],
                    'GITHUB_REPOSITORY': self.identity['repository'], 'GITHUB_EVENT_NAME': 'push',
                    'GITHUB_REF': self.ref, 'GITHUB_SHA': self.sha, 'GITHUB_RUN_ID': '123',
                    'GITHUB_RUN_ATTEMPT': '1', 'MESHCHAN_CI_CHECK_RUN_ID': '456',
                    'MESHCHAN_CI_STEPS': json.dumps(context), 'RUNNER_OS': 'Linux',
                    'RUNNER_ARCH': 'X64', 'MESHCHAN_CI_RUNNER_LABEL': 'ubuntu-latest',
                }

                def git_show(command, **kwargs):
                    name = command[-1].split(':', 1)[-1]
                    if name == 'pubspec.lock' and missing_from == 'checked-out commit':
                        raise subprocess.CalledProcessError(128, command)
                    return {evidence.WORKFLOW: self.workflow, evidence.CAPTURE_TOOL: capture_bytes,
                            'pubspec.lock': b'locked dependencies'}[name]

                with (chdir(checkout), patch.dict(os.environ, env),
                      patch.object(evidence.subprocess, 'check_output', side_effect=git_show),
                      patch.object(evidence, 'command_output', side_effect=[self.sha, '', 'x86_64']),
                      patch.object(evidence.platform, 'freedesktop_os_release', return_value={'PRETTY_NAME': 'Linux'}),
                      redirect_stderr(io.StringIO()) as stderr):
                    evidence.report_job()
                artifact = root / 'meshchan-ci-evidence'
                report = json.loads((artifact / 'report.json').read_bytes())
                message = f'Could not read CI input from the {missing_from}: pubspec.lock'
                self.assertIn(message, report['evidence_errors'])
                self.assertIn(message, stderr.getvalue())
                self.assertEqual('pubspec.lock' in report['checkout_inputs'], missing_from == 'worktree')
                self.assertEqual((artifact / 'workflow.yml').read_bytes(), self.workflow)
                self.assertIn('evidence_ok=false', output.read_text())
                with tarfile.open(artifact / 'logs.tar.gz', 'r:gz') as archive:
                    self.assertEqual(archive.extractfile('locked_dependencies.log').read(), capture_log)


if __name__ == '__main__':
    unittest.main()
