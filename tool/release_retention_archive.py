"""Exact archive creation and restoration for selected engineering evidence."""

from contextlib import ExitStack
import os
from pathlib import Path, PurePosixPath
import stat
import tarfile

from release_materials import product_inventory
from release_package_archive import (
    archive_stamp, check_payload, directory_fd, extract_archive, new_extraction_root, open_archive,
)


def file_identity(metadata):
    return (metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_size,
            metadata.st_mtime_ns, metadata.st_ctime_ns)


def regular_entry(path):
    with open_archive(path) as stream:
        stamp = file_identity(os.fstat(stream.fileno()))
        identity, _ = archive_stamp(stream)
        if file_identity(os.fstat(stream.fileno())) != stamp or file_identity(path.lstat()) != stamp:
            raise ValueError(f'Input changed while being read: {path}')
    return identity, stamp


def scanned_input(path):
    if stat.S_ISREG(path.lstat().st_mode):
        entry, stamp = regular_entry(path)
        return {'.': entry}, {'.': stamp}
    # Snapshot the underlying directory entries as well as the exact inventory.
    inventory = product_inventory(path)
    return inventory, {name: file_identity((path/name).lstat()) for name in inventory}


def write_archive(path, mapping, expected, stamps):
    origins = {member: Path(original) for original, member in mapping.items()}
    with path.open('x+b') as output:
        os.fchmod(output.fileno(), 0o400)
        with tarfile.open(fileobj=output, mode='w:', format=tarfile.PAX_FORMAT) as archive:
            for name, entry in sorted(expected.items()):
                member = tarfile.TarInfo(name)
                member.mode = entry['mode']
                if member.mode & ~0o777:
                    raise ValueError(f'Unsupported permission bits: {name}')
                if entry['type'] == 'directory':
                    member.type = tarfile.DIRTYPE
                    archive.addfile(member)
                elif entry['type'] == 'symlink':
                    member.type = tarfile.SYMTYPE
                    member.linkname = entry['symlink']
                    archive.addfile(member)
                else:
                    relative = PurePosixPath(name)
                    prefix = str(PurePosixPath(*relative.parts[:2]))
                    root = origins[prefix]
                    source_name = relative.relative_to(prefix)
                    source = root/source_name
                    before = stamps[str(root)][str(source_name)]
                    member.size = entry['size']
                    with ExitStack() as ancestors:
                        parent = ancestors.enter_context(directory_fd(source.anchor))
                        for part in source.parent.parts[1:]:
                            parent = ancestors.enter_context(directory_fd(part, parent))
                        flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
                        fd = os.open(source.name, flags, dir_fd=parent)
                        with os.fdopen(fd, 'rb') as file:
                            if not stat.S_ISREG(os.fstat(fd).st_mode) or file_identity(os.fstat(fd)) != before:
                                raise ValueError(f'Input changed before archiving: {source}')
                            archive.addfile(member, file)
                            if file_identity(os.fstat(fd)) != before:
                                raise ValueError(f'Input changed while archiving: {source}')
        output.flush()
        os.fsync(output.fileno())
        return archive_stamp(output)[0]


def restore_members(path, destination, expected_archive, members, roots):
    # Pin the complete tar bytes before parsing even the first member.
    with open_archive(path) as stream:
        original = file_identity(os.fstat(stream.fileno()))
        if archive_stamp(stream)[0] != expected_archive:
            raise ValueError('Retained archive bytes, size or mode differ from the external receipt')
        if file_identity(os.fstat(stream.fileno())) != original or file_identity(path.lstat()) != original:
            raise ValueError('Retained archive changed while checking its pin')
        with new_extraction_root(destination) as fd:
            extract_archive(stream, fd, members, tuple(roots))
            restored = os.fstat(fd)
            if not os.path.samestat(restored, destination.lstat()):
                raise ValueError('Restore directory was replaced')
        check_payload(destination, {'.': {'type': 'directory', 'mode': 0o700}, **members})
        if (archive_stamp(stream)[0] != expected_archive
                or file_identity(os.fstat(stream.fileno())) != original
                or file_identity(path.lstat()) != original):
            raise ValueError('Retained archive changed during verification')
        return original, restored
