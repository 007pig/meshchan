import 'errors.dart';
import 'models/connection_profile.dart';
import 'models/effective_parameters.dart';
import 'profile_validation.dart';
import 'repositories/profile_repository.dart';
import 'repositories/settings_repository.dart';
import 'storage/storage.dart';
import 'validation.dart';

int _required(int? value) {
  requireValid(value != null);
  return value!;
}

ProfileBudgets _budgets(BudgetOverrides o, ProfileBudgets? p) => ProfileBudgets(
  requestTimeoutSeconds:
      o.requestTimeoutSeconds ?? p?.requestTimeoutSeconds ?? 5,
  initializationTimeoutSeconds:
      o.initializationTimeoutSeconds ?? p?.initializationTimeoutSeconds ?? 15,
  startupDelayMilliseconds:
      o.startupDelayMilliseconds ?? p?.startupDelayMilliseconds ?? 0,
  taskTimeoutSeconds: _required(o.taskTimeoutSeconds ?? p?.taskTimeoutSeconds),
);
ProfileRoute _route(RouteOverrides? o, ProfileRoute? p) => ProfileRoute(
  routeDescriptor: _required(o?.routeDescriptor ?? p?.routeDescriptor),
  path: o?.path ?? p?.path ?? const [],
);
ProfileTestEndpoints _endpoints(EndpointOverrides o, ProfileTestEndpoints? p) =>
    ProfileTestEndpoints(
      localTestId: _required(o.localTestId ?? p?.localTestId),
      peerTestId: _required(o.peerTestId ?? p?.peerTestId),
    );

/// One admission spans the snapshot, pure merge, validation and construction.
/// No public repository call is nested inside it, including after close starts.
Future<EffectiveParameters> resolveParameters(
  StorageHandle storage,
  EffectiveParameterRequest request,
) => storage.useDatabase((db) async {
  final profile = await db.transaction(() async {
    final id =
        request.profileId ?? (await readStoredSettings(db)).defaultProfileId;
    return id == null ? null : await readStoredProfile(db, id);
  });
  if (profile != null && profile.operation != request.operation) {
    throw const CoreException(CoreErrorCode.invalidInput);
  }
  final p = profile?.parameters;
  final ProfileParameters effective;
  final List<int>? content;
  switch (request) {
    case SendParameterRequest():
      final o = request.overrides;
      final saved = p as SendProfileParameters?;
      effective = SendProfileParameters(
        budgets: _budgets(o.budgets, saved?.budgets),
        sendChannelIndex: _required(
          o.sendChannelIndex ?? saved?.sendChannelIndex,
        ),
        route: _route(o.route, saved?.route),
        dataType: _required(o.dataType ?? saved?.dataType),
      );
      content = request.payload;
      requireValid(content != null);
    case ListenParameterRequest():
      final o = request.overrides;
      final saved = p as ListenProfileParameters?;
      effective = ListenProfileParameters(
        budgets: _budgets(o.budgets, saved?.budgets),
        receiveChannelIndex: _required(
          o.receiveChannelIndex ?? saved?.receiveChannelIndex,
        ),
        dataType: o.dataType == null ? saved?.dataType : o.dataType!.value,
        listenDurationSeconds: _required(
          o.listenDurationSeconds ?? saved?.listenDurationSeconds,
        ),
        maxEntries: o.maxEntries ?? saved?.maxEntries ?? 128,
      );
      content = null;
    case PingParameterRequest():
      final o = request.overrides;
      final saved = p as PingProfileParameters?;
      effective = PingProfileParameters(
        budgets: _budgets(o.budgets, saved?.budgets),
        sendChannelIndex: _required(
          o.sendChannelIndex ?? saved?.sendChannelIndex,
        ),
        receiveChannelIndex: _required(
          o.receiveChannelIndex ?? saved?.receiveChannelIndex,
        ),
        route: _route(o.route, saved?.route),
        endpoints: _endpoints(o.endpoints, saved?.endpoints),
        responseTimeoutSeconds: _required(
          o.responseTimeoutSeconds ?? saved?.responseTimeoutSeconds,
        ),
        maxEntries: o.maxEntries ?? saved?.maxEntries ?? 128,
      );
      content = request.content;
      requireValid(content != null);
    case RespondParameterRequest():
      final o = request.overrides;
      final saved = p as RespondProfileParameters?;
      effective = RespondProfileParameters(
        budgets: _budgets(o.budgets, saved?.budgets),
        sendChannelIndex: _required(
          o.sendChannelIndex ?? saved?.sendChannelIndex,
        ),
        receiveChannelIndex: _required(
          o.receiveChannelIndex ?? saved?.receiveChannelIndex,
        ),
        route: _route(o.route, saved?.route),
        endpoints: _endpoints(o.endpoints, saved?.endpoints),
        listenDurationSeconds: _required(
          o.listenDurationSeconds ?? saved?.listenDurationSeconds,
        ),
        maxEntries: o.maxEntries ?? saved?.maxEntries ?? 128,
        maxResponses: o.maxResponses ?? saved?.maxResponses ?? 1,
      );
      content = null;
  }
  validateProfileParameters(effective);
  if (content != null) {
    for (final byte in content) {
      requireValid(byte >= 0 && byte <= 255);
    }
    final route = switch (effective) {
      SendProfileParameters() => effective.route,
      PingProfileParameters() => effective.route,
      _ => throw StateError('Unexpected content operation.'),
    };
    requireValid(
      content.length <=
          routeCapacity(route, diagnostic: effective is PingProfileParameters),
    );
  }
  return EffectiveParameters(
    profileId: profile?.id,
    parameters: effective,
    content: content,
  );
});
