#!/usr/bin/env python3
"""Owned public-core history, worker drain, recovery and independent reopen."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import threading


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dart', required=True)
    parser.add_argument('--evidence-root', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    evidence = (args.evidence_root or Path(tempfile.mkdtemp(prefix='meshchan-history-'))).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    entry = root / 'apps/meshchan_app/tool/history_process.dart'

    def command(mode, fixture):
        return [args.dart, 'run', str(entry), mode, str(fixture)]

    def run(mode, fixture, label):
        result = subprocess.run(command(mode, fixture), cwd=evidence, capture_output=True, text=True, timeout=180)
        (evidence / (label + '.log')).write_text(result.stdout + result.stderr)
        result.check_returncode()
        report = json.loads(result.stdout.splitlines()[-1])
        if report.get('passed') is not True:
            raise RuntimeError('Missing pass')
        return report

    fixture = evidence / 'normal'
    run('seed', fixture, 'seed')
    run('normal', fixture, 'normal')
    if run('inspect', fixture, 'normal-reopen')['runs'] != 1:
        raise RuntimeError('Reopen mismatch')
    for mode in ['crash-prepared', 'crash-logical']:
        fixture = evidence / mode
        child = subprocess.Popen(command(mode, fixture), cwd=evidence, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        watchdog = threading.Timer(180, child.terminate)
        watchdog.start()
        try:
            line = child.stdout.readline()
            if json.loads(line).get('barrier') != mode:
                raise RuntimeError('Missing owned crash barrier')
            child.terminate()
            out, err = child.communicate(timeout=30)
            (evidence / (mode + '.log')).write_text(line + out + err)
        finally:
            watchdog.cancel()
            if child.poll() is None:
                child.terminate()
                child.wait(timeout=30)
        first = run('inspect', fixture, mode + '-recovery')['summary']['runs']
        second = run('inspect', fixture, mode + '-again')['summary']['runs']
        if first != second or first[0]['recordState'] != 'recovered_archived':
            raise RuntimeError('Recovery not stable')
        expected = 'interrupted' if mode == 'crash-prepared' else 'cleanup_unconfirmed'
        if first[0]['recoveryReason'] != expected:
            raise RuntimeError('Recovery reason mismatch')
    print(json.dumps({'passed': True, 'cases': 3, 'hardware': False, 'evidence': str(evidence)}))


if __name__ == '__main__':
    main()
