#!/usr/bin/env python3
"""Summarize retained RF evidence without contacting devices or the network."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re

from prepare_openhop_acceptance import validated_passive_report
from run_openhop_acceptance import attempt_accounting, case_send_limits, validate_content_length, _send_limit

BUILD_ID = '0.1.0-dev.2-macos-arm64-20261110T193252Z'
TRIAL_DIRECTORIES = [
    ('initial', 'matrix-results'), ('H2-followup', 'H2-followup-results'),
    ('H7-followup', 'H7-followup-results'), ('H2-command15', 'H2-command15-results'),
    ('H7-command15', 'H7-command15-results'),
    ('H2-command15-after-H7', 'H2-command15-after-H7-results'),
]
NATIVE_FILES = {'bin/meshctl', 'lib/liblibserialport_plus.dylib'}


def _cleanup(record):
    value = ((record or {}).get('final') or {}).get('cleanup') or (record or {}).get('cleanup')
    return value.get('state') if isinstance(value, dict) else value


def _counts(case):
    actual = case['applicationSendAttempts']
    if actual is not None and (type(actual) is not int or actual < 0):
        raise ValueError('Invalid recorded application attempt count.')
    known = case.get('knownApplicationSendAttempts', actual)
    upper = case.get('applicationSendAttemptUpperBound', actual)
    if type(known) is not int or type(upper) is not int or not 0 <= known <= upper:
        raise ValueError('Unknown sends require a known lower bound and reserved upper bound.')
    if actual is not None and (actual != known or actual != upper):
        raise ValueError('Conflicting application attempt counts.')
    records = case['allInvocations']
    limits = case_send_limits(case['id'])
    for record in records:
        if not re.fullmatch(r'[AB]-[1-9][0-9]*', record['label']):
            raise ValueError('Invocation does not belong to a permitted case endpoint.')
        if case['id'] == 'H6' and record['label'].startswith('B-'):
            raise ValueError('Invocation does not belong to a permitted case endpoint.')
    computed = attempt_accounting(records, case['id'], limits)
    counts = (computed['applicationSendAttempts'], computed['knownApplicationSendAttempts'],
              computed['applicationSendAttemptUpperBound'])
    if (actual, known, upper) != counts:
        raise ValueError('Cached send totals disagree with retained invocation facts.')
    if ('applicationSendAttemptsKnown' in case and
            case['applicationSendAttemptsKnown'] is not computed['applicationSendAttemptsKnown']):
        raise ValueError('Cached send certainty disagrees with retained invocation facts.')
    return counts


def _check_boundary_content(case):
    if case['id'] != 'H5':
        return
    initiators = [r for r in case['allInvocations'] if r['label'].startswith('A-')]
    if case['contentBytes'] != 131 or (case['status'] == 'PASS' and not initiators):
        raise ValueError('Boundary evidence requires an actual 131-byte initiating command.')
    for record in initiators:
        argv = record['argv']
        if argv[1:3] != ['datagram', 'ping']:
            raise ValueError('Boundary evidence requires the expected A ping command.')
        _send_limit('ping', argv[3:], 1)
        validate_content_length('H5', 'ping', argv[3:], case['contentBytes'])


def _reconcile_process_metadata(directory, cases):
    represented = {}
    for case in cases:
        for invocation in case['allInvocations']:
            key = (case['id'], invocation['label'])
            if key in represented:
                raise ValueError('Duplicate process invocation in retained case results.')
            represented[key] = invocation
    captures = []
    for path in sorted(directory.glob('*/*.process.json')):
        key = (path.parent.name, path.name.removesuffix('.process.json'))
        invocation = represented.get(key)
        if invocation is None:
            raise ValueError('Process metadata is unrepresented in case results; accounting is incomplete.')
        content = path.read_bytes()
        metadata = json.loads(content)
        if not isinstance(metadata, dict):
            raise ValueError('Invalid process metadata.')
        # Initial metadata need not have final facts yet. Every fact it does
        # contain must agree; stale results cannot silently hide a later state.
        for field in ('label', 'pid', 'argv', 'startedUtc', 'expectedExitCode',
                      'endedUtc', 'actualExitCode', 'cleanup', 'final', 'events'):
            if field in metadata and metadata[field] != invocation.get(field):
                raise ValueError('Process metadata disagrees with its retained invocation.')
        captures.append({'path': str(path), 'sha256': hashlib.sha256(content).hexdigest()})
    return captures


def _check_execution_directory_coverage(folder):
    registered = {folder / name for _, name in TRIAL_DIRECTORIES}
    markers = {'execution-plan.json', 'results.json', 'STOPPED.json'}
    for path in folder.rglob('*'):
        if path.is_symlink():
            raise ValueError('Symbolic evidence entries cannot establish complete execution coverage.')
        if not path.is_file():
            continue
        if path.name.endswith('.process.json'):
            execution = path.parent.parent
        elif path.name in markers:
            execution = path.parent
        else:
            continue
        if execution not in registered:
            raise ValueError('Unregistered execution evidence must be reconciled before summarizing sends.')


def build_summary(folder, candidate=None):
    folder = Path(folder).resolve()
    _check_execution_directory_coverage(folder)
    root = Path(__file__).resolve().parents[1]
    candidate = Path(candidate) if candidate is not None else root / 'build/phase-1b9/20261110T193252Z/delivery' / BUILD_ID
    trials, captures = [], []
    captured_hashes = None
    for label, name in TRIAL_DIRECTORIES:
        directory = folder / name
        path = directory / 'results.json'
        stop_path = directory / 'STOPPED.json'
        if not path.exists():
            if stop_path.exists() or list(directory.glob('*/*.process.json')):
                raise ValueError('Unsettled trial lacks case results; do not omit its sends.')
            continue
        manifest_path = directory / 'execution-plan.json'
        manifest_bytes = manifest_path.read_bytes()
        hashes = json.loads(manifest_bytes)['nativeHashes']
        if (not isinstance(hashes, dict) or set(hashes) != NATIVE_FILES
                or any(not isinstance(v, str) or not re.fullmatch(r'[0-9a-f]{64}', v) for v in hashes.values())):
            raise ValueError('Missing or invalid captured native hashes.')
        if captured_hashes is not None and hashes != captured_hashes:
            raise ValueError('Trials refer to different native builds.')
        captured_hashes = dict(hashes)
        result_bytes = path.read_bytes()
        result = json.loads(result_bytes)
        process_captures = _reconcile_process_metadata(directory, result['cases'])
        captures.append({'executionPlan': str(manifest_path),
                         'executionPlanSha256': hashlib.sha256(manifest_bytes).hexdigest(),
                         'results': str(path), 'resultsSha256': hashlib.sha256(result_bytes).hexdigest(),
                         'processMetadata': process_captures})
        if stop_path.exists():
            stopped = json.loads(stop_path.read_text())
            stopped_case = next((c for c in result['cases'] if c['id'] == stopped.get('caseId')), None)
            if stopped_case is None or stopped_case['status'] == 'PASS':
                raise ValueError('Stopped execution lacks a retained failed or blocked case.')
        for case in result['cases']:
            _check_boundary_content(case)
            actual, known, upper = _counts(case)
            invocations = case['allInvocations']
            a = next((r for r in reversed(invocations) if r['label'].startswith('A-')), None)
            b = next((r for r in reversed(invocations) if r['label'].startswith('B-')), None)
            pending = actual is None or any(r['actualExitCode'] is None for r in invocations)
            failed_cleanup = any(_cleanup(r) != 'succeeded' for r in invocations)
            status = 'BLOCKED' if pending else 'FAIL' if failed_cleanup else case['status']
            starts = [r['startedUtc'] for r in invocations]
            ends = [r['endedUtc'] for r in invocations if r.get('endedUtc') is not None]
            trial = {**case, 'status': status, 'trial': label, 'evidence': str(path),
                     'startedUtc': case.get('startedUtc') or (min(starts) if starts else None),
                     'endedUtc': None if pending else case.get('endedUtc') or (max(ends) if ends else None),
                     'knownApplicationSendAttempts': known, 'applicationSendAttemptUpperBound': upper,
                     'aCleanupState': _cleanup(a), 'bCleanupState': _cleanup(b),
                     'finalA': None if a is None else a.get('final'),
                     'finalB': None if b is None else b.get('final')}
            if trial['startedUtc'] is None:
                raise ValueError('Trial lacks a recorded start time.')
            trials.append(trial)
    if captured_hashes is None:
        raise ValueError('No captured native evidence was found.')
    current_hashes = {name: hashlib.sha256((candidate / name).read_bytes()).hexdigest() for name in captured_hashes}
    if current_hashes != captured_hashes:
        raise ValueError('Current candidate differs from captured trial native hashes; revalidation is required.')
    latest = {}
    for trial in sorted(trials, key=lambda t: t['startedUtc']):
        latest[trial['id']] = trial
    cases = []
    for case_id in ('H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'H7'):
        trial = latest.get(case_id)
        if trial is None:
            cases.append({'id': case_id, 'status': 'NOT_RUN'})
            continue
        a, b = trial['finalA'] or {}, trial['finalB'] or {}
        ar, br = a.get('result') or {}, b.get('result') or {}
        ping = ar if case_id in ('H3', 'H5', 'H6') else br if case_id in ('H4', 'H7') else {}
        cases.append({k: trial[k] for k in ('id', 'status', 'trial', 'expectedAExit', 'actualAExit',
                     'expectedBExit', 'actualBExit', 'contentBytes', 'signalAfterExactPong', 'evidence')} | {
            'applicationRttUs': ping.get('applicationRttUs'), 'roundTripSucceeded': ping.get('roundTripSucceeded'),
            'exactContentValidated': ping.get('exactContentValidated'),
            'aCleanup': a.get('cleanup') or (None if trial['aCleanupState'] is None else {'state': trial['aCleanupState']}),
            'bCleanup': b.get('cleanup') or (None if trial['bCleanupState'] is None else {'state': trial['bCleanupState']}),
            'aResultReason': ar.get('reason'), 'bResultReason': br.get('reason')})
    approval_path = folder / 'comparison-authorization.json'
    approval_bytes = approval_path.read_bytes() if approval_path.exists() else None
    approval = json.loads(approval_bytes) if approval_bytes is not None else None
    ceiling = 15 if approval and approval.get('approvedGlobalCeiling') == 15 else 12
    known = sum(t['knownApplicationSendAttempts'] for t in trials)
    upper = sum(t['applicationSendAttemptUpperBound'] for t in trials)
    actual = known if all(t['applicationSendAttempts'] is not None for t in trials) else None
    if known > ceiling:
        raise ValueError('Recorded attempts exceed the authorized ceiling.')
    comparison, comparison_upper = {}, {}
    for case_id, limit in (('H2', 1), ('H7', 3)):
        selected = [t for t in trials if t['id'] == case_id and 'command15' in t['trial']]
        lower = sum(t['knownApplicationSendAttempts'] for t in selected)
        comparison[case_id] = lower if all(t['applicationSendAttempts'] is not None for t in selected) else None
        comparison_upper[case_id] = sum(t['applicationSendAttemptUpperBound'] for t in selected)
        if lower > limit:
            raise ValueError('Recorded attempts exceed the per-case comparison allocation.')
    probe = validated_passive_report(json.loads((folder / 'idle-probe-after-client-release/result.json').read_text()), 90)
    blocked = actual is None or upper > ceiling or any(t['status'] == 'BLOCKED' for t in trials)
    return {'schemaVersion': 2, 'recordedUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'status': 'BLOCKED' if blocked else 'PASS_WITH_RETAINED_FAILURES' if all(c['status'] == 'PASS' for c in cases) else 'PARTIAL_WITH_FAILURES',
            'buildId': BUILD_ID, 'nativeHashes': captured_hashes,
            'nativeEvidence': {'hashSource': 'Captured per-execution native hashes',
                               'currentCandidateMatches': True, 'captures': captures},
            'selectedSlots': {'aSend': 1, 'aReceive': 1, 'bSend': 3, 'bReceive': 3},
            'routes': {'A': {'descriptor': 0, 'path': ''}, 'B': {'descriptor': 0, 'path': ''}},
            'effectiveConfiguredIdleTimeoutSeconds': None,
            'verifiedPassiveWindowSeconds': probe['verifiedIdleWindowLowerBoundSeconds'],
            'actualApplicationSendAttempts': actual, 'knownApplicationSendAttempts': known,
            'applicationSendAttemptUpperBound': upper, 'authorizedApplicationSendAttemptCeiling': ceiling,
            'commandBudgetComparison': {'authorization': 'APPROVED' if approval else 'PENDING',
                'authorizationRecordedUtc': None if approval is None else approval['recordedUtc'],
                'authorizationEvidenceSha256': None if approval_bytes is None else hashlib.sha256(approval_bytes).hexdigest(),
                'aCommandSeconds': 5, 'bCommandSeconds': 15, 'applicationSendAttemptsByCase': comparison,
                'applicationSendAttemptUpperBoundByCase': comparison_upper,
                'maximumApplicationSendAttemptsByCase': {'H2': 1, 'H7': 3}},
            'allTrials': trials, 'latestCaseResults': cases,
            'retainedFailedTrials': [{'id': t['id'], 'trial': t['trial'], 'evidence': t['evidence']} for t in trials if t['status'] != 'PASS'],
            'conditional': {'specifiedRelayPath': 'NOT_RUN', 'physicalReadyUsbUnplug': 'NOT_RUN'},
            'evidenceBoundary': 'Native Meshchan USB CLI and openHop virtual Companion through real LoRa; shared Meshchan diagnostic core, not independent application implementations',
            'publicDistribution': 'NOT_READY', 'historicalUsbCauseFixed': False,
            'credentialsOrRawUserMessagesIncluded': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--candidate', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        summary = build_summary(args.directory, args.candidate)
    except (ValueError, KeyError, TypeError, OSError):
        parser.error('Evidence validation failed; verify native hashes, process coverage, stopped trials, and passive-window proof.')
    path = args.output or args.directory / 'rf-summary.json'
    path.write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps({'summary': str(path), 'status': summary['status'],
                      'actualApplicationSendAttempts': summary['actualApplicationSendAttempts'],
                      'latestResults': [{'id': c['id'], 'status': c['status'], 'trial': c.get('trial')}
                                        for c in summary['latestCaseResults']]}, indent=2))


if __name__ == '__main__':
    main()
