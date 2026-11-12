#!/usr/bin/env python3
"""Generate a schema-1 file with controlled dev.2 source, then open it with dev.3."""
import argparse
from contextlib import closing
import datetime
import io
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tarfile

from candidate_common import ROOT, digest, product_inputs, write_json
from smoke_cli import Checks, executable, nonempty_history_checks

BASELINE = 'e237be5c2fb9e4fd1cf2f2c26717582f34a5e757'


def rows(directory):
    uri = (directory / 'meshchan.sqlite').resolve().as_uri() + '?mode=ro'
    with closing(sqlite3.connect(uri, uri=True)) as db:
        if db.execute('PRAGMA user_version').fetchone()[0] != 1:
            raise ValueError('Expected real database schema 1')
        return {table: db.execute('SELECT * FROM ' + table + ' ORDER BY 1').fetchall()
                for table in ('stored_drafts', 'stored_profiles', 'stored_settings', 'stored_runs')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-directory', type=Path, required=True)
    parser.add_argument('--dart', type=executable, required=True)
    args = parser.parse_args()
    base = args.build_directory.resolve()
    folder = base / 'schema-compatibility'
    folder.mkdir(exist_ok=False)
    old = folder / 'dev2-source'
    old.mkdir()
    archived = subprocess.check_output(['git', 'archive', BASELINE], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archived)) as tar:
        tar.extractall(old, filter='data')
    # Only the new development harness is overlaid. Old production source and
    # its version stay exactly at the named baseline; no private SQL seeding.
    overlays = ['apps/meshctl/tool/datagram_acceptance.dart',
                'apps/meshctl/test/support/datagram_acceptance_scenarios.dart']
    for name in overlays:
        shutil.copy2(ROOT / name, old / name)
    env = {**os.environ, 'PATH': '/usr/bin:/bin:/opt/homebrew/bin:' + os.environ.get('PATH', '')}
    checks = Checks(env=env)
    checks.check('legacy locked resolution', [str(args.dart), 'pub', 'get', '--enforce-lockfile'], old, out='')
    legacy = folder / 'legacy database'
    checks.check('dev.2 controlled CLI/core recording', [str(args.dart), '--enable-asserts', 'run',
        'tool/datagram_acceptance.dart', '--recording-directory', str(legacy),
        '--expected-version', '0.1.0-dev.2', '--legacy-fixture'], old / 'apps/meshctl', out='')
    before = rows(legacy)
    if not all(before.values()) or before['stored_runs'][0][2] != '0.1.0-dev.2':
        raise ValueError('Legacy fixture lacks actual business data and old version')
    shutil.copytree(legacy, folder / 'original closed fixture')
    old_hash = digest(legacy / 'meshchan.sqlite')
    current = base / 'acceptance/bundle/bin/datagram_acceptance'
    checks.check('dev.3 AOT runCli/core records into schema-1 file',
        [str(current), '--recording-directory', str(legacy)], folder, out='')
    product = base / 'cli/bundle/bin/meshctl'
    checks.check('new product business commit into legacy file', [str(product), '--data-dir', str(legacy),
        'draft', 'create', '--body=new dev.3 中文😀', '--json'], folder, out='')
    nonempty_history_checks(checks, 'schema compatibility', [str(product)], folder, legacy)
    after = rows(legacy)
    for table, existing in before.items():
        if any(row not in after[table] for row in existing):
            raise ValueError('Upgrade changed old row bytes/IDs/revision/times/configuration: ' + table)
    if len(after['stored_runs']) != len(before['stored_runs']) + 3:
        raise ValueError('Unexpected recording count')
    if any(row[2] != '0.1.0-dev.3' for row in after['stored_runs'] if row not in before['stored_runs']):
        raise ValueError('New run appVersion mismatch')
    rejected = []
    for name in ('future', 'corrupt'):
        target = folder / name
        target.mkdir()
        path = target / 'meshchan.sqlite'
        if name == 'future':
            shutil.copy2(legacy / path.name, path)
            with sqlite3.connect(path) as db:
                db.execute('PRAGMA user_version=2')
        else:
            path.write_bytes(b'controlled corrupt database\x00')
        previous = digest(path)
        def failure(value):
            data = json.loads(value)
            expected = 'unsupported_database_version' if name == 'future' else 'database_corrupt'
            if data['failure']['code'] != expected:
                raise ValueError('Wrong schema rejection')
        checks.check('preserve rejected ' + name, [str(product), '--data-dir', str(target),
            'draft', 'list', '--json'], folder, code=74, out='', validate=failure)
        if digest(path) != previous:
            raise ValueError('Rejected original database changed')
        rejected.append({'fixture': name, 'sha256BeforeAndAfter': previous})
    write_json(base / 'schema-compatibility.json', {'status': 'PASS',
        'processPath': env['PATH'], 'dartExecutable': str(args.dart),
        'baselineCommit': BASELINE, 'baselineProductionSource': 'git archive; no production overlay',
        'harnessOverlays': {p: digest(ROOT / p) for p in overlays},
        'productCompilationInputHashes': product_inputs(), 'oldDatabaseSha256': old_hash,
        'originalClosedFixture': str(folder / 'original closed fixture'),
        'newDatabaseSha256': digest(legacy / 'meshchan.sqlite'),
        'preservedTables': list(before), 'oldAppVersion': '0.1.0-dev.2', 'newAppVersion': '0.1.0-dev.3',
        'recoveryRetention': 'No residual rows; limit 1000. Existing recovery/retention suites remain the separate contract gate.',
        'rejections': rejected, 'checks': checks.records,
        'verifiedUtc': datetime.datetime.now(datetime.timezone.utc).isoformat()})


if __name__ == '__main__':
    main()
