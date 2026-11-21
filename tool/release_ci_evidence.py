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
MERGE_REF = re.compile(rb'(?m)^\S+ \[command\][^\r\n]+/git checkout .*pull/([1-9][0-9]*)/merge\r?$')


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


def load_json(data):
    def unique_object(pairs):
        result = {}
        for name, value in pairs:
            require(name not in result, f'Duplicate JSON field: {name}')
            result[name] = value
        return result

    return json.loads(data, object_pairs_hook=unique_object)


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
                and positive_int(record.get('run_attempt')) and record['run_attempt'] == expected.attempt
                and record.get('event') == expected.event and record.get('head_sha') == expected.head_sha
                and record.get('repository', {}).get('full_name') == expected.repository
                and record.get('path') == WORKFLOW,
                'GitHub run or attempt has a different repository, event, head or workflow identity')
        require(record.get('status') == 'completed' and record.get('conclusion') == 'success',
                'GitHub run and selected attempt must be completed with a success conclusion')
    for key in ('workflow_id', 'check_suite_id', 'head_branch', 'run_started_at'):
        require(run.get(key) and run[key] == attempt.get(key), f'Run and attempt disagree on {key}')
    require(positive_int(attempt['repository'].get('id')), 'Missing repository ID')
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


def verify_checkouts(data, jobs, expected):
    merge_numbers = set()
    with ZipFile(io.BytesIO(data)) as archive:
        for name in jobs:
            matches = [member for member in archive.infolist()
                       if re.fullmatch(rf'[0-9]+_{re.escape(name)}\.txt', member.filename)]
            require(len(matches) == 1 and matches[0].file_size <= MAX_FILE_BYTES,
                    f'Missing or repeated GitHub job log: {name}')
            log = archive.read(matches[0])
            checkouts = CHECKOUT.findall(log)
            require(checkouts == [expected.source.encode()], f'Actual checkout log disagrees for {name}')
            if expected.event == 'pull_request':
                refs = MERGE_REF.findall(log)
                require(len(refs) == 1, f'Missing pull request merge ref in checkout log: {name}')
                merge_numbers.add(int(refs[0]))
    if expected.event == 'pull_request':
        require(len(merge_numbers) == 1, 'Jobs checked out different pull requests')
        return merge_numbers.pop()
    return None


def read_artifacts(read, rows, jobs, attempt, expected, collected_at, pr_number):
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
        requested_ref = (f'refs/pull/{pr_number}/merge' if pr_number is not None
                         else f'refs/heads/{attempt["head_branch"]}')
        with ZipFile(io.BytesIO(data)) as archive:
            report = verify_job_zip(
                archive, repository=expected.repository, event=expected.event, checkout_sha=expected.source,
                requested_sha=expected.source, requested_ref=requested_ref, workflow_sha256=expected.workflow_sha256,
                run_id=expected.run_id, attempt=expected.attempt, job=job,
            )
        require(report.get('workflow_sha') == expected.source, f'Workflow source differs in artifact: {name}')
        require(report.get('job_id') == job_data['id'], f'GitHub job ID differs in artifact: {name}')
        if pr_number is not None:
            pr = report.get('pull_request', {})
            require(pr.get('number') == pr_number and pr.get('head_sha') == expected.head_sha
                    and pr.get('merge_sha') == expected.source, f'PR identity differs in artifact: {name}')
        require(any(step.get('name') == 'Upload CI job evidence' and step.get('conclusion') == 'success'
                    for step in job_data.get('steps', [])), f'No successful upload step for {name}')
        artifacts.append({'id': artifact_id, 'job': job, 'name': name, 'sha256': digest.removeprefix('sha256:'),
                          'size': size, 'created_at': artifact['created_at'], 'expires_at': expiry,
                          'download_url': API + endpoint, 'file': filename})
    return artifacts


def inspect(read, expected, collected_at):
    attempt = run_metadata(read, expected)
    jobs = successful_jobs(read, expected)
    workflow = read('workflow.yml', f'repos/{expected.repository}/contents/{WORKFLOW}?ref={expected.source}', raw=True)
    require(sha256(workflow) == expected.workflow_sha256, 'GitHub workflow bytes differ from their external digest')
    logs = read('logs.zip', f'{expected.attempt_endpoint}/logs')
    pr_number = verify_checkouts(logs, jobs, expected)
    if pr_number is not None:
        commit = load_json(read('merge-commit.json', f'repos/{expected.repository}/git/commits/{expected.source}'))
        parents = [parent.get('sha') for parent in commit.get('parents', [])]
        require(commit.get('sha') == expected.source and len(parents) == 2 and parents[1] == expected.head_sha,
                'GitHub merge checkout parents do not match the requested PR head')
    rows = paginated(read, f'{expected.endpoint}/artifacts', 'artifacts')
    artifacts = read_artifacts(read, rows, jobs, attempt, expected, collected_at, pr_number)
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
                    event='push', repository='007pig/meshchan', run_id=None, attempt=None, head_sha=None):
    """Verify the supplied pin, original responses, attempt identity and downloaded objects offline."""
    directory = Path(directory)
    require(directory.is_dir() and not directory.is_symlink(), 'Expected a real CI snapshot directory')
    raw = read_file(directory / MANIFEST)
    require(sha256(raw) == expected_pin, 'CI snapshot manifest does not match the external digest')
    manifest = load_json(raw)
    expected = Attempt(repository, source, event, head_sha or source, workflow_sha256,
                       manifest['run_id'] if run_id is None else run_id,
                       manifest['attempt'] if attempt is None else attempt, require_artifacts)
    validate_manifest(directory, manifest, expected, MANIFEST)
    return manifest


def validate_manifest(directory, manifest, expected, manifest_filename):
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

    summary = inspect(read, expected, collected_at)
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
