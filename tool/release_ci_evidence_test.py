import io
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch
from zipfile import ZipFile

import release_ci_evidence as evidence


SOURCE = 'a' * 40
MERGE = 'b' * 40
WORKFLOW = b'name: CI\n'
STARTED = '2026-11-21T12:00:00Z'
COMPLETED = '2026-11-21T12:05:00Z'
INPUTS = {'tool/ci_evidence.py': 'd' * 64, 'pubspec.lock': 'e' * 64}


class EvidenceTest(unittest.TestCase):
    def setUp(self):
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def responses(self, expected, *, checked_ref=None):
        run = {'id': expected.run_id, 'run_attempt': expected.attempt, 'event': expected.event,
               'head_sha': expected.head_sha, 'repository': {'id': 17, 'full_name': expected.repository},
               'path': evidence.WORKFLOW, 'status': 'completed', 'conclusion': 'success',
               'workflow_id': 123, 'check_suite_id': 23, 'head_branch': 'main', 'run_started_at': STARTED}
        if checked_ref is None:
            checked_ref = 'refs/remotes/pull/46/merge' if expected.event == 'pull_request' else 'refs/remotes/origin/main'
        jobs = []
        for identifier, (name, label) in enumerate(evidence.JOBS.items(), start=30):
            jobs.append({'id': identifier, 'name': name, 'run_id': expected.run_id,
                         'run_attempt': expected.attempt, 'head_sha': expected.head_sha,
                         'run_url': evidence.API + expected.endpoint, 'labels': [label], 'status': 'completed',
                         'conclusion': 'success', 'started_at': STARTED, 'completed_at': COMPLETED,
                         'steps': [{'name': 'Upload CI job evidence', 'conclusion': 'success'}]})
        logs = io.BytesIO()
        with ZipFile(logs, 'w') as archive:
            for identifier, job in enumerate(evidence.JOBS):
                log = (f'{STARTED} [command]/usr/bin/git checkout --force {checked_ref}\n'
                       f'{STARTED} [command]/usr/bin/git log -1 --format=%H\n'
                        f'{STARTED} {expected.source}\n')
                archive.writestr(f'{identifier}_{job}.txt', log)
        self.records = {expected.endpoint: run, expected.attempt_endpoint: dict(run),
                        expected.attempt_endpoint + '/jobs?per_page=100&page=1':
                            {'total_count': len(jobs), 'jobs': jobs},
                        expected.attempt_endpoint + '/logs': logs.getvalue(),
                        f'repos/{expected.repository}/contents/{evidence.WORKFLOW}?ref={expected.source}': WORKFLOW,
                        expected.endpoint + '/artifacts?per_page=100&page=1':
                            {'total_count': 0, 'artifacts': []}}
        if expected.event == 'pull_request':
            self.records[f'repos/{expected.repository}/git/commits/{expected.source}'] = {
                'sha': expected.source, 'parents': [{'sha': 'c' * 40}, {'sha': expected.head_sha}]}
        if expected.require_artifacts:
            self.add_artifacts(expected)
        return self.records

    def add_artifacts(self, expected):
        artifacts = []
        for identifier, job in enumerate(evidence.JOBS, start=100):
            zip_bytes = io.BytesIO()
            with ZipFile(zip_bytes, 'w') as archive:
                archive.writestr('report.json', '{}')
            data = zip_bytes.getvalue()
            endpoint = f'repos/{expected.repository}/actions/artifacts/{identifier}/zip'
            artifacts.append({'id': identifier, 'workflow_run': {'id': expected.run_id,
                              'head_sha': expected.head_sha, 'repository_id': 17},
                              'name': f'meshchan-ci-{expected.source}-{expected.run_id}-{expected.attempt}-{job}',
                              'size_in_bytes': len(data), 'digest': f'sha256:{evidence.sha256(data)}',
                              'archive_download_url': evidence.API + endpoint, 'expired': False,
                              'created_at': STARTED, 'expires_at': '9999-11-21T12:00:00Z'})
            self.records[endpoint] = data
        self.records[expected.endpoint + '/artifacts?per_page=100&page=1'] = {
            'total_count': len(artifacts), 'artifacts': artifacts}

    def github(self, command, **options):
        value = self.records[command[-1]]
        data = value if isinstance(value, bytes) else json.dumps(value).encode()
        return subprocess.CompletedProcess(command, 0, data, b'')

    def expected(self, event='push', artifacts=False):
        return evidence.Attempt('007pig/meshchan', MERGE if event == 'pull_request' else SOURCE,
                                event, SOURCE, evidence.sha256(WORKFLOW), 1000, 2, artifacts)

    def verify(self, path, pin, expected, **options):
        return evidence.verify_snapshot(path, pin, source=expected.source, event=expected.event,
                                        head_sha=expected.head_sha, workflow_sha256=expected.workflow_sha256,
                                        require_artifacts=expected.require_artifacts, run_id=expected.run_id,
                                        attempt=expected.attempt, **options)

    def collect(self, path, expected, message=None):
        with patch.object(evidence.subprocess, 'run', side_effect=self.github):
            if message is None:
                return evidence.collect(path, expected)
            with self.assertRaisesRegex(ValueError, message):
                evidence.collect(path, expected)
        self.assertFalse((path / evidence.MANIFEST).exists())
        self.assertTrue((path / 'collection-error.txt').is_file())

    def test_historical_collection_and_offline_verification_require_external_pins(self):
        expected = self.expected()
        self.responses(expected)
        target = self.root / 'collected snapshot'
        pin = self.collect(target, expected)
        result = self.verify(target, pin, expected)
        self.assertEqual(result['source'], SOURCE)
        self.assertEqual(result['artifacts'], [])
        self.assertEqual(result['listed_artifacts'], 0)
        self.assertEqual(result['jobs'], {'check': 30, 'macos-app': 31})
        self.assertEqual((target / 'workflow.yml').read_bytes(), WORKFLOW)
        self.assertNotIn('toolchain', result)
        with self.assertRaisesRegex(ValueError, 'external digest'):
            self.verify(target, '0' * 64, expected)
        with self.assertRaises(FileExistsError):
            self.collect(target, expected)
        (target / 'logs.zip').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'Pinned CI evidence differs'):
            self.verify(target, pin, expected)

    def test_all_required_jobs_and_run_attempt_must_be_successful(self):
        expected = self.expected()
        for index, (field, value) in enumerate([('status', 'queued'), ('status', 'in_progress'),
                                                ('conclusion', 'failure'), ('conclusion', 'cancelled')]):
            records = self.responses(expected)
            records[expected.attempt_endpoint][field] = value
            self.collect(self.root / f'run-{index}', expected, 'completed with a success conclusion')
        records = self.responses(expected)
        records[expected.endpoint]['run_attempt'] = 1
        self.collect(self.root / 'attempt unavailable', expected, 'different attempt number')
        records = self.responses(expected)
        records[expected.attempt_endpoint]['run_attempt'] = 1
        self.collect(self.root / 'mismatched attempt', expected, 'different attempt number')
        records = self.responses(expected)
        jobs = records[expected.attempt_endpoint + '/jobs?per_page=100&page=1']
        jobs['jobs'][0]['run_attempt'] = 1
        self.collect(self.root / 'mixed job attempts', expected, 'wrong run, attempt')
        jobs['jobs'].pop(0)
        jobs['total_count'] = 1
        self.collect(self.root / 'missing job', expected, 'Missing or unexpected')

    def test_earlier_successful_attempt_can_be_collected_after_rerun(self):
        expected = self.expected()
        for status, conclusion in [('queued', None), ('completed', 'failure')]:
            records = self.responses(expected)
            records[expected.endpoint].update(run_attempt=3, status=status, conclusion=conclusion,
                                              run_started_at='2026-11-21T12:10:00Z')
            target = self.root / status
            pin = self.collect(target, expected)
            result = self.verify(target, pin, expected)
            self.assertEqual(result['attempt'], 2)

    def test_workflow_and_pr_checkout_are_bound_separately_from_head(self):
        expected = self.expected('pull_request')
        records = self.responses(expected)
        target = self.root / 'merge snapshot'
        pin = self.collect(target, expected)
        result = self.verify(target, pin, expected)
        self.assertEqual(result['pull_request_number'], 46)
        self.assertEqual(result['head_sha'], SOURCE)
        self.assertEqual(result['source'], MERGE)
        with self.assertRaisesRegex(ValueError, 'distinct checkout'):
            evidence.verify_snapshot(target, pin, source=SOURCE, event='pull_request', head_sha=SOURCE,
                                     workflow_sha256=expected.workflow_sha256, require_artifacts=False)
        records[f'repos/{expected.repository}/contents/{evidence.WORKFLOW}?ref={MERGE}'] = b'new workflow'
        self.collect(self.root / 'wrong workflow content', expected, 'workflow bytes differ')
        records = self.responses(expected)
        records[expected.attempt_endpoint]['path'] = '.github/workflows/another.yml'
        self.collect(self.root / 'wrong workflow path', expected, 'workflow identity')

    def test_pagination_keeps_all_pages_and_rejects_incomplete_or_repeated_data(self):
        pages = {1: [{'id': i} for i in range(1, 101)], 2: [{'id': 101}, {'id': 102}]}

        def read(filename, endpoint):
            index = int(endpoint.rsplit('=', 1)[1])
            self.assertEqual(filename, f'artifacts-{index}.json')
            return json.dumps({'total_count': 102, 'artifacts': pages[index]}).encode()

        self.assertEqual(len(evidence.paginated(read, 'artifacts', 'artifacts')), 102)
        pages[2][0]['id'] = 100
        with self.assertRaisesRegex(ValueError, 'repeated'):
            evidence.paginated(read, 'artifacts', 'artifacts')
        pages[2].pop()
        with self.assertRaisesRegex(ValueError, 'Incomplete'):
            evidence.paginated(read, 'artifacts', 'artifacts')

    @staticmethod
    def verified_report(archive, *, job, **identity):
        return {'workflow_sha': SOURCE, 'job_id': {'check': 30, 'macos-app': 31}[job],
                'checkout_inputs': dict(INPUTS)}

    @patch('ci_evidence.verify_job_zip', side_effect=verified_report)
    def test_artifact_transport_verifies_outer_zip_and_binds_ci_report(self, verify_job_zip):
        expected = self.expected(artifacts=True)
        records = self.responses(expected)
        target = self.root / 'current snapshot'
        pin = self.collect(target, expected)
        result = self.verify(target, pin, expected)
        self.assertEqual(result, self.verify(target, pin, expected, checkout_inputs=INPUTS))
        with self.assertRaisesRegex(ValueError, 'input digests disagree'):
            self.verify(target, pin, expected, checkout_inputs=INPUTS | {'pubspec.lock': 'f' * 64})
        self.assertEqual([row['id'] for row in result['artifacts']], [100, 101])
        self.assertEqual(verify_job_zip.call_args.kwargs['checkout_sha'], SOURCE)
        self.assertEqual(verify_job_zip.call_args.kwargs['attempt'], 2)
        self.assertEqual(verify_job_zip.call_args.kwargs['requested_ref'], 'refs/heads/main')
        endpoint = f'repos/{expected.repository}/actions/artifacts/100/zip'
        records[endpoint] += b'altered bytes'
        verify_job_zip.reset_mock()
        self.collect(self.root / 'wrong download', expected, 'ZIP differs from its remote size or digest')
        verify_job_zip.assert_not_called()

    @patch('ci_evidence.verify_job_zip', side_effect=verified_report)
    def test_tag_ref_is_bound_to_checkout_logs_and_job_reports(self, verify_job_zip):
        expected = self.expected(artifacts=True)
        records = self.responses(expected, checked_ref='refs/tags/example-tag')
        records[expected.endpoint]['head_branch'] = 'example-tag'
        records[expected.attempt_endpoint]['head_branch'] = 'example-tag'
        target = self.root / 'tag snapshot'
        pin = self.collect(target, expected)
        self.verify(target, pin, expected)
        self.assertTrue(all(call.kwargs['requested_ref'] == 'refs/tags/example-tag'
                            for call in verify_job_zip.call_args_list))
        records[expected.endpoint]['head_branch'] = 'other-ref'
        records[expected.attempt_endpoint]['head_branch'] = 'other-ref'
        self.collect(self.root / 'wrong tag ref', expected, 'disagrees with the checked-out ref')

    def test_jobs_must_agree_on_ci_input_digests(self):
        expected = self.expected(artifacts=True)
        self.responses(expected)

        def report(archive, *, job, **identity):
            result = self.verified_report(archive, job=job, **identity)
            if job == 'macos-app':
                result['checkout_inputs']['pubspec.lock'] = 'f' * 64
            return result

        with patch('ci_evidence.verify_job_zip', side_effect=report):
            self.collect(self.root / 'mismatched input digests', expected, 'input digests disagree')

    def test_pr_artifact_parents_must_match_github_merge_commit(self):
        expected = self.expected('pull_request', artifacts=True)
        self.responses(expected)
        parents = ['c' * 40, expected.head_sha]

        def report(archive, *, job, **identity):
            result = self.verified_report(archive, job=job, **identity)
            result.update(workflow_sha=expected.source, checkout_parents=parents,
                          pull_request={'number': 46, 'head_sha': expected.head_sha,
                                        'merge_sha': expected.source})
            return result

        with patch('ci_evidence.verify_job_zip', side_effect=report):
            target = self.root / 'verified merge artifacts'
            self.verify(target, self.collect(target, expected), expected)
            parents[0] = 'f' * 40
            self.collect(self.root / 'wrong merge parent', expected, 'checkout parent list differs')

    @patch('ci_evidence.verify_job_zip', side_effect=verified_report)
    def test_expired_missing_and_unsuccessful_artifacts_are_not_evidence(self, verify_job_zip):
        expected = self.expected(artifacts=True)
        records = self.responses(expected)
        artifacts = records[expected.endpoint + '/artifacts?per_page=100&page=1']
        artifacts['artifacts'][0]['expired'] = True
        self.collect(self.root / 'expired', expected, 'was expired when collected')
        artifacts['artifacts'].pop(0)
        artifacts['total_count'] = 1
        self.collect(self.root / 'missing', expected, 'artifact is missing or duplicated')
        records = self.responses(expected)
        records[expected.attempt_endpoint + '/jobs?per_page=100&page=1']['jobs'][0]['steps'].clear()
        self.collect(self.root / 'failed upload', expected, 'No successful upload step')


if __name__ == '__main__':
    unittest.main()
