#!/usr/bin/env python3
"""Product CRUD and committed-but-lost create using fixture-only processes."""
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
    evidence = (args.evidence_root or Path(tempfile.mkdtemp(prefix='meshchan-drafts-'))).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    fixture = Path(tempfile.mkdtemp(prefix='product-', dir=evidence))
    unknown = Path(tempfile.mkdtemp(prefix='unknown-', dir=evidence))
    target = str(root / 'apps/meshchan_app/tool/draft_process.dart')

    def command(mode, directory):
        return [args.dart, 'run', target, mode, str(directory)]

    def run(mode, directory):
        result = subprocess.run(command(mode, directory), cwd=root, text=True,
                                capture_output=True, timeout=180)
        (evidence / (mode + '.log')).write_text(result.stdout + result.stderr)
        result.check_returncode()
        lines = [json.loads(line[line.index('{'):]) for line in result.stdout.splitlines() if '{' in line]
        if not lines or lines[-1].get('passed') is not True:
            raise RuntimeError('Missing product process success: ' + mode)
        return lines[-1]

    owner = subprocess.Popen(command('write', fixture), cwd=root, text=True,
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    watchdog = threading.Timer(180, owner.terminate)
    watchdog.start()
    try:
        while True:
            line = owner.stdout.readline()
            if not line:
                raise RuntimeError('Product owner failed to start')
            if '{' in line and json.loads(line[line.index('{'):]).get('ready'):
                break
        run('contend', fixture)
        tail, errors = owner.communicate('close\n', timeout=180)
        (evidence / 'write.log').write_text(tail + errors)
        if owner.returncode or not json.loads(tail.splitlines()[-1]).get('passed'):
            raise RuntimeError('Product owner close failed')
        run('read', fixture)
        run('unknown', unknown)
        run('unknown-read', unknown)
        print(json.dumps({'passed': True, 'fixtureWrites': False,
                          'checks': ['CRUD', 'owner contention', 'reopen', 'committed lost create',
                                     'frozen retry', 'safe close', 'new-process count=1']}))
    finally:
        watchdog.cancel()
        if owner.poll() is None:
            owner.terminate()  # Reclamation is never a normal-close pass.
            owner.wait(timeout=30)


if __name__ == '__main__':
    main()
