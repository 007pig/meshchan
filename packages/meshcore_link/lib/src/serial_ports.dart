import 'dart:io';

import 'package:libserialport_plus/libserialport_plus.dart' as native;

/// Limited display metadata. System paths are preserved verbatim; identifier
/// fields and native handles stay inside the adapter.
class SerialPortDescription {
  const SerialPortDescription({
    required this.path,
    this.description,
    this.transport,
    this.usbVid,
    this.usbPid,
    this.warning,
  });

  final String path;
  final String? description;
  final String? transport;
  final int? usbVid;
  final int? usbPid;
  final String? warning;
}

/// An expected serial, platform, or native runtime dependency failure.
class SerialPortFailure implements Exception {
  const SerialPortFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Internal evidence that native open and its one recovery close both failed.
final class NativeOpenCleanupFailure extends SerialPortFailure {
  NativeOpenCleanupFailure(this.openError, this.cleanupError)
    : super('$openError; cleanup failed: $cleanupError');

  final Object openError;
  final Object cleanupError;
}

/// Synchronous diagnostics. Constructing this service does not access hardware.
class SerialPorts {
  SerialPorts({
    List<String> Function()? listPaths,
    SerialPortHandle Function(String)? createHandle,
  }) : _listPaths = listPaths ?? _availablePaths,
       _createHandle = createHandle ?? _NativeSerialPortHandle.create;

  final List<String> Function() _listPaths;
  final SerialPortHandle Function(String) _createHandle;

  /// Enumerates metadata without opening any port or sending probe data.
  List<SerialPortDescription> listPorts() {
    final paths = [..._listPaths()]..sort();
    return [for (final path in paths) _describe(path)];
  }

  SerialPortDescription _describe(String path) {
    try {
      final port = _createHandle(path);
      return _withCleanup(() => port.getDescription(path), port.dispose);
    } on SerialPortFailure catch (failure) {
      return SerialPortDescription(path: path, warning: failure.message);
    }
  }

  /// Opens and closes only [path]. No protocol data is sent. Native open can
  /// apply terminal settings, and drivers may reset some boards.
  void checkPort(String path) {
    if (path.trim().isEmpty || path.contains('\u0000')) {
      throw const SerialPortFailure(
        'Port path must be nonblank and contain no NUL.',
      );
    }
    final port = _createHandle(path);
    var canDispose = true;
    _withCleanup(
      () {
        try {
          // Native open/close report their own failures. isOpen() in the
          // pinned wrapper misclassifies the valid POSIX descriptor 0.
          port.open();
          canDispose = false;
          port.close();
          canDispose = true;
        } on NativeOpenCleanupFailure catch (failure, stack) {
          canDispose = false;
          if (failure.openError is! SerialPortFailure) {
            Error.throwWithStackTrace(failure.openError, stack);
          }
          rethrow;
        }
      },
      () {
        if (canDispose) {
          port.dispose();
        } else {
          _unconfirmedPortHandles.add(port);
        }
      },
    );
  }
}

// Keep native handles alive following an unconfirmed close.
final _unconfirmedPortHandles = Set<SerialPortHandle>.identity();

/// Small internal adapter seam for hardware-free lifecycle tests.
abstract interface class SerialPortHandle {
  SerialPortDescription getDescription(String path);

  /// On failure, recover partial acquisition or throw [NativeOpenCleanupFailure].
  void open();
  void close();
  void dispose();
}

class _NativeSerialPortHandle implements SerialPortHandle {
  _NativeSerialPortHandle(this._port);

  static SerialPortHandle create(String path) => nativeSerialOperation(
    () => _NativeSerialPortHandle(native.SerialPort(path)),
  );

  final native.SerialPort _port;

  @override
  SerialPortDescription getDescription(String path) =>
      readSerialPortDescription(path, _port.getInfo);

  @override
  void open() => openNativePort(
    () => _port.open(native.SerialPortMode.readWrite),
    _port.close,
  );

  @override
  void close() => _nativeCall(_port.close);

  @override
  void dispose() => _nativeCall(_port.dispose);
}

/// Blocks known unsafe backends before enumeration or native handle creation.
/// Optional platform/callback injection keeps guard tests hardware-free.
T nativeSerialOperation<T>(
  T Function() action, {
  bool enumerating = false,
  String? operatingSystem,
}) {
  final platform = operatingSystem ?? Platform.operatingSystem;
  if (platform == 'windows') {
    // Windows metadata initialization also opens USB ports to wake devices.
    throw const SerialPortFailure(
      'Native serial diagnostics are unavailable on Windows with '
      'libserialport_plus 1.0.5: unsafe handle state checks and '
      'port-opening metadata lookup.',
    );
  }
  if (enumerating && (platform == 'linux' || platform == 'android')) {
    // Both targets compile linux.c, whose serial8250 enumeration opens ports.
    final name = platform == 'linux' ? 'Linux' : 'Android';
    throw SerialPortFailure(
      'Serial port enumeration is unavailable on $name with '
      'libserialport_plus 1.0.5: the native backend can open unselected ports.',
    );
  }
  if (!const {'macos', 'linux', 'android'}.contains(platform)) {
    throw SerialPortFailure(
      'No native serial backend is available on $platform.',
    );
  }
  return _nativeCall(action);
}

/// Only native metadata decoding failures become recoverable port warnings.
SerialPortDescription readSerialPortDescription(
  String path,
  native.SerialPortInfo Function() getInfo,
) {
  final native.SerialPortInfo info;
  try {
    info = _nativeCall(getInfo);
  } on FormatException catch (exception) {
    // Keep the reason, but not FormatException.source, which may identify a device.
    throw SerialPortFailure(
      'Could not decode serial port metadata as UTF-8: ${exception.message}',
    );
  }
  return serialPortDescription(path, info);
}

/// Internal adapter helper: sp_open() can acquire a descriptor before failing.
/// Recovery uses close(), not isOpen(), because the pinned wrapper misses fd 0.
void openNativePort(void Function() open, void Function() close) {
  try {
    _nativeCall(open);
  } catch (openError, stack) {
    try {
      _nativeCall(() {
        try {
          close();
        } on native.SerialPortException catch (exception) {
          // For a valid, undisposed port, sp_close() returns SP_ERR_ARG (-1)
          // only if it is already closed, including upstream failure cleanup.
          if (exception.code != -1) rethrow;
        }
      });
    } catch (cleanupError) {
      Error.throwWithStackTrace(
        NativeOpenCleanupFailure(openError, cleanupError),
        stack,
      );
    }
    rethrow;
  }
}

/// Projects upstream info into display data without exporting identifier fields.
SerialPortDescription serialPortDescription(
  String path,
  native.SerialPortInfo info,
) {
  final isUsb = info.transport == native.SerialPortTransport.usb;
  var description = info.description;
  final serial = info.usbSerialNumber;
  if (isUsb && serial != null && serial.isNotEmpty) {
    // Linux appends " - <serial>" into a fixed-size description buffer.
    // Remove even a truncated serial suffix before removing other occurrences.
    var separator = description.indexOf(' - ');
    while (separator >= 0) {
      final suffix = description.substring(separator + 3);
      if (suffix.isNotEmpty && serial.startsWith(suffix)) {
        description = description.substring(0, separator);
        break;
      }
      separator = description.indexOf(' - ', separator + 3);
    }
    description = description.replaceAll(serial, '').trim();
  }
  return SerialPortDescription(
    path: path,
    description: description.isEmpty ? null : description,
    transport: switch (info.transport) {
      native.SerialPortTransport.native => 'Native',
      native.SerialPortTransport.usb => 'USB',
      native.SerialPortTransport.bluetooth => 'Bluetooth',
    },
    usbVid: isUsb ? info.usbVid : null,
    usbPid: isUsb ? info.usbPid : null,
  );
}

List<String> _availablePaths() => nativeSerialOperation(
  native.SerialPort.getAvailablePorts,
  enumerating: true,
);

T _nativeCall<T>(T Function() action) {
  try {
    return action();
  } on native.SerialPortException catch (exception) {
    throw SerialPortFailure(exception.toString());
  } on UnsupportedError catch (exception) {
    throw SerialPortFailure(exception.toString());
  } on ArgumentError catch (exception) {
    // FFI asset resolution reports ArgumentError. Preserve other argument bugs.
    final message = exception.toString();
    if (message.contains('libserialport_plus') &&
        (message.contains("Couldn't resolve native function") ||
            message.contains('Failed to load dynamic library'))) {
      throw SerialPortFailure(message);
    }
    rethrow;
  }
}

T _withCleanup<T>(T Function() action, void Function() cleanup) {
  Object? primary;
  StackTrace? primaryStack;
  try {
    return action();
  } catch (exception, stack) {
    // Catch only to preserve the primary failure while cleanup still runs.
    primary = exception;
    primaryStack = stack;
    rethrow;
  } finally {
    try {
      cleanup();
    } catch (exception) {
      if (primary == null) rethrow;
      if (primary is SerialPortFailure) {
        Error.throwWithStackTrace(
          SerialPortFailure('${primary.message}; cleanup failed: $exception'),
          primaryStack!,
        );
      }
      // An unexpected primary error keeps its original type and stack.
    }
  }
}
