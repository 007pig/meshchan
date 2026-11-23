"""Exact-inventory PAX tar handling for the Phase 1E.5 engineering package."""
from collections import defaultdict, deque
from contextlib import ExitStack, contextmanager
import errno
import hashlib
import os
from pathlib import PurePosixPath
import shutil
import stat
import sys
import tarfile

from release_materials import product_inventory


QUARANTINE_ATTRIBUTE = 'com.apple.quarantine'


def compare(expected, actual, label):
    if expected != actual:
        different = sorted(key for key in expected.keys() | actual.keys()
                           if expected.get(key) != actual.get(key))
        raise ValueError(f'{label} differs at {", ".join(different[:8])} '
                         f'({len(different)} differing entries)')


def prefixed(prefix, inventory):
    return {prefix if name == '.' else prefix+'/'+name: entry
            for name, entry in inventory.items()}


def check_payload(root, expected):
    compare(expected, product_inventory(root), str(root))
    for name, entry in expected.items():
        if entry['type'] == 'file' and (root/name).lstat().st_nlink != 1:
            raise ValueError('Packaged file has shared hard links: '+str(root/name))


def archive_members(archive, expected, link_roots):
    """Validate the complete member graph and all file data before writing."""
    members = {}
    for member in archive:
        name = member.name
        path = PurePosixPath(name)
        if (not path.parts or path.is_absolute() or '..' in path.parts
                or path.as_posix() != name or name in members or name not in expected):
            raise ValueError('Unexpected, unsafe or repeated archive member: '+repr(name))
        entry = expected[name]
        kind = {tarfile.REGTYPE: 'file', tarfile.AREGTYPE: 'file',
                tarfile.DIRTYPE: 'directory', tarfile.SYMTYPE: 'symlink'}.get(member.type)
        if (kind != entry['type'] or member.mode != entry['mode'] or member.sparse is not None
                or member.mode & ~0o777 or set(member.pax_headers) - {'path', 'linkpath', 'mtime'}):
            raise ValueError('Unexpected archive type, mode or metadata: '+name)
        if member.size != entry.get('size', 0) or member.linkname != entry.get('symlink', ''):
            raise ValueError('Unexpected archive size or link target: '+name)
        members[name] = member
    if members.keys() != expected.keys():
        raise ValueError('Missing archive members: '+', '.join(sorted(expected.keys()-members.keys())[:8]))
    # tarfile stops at the first end marker (and can stop at an invalid header).
    # Require the complete terminator and allow only zero padding after it.
    archive.fileobj.seek(archive.offset)
    end = bytes(2*tarfile.BLOCKSIZE)
    if archive.fileobj.read(len(end)) != end:
        raise ValueError('Missing tar end-of-archive blocks')
    while padding := archive.fileobj.read(64*1024):
        if padding.strip(b'\0'):
            raise ValueError('Unexpected data after tar end-of-archive blocks')
    for name, member in members.items():
        parent = str(PurePosixPath(name).parent)
        if parent != '.' and expected.get(parent, {}).get('type') != 'directory':
            raise ValueError('Archive member lacks a real parent directory: '+name)
        if member.issym():
            validate_link(name, expected, link_roots)
        if member.isfile():
            with archive.extractfile(member) as stream:
                if hashlib.file_digest(stream, 'sha256').hexdigest() != expected[name]['sha256']:
                    raise ValueError('Archive file content differs: '+name)
    return members


def validate_link(name, expected, link_roots):
    path = PurePosixPath(name)
    origin = next((PurePosixPath(root) for root in link_roots if path.is_relative_to(root)), None)
    if origin is None:
        raise ValueError('Unexpected archive symlink: '+name)
    parts = deque([path.name])
    current, followed = path.parent, 0
    while parts:
        part = parts.popleft()
        if expected.get(str(current), {}).get('type') != 'directory':
            raise ValueError('Archive link traverses a missing path or non-directory: '+name)
        if part in ('', '.'):
            continue
        if part == '..':
            if current == origin:
                raise ValueError('Archive link escapes its product: '+name)
            current = current.parent
            continue
        child = current/part
        entry = expected.get(str(child))
        if entry is None:
            raise ValueError('Dangling archive link: '+name)
        if entry['type'] == 'symlink':
            raw = entry['symlink']
            followed += 1
            if not raw or raw.startswith('/') or followed > 40:
                raise ValueError('Absolute, empty or cyclic archive link: '+name)
            parts.extendleft(reversed(raw.split('/')))
        else:
            current = child


def create_archive(path, stage, expected):
    with path.open('x+b') as output:
        with tarfile.open(fileobj=output, mode='w:', format=tarfile.PAX_FORMAT) as archive:
            for name, entry in sorted(expected.items()):
                source = stage.parent/name
                member = archive.gettarinfo(str(source), arcname=name)
                member.uid = member.gid = 0
                member.uname = member.gname = ''
                if entry['type'] == 'file':
                    with source.open('rb') as stream:
                        archive.addfile(member, stream)
                else:
                    archive.addfile(member)
        output.flush()
        return archive_stamp(output)


def archive_stamp(stream):
    st = os.fstat(stream.fileno())
    if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1:
        raise ValueError('Archive must be a single-link regular file')
    stream.seek(0)
    entry = {'type': 'file', 'mode': stat.S_IMODE(st.st_mode), 'size': st.st_size,
             'sha256': hashlib.file_digest(stream, 'sha256').hexdigest()}
    stream.seek(0)
    return entry, (st.st_dev, st.st_ino)


def open_archive(path):
    return os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), 'rb')


@contextmanager
def directory_fd(path, parent=None):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
    try:
        yield fd
    finally:
        os.close(fd)


@contextmanager
def new_extraction_root(destination):
    """Create and pin a fresh root without following any path components."""
    with ExitStack() as parents:
        parent = parents.enter_context(directory_fd(destination.anchor))
        for part in destination.parent.parts[1:]:
            parent = parents.enter_context(directory_fd(part, parent))
        os.mkdir(destination.name, mode=0o700, dir_fd=parent)
        with directory_fd(destination.name, parent) as target:
            yield target


def extract_archive(stream, destination, expected, link_roots):
    """Materialize validated members relative to the already-open root."""
    with tarfile.open(fileobj=stream, mode='r:') as archive:
        members = archive_members(archive, expected, link_roots)
        children = defaultdict(list)
        for name in sorted(members):
            path = PurePosixPath(name)
            children[path.parent].append(path)

        def write_directory(path, parent):
            for child in children[path]:
                member = members[child.as_posix()]
                name = child.name
                if member.isdir():
                    os.mkdir(name, mode=0o700, dir_fd=parent)
                    with directory_fd(name, parent) as fd:
                        write_directory(child, fd)
                        os.fchmod(fd, member.mode)
                elif member.isfile():
                    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
                    with archive.extractfile(member) as source:
                        fd = os.open(name, flags, 0o600, dir_fd=parent)
                        with os.fdopen(fd, 'wb') as target:
                            shutil.copyfileobj(source, target, length=1024*1024)
                            os.fchmod(target.fileno(), member.mode)
                else:
                    os.symlink(member.linkname, name, dir_fd=parent)
                    mode = os.stat(name, dir_fd=parent, follow_symlinks=False).st_mode
                    if stat.S_IMODE(mode) != member.mode:
                        os.chmod(name, member.mode, dir_fd=parent, follow_symlinks=False)

        write_directory(PurePosixPath('.'), destination)


class MacMetadata:
    """The data tar omits filesystem metadata that this candidate does not need."""

    def __init__(self):
        import ctypes
        self.ctypes = ctypes
        self.lib = ctypes.CDLL(None, use_errno=True)
        self.lib.listxattr.argtypes = (ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int)
        self.lib.listxattr.restype = ctypes.c_ssize_t
        self.lib.getxattr.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p,
                                    ctypes.c_size_t, ctypes.c_uint32, ctypes.c_int)
        self.lib.getxattr.restype = ctypes.c_ssize_t
        self.lib.acl_get_link_np.argtypes = (ctypes.c_char_p, ctypes.c_int)
        self.lib.acl_get_link_np.restype = ctypes.c_void_p
        self.lib.acl_free.argtypes = (ctypes.c_void_p,)

    def inspect(self, path, *, allow_quarantine=False):
        raw = os.fsencode(path)
        size = self.lib.listxattr(raw, None, 0, 1)  # XATTR_NOFOLLOW
        if size < 0:
            raise OSError(self.ctypes.get_errno(), 'Cannot inspect extended attributes', path)
        names = []
        if size:
            buffer = self.ctypes.create_string_buffer(size)
            if self.lib.listxattr(raw, buffer, size, 1) != size:
                raise ValueError('Extended attributes changed during inspection: '+str(path))
            names = buffer.raw[:-1].decode().split('\0')
        allowed = {'com.apple.provenance'}
        if allow_quarantine:
            allowed.add(QUARANTINE_ATTRIBUTE)
        if set(names) - allowed:
            raise ValueError('Unsupported extended attributes (including resource forks): '+str(path))
        acl = self.lib.acl_get_link_np(raw, 0x100)  # ACL_TYPE_EXTENDED
        if acl:
            self.lib.acl_free(acl)
            raise ValueError('Unsupported extended ACL: '+str(path))
        if self.ctypes.get_errno() != errno.ENOENT:
            raise OSError(self.ctypes.get_errno(), 'Cannot inspect extended ACL', path)
        if path.lstat().st_flags:
            raise ValueError('Unsupported file flags: '+str(path))
        return names

    def quarantine(self, path):
        raw, name = os.fsencode(path), QUARANTINE_ATTRIBUTE.encode('ascii')
        size = self.lib.getxattr(raw, name, None, 0, 0, 1)  # XATTR_NOFOLLOW
        if size < 0:
            raise OSError(self.ctypes.get_errno(), 'Cannot read quarantine attribute', path)
        if not 0 < size <= 4096:
            raise ValueError('Unexpected quarantine attribute size: '+str(path))
        buffer = self.ctypes.create_string_buffer(size)
        if self.lib.getxattr(raw, name, buffer, size, 0, 1) != size:
            raise ValueError('Quarantine attribute changed during inspection: '+str(path))
        return buffer.raw


def metadata_observations(root, inventory, *, allow_quarantine=False):
    if sys.platform != 'darwin':
        return {}
    inspector = MacMetadata()
    observations = {}
    for name in inventory:
        if names := inspector.inspect(root/name, allow_quarantine=allow_quarantine):
            observations[name] = names
    return observations
