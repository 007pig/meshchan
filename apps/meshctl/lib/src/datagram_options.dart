import 'dart:convert';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshcore_link/meshcore_link.dart';

ArgParser datagramParser() {
  final group = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show group usage.');
  for (final operation in ['send', 'listen', 'ping', 'respond']) {
    final sends = operation != 'listen';
    final diagnostic = operation == 'ping' || operation == 'respond';
    final receives = operation != 'send';
    final leaf = ArgParser()
      ..addFlag(
        'help',
        abbr: 'h',
        negatable: false,
        help: 'Show operation usage.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help:
            'Write ${operation == 'listen' ? 'NDJSON events and end' : 'one final JSON object'}.',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Write safe structural diagnostics to stderr.',
      )
      ..addOption(
        'port',
        help: 'Required exact, explicitly selected serial port path.',
      )
      ..addOption(
        'timeout',
        defaultsTo: '5',
        help:
            'Per-command initialization/send/read budget, seconds (1..86400).',
      )
      ..addOption(
        'init-timeout',
        defaultsTo: '15',
        help: 'Total initialization budget, seconds (1..86400).',
      )
      ..addOption(
        'startup-delay',
        defaultsTo: '0',
        help: 'Startup delay, milliseconds (0..86399999); less than init-timeout.',
      )
      ..addOption(
        'task-timeout',
        help: 'Required overall application budget, seconds (1..86400); excludes cleanup/output.',
      );
    leaf
      ..addOption(
        'profile',
        help: 'Local profile ID; otherwise use the default profile.',
      )
      ..addFlag(
        'record',
        negatable: false,
        help: 'Record finite logical, cleanup and persistence summaries. Listen emits only one final end.',
      );
    if (operation == 'listen') {
      leaf.addFlag(
        'all-data-types',
        negatable: false,
        help: 'Clear an inherited listen data type filter; conflicts with --data-type.',
      );
    }
    if (sends) {
      leaf
        ..addOption('send-channel', help: 'Required local send slot, uint8.')
        ..addOption(
          'route-descriptor',
          help: 'Required send route uint8; 0xFF Flood, 0x00 zero-hop Direct.',
        )
        ..addOption(
          'path-hex',
          defaultsTo: '',
          help: 'Exact route bytes as even-length ASCII HEX; default: empty.',
        );
    }
    if (receives) {
      leaf
        ..addOption(
          'receive-channel',
          help: 'Required local receive slot, uint8.',
        )
        ..addOption(
          'max-entries',
          defaultsTo: '128',
          help: 'Total published entries (1..4096), including filtered traffic and chat.',
        );
    }
    if (diagnostic) {
      leaf
        ..addOption(
          'local-id',
          help: 'Required nonzero uint32 local test label.',
        )
        ..addOption(
          'peer-id',
          help: 'Required distinct nonzero uint32 peer test label.',
        );
    } else {
      leaf.addOption(
        'data-type',
        help: operation == 'send'
            ? 'Required raw data type (1..65535).'
            : 'Optional data type filter (0..65535); default: all.',
      );
    }
    if (operation == 'send' || operation == 'ping') {
      leaf
        ..addOption(
          operation == 'send' ? 'payload-hex' : 'content-hex',
          help: 'Even-length ASCII HEX; exactly one of this option or --text (empty allowed).',
        )
        ..addOption(
          'text',
          help: 'Exact UTF-8 content; no normalization or terminator (empty allowed).',
        );
    }
    if (operation == 'ping') {
      leaf.addOption(
        'response-timeout',
        help: 'Required PONG wait budget, seconds (1..86400).',
      );
    }
    if (operation == 'listen' || operation == 'respond') {
      leaf.addOption(
        'duration',
        help:
            'Required finite listening window after ready, seconds (1..86400).',
      );
    }
    if (operation == 'respond') {
      leaf.addOption(
        'max-responses',
        defaultsTo: '1',
        help: 'Response attempt limit (1..4096).',
      );
    }
    group.addCommand(operation, leaf);
  }
  return group;
}

String datagramHelp(ArgParser group, [String? operation]) => operation == null
    ? 'Usage: meshctl datagram <operation> [options]\n\n${group.usage}\n\n'
          'Operations:\n  send     Send one raw datagram; confirm device acceptance.\n'
          '  listen   Consume the shared inbox for a finite window.\n'
          '  ping     Run one exact diagnostic PING/PONG round trip.\n'
          '  respond  Run a finite diagnostic responder.\n\n'
          'Put business options after the operation. Run "meshctl datagram <operation> --help".'
    : 'Usage: meshctl datagram $operation [options]\n\n${group.commands[operation]!.usage}\n\n'
          'Initializes with DEVICE_QUERY then APP_START; opening may reset boards. No retry.\n'
          'Protocol integers accept strict decimal or 0x/0X HEX; times/counts are decimal only.\n'
          'Route/path validity and the full encoded byte budget are checked before I/O.\n'
          'Explicit values override the selected/default profile, then program defaults.\n'
          'Every invocation opens business storage, even without --record.\n'
          '--port and send/ping content must be supplied on this invocation.\n'
          '--record listen emits one final summary end, without per-datagram events.\n'
          'Cleanup and output may remain pending beyond --task-timeout.\n'
          '${operation == 'send' ? 'Success means local write and device acceptance, not remote delivery.' : 'Consumes the shared inbox, including ordinary chat and other applications.\nFiltering occurs after consumption; all entries consume max-entries. Chat bodies are discarded.'}';

/// Pure validation. Do not use task construction/start as a configuration probe.
final class DatagramOptions {
  DatagramOptions(ArgResults args)
    : operation = args.name!,
      json = args.flag('json'),
      verbose = args.flag('verbose') {
    port = args.option('port') ?? '';
    if (port.trim().isEmpty) {
      throw const FormatException('--port must be nonempty.');
    }
    requestTimeout = Duration(seconds: _integer(args, 'timeout', 1, 86400)!);
    initializationTimeout = Duration(
      seconds: _integer(args, 'init-timeout', 1, 86400)!,
    );
    startupDelay = Duration(
      milliseconds: _integer(args, 'startup-delay', 0, 86399999)!,
    );
    if (startupDelay >= initializationTimeout) {
      throw const FormatException(
        '--startup-delay must be less than --init-timeout in milliseconds.',
      );
    }
    taskTimeout = Duration(seconds: _integer(args, 'task-timeout', 1, 86400)!);
    if (operation != 'listen') {
      sendChannel = _integer(args, 'send-channel', 0, 255, protocol: true);
      routeDescriptor = _integer(
        args,
        'route-descriptor',
        0,
        255,
        protocol: true,
      );
      path = _hex(args.option('path-hex')!, 'path-hex');
    }
    if (operation != 'send') {
      receiveChannel = _integer(
        args,
        'receive-channel',
        0,
        255,
        protocol: true,
      );
      maxEntries = _integer(args, 'max-entries', 1, 4096)!;
    }
    if (operation == 'ping' || operation == 'respond') {
      localId = _integer(args, 'local-id', 1, 0xffffffff, protocol: true);
      peerId = _integer(args, 'peer-id', 1, 0xffffffff, protocol: true);
      if (localId == peerId) {
        throw const FormatException('--local-id and --peer-id must differ.');
      }
    } else {
      dataType = _integer(
        args,
        'data-type',
        operation == 'send' ? 1 : 0,
        65535,
        protocol: true,
        required: operation == 'send',
      );
    }
    if (operation == 'send' || operation == 'ping') {
      final name = operation == 'send' ? 'payload-hex' : 'content-hex';
      if (args.wasParsed(name) == args.wasParsed('text')) {
        throw FormatException('Provide exactly one of --$name or --text.');
      }
      bytes = args.wasParsed(name)
          ? _hex(args.option(name)!, name)
          : Uint8List.fromList(utf8.encode(args.option('text')!));
    }
    if (operation == 'ping') {
      responseTimeout = Duration(
        seconds: _integer(args, 'response-timeout', 1, 86400)!,
      );
    }
    if (operation == 'listen' || operation == 'respond') {
      duration = Duration(seconds: _integer(args, 'duration', 1, 86400)!);
    }
    if (operation == 'respond') {
      maxResponses = _integer(args, 'max-responses', 1, 4096)!;
    }
    if (operation != 'listen') {
      final int capacity;
      try {
        capacity = operation == 'send'
            ? maxChannelDataPayloadLengthForRoute(
                routeDescriptor: routeDescriptor!,
                path: path,
              )
            : maxDiagnosticContentLengthForRoute(
                routeDescriptor: routeDescriptor!,
                path: path,
              );
      } on ArgumentError {
        throw const FormatException(
          '--route-descriptor and --path-hex must describe a valid send route.',
        );
      }
      if (bytes.length > capacity) {
        throw FormatException(
          '${operation == 'send' ? 'Payload' : 'Content'} exceeds --route-descriptor/--path-hex byte capacity ($capacity).',
        );
      }
    }
  }

  DatagramOptions.effective(DatagramInput input, EffectiveParameters effective)
    : operation = input.operation,
      json = input.json,
      verbose = input.verbose {
    port = input.port;
    final p = effective.parameters;
    final b = p.budgets;
    requestTimeout = Duration(seconds: b.requestTimeoutSeconds);
    initializationTimeout = Duration(seconds: b.initializationTimeoutSeconds);
    startupDelay = Duration(milliseconds: b.startupDelayMilliseconds);
    taskTimeout = Duration(seconds: b.taskTimeoutSeconds);
    bytes = Uint8List.fromList(effective.content ?? const []);
    void route(ProfileRoute r) {
      routeDescriptor = r.routeDescriptor;
      path = Uint8List.fromList(r.path);
    }

    void endpoints(ProfileTestEndpoints e) {
      localId = e.localTestId;
      peerId = e.peerTestId;
    }

    switch (p) {
      case SendProfileParameters():
        sendChannel = p.sendChannelIndex;
        dataType = p.dataType;
        route(p.route);
      case ListenProfileParameters():
        receiveChannel = p.receiveChannelIndex;
        dataType = p.dataType;
        duration = Duration(seconds: p.listenDurationSeconds);
        maxEntries = p.maxEntries;
      case PingProfileParameters():
        sendChannel = p.sendChannelIndex;
        receiveChannel = p.receiveChannelIndex;
        route(p.route);
        endpoints(p.endpoints);
        maxEntries = p.maxEntries;
        responseTimeout = Duration(seconds: p.responseTimeoutSeconds);
      case RespondProfileParameters():
        sendChannel = p.sendChannelIndex;
        receiveChannel = p.receiveChannelIndex;
        route(p.route);
        endpoints(p.endpoints);
        maxEntries = p.maxEntries;
        duration = Duration(seconds: p.listenDurationSeconds);
        maxResponses = p.maxResponses;
    }
  }

  final String operation;
  final bool json;
  final bool verbose;
  late final String port;
  late final Duration requestTimeout,
      initializationTimeout,
      startupDelay,
      taskTimeout;
  int? sendChannel, receiveChannel, dataType, routeDescriptor, localId, peerId;
  int maxEntries = 128, maxResponses = 1;
  Uint8List path = Uint8List(0), bytes = Uint8List(0);
  Duration? responseTimeout, duration;

  DiagnosticTaskOptions taskOptions() => DiagnosticTaskOptions(
    sendChannelIndex: sendChannel!,
    receiveChannelIndex: receiveChannel!,
    localTestId: localId!,
    peerTestId: peerId!,
    routeDescriptor: routeDescriptor!,
    path: path,
    taskTimeout: taskTimeout,
    maxEntries: maxEntries,
  );
}

int? _integer(
  ArgResults args,
  String name,
  int min,
  int max, {
  bool protocol = false,
  bool required = true,
}) {
  final value = args.option(name);
  if (value == null && !required) return null;
  final decimal = value != null && RegExp(r'^[0-9]+$').hasMatch(value);
  final hex =
      protocol &&
      value != null &&
      RegExp(r'^0[xX][0-9a-fA-F]+$').hasMatch(value);
  final number = decimal
      ? int.tryParse(value)
      : hex
      ? int.tryParse(value.substring(2), radix: 16)
      : null;
  if (number == null || number < min || number > max) {
    throw FormatException(
      '--$name must be a ${protocol ? 'decimal or 0x-prefixed hexadecimal' : 'decimal'} integer in $min..$max.',
    );
  }
  return number;
}

Uint8List _hex(String value, String name) {
  if (value.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(value)) {
    throw FormatException(
      '--$name must contain an even number of ASCII HEX digits without separators or prefix.',
    );
  }
  return Uint8List.fromList([
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ]);
}

/// Lexical values retain presence. No parser-inserted default enters a request.
final class ParameterInput {
  ParameterInput(this.args, this.operation) {
    final applicable = datagramParser().commands[operation]!.options.keys
        .toSet();
    for (final name in parameterNames) {
      if (args.options.contains(name) &&
          args.wasParsed(name) &&
          !applicable.contains(name)) {
        throw FormatException('--$name does not apply to this operation.');
      }
    }
    for (final name in parameterNames) {
      if (!applicable.contains(name) ||
          !args.wasParsed(name) ||
          name == 'all-data-types' ||
          name == 'path-hex') {
        continue;
      }
      final (min, max, protocol) = switch (name) {
        'send-channel' ||
        'receive-channel' ||
        'route-descriptor' => (0, 255, true),
        'local-id' || 'peer-id' => (1, 0xffffffff, true),
        'data-type' => (operation == 'send' ? 1 : 0, 65535, true),
        'startup-delay' => (0, 86399999, false),
        'max-entries' || 'max-responses' => (1, 4096, false),
        _ => (1, 86400, false),
      };
      numbers[name] = _integer(args, name, min, max, protocol: protocol)!;
    }
    if (applicable.contains('path-hex') && args.wasParsed('path-hex')) {
      path = _hex(args.option('path-hex')!, 'path-hex');
    }
    if (operation == 'listen' &&
        args.wasParsed('all-data-types') &&
        args.wasParsed('data-type')) {
      throw const FormatException(
        '--all-data-types conflicts with --data-type.',
      );
    }
    if (numbers['local-id'] != null &&
        numbers['local-id'] == numbers['peer-id']) {
      throw const FormatException('--local-id and --peer-id must differ.');
    }
    if (numbers['startup-delay'] != null &&
        numbers['init-timeout'] != null &&
        numbers['startup-delay']! >= numbers['init-timeout']! * 1000) {
      throw const FormatException(
        '--startup-delay must be less than --init-timeout in milliseconds.',
      );
    }
  }
  final ArgResults args;
  final String operation;
  final numbers = <String, int>{};
  Uint8List? path;
  int? n(String name) => numbers[name];
  int requiredNumber(String name) =>
      n(name) ??
      (throw FormatException('--$name is required for a complete preset.'));
  BudgetOverrides get budgets => BudgetOverrides(
    requestTimeoutSeconds: n('timeout'),
    initializationTimeoutSeconds: n('init-timeout'),
    startupDelayMilliseconds: n('startup-delay'),
    taskTimeoutSeconds: n('task-timeout'),
  );
  RouteOverrides get route =>
      RouteOverrides(routeDescriptor: n('route-descriptor'), path: path);
  EndpointOverrides get endpoints =>
      EndpointOverrides(localTestId: n('local-id'), peerTestId: n('peer-id'));
  DataTypeOverride? get filter => args.wasParsed('all-data-types')
      ? const DataTypeOverride(null)
      : n('data-type') == null
      ? null
      : DataTypeOverride(n('data-type'));

  EffectiveParameterRequest request({LocalId? profileId, List<int>? content}) =>
      switch (operation) {
        'send' => SendParameterRequest(
          profileId: profileId,
          payload: content,
          overrides: SendOverrides(
            budgets: budgets,
            sendChannelIndex: n('send-channel'),
            route: route,
            dataType: n('data-type'),
          ),
        ),
        'listen' => ListenParameterRequest(
          profileId: profileId,
          overrides: ListenOverrides(
            budgets: budgets,
            receiveChannelIndex: n('receive-channel'),
            dataType: filter,
            listenDurationSeconds: n('duration'),
            maxEntries: n('max-entries'),
          ),
        ),
        'ping' => PingParameterRequest(
          profileId: profileId,
          content: content,
          overrides: PingOverrides(
            budgets: budgets,
            sendChannelIndex: n('send-channel'),
            receiveChannelIndex: n('receive-channel'),
            route: route,
            endpoints: endpoints,
            responseTimeoutSeconds: n('response-timeout'),
            maxEntries: n('max-entries'),
          ),
        ),
        'respond' => RespondParameterRequest(
          profileId: profileId,
          overrides: RespondOverrides(
            budgets: budgets,
            sendChannelIndex: n('send-channel'),
            receiveChannelIndex: n('receive-channel'),
            route: route,
            endpoints: endpoints,
            listenDurationSeconds: n('duration'),
            maxEntries: n('max-entries'),
            maxResponses: n('max-responses'),
          ),
        ),
        _ => throw StateError('Unknown operation.'),
      };

  ProfileParameters completeParameters() {
    final b = ProfileBudgets(
      taskTimeoutSeconds: requiredNumber('task-timeout'),
      requestTimeoutSeconds: n('timeout') ?? 5,
      initializationTimeoutSeconds: n('init-timeout') ?? 15,
      startupDelayMilliseconds: n('startup-delay') ?? 0,
    );
    ProfileRoute r() => ProfileRoute(
      routeDescriptor: requiredNumber('route-descriptor'),
      path: path ?? const [],
    );
    ProfileTestEndpoints e() => ProfileTestEndpoints(
      localTestId: requiredNumber('local-id'),
      peerTestId: requiredNumber('peer-id'),
    );
    return switch (operation) {
      'send' => SendProfileParameters(
        budgets: b,
        sendChannelIndex: requiredNumber('send-channel'),
        route: r(),
        dataType: requiredNumber('data-type'),
      ),
      'listen' => ListenProfileParameters(
        budgets: b,
        receiveChannelIndex: requiredNumber('receive-channel'),
        listenDurationSeconds: requiredNumber('duration'),
        dataType: n('data-type'),
        maxEntries: n('max-entries') ?? 128,
      ),
      'ping' => PingProfileParameters(
        budgets: b,
        sendChannelIndex: requiredNumber('send-channel'),
        receiveChannelIndex: requiredNumber('receive-channel'),
        route: r(),
        endpoints: e(),
        responseTimeoutSeconds: requiredNumber('response-timeout'),
        maxEntries: n('max-entries') ?? 128,
      ),
      'respond' => RespondProfileParameters(
        budgets: b,
        sendChannelIndex: requiredNumber('send-channel'),
        receiveChannelIndex: requiredNumber('receive-channel'),
        route: r(),
        endpoints: e(),
        listenDurationSeconds: requiredNumber('duration'),
        maxEntries: n('max-entries') ?? 128,
        maxResponses: n('max-responses') ?? 1,
      ),
      _ => throw StateError('Unknown operation.'),
    };
  }
}

const parameterNames = {
  'timeout',
  'init-timeout',
  'startup-delay',
  'task-timeout',
  'send-channel',
  'receive-channel',
  'route-descriptor',
  'path-hex',
  'local-id',
  'peer-id',
  'data-type',
  'response-timeout',
  'duration',
  'max-entries',
  'max-responses',
  'all-data-types',
};

/// Profile parsing reuses the same option declarations and lexical rules, while
/// rejecting explicit fields that do not apply to its selected operation.
void addProfileParameterOptions(ArgParser parser) {
  for (final leaf in datagramParser().commands.values) {
    for (final option in leaf.options.values) {
      if (!parameterNames.contains(option.name) ||
          parser.options.containsKey(option.name)) {
        continue;
      }
      if (option.name == 'all-data-types') {
        parser.addFlag(option.name, negatable: false, help: option.help);
      } else {
        parser.addOption(
          option.name,
          help: option.name == 'data-type'
              ? 'Send type (1..65535) or optional listen filter (0..65535).'
              : option.help,
        );
      }
    }
  }
}

final class DatagramInput {
  DatagramInput(ArgResults args)
    : operation = args.name!,
      json = args.flag('json'),
      verbose = args.flag('verbose'),
      record = args.flag('record') {
    port = args.option('port') ?? '';
    if (!args.wasParsed('port') || port.trim().isEmpty) {
      throw const FormatException(
        '--port must be nonempty and explicitly supplied.',
      );
    }
    parameters = ParameterInput(args, operation);
    if (args.wasParsed('profile')) profileId = LocalId(args.option('profile')!);
    if (operation == 'send' || operation == 'ping') {
      final name = operation == 'send' ? 'payload-hex' : 'content-hex';
      if (args.wasParsed(name) == args.wasParsed('text')) {
        throw FormatException('Provide exactly one of --$name or --text.');
      }
      content = args.wasParsed(name)
          ? _hex(args.option(name)!, name)
          : Uint8List.fromList(utf8.encode(args.option('text')!));
    }
  }
  final String operation;
  final bool json, verbose, record;
  late final String port;
  late final ParameterInput parameters;
  LocalId? profileId;
  List<int>? content;
  EffectiveParameterRequest get request =>
      parameters.request(profileId: profileId, content: content);
}
