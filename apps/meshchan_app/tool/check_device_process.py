#!/usr/bin/env python3
"""Finite checks with a public fake transport, real owner and separate contenders."""
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
    evidence = (args.evidence_root or Path(tempfile.mkdtemp(prefix='meshchan-device-'))).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    for mode in ['normal', 'delayed']:
        fixture = Path(tempfile.mkdtemp(prefix=mode + '-', dir=evidence))
        command = [args.dart, 'run', str(root / 'apps/meshchan_app/tool/device_process.dart'), mode, str(fixture)]
        owner = subprocess.Popen(command, cwd=evidence, text=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        watchdog = threading.Timer(180, owner.terminate)
        watchdog.start()
        try:
            while True:
                line = owner.stdout.readline()
                if not line:
                    raise RuntimeError('Missing held check: ' + owner.stderr.read())
                if '"held":true' in line:
                    break
            contender = subprocess.run([args.dart, 'run', str(root / 'apps/meshchan_app/tool/runtime_process.dart'), 'read', str(fixture)], cwd=evidence, text=True, capture_output=True, timeout=180)
            (evidence / (mode + '-contender.log')).write_text(contender.stdout + contender.stderr)
            contender.check_returncode()
            if 'data_directory_busy' not in contender.stdout:
                raise RuntimeError('Contender did not observe owner')
            output, errors = owner.communicate('close\n', timeout=180)
            (evidence / (mode + '.log')).write_text(output + errors)
            if owner.returncode or not json.loads(output.splitlines()[-1])['passed']:
                raise RuntimeError('Device process failed')
            reopened = subprocess.run([args.dart, 'run', str(root / 'apps/meshchan_app/tool/runtime_process.dart'), 'read', str(fixture)], cwd=evidence, text=True, capture_output=True, timeout=180)
            (evidence / (mode + '-reopen.log')).write_text(reopened.stdout + reopened.stderr)
            reopened.check_returncode()
            if '"body":"final save"' not in reopened.stdout:
                raise RuntimeError('Committed offline data missing')
        finally:
            watchdog.cancel()
            if owner.poll() is None:
                owner.terminate()  # Failure reclamation is never a normal quit pass.
                owner.wait(timeout=30)
    fault_fixture = Path(tempfile.mkdtemp(prefix='fault-', dir=evidence))
    fault = subprocess.run([args.dart, 'run', str(root / 'apps/meshchan_app/tool/device_process.dart'), 'fault', str(fault_fixture)], cwd=evidence, capture_output=True, text=True, timeout=180)
    (evidence / 'fault.log').write_text(fault.stdout + fault.stderr)
    fault.check_returncode()
    report = json.loads(fault.stdout.splitlines()[-1])
    if not report['passed'] or report['resourcesReleased'] or report['normalClose']:
        raise RuntimeError('Fault child misreported release')
    print(json.dumps({'passed': True, 'cases': ['blocked cleanup', 'delayed ack cancel', 'owner contender', 'independent reopen'], 'hardware': False}))


if __name__ == '__main__':
    main()
