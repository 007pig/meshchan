import 'dart:collection';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:test/test.dart';

void main() {
  test('the public sealed family dispatches to the matching kind', () {
    final targets = <ConnectionTarget>[
      UsbSerialTarget(portPath: 'COM3'),
      TcpTarget(host: 'localhost', port: 1),
      BleTarget(selectionId: 'host selection'),
    ];

    expect(targets.map((target) => target.kind), CompanionTransportKind.values);
    expect(
      targets.map(
        (target) => switch (target) {
          UsbSerialTarget(:final portPath) => portPath,
          TcpTarget(:final host, :final port) => '$host:$port',
          BleTarget(:final selectionId) => selectionId,
        },
      ),
      ['COM3', 'localhost:1', 'host selection'],
    );
  });

  group('USB path', () {
    test('preserves explicit paths without resolving or opening them', () {
      for (final path in [
        '/dev/cu.meshchan-step5-nonexistent',
        '/dev/ttyUSB0',
        'COM3',
        '  ~/Serial Ports/Companion  ',
        r'$HOME/Serial/Companion',
      ]) {
        expect(UsbSerialTarget(portPath: path).portPath, path);
      }
    });

    test('rejects blank paths and NUL', () {
      for (final path in ['', ' \t\n', '\u00a0', 'port\u0000path']) {
        expect(() => UsbSerialTarget(portPath: path), throwsArgumentError);
      }
    });
  });

  group('TCP endpoint', () {
    final longestDnsName = List.filled(
      3,
      'a' * 63,
    ).followedBy(['b' * 61]).join('.');

    test('preserves valid DNS names and bare IP literals verbatim', () {
      for (final host in [
        'localhost',
        '123',
        '123.',
        'Companion.local',
        'example.test.',
        'xn--bcher-kva.test',
        longestDnsName,
        '$longestDnsName.',
        '192.0.2.10',
        '::1',
        '2001:db8::1',
        '2001:db8::1:5050',
        '2001:0DB8:0000:0000:0000:0000:0000:0001',
        '1:2:3:4:5:6:7::',
        '1:2:3:4:5:6:7:8',
        '::ffff:192.0.2.10',
      ]) {
        final target = TcpTarget(host: host, port: 42);
        expect(target.host, host);
        expect(target.port, 42);
      }
    });

    test('rejects malformed hosts', () {
      for (final host in [
        '',
        '.',
        ' companion.local',
        'companion.local ',
        'com panion.local',
        'companion.local\n',
        'companion.local\u00a0',
        'companion\u0000.local',
        'companion\u007f.local',
        'tcp://companion.local:5050',
        'companion.local:5050',
        'user@companion.local',
        'companion.local/path',
        'companion.local?query',
        'companion.local#fragment',
        '[::1]',
        '::1\u0000',
        '::1\n',
        'fe80::1%en0',
        'fe80::1%25en0',
        '999.1.1.1',
        '192.0.2',
        '192.0.02.10',
        '192.0.2.10.',
        '2001:db8:::1',
        '2001:db8:1',
        '::ffff:999.1.1.1',
        '-companion.local',
        'companion-.local',
        'companion_host.local',
        'companion..local',
        'companion.local..',
        'bücher.test',
        'a' * 64,
        '${longestDnsName}b',
      ]) {
        expect(
          () => TcpTarget(host: host, port: 42),
          throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'host')),
          reason: 'Expected rejection for synthetic host ${host.codeUnits}',
        );
      }
    });

    test('requires a port in the inclusive range 1..65535', () {
      for (final port in [1, 65535]) {
        expect(TcpTarget(host: 'localhost', port: port).port, port);
      }
      for (final port in [0, -1, 65536]) {
        expect(
          () => TcpTarget(host: 'localhost', port: port),
          throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'port')),
        );
      }
    });
  });

  group('BLE selection', () {
    test('preserves opaque selections with no host mapping', () {
      for (final selection in ['Pick:Slot/A', 'MixedCase café #2']) {
        expect(BleTarget(selectionId: selection).selectionId, selection);
      }
    });

    test('rejects blank, padded, and control-containing selections', () {
      for (final selection in [
        '',
        '   ',
        '\u00a0',
        ' Pick',
        'Pick ',
        'Pick\u00a0',
        'Pi\u0000ck',
        'Pi\tck',
        'Pi\nck',
        'Pi\u007fck',
        'Pi\u0085ck',
      ]) {
        expect(() => BleTarget(selectionId: selection), throwsArgumentError);
      }
    });
  });

  test('same-type exact fields work as local Set and Map keys', () {
    final expected = <ConnectionTarget>[
      UsbSerialTarget(portPath: 'Companion'),
      TcpTarget(host: 'Companion', port: 42),
      BleTarget(selectionId: 'Companion'),
    ];
    final duplicates = <ConnectionTarget>[
      UsbSerialTarget(portPath: 'Companion'),
      TcpTarget(host: 'Companion', port: 42),
      BleTarget(selectionId: 'Companion'),
    ];
    final keys = HashSet<ConnectionTarget>.of([...expected, ...duplicates]);
    final byTarget = {for (final target in expected) target: target.kind};

    expect(duplicates, expected);
    expect(keys, hasLength(3));
    for (final target in duplicates) {
      expect(byTarget[target], target.kind);
    }
    for (final distinct in [
      UsbSerialTarget(portPath: ' Companion'),
      UsbSerialTarget(portPath: 'companion'),
      TcpTarget(host: 'companion', port: 42),
      TcpTarget(host: 'Companion.', port: 42),
      TcpTarget(host: 'Companion', port: 43),
      BleTarget(selectionId: 'companion'),
    ]) {
      expect(keys.contains(distinct), isFalse);
    }
    expect(
      TcpTarget(host: '::1', port: 42),
      isNot(TcpTarget(host: '0:0:0:0:0:0:0:1', port: 42)),
    );
  });

  test('summaries and interpolation expose only the transport kind', () {
    final targets = <ConnectionTarget>[
      UsbSerialTarget(portPath: '/dev/usb-private-path-7Kd'),
      TcpTarget(host: 'tcp-private-host-4Nj.test', port: 53179),
      BleTarget(selectionId: 'ble-private-selection-8Fr'),
    ];
    final safeLabels = ['usbSerial', 'tcp', 'ble'];
    expect(targets.map((target) => target.safeSummary), safeLabels);
    expect(targets.map((target) => '$target'), safeLabels);
  });

  test('argument errors carry only the field and a fixed reason', () {
    _expectSafeError(
      () => UsbSerialTarget(portPath: '/dev/usb-private-path-7Kd\u0000'),
      field: 'portPath',
      marker: 'usb-private-path-7Kd',
      reason: 'nonblank',
    );
    _expectSafeError(
      () => TcpTarget(host: 'user:private-password-5Hm@host.test', port: 42),
      field: 'host',
      marker: 'private-password-5Hm',
      reason: 'Specify the port separately',
    );
    _expectSafeError(
      () => TcpTarget(host: '192.0.2.901', port: 42),
      field: 'host',
      marker: '192.0.2.901',
      reason: 'IPv4 address',
    );
    _expectSafeError(
      () => TcpTarget(host: '1:2:3:4:5:6:7::8', port: 42),
      field: 'host',
      marker: '1:2:3:4:5:6:7::8',
      reason: 'Specify the port separately',
    );
    _expectSafeError(
      () => TcpTarget(host: 'tcp-private-host-4Nj.test', port: 876543),
      field: 'port',
      marker: '876543',
      reason: '1 and 65535',
    );
    _expectSafeError(
      () => BleTarget(selectionId: 'ble-private-selection-8Fr\n'),
      field: 'selectionId',
      marker: 'ble-private-selection-8Fr',
      reason: 'control characters',
    );
  });
}

void _expectSafeError(
  ConnectionTarget Function() construct, {
  required String field,
  required String marker,
  required String reason,
}) {
  expect(
    construct,
    throwsA(
      isA<ArgumentError>()
          .having((e) => e.name, 'name', field)
          .having((e) => e.invalidValue, 'invalidValue', isNull)
          .having(
            (e) => e.message,
            'message',
            allOf(contains(reason), isNot(contains(marker))),
          )
          .having((e) => '$e', 'toString', isNot(contains(marker))),
    ),
  );
}
