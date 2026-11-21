"""Collect and independently verify one GitHub Actions CI attempt."""

import argparse
from dataclasses import dataclass
from datetime import UTC, datetime
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from zipfile import BadZipFile, ZipFile

from ci_evidence import load_json
from release_package_archive import open_archive


MANIFEST = 'ci-snapshot.json'
WORKFLOW = '.github/workflows/ci.yml'
JOBS = {'check': 'ubuntu-latest', 'macos-app': 'macos-15'}
API = 'https://api.github.com/'
MAX_FILE_BYTES = 128 * 1024 * 1024
CHECKOUT = re.compile(
    rb'(?m)^\S+ \[command\][^\r\n]+/git log -1 --format=%H\r?\n'
    rb'\S+ ([0-9a-f]{40})\r?$'
)
CHECKED_REF = re.compile(
    rb'(?m)^\S+ \[command\][^\r\n]+/git checkout [^\r\n]+ '
    rb'(refs/(?:remotes/origin/|remotes/pull/|tags/)\S+)\r?$'
)
MERGE_REF = re.compile(r'refs/pull/([1-9][0-9]*)/merge')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def stamp(data):
    return {'size': len(data), 'sha256': sha256(data)}


def positive_int(value):
    return type(value) is int and value > 0


def utc_date(value):
    require(isinstance(value, str) and value.endswith('Z'), 'Invalid GitHub or collection timestamp')
    return datetime.fromisoformat(value)


@dataclass(frozen=True)
class Attempt:
    repository: str
    source: str
    event: str
    head_sha: str
    workflow_sha256: str
    run_id: int
    attempt: int
    require_artifacts: bool

    def __post_init__(self):
        require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', self.repository)
                and all(part not in ('.', '..') for part in self.repository.split('/')),
                'Expected a GitHub owner/repository name')
        require(all(re.fullmatch(r'[0-9a-f]{40}', value) for value in (self.source, self.head_sha)),
                'Expected full checkout and head commit SHAs')
        require(re.fullmatch(r'[0-9a-f]{64}', self.workflow_sha256), 'Expected a full workflow digest')
        require(positive_int(self.run_id) and positive_int(self.attempt), 'Invalid run ID or attempt')
        require(type(self.require_artifacts) is bool, 'Expected an explicit artifact requirement')
        require(self.event in ('push', 'pull_request', 'workflow_dispatch')
                and (self.source != self.head_sha) == (self.event == 'pull_request'),
                'A pull request requires distinct checkout and PR head SHAs')

    @property
    def endpoint(self):
        return f'repos/{self.repository}/actions/runs/{self.run_id}'

    @property
    def attempt_endpoint(self):
        return f'{self.endpoint}/attempts/{self.attempt}'

    def identity(self):
        return {'repository': self.repository, 'source': self.source, 'event': self.event,
                'head_sha': self.head_sha, 'workflow_path': WORKFLOW,
                'workflow_sha256': self.workflow_sha256,
                'run_id': self.run_id, 'attempt': self.attempt, 'require_artifacts': self.require_artifacts}


def run_metadata(read, expected):
    run = load_json(read('run.json', expected.endpoint))
    attempt = load_json(read('attempt.json', expected.attempt_endpoint))
    for record in (run, attempt):
        require(positive_int(record.get('id')) and record['id'] == expected.run_id
                and record.get('event') == expected.event and record.get('head_sha') == expected.head_sha
                and record.get('repository', {}).get('full_name') == expected.repository
                and record.get('path') == WORKFLOW,
                'GitHub run or attempt has a different repository, event, head or workflow identity')
    latest, selected = run.get('run_attempt'), attempt.get('run_attempt')
    require(positive_int(latest) and positive_int(selected) and latest >= selected == expected.attempt,
            'GitHub run or attempt has a different attempt number')
    require(attempt.get('status') == 'completed' and attempt.get('conclusion') == 'success',
            'The selected GitHub attempt must be completed with a success conclusion')
    require(positive_int(run.get('workflow_id')) and run['workflow_id'] == attempt.get('workflow_id'),
            'Run and attempt disagree on workflow ID')
    require(positive_int(run['repository'].get('id')) and run['repository']['id'] == attempt['repository'].get('id'),
            'Run and attempt disagree on repository ID')
    require(all(positive_int(record.get('check_suite_id')) for record in (run, attempt)),
            'Missing GitHub run or attempt check suite ID')
    if latest == selected:
        require(run.get('status') == 'completed' and run.get('conclusion') == 'success',
                'The latest GitHub run must be completed with a success conclusion')
        for key in ('check_suite_id', 'head_branch', 'run_started_at'):
            require(run.get(key) == attempt.get(key), f'Run and attempt disagree on {key}')
    utc_date(attempt['run_started_at'])
    return attempt


def paginated(read, endpoint, key):
    # Request numbered pages explicitly so the original bytes of each response survive.
    records, page, expected_count = {}, 1, None
    while True:
        data = load_json(read(f'{key}-{page}.json', f'{endpoint}?per_page=100&page={page}'))
        items = data.get(key)
        count = data.get('total_count')
        require(type(count) is int and count >= 0 and isinstance(items, list)
                and (expected_count is None or count == expected_count)
                and len(items) == min(100, count - len(records)),
                f'Incomplete or inconsistent GitHub {key} pagination')
        for item in items:
            identifier = item.get('id')
            require(positive_int(identifier) and identifier not in records,
                    f'Invalid or repeated GitHub {key} ID')
            records[identifier] = item
        if len(records) == count:
            return list(records.values())
        page += 1
        expected_count = count


def successful_jobs(read, expected):
    jobs = paginated(read, f'{expected.attempt_endpoint}/jobs', 'jobs')
    require(sorted(row.get('name', '') for row in jobs) == sorted(JOBS), 'Missing or unexpected CI jobs')
    result = {}
    for job in jobs:
        name = job['name']
        require(positive_int(job.get('run_id')) and job['run_id'] == expected.run_id
                and positive_int(job.get('run_attempt')) and job['run_attempt'] == expected.attempt
                and job.get('head_sha') == expected.head_sha
                and job.get('run_url') == API + expected.endpoint and job.get('labels') == [JOBS[name]],
                f'GitHub job has the wrong run, attempt, head or runner label: {name}')
        require(job.get('status') == 'completed' and job.get('conclusion') == 'success',
                f'GitHub job did not complete successfully: {name}')
        result[name] = job
    return result


def verify_checkouts(data, jobs, attempt, expected):
    refs = set()
    with ZipFile(io.BytesIO(data)) as archive:
        for name in jobs:
            # Prefer the checkout step itself. Some older log downloads contain
            # only the combined job log, which still holds the checkout record.
            matches = [member for member in archive.infolist()
                       if re.fullmatch(rf'{re.escape(name)}/[0-9]+_Check out repository\.txt', member.filename)]
            if not matches:
                matches = [member for member in archive.infolist()
                           if re.fullmatch(rf'[0-9]+_{re.escape(name)}\.txt', member.filename)]
            require(len(matches) == 1 and matches[0].file_size <= MAX_FILE_BYTES,
                    f'Missing or repeated GitHub job log: {name}')
            log = archive.read(matches[0])
            checkouts = CHECKOUT.findall(log)
            require(checkouts == [expected.source.encode()], f'Actual checkout log disagrees for {name}')
            matches = CHECKED_REF.findall(log)
            require(len(matches) == 1, f'Missing or repeated checkout ref in GitHub job log: {name}')
            checked_ref = matches[0].decode()
            if checked_ref.startswith('refs/remotes/origin/'):
                checked_ref = 'refs/heads/' + checked_ref.removeprefix('refs/remotes/origin/')
            elif checked_ref.startswith('refs/remotes/pull/'):
                checked_ref = 'refs/pull/' + checked_ref.removeprefix('refs/remotes/pull/')
            refs.add(checked_ref)
    require(len(refs) == 1, 'Jobs checked out different refs')
    ref = refs.pop()
    if expected.event == 'pull_request':
        pr = MERGE_REF.fullmatch(ref)
        require(pr, 'Missing pull request merge ref in GitHub job logs')
        return ref, int(pr[1])
    require(ref.startswith(('refs/heads/', 'refs/tags/')), 'Expected a branch or tag checkout')
    branch = attempt.get('head_branch')
    require(branch == ref.split('/', 2)[2] or (ref.startswith('refs/tags/') and branch is None),
            'GitHub run branch or tag disagrees with the checked-out ref')
    return ref, None


def read_artifacts(read, rows, jobs, attempt, expected, collected_at, requested_ref, expected_pr, checkout_inputs):
    # A GitHub artifact listing is run-wide. The exact name, report and job
    # window bind each selected object to this attempt without hiding other rows.
    if not expected.require_artifacts:
        return []

    from ci_evidence import verify_job_zip

    artifacts = []
    for job, job_data in sorted(jobs.items()):
        name = f'meshchan-ci-{expected.source}-{expected.run_id}-{expected.attempt}-{job}'
        matches = [artifact for artifact in rows if artifact.get('name') == name]
        require(len(matches) == 1, f'Required GitHub artifact is missing or duplicated: {name}')
        artifact = matches[0]
        artifact_id = artifact['id']
        endpoint = f'repos/{expected.repository}/actions/artifacts/{artifact_id}/zip'
        run = artifact.get('workflow_run', {})
        require(run.get('id') == expected.run_id and run.get('head_sha') == expected.head_sha
                and run.get('repository_id') == attempt['repository']['id']
                and artifact.get('archive_download_url') == API + endpoint,
                f'Artifact belongs to a different source or run: {name}')
        expiry = artifact.get('expires_at')
        created_at = utc_date(artifact.get('created_at'))
        require(artifact.get('expired') is False and collected_at < utc_date(expiry),
                f'Required GitHub artifact was expired when collected: {name}')
        require(utc_date(job_data.get('started_at')) <= created_at <= utc_date(job_data.get('completed_at')),
                f'Artifact timestamp does not fall inside the selected job: {name}')
        digest = artifact.get('digest')
        size = artifact.get('size_in_bytes')
        require(isinstance(digest, str) and re.fullmatch(r'sha256:[0-9a-f]{64}', digest)
                and positive_int(size), f'Missing GitHub artifact digest or size: {name}')
        filename = f'artifact-{artifact_id}.zip'
        data = read(filename, endpoint)
        require(len(data) == size and f'sha256:{sha256(data)}' == digest,
                f'GitHub artifact ZIP differs from its remote size or digest: {name}')
        with ZipFile(io.BytesIO(data)) as archive:
            report = verify_job_zip(
                archive, repository=expected.repository, event=expected.event, checkout_sha=expected.source,
                requested_sha=expected.source, requested_ref=requested_ref, workflow_sha256=expected.workflow_sha256,
                run_id=expected.run_id, attempt=expected.attempt, job=job,
            )
        require(report.get('workflow_sha') == expected.source, f'Workflow source differs in artifact: {name}')
        require(report.get('job_id') == job_data['id'], f'GitHub job ID differs in artifact: {name}')
        if checkout_inputs is None:
            checkout_inputs = report['checkout_inputs']
        require(report['checkout_inputs'] == checkout_inputs, f'CI input digests disagree for artifact: {name}')
        if expected_pr is not None:
            pr_number, pr_parents = expected_pr
            pr = report.get('pull_request', {})
            require(pr.get('number') == pr_number and pr.get('head_sha') == expected.head_sha
                    and pr.get('merge_sha') == expected.source
                    and report.get('checkout_parents') == pr_parents,
                    f'PR merge identity or checkout parent list differs in artifact: {name}')
        require(any(step.get('name') == 'Upload CI job evidence' and step.get('conclusion') == 'success'
                    for step in job_data.get('steps', [])), f'No successful upload step for {name}')
        artifacts.append({'id': artifact_id, 'job': job, 'name': name, 'sha256': digest.removeprefix('sha256:'),
                          'size': size, 'created_at': artifact['created_at'], 'expires_at': expiry,
                          'download_url': API + endpoint, 'file': filename})
    return artifacts


def inspect(read, expected, collected_at, *, checkout_inputs=None):
    attempt = run_metadata(read, expected)
    jobs = successful_jobs(read, expected)
    workflow = read('workflow.yml', f'repos/{expected.repository}/contents/{WORKFLOW}?ref={expected.source}', raw=True)
    require(sha256(workflow) == expected.workflow_sha256, 'GitHub workflow bytes differ from their external digest')
    logs = read('logs.zip', f'{expected.attempt_endpoint}/logs')
    requested_ref, pr_number = verify_checkouts(logs, jobs, attempt, expected)
    expected_pr = None
    if pr_number is not None:
        commit = load_json(read('merge-commit.json', f'repos/{expected.repository}/git/commits/{expected.source}'))
        pr_parents = [parent.get('sha') for parent in commit.get('parents', [])]
        require(commit.get('sha') == expected.source and len(pr_parents) == 2 and pr_parents[1] == expected.head_sha
                and isinstance(pr_parents[0], str) and re.fullmatch(r'[0-9a-f]{40}', pr_parents[0]),
                'GitHub merge checkout parents do not match the requested PR head')
        expected_pr = (pr_number, pr_parents)
    rows = paginated(read, f'{expected.endpoint}/artifacts', 'artifacts')
    artifacts = read_artifacts(read, rows, jobs, attempt, expected, collected_at,
                               requested_ref, expected_pr, checkout_inputs)
    return {'pull_request_number': pr_number, 'jobs': {name: job['id'] for name, job in jobs.items()},
            'listed_artifacts': len(rows), 'artifacts': artifacts}


def read_file(path):
    with open_archive(path) as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1, 'CI evidence must be a single-link regular file')
        require(info.st_size <= MAX_FILE_BYTES, f'CI evidence exceeds the file size limit: {path.name}')
        data = stream.read(info.st_size + 1)
        require(len(data) == info.st_size, f'CI evidence file changed while reading: {path.name}')
        return data


def verify_snapshot(directory, expected_pin, *, source, workflow_sha256, require_artifacts,
                    event='push', repository='007pig/meshchan', run_id=None, attempt=None, head_sha=None,
                    checkout_inputs=None):
    """Verify the supplied pin, original responses, attempt identity and downloaded objects offline."""
    directory = Path(directory)
    require(directory.is_dir() and not directory.is_symlink(), 'Expected a real CI snapshot directory')
    raw = read_file(directory / MANIFEST)
    require(sha256(raw) == expected_pin, 'CI snapshot manifest does not match the external digest')
    manifest = load_json(raw)
    expected = Attempt(repository, source, event, head_sha or source, workflow_sha256,
                       manifest['run_id'] if run_id is None else run_id,
                       manifest['attempt'] if attempt is None else attempt, require_artifacts)
    require(checkout_inputs is None or require_artifacts, 'CI input verification requires the job artifacts')
    validate_manifest(directory, manifest, expected, MANIFEST, checkout_inputs=checkout_inputs)
    return manifest


def validate_manifest(directory, manifest, expected, manifest_filename, *, checkout_inputs=None):
    require(manifest.get('kind') == 'meshchan-github-ci-snapshot' and type(manifest.get('schema')) is int
            and manifest['schema'] == 1 and all(manifest.get(key) == value for key, value in expected.identity().items()),
            'CI snapshot manifest has an unexpected kind or identity')
    collected_at = utc_date(manifest.get('collected_at'))
    files = {}

    def read(filename, endpoint, raw=False):
        data = read_file(directory / filename)
        files[filename] = {**stamp(data), 'url': API + endpoint}
        require(manifest['files'].get(filename) == files[filename], f'Pinned CI evidence differs: {filename}')
        return data

    summary = inspect(read, expected, collected_at, checkout_inputs=checkout_inputs)
    require(manifest['files'] == files and {p.name for p in directory.iterdir()} == files.keys() | {manifest_filename}
            and all(manifest.get(key) == value for key, value in summary.items()),
            'CI snapshot has an incomplete, unexpected or inconsistent file set')


def collect(directory, expected):
    directory.mkdir(mode=0o700)
    collected_at = datetime.now(UTC)
    files = {}

    def read(filename, endpoint, raw=False):
        command = ['gh', 'api', '--hostname', 'github.com']
        if raw:
            command += ['-H', 'Accept: application/vnd.github.raw+json']
        command.append(endpoint)
        run = subprocess.run(command, capture_output=True, check=False, timeout=180)
        if run.returncode:
            message = run.stderr.decode(errors='replace').strip()
            # A failed ZIP redirect can expose a short-lived signed URL in stderr.
            message = re.sub(r'https://[^\s"?]+\?[^\s"]+', '[URL query redacted]', message)
            raise ValueError(f'GitHub API read failed for {endpoint}: {message}')
        data = run.stdout
        require(len(data) <= MAX_FILE_BYTES, f'GitHub response exceeds size limit: {filename}')
        with (directory / filename).open('xb') as output:
            output.write(data)
        files[filename] = {**stamp(data), 'url': API + endpoint}
        return data

    try:
        summary = inspect(read, expected, collected_at)
        manifest = {'schema': 1, 'kind': 'meshchan-github-ci-snapshot', **expected.identity(), **summary,
                    'collected_at': collected_at.isoformat(timespec='seconds').replace('+00:00', 'Z'), 'files': files}
        data = (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode()
        pin = sha256(data)
        pending = directory / (MANIFEST + '.pending')
        with pending.open('xb') as output:
            output.write(data)
        staged = read_file(pending)
        require(sha256(staged) == pin, 'CI snapshot changed before publication')
        validate_manifest(directory, load_json(staged), expected, pending.name)
        pending.rename(directory / MANIFEST)
        return pin
    except (OSError, ValueError, KeyError, TypeError, AttributeError, BadZipFile,
            subprocess.SubprocessError, KeyboardInterrupt) as error:
        with (directory / 'collection-error.txt').open('x') as output:
            output.write(f'{type(error).__name__}: {error}\n')
        raise


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('collect', 'verify'))
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--repository', default='007pig/meshchan')
    parser.add_argument('--event', choices=('push', 'pull_request', 'workflow_dispatch'), default='push')
    parser.add_argument('--source', required=True, help='Actual checkout Git SHA')
    parser.add_argument('--head-sha', help='PR head Git SHA for a merge checkout')
    parser.add_argument('--workflow-sha256', required=True)
    parser.add_argument('--run-id', type=int, required=True)
    parser.add_argument('--attempt', type=int, required=True)
    parser.add_argument('--require-artifacts', action='store_true')
    parser.add_argument('--snapshot-sha256', help='External snapshot pin required for verify')
    args = parser.parse_args(argv)
    try:
        expected = Attempt(args.repository, args.source, args.event, args.head_sha or args.source,
                           args.workflow_sha256, args.run_id, args.attempt, args.require_artifacts)
        if args.action == 'collect':
            require(args.snapshot_sha256 is None, 'Collection generates a new snapshot digest')
            print(collect(args.directory, expected))
        else:
            require(args.snapshot_sha256 is not None, 'Verification requires an external snapshot digest')
            result = verify_snapshot(args.directory, args.snapshot_sha256, source=expected.source,
                                     head_sha=expected.head_sha, event=expected.event, repository=expected.repository,
                                     workflow_sha256=expected.workflow_sha256, run_id=expected.run_id,
                                     attempt=expected.attempt, require_artifacts=expected.require_artifacts)
            print(json.dumps(result, indent=2, sort_keys=True))
    except (OSError, ValueError, KeyError, TypeError, AttributeError, BadZipFile, subprocess.SubprocessError) as error:
        print(f'CI evidence check failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
