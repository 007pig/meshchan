import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshctl/meshctl.dart';
import 'package:meshctl/src/process_io.dart';
import 'package:test/test.dart';

void main() {
  test('help and no arguments print usage to stdout and succeed', () async {
    for (final arguments in <List<String>>[
      [],
      ['--help'],
      ['-h'],
      ['--help', '--version'],
      ['--version', '--help'],
      ['ports', '--help'],
      ['ports', '-h'],
      ['port-check', '--help'],
      ['port-check', '-h'],
      ['--help', 'port-check'],
    ]) {
      final output = StringBuffer();
      final error = StringBuffer();

      final ports = FakeSerialPorts();
      final code = await runCli(
        arguments,
        output: output,
        error: error,
        serialPorts: ports,
      );

      expect(code, 0, reason: '$arguments');
      expect(output.toString(), contains('Usage: meshctl'));
      expect(output.toString(), contains('--help'));
      if (arguments.isEmpty || !arguments.first.startsWith('port')) {
        expect(output.toString(), contains('--version'));
      }
      expect(error.toString(), isEmpty);
      expect(ports.listCalls, 0);
      expect(ports.checkedPaths, isEmpty);
    }
  });

  test(
    'version prints the tool name and application version and succeeds',
    () async {
      final output = StringBuffer();
      final error = StringBuffer();

      final ports = FakeSerialPorts();
      final code = await runCli(
        ['--version'],
        output: output,
        error: error,
        serialPorts: ports,
      );

      expect(code, 0);
      expect(output.toString().trim(), 'meshctl 0.1.0-dev.1');
      expect(error.toString(), isEmpty);
      expect(ports.listCalls, 0);
      expect(ports.checkedPaths, isEmpty);
    },
  );

  test(
    'unknown options print an error to stderr and return usage error',
    () async {
      for (final arguments in <List<String>>[
        ['--unknown'],
        ['-x'],
        ['--help', '--unknown'],
        ['ports', '--unknown'],
        ['port-check', '--port', '/dev/example', '--unknown'],
      ]) {
        final output = StringBuffer();
        final error = StringBuffer();

        final ports = FakeSerialPorts();
        final code = await runCli(
          arguments,
          output: output,
          error: error,
          serialPorts: ports,
        );

        expect(code, 64, reason: '$arguments');
        expect(output.toString(), isEmpty);
        expect(error.toString(), contains('Error:'));
        expect(error.toString(), contains('meshctl --help'));
        expect(error.toString(), isNot(contains('#0')));
        expect(ports.listCalls, 0);
        expect(ports.checkedPaths, isEmpty);
      }
    },
  );

  test(
    'positional arguments print an error to stderr and return usage error',
    () async {
      for (final arguments in <List<String>>[
        ['unknown-command'],
        ['--version', 'unknown-command'],
        ['--', 'watch'],
        ['ports', 'extra'],
        ['port-check', '--port', '/dev/example', 'extra'],
      ]) {
        final output = StringBuffer();
        final error = StringBuffer();

        final ports = FakeSerialPorts();
        final code = await runCli(
          arguments,
          output: output,
          error: error,
          serialPorts: ports,
        );

        expect(code, 64, reason: '$arguments');
        expect(output.toString(), isEmpty);
        expect(error.toString(), contains('positional arguments'));
        expect(error.toString(), contains(arguments.last));
        expect(error.toString(), contains('meshctl --help'));
        expect(error.toString(), isNot(contains('#0')));
        expect(ports.listCalls, 0);
        expect(ports.checkedPaths, isEmpty);
      }
    },
  );

  test(
    'missing and blank port values are usage errors without operations',
    () async {
      for (final arguments in <List<String>>[
        ['port-check'],
        ['port-check', '--port'],
        ['port-check', '--port='],
        ['port-check', '--port', '   '],
      ]) {
        final output = StringBuffer();
        final error = StringBuffer();
        final ports = FakeSerialPorts();
        final code = await runCli(
          arguments,
          output: output,
          error: error,
          serialPorts: ports,
        );
        expect(code, 64, reason: '$arguments');
        expect(output.toString(), isEmpty);
        expect(error.toString(), contains('Error:'));
        expect(error.toString(), isNot(contains('#0')));
        expect(ports.listCalls, 0);
        expect(ports.checkedPaths, isEmpty);
      }
    },
  );

  test(
    'ports sorts paths, shows limited metadata, and retains warnings',
    () async {
      final ports = FakeSerialPorts()
        ..descriptions = [
          const SerialPortDescription(
            path: '/dev/z',
            warning: 'Device disappeared',
          ),
          const SerialPortDescription(
            path: '/dev/b',
            description: 'USB adapter',
            transport: 'USB',
            usbVid: 0x1a86,
            usbPid: 0x55d4,
          ),
          const SerialPortDescription(path: '/dev/a'),
        ];
      final output = StringBuffer();
      final error = StringBuffer();
      final code = await runCli(
        ['ports'],
        output: output,
        error: error,
        serialPorts: ports,
      );
      final text = output.toString();
      expect(code, 0);
      expect(text.indexOf('/dev/a'), lessThan(text.indexOf('/dev/b')));
      expect(text.indexOf('/dev/b'), lessThan(text.indexOf('/dev/z')));
      expect(text, contains('Description: -'));
      expect(text, contains('Transport: -'));
      expect(text, contains('Description: USB adapter'));
      expect(text, contains('Transport: USB'));
      expect(text, contains('USB VID/PID: 1A86/55D4'));
      expect(text, contains('USB VID/PID: -/-'));
      expect(error.toString(), contains('Warning: /dev/z: Device disappeared'));
      expect(ports.listCalls, 1);
      expect(ports.checkedPaths, isEmpty);
    },
  );

  test(
    'empty enumeration succeeds; enumeration failure is not an empty list',
    () async {
      for (final failure in [
        null,
        const SerialPortFailure('Enumeration failed'),
      ]) {
        final ports = FakeSerialPorts()..failure = failure;
        final output = StringBuffer();
        final error = StringBuffer();
        final code = await runCli(
          ['ports'],
          output: output,
          error: error,
          serialPorts: ports,
        );
        expect(code, failure == null ? 0 : 69);
        expect(
          output.toString(),
          failure == null ? 'No serial ports found.\n' : isEmpty,
        );
        expect(
          error.toString(),
          failure == null ? isEmpty : contains('Enumeration failed'),
        );
        expect(error.toString(), isNot(contains('#0')));
        expect(ports.listCalls, 1);
        expect(ports.checkedPaths, isEmpty);
      }
    },
  );

  test(
    'port-check checks only the exact path and reports protocol boundary',
    () async {
      final ports = FakeSerialPorts();
      final output = StringBuffer();
      final error = StringBuffer();
      const path = '/dev/cu.explicit-port';
      final code = await runCli(
        ['port-check', '--port', path],
        output: output,
        error: error,
        serialPorts: ports,
      );
      expect(code, 0);
      expect(ports.listCalls, 0);
      expect(ports.checkedPaths, [path]);
      expect(
        output.toString(),
        contains('opened and closed successfully: $path'),
      );
      expect(
        output.toString(),
        contains('MeshCore protocol support has not been checked.'),
      );
      expect(output.toString(), isNot(contains('MeshCore connected')));
      expect(error.toString(), isEmpty);
    },
  );

  test(
    'port-check failure returns unavailable without success or stack',
    () async {
      final ports = FakeSerialPorts()
        ..failure = const SerialPortFailure('Permission denied (code: 13)');
      final output = StringBuffer();
      final error = StringBuffer();
      final code = await runCli(
        ['port-check', '--port', '/dev/example'],
        output: output,
        error: error,
        serialPorts: ports,
      );
      expect(code, 69);
      expect(output.toString(), isEmpty);
      expect(error.toString(), contains('Permission denied (code: 13)'));
      expect(error.toString(), isNot(contains('#0')));
      expect(ports.listCalls, 0);
      expect(ports.checkedPaths, ['/dev/example']);
    },
  );

  test('unexpected programming errors propagate', () async {
    final ports = FakeSerialPorts()..failure = StateError('Bug');
    await expectLater(
      runCli(
        ['ports'],
        output: StringBuffer(),
        error: StringBuffer(),
        serialPorts: ports,
      ),
      throwsStateError,
    );
    final error = StringBuffer();
    expect(
      await runProcessCli(
        ['ports'],
        output: StringBuffer(),
        error: error,
        serialPorts: ports,
      ),
      70,
    );
    expect(error.toString(), 'Error: Unexpected internal CLI failure.\n');
    expect(error.toString(), isNot(contains('Bug')));
  });
}

class FakeSerialPorts implements SerialPorts {
  List<SerialPortDescription> descriptions = [];
  Object? failure;
  int listCalls = 0;
  final checkedPaths = <String>[];

  @override
  List<SerialPortDescription> listPorts() {
    listCalls++;
    if (failure != null) throw failure!;
    return descriptions;
  }

  @override
  void checkPort(String path) {
    checkedPaths.add(path);
    if (failure != null) throw failure!;
  }
}
