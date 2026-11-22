"""Check an extracted public engineering image for local build data."""

import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import tarfile

from release_materials import digest, product_inventory
from release_package_archive import compare, validate_link
from release_signing import policy_object


PROFILE = 'public-engineering-v1'
MANIFEST = 'image-payload.json'
FIRST_PARTY = 'materials/source-materials/meshchan/meshchan-source.tar.gz'
PRIVATE_DIRECTORIES = {'evidence', 'provenance', 'upstream-provenance', '.git', '.ssh',
                       '__pycache__'}
PRIVATE_SUFFIXES = ('.log', '.stderr', '.stdout', '.sqlite', '.sqlite3', '.db', '.wal',
                    '.shm', '.sqlite-wal', '.sqlite-shm')
MACH_O_MAGIC = {
    bytes.fromhex(magic) for magic in ('feedface', 'cefaedfe', 'feedfacf', 'cffaedfe',
                                       'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')
}
MACH_O_BUILD_PATH = re.compile(
    rb'(?:/Users/[^/\s]+/|/private/var/folders/|/private/tmp/|file:///tmp/|/home/[^/\s]+/)'
)
TEST_LOG_MARKER = re.compile(rb'-----BEGIN (?:[A-Z0-9]+ )?PRIVATE KEY-----')


def json_record(path):
    result = json.loads(path.read_bytes(), object_pairs_hook=policy_object)
    if type(result) is not dict:
        raise ValueError(f'Expected a JSON object in {path.name}')
    return result


def private_name(relative):
    return (bool(PRIVATE_DIRECTORIES.intersection(part.lower() for part in relative.parts))
            or relative.name.lower().endswith(PRIVATE_SUFFIXES))


def scan_stream(stream, needles, *, macho=False):
    """Find signatures across read boundaries without retaining matched path values."""
    overlap = max(4096, max(map(len, needles), default=0))
    tail = b''
    findings = set()
    while chunk := stream.read(1024 * 1024):
        data = tail + chunk
        if any(needle in data for needle in needles):
            findings.add('localBuildPath')
        if macho and MACH_O_BUILD_PATH.search(data):
            findings.add('nativeImageLocalPath')
        if TEST_LOG_MARKER.search(data):
            findings.add('privateKeyMarker')
        tail = data[-overlap:]
    return findings


def source_archive_findings(path, needles):
    findings = {}
    names = set()
    with tarfile.open(path, 'r|gz') as archive:
        for member in archive:
            relative = PurePosixPath(member.name)
            if (not relative.parts or relative.is_absolute() or '..' in relative.parts
                    or relative.as_posix() != member.name or relative in names
                    or not (member.isfile() or member.isdir())):
                raise ValueError('Unsafe or duplicate first-party source archive member')
            names.add(relative)
            reasons = set()
            if member.isfile():
                with archive.extractfile(member) as stream:
                    reasons = scan_stream(stream, needles)
            if private_name(relative):
                reasons.add('privateEvidenceFilename')
            if reasons:
                findings[relative.as_posix()] = sorted(reasons)
    if not names:
        raise ValueError('Empty first-party source archive')
    return findings, len(names)


def audit(root, local_prefixes, *, image_inventory_sha256):
    if root.is_symlink() or not root.is_dir() or root.resolve() != root:
        raise ValueError('Use the canonical directory of the extracted payload or read-only mount')
    inventory_path = root / MANIFEST
    if not inventory_path.is_file() or inventory_path.is_symlink():
        raise ValueError('Expected a regular image-payload.json')
    if digest(inventory_path) != image_inventory_sha256:
        raise ValueError('Image inventory does not match the independent digest')
    manifest = json_record(inventory_path)
    if manifest.get('payloadProfile') != PROFILE:
        raise ValueError('Expected a public engineering payload')
    inventory = product_inventory(root)
    claimed = manifest['inventory']
    if MANIFEST in claimed:
        raise ValueError('The image inventory includes itself')
    compare({**claimed, MANIFEST: inventory[MANIFEST]}, inventory, 'Public image inventory')
    product_roots = sorted(name for name in inventory if '/' not in name and
                           name.startswith('Meshchan-') and inventory[name]['type'] == 'directory')
    if len(product_roots) != 1:
        raise ValueError('Expected one top-level Meshchan product folder')
    product = product_roots[0]
    source = f'{product}/{FIRST_PARTY}'
    if inventory.get(source, {}).get('type') != 'file':
        raise ValueError('Missing regular first-party archive')
    link_roots = {f'{product}/Meshchan.app', f'{product}/meshctl'}
    needles = tuple(os.fsencode(prefix.rstrip('/') + '/') for prefix in sorted(set(local_prefixes)))
    if not needles or any(not needle.startswith(b'/') or needle == b'/' for needle in needles):
        raise ValueError('Supply at least one absolute non-root local prefix')
    candidates, findings = [], {}
    for name, entry in sorted(inventory.items()):
        relative = PurePosixPath(name)
        reasons = {'privateEvidenceFilename'} if private_name(relative) else set()
        if entry['type'] == 'symlink':
            validate_link(name, inventory, link_roots)
        if entry['type'] == 'file':
            file = root / name
            if file.lstat().st_nlink != 1:
                raise ValueError(f'Public image contains a shared hard link: {name}')
            with file.open('rb') as stream:
                macho = stream.read(4) in MACH_O_MAGIC
                stream.seek(0)
                reasons.update(scan_stream(stream, needles, macho=macho))
            if macho:
                candidates.append(name)
        if reasons:
            findings[name] = sorted(reasons)
    archived_findings, source_members = source_archive_findings(root / source, needles)
    findings.update({f'{source}:{name}': reasons for name, reasons in archived_findings.items()})
    required_machos = {f'{product}/Meshchan.app/Contents/MacOS/Meshchan',
                       f'{product}/meshctl/bin/meshctl'}
    if not required_machos <= set(candidates):
        raise ValueError('Missing native App or CLI executable')
    return {'status': 'FAIL' if findings else 'PASS', 'payloadProfile': PROFILE,
            'imageInventorySha256': image_inventory_sha256, 'inventoryEntries': len(inventory),
            'firstPartyArchiveEntries': source_members, 'machOFiles': candidates,
            'findings': findings}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('payload', type=Path, help='Extracted payload or verified read-only mount')
    parser.add_argument('--image-inventory-sha256', required=True, help='Independently pinned image inventory digest')
    parser.add_argument('--local-prefix', action='append', default=[],
                        help='Additional private absolute build root to look for in file bytes')
    args = parser.parse_args()
    try:
        result = audit(args.payload, [str(Path.home()), *args.local_prefix],
                       image_inventory_sha256=args.image_inventory_sha256)
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        parser.exit(1, f'Public payload audit failed: {error}\n')
    print(json.dumps(result, indent=2, sort_keys=True))
    return int(result['status'] != 'PASS')


if __name__ == '__main__':
    raise SystemExit(main())
