#!/usr/bin/env python3
"""Run the isolated Debug probe on a new owned arm64 AVD, without radio access."""
import argparse
import datetime
import json
from pathlib import Path
import re
import socket
import subprocess
import sys
import time
import os

from regression_1d10 import ROOT, write_json

PROBE_ID = 'org.meshchan.probe.meshchan_app'


def require_owned_emulator(actual_name, expected_name, qemu, abi):
    if actual_name != expected_name or qemu != '1' or abi != 'arm64-v8a':
        raise ValueError('Exact owned arm64 emulator identity required; no app install attempted')


def validate_report(report):
    expected = {'probe': 'meshchan.mobile.1d10', 'os': 'android',
                'abi': 'android_arm64', 'passed': True,
                'sqliteLoadReadWriteClose': 'PASS', 'coreStorageRejection': 'PASS',
                'businessDirectoryAbsent': True, 'storageCapability': 'UNSUPPORTED',
                'serialEnumerationGuard': 'PASS'}
    if any(type(report.get(k)) is not type(v) or report.get(k) != v
           for k, v in expected.items()) or not report.get('sqliteVersion'):
        raise ValueError('Android dependency/API assertions failed: ' + json.dumps(report))


def owned_receipt_path(output):
    paths = [line.removeprefix('./') for line in output.splitlines() if line.strip()]
    allowed = {'cache/meshchan-mobile-report.json', 'code_cache/meshchan-mobile-report.json'}
    if len(paths) > 1 or any(p not in allowed for p in paths):
        raise ValueError('Ambiguous or unexpected probe receipt path')
    return paths[0] if paths else None


def reap_owned_emulator(child, cleanup_errors):
    """Escalate only the Popen child; a wait deadline never proves its exit."""
    for action, timeout in ((None, 60), ('terminate', 10), ('kill', 10)):
        if action is not None:
            try:
                if child.poll() is None:
                    getattr(child, action)()
            except OSError as error:
                cleanup_errors.append(error)
        try:
            return child.wait(timeout=timeout), True
        except (subprocess.SubprocessError, OSError) as error:
            cleanup_errors.append(error)
    return None, False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--java-home', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--system-image', default='system-images;android-36;google_apis_playstore;arm64-v8a')
    parser.add_argument('--port', type=int, default=5558)
    args = parser.parse_args()
    sdk, apk, evidence = args.sdk.resolve(strict=True), args.apk.resolve(strict=True), args.evidence.resolve()
    if evidence == ROOT or ROOT in evidence.parents or not 5554 <= args.port <= 5682 or args.port % 2:
        parser.error('Use external evidence and an even emulator port from 5554 to 5682')
    parts = args.system_image.split(';')
    if len(parts) != 4 or parts[0] != 'system-images' or parts[-1] != 'arm64-v8a' or any(
            not re.fullmatch(r'[A-Za-z0-9_.-]+', p) for p in parts):
        parser.error('An explicit installed arm64 system image is required')
    if not (sdk.joinpath(*parts) / 'source.properties').is_file():
        parser.error('System image is absent; this runner never installs one')
    for port in (args.port, args.port + 1):
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', port))
    evidence.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ)
    env.update(ANDROID_HOME=str(sdk), ANDROID_SDK_ROOT=str(sdk),
               ANDROID_AVD_HOME=str(evidence / 'avds'),
               ANDROID_USER_HOME=str(evidence / 'android-user'),
               ANDROID_EMULATOR_HOME=str(evidence / 'emulator-home'),
               JAVA_HOME=str(args.java_home.resolve(strict=True)))
    for key in ('ANDROID_AVD_HOME', 'ANDROID_USER_HOME', 'ANDROID_EMULATOR_HOME'):
        Path(env[key]).mkdir()
    records = []
    def run(label, argv, *, check=True, input=None):
        started = datetime.datetime.now(datetime.timezone.utc).isoformat()
        result = subprocess.run(list(map(str, argv)), cwd=evidence, env=env,
                                capture_output=True, text=True, input=input, timeout=120)
        records.append(dict(name=label, argv=list(map(str, argv)), cwd=str(evidence),
            startedUtc=started, finishedUtc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
            exitCode=result.returncode, stdout=result.stdout, stderr=result.stderr))
        write_json(evidence / 'commands.json', records)
        if check:
            result.check_returncode()
        return result
    adb = [sdk / 'platform-tools/adb', '-s', 'emulator-' + str(args.port)]
    badging = run('APK identity', [sdk / 'build-tools/37.0.0/aapt2', 'dump', 'badging', apk]).stdout
    package = re.search(r"^package: name='([^']+)'", badging, re.M)
    if package is None or package[1] != PROBE_ID:
        raise ValueError('Only the isolated Meshchan probe APK may be installed')
    name = 'meshchan_1d10_' + evidence.parent.name.replace('-', '_')
    run('create owned AVD', [sdk / 'cmdline-tools/latest/bin/avdmanager', 'create', 'avd',
        '--name', name, '--package', args.system_image, '--path', evidence / 'device.avd',
        '--device', 'medium_phone'], input='no\n')
    launch = [str(sdk / 'emulator/emulator'), '-avd', name, '-port', str(args.port),
              '-no-window', '-no-snapshot', '-no-audio', '-no-boot-anim', '-gpu', 'swiftshader']
    identity_confirmed = False
    with (evidence / 'emulator.log').open('x') as log:
        child = subprocess.Popen(launch, cwd=evidence, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            write_json(evidence / 'emulator-process.json', dict(argv=launch, pid=child.pid, cwd=str(evidence)))
            deadline = time.monotonic() + 240
            while time.monotonic() < deadline:
                if child.poll() is not None:
                    raise RuntimeError('Owned emulator exited before boot; see emulator.log')
                boot = run('observe boot', adb + ['shell', 'getprop', 'sys.boot_completed'], check=False)
                if boot.returncode == 0 and boot.stdout.strip() == '1':
                    break
                time.sleep(1)
            else:
                raise RuntimeError('Boot observation expired; no resource release inferred')
            actual_name = run('AVD identity', adb + ['emu', 'avd', 'name']).stdout.splitlines()[0].strip()
            qemu = run('virtual device', adb + ['shell', 'getprop', 'ro.kernel.qemu']).stdout.strip()
            abi = run('device ABI', adb + ['shell', 'getprop', 'ro.product.cpu.abi']).stdout.strip()
            require_owned_emulator(actual_name, name, qemu, abi)
            identity_confirmed = True
            run('OS version', adb + ['shell', 'getprop', 'ro.build.version.release'])
            run('API level', adb + ['shell', 'getprop', 'ro.build.version.sdk'])
            run('install finite probe', adb + ['install', apk])
            run('launch finite probe', adb + ['shell', 'am', 'start', '-W', '-n', PROBE_ID + '/.MainActivity'])
            deadline = time.monotonic() + 120
            report = None
            while time.monotonic() < deadline:
                found = run('locate owned receipt', adb + ['shell', 'run-as', PROBE_ID,
                    'find', '.', '-maxdepth', '2', '-name', 'meshchan-mobile-report.json'])
                path = owned_receipt_path(found.stdout)
                if path:
                    result = run('read owned receipt', adb + ['exec-out', 'run-as', PROBE_ID,
                        'cat', path], check=False)
                    if result.returncode == 0:
                        try:
                            report = json.loads(result.stdout)
                            break
                        except json.JSONDecodeError:
                            pass  # An incomplete receipt is not yet evidence.
                time.sleep(0.2)
            if report is None:
                run('probe logs', adb + ['logcat', '-d', '-s', 'flutter'], check=False)
                raise RuntimeError('Probe receipt observation expired; runtime is not PASS')
            write_json(evidence / 'report.json', report)
            validate_report(report)
            print(json.dumps(report), flush=True)
        finally:
            primary = sys.exception()
            cleanup_errors = []
            if identity_confirmed:
                for label, argv in [('stop finite probe UI', adb + ['shell', 'am', 'force-stop', PROBE_ID]),
                                    ('stop owned emulator', adb + ['emu', 'kill'])]:
                    try:
                        run(label, argv)
                    except (subprocess.SubprocessError, OSError) as error:
                        cleanup_errors.append(error)
            else:
                try:
                    if child.poll() is None:
                        child.terminate()  # Only this runner's exact child, never a discovered emulator.
                except OSError as error:
                    cleanup_errors.append(error)
            code, reaped = reap_owned_emulator(child, cleanup_errors)
            try:
                write_json(evidence / 'emulator-exit.json', dict(exitCode=code, processReaped=reaped,
                    productQuitClaim=False, identityConfirmed=identity_confirmed))
            except OSError as error:
                cleanup_errors.append(error)
            if cleanup_errors:
                try:
                    write_json(evidence / 'cleanup-errors.json', [str(e) for e in cleanup_errors])
                except OSError as error:
                    cleanup_errors.append(error)
                if primary is None:
                    raise ExceptionGroup('Finite probe cleanup commands failed', cleanup_errors)
                primary.add_note('Finite probe cleanup failures: ' + '; '.join(map(str, cleanup_errors)))


if __name__ == '__main__':
    main()
