"""Stage the accepted Beta fixture and compare installed business behavior."""

import json
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import shlex
import shutil
import stat
import subprocess
import tarfile
import tempfile

import installed_release_beta as beta
from installed_release_files import verify_guest_tree
from release_materials import controlled_environment, product_inventory
from release_package_archive import archive_members, create_archive, directory_fd, prefixed
from retain_release import publish_seal


APP = 'Meshchan.app'
CLI = 'meshctl'
CLI_BINARY = 'bin/meshctl'
BETA_SOURCE_SNAPSHOT = 'beta-source-closed'
BETA_STAGE_ATTEMPT = 'beta-stage-attempt'
BETA_STAGE_COMMIT = '.meshchan-beta-stage-commit'
ARCHIVE_DATA = 'data'
EMPTY_PUBLIC = {
    'drafts': [], 'profiles': [], 'settings': {'defaultProfileId': None, 'diagnosticHistoryLimit': 1000},
    'history': {'items': [], 'details': []}, 'schemaVersion': 1,
    'summary': {'diagnosticSummaryFormatVersion': 1, 'runs': []},
}
EMPTY_DATABASE = {
    'drafts': [], 'profiles': [], 'history': [], 'schemaVersion': 1,
    'settings': [{'singleton': 1, 'default_profile_id': None, 'diagnostic_history_limit': 1000}],
}
q = shlex.quote

# NSFileManager's exact destination operation refuses occupied directories.
# Keeping the moves on one filesystem avoids its cross-volume copy fallback.
PUBLISH_BETA = r'''
ObjC.import('Foundation');

function run(argv) {
    const manager = $.NSFileManager.defaultManager;
    const scratch = argv[0];
    const destinations = JSON.parse(argv[1]);
    const moved = [];

    function directory(path) {
        const attrs = manager.attributesOfItemAtPathError(path, null);
        if (attrs.isNil() || ObjC.unwrap(attrs.objectForKey('NSFileType')) !== 'NSFileTypeDirectory') {
            throw Error('Expected a physical stage directory: ' + path);
        }
        const device = ObjC.unwrap(attrs.objectForKey('NSFileSystemNumber').stringValue);
        const inode = ObjC.unwrap(attrs.objectForKey('NSFileSystemFileNumber').stringValue);
        return { device, stamp: device + ':' + inode };
    }

    const moves = destinations.map(([prefix, target]) => {
        const source = scratch + '/' + prefix;
        const parent = target.slice(0, target.lastIndexOf('/'));
        const original = directory(source);
        const destinationParent = directory(parent);
        if (original.device !== destinationParent.device) {
            throw Error('Beta staging requires one filesystem: ' + target);
        }
        return { source, target, parent, original, destinationParent };
    });
    try {
        for (const plan of moves) {
            if (directory(plan.parent).stamp !== plan.destinationParent.stamp
                    || !manager.moveItemAtPathToPathError(plan.source, plan.target, null)) {
                throw Error('Could not exclusively publish the Beta destination: ' + plan.target);
            }
            moved.push(plan);
        }
    } catch (error) {
        const remaining = [];
        for (const plan of moved.reverse()) {
            try {
                if (directory(plan.parent).stamp !== plan.destinationParent.stamp
                        || directory(plan.target).stamp !== plan.original.stamp
                        || !manager.moveItemAtPathToPathError(plan.target, plan.source, null)) {
                    remaining.push(plan.target);
                }
            } catch (_) {
                remaining.push(plan.target);
            }
        }
        if (remaining.length) {
            throw Error(error.message + '. Rollback could not reclaim: ' + remaining.join(', '));
        }
        throw error;
    }
}
'''


def product_manifest(admitted):
    manifest = admitted['productsManifest']
    beta.same(beta.PRODUCTS_PIN, manifest['sha256'], 'Beta products manifest pin')
    return beta.pinned_json(Path(manifest['path']), beta.PRODUCTS_PIN)


def require_beta_data(members):
    # The independently admitted historical Beta fixture has no sidecars.
    beta.same([beta.DATABASE], list(members), 'Historical Beta SQLite member set')
    beta.same(beta.DATABASE_PIN, members[beta.DATABASE]['sha256'], 'Historical Beta database pin')


def beta_source_snapshot(admitted, snapshot):
    beta.same(beta.DATABASE_PIN, admitted['closedDatabaseSha256'], 'Beta data member pin')
    if not os.path.lexists(snapshot):
        with tempfile.TemporaryDirectory(prefix='.beta-source-attempt.', dir=snapshot.parent) as temporary:
            pending = Path(temporary)
            captured = pending/'closed'
            closed = beta.capture_closed(Path(admitted['closedFixture']), captured,
                                         expected_main_sha256=beta.DATABASE_PIN)
            require_beta_data(closed['files'])
            (captured/beta.DATABASE).rename(pending/beta.DATABASE)
            captured.rmdir()
            with directory_fd(snapshot.parent) as parent:
                publish_seal(pending, snapshot, parent, pending.lstat())
        return closed
    # A failed guest attempt can leave a completed private host capture.
    # Reuse only that exact, read-only historical database.
    metadata = snapshot.lstat()
    if (snapshot.resolve(strict=True) != snapshot or not stat.S_ISDIR(metadata.st_mode)
            or stat.S_IMODE(metadata.st_mode) != 0o700 or metadata.st_uid != os.getuid()
            or {path.name for path in snapshot.iterdir()} != {beta.DATABASE}):
        raise ValueError('Expected an intact private Beta source snapshot for retry')
    database = beta.regular(snapshot/beta.DATABASE)
    if database.st_uid != os.getuid() or stat.S_IMODE(database.st_mode) != 0o400:
        raise ValueError('Expected an intact read-only Beta source database for retry')
    files = beta.sqlite_members(snapshot)
    require_beta_data(files)
    closed = beta.project_archive(snapshot, files)
    beta.same(files, beta.sqlite_members(snapshot), 'Beta source snapshot after reprojection')
    return closed


def stage_paths(vm, layout, beta_cli_root):
    user = vm.c['user']
    home = PurePosixPath('/Users', user)
    support = home/'Library/Application Support'
    app, data = home/'Applications'/APP, support/'meshchan'
    cli = PurePosixPath(beta_cli_root)
    if (not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_-]*', user)
            or (layout['home'], layout['app'], layout['data']) != tuple(map(str, (home, app, data)))
            or str(cli) != str(beta_cli_root) or cli.name != CLI
            or cli.parent.parent != support/'meshchan-engineering/beta-reference'
            or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,63}', cli.parent.name)):
        raise ValueError('Expected exact owned Beta guest destinations')
    return home, {APP: app, CLI: cli, ARCHIVE_DATA: data}


def staged_commit_path(destinations):
    return destinations[CLI].parent/BETA_STAGE_COMMIT


def receipt_bytes(receipt):
    return (json.dumps(receipt, sort_keys=True, separators=(',', ':'))+'\n').encode()


def stage_attempt(evidence, destinations, transfer):
    """Commit the expected guest publication identity before opening SSH."""
    directory = evidence/BETA_STAGE_ATTEMPT
    record = {'formatVersion': 1, 'destinations': {key: str(path) for key, path in destinations.items()},
              'productsManifestSha256': beta.PRODUCTS_PIN, 'sourceDatabaseSha256': beta.DATABASE_PIN,
              'transferArchive': transfer}
    if os.path.lexists(directory):
        path = directory/'receipt.json'
        beta.regular(path)
        saved = beta.json_object(path.read_bytes())
        nonce = saved.get('nonce')
        if (directory.resolve(strict=True) != directory or type(nonce) is not str
                or re.fullmatch(r'[0-9a-f]{32}', nonce) is None):
            raise ValueError('Expected a canonical Beta stage attempt and valid nonce')
        beta.same({**record, 'nonce': nonce}, saved, 'Beta stage attempt identity')
        return saved, True
    record['nonce'] = secrets.token_hex(16)
    with tempfile.TemporaryDirectory(prefix='.beta-stage-attempt.', dir=evidence) as temporary:
        stage = Path(temporary)
        path = stage/'receipt.json'
        path.write_bytes(receipt_bytes(record))
        path.chmod(0o400)
        with directory_fd(evidence) as parent:
            publish_seal(stage, directory, parent, stage.lstat())
    return record, False


def read_guest_commit(vm, destinations, attempt):
    marker = staged_commit_path(destinations)
    path = q(str(marker/'receipt.json'))
    target = q(str(marker))
    expected = receipt_bytes(attempt)
    command = f'''set -e
if test ! -e {target} && test ! -L {target}; then exit 0; fi
test "$(cd {target} && /bin/pwd -P)" = {target}
test -f {path} && test ! -L {path}
test "$(/usr/bin/stat -f '%u %p %l %z' {path})" = "$(/usr/bin/id -u) 100600 1 {len(expected)}"
/bin/cat {path}
'''
    result = vm.remote(command, capture_output=True, timeout=15)
    beta.same(0, result.returncode, 'Guest Beta stage marker read')
    if result.stdout == b'':
        return False
    if result.stdout != expected:
        raise ValueError('Guest Beta stage marker differs from the recorded attempt')
    return True


def guest_stage_script(home, destinations, cli_inventory, database_files, attempt):
    support = home/'Library/Application Support'
    parents = [home/'Applications']
    parents.extend(p for p in reversed(destinations[CLI].parents) if p.is_relative_to(support) and p != support)
    script = [
        'set -euo pipefail',
        'umask 077',
        f'test "$HOME" = {q(str(home))}',
        f'test "$(/usr/bin/id -un)" = {q(home.name)}',
        'uid=$(/usr/bin/id -u)',
        '''owned_dir() {
    test -d "$1" && test ! -L "$1"
    test "$(cd "$1" && /bin/pwd -P)" = "$1"
    test "$(/usr/bin/stat -f %u "$1")" = "$uid"
}''',
        '''vacant() {
    if test -e "$1" || test -L "$1"; then
        printf 'Beta stage destination is occupied: %s\n' "$1" >&2
        exit 1
    fi
}''',
        '''check_parent() {
    if test -e "$1" || test -L "$1"; then owned_dir "$1"; fi
}''',
        '''prepare_parent() {
    if test ! -e "$1" && test ! -L "$1"; then
        /bin/mkdir -m 700 "$1"
        printf '%s\t%s\n' "$(/usr/bin/stat -f %d:%i "$1")" "$1" >> "$scratch/created-parents"
    fi
    owned_dir "$1"
}''',
        '''finish() {
    result=$?
    trap - EXIT HUP INT TERM
    if test "$result" -ne 0 && test -f "$scratch/publishing"; then
        printf 'Beta staging failed during publication; retained private scratch: %s\n' "$scratch" >&2
        if test -f "$scratch/created-parents"; then
            /usr/bin/tail -r "$scratch/created-parents" |
            while IFS="$(printf '\t')" read -r stamp parent; do
                if test ! -L "$parent" && test "$(/usr/bin/stat -f %d:%i "$parent")" = "$stamp"; then
                    /bin/rmdir "$parent" 2>/dev/null || :
                fi
            done
        fi
    else
        /bin/rm -rf -- "$scratch" || printf 'Retained private Beta stage scratch: %s\n' "$scratch" >&2
    fi
    exit "$result"
}''',
        *(shlex.join(('owned_dir', str(path))) for path in (home, home/'Library', support)),
        *(shlex.join(('check_parent', str(path))) for path in parents),
        *(shlex.join(('vacant', str(path))) for path in destinations.values()),
        shlex.join(('vacant', str(staged_commit_path(destinations)))),
        f'scratch=$(/usr/bin/mktemp -d {q(str(home/".meshchan-beta-stage.XXXXXXXX"))})',
        'trap finish EXIT',
        "trap 'exit 1' HUP INT TERM",
        'export COPYFILE_DISABLE=1',
        '/usr/bin/tar -xpkf - -C "$scratch"',
        f'/usr/bin/codesign --verify --deep --strict "$scratch"/{q(APP)}',
    ]
    for name in sorted(cli_inventory):
        script.append(f'/usr/bin/codesign --verify --strict "$scratch"/{q(CLI+"/"+name)}')
    for name, member in sorted(database_files.items()):
        file = f'"$scratch"/{q(ARCHIVE_DATA+"/"+name)}'
        script.extend([
            f'test "$(/usr/bin/stat -f %p {file})" = 100600',
            f'checksum=$(/usr/bin/shasum -a 256 < {file})',
            f'test "${{checksum%% *}}" = {q(member["sha256"])}',
        ])
    publication = {**destinations, BETA_STAGE_COMMIT: staged_commit_path(destinations)}
    plan = json.dumps([(prefix, str(destination)) for prefix, destination in publication.items()])
    marker = f'"$scratch"/{q(BETA_STAGE_COMMIT)}'
    record = q(receipt_bytes(attempt).decode().rstrip('\n'))
    script.extend([
        f'/bin/mkdir -m 700 {marker}',
        f'printf \'%s\\n\' {record} > {marker}/receipt.json',
        ': > "$scratch/publishing"',
        *(shlex.join(('prepare_parent', str(path))) for path in parents),
        f'/usr/bin/osascript -l JavaScript -e {q(PUBLISH_BETA)} "$scratch" {q(plan)}',
        "printf '%s\\n' 'Beta staged'",
    ])
    return '\n'.join(script)


def stage_beta(vm, layout, beta_cli_root, admitted, evidence):
    """Transfer only authenticated complete Beta products and closed SQLite members."""
    home, destinations = stage_paths(vm, layout, beta_cli_root)
    manifest = product_manifest(admitted)
    snapshot = evidence/BETA_SOURCE_SNAPSHOT
    closed = beta_source_snapshot(admitted, snapshot)
    with tempfile.TemporaryDirectory(prefix='meshchan-beta-stage-') as temporary:
        work = Path(temporary).resolve()
        for label, name in (('app', APP), ('cli', CLI)):
            shutil.copytree(Path(admitted[label]), work/name, symlinks=True)
            beta.beta_inventory(work/name, manifest[label]['inventory'])
        data = work/ARCHIVE_DATA
        data.mkdir(mode=0o700)
        for name in closed['files']:
            shutil.copyfile(snapshot/name, data/name)
            (data/name).chmod(0o600)
        beta.same(closed['files'], beta.sqlite_members(data), 'Staged Beta SQLite members')
        inventories = {name: product_inventory(work/name) for name in destinations}
        expected = {path: entry for name, inventory in inventories.items()
                    for path, entry in prefixed(name, inventory).items()}
        # The upload digest must be reproducible on a retry using new scratch.
        for path in expected:
            os.utime(work/path, (0, 0), follow_symlinks=False)
        payload = work/'beta-products.tar'
        transfer, _ = create_archive(payload, work/APP, expected)
        payload.chmod(0o400)
        transfer['mode'] = 0o400
        with tarfile.open(payload, mode='r:') as archive:
            archive_members(archive, expected, (APP, CLI))
        attempt, retry = stage_attempt(evidence, destinations, transfer)
        if retry and read_guest_commit(vm, destinations, attempt):
            for prefix, target in destinations.items():
                verify_guest_tree(vm, target, inventories[prefix], scratch=evidence)
            if not read_guest_commit(vm, destinations, attempt):
                raise ValueError('Guest Beta stage marker disappeared during verification')
        else:
            commands = guest_stage_script(home, destinations, manifest['cli']['inventory'], closed['files'], attempt)
            with payload.open('rb') as stream:
                try:
                    result = vm.remote(commands, stdin=stream, capture_output=True, timeout=180)
                except subprocess.CalledProcessError as error:
                    result = error
            if result.returncode != 0:
                detail = (result.stderr or b'').decode(errors='replace').strip()
                message = f'Guest Beta transfer exit {result.returncode}'
                raise ValueError(message + ('\n' + detail if detail else ''))
            if result.stdout != b'Beta staged\n':
                raise ValueError('Missing guest Beta installation receipt')
    return {
        'status': 'PASS', 'app': str(destinations[APP]), 'cli': str(destinations[CLI]/CLI_BINARY),
        'dataDirectory': str(destinations[ARCHIVE_DATA]),
        'sourceSnapshot': str(snapshot), 'sourceClosedSnapshot': closed, 'transferArchive': transfer,
        'stageNonce': attempt['nonce'], 'guestStageReceipt': str(staged_commit_path(destinations)/'receipt.json'),
    }


def project_beta_reference(admitted, snapshot):
    """Read the trusted Beta fixture through the admitted CLI on a disposable copy."""
    cli = Path(admitted['cli'])
    beta.beta_inventory(cli, product_manifest(admitted)['cli']['inventory'])
    members = beta.sqlite_members(snapshot)
    require_beta_data(members)
    with tempfile.TemporaryDirectory(prefix='meshchan-beta-reference-') as temporary:
        home = Path(temporary).resolve()
        data = home/'owned-data'
        data.mkdir(mode=0o700)
        for name in members:
            shutil.copyfile(snapshot/name, data/name)
            (data/name).chmod(0o600)
        beta.same(members, beta.sqlite_members(data), 'Reference Beta data copy')
        argv = [cli/CLI_BINARY, '--data-dir', data]

        def invoke(*args):
            return subprocess.run([*argv, *args], cwd=home, env=controlled_environment(),
                                  capture_output=True, text=True, timeout=30)

        projection = beta.capture_cli(invoke)
    beta.same(members, beta.sqlite_members(snapshot), 'Reference Beta archive after CLI reads')
    return projection


def compare_business(before_public, after_public, initial_db, reopened_db, *,
                     title, body, history_limit, beta_baseline=None):
    """Allow a single explicit Unicode draft and History limit change."""
    public, database = EMPTY_PUBLIC, EMPTY_DATABASE
    if beta_baseline is not None:
        public, database = beta_baseline['public'], beta_baseline['snapshot']['database']
    beta.same(public, before_public, 'Public projection before the installed writes')
    old_ids = {row['id'] for row in database['drafts']}
    new_drafts = [row for row in initial_db['drafts'] if row['id'] not in old_ids]
    if len(new_drafts) != 1:
        raise ValueError('Expected exactly one newly saved draft')
    draft = new_drafts[0]
    beta.same({'title': title, 'body': body}, {key: draft[key] for key in ('title', 'body')},
              'Installed draft content')
    for closed in (initial_db, reopened_db):
        beta.compare_sqlite(database, closed, new_draft=draft, history_limit=history_limit)
    beta.compare_cli(public, after_public, new_draft=draft, history_limit=history_limit)
    beta.verify_history_export(before_public, database)
    beta.verify_history_export(after_public, reopened_db)
    return {
        'status': 'PASS', 'newDraft': draft,
        'draftsBefore': len(database['drafts']), 'draftsAfter': len(initial_db['drafts']),
        'profilesPreserved': len(database['profiles']), 'historyPreserved': len(database['history']),
        'historyLimitBefore': public['settings']['diagnosticHistoryLimit'],
        'historyLimitAfter': history_limit,
    }
