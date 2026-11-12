import 'package:args/args.dart';
import 'package:meshchan_core/meshchan_core.dart';

int decimalOption(
  ArgResults args,
  String name,
  int min,
  int max, {
  int? fallback,
}) {
  final text = args.option(name);
  if (text == null && fallback != null) return fallback;
  final value = text != null && RegExp(r'^[0-9]+$').hasMatch(text)
      ? int.tryParse(text)
      : null;
  if (value == null || value < min || value > max) {
    throw FormatException('--$name must be a decimal integer in $min..$max.');
  }
  return value;
}

LocalId idOption(ArgResults args, [String name = 'id']) {
  final text = args.option(name);
  if (text == null) throw FormatException('--$name is required.');
  return LocalId(text);
}

/// Restrict precision and compare every calendar component after construction;
/// DateTime.parse alone normalizes invalid dates.
DateTime utcInput(String text) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?Z$',
  ).firstMatch(text);
  if (match == null) {
    throw const FormatException(
      'Time must be UTC YYYY-MM-DDTHH:mm:ss[.ffffff]Z.',
    );
  }
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match[i]!)];
  final micros = int.parse((match[7] ?? '').padRight(6, '0'));
  final date = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
    micros ~/ 1000,
    micros % 1000,
  );
  if (date.year != parts[0] ||
      date.month != parts[1] ||
      date.day != parts[2] ||
      date.hour != parts[3] ||
      date.minute != parts[4] ||
      date.second != parts[5]) {
    throw const FormatException('Time must name a valid UTC calendar instant.');
  }
  return date;
}

String utcOutput(DateTime time) {
  final utc = time.toUtc();
  final iso = utc.toIso8601String();
  return utc.microsecond == 0 ? '${iso.substring(0, iso.length - 1)}000Z' : iso;
}

UpdatedCursor? updatedCursor(ArgResults args) {
  if (args.wasParsed('after-updated-at') != args.wasParsed('after-id')) {
    throw const FormatException(
      'Provide both --after-updated-at and --after-id.',
    );
  }
  return !args.wasParsed('after-id')
      ? null
      : UpdatedCursor(
          updatedAt: utcInput(args.option('after-updated-at')!),
          id: idOption(args, 'after-id'),
        );
}

HistoryCursor? historyCursor(ArgResults args) {
  if (args.wasParsed('after-prepared-at') != args.wasParsed('after-run-id')) {
    throw const FormatException(
      'Provide both --after-prepared-at and --after-run-id.',
    );
  }
  return !args.wasParsed('after-run-id')
      ? null
      : HistoryCursor(
          preparedAt: utcInput(args.option('after-prepared-at')!),
          runId: idOption(args, 'after-run-id'),
        );
}

Map<String, Object?>? updatedCursorFields(UpdatedCursor? c) =>
    c == null ? null : {'updatedAt': utcOutput(c.updatedAt), 'id': c.id.value};
Map<String, Object?>? historyCursorFields(HistoryCursor? c) => c == null
    ? null
    : {'preparedAt': utcOutput(c.preparedAt), 'runId': c.runId.value};
