import 'dart:async';

import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_app/history/model.dart';
import 'package:meshchan_app/diagnostics/outcomes.dart';
import 'package:meshchan_app/history/view.dart';
import 'package:meshchan_app/export/coordinator.dart';
import 'package:meshchan_app/runtime/protocol.dart';

import 'support/draft_runtime.dart';

DiagnosticRun historyRun(
  int n, {
  DiagnosticConfiguration? configuration,
  LogicalSummary? result,
  DiagnosticRecordState state = DiagnosticRecordState.settled,
}) => DiagnosticRun(
  runId: LocalId(n.toRadixString(16).padLeft(32, '0')),
  appVersion: 'fixture',
  configuration:
      configuration ??
      const SendConfiguration(
        budgets: ProfileBudgets(taskTimeoutSeconds: 10),
        sendChannelIndex: 0,
        dataType: 1,
        route: DiagnosticRoute(routeDescriptor: 255, pathByteCount: 0),
        payloadByteLength: 0,
      ),
  preparedAt: DateTime.utc(2026, 11, 14),
  result: result,
  recordState: state,
);

void main() {
  test(
    'strict UTC grammar rejects timezone omission, invalid dates and overflow',
    () {
      expect(parseHistoryUtc(''), null);
      expect(parseHistoryUtc('2026-11-14T01:02:03.123456Z')!.microsecond, 456);
      for (final value in [
        '2026-02-29T00:00:00Z',
        '2026-13-01T00:00:00Z',
        '2026-01-01T24:00:00Z',
        '2026-01-01T00:00:60Z',
        '2026-01-01',
        '2026-01-01T00:00:00',
        '2026-01-01T00:00:00+00:00',
        '2026-01-01T00:00:00Z\n',
      ]) {
        expect(
          () => parseHistoryUtc(value),
          throwsFormatException,
          reason: value,
        );
      }
    },
  );
  test('applied selection, current input cursor, navigation and failed page are distinct', () async {
    final r = DraftRuntime(), m = HistoryModel(DraftRuntime());
    m.dispose();
    final model = HistoryModel(r);
    final queries = <HistorySelection>[];
    final cursor = HistoryCursor(
      preparedAt: historyRun(1).preparedAt,
      runId: historyRun(1).runId,
    );
    r.onHistory = (request) async {
      final s = (request as QueryHistory).selection;
      queries.add(s);
      return HistoryPageValue(
        Page(
          items: [historyRun(1)],
          nextCursor: s.after == null ? cursor : null,
        ),
      );
    };
    await model.enter();
    expect(queries.single.size, 50);
    expect(model.canExport, true);
    model.from.text = '2026-11-14T00:00:00Z';
    expect(model.canExport, false);
    await model.apply();
    expect(
      model.selection!.filter!.preparedFromInclusive,
      DateTime.utc(2026, 11, 14),
    );
    await model.next();
    expect(identical(model.selection!.after, cursor), true);
    expect(model.page!.nextCursor, null);
    await model.refresh();
    expect(queries.last.after, cursor);
    await model.previous();
    expect(model.selection!.after, null);
    model.size = 200;
    await model.apply();
    expect(queries.last.size, 200);
    model.until.text = model.from.text;
    await model.apply();
    expect(model.formError, isNotNull);
    expect(model.canExport, false);
    model.until.clear();
    await model.apply();
    expect(model.canExport, true);
    r.onHistory = (_) async =>
        throw const CoreException(CoreErrorCode.databaseCorrupt);
    await model.refresh();
    expect(model.pageError!.core, CoreErrorCode.databaseCorrupt);
    expect(model.canExport, false);
    expect(model.page!.items, isNotEmpty);
    model.dispose();
    await r.states.close();
  });
  test(
    'failed filter and size application cannot reuse a cached continuation',
    () async {
      final runtime = DraftRuntime();
      final model = HistoryModel(runtime);
      addTearDown(model.dispose);
      addTearDown(runtime.states.close);
      final queries = <HistorySelection>[];
      final oldCursor = HistoryCursor(
        preparedAt: historyRun(1).preparedAt,
        runId: historyRun(1).runId,
      );
      final freshCursor = HistoryCursor(
        preparedAt: historyRun(3).preparedAt,
        runId: historyRun(3).runId,
      );
      final failedQuery = Completer<ReplyValue>();
      runtime.onHistory = (request) {
        queries.add((request as QueryHistory).selection);
        return queries.length == 1
            ? Future.value(
                HistoryPageValue(
                  Page(items: [historyRun(1)], nextCursor: oldCursor),
                ),
              )
            : failedQuery.future;
      };
      await model.enter();
      model.operation = DiagnosticOperation.send;
      model.recordState = DiagnosticRecordState.settled;
      model.from.text = '2026-11-14T00:00:00Z';
      model.until.text = '2026-11-15T00:00:00Z';
      model.size = 200;
      final apply = model.apply();
      expect(model.loading, true);
      await model.next();
      expect(queries.length, 2);
      failedQuery.completeError(
        const CoreException(CoreErrorCode.storageReadFailed),
      );
      await apply;
      expect(model.pageError!.core, CoreErrorCode.storageReadFailed);
      expect(model.page!.nextCursor, same(oldCursor));
      expect(model.canExport, false);
      await model.next();
      await model.previous();
      expect(queries.length, 2);
      expect(model.selection!.after, null);
      expect(model.pageError!.core, CoreErrorCode.storageReadFailed);

      runtime.onHistory = (request) async {
        final selection = (request as QueryHistory).selection;
        queries.add(selection);
        return HistoryPageValue(
          Page(
            items: [historyRun(3)],
            nextCursor: selection.after == null ? freshCursor : null,
          ),
        );
      };
      await model.refresh();
      expect(queries.last.after, null);
      expect(queries.last.filter!.operation, DiagnosticOperation.send);
      expect(queries.last.filter!.recordState, DiagnosticRecordState.settled);
      expect(
        queries.last.filter!.preparedFromInclusive,
        DateTime.utc(2026, 11, 14),
      );
      expect(
        queries.last.filter!.preparedUntilExclusive,
        DateTime.utc(2026, 11, 15),
      );
      expect(queries.last.size, 200);
      expect(model.canExport, true);
      await model.next();
      expect(queries.last.after, same(freshCursor));
      expect(model.selection!.after, same(freshCursor));
      expect(model.canExport, true);
    },
  );
  test('failed continuation blocks both directions until an explicit refresh succeeds', () async {
    final runtime = DraftRuntime();
    final model = HistoryModel(runtime);
    addTearDown(model.dispose);
    addTearDown(runtime.states.close);
    final queries = <HistorySelection>[];
    final firstCursor = HistoryCursor(
      preparedAt: historyRun(1).preparedAt,
      runId: historyRun(1).runId,
    );
    final secondCursor = HistoryCursor(
      preparedAt: historyRun(2).preparedAt,
      runId: historyRun(2).runId,
    );
    var fail = true;
    runtime.onHistory = (request) async {
      final selection = (request as QueryHistory).selection;
      queries.add(selection);
      if (identical(selection.after, secondCursor)) {
        if (fail) {
          throw const CoreException(CoreErrorCode.storageReadFailed);
        }
        return HistoryPageValue(Page(items: [historyRun(3)]));
      }
      return HistoryPageValue(
        Page(
          items: [historyRun(selection.after == null ? 1 : 2)],
          nextCursor: selection.after == null ? firstCursor : secondCursor,
        ),
      );
    };
    await model.enter();
    await model.next();
    expect(model.canPrevious, true);
    await model.next();
    expect(model.pageError, isNotNull);
    expect(model.canPrevious, false);
    expect(model.canExport, false);
    await model.next();
    await model.previous();
    expect(queries.length, 3);
    expect(model.selection!.after, same(secondCursor));
    expect(model.page!.items.single.runId, historyRun(2).runId);
    fail = false;
    await model.refresh();
    expect(queries.last.after, same(secondCursor));
    expect(model.page!.items.single.runId, historyRun(3).runId);
    expect(model.canPrevious, true);
    await model.previous();
    expect(queries.last.after, same(firstCursor));
    expect(model.page!.items.single.runId, historyRun(2).runId);
    await model.previous();
    expect(queries.last.after, null);
    expect(model.canPrevious, false);
  });
  testWidgets('failed Apply disables cached continuation and export buttons', (
    tester,
  ) async {
    final runtime = DraftRuntime();
    final model = HistoryModel(runtime);
    final output = ExportCoordinator(runtime);
    final queries = <HistorySelection>[];
    runtime.onHistory = (request) async {
      queries.add((request as QueryHistory).selection);
      if (queries.length > 1) {
        throw const CoreException(CoreErrorCode.storageReadFailed);
      }
      return HistoryPageValue(
        Page(
          items: [historyRun(1)],
          nextCursor: HistoryCursor(
            preparedAt: historyRun(1).preparedAt,
            runId: historyRun(1).runId,
          ),
        ),
      );
    };
    await model.enter();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryView(model: model, output: output),
        ),
      ),
    );
    TextButton button(String label) =>
        tester.widget<TextButton>(find.widgetWithText(TextButton, label));
    expect(button('Next page').onPressed, isNotNull);
    model.operation = DiagnosticOperation.send;
    model.size = 200;
    model.formChanged();
    await tester.pump();
    await tester.ensureVisible(find.text('Apply'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Page request failed:'), findsOneWidget);
    expect(button('Next page').onPressed, isNull);
    expect(button('Previous page').onPressed, isNull);
    expect(button('Export one page of redacted summaries').onPressed, isNull);
    expect(button('Refresh page').onPressed, isNotNull);
    expect(queries.length, 2);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
    output.dispose();
    await runtime.states.close();
  });
  test(
    'late page and detail replies do not overwrite newer identities',
    () async {
      final r = DraftRuntime(), pending = <Completer<ReplyValue>>[];
      r.onHistory = (_) {
        final c = Completer<ReplyValue>();
        pending.add(c);
        return c.future;
      };
      final m = HistoryModel(r);
      final a = m.apply();
      m.size = 1;
      final b = m.apply();
      pending[1].complete(HistoryPageValue(Page(items: [historyRun(2)])));
      await b;
      pending[0].complete(HistoryPageValue(Page(items: [historyRun(1)])));
      await a;
      expect(m.page!.items.single.runId, historyRun(2).runId);
      final c = m.select(historyRun(1).runId.value),
          d = m.select(historyRun(2).runId.value);
      pending[3].complete(HistoryRunValue(historyRun(2)));
      await d;
      pending[2].complete(HistoryRunValue(historyRun(1)));
      await c;
      expect(m.detail!.runId, historyRun(2).runId);
      m.dispose();
      await r.states.close();
    },
  );
  test('delete freezes confirmed ID through selection changes and waits for commit', () async {
    final r = DraftRuntime(), deleted = <String>[];
    final commit = Completer<ReplyValue>();
    r.onHistory = (q) async {
      if (q is ReadHistory) {
        return HistoryRunValue(historyRun(q.id.endsWith('1') ? 1 : 2));
      }
      if (q is DeleteHistory) {
        deleted.add(q.id);
        return commit.future;
      }
      return HistoryPageValue(Page(items: []));
    };
    final m = HistoryModel(r);
    await m.select(historyRun(1).runId.value);
    await m.deleteSelected((_) async => false);
    expect(deleted, isEmpty);
    final confirmation = Completer<bool>();
    final work = m.deleteSelected((run) {
      expect(run.runId, historyRun(1).runId);
      return confirmation.future;
    });
    await m.select(historyRun(2).runId.value);
    confirmation.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(deleted.single, historyRun(1).runId.value);
    expect(m.deletedId, null);
    commit.complete(const Accepted());
    await work;
    expect(m.deletedId, historyRun(1).runId.value);
    expect(m.detail!.runId, historyRun(2).runId);
    m.dispose();
    await r.states.close();
  });
  test(
    'ack captures actually seen revision and count; refresh is a separate read',
    () async {
      final r = DraftRuntime(), requests = <HistoryRequest>[];
      final seen = MaintenanceSnapshot(
        HistoryMaintenanceState.completed,
        CoreErrorCode.storageWriteFailed,
        2,
        revision: 7,
      );
      r.onHistory = (q) async {
        requests.add(q);
        return MaintenanceValue(seen, null);
      };
      final m = HistoryModel(r);
      await m.refreshMaintenance();
      await m.acknowledge();
      expect(requests.first, isA<ReadMaintenanceStatus>());
      final ack = requests.last as AcknowledgeMaintenance;
      expect((ack.generation, ack.revision, ack.count), (1, 7, 2));
      m.dispose();
      await r.states.close();
    },
  );
  testWidgets(
    'live mouse composition guards filter actions, menus and export before rebuild',
    (tester) async {
      final r = DraftRuntime(), calls = <HistoryRequest>[];
      r.onHistory = (q) async {
        calls.add(q);
        return HistoryPageValue(Page(items: []));
      };
      final m = HistoryModel(r), out = ExportCoordinator(r);
      await m.enter();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistoryView(model: m, output: out),
          ),
        ),
      );
      final field = find.byKey(const ValueKey('history-from'));
      await tester.tap(field);
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'zhong',
          composing: TextRange(start: 0, end: 5),
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      final value = m.from.value, focus = FocusManager.instance.primaryFocus;
      await tester.tap(find.text('Apply'));
      await tester.pump();
      await tester.tap(find.text('Operation: All'));
      await tester.pump();
      expect(calls.length, 1);
      expect(m.from.value, value);
      expect(FocusManager.instance.primaryFocus, focus);
      expect(
        find.text('Finish or cancel text composition before this action.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      m.dispose();
      out.dispose();
      await r.states.close();
    },
  );
  testWidgets(
    'history renders saved four-type facts and recovered partial facts without session attempts',
    (tester) async {
      const budgets = ProfileBudgets(taskTimeoutSeconds: 10);
      final configurations = <DiagnosticConfiguration>[
        historyRun(1).configuration,
        const ListenConfiguration(
          budgets: budgets,
          receiveChannelIndex: 0,
          listenDurationSeconds: 1,
          maxEntries: 2,
        ),
        const PingConfiguration(
          budgets: budgets,
          sendChannelIndex: 0,
          receiveChannelIndex: 0,
          route: DiagnosticRoute(routeDescriptor: 255, pathByteCount: 0),
          maxEntries: 2,
          responseTimeoutSeconds: 1,
          contentByteLength: 0,
        ),
        const RespondConfiguration(
          budgets: budgets,
          sendChannelIndex: 0,
          receiveChannelIndex: 0,
          route: DiagnosticRoute(routeDescriptor: 255, pathByteCount: 0),
          maxEntries: 2,
          listenDurationSeconds: 1,
          maxResponses: 2,
        ),
      ];
      for (final c in configurations) {
        final run = historyRun(
          1,
          configuration: c,
          state: DiagnosticRecordState.recoveredArchived,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: HistoryDetail(run: run)),
            ),
          ),
        );
        expect(
          find.textContaining('Persisted diagnostic record'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Logical result: Not observed'),
          findsOneWidget,
        );
        expect(find.textContaining('Host attempt:'), findsNothing);
        expect(
          find.textContaining('Record state: recoveredArchived'),
          findsOneWidget,
        );
      }
    },
  );
  test(
    'all operation/state filters retain the same UTC AND selection',
    () async {
      final runtime = DraftRuntime();
      HistorySelection? captured;
      runtime.onHistory = (request) async {
        captured = (request as QueryHistory).selection;
        return HistoryPageValue(Page(items: []));
      };
      final model = HistoryModel(runtime);
      model.from.text = '2026-11-14T00:00:00.000001Z';
      model.until.text = '2026-11-14T00:00:00.000002Z';
      for (final operation in DiagnosticOperation.values) {
        for (final state in DiagnosticRecordState.values) {
          model.operation = operation;
          model.recordState = state;
          await model.apply();
          expect(captured!.filter!.operation, operation);
          expect(captured!.filter!.recordState, state);
          expect(captured!.filter!.preparedFromInclusive!.microsecond, 1);
          expect(captured!.filter!.preparedUntilExclusive!.microsecond, 2);
          expect(captured!.after, null);
          expect(model.canExport, true);
        }
      }
      model.dispose();
      await runtime.states.close();
    },
  );

  test('four typed results preserve local/remote and published/processed distinctions', () {
    Map<String, Object?> facts(LogicalSummary summary) =>
        Map.fromEntries(logicalFacts(summary).map((f) => MapEntry(f.$1, f.$2)));
    final send = facts(
      const SendSummary(
        reason: LogicalReason.sendFailed,
        send: SendFacts(
          attempted: true,
          pendingAtTermination: false,
          deviceAcceptanceConfirmed: false,
          localWriteCompleted: false,
        ),
      ),
    );
    expect(send['Send device acceptance confirmed'], false);
    expect(send['Send local write completed'], false);
    expect(send['Send dispatched'], null);
    final listen = facts(
      const ListenSummary(
        reason: LogicalReason.completed,
        publishedEntries: 4,
        processedEntries: 3,
        matchingDatagrams: 1,
        filteredDatagrams: 1,
        ordinaryMessages: 1,
      ),
    );
    expect(listen['Listen published entries'], 4);
    expect(listen['Processed entries'], 3);
    expect(listen['Matching datagrams'], 1);
    final ping = facts(
      const PingSummary(
        reason: LogicalReason.sendFailed,
        matchingPongObserved: true,
        exactContentValidated: true,
        roundTripSucceeded: false,
        firstMatchingPongElapsedUs: 0,
      ),
    );
    expect(ping['Matching PONG observed'], true);
    expect(ping['Round trip succeeded'], false);
    expect(ping['First matching PONG elapsed (µs)'], 0);
    expect(ping['Successful application RTT (µs)'], null);
    final respond = facts(
      const RespondSummary(
        reason: LogicalReason.completed,
        responseAttempts: 0,
        localResponsesConfirmed: 0,
      ),
    );
    expect(respond['Response attempts'], 0);
    expect(respond['Local responses confirmed'], 0);
    expect(respond['Last send only attempted'], null);
  });
}
