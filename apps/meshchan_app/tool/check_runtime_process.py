#!/usr/bin/env python3
"""Verify production worker ownership and exact text across separate processes."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import threading


def reports(text):
    # dart run may prefix the first product line with native-hook progress.
    return [json.loads(line[line.index('{'):]) for line in text.splitlines() if '{' in line]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dart', required=True)
    parser.add_argument('--evidence-root', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    app = root / 'apps/meshchan_app'
    evidence = (args.evidence_root or Path(tempfile.mkdtemp(prefix='meshchan-runtime-process-'))).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    fixture = Path(tempfile.mkdtemp(prefix='fixture-', dir=evidence)).resolve()
    target = str(app / 'tool/runtime_process.dart')

    def read():
        result = subprocess.run([args.dart, 'run', target, 'read', str(fixture)],
                                cwd=evidence, text=True, capture_output=True, timeout=120)
        (evidence / ('read-' + str(len(list(evidence.glob('read-*.log')))) + '.log')).write_text(result.stdout + result.stderr)
        result.check_returncode()
        return reports(result.stdout)

    owner = subprocess.Popen([args.dart, 'run', target, 'hold', str(fixture)],
                             cwd=evidence, text=True, stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    watchdog = threading.Timer(120, owner.terminate)
    watchdog.start()
    try:
        while True:
            line = owner.stdout.readline()
            if not line:
                raise RuntimeError('Owner startup failed: ' + owner.stderr.read())
            if '{' in line:
                ready = reports(line)[0]
                break
        if ready['phase'] != 'ready':
            raise RuntimeError('Owner did not become ready')
        busy = read()
        if busy[0]['error'] != 'data_directory_busy' or busy[0]['owner'] != 'none':
            raise RuntimeError('Second process did not preserve exclusive ownership')
        owner.stdin.write('close\n')
        owner.stdin.flush()
        tail, errors = owner.communicate(timeout=120)
        (evidence / 'owner.log').write_text(tail + errors)
        if owner.returncode != 0 or not reports(tail)[-1]['released']:
            raise RuntimeError('Owner did not confirm release: ' + errors)
        reopened = read()
        if reopened[0]['phase'] != 'ready' or reopened[-1] != {
                'released': True, 'exited': True, 'ports': 0, 'pending': 0}:
            raise RuntimeError('Separate process did not reopen cleanly')
        draft = reopened[1]['drafts'][0]
        if draft != {'id': ready['draftId'], 'revision': 1,
                     'body': 'First\r\n第二行 🙂\nLast\rEnd'}:
            raise RuntimeError('Committed draft text or identity changed across processes')
        print(json.dumps({'passed': True, 'fixture': str(fixture),
                          'busy': busy, 'reopened': reopened}))
    finally:
        watchdog.cancel()
        if owner.poll() is None:
            # Test-environment reclamation only; never counts as release PASS.
            owner.terminate()
            owner.wait(timeout=30)


if __name__ == '__main__':
    main()
