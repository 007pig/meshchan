import 'probe_request.dart';

enum LaunchMode { normal, probe, runtimeVerification, nativeTest }

/// Pure validation must precede directory facts, spawn and native calls.
final class LaunchConfiguration {
  const LaunchConfiguration._(
    this.mode, {
    this.directory,
    this.probe,
    this.verification,
    this.exitWhenDone = false,
  });
  final LaunchMode mode;
  final String? directory, verification;
  final ProbeRequest? probe;
  final bool exitWhenDone;
  static LaunchConfiguration parse(
    List<String> arguments, {
    bool nativeTestHost = false,
  }) {
    final args = <String>[];
    final cocoa = <String>{};
    for (var i = 0; i < arguments.length; i++) {
      final a = arguments[i];
      if (const {
        '-NSDocumentRevisionsDebugMode',
        '-NSTreatUnknownArgumentsAsOpen',
        '-ApplePersistenceIgnoreState',
      }.contains(a)) {
        if (!cocoa.add(a) ||
            i + 1 >= arguments.length ||
            !const {'YES', 'NO'}.contains(arguments[++i])) {
          throw const FormatException(
            'Invalid or duplicate Cocoa launch option.',
          );
        }
      } else {
        args.add(a);
      }
    }
    if (nativeTestHost) {
      if (args.length != 1 || args.single != '--meshchan-native-test') {
        throw const FormatException(
          'Native test configuration is missing or invalid.',
        );
      }
      return const LaunchConfiguration._(LaunchMode.nativeTest);
    }
    if (args.contains('--meshchan-native-test')) {
      throw const FormatException(
        'Native test mode requires a native test host.',
      );
    }
    if (args.any((a) => a.startsWith('--meshchan-probe='))) {
      final probe = ProbeRequest.parse(args)!;
      return LaunchConfiguration._(LaunchMode.probe, probe: probe);
    }
    String? directory, verification;
    var exitWhenDone = false;
    for (final a in args) {
      if (a.startsWith('--data-dir=') && directory == null) {
        directory = a.substring('--data-dir='.length);
        validateDirectory(directory);
      } else if (a.startsWith('--meshchan-runtime=') && verification == null) {
        verification = a.substring('--meshchan-runtime='.length);
        if (!const {
          'write',
          'read',
          'hold',
          'quit-starting',
          'quit-ready',
          'hold-startup',
        }.contains(verification)) {
          throw const FormatException('Invalid runtime verification mode.');
        }
      } else if (a == '--runtime-exit' && !exitWhenDone) {
        exitWhenDone = true;
      } else {
        throw const FormatException('Unknown or duplicate launch option.');
      }
    }
    if (verification != null) {
      if (directory == null ||
          !RegExp(r'/meshchan-1d3-[A-Za-z0-9_-]+$').hasMatch(directory) ||
          (const {
                'hold',
                'quit-starting',
                'quit-ready',
                'hold-startup',
              }.contains(verification) &&
              exitWhenDone)) {
        throw const FormatException(
          'Runtime verification requires a dedicated meshchan-1d3-* directory.',
        );
      }
      return LaunchConfiguration._(
        LaunchMode.runtimeVerification,
        directory: directory,
        verification: verification,
        exitWhenDone: exitWhenDone,
      );
    }
    if (exitWhenDone) {
      throw const FormatException('Runtime exit requires verification mode.');
    }
    return LaunchConfiguration._(LaunchMode.normal, directory: directory);
  }

  static void validateDirectory(String path) {
    if (!path.startsWith('/') ||
        path.trim().isEmpty ||
        path.contains('\u0000') ||
        path.split('/').any((p) => p == '.' || p == '..')) {
      throw const FormatException(
        'Data directory must be an absolute path without NUL or dot segments.',
      );
    }
  }
}
