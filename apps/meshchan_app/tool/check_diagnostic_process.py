#!/usr/bin/env python3
"""Recorded diagnostics: real worker/core/SQLite with public fake transports."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dart', required=True)
    parser.add_argument('--evidence-root', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    evidence = (args.evidence_root or Path(tempfile.mkdtemp(prefix='meshchan-diagnostic-'))).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    entry = root / 'apps/meshchan_app/tool/diagnostic_process.dart'
    for mode in ['normal', 'resolve', 'stop', 'prepared', 'fault']:
        fixture = Path(tempfile.mkdtemp(prefix=mode + '-', dir=evidence))
        command = [args.dart, 'run', str(entry), mode, str(fixture)]
        if mode == 'normal':
            owner = subprocess.Popen(command, cwd=evidence, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                # Child's bounded scenario waits here with the real owner held.
                import threading
                watchdog = threading.Timer(180, owner.terminate)
                watchdog.start()
                while True:
                    line = owner.stdout.readline()
                    if not line:
                        raise RuntimeError('Missing held barrier: ' + owner.stderr.read())
                    if '"held":true' in line:
                        break
                contender = subprocess.run([args.dart, 'run', str(root / 'apps/meshchan_app/tool/runtime_process.dart'), 'read', str(fixture)], cwd=evidence, capture_output=True, text=True, timeout=180)
                (evidence / 'contender.log').write_text(contender.stdout + contender.stderr)
                contender.check_returncode()
                if 'data_directory_busy' not in contender.stdout:
                    raise RuntimeError('Owner barrier missing')
                out, err = owner.communicate('close\n', timeout=180)
                if owner.returncode:
                    raise RuntimeError(out + err)
            finally:
                watchdog.cancel()
                if owner.poll() is None:
                    owner.terminate()
                    owner.wait(timeout=30)
        else:
            result = subprocess.run(command, cwd=evidence, capture_output=True, text=True, timeout=180)
            out, err = result.stdout, result.stderr
            (evidence / (mode + '.log')).write_text(out + err)
            result.check_returncode()
        (evidence / (mode + '.log')).write_text(out + err)
        report = json.loads(out.splitlines()[-1])
        if report.get('passed') is not True:
            raise RuntimeError('Missing pass')
        if mode != 'fault':
            reopened = subprocess.run([args.dart, 'run', str(entry), 'read', str(fixture)], cwd=evidence, capture_output=True, text=True, timeout=180)
            (evidence / (mode + '-reopen.log')).write_text(reopened.stdout + reopened.stderr)
            reopened.check_returncode()
            if json.loads(reopened.stdout.splitlines()[-1])['runs'] != report['runs']:
                raise RuntimeError('Independent history mismatch')
        elif report.get('normalClose') is not False or report.get('resourcesReleased') is not False:
            raise RuntimeError('Fault misreported release')
    print(json.dumps({'passed': True, 'cases': 5, 'hardware': False}))


if __name__ == '__main__':
    main()
