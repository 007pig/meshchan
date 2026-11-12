import 'dart:io';

import 'package:meshchan_core/meshchan_core.dart';

/// Offline host example. The host supplies its directory and chooses how to
/// display/store the returned JSON and independent maintenance reports. An
/// empty directory yields valid empty selections. No hardware is required.
Future<
  ({
    DiagnosticSummaryPage summary,
    HistoryMaintenanceReport maintenance,
    HistoryMaintenanceReport? unacknowledgedFailure,
  })
>
inspectHistory(
  Directory hostDataDirectory, {
  LocalId? explicitlySelectedRunToDelete,
}) async {
  final storage = await CoreStorage.open(dataDirectory: hostDataDirectory);
  try {
    final history = storage.history;
    final startup = history.latestMaintenance!;
    // A host can display startup.error independently of opening or saving.
    if (startup.state == HistoryMaintenanceState.failed) {
      assert(history.unacknowledgedFailure != null);
    }
    final filter = HistoryQuery(
      operation: DiagnosticOperation.ping,
      preparedFromInclusive: DateTime.utc(2026, 11, 1),
    );
    final first = await history.query(filter: filter, size: PageSize(50));
    if (first.nextCursor case final cursor?) {
      await history.query(filter: filter, size: PageSize(50), after: cursor);
    }
    final summary = await history.exportSummary(
      filter: filter,
      size: PageSize(50),
    );
    // Continue exports explicitly with summary.nextCursor and the same filter.
    if (explicitlySelectedRunToDelete case final id?) {
      // The host must select a particular run. Core checks current eligibility
      // and active protection atomically; handle conflict/not_found as needed.
      await history.delete(id);
    }
    await history.waitForMaintenance();
    final maintenance = await history.maintain();
    return (
      summary: summary,
      maintenance: maintenance,
      unacknowledgedFailure: history.unacknowledgedFailure,
    );
    // After displaying/handling failures, a long-lived host may explicitly call
    // history.acknowledgeMaintenanceFailures(). Success never acknowledges them.
  } finally {
    await storage.close();
  }
}
