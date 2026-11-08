import 'package:meshctl/meshctl.dart';
import 'package:test/test.dart';

void main() {
  test('help and no arguments print usage to stdout and succeed', () {
    for (final arguments in <List<String>>[
      [],
      ['--help'],
      ['-h'],
      ['--help', '--version'],
    ]) {
      final output = StringBuffer();
      final error = StringBuffer();

      final code = runCli(arguments, output: output, error: error);

      expect(code, 0, reason: '$arguments');
      expect(output.toString(), contains('Usage: meshctl [options]'));
      expect(output.toString(), contains('--help'));
      expect(output.toString(), contains('--version'));
      expect(error.toString(), isEmpty);
    }
  });

  test('version prints the tool name and application version and succeeds', () {
    final output = StringBuffer();
    final error = StringBuffer();

    final code = runCli(['--version'], output: output, error: error);

    expect(code, 0);
    expect(output.toString().trim(), 'meshctl 0.1.0-dev.1');
    expect(error.toString(), isEmpty);
  });

  test('unknown options print an error to stderr and return usage error', () {
    for (final arguments in <List<String>>[
      ['--unknown'],
      ['-x'],
      ['--help', '--unknown'],
    ]) {
      final output = StringBuffer();
      final error = StringBuffer();

      final code = runCli(arguments, output: output, error: error);

      expect(code, 64, reason: '$arguments');
      expect(output.toString(), isEmpty);
      expect(error.toString(), contains('Error:'));
      expect(error.toString(), contains('meshctl --help'));
      expect(error.toString(), isNot(contains('#0')));
    }
  });

  test(
    'positional arguments print an error to stderr and return usage error',
    () {
      for (final arguments in <List<String>>[
        ['ports'],
        ['--version', 'info'],
        ['--', 'watch'],
      ]) {
        final output = StringBuffer();
        final error = StringBuffer();

        final code = runCli(arguments, output: output, error: error);

        expect(code, 64, reason: '$arguments');
        expect(output.toString(), isEmpty);
        expect(error.toString(), contains('Positional arguments'));
        expect(error.toString(), contains(arguments.last));
        expect(error.toString(), contains('meshctl --help'));
        expect(error.toString(), isNot(contains('#0')));
      }
    },
  );
}
