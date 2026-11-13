/// Explicit developer mode for the same macOS application, including release.
/// Parsing is pure: reject malformed input before any filesystem/native work.
final class ProbeRequest {
  const ProbeRequest(
    this.mode,
    this.directory, {
    this.enumerate = false,
    this.exitWhenDone = false,
  });

  final String mode;
  final String directory;
  final bool enumerate;
  final bool exitWhenDone;

  static ProbeRequest? parse(List<String> arguments) {
    final options = <String>[];
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      // Xcode launches and XCTest hosts supply Cocoa boolean option/value pairs.
      // Keep this list narrow so malformed probe input is never discarded.
      if (const {
        '-NSDocumentRevisionsDebugMode',
        '-NSTreatUnknownArgumentsAsOpen',
        '-ApplePersistenceIgnoreState',
      }.contains(argument)) {
        if (index + 1 >= arguments.length ||
            !const {'YES', 'NO'}.contains(arguments[index + 1])) {
          throw const FormatException('Invalid Cocoa launch option.');
        }
        index++;
      } else {
        options.add(argument);
      }
    }
    if (options.isEmpty) return null;
    final values = <String, String>{};
    var enumerate = false;
    var exitWhenDone = false;
    for (final argument in options) {
      if (argument == '--enumerate-serial' && !enumerate) {
        enumerate = true;
      } else if (argument == '--probe-exit' && !exitWhenDone) {
        exitWhenDone = true;
      } else {
        final separator = argument.indexOf('=');
        if (separator < 0) {
          throw const FormatException('Unknown launch option.');
        }
        final key = argument.substring(0, separator);
        if (!const {'--meshchan-probe', '--fixture'}.contains(key) ||
            values.containsKey(key)) {
          throw const FormatException('Unknown or duplicate launch option.');
        }
        values[key] = argument.substring(separator + 1);
      }
    }
    final mode = values['--meshchan-probe'];
    final directory = values['--fixture'];
    if (!const {'write', 'read'}.contains(mode) ||
        directory == null ||
        !RegExp(r'^/([^/\x00]+/)*meshchan-1d2-[A-Za-z0-9_-]+$')
            .hasMatch(directory) ||
        directory.split('/').any((part) => part == '.' || part == '..')) {
      throw const FormatException(
        'Expected write/read and an absolute, dedicated meshchan-1d2-* fixture path.',
      );
    }
    return ProbeRequest(
      mode!,
      directory,
      enumerate: enumerate,
      exitWhenDone: exitWhenDone,
    );
  }
}
