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
            'toolchain': {'compiler': 'Compiler version', 'python': {'version': '3.15.2'},
                          'flutter': {'version': 'Flutter version'}, 'dart': {'version': 'Dart version'}},
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
                log = (name + '\n').encode()
                path = name + '.log'
                self.logs[path] = log
                row['log'] = {'path': path, 'sha256': evidence.sha256(log), 'size': len(log)}
                row['exit_code'] = 0
            self.report['steps'].append(row)

    def verify(self, *, extra_log=None, extra_zip_member=None):
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
            archive.writestr('report.json', json.dumps(self.report))
            archive.writestr('logs.tar.gz', bundle.getvalue())
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


if __name__ == '__main__':
    unittest.main()
