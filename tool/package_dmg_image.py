"""Create and inspect a macOS engineering disk image with an owned mount."""
from contextlib import contextmanager
from dataclasses import dataclass
import io
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import time
from xml.parsers.expat import ExpatError

import build_release as build
from package_release import equal, file_stamp, require_extraction_root, verify_report_fields
from release_package_archive import metadata_observations
from release_materials import digest, sha

HDIUTIL = '/usr/bin/hdiutil'
DISKUTIL = '/usr/sbin/diskutil'
IMAGE_FORMAT = 'UDZO'
FILESYSTEM = 'HFS+'
IMAGE_TYPE = 'UDIF read-only compressed (zlib)'
WHOLE_DISK = re.compile(r'/dev/disk[0-9]+')
DEVICE = re.compile(r'/dev/disk[0-9]+(?:s[0-9]+)*')
ATTACH_SETTLE_SECONDS = 5


def parse_plist(text, label):
    try:
        result = plistlib.loads(text.encode())
    except (ValueError, TypeError, plistlib.InvalidFileException, ExpatError) as error:
        raise ValueError('Invalid '+label+' property list') from error
    if type(result) is not dict:
        raise ValueError('Expected a dictionary in '+label+' property list')
    return result


def require_image(image, stamp):
    equal(stamp, file_stamp(image), 'Disk image file identity, metadata, and contents')


def create_image(runner, staging, image, volume_name):
    runner.command('create-image', [HDIUTIL, 'create', '-srcfolder', staging, '-format', IMAGE_FORMAT,
                                    '-fs', FILESYSTEM, '-volname', volume_name, '-nospotlight', '-plist', image])
    return file_stamp(image)


def verify_image(runner, image, stamp):
    require_image(image, stamp)
    details = parse_plist(runner.command('image-info', [HDIUTIL, 'imageinfo', '-plist', image]), 'hdiutil imageinfo')
    verify_report_fields(details, {'Format': IMAGE_FORMAT, 'Format Description': IMAGE_TYPE,
                                   'Class Name': 'CUDIFDiskImage'}, 'Disk image')
    verify_report_fields(details['Properties'], {'Checksummed': True, 'Compressed': True, 'Encrypted': False},
                         'Disk image properties')
    partitions = details['partitions']['partitions']
    if type(partitions) is not list or any(type(part) is not dict for part in partitions):
        raise ValueError('Invalid disk image partition information')
    filesystems = [part['partition-filesystems'] for part in partitions if 'partition-filesystems' in part]
    equal([{FILESYSTEM: ''}], filesystems, 'Disk image data partition')
    checksum = parse_plist(runner.command('verify-image', [HDIUTIL, 'verify', '-plist', image]), 'hdiutil verify')
    expected = checksum.get('expected')
    if (type(expected) is not dict or expected.get('Checksum Type') != 'CRC32'
            or type(expected.get('Checksum Value')) is not str
            or re.fullmatch(r'\$[0-9A-Fa-f]{8}', expected['Checksum Value']) is None):
        raise ValueError('Missing structural checksum in disk image verification')
    verify_report_fields(checksum, {'calculated': expected}, 'Disk image structural verification')
    try:
        runner.command('inspect-container-signature', ['/usr/bin/codesign', '--display', image])
    except subprocess.CalledProcessError as error:
        diagnostics = error.stderr or b''
        if isinstance(diagnostics, str):
            diagnostics = diagnostics.encode()
        if error.returncode != 1 or diagnostics.strip() != os.fsencode(image)+b': code object is not signed at all':
            raise
    else:
        raise ValueError('Engineering disk image container unexpectedly has a code signature')
    require_image(image, stamp)
    return {'format': IMAGE_FORMAT, 'formatDescription': IMAGE_TYPE, 'filesystem': FILESYSTEM,
            'checksum': expected, 'containerSignature': 'UNSIGNED'}


@dataclass(frozen=True)
class Entity:
    device: str
    mount: Path | None


def entities(value):
    if type(value) is not list or not value:
        raise ValueError('Disk image property list has no system entities')
    result = []
    for item in value:
        if type(item) is not dict:
            raise ValueError('Invalid system entity in disk image property list')
        device = item.get('dev-entry')
        mount = item.get('mount-point')
        if (type(device) is not str or DEVICE.fullmatch(device) is None
                or (mount is not None and (type(mount) is not str or not Path(mount).is_absolute()))):
            raise ValueError('Invalid device or mount point in disk image property list')
        result.append(Entity(device, Path(mount) if mount is not None else None))
    if len({entity.device for entity in result}) != len(result):
        raise ValueError('Duplicate disk image device')
    # hdiutil may report the same devices in a different order on each query.
    return tuple(sorted(result, key=lambda entity: entity.device))


@dataclass(frozen=True)
class AttachedImage:
    path: Path | None
    entities: tuple[Entity, ...]
    writable: bool | None
    pid: int | None

    def names(self, path, pin):
        if self.path == path:
            return True
        if self.path is None:
            return False
        try:
            metadata = self.path.stat()
        except (FileNotFoundError, NotADirectoryError, PermissionError):
            return False
        return (metadata.st_dev, metadata.st_ino) == pin

    def describe(self):
        return {'path': str(self.path) if self.path is not None else None,
                'imageProcessPid': self.pid, 'writable': self.writable,
                'entities': [{'device': entity.device, 'mountPoint': str(entity.mount) if entity.mount else None}
                             for entity in self.entities]}


@dataclass(frozen=True)
class Snapshot:
    framework: str
    revision: str
    images: tuple[AttachedImage, ...]

    @property
    def devices(self):
        return {entity.device for image in self.images for entity in image.entities}

    def related(self, image, pin, mount):
        return [item for item in self.images
                if item.names(image, pin)
                or any(entity.mount is not None and entity.mount.resolve() == mount for entity in item.entities)]


def image_snapshot(runner):
    # Capture only related entries in the acceptance record. A global hdiutil
    # report can contain paths to private images and other users' mount points.
    result = subprocess.run([HDIUTIL, 'info', '-plist'], env=runner.env, timeout=min(runner.timeout, 30),
                            check=True, capture_output=True, text=True)
    value = parse_plist(result.stdout, 'hdiutil info')
    reports = value.get('images')
    if (type(reports) is not list or type(value.get('framework')) is not str
            or type(value.get('revision')) is not str):
        raise ValueError('Incomplete hdiutil info property list')
    images = []
    for report in reports:
        if type(report) is not dict:
            raise ValueError('Invalid image row in hdiutil info')
        path, writable, pid = report.get('image-path'), report.get('writeable'), report.get('hdid-pid')
        if ((path is not None and type(path) is not str)
                or (writable is not None and type(writable) is not bool)
                or (pid is not None and (type(pid) is not int or pid < 2))):
            raise ValueError('Invalid image identity in hdiutil info')
        # An unrelated image can have a remote backing URL. Its devices still
        # count as preexisting, but only local image paths can match this input.
        local = Path(path).resolve() if path is not None and Path(path).is_absolute() else None
        images.append(AttachedImage(local,
                                    entities(report.get('system-entities')), writable, pid))
    return Snapshot(value['framework'], value['revision'], tuple(images))


def owned_attachment(snapshot, prior_devices, image, image_pin, mount):
    on_owned_path = [item for item in snapshot.images if any(entity.mount == mount for entity in item.entities)]
    if len(on_owned_path) != 1:
        raise ValueError('Cannot establish ownership of the disk image attachment')
    item = on_owned_path[0]
    whole = [entity for entity in item.entities if WHOLE_DISK.fullmatch(entity.device)]
    mounted = [entity for entity in item.entities if entity.mount is not None]
    other_devices = {entity.device for other in snapshot.images if other is not item for entity in other.entities}
    if (not item.names(image, image_pin) or item.pid is None or len(item.entities) != 2 or len(whole) != 1
            or len(mounted) != 1 or mounted[0].mount != mount
            or re.fullmatch(re.escape(whole[0].device)+r's[0-9]+', mounted[0].device) is None
            or any(entity.device in other_devices for entity in item.entities)
            or any(entity.device in prior_devices for entity in item.entities)):
        raise ValueError('Cannot establish ownership of the disk image attachment')
    return item, whole[0], mounted[0]


def volume_information(runner, mount, whole, volume, name):
    reported = parse_plist(runner.command('volume-info', [DISKUTIL, 'info', '-plist', mount]), 'diskutil info')
    verify_report_fields(reported, {
        'BusProtocol': 'Disk Image', 'DeviceNode': volume.device, 'ParentWholeDisk': Path(whole.device).name,
        'MountPoint': str(mount), 'FilesystemType': 'hfs', 'FilesystemName': FILESYSTEM, 'VolumeName': name,
        'Writable': False, 'WritableVolume': False, 'WritableMedia': False,
    }, 'Read-only disk image volume')
    if type(reported.get('GlobalPermissionsEnabled')) is not bool:
        raise ValueError('Missing volume ownership information')
    if not os.statvfs(mount).f_flag & os.ST_RDONLY:
        raise ValueError('Disk image does not have a read-only mount flag')
    owner = mount.lstat()
    metadata = metadata_observations(mount, {'.': {}}).get('.', [])
    return {'name': name, 'mountPoint': str(mount), 'wholeDevice': whole.device, 'volumeDevice': volume.device,
            'filesystem': reported['FilesystemName'], 'volumeUuid': reported['VolumeUUID'], 'readOnly': True,
            'volumeRoot': {'mode': stat.S_IMODE(owner.st_mode), 'uid': owner.st_uid, 'gid': owner.st_gid,
                           'globalPermissionsEnabled': reported['GlobalPermissionsEnabled'],
                           'systemManagedExtendedAttributes': metadata}}


def attach_image(runner, mount, image, record):
    # DiskImages starts a process that intentionally outlives the command.
    # Reap the CLI here. The attachment verified below owns the disk helper,
    # which the normal detach closes without process-group signals.
    name = 'attach-image'
    argv = list(map(str, [HDIUTIL, 'attach', '-readonly', '-nobrowse', '-noautoopen',
                          '-mount', 'required', '-mountpoint', mount, '-plist', image]))
    stdout = runner.evidence/'logs/attach-image.log'
    stderr = runner.evidence/'logs/attach-image.stderr.log'
    stdout.parent.mkdir(exist_ok=True)
    started = time.monotonic()
    step = {'name': name, 'argv': argv, 'cwd': str(runner.root), 'startedAt': build.now(),
            'log': stdout.relative_to(runner.root).as_posix(),
            'stderrLog': stderr.relative_to(runner.root).as_posix()}
    runner.receipt['steps'].append(step)
    runner.save()
    if runner.show_progress:
        print('START '+name, flush=True)
    try:
        build.raise_if_interrupted(runner.interrupted)
        with stdout.open('xb') as log, stderr.open('xb') as diagnostics:
            with subprocess.Popen(argv, cwd=runner.root, env=runner.env, stdin=subprocess.DEVNULL,
                                  stdout=log, stderr=diagnostics, start_new_session=True) as process:
                step['pid'] = process.pid
                record['attachChildPid'] = process.pid
                try:
                    while process.poll() is None:
                        build.raise_if_interrupted(runner.interrupted)
                        if time.monotonic()-started > runner.timeout:
                            raise TimeoutError('Command deadline exceeded: '+name)
                        time.sleep(0.05)
                finally:
                    if process.poll() is None:
                        try:
                            process.terminate()
                            process.wait(timeout=2)
                        except ProcessLookupError:
                            pass
                        except subprocess.TimeoutExpired:
                            process.kill()
                    step['exitCode'] = process.wait()
                    step['childReaped'] = True
        stderr_data = stderr.read_bytes()
        if step['exitCode']:
            raise subprocess.CalledProcessError(step['exitCode'], argv, stderr=stderr_data)
        data = stdout.read_bytes()
        step['logSha256'], step['stderrLogSha256'] = sha(data), sha(stderr_data)
        build.raise_if_interrupted(runner.interrupted)
    finally:
        step.setdefault('logSha256', digest(stdout) if stdout.exists() else None)
        step.setdefault('stderrLogSha256', digest(stderr) if stderr.exists() else None)
        step.update(finishedAt=build.now(), elapsedSeconds=round(time.monotonic()-started, 3))
        runner.save()
    if runner.show_progress:
        print('PASS '+name, flush=True)
    with io.TextIOWrapper(io.BytesIO(data)) as stream:
        return stream.read()


def cleanup_snapshot(runner):
    # Reobserve once if DiskImages is temporarily unavailable. Cleanup still
    # requires a valid snapshot before it can detach or confirm disappearance.
    try:
        return image_snapshot(runner)
    except (OSError, ValueError, subprocess.SubprocessError):
        time.sleep(0.1)
        return image_snapshot(runner)


def cleanup_attachment(runner, before, image, pin, mount, owned, record):
    # On failed attach the CLI may exit while DiskImages is still registering
    # the device or mount point. Give an unconfirmed attachment time to appear.
    deadline = time.monotonic() + (min(runner.timeout, ATTACH_SETTLE_SECONDS) if owned is None else 0)
    while True:
        current = cleanup_snapshot(runner)
        related = current.related(image, pin, mount)
        record['residualAttachments'] = [item.describe() for item in related]
        if related:
            try:
                selected, _, _ = owned_attachment(current, before.devices, image, pin, mount)
            except ValueError:
                if time.monotonic() >= deadline:
                    raise
            else:
                if owned is not None:
                    equal(owned, selected, 'Selected attachment before detach')
                return selected
        elif time.monotonic() >= deadline:
            if owned is not None:
                raise ValueError('Owned image attachment disappeared before normal detach')
            return None
        time.sleep(0.1)


def detach_image(runner, mount):
    # Eject even when the evidence filesystem is unwritable. Capture the small
    # command output in memory and persist it only after reaping the command.
    argv = [HDIUTIL, 'detach', str(mount)]
    stdout, stderr = b'', b''
    step = {'name': 'detach-image', 'argv': argv, 'cwd': '/', 'startedAt': build.now()}
    started = time.monotonic()
    try:
        result = subprocess.run(argv, cwd=step['cwd'], env=runner.env, stdin=subprocess.DEVNULL,
                                capture_output=True, timeout=min(runner.timeout, 30), start_new_session=True)
        stdout, stderr = result.stdout, result.stderr
        step.update(exitCode=result.returncode, childReaped=True)
        result.check_returncode()
    except subprocess.TimeoutExpired as error:
        stdout, stderr = error.stdout or b'', error.stderr or b''
        step.update(timedOut=True, childReaped=True)
        raise
    finally:
        step.update(finishedAt=build.now(), elapsedSeconds=round(time.monotonic()-started, 3))
        runner.receipt['steps'].append(step)
        logs = runner.evidence/'logs'
        logs.mkdir(exist_ok=True)
        for label, filename, data in (('log', 'detach-image.log', stdout),
                                      ('stderrLog', 'detach-image.stderr.log', stderr)):
            path = logs/filename
            with path.open('xb') as stream:
                stream.write(data)
            step.update({label: path.relative_to(runner.root).as_posix(), label+'Sha256': sha(data)})
        runner.save()


@contextmanager
def mounted_image(runner, image, stamp, mount, name, record):
    """Yield only a confirmed new read-only path and detach only its own device."""
    require_image(image, stamp)
    before = image_snapshot(runner)
    record['diskImages'] = {'framework': before.framework, 'revision': before.revision}
    related = before.related(image, stamp[1], mount)
    if related:
        record['existingAttachments'] = [item.describe() for item in related]
        raise ValueError('The selected disk image or mount point is already attached')
    mount.mkdir(mode=0o700)
    mount_stamp = mount.lstat()
    record['mountPoint'] = str(mount)
    record['attachStatus'] = 'RUNNING'
    record['detachStatus'] = 'PENDING'
    owned = None
    try:
        attached = attach_image(runner, mount, image, record)
        after = image_snapshot(runner)
        owned, whole, volume = owned_attachment(after, before.devices, image, stamp[1], mount)
        declared = entities(parse_plist(attached, 'hdiutil attach').get('system-entities'))
        equal(set(owned.entities), set(declared), 'Attach property list ownership')
        if owned.writable is not False:
            raise ValueError('Disk image attachment is not explicitly read-only')
        record['mount'] = volume_information(runner, mount, whole, volume, name)
        require_image(image, stamp)
        record['attachStatus'] = 'PASS'
        yield mount
    except BaseException as error:
        error_field = 'extractionError' if record['attachStatus'] == 'PASS' else 'attachError'
        record[error_field] = build.failure_message(error)
        raise
    finally:
        # A timed-out or interrupted attach can still have registered a mount.
        # Use a fresh bounded cleanup supervisor to run after a deferred signal.
        cleanup = build.Runner(runner.root, runner.evidence, runner.receipt, runner.env,
                               min(runner.timeout, 30), [])
        try:
            current = None
            if 'attachChildPid' in record:
                current = cleanup_attachment(cleanup, before, image, stamp[1], mount, owned, record)
            else:
                related = cleanup_snapshot(cleanup).related(image, stamp[1], mount)
                record['residualAttachments'] = [item.describe() for item in related]
                if related:
                    raise ValueError('Unexpected attachment when the attach command did not launch')
            if current is not None:
                record['ownedAttachment'] = current.describe()
                # Device numbers can be reused if an attachment disappears.
                # Address the freshly owned path so that reuse elsewhere cannot
                # redirect the detach to another device.
                try:
                    detach_image(cleanup, mount)
                except Exception:
                    try:
                        remaining = cleanup_snapshot(cleanup).related(image, stamp[1], mount)
                        record['residualAttachments'] = [item.describe() for item in remaining]
                    except Exception as error:
                        record['residualSnapshotError'] = build.failure_message(error)
                    raise
                remaining = cleanup_snapshot(cleanup).related(image, stamp[1], mount)
                record['residualAttachments'] = [item.describe() for item in remaining]
                if remaining:
                    raise ValueError('Matching image or mount path remains registered after normal detach')
                record['detachStatus'] = 'PASS'
            else:
                record['detachStatus'] = 'ABSENT' if 'attachChildPid' in record else 'NOT_RUN'
            require_extraction_root(mount, mount_stamp)
            if any(mount.iterdir()):
                raise ValueError('Unmounted path does not contain its original empty directory')
            mount.rmdir()
        except Exception as error:
            record['detachStatus'] = 'FAIL'
            record['detachError'] = build.failure_message(error)
            raise
