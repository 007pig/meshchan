"""Verify the recorded Beta build 5 handoff and compare closed upgrade data."""

from contextlib import closing, contextmanager
from datetime import UTC, datetime, timedelta
import fcntl
import io
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import sqlite3
import stat
import subprocess
import tarfile
import tempfile

from release_materials import digest, product_inventory, safe
from release_package_archive import directory_fd
from release_retention_archive import regular_entry
from release_retention_inputs import json_object, original_path
from retain_release import publish_seal
from verify_retention_bootstrap import read_regular


BETA_COMMIT = '0fd49a3495d972c88dee35fc709501db78a16d16'
BETA_APP = '0.1.0-beta.1+5'
BETA_CLI = '0.1.0-beta.1'
PRODUCTS_PIN = 'edcdf862edae4733ff430feafcd08537bbce5e56afa716e93553d42d3f4e5782'
INPUT_PIN = '4a38b190afe218d15a86126e3c72c0d93e225be5c58a3aef3b0237b1e8b94f8e'
DIFF_PIN = '8f92887b499d249e50d4af23389ed6679c76e8a7ac5e616a288c7965c14827bd'
HANDOFF_PIN = '3af9cbc959aeece28e054ff0c29d33840aa0ac43aaab3c558ce963eec886de13'
CLOSE_PIN = '76f4797c4831793f362514a420c8358bd56311e9c6b0521557a7c333ade58cdc'
DATABASE_PIN = '217277ba7672c02fa7ebf00f05b3e53797bb179dfb6df9e6338e51dbee23f3db'
SUMMARY_PIN = '6205733d6e8c873807db1075a40b5bd55738b5a2fe2453cb0a1fd8db972d74d0'
DATABASE = 'meshchan.sqlite'
LOCK = '.meshchan.owner.lock'
SQLITE_FILES = tuple(DATABASE + suffix for suffix in ('', '-wal', '-shm', '-journal'))
MAX_GUEST_SNAPSHOT = 64 * 1024 * 1024
HISTORY_PUBLIC_IDENTITY = {
    'runId': 'run_id', 'operation': 'operation', 'appVersion': 'app_version',
    'diagnosticSummaryFormatVersion': 'summary_format_version', 'recordState': 'record_state',
    'recoveryReason': 'recovery_reason',
}
HISTORY_PUBLIC_TIMES = {
    'preparedAt': 'prepared_at_us', 'logicalEndedAt': 'logical_ended_at_us',
    'recoveredAt': 'recovered_at_us',
}
SQL_TABLES = {
    'drafts': ('stored_drafts', 'id'),
    'profiles': ('stored_profiles', 'id'),
    'settings': ('stored_settings', 'singleton'),
    'history': ('stored_runs', 'prepared_at_us DESC, run_id DESC'),
}
NONBUILD_HANDOFF_CHANGES = {
    '.github/workflows/ci.yml', 'README.md', 'apps/meshchan_app/README.md',
    'docs/architecture/flutter-host.md', 'docs/hardware-validation.md',
    'docs/releases/phase-1d-beta1.md', 'docs/testing.md',
    'docs/validation/phase-1d11-build5-gui-delay.md',
    'docs/validation/phase-1d11-hardware-beta.md',
}


def same(expected, actual, label):
    # Python equality aliases false/0 and true/1. Evidence must preserve types.
    options = {'sort_keys': True, 'ensure_ascii': False, 'allow_nan': False}
    if json.dumps(expected, **options) != json.dumps(actual, **options):
        raise ValueError(f'{label} differs')


def regular(path):
    for parent in path.parents:
        if not stat.S_ISDIR(parent.lstat().st_mode):
            raise ValueError(f'Aliased parent for {path}')
    meta = path.lstat()
    if not stat.S_ISREG(meta.st_mode) or meta.st_nlink != 1:
        raise ValueError(f'Expected a single-link regular file: {path}')
    return meta


def pinned(path, expected):
    regular(path)
    entry, _ = regular_entry(path)
    if entry['sha256'] != expected:
        raise ValueError(f'Beta evidence digest differs: {path}')
    return path


def pinned_json(path, expected):
    regular(path)
    raw, _ = read_regular(None, path, expected_sha256=expected)
    return json_object(raw)


def beta_inventory(path, expected):
    inventory = {}
    for name, item in product_inventory(path).items():
        if item['type'] == 'symlink':
            inventory[name] = {'symlink': item['symlink']}
        elif item['type'] == 'file':
            regular(path / name)
            inventory[name] = {key: item[key] for key in ('sha256', 'size', 'mode')}
    same(expected, inventory, f'Beta product inventory {path}')


def verify_beta(evidence_root):
    """Admit the byte-identical prepared copy named by the Beta acceptance."""
    root = Path(evidence_root).absolute()
    history = root / 'hardware/run-09-rf-restart'
    retained = history / 'delivery-prepared-retained'
    metadata = retained / 'metadata'
    record = pinned_json(metadata / 'products.json', PRODUCTS_PIN)
    historical_delivery = original_path(record['app']['path']).parent
    if historical_delivery.name != 'delivery-beta1-build5':
        raise ValueError('Unexpected historical Beta delivery location')
    compilation_path = root / 'source-hw08-build5-input.json'
    compilation = pinned_json(compilation_path, INPUT_PIN)
    pinned(metadata / 'source-manifest.json', INPUT_PIN)
    diff = pinned(metadata / 'source-compilation.diff', DIFF_PIN)
    handoff_path = metadata / 'source-handoff.json'
    handoff = pinned_json(handoff_path, HANDOFF_PIN)
    differences = {name for name in compilation.keys() | handoff.keys()
                   if handoff.get(name) != compilation.get(name)}
    if differences != NONBUILD_HANDOFF_CHANGES:
        raise ValueError('Prepared Beta source has unexpected compilation-input differences')
    for name, expected in handoff.items():
        pinned(retained / 'source' / safe(name), expected)

    products = {}
    for label, name in [('app', 'Meshchan.app'), ('cli', 'meshctl')]:
        entry = record[label]
        same(str(historical_delivery / name), entry['path'], 'Beta manifest original location')
        products[label] = retained / name
        beta_inventory(products[label], entry['inventory'])
    app, cli = products.values()
    with (app / 'Contents/Info.plist').open('rb') as handle:
        plist = plistlib.load(handle)
    for key, value in {'CFBundleIdentifier': 'org.meshchan.meshchan',
                       'CFBundleExecutable': 'Meshchan',
                       'CFBundleShortVersionString': '0.1.0.1',
                       'CFBundleVersion': '5'}.items():
        same(value, plist.get(key), f'Beta {key}')
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    for name in record['cli']['inventory']:
        subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(cli / name)], check=True)

    closed_receipt = history / 'offline-host-verification.json'
    closed = pinned_json(closed_receipt, CLOSE_PIN)
    fixture = history / 'vm-source-closed-fixture'
    historical_fixture = historical_delivery.parent / fixture.relative_to(root)
    same(str(historical_fixture), closed.get('safeClosedFixtureForVm'), 'Historical closed fixture reference')
    verify_shutdown(closed['actualShutdown'])
    same(True, closed.get('osPidAbsent'), 'Historical OS exit')
    same(True, closed.get('allIndependentConsumersClosed'), 'Historical independent close')
    with ownership(fixture):
        files = sqlite_members(fixture)
        same([DATABASE], list(files), 'Historical SQLite member set')
        pinned(fixture / DATABASE, DATABASE_PIN)
    summary_path = history / 'vm-offline/Release/exports/meshchan-beta5-summary-run09.json'
    summary = pinned_json(summary_path, SUMMARY_PIN)
    history_versions = [BETA_APP] * 6 + ['0.1.0-beta.1+4'] * 4 + ['0.1.0-beta.1+3'] * 2
    same(history_versions, [run['appVersion'] for run in summary['runs']], 'Historical versions')
    same(1, summary['diagnosticSummaryFormatVersion'], 'Historical summary format')
    return {
        'app': str(app), 'cli': str(cli), 'appVersion': BETA_APP, 'cliVersion': BETA_CLI,
        'appleShortVersion': plist['CFBundleShortVersionString'],
        'appleBuild': plist['CFBundleVersion'], 'bundleId': plist['CFBundleIdentifier'],
        'productsManifest': {'path': str(metadata / 'products.json'), 'sha256': PRODUCTS_PIN},
        'source': {
            'baseCommit': BETA_COMMIT,
            'compilationManifest': {'path': str(compilation_path), 'sha256': INPUT_PIN},
            'compilationDiff': {'path': str(diff), 'sha256': DIFF_PIN},
            'handoffManifest': {'path': str(handoff_path), 'sha256': HANDOFF_PIN},
            'verifiedHandoffFiles': len(handoff),
            'nonbuildHandoffChanges': sorted(differences),
        },
        'closedFixture': str(fixture), 'closedDatabaseSha256': DATABASE_PIN,
        'closeReceipt': {'path': str(closed_receipt), 'sha256': CLOSE_PIN},
        'historySummary': {'path': str(summary_path), 'sha256': SUMMARY_PIN},
    }


def verify_shutdown(report):
    fields = {'runtime': 'meshchan.shutdown.1d3', 'quitPhase': 'ready',
              'resourcesReleased': True, 'workerExited': True, 'workerWasSpawned': True,
              'owner': 'released', 'error': None, 'maintenanceFailureCount': 0,
              'pendingRequests': 0, 'receivePorts': 0}
    same(fields, {key: report[key] for key in fields}, 'Normal GUI shutdown receipt')


@contextmanager
def ownership(source):
    """Exclude product owners with the exact BSD flock protocol used by storage."""
    path = source / LOCK
    meta = regular(path)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        current = os.fstat(fd)
        if (current.st_dev, current.st_ino, current.st_nlink) != (meta.st_dev, meta.st_ino, 1):
            raise ValueError('Ownership file changed during open')
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise ValueError('Data directory is still owned') from exc
        yield
    finally:
        os.close(fd)


def sqlite_members(source):
    result = {}
    for name in SQLITE_FILES:
        path = source / name
        try:
            meta = regular(path)
        except FileNotFoundError:
            if name == DATABASE:
                raise
            continue
        result[name] = {'sha256': digest(path), 'size': meta.st_size}
    return result


def capture_closed(source, snapshot, *, expected_main_sha256=None):
    """Copy the closed SQLite set once and project from a disposable working copy.

    The caller must first verify normal completion and PID absence. Holding the
    product's flock bars another business owner during the copy. The archived
    SQLite files retain all bytes, including sidecars, and are never opened by SQL.
    """
    source = Path(source).absolute()
    snapshot = Path(snapshot).absolute()
    if snapshot.parent.resolve(strict=True) != snapshot.parent:
        raise ValueError('Snapshot parent must be a real canonical directory')
    if snapshot.is_relative_to(source.resolve(strict=True)):
        raise ValueError('Snapshot must be outside the source data directory')
    with ownership(source):
        files = sqlite_members(source)
        if expected_main_sha256 is not None:
            same(expected_main_sha256, files[DATABASE]['sha256'], 'Closed source database digest')
        snapshot.mkdir(mode=0o700, exist_ok=False)
        for name in files:
            target = snapshot / name
            shutil.copyfile(source / name, target)
            target.chmod(0o400)
        same(files, sqlite_members(source), 'Source SQLite members after snapshot')
        same(files, sqlite_members(snapshot), 'Snapshot SQLite members')
    return project_archive(snapshot, files)


def project_archive(snapshot, files):
    with tempfile.TemporaryDirectory(prefix='meshchan-closed-projection-') as work:
        working = Path(work).resolve()
        for name in files:
            shutil.copyfile(snapshot / name, working / name)
        same(files, sqlite_members(working), 'Working SQLite members before projection')
        projection = _sqlite_projection(working)
    return {'files': files, 'database': projection}


def verify_archived_snapshot(snapshot, record):
    """Rebind a closed evidence receipt to the retained SQLite files and rows."""
    snapshot = Path(snapshot).absolute()
    if snapshot.resolve(strict=True) != snapshot or not snapshot.is_dir():
        raise ValueError('Expected a canonical closed SQLite snapshot directory')

    def archived_members():
        files = sqlite_members(snapshot)
        same(sorted(files), sorted(path.name for path in snapshot.iterdir()), 'Archived SQLite member set')
        return files

    files = archived_members()
    same(record['files'], files, 'Archived SQLite member hashes')
    actual = project_archive(snapshot, files)
    same(files, archived_members(), 'Archived SQLite members after reprojection')
    same(record['database'], actual['database'], 'Archived SQLite projection')
    return actual


GUEST_STORAGE_LOCK = r'''
use strict;
use warnings;
sub lock_default_storage {
    my ($directory) = @_;
    die "Aliased guest home\n" unless -d $directory && !-l $directory;
    for ('Library', 'Application Support', 'meshchan') {
        $directory .= "/$_";
        die "Aliased or missing default directory\n" unless -d $directory && !-l $directory;
    }
    chdir($directory) or die "Cannot enter default directory: $!\n";
    my $lockname = '.meshchan.owner.lock';
    my @lockpath = lstat $lockname;
    die "Wrong ownership file\n" unless @lockpath && S_ISREG($lockpath[2]) && $lockpath[3] == 1;
    sysopen(my $lock, $lockname, O_RDONLY|O_NOFOLLOW|O_NONBLOCK) or die "Cannot open ownership file: $!\n";
    my @lockfile = stat $lock;
    die "Ownership file changed\n" unless @lockfile && $lockfile[0] == $lockpath[0]
        && $lockfile[1] == $lockpath[1] && $lockfile[3] == 1;
    flock($lock, LOCK_EX|LOCK_NB) or die "Directory still owned: $!\n";
    @lockpath = lstat $lockname;
    die "Ownership file changed\n" unless @lockpath && $lockpath[0] == $lockfile[0]
        && $lockpath[1] == $lockfile[1] && $lockpath[3] == 1;
    return $lock;
}
'''


GUEST_STORAGE_PROBE = GUEST_STORAGE_LOCK + r'''
my $user = shift @ARGV;
my @account = getpwuid($<);
die "Wrong default directory account\n" unless @account && $account[0] eq $user
    && $account[7] eq "/Users/$user";
my $lock = lock_default_storage($account[7]);
'''


GUEST_DATABASE_ARCHIVE = GUEST_STORAGE_PROBE + r'''
my ($limit, @names) = @ARGV;
my @files;
my $size = 0;
for (@names) {
    my @file = lstat $_;
    next if !@file && $_ ne $names[0] && $!{ENOENT};
    die "Invalid SQLite member $_\n" unless @file && S_ISREG($file[2]) && $file[3] == 1;
    $size += $file[7];
    die "Guest SQLite set exceeds the evidence size limit\n" if $size > $limit;
    push @files, $_;
}
$ENV{COPYFILE_DISABLE} = 1;
system('/usr/bin/tar', '-cf', '-', '--', @files) == 0 or die "Guest SQLite archive failed\n";
'''


def require_guest_storage_released(remote, user):
    """Check that the exact guest default-directory lock has no active owner."""
    if type(user) is not str or not re.fullmatch(r'[a-z_][a-z0-9_-]*', user):
        raise ValueError('Expected the confirmed guest account')
    command = shlex.join(('/usr/bin/perl', '-MFcntl=:DEFAULT,:flock,:mode', '-e', GUEST_STORAGE_PROBE,
                          '--', user))
    try:
        result = remote(command, capture_output=True, text=True, timeout=10)
    except subprocess.CalledProcessError as error:
        result = error
    if type(result.returncode) is not int or result.returncode != 0:
        detail = (result.stderr or '').strip()
        raise ValueError('Guest default directory release unverified' + (': ' + detail if detail else ''))


def extract_guest_archive(raw, snapshot):
    if len(raw) > MAX_GUEST_SNAPSHOT + 64 * 1024:
        raise ValueError('Guest archive exceeds the evidence size limit')
    with tarfile.open(fileobj=io.BytesIO(raw), mode='r:') as archive:
        members = archive.getmembers()
        names = [member.name for member in members]
        if (DATABASE not in names or len(names) != len(set(names))
                or any(not member.isreg() or member.issparse() or member.name not in SQLITE_FILES
                       for member in members)
                or sum(member.size for member in members) > MAX_GUEST_SNAPSHOT):
            raise ValueError('Unexpected guest SQLite archive member set')
        for member in members:
            target = snapshot / member.name
            with archive.extractfile(member) as incoming, target.open('xb') as outgoing:
                shutil.copyfileobj(incoming, outgoing)
            target.chmod(0o400)


def capture_guest_closed(remote, user, pid, report, snapshot):
    """Collect a closed guest default database through the authenticated VM controller."""
    if (type(user) is not str or not re.fullmatch(r'[a-z_][a-z0-9_-]*', user)
            or type(pid) is not int or pid <= 1):
        raise ValueError('Expected the confirmed guest account and observed application PID')
    verify_shutdown(report)
    snapshot = Path(snapshot).absolute()
    if snapshot.parent.resolve(strict=True) != snapshot.parent or os.path.lexists(snapshot):
        raise ValueError('Expected a fresh snapshot under a real canonical evidence directory')
    command = ['/usr/bin/perl', '-MFcntl=:DEFAULT,:flock,:mode', '-e', GUEST_DATABASE_ARCHIVE,
               '--', user, str(MAX_GUEST_SNAPSHOT), *SQLITE_FILES]
    script = (f'if /bin/ps -p {pid} -o pid= >/dev/null; then '
              'echo "GUI PID still exists" >&2; exit 1; fi\n' + shlex.join(command))
    result = remote(script, capture_output=True, timeout=30)
    same(0, result.returncode, 'Guest snapshot collection exit')
    with tempfile.TemporaryDirectory(prefix='.closed-sqlite-', dir=snapshot.parent) as temporary:
        stage = Path(temporary)
        extract_guest_archive(result.stdout, stage)
        report = project_archive(stage, sqlite_members(stage))
        with directory_fd(snapshot.parent) as parent:
            publish_seal(stage, snapshot, parent, stage.lstat())
    return report


def _sqlite_projection(working):
    # SQLite may need to recover a hot journal in this disposable copy.
    # The archived database and its sidecars never reach the SQL connection.
    uri = (working / DATABASE).as_uri() + '?mode=rw'
    with closing(sqlite3.connect(uri, uri=True)) as db:
        db.row_factory = sqlite3.Row
        schema = db.execute('PRAGMA user_version').fetchone()[0]
        same(1, schema, 'Database schema version')
        db.execute('PRAGMA query_only = ON')
        integrity = db.execute('PRAGMA integrity_check(1)').fetchone()[0]
        same('ok', integrity, 'SQLite integrity check')
        if db.execute('PRAGMA foreign_key_check').fetchone() is not None:
            raise ValueError('SQLite foreign-key check failed')
        projection = {'schemaVersion': schema}
        for key, (table, order) in SQL_TABLES.items():
            projection[key] = [dict(row) for row in db.execute(f'SELECT * FROM {table} ORDER BY {order}')]
    for row in projection['history']:
        same(1, row['summary_format_version'], 'Stored summary format version')
        if row['record_state'] not in {'settled', 'recovered_archived'}:
            raise ValueError('History contains an unsettled record')
    return projection


def add_draft(drafts, new_draft):
    fields = {'id', 'title', 'body', 'revision', 'created_at_us', 'updated_at_us'}
    if (set(new_draft) != fields or type(new_draft['id']) is not str
            or not re.fullmatch(r'[0-9a-f]{32}', new_draft['id'])
            or any(type(new_draft[field]) is not str for field in ('title', 'body'))
            or type(new_draft['created_at_us']) is not int or new_draft['created_at_us'] <= 0
            or new_draft['id'] in {row['id'] for row in drafts}):
        raise ValueError('Invalid declared new draft')
    same(1, new_draft['revision'], 'New draft revision')
    same(new_draft['created_at_us'], new_draft['updated_at_us'], 'New draft timestamps')
    return sorted([*drafts, new_draft], key=lambda row: row['id'])


def compare_sqlite(before, after, *, new_draft=None, history_limit=None):
    """Allow one exact new draft and one declared settings history-limit save."""
    expected = dict(before)
    if new_draft is not None:
        expected['drafts'] = add_draft(before['drafts'], new_draft)
    if history_limit is not None:
        if (type(history_limit) is not int or not 1 <= history_limit <= 100000
                or history_limit < len(before['history']) or len(before['settings']) != 1
                or before['settings'][0]['diagnostic_history_limit'] == history_limit):
            raise ValueError('Invalid declared History retention change')
        expected['settings'] = [dict(before['settings'][0], diagnostic_history_limit=history_limit)]
    same(sorted(expected), sorted(after), 'Closed database projection fields')
    for field, value in expected.items():
        same(value, after[field], 'Closed database ' + field)


def _successful(result, command, action):
    expected = {'schemaVersion': 1, 'command': command, 'action': action,
                'operationSucceeded': True, 'reason': 'completed', 'exitCode': 0,
                'failure': None, 'storageClose': {'state': 'closed', 'error': None},
                'hostCleanup': 'succeeded', 'additionalFailures': []}
    same(0, result.returncode, f'{command} {action} process exit')
    export = command == 'history' and action == 'export'
    if export:
        value = json_object(result.stderr)
        expected.update({'event': 'metadata', 'nextCursor': None})
    else:
        value = json_object(result.stdout)
        expected['committed'] = None
    same(expected, {field: value[field] for field in expected}, f'{command} {action} envelope')
    maintenance = value['maintenance']
    same(None, maintenance['unacknowledgedFailure'], 'CLI maintenance failure')
    same(0, maintenance['unacknowledgedFailureCount'], 'CLI maintenance failure count')
    same(0, maintenance['latest']['deletedCount'], 'CLI maintenance deletions')
    return json_object(result.stdout) if export else value


def capture_cli(invoke):
    """Project a finite settled fixture through installed default-directory commands.

    Each call receives leaf command arguments and must return the real process
    exit code, stdout and stderr. The caller binds the executable and account.
    """
    projection = {'schemaVersion': 1}
    for command, key, timestamp, detail_only in (
            ('draft', 'id', 'updatedAt', {'body'}),
            ('profile', 'id', 'updatedAt', {'portHint', 'parameters'}),
            ('history', 'runId', 'preparedAt', {'configuration'})):
        listed = _successful(invoke(command, 'list', '--limit', '200', '--json'), command, 'list')
        same(None, listed['nextCursor'], command + ' complete page')
        ids = [item[key] for item in listed['items']]
        if (any(type(value) is not str or not re.fullmatch(r'[0-9a-f]{32}', value) for value in ids)
                or len(ids) != len(set(ids))):
            raise ValueError(f'Invalid {command} identifiers')
        inner = 'run' if command == 'history' else command
        shown = [_successful(invoke(command, 'show', '--id', item, '--json'), command, 'show')[inner]
                 for item in ids]
        same(ids, [item[key] for item in shown], command + ' list/show identity')
        expected_items = [{field: value for field, value in item.items() if field not in detail_only}
                          for item in shown]
        expected_items.sort(key=lambda item: (datetime.fromisoformat(item[timestamp]), item[key]),
                            reverse=True)
        same(expected_items, listed['items'], command + ' list/show fields and order')
        if command == 'history':
            projection['history'] = {'items': listed['items'], 'details': shown}
        else:
            projection[command + 's'] = sorted(shown, key=lambda item: item[key])
    settings = _successful(invoke('settings', 'show', '--json'), 'settings', 'show')
    projection['settings'] = settings['settings']
    summary = _successful(invoke('history', 'export', '--limit', '200'), 'history', 'export')
    same(['diagnosticSummaryFormatVersion', 'exportedAt', 'runs'], sorted(summary),
         'CLI diagnostic summary envelope fields')
    same(1, summary['diagnosticSummaryFormatVersion'], 'CLI diagnostic summary format')
    time = summary['exportedAt']
    if type(time) is not str or not time.endswith('Z') or datetime.fromisoformat(time).tzinfo != UTC:
        raise ValueError('Expected a UTC diagnostic export timestamp')
    shared = HISTORY_PUBLIC_IDENTITY.keys() | HISTORY_PUBLIC_TIMES.keys()
    same([{key: row[key] for key in shared} for row in projection['history']['details']],
         [{key: row[key] for key in shared} for row in summary['runs']], 'CLI History detail/export identity')
    projection['summary'] = {key: summary[key] for key in ('diagnosticSummaryFormatVersion', 'runs')}
    return projection


def cli_date(microseconds):
    timestamp = datetime(1970, 1, 1, tzinfo=UTC) + timedelta(microseconds=microseconds)
    return timestamp.isoformat(timespec='microseconds').replace('+00:00', 'Z')


def verify_history_export(public, database):
    """Match the version-1 public export with the separately closed SQLite history."""
    expected = []
    for row in database['history']:
        exported = {name: row[column] for name, column in HISTORY_PUBLIC_IDENTITY.items()}
        exported.update({name: (None if row[column] is None else cli_date(row[column]))
                         for name, column in HISTORY_PUBLIC_TIMES.items()})
        for name in ('configuration', 'result', 'cleanup'):
            encoded = row[name + '_json']
            exported[name] = None if encoded is None else json_object(encoded)
        expected.append(exported)
    same(expected, public['summary']['runs'], 'CLI History export against closed SQLite')


def compare_cli(before, after, *, new_draft=None, history_limit=None):
    """Check public disk reads against the same declared SQLite changes."""
    expected = dict(before)
    if new_draft is not None:
        add_draft(before['drafts'], new_draft)
        date = cli_date(new_draft['created_at_us'])
        draft = {field: new_draft[field] for field in ('id', 'title', 'body', 'revision')}
        draft.update({'createdAt': date, 'updatedAt': date,
                      'bodyUtf8ByteLength': len(draft['body'].encode('utf-8'))})
        expected['drafts'] = sorted([*before['drafts'], draft], key=lambda row: row['id'])
    if history_limit is not None:
        expected['settings'] = dict(before['settings'], diagnosticHistoryLimit=history_limit)
    same(sorted(expected), sorted(after), 'CLI projection fields')
    for field, value in expected.items():
        same(value, after[field], 'CLI projection ' + field)


def verify_busy(result):
    same(69, result.returncode, 'CLI contender process exit')
    value = json_object(result.stdout)
    expected = {'schemaVersion': 1, 'command': 'draft', 'action': 'list',
                'operationSucceeded': False, 'committed': False, 'exitCode': 69,
                'reason': 'business_failure', 'additionalFailures': [],
                'maintenance': None, 'storageClose': None, 'hostCleanup': 'succeeded',
                'failure': {'domain': 'storage', 'source': 'open',
                            'code': 'data_directory_busy', 'cleanupUnconfirmed': False}}
    same(expected, value, 'CLI contender envelope')
