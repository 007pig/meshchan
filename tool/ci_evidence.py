#!/usr/bin/env python3
"""Capture the hosted jobs' checks and independently verify their evidence ZIPs."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tarfile


WORKFLOW = '.github/workflows/ci.yml'
CAPTURE_TOOL = 'tool/ci_evidence.py'
SETUP = ('checkout', 'setup_flutter', 'setup_python', 'enable_evidence')
PROCESS_CHECKS = ('runtime_process', 'draft_process', 'profile_process',
                  'device_process', 'diagnostic_process', 'history_process')
COMMON_START = ('runner_toolchain', 'locked_dependencies', 'candidate_identity')
CHECKS = {
    'check': COMMON_START + (
        'generate_database', 'schema_snapshot', 'tracked_generated', 'format',
        'analyze', 'flutter_tests', *PROCESS_CHECKS, 'python_tests', 'core_tests',
        'cli_tests', 'link_tests', 'native_cli', 'serial_probe',
        'datagram_probe', 'cli_smoke', 'whitespace',
    ),
    'macos-app': COMMON_START + (
        'flutter_tests', *PROCESS_CHECKS, 'macos_build', 'release_plist',
        'xctest', 'macos_runtime', 'macos_sqlite',
    ),
}
RUNNER_IDENTITY = {
    'check': ('Linux', 'X64', 'x86_64', 'ubuntu-latest'),
    'macos-app': ('macOS', 'ARM64', 'arm64', 'macos-15'),
}
SCOPE = {
    'check': 'Hardware-free source, runtime, and native CLI checks on hosted Linux.',
    'macos-app': 'Hardware-free macOS App, native XCTest, runtime, and relocation checks.',
}
MEMBERS = {'report.json', 'workflow.yml', 'logs.tar.gz'}
RETENTION_DAYS = 30
SHA = re.compile(r'[0-9a-f]{40}')
DIGEST = re.compile(r'[0-9a-f]{64}')


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, data):
    with path.open('x', encoding='utf-8') as stream:
        json.dump(data, stream, indent=2)
        stream.write('\n')


def capture_root():
    return Path(os.environ['RUNNER_TEMP']) / 'meshchan-ci-capture'


def run_step(script):
    """Run the runner's original Bash script with live output and its real exit code."""
    stage = os.environ['GITHUB_ACTION']
    if stage not in CHECKS[os.environ['GITHUB_JOB']]:
        raise ValueError('Unlisted CI evidence step: ' + stage)
    log = capture_root() / (stage + '.log')
    with log.open('xb') as stream, subprocess.Popen(
        ['bash', '--noprofile', '--norc', '-eo', 'pipefail', script],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    ) as command:
        for data in iter(lambda: command.stdout.read1(65536), b''):
            stream.write(data)
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
        code = command.wait()
    if code < 0:
        code = 128 - code
    write_json(capture_root() / (stage + '.json'), {'exit_code': code})
    return code


def command_output(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def record_toolchain():
    macos = os.environ['RUNNER_OS'] == 'macOS'
    dart = shutil.which('dart')
    flutter = shutil.which('flutter')
    if not dart or not flutter:
        raise ValueError('Could not locate the configured Flutter and Dart SDKs')
    data = {
        'python': {'version': platform.python_version(), 'executable': sys.executable},
        'flutter': {'executable': flutter,
                    'version': json.loads(command_output(flutter, '--version', '--machine'))},
        'dart': {'executable': dart, 'version': command_output(dart, '--version')},
        'compiler': (command_output('xcrun', 'clang', '--version') if macos
                     else command_output('cc', '--version')),
        'compiler_path': (command_output('xcrun', '--find', 'clang') if macos else shutil.which('cc')),
        'linux_clang': command_output('clang', '--version') if not macos and shutil.which('clang') else None,
        'xcode': (command_output('xcodebuild', '-version') if macos else None),
        'xcode_selected': (command_output('xcode-select', '-p') if macos else None),
        'macos_sdk': (command_output('xcrun', '--sdk', 'macosx', '--show-sdk-version')
                      if macos else None),
    }
    if data['python']['version'] != os.environ['MESHCHAN_CI_PYTHON_VERSION']:
        raise ValueError('The selected interpreter differs from the configured CI Python')
    write_json(capture_root() / 'toolchain.json', data)
    print(json.dumps(data, indent=2))


def measure(stream):
    digest = hashlib.sha256()
    size = 0
    for data in iter(lambda: stream.read(65536), b''):
        digest.update(data)
        size += len(data)
    return {'size': size, 'sha256': digest.hexdigest()}


def step_report(job, context, root):
    results = []
    errors = []
    for stage in SETUP + CHECKS[job]:
        result = context.get(stage, {})
        row = {
            'id': stage, 'outcome': result.get('outcome', 'not_run'),
            'conclusion': result.get('conclusion', 'not_run'),
            'log': None, 'exit_code': None,
        }
        log = root / (stage + '.log')
        result_path = root / (stage + '.json')
        if stage in CHECKS[job] and log.is_file():
            with log.open('rb') as stream:
                row['log'] = {'path': log.name, **measure(stream)}
            if result_path.is_file():
                row['exit_code'] = json.loads(result_path.read_bytes())['exit_code']
        if (stage in CHECKS[job] and row['outcome'] == 'success'
                and (row['log'] is None or row['exit_code'] != 0)):
            errors.append('Successful step is missing complete capture: ' + stage)
        results.append(row)
    return results, errors


def pull_request_identity(event, ref, requested_sha):
    if event != 'pull_request':
        return None
    payload = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_bytes())
    pr = payload['pull_request']
    number = payload['number']
    return {
        'number': number,
        'head_sha': pr['head']['sha'],
        'base_sha': pr['base']['sha'],
        'merge_sha': requested_sha if ref == f'refs/pull/{number}/merge' else None,
        'payload_merge_commit_sha': pr.get('merge_commit_sha'),
    }


def report_job():
    env = os.environ
    job = env['GITHUB_JOB']
    root = capture_root()
    steps, errors = step_report(job, json.loads(env['MESHCHAN_CI_STEPS']), root)
    checkout = command_output('git', 'rev-parse', 'HEAD')
    checkout_parents = [line.split()[1] for line in
                        command_output('git', 'cat-file', '-p', checkout).split('\n\n', 1)[0].splitlines()
                        if line.startswith('parent ')]
    workflow_sha = env['GITHUB_WORKFLOW_SHA']
    if not SHA.fullmatch(workflow_sha):
        raise ValueError('Malformed workflow commit')
    workflow = subprocess.check_output(['git', 'show', workflow_sha + ':' + WORKFLOW])
    checkout_inputs = {}
    for source in (CAPTURE_TOOL, 'pubspec.lock'):
        original = subprocess.check_output(['git', 'show', checkout + ':' + source])
        checkout_inputs[source] = sha256(original)
        if Path(source).read_bytes() != original:
            errors.append('CI input differs from the checked-out commit: ' + source)
    runner = {
        'os': env['RUNNER_OS'], 'arch': env['RUNNER_ARCH'],
        'label': env['MESHCHAN_CI_RUNNER_LABEL'],
        'uname_machine': command_output('uname', '-m'),
        'kernel': platform.release(),
        'os_version': (command_output('sw_vers') if env['RUNNER_OS'] == 'macOS' else
                       platform.freedesktop_os_release().get('PRETTY_NAME')),
    }
    pr = pull_request_identity(env['GITHUB_EVENT_NAME'], env['GITHUB_REF'], env['GITHUB_SHA'])
    if checkout != env['GITHUB_SHA'] or (
            pr is not None and (pr['merge_sha'] != checkout or pr['head_sha'] not in checkout_parents)):
        errors.append('Actual checkout does not match the workflow event checkout')
    if ((runner['os'], runner['arch'], runner['uname_machine'], runner['label'])
            != RUNNER_IDENTITY[job]):
        errors.append('Unexpected operating system or architecture for the configured job')
    toolchain_path = root / 'toolchain.json'
    toolchain = json.loads(toolchain_path.read_bytes()) if toolchain_path.is_file() else None
    if steps[len(SETUP)]['outcome'] == 'success' and toolchain is None:
        errors.append('Successful toolchain probe is missing its report')
    report = {
        'schema': 1,
        'kind': 'meshchan-ci-job',
        'recorded_at': datetime.now(timezone.utc).isoformat(),
        'repository': env['GITHUB_REPOSITORY'], 'event': env['GITHUB_EVENT_NAME'],
        'requested_ref': env['GITHUB_REF'], 'requested_sha': env['GITHUB_SHA'],
        'checkout_sha': checkout, 'checkout_parents': checkout_parents,
        'pull_request': pr,
        'workflow_path': WORKFLOW, 'workflow_ref': env['GITHUB_WORKFLOW_REF'],
        'workflow_sha': workflow_sha, 'workflow_sha256': sha256(workflow),
        'checkout_inputs': checkout_inputs,
        'run_id': int(env['GITHUB_RUN_ID']), 'attempt': int(env['GITHUB_RUN_ATTEMPT']),
        'job': job, 'job_id': int(env['MESHCHAN_CI_CHECK_RUN_ID']),
        'runner': runner, 'toolchain': toolchain, 'steps': steps,
        'scope': SCOPE[job],
        'artifact_retention_days_requested': RETENTION_DAYS,
        'evidence_errors': errors,
    }
    output = Path(env['RUNNER_TEMP']) / 'meshchan-ci-evidence'
    output.mkdir(mode=0o700)
    write_json(output / 'report.json', report)
    (output / 'workflow.yml').write_bytes(workflow)
    with tarfile.open(output / 'logs.tar.gz', 'x:gz') as archive:
        for step in steps:
            if step['log'] is not None:
                name = step['log']['path']
                archive.add(root / name, arcname=name, recursive=False)
    with Path(env['GITHUB_OUTPUT']).open('a', encoding='utf-8') as stream:
        print('checkout_sha=' + checkout, file=stream)
        print('evidence_ok=' + ('false' if errors else 'true'), file=stream)
    for error in errors:
        print(error, file=sys.stderr)


def _verify_report(report, identity):
    if not isinstance(report, dict) or any(report.get(key) != value for key, value in identity.items()):
        raise ValueError('CI report identity mismatch')
    if type(report['schema']) is not int or type(report['run_id']) is not int or type(report['attempt']) is not int:
        raise ValueError('CI report has a malformed schema or run identity')
    job = identity['job']
    if (type(report.get('job_id')) is not int or report['job_id'] <= 0
            or report.get('scope') != SCOPE[job]):
        raise ValueError('CI report has a malformed job identity or scope')
    checkout = report['checkout_sha']
    pr = report.get('pull_request')
    ref = report.get('requested_ref')
    parents = report.get('checkout_parents')
    if (not isinstance(ref, str) or not ref.startswith('refs/') or not SHA.fullmatch(checkout)
            or checkout != report['requested_sha'] or not isinstance(parents, list)
            or not all(isinstance(parent, str) and SHA.fullmatch(parent) for parent in parents)):
        raise ValueError('CI report does not identify the actual event checkout')
    if report['event'] == 'pull_request':
        if (not isinstance(pr, dict) or type(pr.get('number')) is not int
                or ref != f"refs/pull/{pr['number']}/merge"
                or pr.get('merge_sha') != checkout or pr.get('head_sha') == checkout
                or pr.get('head_sha') not in parents
                or not isinstance(pr.get('base_sha'), str) or not SHA.fullmatch(pr['base_sha'])):
            raise ValueError('CI PR evidence does not identify the merge checkout and PR head')
    elif pr is not None or report['event'] not in ('push', 'workflow_dispatch'):
        raise ValueError('Unexpected PR identity or CI event')
    workflow_ref = report.get('workflow_ref')
    if (not isinstance(workflow_ref, str)
            or workflow_ref != f"{report['repository']}/{WORKFLOW}@{ref}"
            or not isinstance(report.get('workflow_sha'), str)
            or not SHA.fullmatch(report['workflow_sha'])):
        raise ValueError('CI report workflow ref or commit is inconsistent')
    runner = report.get('runner')
    if (not isinstance(runner, dict) or
            tuple(runner.get(key) for key in ('os', 'arch', 'uname_machine', 'label'))
            != RUNNER_IDENTITY[job] or not runner.get('os_version') or not runner.get('kernel')):
        raise ValueError('CI runner operating system or architecture is missing or incorrect')
    toolchain = report.get('toolchain')
    if (not isinstance(toolchain, dict)
            or not all(toolchain.get(key) for key in ('python', 'flutter', 'dart', 'compiler'))
            or (job == 'macos-app'
                and not all(toolchain.get(key) for key in ('xcode', 'xcode_selected', 'macos_sdk')))):
        raise ValueError('CI report lacks the required actual toolchain versions')
    inputs = report.get('checkout_inputs')
    if (not isinstance(inputs, dict) or set(inputs) != {CAPTURE_TOOL, 'pubspec.lock'}
            or not all(isinstance(value, str) and DIGEST.fullmatch(value) for value in inputs.values())
            or report.get('artifact_retention_days_requested') != RETENTION_DAYS
            or report.get('evidence_errors') != []):
        raise ValueError('CI report has missing inputs, retention policy, or capture errors')


def _verify_steps(report):
    job = report['job']
    steps = report.get('steps')
    declared = SETUP + CHECKS[job]
    if not isinstance(steps, list) or len(steps) != len(declared):
        raise ValueError('CI report is missing required steps')
    logs = {}
    for step, stage in zip(steps, declared):
        if (not isinstance(step, dict) or step.get('id') != stage
                or step.get('outcome') != 'success' or step.get('conclusion') != 'success'):
            raise ValueError('CI step did not complete successfully: ' + stage)
        log = step.get('log')
        code = step.get('exit_code')
        if stage in SETUP:
            if log is not None or code is not None:
                raise ValueError('Unexpected capture for an action or setup step: ' + stage)
            continue
        if (type(code) is not int or code != 0 or not isinstance(log, dict)
                or set(log) != {'path', 'size', 'sha256'} or log.get('path') != stage + '.log'
                or type(log.get('size')) is not int or log['size'] < 0
                or not isinstance(log.get('sha256'), str) or not DIGEST.fullmatch(log['sha256'])):
            raise ValueError('CI step log or exit code is missing or invalid: ' + stage)
        logs[log['path']] = {'size': log['size'], 'sha256': log['sha256']}
    return logs


def verify_job_zip(archive, *, repository, event, checkout_sha, requested_sha,
                   workflow_sha256, run_id, attempt, job, requested_ref=None):
    """Verify complete successful job evidence after checking the outer Actions digest."""
    names = archive.namelist()
    if set(names) != MEMBERS or len(names) != len(MEMBERS):
        raise ValueError('CI evidence ZIP has unexpected, missing, or duplicate members')
    for name, maximum in (('report.json', 256 * 1024), ('workflow.yml', 256 * 1024),
                          ('logs.tar.gz', 256 * 1024 * 1024)):
        if archive.getinfo(name).file_size > maximum:
            raise ValueError('CI evidence ZIP member exceeds its size limit: ' + name)
    report = json.loads(archive.read('report.json'))
    identity = dict(schema=1, kind='meshchan-ci-job', repository=repository, event=event,
                    checkout_sha=checkout_sha, requested_sha=requested_sha, run_id=run_id,
                    attempt=attempt, job=job, workflow_path=WORKFLOW, workflow_sha256=workflow_sha256)
    if requested_ref is not None:
        identity['requested_ref'] = requested_ref
    _verify_report(report, identity)
    if sha256(archive.read('workflow.yml')) != workflow_sha256:
        raise ValueError('CI workflow bytes do not match the expected digest')
    logs = _verify_steps(report)
    with archive.open('logs.tar.gz') as compressed, tarfile.open(fileobj=compressed, mode='r|gz') as members:
        for member in members:
            expected = logs.pop(member.name, None)
            if (expected is None or not member.isfile() or member.size != expected['size']
                    or member.size > 128 * 1024 * 1024):
                raise ValueError('CI log archive has an unexpected, duplicate, or invalid member: ' + member.name)
            with members.extractfile(member) as log:
                if measure(log) != expected:
                    raise ValueError('CI log digest mismatch: ' + member.name)
        if logs:
            raise ValueError('CI log archive is missing required logs: ' + ', '.join(logs))
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('run', 'toolchain', 'report'))
    parser.add_argument('script', nargs='?')
    args = parser.parse_args()
    if args.command == 'run':
        if args.script is None:
            parser.error('run requires the temporary script')
        return run_step(args.script)
    if args.script is not None:
        parser.error('only run takes a temporary script')
    if args.command == 'toolchain':
        record_toolchain()
    else:
        report_job()
    return 0


if __name__ == '__main__':
    sys.exit(main())
