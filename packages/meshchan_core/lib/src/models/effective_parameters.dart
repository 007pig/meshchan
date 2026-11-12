import '../values.dart';
import 'connection_profile.dart';

/// Nullable fields mean absent; these values never insert parser defaults.
final class BudgetOverrides {
  const BudgetOverrides({
    this.requestTimeoutSeconds,
    this.initializationTimeoutSeconds,
    this.startupDelayMilliseconds,
    this.taskTimeoutSeconds,
  });
  final int? requestTimeoutSeconds;
  final int? initializationTimeoutSeconds;
  final int? startupDelayMilliseconds;
  final int? taskTimeoutSeconds;
}

/// Descriptor and path merge independently. An explicit empty path replaces it.
/// Bytes are copied before asynchronous resolution, then validated without loss.
final class RouteOverrides {
  RouteOverrides({this.routeDescriptor, Iterable<int>? path})
    : path = path == null ? null : List.unmodifiable(path);
  final int? routeDescriptor;
  final List<int>? path;
}

final class EndpointOverrides {
  const EndpointOverrides({this.localTestId, this.peerTestId});
  final int? localTestId;
  final int? peerTestId;
}

/// Null override object means inherit; DataTypeOverride(null) clears a filter.
/// Zero is a valid explicit listen filter. Send has a separate nonnull field.
final class DataTypeOverride {
  const DataTypeOverride(this.value);
  final int? value;
}

final class SendOverrides {
  const SendOverrides({
    this.budgets = const BudgetOverrides(),
    this.sendChannelIndex,
    this.route,
    this.dataType,
  });
  final BudgetOverrides budgets;
  final int? sendChannelIndex;
  final RouteOverrides? route;
  final int? dataType;
}

final class ListenOverrides {
  const ListenOverrides({
    this.budgets = const BudgetOverrides(),
    this.receiveChannelIndex,
    this.dataType,
    this.listenDurationSeconds,
    this.maxEntries,
  });
  final BudgetOverrides budgets;
  final int? receiveChannelIndex;
  final DataTypeOverride? dataType;
  final int? listenDurationSeconds;
  final int? maxEntries;
}

final class PingOverrides {
  const PingOverrides({
    this.budgets = const BudgetOverrides(),
    this.sendChannelIndex,
    this.receiveChannelIndex,
    this.route,
    this.endpoints = const EndpointOverrides(),
    this.responseTimeoutSeconds,
    this.maxEntries,
  });
  final BudgetOverrides budgets;
  final int? sendChannelIndex;
  final int? receiveChannelIndex;
  final RouteOverrides? route;
  final EndpointOverrides endpoints;
  final int? responseTimeoutSeconds;
  final int? maxEntries;
}

final class RespondOverrides {
  const RespondOverrides({
    this.budgets = const BudgetOverrides(),
    this.sendChannelIndex,
    this.receiveChannelIndex,
    this.route,
    this.endpoints = const EndpointOverrides(),
    this.listenDurationSeconds,
    this.maxEntries,
    this.maxResponses,
  });
  final BudgetOverrides budgets;
  final int? sendChannelIndex;
  final int? receiveChannelIndex;
  final RouteOverrides? route;
  final EndpointOverrides endpoints;
  final int? listenDurationSeconds;
  final int? maxEntries;
  final int? maxResponses;
}

/// The subtype explicitly selects the operation and its applicable fields.
/// No request accepts a port: a hint never authorizes a device connection.
sealed class EffectiveParameterRequest {
  const EffectiveParameterRequest({this.profileId});
  final LocalId? profileId;
  DiagnosticOperation get operation;
}

final class SendParameterRequest extends EffectiveParameterRequest {
  SendParameterRequest({
    super.profileId,
    this.overrides = const SendOverrides(),
    Iterable<int>? payload,
  }) : payload = payload == null ? null : List.unmodifiable(payload);
  final SendOverrides overrides;

  /// Invocation bytes only. Null is missing; an explicitly empty list is valid.
  final List<int>? payload;
  @override
  DiagnosticOperation get operation => DiagnosticOperation.send;
}

final class ListenParameterRequest extends EffectiveParameterRequest {
  const ListenParameterRequest({
    super.profileId,
    this.overrides = const ListenOverrides(),
  });
  final ListenOverrides overrides;
  @override
  DiagnosticOperation get operation => DiagnosticOperation.listen;
}

final class PingParameterRequest extends EffectiveParameterRequest {
  PingParameterRequest({
    super.profileId,
    this.overrides = const PingOverrides(),
    Iterable<int>? content,
  }) : content = content == null ? null : List.unmodifiable(content);
  final PingOverrides overrides;
  final List<int>? content;
  @override
  DiagnosticOperation get operation => DiagnosticOperation.ping;
}

final class RespondParameterRequest extends EffectiveParameterRequest {
  const RespondParameterRequest({
    super.profileId,
    this.overrides = const RespondOverrides(),
  });
  final RespondOverrides overrides;
  @override
  DiagnosticOperation get operation => DiagnosticOperation.respond;
}

/// Immutable execution input, NOT a safe diagnostic-history snapshot.
/// Contains local route/test labels and optional raw send payload/PING content.
/// 1C.6 must project only its allowed safe fields before recording history.
final class EffectiveParameters {
  EffectiveParameters({
    required this.profileId,
    required this.parameters,
    Iterable<int>? content,
  }) : content = content == null ? null : List.unmodifiable(content);
  final LocalId? profileId;
  final ProfileParameters parameters;

  /// Send payload or PING content; absent for listen/respond. Opaque bytes.
  final List<int>? content;
  DiagnosticOperation get operation => parameters.operation;
}
