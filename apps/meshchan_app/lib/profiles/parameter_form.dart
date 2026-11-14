import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshcore_link/meshcore_link.dart';

enum ParameterField {
  requestTimeoutSeconds,
  initializationTimeoutSeconds,
  startupDelayMilliseconds,
  taskTimeoutSeconds,
  sendChannelIndex,
  receiveChannelIndex,
  routeDescriptor,
  path,
  dataType,
  localTestId,
  peerTestId,
  responseTimeoutSeconds,
  listenDurationSeconds,
  maxEntries,
  maxResponses,
}

const budgetFields = [
  ParameterField.requestTimeoutSeconds,
  ParameterField.initializationTimeoutSeconds,
  ParameterField.startupDelayMilliseconds,
  ParameterField.taskTimeoutSeconds,
];
const routeFields = [ParameterField.routeDescriptor, ParameterField.path];
const endpointFields = [ParameterField.localTestId, ParameterField.peerTestId];
List<ParameterField> fieldsFor(DiagnosticOperation operation) => [
  ...budgetFields,
  if (operation != DiagnosticOperation.listen) ParameterField.sendChannelIndex,
  if (operation != DiagnosticOperation.send) ParameterField.receiveChannelIndex,
  if (operation != DiagnosticOperation.listen) ...routeFields,
  if (operation == DiagnosticOperation.send ||
      operation == DiagnosticOperation.listen)
    ParameterField.dataType,
  if (operation == DiagnosticOperation.ping ||
      operation == DiagnosticOperation.respond)
    ...endpointFields,
  if (operation == DiagnosticOperation.ping)
    ParameterField.responseTimeoutSeconds,
  if (operation == DiagnosticOperation.listen ||
      operation == DiagnosticOperation.respond)
    ParameterField.listenDurationSeconds,
  if (operation != DiagnosticOperation.send) ParameterField.maxEntries,
  if (operation == DiagnosticOperation.respond) ParameterField.maxResponses,
];
bool protocolNumber(ParameterField f) => [
  ...routeFields,
  ...endpointFields,
  ParameterField.sendChannelIndex,
  ParameterField.receiveChannelIndex,
  ParameterField.dataType,
].contains(f);
int parseNumber(String text, {bool protocol = false}) {
  if (!RegExp(protocol ? r'^(?:[0-9]+|0[xX][0-9a-fA-F]+)$' : r'^[0-9]+$')
      .hasMatch(text)) {
    throw const FormatException(
      'Enter a whole number using the displayed syntax.',
    );
  }
  if (text.contains('\n') || text.contains('\r')) {
    throw const FormatException('No whitespace is allowed in numbers.');
  }
  final value = int.tryParse(
    text.startsWith('0x') || text.startsWith('0X') ? text.substring(2) : text,
    radix: text.startsWith('0x') || text.startsWith('0X') ? 16 : 10,
  );
  if (value == null) throw const FormatException('Number is too large.');
  return value;
}

List<int> parseHex(String text) {
  if (text.contains('\n') ||
      text.contains('\r') ||
      text.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]*$').hasMatch(text)) {
    throw const FormatException(
      'Use even-length ASCII hex without separators or a prefix.',
    );
  }
  return List.unmodifiable([
    for (var i = 0; i < text.length; i += 2)
      int.parse(text.substring(i, i + 2), radix: 16),
  ]);
}

String hexBytes(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Presence and raw lexical input are independent. No resolver defaults are
/// inserted into invocation requests, and no private core validation is used.
class ParameterForm {
  ParameterForm(this.operation, {this.overrides = false}) {
    for (final f in ParameterField.values) {
      inputs[f] = TextEditingController();
    }
    if (!overrides) loadDefaults();
  }
  DiagnosticOperation operation;
  final bool overrides;
  final inputs = <ParameterField, TextEditingController>{};
  final explicit = <ParameterField>{};
  bool listenAll = true;
  List<ParameterField> get fields => fieldsFor(operation);
  void loadDefaults() {
    for (final c in inputs.values) {
      c.text = '';
    }
    inputs[ParameterField.requestTimeoutSeconds]!.text = '5';
    inputs[ParameterField.initializationTimeoutSeconds]!.text = '15';
    inputs[ParameterField.startupDelayMilliseconds]!.text = '0';
    inputs[ParameterField.maxEntries]!.text = '128';
    inputs[ParameterField.maxResponses]!.text = '1';
    listenAll = true;
  }

  void changeType(DiagnosticOperation next) {
    final common = {for (final f in budgetFields) f: inputs[f]!.text};
    operation = next;
    loadDefaults();
    explicit.clear();
    for (final e in common.entries) {
      inputs[e.key]!.text = e.value;
    }
  }

  Map<ParameterField, String> values(ProfileParameters p) {
    final b = p.budgets;
    final v = <ParameterField, String>{
      ParameterField.requestTimeoutSeconds: '${b.requestTimeoutSeconds}',
      ParameterField.initializationTimeoutSeconds:
          '${b.initializationTimeoutSeconds}',
      ParameterField.startupDelayMilliseconds: '${b.startupDelayMilliseconds}',
      ParameterField.taskTimeoutSeconds: '${b.taskTimeoutSeconds}',
    };
    void route(ProfileRoute r) {
      v[ParameterField.routeDescriptor] = '${r.routeDescriptor}';
      v[ParameterField.path] = hexBytes(r.path);
    }

    void endpoints(ProfileTestEndpoints e) {
      v[ParameterField.localTestId] = '${e.localTestId}';
      v[ParameterField.peerTestId] = '${e.peerTestId}';
    }

    switch (p) {
      case SendProfileParameters():
        v[ParameterField.sendChannelIndex] = '${p.sendChannelIndex}';
        v[ParameterField.dataType] = '${p.dataType}';
        route(p.route);
      case ListenProfileParameters():
        v[ParameterField.receiveChannelIndex] = '${p.receiveChannelIndex}';
        v[ParameterField.dataType] = p.dataType == null
            ? 'All types'
            : '${p.dataType}';
        v[ParameterField.listenDurationSeconds] = '${p.listenDurationSeconds}';
        v[ParameterField.maxEntries] = '${p.maxEntries}';
      case PingProfileParameters():
        v[ParameterField.sendChannelIndex] = '${p.sendChannelIndex}';
        v[ParameterField.receiveChannelIndex] = '${p.receiveChannelIndex}';
        route(p.route);
        endpoints(p.endpoints);
        v[ParameterField.responseTimeoutSeconds] =
            '${p.responseTimeoutSeconds}';
        v[ParameterField.maxEntries] = '${p.maxEntries}';
      case RespondProfileParameters():
        v[ParameterField.sendChannelIndex] = '${p.sendChannelIndex}';
        v[ParameterField.receiveChannelIndex] = '${p.receiveChannelIndex}';
        route(p.route);
        endpoints(p.endpoints);
        v[ParameterField.listenDurationSeconds] = '${p.listenDurationSeconds}';
        v[ParameterField.maxEntries] = '${p.maxEntries}';
        v[ParameterField.maxResponses] = '${p.maxResponses}';
    }
    return v;
  }

  void load(ProfileParameters p) {
    operation = p.operation;
    for (final c in inputs.values) {
      c.text = '';
    }
    for (final e in values(p).entries) {
      inputs[e.key]!.text = e.value;
    }
    listenAll = p is ListenProfileParameters && p.dataType == null;
    if (listenAll) inputs[ParameterField.dataType]!.text = '';
  }

  String get signature => jsonEncode([
    operation.name,
    operation == DiagnosticOperation.listen ? listenAll : false,
    for (final f in fields) [f.name, inputs[f]!.text, explicit.contains(f)],
  ]);
  int? number(ParameterField f) => overrides && !explicit.contains(f)
      ? null
      : parseNumber(inputs[f]!.text, protocol: protocolNumber(f));
  List<int>? get path => overrides && !explicit.contains(ParameterField.path)
      ? null
      : parseHex(inputs[ParameterField.path]!.text);
  BudgetOverrides get budgetOverrides => BudgetOverrides(
    requestTimeoutSeconds: number(ParameterField.requestTimeoutSeconds),
    initializationTimeoutSeconds: number(
      ParameterField.initializationTimeoutSeconds,
    ),
    startupDelayMilliseconds: number(ParameterField.startupDelayMilliseconds),
    taskTimeoutSeconds: number(ParameterField.taskTimeoutSeconds),
  );
  RouteOverrides get routeOverrides => RouteOverrides(
    routeDescriptor: number(ParameterField.routeDescriptor),
    path: path,
  );
  EndpointOverrides get endpointOverrides => EndpointOverrides(
    localTestId: number(ParameterField.localTestId),
    peerTestId: number(ParameterField.peerTestId),
  );
  int? get filter => listenAll ? null : number(ParameterField.dataType);
  ProfileParameters parameters() {
    final b = ProfileBudgets(
      requestTimeoutSeconds: number(ParameterField.requestTimeoutSeconds)!,
      initializationTimeoutSeconds: number(
        ParameterField.initializationTimeoutSeconds,
      )!,
      startupDelayMilliseconds: number(
        ParameterField.startupDelayMilliseconds,
      )!,
      taskTimeoutSeconds: number(ParameterField.taskTimeoutSeconds)!,
    );
    ProfileRoute route() => ProfileRoute(
      routeDescriptor: number(ParameterField.routeDescriptor)!,
      path: path!,
    );
    ProfileTestEndpoints endpoints() => ProfileTestEndpoints(
      localTestId: number(ParameterField.localTestId)!,
      peerTestId: number(ParameterField.peerTestId)!,
    );
    return switch (operation) {
      DiagnosticOperation.send => SendProfileParameters(
        budgets: b,
        sendChannelIndex: number(ParameterField.sendChannelIndex)!,
        route: route(),
        dataType: number(ParameterField.dataType)!,
      ),
      DiagnosticOperation.listen => ListenProfileParameters(
        budgets: b,
        receiveChannelIndex: number(ParameterField.receiveChannelIndex)!,
        dataType: filter,
        listenDurationSeconds: number(ParameterField.listenDurationSeconds)!,
        maxEntries: number(ParameterField.maxEntries)!,
      ),
      DiagnosticOperation.ping => PingProfileParameters(
        budgets: b,
        sendChannelIndex: number(ParameterField.sendChannelIndex)!,
        receiveChannelIndex: number(ParameterField.receiveChannelIndex)!,
        route: route(),
        endpoints: endpoints(),
        responseTimeoutSeconds: number(ParameterField.responseTimeoutSeconds)!,
        maxEntries: number(ParameterField.maxEntries)!,
      ),
      DiagnosticOperation.respond => RespondProfileParameters(
        budgets: b,
        sendChannelIndex: number(ParameterField.sendChannelIndex)!,
        receiveChannelIndex: number(ParameterField.receiveChannelIndex)!,
        route: route(),
        endpoints: endpoints(),
        listenDurationSeconds: number(ParameterField.listenDurationSeconds)!,
        maxEntries: number(ParameterField.maxEntries)!,
        maxResponses: number(ParameterField.maxResponses)!,
      ),
    };
  }

  EffectiveParameterRequest request({String? profileId, List<int>? content}) {
    final id = profileId == null ? null : LocalId(profileId);
    return switch (operation) {
      DiagnosticOperation.send => SendParameterRequest(
        profileId: id,
        payload: content,
        overrides: SendOverrides(
          budgets: budgetOverrides,
          sendChannelIndex: number(ParameterField.sendChannelIndex),
          route: routeOverrides,
          dataType: number(ParameterField.dataType),
        ),
      ),
      DiagnosticOperation.listen => ListenParameterRequest(
        profileId: id,
        overrides: ListenOverrides(
          budgets: budgetOverrides,
          receiveChannelIndex: number(ParameterField.receiveChannelIndex),
          dataType: explicit.contains(ParameterField.dataType)
              ? DataTypeOverride(filter)
              : null,
          listenDurationSeconds: number(ParameterField.listenDurationSeconds),
          maxEntries: number(ParameterField.maxEntries),
        ),
      ),
      DiagnosticOperation.ping => PingParameterRequest(
        profileId: id,
        content: content,
        overrides: PingOverrides(
          budgets: budgetOverrides,
          sendChannelIndex: number(ParameterField.sendChannelIndex),
          receiveChannelIndex: number(ParameterField.receiveChannelIndex),
          route: routeOverrides,
          endpoints: endpointOverrides,
          responseTimeoutSeconds: number(ParameterField.responseTimeoutSeconds),
          maxEntries: number(ParameterField.maxEntries),
        ),
      ),
      DiagnosticOperation.respond => RespondParameterRequest(
        profileId: id,
        overrides: RespondOverrides(
          budgets: budgetOverrides,
          sendChannelIndex: number(ParameterField.sendChannelIndex),
          receiveChannelIndex: number(ParameterField.receiveChannelIndex),
          route: routeOverrides,
          endpoints: endpointOverrides,
          listenDurationSeconds: number(ParameterField.listenDurationSeconds),
          maxEntries: number(ParameterField.maxEntries),
          maxResponses: number(ParameterField.maxResponses),
        ),
      ),
    };
  }

  String get routeHint {
    if (operation == DiagnosticOperation.listen) return '';
    try {
      final d = number(ParameterField.routeDescriptor), p = path;
      if (d == null || p == null) {
        return 'Route capacity requires a complete descriptor and path; inherited fields are checked by Preview parameters.';
      }
      if (p.any((b) => b < 0 || b > 255) || (d == 255 && p.isNotEmpty)) {
        return 'Invalid route.';
      }
      final bytes = Uint8List.fromList(p);
      final capacity = operation == DiagnosticOperation.send
          ? maxChannelDataPayloadLengthForRoute(routeDescriptor: d, path: bytes)
          : maxDiagnosticContentLengthForRoute(routeDescriptor: d, path: bytes);
      return 'Route capacity: $capacity ${operation == DiagnosticOperation.send ? 'payload' : 'diagnostic content'} bytes. Respond uses this explicit local return route.';
    } catch (_) {
      return 'Route is incomplete or invalid.';
    }
  }

  bool get composing => inputs.values.any(
    (c) => c.value.isComposingRangeValid && !c.value.composing.isCollapsed,
  );
  void dispose() {
    for (final c in inputs.values) {
      c.dispose();
    }
  }
}
