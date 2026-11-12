import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:meshchan_core/meshchan_core.dart';

import 'business_input.dart';
import 'business_projection.dart';
import 'business_storage.dart';
import 'cli_display.dart';
import 'cli_output.dart';
import 'datagram_options.dart';
import 'session_command.dart';

const offlineGroups = {'draft', 'profile', 'settings', 'history'};
ArgParser _leaf() => ArgParser()
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show command usage.')
  ..addFlag('json', negatable: false, help: 'Write one final JSON object.');
void _id(ArgParser p) => p.addOption(
  'id',
  help: 'Required local ID: 32 lowercase hexadecimal digits.',
);
void _revision(ArgParser p) => p.addOption(
  'expected-revision',
  help: 'Required positive expected revision (decimal).',
);
bool _requiresId(String group, String action) =>
    group != 'settings' &&
    (action == 'show' || action == 'update' || action == 'delete');
bool _requiresRevision(String group, String action) =>
    group == 'draft' && (action == 'update' || action == 'delete');
void _body(ArgParser p) => p
  ..addOption('title', help: 'Exact title; an explicit empty value clears it.')
  ..addOption('body', help: 'Exact body; conflicts with --body-file.')
  ..addOption(
    'body-file',
    help: 'Strict UTF-8 file; consumes one initial BOM and preserves all other text.',
  );
void _page(ArgParser p, {bool history = false}) {
  p.addOption('limit', help: 'Page size (decimal 1..200); default: 50.');
  p.addOption(
    history ? 'after-prepared-at' : 'after-updated-at',
    help: 'UTC cursor time with Z and up to six fractional digits; requires the cursor ID.',
  );
  p.addOption(
    history ? 'after-run-id' : 'after-id',
    help: 'Cursor ID; requires the cursor time.',
  );
  if (history) {
    p
      ..addOption(
        'operation',
        allowed: ['send', 'listen', 'ping', 'respond'],
        help: 'Operation filter.',
      )
      ..addOption(
        'state',
        allowed: ['prepared', 'settled', 'recovered_archived'],
        help: 'Record state filter.',
      )
      ..addOption('from', help: 'Inclusive preparedAt UTC lower bound.')
      ..addOption('until', help: 'Exclusive preparedAt UTC upper bound.');
  }
}

ArgParser offlineParser(String group) {
  final p = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show group usage.');
  final commands = switch (group) {
    'draft' => ['create', 'show', 'update', 'delete', 'list'],
    'profile' => ['create', 'show', 'update', 'delete', 'list'],
    'settings' => ['show', 'set', 'reset'],
    'history' => ['list', 'show', 'delete', 'export', 'prune'],
    _ => throw StateError('Unknown business group.'),
  };
  for (final command in commands) {
    final leaf = _leaf();
    if (_requiresId(group, command)) _id(leaf);
    if (_requiresRevision(group, command)) _revision(leaf);
    if (group == 'draft') {
      if (command == 'create' || command == 'update') _body(leaf);
    }
    if (group == 'profile' && (command == 'create' || command == 'update')) {
      leaf
        ..addOption(
          'name',
          help:
              'Required exact nonblank profile name; names need not be unique.',
        )
        ..addOption(
          'operation',
          allowed: ['send', 'listen', 'ping', 'respond'],
          help: 'Required operation for the complete replacement preset.',
        )
        ..addOption(
          'port-hint',
          help: 'Optional local hint; never authorizes a connection.',
        );
      addProfileParameterOptions(leaf);
    }
    if (group == 'settings' && command == 'set') {
      leaf
        ..addOption(
          'default-profile-id',
          help: 'Existing profile ID; conflicts with --clear-default-profile.',
        )
        ..addFlag(
          'clear-default-profile',
          negatable: false,
          help: 'Explicitly clear the default profile.',
        )
        ..addOption(
          'history-limit',
          help: 'Diagnostic history limit (decimal 1..100000); initial default: 1000.',
        );
    }
    if (command == 'list' || command == 'export') {
      _page(leaf, history: group == 'history');
    }
    p.addCommand(command, leaf);
  }
  return p;
}

String offlineHelp(String group, ArgParser parser, [String? leaf]) =>
    'Usage: meshctl [--data-dir <path>] $group ${leaf ?? '<command>'} [options]\n\n'
    '${leaf == null ? parser.usage : parser.commands[leaf]!.usage}\n\n'
    '${leaf == null ? 'Commands: ${parser.commands.keys.join(', ')}.\n' : ''}'
    'Uses exclusive business storage, including reads; startup may recover/prune history.\n'
    '${group == 'profile' ? 'Create/update supply a complete preset. Update replaces all fields; omitted port hint/filter are cleared.\n' : ''}'
    '${group == 'draft' ? 'Update preserves omitted title/body; explicit empty values clear them. Stale revisions conflict.\n' : ''}'
    '${group == 'history' ? 'Queries/export select one bounded page by preparedAt. Export always writes core summary JSON; stderr carries one JSON metadata line with nextCursor and independent storage status. This is not a backup.\n' : ''}'
    'UTC inputs end in Z with at most six fractional digits. Cursor outputs have exactly six.\n'
    'Continue explicitly with both cursor values and the same filters; pages are not a shared snapshot.';

final class HostIoFailure implements Exception {
  const HostIoFailure(this.source);
  final String source;
}

final class OfflineResult {
  const OfflineResult(this.fields, {required this.committed, this.export});
  final Map<String, Object?> fields;
  final bool? committed;
  final DiagnosticSummaryPage? export;
}

final class OfflineCommand {
  const OfflineCommand(this.group, this.name, this.json, this.execute);
  final String group, name;
  final bool json;
  final Future<OfflineResult> Function(CoreStorage) execute;
}

Future<OfflineCommand> prepareOffline(String group, ArgResults args) async {
  final name = args.name!;
  final json = args.flag('json');
  OfflineCommand action(Future<OfflineResult> Function(CoreStorage) f) =>
      OfflineCommand(group, name, json, f);
  LocalId? id;
  if (_requiresId(group, name)) id = idOption(args);
  int? revision;
  if (_requiresRevision(group, name)) {
    revision = decimalOption(args, 'expected-revision', 1, 0x7fffffffffffffff);
  }
  if (group == 'draft' && (name == 'create' || name == 'update')) {
    if (args.wasParsed('body') && args.wasParsed('body-file')) {
      throw const FormatException('--body conflicts with --body-file.');
    }
    if (name == 'update' &&
        !args.wasParsed('title') &&
        !args.wasParsed('body') &&
        !args.wasParsed('body-file')) {
      throw const FormatException(
        'Update requires --title, --body or --body-file.',
      );
    }
    String? body = args.option('body');
    if (args.wasParsed('body-file')) {
      final List<int> bytes;
      try {
        bytes = await File(args.option('body-file')!).readAsBytes();
      } on FileSystemException {
        throw const HostIoFailure('body_file');
      }
      try {
        body = utf8.decode(bytes, allowMalformed: false);
        // One initial UTF-8 BOM is an encoding marker; all other text is exact.
      } on FormatException {
        throw const FormatException('--body-file must contain valid UTF-8.');
      }
    }
    final title = args.option('title');
    return action((s) async {
      final old = name == 'update' ? await s.drafts.read(id!) : null;
      final content = DraftContent(
        title: title ?? old?.title ?? '',
        body: body ?? old?.body ?? '',
      );
      final result = name == 'create'
          ? await s.drafts.create(content)
          : await s.drafts.update(id!, content, expectedRevision: revision!);
      return OfflineResult({'draft': draftFields(result)}, committed: true);
    });
  }
  if (group == 'profile' && (name == 'create' || name == 'update')) {
    final operation = args.option('operation');
    if (operation == null || args.option('name') == null) {
      throw const FormatException(
        'Provide --name and --operation for a complete preset.',
      );
    }
    final p = ParameterInput(args, operation).completeParameters();
    final content = ProfileContent(
      name: args.option('name')!,
      parameters: p,
      portHint: args.option('port-hint'),
    );
    return action(
      (s) async => OfflineResult({
        'profile': profileFields(await s.profiles.save(content, id: id)),
      }, committed: true),
    );
  }
  if (group == 'settings') {
    switch (name) {
      case 'show':
        return action(
          (s) async => OfflineResult({
            'settings': settingsFields(await s.settings.read()),
          }, committed: null),
        );
      case 'reset':
        return action(
          (s) async => OfflineResult({
            'settings': settingsFields(await s.settings.restoreDefaults()),
          }, committed: true),
        );
      case 'set':
        final selected = args.wasParsed('default-profile-id'),
            clear = args.flag('clear-default-profile'),
            limit = args.wasParsed('history-limit');
        if (selected && clear) {
          throw const FormatException(
            '--default-profile-id conflicts with --clear-default-profile.',
          );
        }
        if (!selected && !clear && !limit) {
          throw const FormatException(
            'Set requires at least one explicit setting.',
          );
        }
        final profile = selected ? idOption(args, 'default-profile-id') : null;
        final historyLimit = limit
            ? decimalOption(args, 'history-limit', 1, 100000)
            : null;
        return action((s) async {
          final old = (selected || clear) && limit
              ? null
              : await s.settings.read();
          final settings = AppSettings(
            defaultProfileId: selected || clear
                ? profile
                : old!.defaultProfileId,
            diagnosticHistoryLimit: historyLimit ?? old!.diagnosticHistoryLimit,
          );
          return OfflineResult({
            'settings': settingsFields(await s.settings.save(settings)),
          }, committed: true);
        });
    }
  }
  if (name == 'show') {
    return action(
      (s) async => OfflineResult(switch (group) {
        'draft' => {'draft': draftFields(await s.drafts.read(id!))},
        'profile' => {'profile': profileFields(await s.profiles.read(id!))},
        'history' => {'run': historyFields(await s.history.read(id!))},
        _ => throw StateError('Unknown show command.'),
      }, committed: null),
    );
  }
  if (name == 'delete') {
    return action((s) async {
      switch (group) {
        case 'draft':
          await s.drafts.delete(id!, expectedRevision: revision!);
        case 'profile':
          await s.profiles.delete(id!);
        case 'history':
          await s.history.delete(id!);
      }
      return OfflineResult({'id': id!.value, 'deleted': true}, committed: true);
    });
  }
  if (name == 'prune') {
    return action((s) async {
      final report = await s.history.maintain();
      return OfflineResult({
        'prune': maintenanceFields(report),
      }, committed: null);
    });
  }
  final size = PageSize(decimalOption(args, 'limit', 1, 200, fallback: 50));
  if (group == 'draft' || group == 'profile') {
    final cursor = updatedCursor(args);
    return action((s) async {
      if (group == 'draft') {
        final page = await s.drafts.list(size: size, after: cursor);
        return OfflineResult({
          'items': page.items.map((d) => draftFields(d, body: false)).toList(),
          'nextCursor': updatedCursorFields(page.nextCursor),
        }, committed: null);
      }
      final page = await s.profiles.list(size: size, after: cursor);
      return OfflineResult({
        'items': page.items.map((p) => profileFields(p, full: false)).toList(),
        'nextCursor': updatedCursorFields(page.nextCursor),
      }, committed: null);
    });
  }
  final cursor = historyCursor(args);
  final filter = HistoryQuery(
    operation: args.option('operation') == null
        ? null
        : DiagnosticOperation.values.singleWhere(
            (v) => v.code == args.option('operation'),
          ),
    recordState: args.option('state') == null
        ? null
        : DiagnosticRecordState.values.singleWhere(
            (v) => v.code == args.option('state'),
          ),
    preparedFromInclusive: args.option('from') == null
        ? null
        : utcInput(args.option('from')!),
    preparedUntilExclusive: args.option('until') == null
        ? null
        : utcInput(args.option('until')!),
  );
  return action((s) async {
    if (name == 'export') {
      final page = await s.history.exportSummary(
        filter: filter,
        size: size,
        after: cursor,
      );
      return OfflineResult(const {}, committed: null, export: page);
    }
    final page = await s.history.query(
      filter: filter,
      size: size,
      after: cursor,
    );
    return OfflineResult({
      'items': page.items.map((r) => historyFields(r, full: false)).toList(),
      'nextCursor': historyCursorFields(page.nextCursor),
    }, committed: null);
  });
}

Future<int> runOffline(
  OfflineCommand command,
  CliOutput io,
  Future<CoreStorage> Function() open,
  Stream<CliStopRequest>? stopRequests,
) async {
  BusinessStorage? life;
  OfflineResult? result;
  Map<String, Object?>? failure;
  Map<String, Object?>? businessFailure;
  var code = 0;
  var reason = 'completed';
  StreamSubscription<CliStopRequest>? signals;
  final hostFailures = <Map<String, Object?>>[];
  Object? internal;
  StackTrace? internalStack;
  var hostCleanup = 'not_required';
  void choose(String why, int value) {
    if (code == 0) {
      reason = why;
      code = value;
    }
  }

  io.onFailure = () => choose('output_failure', 74);
  try {
    signals = stopRequests?.listen(
      (request) {
        choose(request.name, request == CliStopRequest.sigint ? 130 : 143);
      },
      onError: (Object e, StackTrace s) {
        internal ??= e;
        internalStack ??= s;
        choose('internal_error', 70);
      },
    );
    if (io.failed) choose('output_failure', 74);
    if (code == 0) {
      life = BusinessStorage(await open());
      // Admitted SQLite work has no cancellation API. Let it settle and close,
      // preserving any committed result independently of the host's intent.
      if (code == 0) result = await command.execute(life.storage);
    }
  } on CoreException catch (e) {
    businessFailure = coreErrorFields(e, life == null ? 'open' : 'operation');
    if (code == 0) {
      choose('business_failure', coreExitCode(e));
      failure = businessFailure;
    }
  } finally {
    try {
      await life?.finish();
      // Storage settles before signal cleanup; preserve that failure order.
      if (life?.failed ?? false) choose('storage_finalization_failure', 74);
    } finally {
      if (signals != null) {
        try {
          await signals.cancel();
          hostCleanup = 'succeeded';
        } catch (_) {
          hostCleanup = 'failed';
          hostFailures.add({
            'domain': 'host',
            'source': 'signalSubscription',
            'code': 'cleanup_failure',
          });
          choose('cleanup_failure', 69);
        }
      }
      io.onFailure = null;
    }
  }
  if (internal != null) Error.throwWithStackTrace(internal!, internalStack!);
  await io.drain();
  if (io.failed) choose('output_failure', 74);
  final additionalFailures = [
    if (businessFailure != null && failure == null) businessFailure,
    ...hostFailures,
    ...?life?.failures,
  ];
  final envelope = {
    'schemaVersion': 1,
    'command': command.group,
    'action': command.name,
    'operationSucceeded': result != null,
    'committed': result?.committed ?? (businessFailure == null ? null : false),
    'reason': reason,
    'exitCode': code,
    'failure': failure,
    if (result != null) ...result.fields,
    'maintenance': life?.maintenance,
    'storageClose': life?.closeResult,
    'hostCleanup': hostCleanup,
    'additionalFailures': additionalFailures,
  };
  if (command.name == 'export') {
    if (result?.export case final summary?) io.out(summary.json);
    io.err(
      jsonEncode({
        'schemaVersion': 1,
        'command': 'history',
        'action': 'export',
        'event': 'metadata',
        'nextCursor': historyCursorFields(result?.export?.nextCursor),
        'operationSucceeded': result != null,
        'reason': reason,
        'exitCode': code,
        'failure': failure,
        'maintenance': life?.maintenance,
        'storageClose': life?.closeResult,
        'hostCleanup': hostCleanup,
        'additionalFailures': additionalFailures,
      }),
    );
  } else {
    io.out(
      command.json
          ? jsonEncode(envelope)
          : '${command.group} ${command.name}: ${safeText(jsonEncode(envelope))}',
    );
  }
  if (businessFailure != null) {
    io.err('Error: Business operation failed: ${jsonEncode(businessFailure)}');
  }
  for (final f in life?.failures ?? <Map<String, Object?>>[]) {
    io.err('Error: Storage finalization failed: ${jsonEncode(f)}');
  }
  await io.drain();
  return code == 0 && io.failed ? 74 : code;
}
