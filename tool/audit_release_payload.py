"""Check an extracted public engineering image for local build data."""

import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tarfile
from urllib.parse import quote_from_bytes

from release_materials import contains_macho_local_path, product_inventory, sha
from release_package_archive import compare, open_archive, validate_link
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
TEST_LOG_MARKER = re.compile(rb'-----BEGIN (?:[A-Z0-9]+ )?PRIVATE KEY-----')
PATH_END = re.compile(rb'''(?:[/\x00\s"'<>\[\]{}`?#]|\\/)''')
MACOS_USER_TEMP_PATH = re.compile(rb'/var/folders/[a-z0-9_]{2}/[a-z0-9_]{8,}/[TC0]/', re.I)


def private_name(relative):
    return (bool(PRIVATE_DIRECTORIES.intersection(part.lower() for part in relative.parts))
            or relative.name.lower().endswith(PRIVATE_SUFFIXES))


def contains_private_path(data, needles):
    for needle in needles:
        start = 0
        while (index := data.find(needle, start)) >= 0:
            if PATH_END.match(data, index + len(needle)):
                return True
            start = index + 1
    return False


def scan_stream(stream, needles):
    """Find signatures across read boundaries without retaining matched path values."""
    overlap = max(4096, max(map(len, needles), default=0) + 2)
    digest = hashlib.sha256()
    chunk = stream.read(1024 * 1024)
    macho = chunk[:4] in MACH_O_MAGIC
    tail = b''
    findings = set()
    while chunk:
        digest.update(chunk)
        data = tail + chunk
        if (contains_private_path(data, needles)
                or (not macho and MACOS_USER_TEMP_PATH.search(data.replace(b'\\/', b'/')))):
            findings.add('localBuildPath')
        if macho and contains_macho_local_path(data):
            findings.add('nativeImageLocalPath')
        if TEST_LOG_MARKER.search(data):
            findings.add('privateKeyMarker')
        tail = data[-overlap:]
        chunk = stream.read(1024 * 1024)
    if any(tail.endswith(needle) for needle in needles):
        findings.add('localBuildPath')
    return findings, macho, digest.hexdigest()


def source_archive_findings(stream, needles):
    findings = {}
    names = set()
    entries = {'.': {'type': 'directory'}}
    with (gzip.GzipFile(fileobj=stream, mode='rb') as source,
          tarfile.open(fileobj=source, mode='r:') as archive):
        for member in archive:
            relative = PurePosixPath(member.name)
            if (not relative.parts or relative.is_absolute() or '..' in relative.parts
                    or relative.as_posix() != member.name or relative in names
                    or not (member.isfile() or member.isdir() or member.issym())):
                raise ValueError('Unsafe or duplicate first-party source archive member')
            pax_fields = {'path', 'linkpath'} if member.issym() else {'path'}
            if (member.uname or member.gname or member.sparse is not None or archive.pax_headers
                    or set(member.pax_headers) - pax_fields or (member.linkname and not member.issym())
                    or (member.size and not member.isfile())):
                raise ValueError('Unexpected first-party source archive metadata')
            names.add(relative)
            for parent in relative.parents:
                if entries.setdefault(parent.as_posix(), {'type': 'directory'})['type'] != 'directory':
                    raise ValueError('Non-directory first-party source archive parent')
            name = relative.as_posix()
            if name in entries and not member.isdir():
                raise ValueError('Non-directory first-party source archive parent')
            reasons = set()
            if member.isfile():
                entries[name] = {'type': 'file'}
                with archive.extractfile(member) as contents:
                    reasons, _, _ = scan_stream(contents, needles)
            elif member.issym():
                entries[name] = {'type': 'symlink', 'symlink': member.linkname}
            else:
                entries[name] = {'type': 'directory'}
            if private_name(relative):
                reasons.add('privateEvidenceFilename')
            if reasons:
                findings[name] = sorted(reasons)
        source.seek(archive.offset)
        end = bytes(2 * tarfile.BLOCKSIZE)
        if source.read(len(end)) != end:
            raise ValueError('Missing first-party source archive end marker')
        while padding := source.read(1024 * 1024):
            if padding.strip(b'\0'):
                raise ValueError('Unexpected data after the first-party source archive')
    if not names:
        raise ValueError('Empty first-party source archive')
    for name, entry in entries.items():
        if entry['type'] == 'symlink':
            validate_link(name, entries, {'.'})
    return findings, len(names)


def audit(root, local_prefixes, *, image_inventory_sha256):
    if root.is_symlink() or not root.is_dir() or root.resolve() != root:
        raise ValueError('Use the canonical directory of the extracted payload or read-only mount')
    inventory_path = root / MANIFEST
    if not inventory_path.is_file() or inventory_path.is_symlink():
        raise ValueError('Expected a regular image-payload.json')
    with open_archive(inventory_path) as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError('Expected a regular image-payload.json')
        manifest_bytes = stream.read()
    if sha(manifest_bytes) != image_inventory_sha256:
        raise ValueError('Image inventory does not match the independent digest')
    manifest = json.loads(manifest_bytes, object_pairs_hook=policy_object)
    if type(manifest) is not dict or manifest.get('payloadProfile') != PROFILE:
        raise ValueError('Expected a public engineering payload')
    inventory = product_inventory(root)
    claimed = manifest['inventory']
    if type(claimed) is not dict:
        raise ValueError('Expected a JSON object for the public image inventory')
    if MANIFEST in claimed:
        raise ValueError('The image inventory includes itself')
    manifest_entry = {**inventory[MANIFEST], 'sha256': image_inventory_sha256}
    compare({**claimed, MANIFEST: manifest_entry}, inventory, 'Public image inventory')
    product_roots = sorted(name for name in inventory if '/' not in name and
                           name.startswith('Meshchan-') and inventory[name]['type'] == 'directory')
    if len(product_roots) != 1:
        raise ValueError('Expected one top-level Meshchan product folder')
    product = product_roots[0]
    if manifest.get('candidatePath') != product:
        raise ValueError('Image inventory candidate path does not match the product folder')
    source = f'{product}/{FIRST_PARTY}'
    if inventory.get(source, {}).get('type') != 'file':
        raise ValueError('Missing regular first-party archive')
    link_roots = {f'{product}/Meshchan.app', f'{product}/meshctl'}
    absolute = {os.fsencode(prefix.rstrip('/')) for prefix in local_prefixes}
    if not absolute or any(not prefix.startswith(b'/') for prefix in absolute):
        raise ValueError('Supply at least one absolute non-root local prefix')
    urls = {quote_from_bytes(prefix, safe='/').encode('ascii') for prefix in absolute}
    url_lower = {re.sub(rb'%[0-9A-F]{2}', lambda escape: escape[0].lower(), url) for url in urls}
    prefixes = absolute | urls | url_lower
    needles = tuple(sorted(prefixes | {prefix.replace(b'/', b'\\/') for prefix in prefixes}))
    candidates, findings = [], {}
    for name, entry in sorted(inventory.items()):
        relative = PurePosixPath(name)
        reasons = {'privateEvidenceFilename'} if private_name(relative) else set()
        if entry['type'] == 'symlink':
            validate_link(name, inventory, link_roots)
        if entry['type'] == 'file':
            with open_archive(root / name) as stream:
                metadata = os.fstat(stream.fileno())
                if not stat.S_ISREG(metadata.st_mode):
                    raise ValueError(f'Expected a regular public image file: {name}')
                if metadata.st_nlink != 1:
                    raise ValueError(f'Public image contains a shared hard link: {name}')
                if name == source:
                    source_stream = io.BytesIO(stream.read(entry['size'] + 1))
                    scanned, macho, observed = scan_stream(source_stream, needles)
                else:
                    scanned, macho, observed = scan_stream(stream, needles)
            if observed != entry['sha256']:
                raise ValueError(f'Public image file changed during audit: {name}')
            reasons.update(scanned)
            if macho:
                candidates.append(name)
        if reasons:
            findings[name] = sorted(reasons)
    source_stream.seek(0)
    archived_findings, source_members = source_archive_findings(source_stream, needles)
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
    except (EOFError, OSError, ValueError, KeyError, tarfile.TarError) as error:
        parser.exit(1, f'Public payload audit failed: {error}\n')
    print(json.dumps(result, indent=2, sort_keys=True))
    return int(result['status'] != 'PASS')


if __name__ == '__main__':
    raise SystemExit(main())
