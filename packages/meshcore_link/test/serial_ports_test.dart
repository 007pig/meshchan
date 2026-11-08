import 'dart:convert';

import 'package:libserialport_plus/libserialport_plus.dart' as native;
import 'package:meshcore_link/src/serial_ports.dart';
import 'package:test/test.dart';

void main() {
  test('unsafe platform guards run before native enumeration or creation', () {
    for (final (platform, enumerating, blocked) in [
      ('linux', true, true),
      ('android', true, true),
      ('windows', true, true),
      ('windows', false, true),
      ('linux', false, false),
      ('macos', true, false),
      ('macos', false, false),
    ]) {
      var calls = 0;
      String run() => nativeSerialOperation(
        () {
          calls++;
          return 'native callback result';
        },
        enumerating: enumerating,
        operatingSystem: platform,
      );
      if (blocked) {
        expect(
          run,
          throwsA(
            isA<SerialPortFailure>().having(
              (failure) => failure.message,
              'platform diagnostic',
              contains('unavailable'),
            ),
          ),
        );
        expect(calls, 0, reason: '$platform, enumerating=$enumerating');
      } else {
        expect(run(), 'native callback result');
        expect(calls, 1);
      }
    }
  });

  test('invalid UTF-8 metadata retains the path and releases every handle', () {
    final handles = <String, FakeHandle>{};
    final ports = SerialPorts(
      listPaths: () => ['/dev/z', '/dev/a'],
      createHandle: (path) => handles[path] = FakeHandle(
        getInfo: path == '/dev/a'
            ? () {
                utf8.decode([0xc3]);
                throw StateError('Expected malformed UTF-8 to fail');
              }
            : null,
      ),
    );
    final results = ports.listPorts();
    expect(results.map((port) => port.path), ['/dev/a', '/dev/z']);
    expect(results.first.warning, contains('metadata as UTF-8'));
    expect(results.first.description, isNull);
    expect(results.last.warning, isNull);
    for (final handle in handles.values) {
      expect(handle.calls, ['describe', 'dispose']);
    }
  });

  test('metadata recovery preserves errors outside the decoding boundary', () {
    expect(
      () => readSerialPortDescription(
        '/dev/a',
        () => throw StateError('Programming error'),
      ),
      throwsStateError,
    );
    expect(
      () => nativeSerialOperation(
        () => throw const FormatException('Outside metadata decoding'),
        operatingSystem: 'macos',
      ),
      throwsFormatException,
    );
  });

  test(
    'enumeration never opens ports and retains paths on metadata failures',
    () {
      final handles = <String, FakeHandle>{};
      final ports = SerialPorts(
        listPaths: () => ['/dev/z', '/dev/a'],
        createHandle: (path) => handles[path] = FakeHandle(
          failAt: path == '/dev/a' ? 'describe' : null,
        ),
      );
      final results = ports.listPorts();
      expect(results.map((port) => port.path), ['/dev/a', '/dev/z']);
      expect(results.first.warning, contains('describe failed'));
      expect(results.last.warning, isNull);
      for (final handle in handles.values) {
        expect(handle.calls, ['describe', 'dispose']);
      }
    },
  );

  test('check opens once, verifies both states, closes, and disposes', () {
    final handle = FakeHandle();
    final paths = <String>[];
    final ports = SerialPorts(
      listPaths: () => throw StateError('Must not enumerate'),
      createHandle: (path) {
        paths.add(path);
        return handle;
      },
    );
    ports.checkPort('/dev/selected');
    expect(paths, ['/dev/selected']);
    expect(handle.calls, ['open', 'isOpen', 'close', 'isOpen', 'dispose']);
    expect(handle.opened, isFalse);
  });

  test(
    'check failures still release resources and preserve the primary error',
    () {
      for (final stage in ['open', 'isOpen', 'close', 'dispose']) {
        final handle = FakeHandle(failAt: stage, failDispose: true);
        final ports = SerialPorts(createHandle: (_) => handle);
        expect(
          () => ports.checkPort('/dev/selected'),
          throwsA(
            isA<SerialPortFailure>().having(
              (failure) => failure.message,
              'primary failure',
              startsWith('$stage failed'),
            ),
          ),
          reason: stage,
        );
        expect(handle.calls.last, 'dispose');
        expect(handle.calls.where((call) => call == 'open'), hasLength(1));
        if (stage == 'open') {
          expect(handle.calls, ['open', 'dispose']);
        } else {
          expect(handle.calls.where((call) => call == 'close'), hasLength(1));
        }
      }
    },
  );

  test('unexpected open and closed states cannot report success', () {
    for (final state in [false, true]) {
      final handle = FakeHandle(reportedState: state);
      expect(
        () =>
            SerialPorts(createHandle: (_) => handle).checkPort('/dev/selected'),
        throwsA(isA<SerialPortFailure>()),
      );
      expect(handle.calls.last, 'dispose');
      expect(handle.calls.where((call) => call == 'close'), hasLength(1));
      expect(handle.opened, isFalse);
    }
  });

  test(
    'native open recovery closes partial acquisitions and keeps the error',
    () {
      final successCalls = <String>[];
      openNativePort(
        () => successCalls.add('open'),
        () => successCalls.add('close'),
      );
      expect(successCalls, ['open']);

      for (final failClose in [false, true]) {
        var acquired = false;
        final calls = <String>[];
        expect(
          () => openNativePort(
            () {
              calls.add('open');
              acquired = true;
              throw native.SerialPortException(11, 'Lock failed');
            },
            () {
              calls.add('close');
              if (failClose) {
                throw native.SerialPortException(5, 'Close failed');
              }
              acquired = false;
            },
          ),
          throwsA(
            isA<SerialPortFailure>()
                .having(
                  (failure) => failure.message,
                  'primary error',
                  startsWith('SerialPortException: Lock failed (code: 11)'),
                )
                .having(
                  (failure) => failure.message.contains('cleanup failed:'),
                  'cleanup diagnostic',
                  failClose,
                ),
          ),
        );
        expect(calls, ['open', 'close']);
        expect(acquired, failClose);
      }
    },
  );

  test(
    'failed native open tolerates an already closed port during cleanup',
    () {
      final calls = <String>[];
      expect(
        () => openNativePort(
          () {
            calls.add('open');
            throw native.SerialPortException(13, 'Permission denied');
          },
          () {
            calls.add('close');
            throw native.SerialPortException(-1, 'Argument error');
          },
        ),
        throwsA(
          isA<SerialPortFailure>().having(
            (failure) => failure.message,
            'original error without a spurious cleanup failure',
            'SerialPortException: Permission denied (code: 13)',
          ),
        ),
      );
      expect(calls, ['open', 'close']);
    },
  );

  test(
    'display metadata removes full and truncated Linux USB serial suffixes',
    () {
      for (final (description, serial, expected) in [
        ('USB adapter - SAMPLE123456', 'SAMPLE123456', 'USB adapter'),
        ('USB adapter - SAMPLE123', 'SAMPLE123456', 'USB adapter'),
        ('USB - adapter - SAMPLE - 123', 'SAMPLE - 123456', 'USB - adapter'),
        ('USB adapter', 'SAMPLE123456', 'USB adapter'),
        ('SAMPLE123456', 'SAMPLE123456', null),
        ('USB adapter', null, 'USB adapter'),
      ]) {
        final result = serialPortDescription(
          '/dev/ttyUSB0',
          native.SerialPortInfo(
            name: '/dev/ttyUSB0',
            description: description,
            transport: native.SerialPortTransport.usb,
            usbBus: null,
            usbAddress: null,
            usbVid: 0x303a,
            usbPid: 0x1001,
            usbManufacturer: null,
            usbProduct: null,
            usbSerialNumber: serial,
            bluetoothAddress: null,
          ),
        );
        expect(result.path, '/dev/ttyUSB0');
        expect(result.description, expected);
        expect(result.transport, 'USB');
        expect(result.usbVid, 0x303a);
        expect(result.usbPid, 0x1001);
      }
    },
  );
}

class FakeHandle implements SerialPortHandle {
  FakeHandle({
    this.failAt,
    this.failDispose = false,
    this.reportedState,
    this.getInfo,
  });

  final String? failAt;
  final bool failDispose;
  final bool? reportedState;
  final native.SerialPortInfo Function()? getInfo;
  final calls = <String>[];
  bool opened = false;

  void record(String operation) {
    if (calls.contains('dispose')) throw StateError('Used a disposed handle');
    calls.add(operation);
    if (operation == failAt || (operation == 'dispose' && failDispose)) {
      throw SerialPortFailure('$operation failed');
    }
  }

  @override
  SerialPortDescription getDescription(String path) {
    record('describe');
    if (getInfo != null) return readSerialPortDescription(path, getInfo!);
    return SerialPortDescription(path: path);
  }

  @override
  void open() {
    record('open');
    opened = true;
  }

  @override
  bool isOpen() {
    record('isOpen');
    return reportedState ?? opened;
  }

  @override
  void close() {
    record('close');
    opened = false;
  }

  @override
  void dispose() => record('dispose');
}
