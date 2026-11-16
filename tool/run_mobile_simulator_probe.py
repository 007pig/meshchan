#!/usr/bin/env python3
"""Run only the isolated probe in a new, externally owned simulator device set."""
import argparse
import datetime
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import time

from regression_1d10 import ROOT, write_json


def probe_identifier(app):
    identifier = plistlib.loads((app / 'Info.plist').read_bytes())['CFBundleIdentifier']
    if identifier != 'org.meshchan.probe.meshchanApp':
        raise ValueError('Only the isolated Meshchan probe may be installed')
    return identifier


def validate_report(report):
    expected = {'probe': 'meshchan.mobile.1d10', 'os': 'ios', 'abi': 'ios_arm64',
                'passed': True, 'sqliteLoadReadWriteClose': 'PASS',
                'coreStorageRejection': 'PASS', 'serialEnumerationGuard': 'PASS',
                'businessDirectoryAbsent': True, 'storageCapability': 'UNSUPPORTED'}
    if (not isinstance(report, dict) or
            any(type(report.get(k)) is not type(v) or report.get(k) != v
                for k, v in expected.items()) or
            not isinstance(report.get('sqliteVersion'), str) or not report['sqliteVersion']):
        raise ValueError('iOS dependency/API assertions failed: ' + json.dumps(report))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--runtime', required=True)
    parser.add_argument('--device-type', default='com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro')
    args = parser.parse_args()
    identifier = probe_identifier(args.app.resolve(strict=True))
    evidence = args.evidence.resolve()
    if evidence == ROOT or ROOT in evidence.parents:
        parser.error('Simulator evidence must be external')
    evidence.mkdir(parents=True, exist_ok=False)
    device_set = evidence / 'devices'
    device_set.mkdir()
    records = []
    def run(label, arguments):
        argv = ['xcrun', 'simctl', '--set', str(device_set), *arguments]
        started = datetime.datetime.now(datetime.timezone.utc).isoformat()
        result = subprocess.run(argv, cwd=evidence, capture_output=True, text=True)
        records.append(dict(argv=argv, cwd=str(evidence), startedUtc=started,
            finishedUtc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
            exitCode=result.returncode, stdout=result.stdout, stderr=result.stderr))
        write_json(evidence / 'commands.json', records)
        result.check_returncode()
        print(label + ' completed', flush=True)
        return result.stdout
    device = run('create', ['create', 'Meshchan 1D10 probe', args.device_type, args.runtime]).strip()
    report = None
    try:
        run('boot', ['bootstatus', device, '-b'])
        run('install', ['install', device, str(args.app.resolve())])
        container = Path(run('data container', ['get_app_container', device, identifier, 'data']).strip())
        result_file = container / 'tmp/meshchan-mobile-report.json'
        run('launch', ['launch', device, identifier])
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            if result_file.exists():
                try:
                    report = json.loads(result_file.read_text())
                except json.JSONDecodeError:
                    pass  # File creation can precede publication of complete JSON.
            if report is not None:
                break
            time.sleep(0.2)
        if report is None:
            raise RuntimeError('No dependency/API report within observation period; no cleanup inferred')
        write_json(evidence / 'report.json', report)
        validate_report(report)
        print(json.dumps(report), flush=True)
    finally:
        # This finite dependency probe has already reported close or failure.
        # Terminating its UI is not a Meshchan product Quit/cleanup assertion.
        primary = sys.exception()
        cleanup_errors = []
        for label, argv in [('terminate probe', ['terminate', device, identifier]),
                            ('shutdown owned simulator', ['shutdown', device])]:
            try:
                run(label, argv)
            except (subprocess.SubprocessError, OSError) as error:
                cleanup_errors.append(error)
        if cleanup_errors:
            try:
                write_json(evidence / 'cleanup-errors.json', [str(error) for error in cleanup_errors])
            except OSError as error:
                cleanup_errors.append(error)
            if primary is None:
                raise ExceptionGroup('Probe cleanup commands failed', cleanup_errors)
            primary.add_note('Probe cleanup failures: ' + '; '.join(map(str, cleanup_errors)))


if __name__ == '__main__':
    main()
