import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';

import 'errors.dart';
import 'models/connection_profile.dart';
import 'models/effective_parameters.dart';
import 'validation.dart';

/// Complete business validation, independent of DTO construction and device I/O.
void validateProfileContent(ProfileContent content) {
  requireValid(content.name.trim().isNotEmpty);
  validateUnicode(content.name);
  // Schema 1 checks length(trim(name)): SQLite trims only U+0020 by default,
  // and length stops at the first NUL. Reject exactly those NUL-containing
  // names whose prefix disappears, preserving compatible text verbatim.
  final nul = content.name.indexOf('\u0000');
  requireValid(
    nul < 0 || content.name.codeUnits.take(nul).any((unit) => unit != 0x20),
  );
  final hint = content.portHint;
  if (hint != null) {
    requireValid(hint.trim().isNotEmpty);
    validateUnicode(hint);
  }
  validateProfileParameters(content.parameters);
}

void _range(int value, int min, int max) =>
    requireValid(value >= min && value <= max);
void _seconds(int value) => _range(value, 1, 86400);
void _channel(int value) => _range(value, 0, 255);
void _entries(int value) => _range(value, 1, 4096);

void _endpoints(ProfileTestEndpoints endpoints) {
  _range(endpoints.localTestId, 1, 0xffffffff);
  _range(endpoints.peerTestId, 1, 0xffffffff);
  requireValid(endpoints.localTestId != endpoints.peerTestId);
}

/// Validates the actual route through link's public pure capacity helper.
/// Catch only the helper's argument failures, never database/dependency errors.
int routeCapacity(ProfileRoute route, {required bool diagnostic}) {
  _range(route.routeDescriptor, 0, 255);
  for (final byte in route.path) {
    _range(byte, 0, 255);
  }
  final path = Uint8List.fromList(route.path);
  try {
    return diagnostic
        ? maxDiagnosticContentLengthForRoute(
            routeDescriptor: route.routeDescriptor,
            path: path,
          )
        : maxChannelDataPayloadLengthForRoute(
            routeDescriptor: route.routeDescriptor,
            path: path,
          );
  } on ArgumentError {
    throw const CoreException(CoreErrorCode.invalidInput);
  }
}

void validateProfileParameters(ProfileParameters parameters) {
  final budgets = parameters.budgets;
  _seconds(budgets.requestTimeoutSeconds);
  _seconds(budgets.initializationTimeoutSeconds);
  _seconds(budgets.taskTimeoutSeconds);
  _range(budgets.startupDelayMilliseconds, 0, 86399999);
  requireValid(
    budgets.startupDelayMilliseconds <
        budgets.initializationTimeoutSeconds * 1000,
  );
  switch (parameters) {
    case SendProfileParameters():
      _channel(parameters.sendChannelIndex);
      _range(parameters.dataType, 1, 65535);
      routeCapacity(parameters.route, diagnostic: false);
    case ListenProfileParameters():
      _channel(parameters.receiveChannelIndex);
      if (parameters.dataType != null) _range(parameters.dataType!, 0, 65535);
      _seconds(parameters.listenDurationSeconds);
      _entries(parameters.maxEntries);
    case PingProfileParameters():
      _channel(parameters.sendChannelIndex);
      _channel(parameters.receiveChannelIndex);
      _endpoints(parameters.endpoints);
      _seconds(parameters.responseTimeoutSeconds);
      _entries(parameters.maxEntries);
      routeCapacity(parameters.route, diagnostic: true);
    case RespondProfileParameters():
      _channel(parameters.sendChannelIndex);
      _channel(parameters.receiveChannelIndex);
      _endpoints(parameters.endpoints);
      _seconds(parameters.listenDurationSeconds);
      _entries(parameters.maxEntries);
      _entries(parameters.maxResponses);
      routeCapacity(parameters.route, diagnostic: true);
  }
}

/// Revalidates publicly constructible execution values without inventing a
/// profile. Both the resolver and recorder use this exact content boundary.
void validateEffectiveParameters(EffectiveParameters value) {
  final parameters = value.parameters;
  validateProfileParameters(parameters);
  final needsContent =
      parameters is SendProfileParameters ||
      parameters is PingProfileParameters;
  requireValid(needsContent == (value.content != null));
  final content = value.content;
  if (content == null) return;
  requireValid(content.every((byte) => byte >= 0 && byte <= 255));
  final route = switch (parameters) {
    SendProfileParameters() => parameters.route,
    PingProfileParameters() => parameters.route,
    _ => throw const CoreException(CoreErrorCode.invalidInput),
  };
  requireValid(
    content.length <=
        routeCapacity(route, diagnostic: parameters is PingProfileParameters),
  );
}
