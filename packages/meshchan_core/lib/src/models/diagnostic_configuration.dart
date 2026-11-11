import '../values.dart';
import 'connection_profile.dart' show ProfileBudgets;

/// Whitelisted route summary: no exact path bytes.
final class DiagnosticRoute {
  const DiagnosticRoute({
    required this.routeDescriptor,
    required this.pathByteCount,
  });
  final int routeDescriptor;
  final int pathByteCount;
}

/// Immutable safe effective configuration, never a profile or live session.
/// No port, profile name, endpoint ID, nonce, content, or secret is accepted.
sealed class DiagnosticConfiguration {
  const DiagnosticConfiguration({required this.budgets});
  final ProfileBudgets budgets;
  int get appTargetVersion => 3;
  int get maxQueuedCommands => 8;
  DiagnosticOperation get operation;
}

final class SendConfiguration extends DiagnosticConfiguration {
  const SendConfiguration({
    required super.budgets,
    required this.sendChannelIndex,
    required this.dataType,
    required this.route,
    required this.payloadByteLength,
  });
  final int sendChannelIndex;
  final int dataType;
  final DiagnosticRoute route;
  final int payloadByteLength;
  @override
  DiagnosticOperation get operation => DiagnosticOperation.send;
}

final class ListenConfiguration extends DiagnosticConfiguration {
  const ListenConfiguration({
    required super.budgets,
    required this.receiveChannelIndex,
    required this.listenDurationSeconds,
    required this.maxEntries,
    this.dataType,
  });
  final int receiveChannelIndex;
  final int? dataType;
  final int listenDurationSeconds;
  final int maxEntries;
  int get maxReadsPerBatch => 8;
  @override
  DiagnosticOperation get operation => DiagnosticOperation.listen;
}

sealed class TaskConfiguration extends DiagnosticConfiguration {
  const TaskConfiguration({
    required super.budgets,
    required this.sendChannelIndex,
    required this.receiveChannelIndex,
    required this.route,
    required this.maxEntries,
  });
  final int sendChannelIndex;
  final int receiveChannelIndex;
  final DiagnosticRoute route;
  final int maxEntries;
  int get diagnosticWireVersion => 1;
  int get diagnosticDataType => 65535;
  int get maxReadsPerBatch => 8;
}

final class PingConfiguration extends TaskConfiguration {
  const PingConfiguration({
    required super.budgets,
    required super.sendChannelIndex,
    required super.receiveChannelIndex,
    required super.route,
    required super.maxEntries,
    required this.responseTimeoutSeconds,
    required this.contentByteLength,
  });
  final int responseTimeoutSeconds;
  final int contentByteLength;
  @override
  DiagnosticOperation get operation => DiagnosticOperation.ping;
}

final class RespondConfiguration extends TaskConfiguration {
  const RespondConfiguration({
    required super.budgets,
    required super.sendChannelIndex,
    required super.receiveChannelIndex,
    required super.route,
    required super.maxEntries,
    required this.listenDurationSeconds,
    required this.maxResponses,
  });
  final int listenDurationSeconds;
  final int maxResponses;
  int get cacheCapacity => 128;
  int get cacheTtlUs => 120000000;
  @override
  DiagnosticOperation get operation => DiagnosticOperation.respond;
}
