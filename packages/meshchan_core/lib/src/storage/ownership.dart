import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../errors.dart';

const databaseFileName = 'meshchan.sqlite';
const ownershipFileName = '.meshchan.owner.lock';
const markerFileName = '.meshchan.owner.json';

/// A persistent, dedicated inode, never unlinked by the application. BSD flock
/// uses independent open descriptions, including within one process/isolate.
/// Do not replace this with Dart's process-associated fcntl record lock.
final class DirectoryOwnership {
  DirectoryOwnership._(this.directory, this._identity, this._fd);
  final String directory;
  final String _identity;
  final int _fd;
  bool _released = false;
  static final _reservations = <String>{};

  static DirectoryOwnership acquire(Directory requested) {
    if (!const [
      Abi.macosArm64,
      Abi.macosX64,
      Abi.linuxArm64,
      Abi.linuxX64,
    ].contains(Abi.current())) {
      throw const CoreException(CoreErrorCode.storageOpenFailed);
    }
    // Resolve on the filesystem, not lexically: symlink/.. traversal matters.
    // Synchronous creation/resolution/reservation leaves no isolate-local gap.
    requested.createSync(recursive: true);
    final directory = requested.resolveSymbolicLinksSync();
    final identity = _posix.metadata(directory).identity;
    if (!_reservations.add(identity)) {
      throw const CoreException(CoreErrorCode.dataDirectoryBusy);
    }
    int? fd;
    try {
      final path = p.join(directory, ownershipFileName);
      requireRegularOrAbsent(path);
      fd = _posix.open(path);
      if (fd < 0) throw const CoreException(CoreErrorCode.storageOpenFailed);
      if (!_posix.tryLock(fd)) {
        final error = _posix.error;
        final code = error == (Platform.isMacOS ? 35 : 11)
            ? CoreErrorCode.dataDirectoryBusy
            : CoreErrorCode.storageOpenFailed;
        // Closing a failed independent open cannot release the owner's flock.
        if (_posix.close(fd) != 0) {
          throw CoreException(code, cleanupUnconfirmed: true);
        }
        fd = null;
        throw CoreException(code);
      }
      return DirectoryOwnership._(directory, identity, fd);
    } catch (error) {
      if (error is CoreException && error.cleanupUnconfirmed) rethrow;
      if (fd != null && fd >= 0 && _posix.close(fd) != 0) {
        throw CoreException(
          error is CoreException ? error.code : CoreErrorCode.storageOpenFailed,
          cleanupUnconfirmed: true,
        );
      }
      _reservations.remove(identity);
      rethrow;
    }
  }

  void release() {
    if (_released) return;
    // close, rather than LOCK_UN followed by close, keeps the lock until actual
    // descriptor release. A failed close has ambiguous ownership: quarantine it.
    if (_posix.close(_fd) != 0) {
      throw const CoreException(
        CoreErrorCode.storageWriteFailed,
        cleanupUnconfirmed: true,
      );
    }
    _released = true;
    _reservations.remove(_identity);
  }
}

void requireRegularOrAbsent(String path) {
  final type = FileSystemEntity.typeSync(path, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file) {
    throw const CoreException(CoreErrorCode.storageOpenFailed);
  }
  if (type == FileSystemEntityType.file && _posix.metadata(path).links != 1) {
    throw const CoreException(CoreErrorCode.storageOpenFailed);
  }
}

final _posix = _Posix();

final class _Posix {
  final _lib = DynamicLibrary.process();
  late final _open = _lib
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Int32,)>),
        int Function(Pointer<Utf8>, int, int)
      >('open');
  late final _flock = _lib
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'flock',
      );
  late final close = _lib
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  late final _errno = _lib
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        Platform.isMacOS ? '__error' : '__errno_location',
      );
  int get error => _errno().value;

  late final _stat = _lib
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Uint8>),
        int Function(Pointer<Utf8>, Pointer<Uint8>)
      >(Platform.isMacOS ? 'stat64' : 'stat');

  ({String identity, int links}) metadata(String path) {
    final native = path.toNativeUtf8();
    // Aligned storage larger than struct stat on each supported 64-bit ABI.
    // Only the verified prefix is read: Darwin stat64, Linux x86_64 stat,
    // and Linux aarch64 asm-generic stat. No inferred 32-bit ABI support.
    final buffer = calloc<Uint64>(64);
    try {
      if (_stat(native, buffer.cast()) != 0) {
        throw const CoreException(CoreErrorCode.storageOpenFailed);
      }
      final bytes = buffer.cast<Uint8>();
      final device = Platform.isMacOS
          ? buffer.cast<Uint32>().value
          : buffer.value;
      final inode = (bytes + 8).cast<Uint64>().value;
      final links = Platform.isMacOS
          ? (bytes + 6).cast<Uint16>().value
          : Abi.current() == Abi.linuxArm64
          ? (bytes + 20).cast<Uint32>().value
          : (bytes + 16).cast<Uint64>().value;
      return (identity: '$device:$inode', links: links);
    } finally {
      calloc.free(native);
      calloc.free(buffer);
    }
  }

  int open(String path) {
    final native = path.toNativeUtf8();
    try {
      // O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, mode 0600. Only these two
      // verified POSIX ABIs are supported; never guess flags on other systems.
      final flags = Platform.isMacOS
          ? 2 | 0x200 | 0x1000000 | 0x100
          : 2 | 0x40 | 0x80000 | 0x20000;
      return _open(native, flags, 0x180);
    } finally {
      calloc.free(native);
    }
  }

  bool tryLock(int fd) => _flock(fd, 2 | 4) == 0; // LOCK_EX | LOCK_NB
}
