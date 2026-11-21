"""Seal and independently restore an accepted local ad hoc engineering image."""

import argparse
from contextlib import ExitStack
import ctypes
from dataclasses import dataclass
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile

sys.dont_write_bytecode = True  # The retained verifier runs in a sealed tree.

from build_release import ROOT, now
import package_dmg_image
import release_ci_evidence
import release_retention_inputs
from release_materials import (
    ancestor_identities, controlled_environment, directory_identity, encoded, product_inventory,
    require_product_disjoint, safe, sha,
)
from release_package_archive import (
    check_payload, compare, directory_fd, new_extraction_root, prefixed,
)
from release_retention_archive import file_identity, regular_entry, restore_members, scanned_input, write_archive
from verify_retention_bootstrap import read_regular, require_checkout_boundaries

RECEIPT = 'retention-receipt.json'
MANIFEST = 'retention-manifest.json'
ARCHIVE = 'retained.tar'
VERIFIER = 'verifier'
WORKFLOW = '.github/workflows/ci.yml'
CI_CHECKOUT_INPUTS = ('pubspec.lock', 'tool/ci_evidence.py')
REPOSITORY = '007pig/meshchan'
CI_ROLES = {'product', 'dmg-tools', 'retention'}
CANDIDATE_FIELDS = {'dmg', 'dmg_acceptance', 'signed_manifest', 'local_acceptance',
                    'image_record', 'checksums', 'image_payload', 'upstream_tool_snapshot'}
METADATA = ('Preserve data bytes, permission modes, entry types and raw internal symlinks. '
            'Omit ownership, timestamps, ACLs, xattrs and file flags from restored files. '
            'Keep recorded PID and device/inode values in original evidence.')
PIN = re.compile(r'[0-9a-f]{64}')
COMMIT = re.compile(r'[0-9a-f]{40}')


def canonical(value, *, existing=True):
    path = absolute(value)
    if path.resolve(strict=existing) != path:
        raise ValueError(f'Use a canonical path without symlink aliases: {path}')
    return path


def absolute(value):
    literal = os.fspath(value)
    path = Path(literal)
    if not literal.startswith('/') or literal.startswith('//') or '..' in path.parts or str(path) != literal:
        raise ValueError(f'Expected a normalized absolute path: {literal!r}')
    return path


def require_pin(pin):
    if type(pin) is not str or not PIN.fullmatch(pin):
        raise ValueError('Expected a lowercase SHA-256 pin')
    return pin


def bound_json(path, expected):
    raw, _ = read_regular(None, path, expected_sha256=require_pin(expected))

    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f'Duplicate JSON key in {path}: {key}')
            result[key] = value
        return result

    result = json.loads(raw, object_pairs_hook=unique)
    if type(result) is not dict:
        raise ValueError(f'Expected JSON object: {path}')
    return result, raw


def new_file(path, data, mode=0o600):
    with path.open('xb') as stream:
        stream.write(data)
        stream.flush()
        os.fchmod(stream.fileno(), mode)
        os.fsync(stream.fileno())


def new_dir(path):
    with new_extraction_root(path):
        pass


@dataclass(frozen=True)
class Mapping:
    inputs: dict
    root: Path

    def __call__(self, original):
        path = absolute(original)
        for origin, member in self.inputs.items():
            base = absolute(origin)
            if path.is_relative_to(base):
                target = self.root/safe(member)/path.relative_to(base)
                if target.resolve(strict=True) != target:
                    raise ValueError(f'Aliased retained reference: {path}')
                return target
        raise ValueError(f'Reference is absent from retained members: {path}')


def live_locator(allowed, path):
    path = absolute(path)
    if not any(path.is_relative_to(root) for root in allowed):
        raise ValueError(f'Input outside explicitly selected roots: {path}')
    return canonical(path)


def distinct_roots(paths):
    result = set()
    identities = set()
    for path in sorted(set(paths), key=lambda path: (len(path.parts), str(path))):
        if result.intersection(path.parents):
            continue
        if identities.intersection(ancestor_identities(path)):
            raise ValueError(f'Input aliases another retained path: {path}')
        result.add(path)
        identities.add(directory_identity(path))
    return sorted(result)


def destinations(work, others, inputs=()):
    all_paths = {'Work directory': work, **others}
    protected = [*inputs, Path.home()/'Library', Path.home()/'.pub-cache', Path.home()/'.config',
                 Path.home()/'.cache', Path('/opt/homebrew'), Path('/Applications'), Path('/Library/Developer')]
    # The ignored Phase 1E.8 subtree is the one checkout-owned output location.
    if work.is_relative_to(ROOT/'build/phase-1e8') and work.parent == ROOT/'build/phase-1e8':
        work_protected = [*protected, ROOT/'.git']
    else:
        work_protected = [*protected, ROOT]
    require_checkout_boundaries(work, others)
    require_product_disjoint({'Work directory': work}, work_protected)
    require_product_disjoint(others, [*protected, ROOT, Path('/private/tmp'), Path('/tmp'),
                                     Path(tempfile.gettempdir())])
    for label, path in all_paths.items():
        require_product_disjoint({label: path}, [other for key, other in all_paths.items() if key != label])
        if os.path.lexists(path):
            raise ValueError(f'{label} already exists: {path}')
        parent = path.parent.stat()
        if not stat.S_ISDIR(parent.st_mode) or parent.st_uid != os.getuid():
            raise ValueError(f'{label} requires an existing parent directory owned by the caller')


def git(*args):
    return subprocess.check_output(['/usr/bin/git' if sys.platform == 'darwin' else 'git', *args],
                                   cwd=ROOT, env=controlled_environment())


def committed_blob(commit, name):
    if type(commit) is not str or not COMMIT.fullmatch(commit):
        raise ValueError('Expected a full Git source commit')
    name = safe(name)
    tree = git('ls-tree', commit, '--', name).decode().rstrip('\n')
    metadata, separator, path = tree.partition('\t')
    if not separator or path != name or not re.fullmatch(r'100(644|755) blob [0-9a-f]{40}', metadata):
        raise ValueError(f'Expected a committed regular file: {commit}:{name}')
    raw = git('show', f'{commit}:{name}')
    return raw, {'type': 'file', 'mode': int(metadata.split()[0][-3:], 8), 'size': len(raw),
                 'sha256': sha(raw)}


def git_file_entry(entry):
    # Git represents only the owner executable bit, even in a checkout
    # created with an umask that restricts group and other access.
    return {**entry, 'mode': 0o755 if entry['mode'] & 0o100 else 0o644}


def require_checkout_file(name, entry):
    actual, _ = regular_entry(ROOT/name)
    if git_file_entry(actual) != entry:
        raise ValueError(f'Retention checkout file differs from Git: {name}')


def snapshot_verifier(work, commit):
    root = work/VERIFIER
    if git('rev-parse', 'HEAD').decode().strip() != commit:
        raise ValueError('Retention source must match the selected checkout HEAD')
    names = {'LICENSE', 'COPYRIGHT', WORKFLOW, 'docs/releases/phase-1e8-ci-retention.md', *CI_CHECKOUT_INPUTS}
    names.update(name for name in git('ls-tree', '-r', '--name-only', '-z', commit, '--', 'tool').decode().split('\0')
                 if name.endswith('.py'))
    for name in sorted(names):
        raw, entry = committed_blob(commit, name)
        require_checkout_file(name, entry)
        target = root/name
        target.parent.mkdir(parents=True, exist_ok=True)
        new_file(target, raw, entry['mode'])
    return product_inventory(root)


def verify_supporting(selection, locate):
    paths = []
    for entry in selection.get('supporting', ()):
        path = absolute(entry['path'])
        actual, _ = scanned_input(locate(path))
        if set(actual) != {'.'} or actual['.'].get('sha256') != require_pin(entry['sha256']):
            raise ValueError(f'Supporting evidence differs from the selected pin: {path}')
        paths.append(path)
    return paths


def require_committed_inputs(commit, inputs, label):
    if not inputs:
        raise ValueError(f'Missing recorded inputs for {label}')
    for name, entry in inputs.items():
        if committed_blob(commit, name)[1] != git_file_entry(entry):
            raise ValueError(f'{label} does not match its claimed Git source: {name}')


def ci_inputs(selection, chain, locate, *, sealing=False, verifier=None):
    entries = selection['ci']
    if set(entries) not in (CI_ROLES, CI_ROLES | {'dmg-tools-pr'}):
        raise ValueError('Select product, DMG tool and retention CI snapshots')
    candidate = selection['candidate']
    dmg, _ = bound_json(locate(candidate['dmg_acceptance']['path']), candidate['dmg_acceptance']['sha256'])
    signed, _ = bound_json(locate(candidate['signed_manifest']['path']), candidate['signed_manifest']['sha256'])
    coverage = {'dmg': dmg['dmgTool']['inputs'], 'signing': signed['signingTool']['inputs']}
    if any(not tool for tool in coverage.values()):
        raise ValueError('The accepted signing and DMG tool inputs must be recorded')
    if (entries['product']['source'] != dmg['upstream']['sourceCommit']
            or entries['retention']['source'] != selection['retentionSource']):
        raise ValueError('CI checkout selection differs from the accepted product or retention source')
    if sealing:
        tool_commit = entries['dmg-tools']['source']
        for group, inputs in coverage.items():
            require_committed_inputs(tool_commit, inputs, f'Accepted {group} tools covered by CI')
        accepted = chain['identities']
        require_committed_inputs(accepted['upstreamVerifierSnapshotCommit'],
                                 accepted['upstreamVerifier']['inputs'], 'Reconstructed package verifier')
    snapshots = {}
    for role, entry in entries.items():
        event = 'pull_request' if role == 'dmg-tools-pr' else 'push'
        root = locate(entry['path'])
        expected = {'source': entry['source'], 'event': event, 'workflow_sha256': entry['workflowSha256'],
                    'require_artifacts': role == 'retention', 'repository': REPOSITORY,
                    'run_id': entry['runId'], 'attempt': entry['attempt']}
        if event == 'pull_request':
            expected['head_sha'] = entries['dmg-tools']['source']
        if sealing and committed_blob(entry['source'], WORKFLOW)[1]['sha256'] != entry['workflowSha256']:
            raise ValueError(f'Wrong committed workflow for {role}')
        if role == 'retention':
            if sealing:
                expected['checkout_inputs'] = {name: committed_blob(entry['source'], name)[1]['sha256']
                                               for name in CI_CHECKOUT_INPUTS}
            elif verifier is not None and all(name in verifier for name in CI_CHECKOUT_INPUTS):
                expected['checkout_inputs'] = {name: verifier[name]['sha256'] for name in CI_CHECKOUT_INPUTS}
        snapshots[role] = release_ci_evidence.verify_snapshot(root, entry['sha256'], **expected)
    ident = {role: {key: snapshots[role][key] for key in ('source', 'run_id', 'attempt', 'event', 'workflow_sha256')}
             for role in snapshots}
    return {'acceptance': chain['identities'], 'ci': ident, 'dmgToolCiCoverage': coverage}


def source_inventory(mappings):
    expected = {}
    stamps = {}
    for original, member in mappings.items():
        inventory, stamp = scanned_input(Path(original))
        expected.update(prefixed(member, inventory))
        stamps[original] = stamp
    expected['inputs'] = {'type': 'directory', 'mode': 0o700}
    return expected, stamps


def record_progress(work, name, result):
    # The work directory belongs to this invocation. Keep incomplete writes
    # at a staging name that readers never interpret as a result.
    staging = work/('.'+name+'.pending')
    new_file(staging, encoded({'recordedAt': now(), **result}))
    if os.path.lexists(work/name):
        raise FileExistsError(work/name)
    staging.rename(work/name)


def publish_seal(stage, target, parent_fd, stage_id):
    if not os.path.samestat(stage_id, os.stat(stage.name, dir_fd=parent_fd, follow_symlinks=False)):
        raise ValueError('Retention staging directory changed before publication')
    libc = ctypes.CDLL(None, use_errno=True)
    if sys.platform == 'darwin':
        rename, flags = libc.renameatx_np, 0x00000004  # RENAME_EXCL
    elif sys.platform == 'linux':
        rename, flags = libc.renameat2, 1  # RENAME_NOREPLACE
    else:
        raise ValueError('Exclusive seal publication requires macOS or Linux')
    rename.argtypes = (ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint)
    rename.restype = ctypes.c_int
    if rename(parent_fd, os.fsencode(stage.name), parent_fd, os.fsencode(target.name), flags) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), target)


def references(selection):
    candidate = selection['candidate']
    return [ROOT/'tool', *(absolute(entry['path']) for entry in candidate.values()),
            *(absolute(entry['path']) for entry in selection['ci'].values())]


def retain(args):
    selection_path = canonical(args.selection)
    selection, raw = bound_json(selection_path, args.selection_sha256)
    if type(selection.get('formatVersion')) is not int or selection['formatVersion'] != 1:
        raise ValueError('Unsupported retention selection')
    if set(selection['candidate']) != CANDIDATE_FIELDS:
        raise ValueError('Select all current release, checksum, acceptance and tool inputs')
    work = canonical(args.work, existing=False)
    target = canonical(args.destination, existing=False)
    allowed = [canonical(path) for path in selection['inputRoots']]
    destinations(work, {'Retention directory': target}, [*allowed, selection_path, *references(selection)])
    new_dir(work)
    record_progress(work, 'started.json', {'destination': str(target), 'selectionSha256': sha(raw)})
    stage = None
    try:
        locate = lambda path: live_locator(allowed, path)
        chain = release_retention_inputs.verify_chain(selection['candidate'], locate, live=True)
        ident = ci_inputs(selection, chain, locate, sealing=True)
        supporting = verify_supporting(selection, locate)
        roots = distinct_roots([selection_path, *supporting, *(locate(path) for path in chain['roots']),
                                *(locate(entry['path']) for entry in selection['ci'].values())])
        for path in roots:
            if path == Path.home() or path == ROOT:
                raise ValueError(f'Refusing to archive an entire home or checkout: {path}')
            require_product_disjoint({'Retention input': path},
                                     [Path.home()/'Library', Path.home()/'.config', Path.home()/'.ssh',
                                      Path.home()/'.pub-cache', Path('/opt/homebrew')],
                                     protected='user data, configuration or SDK')
        mappings = {str(path): f'inputs/{index:04d}-{path.name}' for index, path in enumerate(roots, 1)}
        expected, stamps = source_inventory(mappings)
        verifier = snapshot_verifier(work, selection['retentionSource'])
        manifest = {'formatVersion': 1, 'selectionPath': str(selection_path), 'selectionSha256': sha(raw),
                    'identities': ident, 'mapping': mappings, 'members': expected, 'verifier': verifier,
                    'metadata': METADATA, 'distribution': {'object': 'maintainer-internal',
                    'engineeringAsset': selection['candidate']['dmg']['path']}}
        target_parent = target.parent.lstat()
        stage = Path(tempfile.mkdtemp(prefix='.meshchan-retention-', dir=target.parent))
        stage_id = stage.lstat()
        record_progress(work, 'staging.json', {'stagingDirectory': str(stage)})
        shutil.copytree(work/VERIFIER, stage/VERIFIER, symlinks=True, copy_function=shutil.copyfile)
        # copyfile supplies independent bytes. Apply the recorded Git permission modes.
        for name, entry in verifier.items():
            (stage/VERIFIER/name).chmod(entry['mode'])
        check_payload(stage/VERIFIER, verifier)
        archive_identity = write_archive(stage/ARCHIVE, mappings, expected, stamps)
        manifest_raw = encoded(manifest)
        new_file(stage/MANIFEST, manifest_raw, 0o400)
        # Run the archive-only verifier before publishing the external index.
        with tempfile.TemporaryDirectory(prefix='verify-', dir=work) as parent:
            extract_and_verify(stage/ARCHIVE, Path(parent)/'payload', archive_identity, manifest)
        final, final_stamps = source_inventory(mappings)
        compare(expected, final, 'Original input bytes and modes after sealing')
        if final_stamps != stamps or bound_json(selection_path, args.selection_sha256)[1] != raw:
            raise ValueError('Original input identity changed while sealing')
        for name, entry in verifier.items():
            if entry['type'] == 'file':
                require_checkout_file(name, entry)
        check_payload(stage/VERIFIER, verifier)
        if (canonical(stage) != stage or not os.path.samestat(stage_id, stage.lstat())
                or regular_entry(stage/ARCHIVE)[0] != archive_identity
                or bound_json(stage/MANIFEST, sha(manifest_raw))[1] != manifest_raw):
            raise ValueError('Retention object changed before publication')
        receipt = {'formatVersion': 1, 'status': 'SEALED', 'sealedAt': now(),
                   'manifestSha256': sha(manifest_raw), 'archive': archive_identity}
        receipt_raw = encoded(receipt)
        log = {'receiptSha256': sha(receipt_raw), 'archive': archive_identity, 'destination': str(target)}
        new_file(stage/RECEIPT, receipt_raw, 0o400)
        stage.chmod(0o500)
        record_progress(work, 'prepared.json', log)
        with directory_fd(target.parent) as parent_fd:
            if not os.path.samestat(target_parent, os.fstat(parent_fd)):
                raise ValueError('Retention parent changed before publication')
            publish_seal(stage, target, parent_fd, stage_id)
    except BaseException as error:
        record_progress(work, 'failed.json', {'error': str(error), 'type': type(error).__name__,
                                              'stagingDirectory': str(stage) if stage else None})
        raise
    print(encoded(log).decode(), end='')


def extract_and_verify(archive, target, archive_identity, manifest):
    mapping = manifest['mapping']
    for origin, member in mapping.items():
        absolute(origin)
        parts = PurePosixPath(safe(member)).parts
        if len(parts) != 2 or parts[0] != 'inputs':
            raise ValueError(f'Invalid retained mapping: {member}')
    if len(set(mapping.values())) != len(mapping):
        raise ValueError('Duplicate retained mapping target')
    roots = sorted(map(absolute, mapping))
    if any(path.is_relative_to(other) for index, path in enumerate(roots) for other in roots[:index]):
        raise ValueError('Overlapping original roots in retained mapping')
    members = manifest['members']
    if ({str(PurePosixPath(*PurePosixPath(name).parts[:2])) for name in members if name != 'inputs'}
            != set(mapping.values())):
        raise ValueError('Retained inventory and mapping cover different roots')
    archive_id, restore_id = restore_members(archive, target, archive_identity, members, mapping.values())
    locate = Mapping(mapping, target)
    selection, _ = bound_json(locate(manifest['selectionPath']), manifest['selectionSha256'])
    verify_supporting(selection, locate)
    chain = release_retention_inputs.verify_chain(selection['candidate'], locate)
    if ci_inputs(selection, chain, locate, verifier=manifest['verifier']) != manifest['identities']:
        raise ValueError('Retained semantic identities differ')
    return locate(selection['candidate']['dmg']['path']), archive_id, restore_id


class ImageProbe:
    def __init__(self, logs):
        self.logs = logs

    def write_logs(self, name, stdout, stderr):
        new_file(self.logs/(name+'.stdout'), stdout or b'')
        new_file(self.logs/(name+'.stderr'), stderr or b'')

    def command(self, name, argv):
        try:
            result = subprocess.run(argv, cwd=self.logs, capture_output=True, timeout=300)
        except subprocess.TimeoutExpired as error:
            self.write_logs(name, error.stdout, error.stderr)
            raise
        self.write_logs(name, result.stdout, result.stderr)
        result.check_returncode()
        return result.stdout.decode()


def verify(args):
    target = canonical(args.retention)
    work = canonical(args.work, existing=False)
    restore = args.command == 'restore'
    dest = canonical(args.destination, existing=False) if restore else None
    destinations(work, {'Restore directory': dest} if restore else {}, [target])
    if {p.name for p in target.iterdir()} != {RECEIPT, MANIFEST, ARCHIVE, VERIFIER}:
        raise ValueError('Retention object is incomplete or contains unexpected files')
    receipt, _ = bound_json(canonical(target/RECEIPT), args.receipt_sha256)
    if receipt.get('status') != 'SEALED' or type(receipt.get('formatVersion')) is not int or receipt['formatVersion'] != 1:
        raise ValueError('Expected a sealed retention receipt')
    manifest, original_manifest = bound_json(canonical(target/MANIFEST), receipt['manifestSha256'])
    if type(manifest.get('formatVersion')) is not int or manifest['formatVersion'] != 1 or manifest['metadata'] != METADATA:
        raise ValueError('Unsupported retention manifest')
    verifier = canonical(target/VERIFIER)
    check_payload(verifier, manifest['verifier'])
    archive = canonical(target/ARCHIVE)
    new_dir(work)
    try:
        with ExitStack() as temporary:
            if dest is None:
                # Check uses the same safe extraction and semantic revalidation.
                parent = temporary.enter_context(tempfile.TemporaryDirectory(prefix='check-', dir=work))
                dest = Path(parent)/'payload'
            dmg, archive_id, restore_id = extract_and_verify(archive, dest, receipt['archive'], manifest)
            structure = {'status': 'NOT_RUN', 'reason': 'The check operation verifies archive integrity'}
            if restore:
                structure['reason'] = 'macOS image verification requires hdiutil and codesign'
            if sys.platform == 'darwin' and restore:
                structure = {'status': 'PASS', **package_dmg_image.verify_image(
                    ImageProbe(work), dmg, package_dmg_image.file_stamp(dmg))}
            check_payload(dest, {'.': {'type': 'directory', 'mode': 0o700}, **manifest['members']})
            if not os.path.samestat(restore_id, dest.lstat()):
                raise ValueError('Verified destination differs from the restored directory')
            if file_identity(archive.lstat()) != archive_id:
                raise ValueError('Retained archive changed after extraction')
            if (bound_json(target/RECEIPT, args.receipt_sha256)[0] != receipt
                    or bound_json(target/MANIFEST, receipt['manifestSha256'])[1] != original_manifest):
                raise ValueError('External retention records changed during verification')
            check_payload(verifier, manifest['verifier'])
            report = {'status': 'PASS', 'operation': args.command, 'receiptSha256': args.receipt_sha256,
                      'archive': receipt['archive'], 'restoredDmg': str(dmg) if restore else None,
                      'imageStructure': structure, 'pythonPath': sys.executable, 'pythonVersion': sys.version,
                      'historicalAcceptance': 'MATCHED', 'newProductRuntime': 'NOT_RUN'}
        record_progress(work, 'verification.json', report)
    except BaseException as error:
        record_progress(work, 'failed.json', {'error': str(error), 'type': type(error).__name__})
        raise
    print(encoded(report).decode(), end='')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    seal = commands.add_parser('retain', help='Seal accepted bytes and independently verify the archive')
    seal.add_argument('--selection', required=True, type=Path)
    seal.add_argument('--selection-sha256', required=True)
    for command in ('check', 'restore'):
        verify_parser = commands.add_parser(command)
        verify_parser.add_argument('--retention', required=True, type=Path)
        verify_parser.add_argument('--receipt-sha256', required=True)
    for command, subparser in commands.choices.items():
        subparser.add_argument('--work', required=True, type=Path)
        if command in ('retain', 'restore'):
            subparser.add_argument('--destination', required=True, type=Path)
    args = parser.parse_args()
    try:
        (retain if args.command == 'retain' else verify)(args)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError, tarfile.TarError) as error:
        parser.exit(1, f'Retention {args.command} failed: {error}\n')


if __name__ == '__main__':
    main()
