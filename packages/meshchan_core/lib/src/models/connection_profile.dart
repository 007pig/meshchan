import '../validation.dart';
import '../values.dart';

/// Named units match existing command budgets. Full effective-parameter and
/// route/capacity validation runs at repository and resolver boundaries.
/// Request/initialization/task seconds must be 1..86400; startup milliseconds
/// must be 0..86399999 and strictly less than initialization milliseconds.
final class ProfileBudgets {
  const ProfileBudgets({
    required this.taskTimeoutSeconds,
    this.requestTimeoutSeconds = 5,
    this.initializationTimeoutSeconds = 15,
    this.startupDelayMilliseconds = 0,
  });
  final int requestTimeoutSeconds;
  final int initializationTimeoutSeconds;
  final int startupDelayMilliseconds;
  final int taskTimeoutSeconds;
}

/// Local configuration only; diagnostic snapshots retain the byte count.
/// Repository/resolver validation uses the public communication helper.
final class ProfileRoute {
  ProfileRoute({required this.routeDescriptor, Iterable<int> path = const []})
    : path = List.unmodifiable(path) {
    requireValid(routeDescriptor >= 0 && routeDescriptor <= 255);
    requireValid(this.path.every((byte) => byte >= 0 && byte <= 255));
  }
  final int routeDescriptor;
  final List<int> path;
}

/// Local test labels, never authenticated identities or diagnostic history.
/// Complete preset validation requires distinct, nonzero uint32 values.
final class ProfileTestEndpoints {
  const ProfileTestEndpoints({
    required this.localTestId,
    required this.peerTestId,
  });
  final int localTestId;
  final int peerTestId;
}

sealed class ProfileParameters {
  const ProfileParameters({required this.budgets});
  final ProfileBudgets budgets;
  DiagnosticOperation get operation;
}

/// Send slot is uint8; dataType is 1..65535. Content is supplied per invocation.
final class SendProfileParameters extends ProfileParameters {
  const SendProfileParameters({
    required super.budgets,
    required this.sendChannelIndex,
    required this.route,
    required this.dataType,
  });
  final int sendChannelIndex;
  final ProfileRoute route;
  final int dataType;
  @override
  DiagnosticOperation get operation => DiagnosticOperation.send;
}

/// Receive slot is uint8; dataType is an optional uint16 filter (null = all).
/// Listen seconds are 1..86400; maxEntries is 1..4096.
final class ListenProfileParameters extends ProfileParameters {
  const ListenProfileParameters({
    required super.budgets,
    required this.receiveChannelIndex,
    required this.listenDurationSeconds,
    this.dataType,
    this.maxEntries = 128,
  });
  final int receiveChannelIndex;
  final int? dataType;
  final int listenDurationSeconds;
  final int maxEntries;
  @override
  DiagnosticOperation get operation => DiagnosticOperation.listen;
}

/// Slots are uint8; response seconds are 1..86400; maxEntries is 1..4096.
/// The diagnostic data type is fixed; PING content is supplied per invocation.
final class PingProfileParameters extends ProfileParameters {
  const PingProfileParameters({
    required super.budgets,
    required this.sendChannelIndex,
    required this.receiveChannelIndex,
    required this.route,
    required this.endpoints,
    required this.responseTimeoutSeconds,
    this.maxEntries = 128,
  });
  final int sendChannelIndex;
  final int receiveChannelIndex;
  final ProfileRoute route;
  final ProfileTestEndpoints endpoints;
  final int responseTimeoutSeconds;
  final int maxEntries;
  @override
  DiagnosticOperation get operation => DiagnosticOperation.ping;
}

/// Slots are uint8; listen seconds are 1..86400. Entry/response limits are
/// 1..4096. The route is this endpoint's explicit local return route.
final class RespondProfileParameters extends ProfileParameters {
  const RespondProfileParameters({
    required super.budgets,
    required this.sendChannelIndex,
    required this.receiveChannelIndex,
    required this.route,
    required this.endpoints,
    required this.listenDurationSeconds,
    this.maxEntries = 128,
    this.maxResponses = 1,
  });
  final int sendChannelIndex;
  final int receiveChannelIndex;
  final ProfileRoute route;
  final ProfileTestEndpoints endpoints;
  final int listenDurationSeconds;
  final int maxEntries;
  final int maxResponses;
  @override
  DiagnosticOperation get operation => DiagnosticOperation.respond;
}

final class ProfileContent {
  ProfileContent({
    required this.name,
    required this.parameters,
    this.portHint,
  }) {
    requireValid(name.trim().isNotEmpty);
    requireValid(portHint == null || portHint!.trim().isNotEmpty);
  }
  final String name;
  final ProfileParameters parameters;

  /// A hint only; never satisfies the invocation's explicit --port requirement.
  final String? portHint;
}

final class ConnectionProfile {
  ConnectionProfile({
    required this.id,
    required this.content,
    required DateTime updatedAt,
  }) : updatedAt = requireUtc(updatedAt);
  final LocalId id;
  final ProfileContent content;
  final DateTime updatedAt;
  String get name => content.name;
  String? get portHint => content.portHint;
  ProfileParameters get parameters => content.parameters;
  DiagnosticOperation get operation => parameters.operation;
}
