import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshcore_link/meshcore_link.dart' show CompanionTransport;

/// Delegates every operation to real storage, recording only host boundaries.
final class AuditedStorage implements CoreStorage {
  AuditedStorage(this.inner) {
    history = AuditedHistory(inner.history, () => closing, events);
  }
  final CoreStorage inner;
  final events = <String>[];
  bool closing = false;
  int closes = 0;
  int planFactories = 0;
  int transportFactories = 0;
  EffectiveParameterRequest? request;
  EffectiveParameters? effective;
  RecordedOperation? operation;
  void Function(RecordedOperation)? onRecord;
  @override
  StorageState get state => inner.state;
  @override
  DraftRepository get drafts => inner.drafts;
  @override
  ProfileRepository get profiles => inner.profiles;
  @override
  SettingsRepository get settings => inner.settings;
  @override
  late final DiagnosticHistory history;
  @override
  Future<EffectiveParameters> resolveParameters(
    EffectiveParameterRequest value,
  ) async {
    events.add('resolve');
    request = value;
    return effective = await inner.resolveParameters(value);
  }

  @override
  RecordedOperation record({
    required EffectiveParameters parameters,
    required String appVersion,
    required CompanionTransport Function() createTransport,
    List<RecordingSubscription> subscriptions = const [],
  }) {
    events.add('record');
    final op = inner.record(
      parameters: parameters,
      appVersion: appVersion,
      createTransport: () {
        transportFactories++;
        return createTransport();
      },
      subscriptions: [
        for (final plan in subscriptions)
          RecordingSubscription(
            stage: plan.stage,
            subscribe: (cancel) {
              planFactories++;
              return plan.subscribe(cancel);
            },
          ),
      ],
    );
    operation = op;
    onRecord?.call(op);
    return op;
  }

  @override
  Future<void> close() {
    closes++;
    closing = true;
    events.add('close');
    return inner.close();
  }
}

final class AuditedHistory implements DiagnosticHistory {
  AuditedHistory(this.inner, this.closing, this.events);
  final DiagnosticHistory inner;
  final bool Function() closing;
  final List<String> events;
  void check(String name) {
    if (closing()) throw StateError('Public I/O after close: $name');
    events.add(name);
  }

  @override
  Future<DiagnosticRun> read(LocalId id) {
    check('read');
    return inner.read(id);
  }

  @override
  Future<Page<DiagnosticRun, HistoryCursor>> query({
    HistoryQuery? filter,
    PageSize? size,
    HistoryCursor? after,
  }) {
    check('query');
    return inner.query(filter: filter, size: size, after: after);
  }

  @override
  Future<void> delete(LocalId id) {
    check('delete');
    return inner.delete(id);
  }

  @override
  Future<DiagnosticSummaryPage> exportSummary({
    HistoryQuery? filter,
    PageSize? size,
    HistoryCursor? after,
  }) {
    check('export');
    return inner.exportSummary(filter: filter, size: size, after: after);
  }

  @override
  Future<HistoryMaintenanceReport> maintain() {
    check('maintain');
    return inner.maintain();
  }

  @override
  Future<HistoryMaintenanceReport> waitForMaintenance() {
    check('wait');
    return inner.waitForMaintenance();
  }

  @override
  HistoryMaintenanceReport? get latestMaintenance => inner.latestMaintenance;
  @override
  HistoryMaintenanceReport? get unacknowledgedFailure =>
      inner.unacknowledgedFailure;
  @override
  int get unacknowledgedFailureCount => inner.unacknowledgedFailureCount;
  @override
  void acknowledgeMaintenanceFailures() {
    check('acknowledge');
    inner.acknowledgeMaintenanceFailures();
  }
}
