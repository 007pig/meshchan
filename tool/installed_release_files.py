"""Inspect a Safari download, its Finder mount, and the actual installed files."""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import plistlib
import re
import shlex
import subprocess
import tarfile
import tempfile
from urllib.parse import urlsplit

import installed_release_inputs as inputs
import package_dmg_image as disk
from package_release import bytes_entry, file_stamp, verify_report_fields
from release_materials import controlled_environment, encoded, require_material_file, safe, sha
from release_package_archive import archive_members, prefixed
import release_signing as signing

APP = 'Meshchan.app'
VOLUME_MANIFEST = 'image-payload.json'
QUARANTINE = 'com.apple.quarantine'
WHERE_FROM = 'com.apple.metadata:kMDItemWhereFroms'
DOWNLOADED_DATE = 'com.apple.metadata:kMDItemDownloadedDate'
# Keep this policy local to installed files. The packaging and retention
# verifiers continue to use their original, stricter metadata contracts.
SYSTEM_ATTRIBUTES = {
    QUARANTINE: 'User download or Gatekeeper approval state',
    WHERE_FROM: 'Browser-recorded download source',
    DOWNLOADED_DATE: 'Browser-recorded download date',
    'com.apple.provenance': 'macOS execution or filesystem provenance',
    'com.apple.macl': 'macOS user-intent access metadata',
    'com.apple.lastuseddate#PS': 'LaunchServices last-used timestamp',
}
GUID = re.compile(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}')
HEX_SHA = re.compile(r'[0-9a-f]{64}')
APPLE_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc)
FIRST_DOWNLOAD_CLOCK_TOLERANCE = timedelta(seconds=2)


def remote_text(vm, argv, *, timeout=30):
    return vm.remote(shlex.join(map(str, argv)), capture_output=True, text=True, timeout=timeout).stdout


def guest_path(value):
    raw = str(value)
    path = Path(raw)
    if not path.is_absolute() or path.as_posix() != raw or '..' in path.parts or any(
            ord(character) < 32 for character in raw):
        raise ValueError('Expected an exact absolute guest path')
    return path


def guest_file_stamp(vm, path):
    """Read the identity of a real, single-link file from the guest itself."""
    path = guest_path(path)
    target, parent = map(shlex.quote, (str(path), str(path.parent)))
    physical = f'test "$(cd {parent} && /bin/pwd -P)" = {parent}'
    script = f'{physical} && test ! -L {target} && test -f {target}'
    layout = '%d %i %p %u %g %l %z %B %Fm'
    output = vm.remote(f'{script} && LC_ALL=C /usr/bin/stat -f {shlex.quote(layout)} {target}',
                       capture_output=True, text=True, timeout=15).stdout
    if not re.fullmatch(r'[0-9]+(?: [0-9]+){7} [0-9]+\.[0-9]{9}\n?', output):
        raise ValueError('Malformed guest file identity')
    device, inode, raw_mode, owner, group, links, size, birth, modified = output.split()
    if int(links) != 1 or int(inode) < 1 or not re.fullmatch(r'10[0-7]{4}', raw_mode):
        raise ValueError('Guest file must be a single-link regular file')
    seconds, nanoseconds = map(int, modified.split('.'))
    return {'path': str(path), 'device': int(device), 'inode': int(inode),
            'mode': int(raw_mode, 8) & 0o7777, 'uid': int(owner), 'gid': int(group),
            'size': int(size), 'birthTime': int(birth), 'modifiedTime': seconds,
            'modifiedTimeNs': seconds * 1_000_000_000 + nanoseconds}


def read_xattr(vm, path, name):
    output = remote_text(vm, ['/usr/bin/xattr', '-p', '-s', '-x', name, path])
    if not re.fullmatch(r'[0-9A-Fa-f\s]*', output):
        raise ValueError('Malformed extended attribute hex data')
    return bytes.fromhex(output)


def observe_metadata(vm, path, *, known_paths=None, quarantine_paths=()):
    """Observe metadata without stripping or rewriting any xattrs or ACLs."""
    path = guest_path(path)
    options = '-sv' if known_paths is None else '-rsv'
    words = remote_text(vm, ['/usr/bin/xattr', options, path], timeout=60)
    allowed_paths = {str(path)} if known_paths is None else {
        str(path/name) for name in known_paths}
    attributes = {}
    for line in words.splitlines():
        name, separator, attribute = line.rpartition(': ')
        if not separator or name not in allowed_paths or attribute not in SYSTEM_ATTRIBUTES:
            raise ValueError('Unexpected installed extended attribute: '+line)
        relative = Path(name).relative_to(path).as_posix()
        values = attributes.setdefault(relative, {})
        if attribute in values:
            raise ValueError('Repeated extended attribute in guest output: '+line)
        values[attribute] = SYSTEM_ATTRIBUTES[attribute]
    for name in attributes.get('.', {}):
        attributes['.'][name] = {'scope': SYSTEM_ATTRIBUTES[name],
                                  'hex': read_xattr(vm, path, name).hex()}
    # Keep raw approval metadata for the exact installed CLI executables and
    # libraries without reading every nested system attribute in the tree.
    for relative in quarantine_paths:
        observed = attributes.get(relative, {})
        if QUARANTINE in observed:
            observed[QUARANTINE] = {'scope': SYSTEM_ATTRIBUTES[QUARANTINE],
                                    'hex': read_xattr(vm, path/relative, QUARANTINE).hex()}
    acl_options = '-ldeO' if known_paths is None else '-laeOR'
    acl_flags = remote_text(vm, ['/bin/ls', acl_options, path], timeout=60)
    # A nonempty extended ACL can change which user can execute or modify an
    # installed object. Record the listing and require explicit review if one
    # is present before treating the installation as accepted.
    if re.search(r'^\s+\d+:\s', acl_flags, re.MULTILINE):
        raise ValueError('Unexpected extended ACL on '+str(path)+'\n'+acl_flags)
    return {'extendedAttributes': attributes, 'ownershipAclAndFlags': acl_flags}


def require_url(value):
    parsed = urlsplit(value)
    if parsed.scheme not in {'http', 'https'} or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError('Expected the browser download URL')
    return value


def parse_time(value):
    parsed = datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        raise ValueError('Download evidence timestamps require a timezone')
    return parsed


def safari_quarantine(value):
    raw = value.decode('ascii')
    fields = raw.split(';')
    if (len(fields) != 4 or re.fullmatch(r'[0-9a-fA-F]{4}', fields[0]) is None
            or re.fullmatch(r'[0-9a-fA-F]{1,16}', fields[1]) is None or fields[2] != 'Safari'
            or GUID.fullmatch(fields[3]) is None):
        raise ValueError('Download does not carry a Safari quarantine event')
    return raw, int(fields[1], 16), fields[3]


def check_download_evidence(quarantine, where_from, events, *, url, started_at, finished_at):
    raw, epoch_seconds, guid = safari_quarantine(quarantine)
    try:
        origins = plistlib.loads(where_from)
    except (ValueError, plistlib.InvalidFileException) as error:
        raise ValueError('Malformed browser download origins') from error
    if type(origins) is not list or any(type(item) is not str for item in origins) or url not in origins:
        raise ValueError('Download origin metadata does not contain the observed browser URL')
    start, end = map(parse_time, (started_at, finished_at))
    if end < start:
        raise ValueError('Invalid download case time interval')
    start -= FIRST_DOWNLOAD_CLOCK_TOLERANCE
    end += FIRST_DOWNLOAD_CLOCK_TOLERANCE
    if not start.timestamp() <= epoch_seconds <= end.timestamp():
        raise ValueError('Quarantine timestamp is outside the observed download')
    if type(events) is not list or len(events) != 1 or type(events[0]) is not dict:
        raise ValueError('Missing or repeated OS quarantine event')
    event = events[0]
    verify_report_fields(event, {'id': guid, 'agent': 'com.apple.Safari'}, 'Safari OS quarantine event')
    # Safari can leave the quarantine database URL unset. The independent
    # browser source xattr above still has to match the observed download.
    if 'url' not in event or event['url'] not in (None, url):
        raise ValueError('Safari OS quarantine event URL conflicts with browser source metadata')
    seconds = event.get('appleTime')
    if type(seconds) not in {int, float} or not (start-APPLE_EPOCH).total_seconds() <= seconds <= (
            end-APPLE_EPOCH).total_seconds():
        raise ValueError('OS quarantine event is outside the observed download')
    return {'quarantine': raw, 'whereFrom': origins, 'event': event}


def require_download_birth(stamp, started_at, finished_at):
    epoch = stamp.get('birthTime') if type(stamp) is dict else None
    if type(epoch) is not int or not (
            (parse_time(started_at)-FIRST_DOWNLOAD_CLOCK_TOLERANCE).timestamp() <= epoch <=
            (parse_time(finished_at)+FIRST_DOWNLOAD_CLOCK_TOLERANCE).timestamp()):
        raise ValueError('Downloaded file birth time is outside the observed download')


def downloaded_date(data, started_at, finished_at):
    timestamps = plistlib.loads(data, aware_datetime=True)
    if (type(timestamps) is not list or len(timestamps) != 1 or type(timestamps[0]) is not datetime
            or not parse_time(started_at)-FIRST_DOWNLOAD_CLOCK_TOLERANCE <= timestamps[0]
            <= parse_time(finished_at)+FIRST_DOWNLOAD_CLOCK_TOLERANCE):
        raise ValueError('Safari download date is outside the observed download')
    return timestamps[0].isoformat()


def verify_safari_download_receipt(report):
    """Recheck the native Safari metadata and the summaries it produced."""
    if (type(report) is not dict or report.get('browser') != 'Safari'
            or any(type(report.get(key)) is not str for key in ('sha256', 'url', 'startedAt', 'finishedAt'))
            or HEX_SHA.fullmatch(report['sha256']) is None):
        raise ValueError('Expected a verified Safari download receipt')
    url = require_url(report['url'])
    start, finish = report['startedAt'], report['finishedAt']
    require_download_birth(report.get('file'), start, finish)
    metadata = report.get('metadata')
    if type(metadata) is not dict:
        raise ValueError('Missing native Safari download metadata')
    raw_attributes, ownership = (metadata.get(key) for key in ('extendedAttributes', 'ownershipAclAndFlags'))
    if (type(raw_attributes) is not dict or raw_attributes.keys() != {'.'}
            or type(raw_attributes['.']) is not dict or type(ownership) is not str
            or not ownership.strip() or re.search(r'^\s+\d+:\s', ownership, re.MULTILINE)):
        raise ValueError('Invalid native Safari download metadata')
    attributes = {}
    for attribute, observed in raw_attributes['.'].items():
        if (attribute not in SYSTEM_ATTRIBUTES or type(observed) is not dict
                or observed.get('scope') != SYSTEM_ATTRIBUTES[attribute] or type(observed.get('hex')) is not str
                or re.fullmatch(r'(?:[0-9a-f]{2})*', observed['hex']) is None):
            raise ValueError('Invalid raw Safari download attribute')
        attributes[attribute] = bytes.fromhex(observed['hex'])
    if not {QUARANTINE, WHERE_FROM} <= attributes.keys():
        raise ValueError('Downloaded DMG lacks quarantine or browser source attributes')
    native = check_download_evidence(attributes[QUARANTINE], attributes[WHERE_FROM], [report.get('event')],
                                     url=url, started_at=start, finished_at=finish)
    if DOWNLOADED_DATE in attributes:
        recorded_date = downloaded_date(attributes[DOWNLOADED_DATE], start, finish)
        if 'downloadedDate' in report:
            native['downloadedDate'] = recorded_date
    elif 'downloadedDate' in report:
        raise ValueError('Safari download date lacks its native attribute')
    verify_report_fields(report, native, 'Safari download summary')


def verify_safari_download(vm, path, *, expected_asset, url, started_at, finished_at, user_home):
    """Corroborate the case's independently observed Safari interaction with macOS records."""
    home = guest_path(user_home)
    path = guest_path(path)
    url = require_url(url)
    name = expected_asset['filename']
    if Path(name).name != name or path != home/'Downloads'/name or path.suffix != '.dmg':
        raise ValueError('Download path differs from the pinned asset and guest Downloads directory')
    stamp = guest_file_stamp(vm, path)
    uid = int(remote_text(vm, ['/usr/bin/id', '-u']).strip())
    verify_report_fields(stamp, {'size': expected_asset['size'], 'uid': uid}, 'Downloaded DMG')
    require_download_birth(stamp, started_at, finished_at)
    digest = remote_text(vm, ['/usr/bin/shasum', '-a', '256', path], timeout=120).split()
    if not digest or not HEX_SHA.fullmatch(digest[0]) or digest[0] != expected_asset['sha256']:
        raise ValueError('Downloaded DMG differs from the trusted external digest')
    metadata = observe_metadata(vm, path)
    roots = metadata['extendedAttributes'].get('.', {})
    if not {QUARANTINE, WHERE_FROM} <= set(roots):
        raise ValueError('Downloaded DMG lacks quarantine or browser source attributes')
    quarantine = bytes.fromhex(roots[QUARANTINE]['hex'])
    _, _, guid = safari_quarantine(quarantine)
    quarantine_database = home/'Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2'
    sql = ('SELECT LSQuarantineEventIdentifier AS id, LSQuarantineTimeStamp AS appleTime, '
           'LSQuarantineAgentBundleIdentifier AS agent, LSQuarantineDataURLString AS url '
           'FROM LSQuarantineEvent WHERE LSQuarantineEventIdentifier=' + "'"+guid+"'")
    events_text = remote_text(vm, ['/usr/bin/sqlite3', '-readonly', '-json', quarantine_database, sql])
    events = json.loads(events_text, object_pairs_hook=signing.policy_object) if events_text.strip() else []
    safari = check_download_evidence(quarantine, bytes.fromhex(roots[WHERE_FROM]['hex']), events,
                                     url=url, started_at=started_at, finished_at=finished_at)
    if DOWNLOADED_DATE in roots:
        safari['downloadedDate'] = downloaded_date(bytes.fromhex(roots[DOWNLOADED_DATE]['hex']),
                                                   started_at, finished_at)
    if guest_file_stamp(vm, path) != stamp:
        raise ValueError('Guest download identity changed during verification')
    return {'file': stamp, 'sha256': digest[0], 'url': url, 'browser': 'Safari',
            'startedAt': started_at, 'finishedAt': finished_at, **safari, 'metadata': metadata}


def parse_mount_snapshot(output):
    report = disk.parse_plist(output, 'guest hdiutil info')
    rows = report.get('images')
    framework, revision = report.get('framework'), report.get('revision')
    if type(rows) is not list or type(framework) is not str or type(revision) is not str:
        raise ValueError('Incomplete guest disk image snapshot')
    images = []
    for row in rows:
        if type(row) is not dict:
            raise ValueError('Invalid guest disk image entry')
        path, writable, pid = (row.get(key) for key in ('image-path', 'writeable', 'hdid-pid'))
        if ((path is not None and type(path) is not str)
                or (writable is not None and type(writable) is not bool)
                or (pid is not None and (type(pid) is not int or pid < 2))):
            raise ValueError('Invalid guest disk image identity')
        local_path = guest_path(path) if path and path.startswith('/') else None
        images.append(disk.AttachedImage(local_path, disk.entities(row.get('system-entities')), writable, pid))
    return disk.Snapshot(framework, revision, tuple(images))


def mount_snapshot(vm):
    return parse_mount_snapshot(remote_text(vm, [disk.HDIUTIL, 'info', '-plist']))


def observe_download_mount(vm, before, download_report, volume_name):
    """Bind the user-opened read-only volume to this exact downloaded file and run."""
    stamp = download_report['file']
    path = guest_path(stamp['path'])
    if guest_file_stamp(vm, path) != stamp:
        raise ValueError('Guest download identity changed before mount inspection')
    snapshot = mount_snapshot(vm)
    matches = [item for item in snapshot.images if item.path == path]
    if len(matches) != 1 or any(item.path == path for item in before.images):
        raise ValueError('Expected one new exact download attachment')
    item = matches[0]
    mounts = [entry.mount for entry in item.entities if entry.mount is not None]
    if len(mounts) != 1 or mounts[0].parent != Path('/Volumes'):
        raise ValueError('Guest download does not have one Finder volume mount')
    mount = mounts[0]
    # The selected image path was compared inside the guest. Avoid statting
    # any unrelated guest mount or image path on the host.
    _, whole, volume = disk.owned_attachment(snapshot, before.devices, path, None, mount)
    if item.writable is not False:
        raise ValueError('Guest attachment is not explicitly read-only')
    details = disk.parse_plist(remote_text(vm, [disk.DISKUTIL, 'info', '-plist', mount]), 'guest diskutil info')
    verify_report_fields(details, {'BusProtocol': 'Disk Image', 'DeviceNode': volume.device,
                                   'ParentWholeDisk': Path(whole.device).name, 'MountPoint': str(mount),
                                   'FilesystemType': 'hfs', 'FilesystemName': disk.FILESYSTEM,
                                   'VolumeName': volume_name, 'Writable': False, 'WritableVolume': False,
                                   'WritableMedia': False}, 'Guest read-only download mount')
    volume_uuid = details.get('VolumeUUID')
    if type(volume_uuid) is not str or GUID.fullmatch(volume_uuid) is None:
        raise ValueError('Guest read-only volume did not report a valid volume UUID')
    if volume_uuid != inputs.DMG_VOLUME_UUID:
        raise ValueError('Guest volume UUID differs from the accepted engineering image')
    owner = remote_text(vm, ['/usr/bin/stat', '-f', '%u %g %p', mount]).strip()
    if re.fullmatch(r'[0-9]+ [0-9]+ 4[0-7]{4}', owner) is None:
        raise ValueError('Guest mount did not report valid directory ownership and mode')
    manifest = mount/VOLUME_MANIFEST
    guest_file_stamp(vm, manifest)
    digest = remote_text(vm, ['/usr/bin/shasum', '-a', '256', manifest]).split()
    if not digest or digest[0] != inputs.CANDIDATE_PINS['image_payload']:
        raise ValueError('Mounted image payload manifest differs from the trusted handoff')
    after = [other for other in mount_snapshot(vm).images if other.path == path
             or any(entity.mount == mount for entity in other.entities)]
    if after != [item] or guest_file_stamp(vm, path) != stamp:
        raise ValueError('Guest download or attachment changed during mount inspection')
    return {'download': stamp, 'attachment': item.describe(), 'volumeName': volume_name,
            'mountPoint': str(mount), 'wholeDevice': whole.device, 'volumeDevice': volume.device,
            'volumeUuid': volume_uuid, 'filesystem': disk.FILESYSTEM, 'readOnly': True,
            'mountOwner': owner}


def detach_download_mount(vm, before, download_report, mount_report):
    current = observe_download_mount(vm, before, download_report, mount_report['volumeName'])
    if current != mount_report:
        raise ValueError('Selected guest mount changed before detach')
    mount = guest_path(current['mountPoint'])
    output = remote_text(vm, [disk.HDIUTIL, 'detach', mount])
    image = guest_path(download_report['file']['path'])
    if any(item.path == image or any(entry.mount == mount for entry in item.entities)
           for item in mount_snapshot(vm).images):
        raise ValueError('Owned disk image or mount remains attached after normal detach')
    return {'attachment': current['attachment'], 'output': output.strip(), 'status': 'PASS'}


def mount_manifest(raw, expected_sha):
    if sha(raw) != expected_sha:
        raise ValueError('Image payload manifest differs from the trusted handoff')
    manifest = json.loads(raw, object_pairs_hook=signing.policy_object)
    if type(manifest) is not dict or type(manifest.get('inventory')) is not dict:
        raise ValueError('Image payload manifest is missing its inventory')
    verify_report_fields(manifest, {'formatVersion': 1, 'signingProfile': 'local-adhoc',
                                    'inventoryExclusions': [VOLUME_MANIFEST]}, 'Image payload manifest')
    return manifest


def installation_layout(raw, expected_sha, *, include_volume_materials=True):
    manifest = mount_manifest(raw, expected_sha)
    candidate = safe(manifest['candidatePath'])
    if len(Path(candidate).parts) != 1:
        raise ValueError('Unexpected candidate folder on the image')
    inventory = manifest['inventory']
    app_prefix = f'{candidate}/{APP}'
    app = {'.': inventory[app_prefix]}
    materials = {'.': inventory['.'] if include_volume_materials else inventory[candidate]}
    for name, entry in inventory.items():
        if name.startswith(app_prefix+'/'):
            app[name.removeprefix(app_prefix+'/')] = entry
        elif name not in {'.', app_prefix}:
            if include_volume_materials:
                materials[name] = entry
            elif name.startswith(candidate+'/'):
                materials[name.removeprefix(candidate+'/')] = entry
    if include_volume_materials:
        materials[VOLUME_MANIFEST] = bytes_entry(raw)
    return candidate, app, materials


def verify_guest_tree(vm, path, expected, *, scratch, link_roots=None, quarantine_paths=()):
    """Check actual copied bytes and modes separately from live metadata."""
    path = guest_path(path)
    physical = shlex.quote(str(path))
    verify_directory = f'test "$(cd {physical} && /bin/pwd -P)" = {physical}'
    archive = ['/usr/bin/tar', '-cf', '-', '--format', 'paxr', '--no-acls', '--no-xattrs', '--no-fflags',
               '-C', path.parent, '--', path.name]
    command = verify_directory+' && COPYFILE_DISABLE=1 '+shlex.join(map(str, archive))
    roots = [path.name] if link_roots is None else [f'{path.name}/{name}' for name in link_roots]
    with tempfile.TemporaryFile(dir=scratch) as stream:
        vm.remote(command, stdout=stream, timeout=240)
        stream.seek(0)
        with tarfile.open(fileobj=stream, mode='r:') as product:
            archive_members(product, prefixed(path.name, expected), roots)
    return {'path': str(path), 'inventorySha256': sha(encoded(expected)),
            'entries': len(expected),
            'metadata': observe_metadata(vm, path, known_paths=expected, quarantine_paths=quarantine_paths)}


def verify_guest_signatures(vm, app, candidate, policy, signed_info):
    app, candidate = map(guest_path, (app, candidate))
    if signing.policy_profile(policy) != signing.LOCAL_PROFILE:
        raise ValueError('Installed candidate requires the local ad hoc signature policy')
    signing.require_local_identity(signed_info['signature']['identity'])
    items = signed_info['signature']['items']
    verify = ['/usr/bin/codesign', '--verify', '--strict']
    result = {'appNested': remote_text(vm, [*verify, '--all-architectures', '--deep', app]), 'items': []}
    for item, accepted in zip(policy, items, strict=True):
        verify_report_fields(accepted, item.record(), 'Accepted installed signature')
        target = app.parent/item.path if Path(item.path).parts[0] == APP else candidate/item.path
        slices = accepted['slices']
        if type(slices) is not dict or 'arm64' not in slices or set(slices)-{'arm64', 'x86_64'}:
            raise ValueError('Unexpected accepted signature slices for '+item.path)
        commands = []
        for architecture, expected in sorted(slices.items()):
            signing.verify_signature_values(item, signed_info['signature']['identity'], expected)
            cdhash = expected['cdhash']
            if type(cdhash) is not str or re.fullmatch(r'[0-9a-f]{40}', cdhash) is None:
                raise ValueError('Invalid accepted CodeDirectory digest for '+item.path)
            requirement = f'identifier "{item.identifier}" and cdhash H"{cdhash}"'
            argv = [*verify, *item.bundle_args(), '--architecture', architecture,
                    '-R='+requirement, target]
            commands.append({'architecture': architecture, 'cdhash': cdhash,
                             'stdout': remote_text(vm, argv), 'exitCode': 0})
        result['items'].append({'path': str(target), 'accepted': item.record(), 'slices': commands})
    return result


def verify_installation(vm, raw, manifest_sha256, app, materials_root, *, scratch, policy, signed_info,
                        include_volume_materials=True):
    app, materials_root = map(guest_path, (app, materials_root))
    home = guest_path('/Users/'+vm.c['user'])
    if (app != home/'Applications'/APP
            or materials_root.parent != home/'Library/Application Support/meshchan-engineering'):
        raise ValueError('Use the Applications and engineering paths for the verified guest account')
    manifest = mount_manifest(raw, manifest_sha256)
    verify_report_fields(manifest, {'signedInfoSha256': sha(encoded(signed_info)),
                                    'identity': signed_info['identity']}, 'Installed signing manifest')
    candidate, app_inventory, materials = installation_layout(
        raw, manifest_sha256, include_volume_materials=include_volume_materials)
    candidate_root = materials_root/candidate if include_volume_materials else materials_root
    candidate_prefix = candidate_root.relative_to(materials_root)
    quarantine_paths = []
    for item in signed_info['signature']['items']:
        binary = signing.relative_product_path(item['binary'])
        if binary.parts[0] == 'meshctl':
            quarantine_paths.append((candidate_prefix/binary).as_posix())
    app_report = verify_guest_tree(vm, app, app_inventory, scratch=scratch)
    plist = remote_text(vm, ['/usr/bin/plutil', '-convert', 'xml1', '-o', '-', app/'Contents/Info.plist'])
    apple_identity = disk.parse_plist(plist, 'installed Info.plist')
    verify_report_fields(apple_identity, manifest['identity']['apple'], 'Installed Apple identity')
    return {'imageManifestSha256': manifest_sha256,
            'app': app_report, 'appleIdentity': manifest['identity']['apple'],
            'materials': verify_guest_tree(vm, materials_root, materials, scratch=scratch, link_roots=[],
                                           quarantine_paths=quarantine_paths),
            'signatures': verify_guest_signatures(vm, app, candidate_root, policy, signed_info),
            'layout': {'app': str(app), 'cli': str(candidate_root/'meshctl/bin/meshctl'),
                       'candidateMaterials': str(candidate_root),
                       'volumeMaterials': str(materials_root) if include_volume_materials else None}}


def os_version(value):
    if type(value) is not str or re.fullmatch(r'[0-9]+\.[0-9]+(?:\.[0-9]+)?', value) is None:
        raise ValueError('Invalid macOS deployment version')
    fields = tuple(map(int, value.split('.')))
    return (*fields, 0) if len(fields) == 2 else fields


def deployment_command(output):
    """Read the platform and minimum version from one arm64 Mach-O listing."""
    commands = []
    for block in re.split(r'^Load command \d+$', output, flags=re.MULTILINE)[1:]:
        names = re.findall(r'^\s*cmd (\S+)$', block, re.MULTILINE)
        if names == ['LC_BUILD_VERSION']:
            key = 'minos'
            if re.findall(r'^\s*platform (\S+)$', block, re.MULTILINE) not in (['1'], ['MACOS'], ['macos']):
                raise ValueError('The arm64 build command must identify macOS')
        elif names == ['LC_VERSION_MIN_MACOSX']:
            key = 'version'
        else:
            continue
        minimum = re.findall(rf'^\s*{key} (\S+)$', block, re.MULTILINE)
        sdk = re.findall(r'^\s*sdk (\S+)$', block, re.MULTILINE)
        if len(minimum) != 1 or len(sdk) != 1:
            raise ValueError('Incomplete macOS deployment command')
        os_version(minimum[0])
        os_version(sdk[0])
        commands.append({'command': names[0], 'minimum': minimum[0], 'sdk': sdk[0]})
    if len(commands) != 1:
        raise ValueError('Expected one macOS deployment command in the arm64 slice')
    return commands[0]


def static_deployment(candidate, signed_info):
    """Inspect only accepted compiled bytes with the host tooling, without executing the product."""
    inventory = signed_info['payloadInventory']

    def accepted_file(name):
        path = require_material_file(candidate, name)
        entry, _ = file_stamp(path)
        verify_report_fields(entry, inventory[name], 'Accepted deployment input '+name)
        return path, entry['sha256']

    plist, plist_sha = accepted_file(APP+'/Contents/Info.plist')
    minimum = plistlib.loads(plist.read_bytes())['LSMinimumSystemVersion']
    floors = {'app': [minimum], 'cli': []}
    os_version(minimum)
    results = []
    for item in signed_info['signature']['items']:
        name = str(signing.relative_product_path(item['binary']))
        binary, digest = accepted_file(name)
        command = ['/usr/bin/otool', '-arch', 'arm64', '-l', binary]
        output = subprocess.run(command, check=True, capture_output=True, text=True, timeout=30,
                                env=controlled_environment()).stdout
        version = deployment_command(output)
        floors['app' if name.startswith(APP+'/') else 'cli'].append(version['minimum'])
        results.append({'binary': name, 'sha256': digest, **version})
    app_floor, cli_floor = (max(floors[product], key=os_version) for product in ('app', 'cli'))
    return {'architecture': 'arm64', 'probe': '/usr/bin/otool -arch arm64 -l',
            'appPlist': {'sha256': plist_sha, 'minimum': minimum}, 'code': results,
            'appCodeMinimum': app_floor, 'cliCodeMinimum': cli_floor,
            'engineeringProductCodeMinimum': max(app_floor, cli_floor, key=os_version)}
