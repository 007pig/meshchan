"""Offline evidence-binding and incomplete-trial regressions."""
import copy
import contextlib
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import summarize_openhop_acceptance as summary


class SummaryTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='meshchan-summary-test-')
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.candidate = self.folder / 'candidate'
        self.hashes = {}
        for name in summary.NATIVE_FILES:
            path = self.candidate / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(('synthetic ' + name).encode())
            self.hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        probe = self.folder / 'idle-probe-after-client-release/result.json'
        probe.parent.mkdir()
        self.probe = {'exitCode': 0, 'status': 'PASS', 'cleanup': 'succeeded',
                      'noHostCommandsDuringObservation': True, 'verifiedIdleWindowLowerBoundSeconds': 95}
        probe.write_text(json.dumps({'actualExitCode': 0, 'report': self.probe}))
        self.case = {
            'id': 'H2', 'status': 'PASS', 'expectedAExit': 0, 'actualAExit': 0,
            'expectedBExit': 0, 'actualBExit': 0, 'contentBytes': 15,
            'signalAfterExactPong': False, 'applicationSendAttempts': 1,
            'allInvocations': [self.invocation('A-1', 'listen', 0), self.invocation('B-1', 'send', 1)],
        }
        self.write_trial('matrix-results', self.case)

    def invocation(self, label, operation, attempts, cleanup='succeeded'):
        return {'label': label, 'startedUtc': '2026-11-11T00:00:00Z',
                'endedUtc': '2026-11-11T00:00:01Z', 'actualExitCode': 0,
                'final': {'operation': operation, 'cleanup': {'state': cleanup},
                          'result': {'responseAttempts': attempts} if operation == 'respond'
                                    else {'send': {'attempted': bool(attempts)}}}}

    def write_trial(self, name, case, hashes=None):
        directory = self.folder / name
        directory.mkdir(exist_ok=True)
        (directory / 'execution-plan.json').write_text(json.dumps({'nativeHashes': hashes or self.hashes}))
        (directory / 'results.json').write_text(json.dumps({'cases': [case]}))
        return directory

    def test_native_hashes_come_from_captures_and_current_bytes_must_match(self):
        result = summary.build_summary(self.folder, self.candidate)
        self.assertEqual(result['nativeHashes'], self.hashes)
        self.assertEqual(result['nativeEvidence']['hashSource'], 'Captured per-execution native hashes')
        self.assertTrue(result['nativeEvidence']['currentCandidateMatches'])
        self.assertEqual(len(result['nativeEvidence']['captures']), 1)
        self.assertEqual(result['actualApplicationSendAttempts'], 1)

    def test_flat_passive_probe_evidence_is_also_accepted(self):
        (self.folder / 'idle-probe-after-client-release/result.json').write_text(json.dumps(self.probe))
        result = summary.build_summary(self.folder, self.candidate)
        self.assertEqual(result['verifiedPassiveWindowSeconds'], 95)

    def test_replaced_candidate_rejects_without_overwriting_a_previous_summary(self):
        (self.candidate / 'bin/meshctl').write_bytes(b'replacement; never executed')
        output = self.folder / 'preserved-summary.json'
        output.write_text('preserved earlier evidence\n')
        with self.assertRaisesRegex(ValueError, 'differs from captured'):
            summary.build_summary(self.folder, self.candidate)
        with patch.object(sys, 'argv', ['summary', '--directory', str(self.folder),
                                      '--candidate', str(self.candidate), '--output', str(output)]), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as caught:
                summary.main()
        self.assertEqual(caught.exception.code, 2)
        self.assertEqual(output.read_text(), 'preserved earlier evidence\n')

    def test_mixed_or_missing_execution_captures_cannot_pass(self):
        other = dict(self.hashes)
        other['lib/liblibserialport_plus.dylib'] = '0' * 64
        directory = self.write_trial('H2-followup-results', self.case, other)
        with self.assertRaisesRegex(ValueError, 'different native builds'):
            summary.build_summary(self.folder, self.candidate)
        (directory / 'execution-plan.json').unlink()
        with self.assertRaises(FileNotFoundError):
            summary.build_summary(self.folder, self.candidate)

    def test_pending_trial_retains_unknown_sends_and_blocks_summary(self):
        case = copy.deepcopy(self.case)
        case.update(id='H7', status='BLOCKED', applicationSendAttempts=None,
                    knownApplicationSendAttempts=1, applicationSendAttemptUpperBound=2)
        case['allInvocations'][0]['final']['operation'] = 'respond'
        case['allInvocations'][0]['final']['result'] = {'responseAttempts': 1}
        case['allInvocations'][1].update(final=None, actualExitCode=None, endedUtc=None,
                                        cleanup={'state': 'pending'})
        directory = self.write_trial('H7-followup-results', case)
        (directory / 'STOPPED.json').write_text(json.dumps({'caseId': 'H7', 'status': 'BLOCKED'}))
        result = summary.build_summary(self.folder, self.candidate)
        self.assertEqual(result['status'], 'BLOCKED')
        self.assertIsNone(result['actualApplicationSendAttempts'])
        self.assertEqual(result['knownApplicationSendAttempts'], 2)
        self.assertEqual(result['applicationSendAttemptUpperBound'], 3)
        self.assertEqual(result['latestCaseResults'][-1]['bCleanup'], {'state': 'pending'})
        self.assertEqual(result['retainedFailedTrials'][0]['id'], 'H7')

    def test_stopped_trial_without_results_is_not_silently_omitted(self):
        directory = self.folder / 'H7-followup-results'
        directory.mkdir()
        (directory / 'STOPPED.json').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'lacks case results'):
            summary.build_summary(self.folder, self.candidate)

    def test_failed_cleanup_cannot_keep_a_cached_pass(self):
        case = copy.deepcopy(self.case)
        case['allInvocations'][1]['final']['cleanup']['state'] = 'failed'
        self.write_trial('matrix-results', case)
        result = summary.build_summary(self.folder, self.candidate)
        self.assertEqual(result['latestCaseResults'][1]['status'], 'FAIL')
        self.assertEqual(result['actualApplicationSendAttempts'], 1)

    def test_partial_results_cannot_omit_later_process_metadata(self):
        for case_id, label, extra in [('H3', 'B-1', {}),
                                      ('H3', 'B-1', {'actualExitCode': 0, 'final': {'result': {'send': {'attempted': True}}}}),
                                      ('H2', 'A-2', {})]:
            with self.subTest(case_id=case_id, label=label, extra=extra):
                directory = self.folder / 'matrix-results' / case_id
                directory.mkdir(exist_ok=True)
                path = directory / (label + '.process.json')
                path.write_text(json.dumps({'argv': ['synthetic'], 'startedUtc': '2026-11-11T00:00:02Z', **extra}))
                try:
                    with self.assertRaises(ValueError):
                        summary.build_summary(self.folder, self.candidate)
                finally:
                    path.unlink()

    def test_represented_metadata_must_match_invocation_identity_and_final_facts(self):
        directory = self.folder / 'matrix-results/H2'
        directory.mkdir()
        record = {**self.case['allInvocations'][0], 'pid': 900001, 'argv': ['synthetic']}
        self.case['allInvocations'][0] = record
        self.write_trial('matrix-results', self.case)
        path = directory / 'A-1.process.json'
        path.write_text(json.dumps(record))
        result = summary.build_summary(self.folder, self.candidate)
        self.assertEqual(len(result['nativeEvidence']['captures'][0]['processMetadata']), 1)
        for field, value in [('pid', 900002), ('argv', ['different']), ('final', None),
                             ('cleanup', {'state': 'pending'})]:
            with self.subTest(field=field):
                path.write_text(json.dumps({**record, field: value}))
                with self.assertRaises(ValueError):
                    summary.build_summary(self.folder, self.candidate)

    def test_unregistered_execution_directories_never_restore_send_allowance(self):
        for relative in ('execution-plan.json', 'results.json', 'STOPPED.json', 'H7/B-1.process.json'):
            with self.subTest(relative=relative):
                directory = self.folder / 'fresh-unregistered-followup'
                path = directory / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('{}')
                try:
                    with self.assertRaises(ValueError):
                        summary.build_summary(self.folder, self.candidate)
                finally:
                    path.unlink()

    def test_unregistered_stopped_sender_does_not_overwrite_previous_summary(self):
        directory = self.folder / 'new-output/H7'
        directory.mkdir(parents=True)
        (directory / 'B-1.process.json').write_text(json.dumps({'actualExitCode': None}))
        output = self.folder / 'preserved-summary.json'
        output.write_text('previous report\n')
        with patch.object(sys, 'argv', ['summary', '--directory', str(self.folder),
                                      '--candidate', str(self.candidate), '--output', str(output)]), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as caught:
                summary.main()
        self.assertEqual(caught.exception.code, 2)
        self.assertEqual(output.read_text(), 'previous report\n')

    def test_cached_send_totals_must_agree_with_invocation_facts(self):
        for actual, known, upper in [(0, 0, 0), (2, 2, 2), (None, 0, 1)]:
            with self.subTest(actual=actual, known=known, upper=upper):
                case = copy.deepcopy(self.case)
                case.update(applicationSendAttempts=actual, knownApplicationSendAttempts=known,
                            applicationSendAttemptUpperBound=upper)
                self.write_trial('matrix-results', case)
                with self.assertRaises(ValueError):
                    summary.build_summary(self.folder, self.candidate)
        output = self.folder / 'previous-summary.json'
        output.write_text('preserved earlier evidence\n')
        with patch.object(sys, 'argv', ['summary', '--directory', str(self.folder),
                                      '--candidate', str(self.candidate), '--output', str(output)]), \
                contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as caught:
                summary.main()
        self.assertEqual(caught.exception.code, 2)
        self.assertEqual(output.read_text(), 'preserved earlier evidence\n')

    def test_unknown_sender_cannot_restore_quota_with_cached_zero_counts(self):
        case = copy.deepcopy(self.case)
        case['allInvocations'][1].update(final=None, actualExitCode=None, endedUtc=None,
                                        cleanup={'state': 'pending'})
        case.update(applicationSendAttempts=0, knownApplicationSendAttempts=0,
                    applicationSendAttemptUpperBound=0)
        self.write_trial('matrix-results', case)
        with self.assertRaises(ValueError):
            summary.build_summary(self.folder, self.candidate)
        case.update(status='BLOCKED', applicationSendAttempts=None,
                    applicationSendAttemptUpperBound=1)
        self.write_trial('matrix-results', case)
        result = summary.build_summary(self.folder, self.candidate)
        self.assertEqual(result['status'], 'BLOCKED')
        self.assertIsNone(result['actualApplicationSendAttempts'])
        self.assertEqual(result['knownApplicationSendAttempts'], 0)
        self.assertEqual(result['applicationSendAttemptUpperBound'], 1)

    def test_responder_retries_and_legacy_read_only_send_fields_are_reconciled(self):
        # Old listen reports may contain a misleading send field; they remain
        # read-only. Every actual responder invocation still contributes.
        self.case['allInvocations'][0]['final']['result']['send']['attempted'] = True
        self.write_trial('matrix-results', self.case)
        self.assertEqual(summary.build_summary(self.folder, self.candidate)['actualApplicationSendAttempts'], 1)
        case = copy.deepcopy(self.case)
        case.update(id='H7', applicationSendAttempts=3)
        case['allInvocations'] = [self.invocation('A-1', 'respond', 1),
                                  self.invocation('A-2', 'respond', 1),
                                  self.invocation('B-1', 'ping', 1)]
        self.write_trial('H7-followup-results', case)
        result = summary.build_summary(self.folder, self.candidate)
        self.assertEqual(result['actualApplicationSendAttempts'], 4)
        case['applicationSendAttempts'] = 2
        self.write_trial('H7-followup-results', case)
        with self.assertRaises(ValueError):
            summary.build_summary(self.folder, self.candidate)

    def test_h5_boundary_is_bound_to_retained_transmitting_arguments(self):
        case = copy.deepcopy(self.case)
        case.update(id='H5', contentBytes=131, applicationSendAttempts=2)
        case['allInvocations'] = [self.invocation('A-1', 'ping', 1), self.invocation('B-1', 'respond', 1)]
        a = case['allInvocations'][0]
        a['argv'] = [str(self.candidate / 'bin/meshctl'), 'datagram', 'ping',
                     '--route-descriptor=0', '--path-hex=', '--content-hex=' + '00' * 131]
        self.write_trial('matrix-results', case)
        self.assertEqual(summary.build_summary(self.folder, self.candidate)['latestCaseResults'][4]['contentBytes'], 131)
        a['argv'][-1] = '--content-hex=00'
        for count in (131, 1):
            with self.subTest(contentBytes=count):
                case['contentBytes'] = count
                self.write_trial('matrix-results', case)
                with self.assertRaises(ValueError):
                    summary.build_summary(self.folder, self.candidate)


if __name__ == '__main__':
    unittest.main()
