import 'dart:async';

import 'package:material_ui/material_ui.dart' hide Page;
import 'package:meshchan_core/meshchan_core.dart';

import '../runtime/controller.dart';
import '../runtime/protocol.dart';

/// Accept only UTC Z timestamps with seconds and up to six fractional digits.
/// Round-trip fields reject DateTime.parse's otherwise silent date overflow.
DateTime? parseHistoryUtc(String text) {
  if (text.isEmpty) return null;
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?Z$',
  ).firstMatch(text);
  if (match == null) throw const FormatException('UTC required');
  final v = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final result = DateTime.parse(text);
  if ([
        result.year,
        result.month,
        result.day,
        result.hour,
        result.minute,
        result.second,
      ].join(',') !=
      v.join(',')) {
    throw const FormatException('Invalid date');
  }
  return result;
}

/// Application-owned bounded page and identity-bound actions. No profile reads,
/// device calls, polling, or Widget-owned asynchronous work.
final class HistoryModel extends ChangeNotifier {
  HistoryModel(this.runtime) {
    from.addListener(_formChanged);
    until.addListener(_formChanged);
    _states = runtime.changes.listen((s) {
      if (s.maintenance != null) _maintenance = s.maintenance;
      _notify();
    });
  }
  final AppRuntime runtime;
  final from = TextEditingController(), until = TextEditingController();
  late final StreamSubscription<RuntimeSnapshot> _states;
  DiagnosticOperation? operation;
  DiagnosticRecordState? recordState;
  int size = 50;
  HistorySelection? selection;
  Page<DiagnosticRun, HistoryCursor>? page;
  final _previous = <HistoryCursor?>[];
  bool loading = false,
      detailLoading = false,
      deleting = false,
      confirming = false;
  bool maintenanceStarting = false,
      maintenanceRefreshing = false,
      acknowledging = false;
  bool blocked = false, _disposed = false;
  bool visible = false;
  void show(bool value) {
    visible = value;
    _notify();
  }

  int _pageGeneration = 0,
      _detailGeneration = 0,
      _actionGeneration = 0,
      _maintenanceId = 0;
  String? selectedId, notice, formError;
  DiagnosticRun? detail;
  RuntimeFault? pageError, detailError, deleteError, maintenanceError;
  String? deletedId, deleteTargetId;
  MaintenanceSnapshot? _maintenance;
  MaintenanceSnapshot? get maintenance =>
      _maintenance ?? runtime.snapshot.maintenance;
  MaintenanceActionSnapshot? get maintenanceAction =>
      runtime.snapshot.maintenanceAction;
  bool get composing => [
    from,
    until,
  ].any((c) => c.value.composing.isValid && !c.value.composing.isCollapsed);
  bool get available => !blocked && runtime.ordinaryAdmissionOpen;
  bool allowChange() {
    if (composing) {
      notice = 'Finish or cancel text composition before this action.';
      _notify();
      return false;
    }
    if (notice != null) {
      notice = null;
      _notify();
    }
    return available;
  }

  String _key(HistoryQuery? q, int n) =>
      '${q?.operation}|${q?.recordState}|${q?.preparedFromInclusive?.toIso8601String()}|${q?.preparedUntilExclusive?.toIso8601String()}|$n';
  HistoryQuery _filter() => HistoryQuery(
    operation: operation,
    recordState: recordState,
    preparedFromInclusive: parseHistoryUtc(from.text),
    preparedUntilExclusive: parseHistoryUtc(until.text),
  );
  bool get unapplied {
    try {
      return selection == null ||
          _key(_filter(), size) != _key(selection!.filter, selection!.size);
    } catch (_) {
      return true;
    }
  }

  // Cached rows survive a failed request, but their cursors do not belong to
  // the attempted selection until that selection has loaded successfully.
  bool get _pageReady =>
      !loading && pageError == null && selection != null && page != null;
  bool get canExport => available && _pageReady && !unapplied;
  bool get canNext => _pageReady && page!.nextCursor != null;
  bool get canPrevious => _pageReady && _previous.isNotEmpty;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _formChanged() {
    formError = null;
    _notify();
  }

  void formChanged() => _formChanged();
  Future<void> enter() async {
    if (selection == null && !loading) await apply();
  }

  Future<void> apply() async {
    if (!allowChange()) return;
    try {
      PageSize(size);
      final next = HistorySelection(filter: _filter(), size: size);
      formError = null;
      _previous.clear();
      await _load(next);
    } catch (_) {
      formError = 'Use valid UTC timestamps YYYY-MM-DDTHH:mm:ss[.ffffff]Z with from < until, and a page size from 1 to 200.';
      _notify();
    }
  }

  Future<void> reset() async {
    if (!allowChange()) return;
    from.clear();
    until.clear();
    operation = null;
    recordState = null;
    size = 50;
    await apply();
  }

  Future<void> refresh() async {
    if (!allowChange() || selection == null) return;
    await _load(selection!);
  }

  Future<void> first() async {
    if (!allowChange() || selection == null) return;
    _previous.clear();
    await _load(
      HistorySelection(filter: selection!.filter, size: selection!.size),
    );
  }

  Future<void> next() async {
    if (!allowChange() || !canNext) return;
    _previous.add(selection!.after);
    await _load(
      HistorySelection(
        filter: selection!.filter,
        size: selection!.size,
        after: page!.nextCursor,
      ),
    );
  }

  Future<void> previous() async {
    if (!allowChange() || !canPrevious) return;
    await _load(
      HistorySelection(
        filter: selection!.filter,
        size: selection!.size,
        after: _previous.removeLast(),
      ),
    );
  }

  Future<void> _load(HistorySelection next) async {
    final generation = ++_pageGeneration;
    selection = next;
    loading = true;
    pageError = null;
    _notify();
    try {
      final result =
          await runtime.historyRequest(QueryHistory(next)) as HistoryPageValue;
      if (generation != _pageGeneration) return;
      page = result.page;
    } catch (e) {
      if (generation == _pageGeneration) pageError = RuntimeFault.from(e);
    } finally {
      if (generation == _pageGeneration) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> select(String id) async {
    if (!allowChange()) return;
    final generation = ++_detailGeneration;
    selectedId = id;
    detail = null;
    detailError = null;
    detailLoading = true;
    _notify();
    try {
      final value =
          await runtime.historyRequest(ReadHistory(id)) as HistoryRunValue;
      if (generation == _detailGeneration && selectedId == id) {
        detail = value.run;
      }
    } catch (e) {
      if (generation == _detailGeneration) detailError = RuntimeFault.from(e);
    } finally {
      if (generation == _detailGeneration) {
        detailLoading = false;
        _notify();
      }
    }
  }

  Future<void> deleteSelected(
    Future<bool> Function(DiagnosticRun) confirm,
  ) async {
    if (!allowChange() || deleting || confirming || detail == null) return;
    final target = detail!;
    final action = ++_actionGeneration;
    confirming = true;
    _notify();
    bool accepted;
    try {
      accepted = await confirm(target);
    } finally {
      confirming = false;
      _notify();
    }
    if (!accepted || !allowChange()) return;
    deleteTargetId = target.runId.value;
    deleting = true;
    deleteError = null;
    deletedId = null;
    _notify();
    try {
      await runtime.historyRequest(DeleteHistory(target.runId.value));
      if (action != _actionGeneration) return;
      deletedId = target.runId.value;
      if (selectedId == deletedId) {
        ++_detailGeneration;
        detail = null;
        detailLoading = false;
        detailError = const RuntimeFault(core: CoreErrorCode.notFound);
      }
      // Keep the selected identity. Independent maintenance can remove more rows.
      if (available && selection != null) await _load(selection!);
    } catch (e) {
      if (action == _actionGeneration) deleteError = RuntimeFault.from(e);
    } finally {
      if (action == _actionGeneration) {
        deleting = false;
        _notify();
      }
    }
  }

  Future<void> refreshMaintenance() async {
    if (!allowChange() || maintenanceRefreshing) return;
    maintenanceRefreshing = true;
    maintenanceError = null;
    _notify();
    try {
      final value = await runtime.historyRequest(
        const ReadMaintenanceStatus(),
      ) as MaintenanceValue;
      _maintenance = value.snapshot;
    } catch (e) {
      maintenanceError = RuntimeFault.from(e);
    } finally {
      maintenanceRefreshing = false;
      _notify();
    }
  }

  Future<void> maintain() async {
    if (!allowChange() ||
        maintenanceStarting ||
        maintenanceAction?.done == false) {
      return;
    }
    maintenanceStarting = true;
    maintenanceError = null;
    _notify();
    try {
      await runtime.historyRequest(StartMaintenance(++_maintenanceId));
    } catch (e) {
      maintenanceError = RuntimeFault.from(e);
    } finally {
      maintenanceStarting = false;
      _notify();
    }
  }

  Future<void> acknowledge() async {
    if (!allowChange() || acknowledging || maintenance == null) return;
    final seen = maintenance!;
    final generation = runtime.snapshot.generation;
    acknowledging = true;
    maintenanceError = null;
    _notify();
    try {
      final value = await runtime.historyRequest(
        AcknowledgeMaintenance(generation, seen.revision, seen.failureCount),
      ) as MaintenanceValue;
      _maintenance = value.snapshot;
    } catch (e) {
      maintenanceError = RuntimeFault.from(e);
      _maintenance = runtime.snapshot.maintenance;
    } finally {
      acknowledging = false;
      _notify();
    }
  }

  void setBlocked(bool value) {
    blocked = value;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_states.cancel());
    from.dispose();
    until.dispose();
    super.dispose();
  }
}
