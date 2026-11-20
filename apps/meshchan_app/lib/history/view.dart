import 'package:material_ui/material_ui.dart';

import '../widgets/selectable_label.dart';

import 'package:meshchan_core/meshchan_core.dart';

import '../diagnostics/outcomes.dart';
import '../export/coordinator.dart';
import '../profiles/choice.dart';
import '../runtime/protocol.dart';
import 'model.dart';

Widget historyFacts(List<(String, Object?)> facts) => SelectableLabel(
  facts
      .map(
        (f) =>
            '${f.$1}: ${f.$2 is DateTime ? (f.$2 as DateTime).toUtc().toIso8601String() : observed(f.$2)}',
      )
      .join('\n'),
);

class HistoryDetail extends StatelessWidget {
  const HistoryDetail({super.key, required this.run});
  final DiagnosticRun run;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Persisted diagnostic record'),
      historyFacts([
        ('Run ID', run.runId.value),
        ('Prepared at (UTC)', run.preparedAt),
        ('Logical ended at (UTC)', run.logicalEndedAt),
        ('Record state', run.recordState),
        ...configurationFacts(run),
      ]),
      if (run.result case final result?)
        historyFacts(logicalFacts(result))
      else
        const Text('Logical result: Not observed'),
      for (final (label, scope) in [
        ('Core', run.cleanup.core),
        ('Host subscriptions', run.cleanup.hostSubscriptions),
      ]) ...[
        historyFacts([
          ('$label cleanup', scope.state),
          ('$label failure count', scope.failureCount),
        ]),
        for (final f in scope.failures) historyFacts(failureFacts(label, f)),
      ],
      historyFacts([
        ('Aggregate cleanup', run.cleanup.aggregate),
        ('Recovered at (UTC)', run.recoveredAt),
        ('Recovery reason', run.recoveryReason),
      ]),
      const Text(
        'Recovery time is an observation after exit, not a logical end or RTT. Interrupted records do not establish wireless failure. Unconfirmed cleanup does not prove release. Terminal failed cleanup can be eligible for deletion without confirming release.',
      ),
      const Text(
        'This record contains saved facts only. Session save attempts, app observers and fully successful status are not persisted here. Local acceptance does not prove peer receipt; missing facts remain unobserved.',
      ),
    ],
  );
}

class HistoryView extends StatelessWidget {
  const HistoryView({super.key, required this.model, required this.output});
  final HistoryModel model;
  final ExportCoordinator output;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([model, output]),
    builder: (context, _) {
      final m = model;
      Widget button(String label, VoidCallback action, {bool enabled = true}) =>
          TextButton(
            onPressed: enabled && m.available
                ? () {
                    if (m.allowChange()) action();
                  }
                : null,
            child: Text(label),
          );
      Widget report(String label, MaintenanceReportSnapshot? r) =>
          historyFacts([
            (label, r?.state),
            ('$label committed deletions', r?.deletedCount),
            ('$label deferred eligible excess pins', r?.deferredCount),
            ('$label history limit (unknown if unobserved)', r?.historyLimit),
            ('$label error', r?.error?.code),
          ]);
      final h = m.maintenance, action = m.maintenanceAction, job = output.job;
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'History uses persisted records. UTC registration range is [from, until); all filters combine with AND. Order: preparedAt descending, run ID descending. Separate calls do not share a snapshot.',
            ),
            Wrap(
              spacing: 12,
              children: [
                GuardedChoice<int>(
                  label: 'Operation: ${m.operation?.name ?? 'All'}',
                  choices: [
                    (value: -1, label: 'All'),
                    for (final o in DiagnosticOperation.values)
                      (
                        value: o.index,
                        label: switch (o) {
                          DiagnosticOperation.ping => 'PING',
                          DiagnosticOperation.respond => 'Responder',
                          _ => o.name,
                        },
                      ),
                  ],
                  enabled: m.available,
                  allowOpen: m.allowChange,
                  onSelected: (i) {
                    m.operation = i < 0 ? null : DiagnosticOperation.values[i];
                    m.formChanged();
                  },
                ),
                GuardedChoice<int>(
                  label: 'Record state: ${m.recordState?.name ?? 'All'}',
                  choices: [
                    (value: -1, label: 'All'),
                    for (final s in DiagnosticRecordState.values)
                      (value: s.index, label: s.name),
                  ],
                  enabled: m.available,
                  allowOpen: m.allowChange,
                  onSelected: (i) {
                    m.recordState = i < 0
                        ? null
                        : DiagnosticRecordState.values[i];
                    m.formChanged();
                  },
                ),
                GuardedChoice<int>(
                  label: 'Page size: ${m.size}',
                  choices: [
                    for (final n in [1, 20, 50, 100, 200])
                      (value: n, label: '$n'),
                  ],
                  enabled: m.available,
                  allowOpen: m.allowChange,
                  onSelected: (n) {
                    m.size = n;
                    m.formChanged();
                  },
                ),
              ],
            ),
            TextField(
              key: const ValueKey('history-from'),
              controller: m.from,
              onTapOutside: (_) {},
              readOnly: !m.available,
              decoration: const InputDecoration(
                labelText: 'Prepared from (UTC, inclusive)',
                helperText:
                    'YYYY-MM-DDTHH:mm:ss[.ffffff]Z; empty means no lower bound',
              ),
            ),
            TextField(
              key: const ValueKey('history-until'),
              controller: m.until,
              onTapOutside: (_) {},
              readOnly: !m.available,
              decoration: const InputDecoration(
                labelText: 'Prepared until (UTC, exclusive)',
                helperText:
                    'YYYY-MM-DDTHH:mm:ss[.ffffff]Z; empty means no upper bound',
              ),
            ),
            Wrap(
              children: [
                button('Apply', m.apply),
                button('Reset', m.reset),
                button(
                  'Refresh page',
                  m.refresh,
                  enabled: m.selection != null && !m.loading,
                ),
                button(
                  'First page',
                  m.first,
                  enabled: m.selection != null && !m.loading,
                ),
                button('Previous page', m.previous, enabled: m.canPrevious),
                button('Next page', m.next, enabled: m.canNext),
              ],
            ),
            if (m.notice != null) Text(m.notice!),
            if (m.formError != null) Text(m.formError!),
            if (m.unapplied)
              const Text('Filter edits are not applied. Apply before export.'),
            if (m.loading) const Text('Loading selected page…'),
            if (m.pageError != null)
              Text(
                'Page request failed: ${m.pageError!.code}. Cached rows are from an earlier successful call.',
              ),
            if (m.page case final page?) ...[
              Text(
                'Rows on this page: ${page.items.length}. Recovered on this page: ${page.items.where((r) => r.recordState == DiagnosticRecordState.recoveredArchived).length}.',
              ),
              if (page.items.isEmpty)
                const Text(
                  'This page is empty. Return to the previous or first page if needed.',
                ),
              for (final r in page.items)
                ListTile(
                  selected: m.selectedId == r.runId.value,
                  title: Text('${r.operation.name} • ${r.runId.value}'),
                  subtitle: Text(
                    '${r.preparedAt.toIso8601String()} • ${r.recordState.name}\nLogical: ${observed(r.result?.reason)} • cleanup: ${r.cleanup.aggregate.name} • recovery: ${observed(r.recoveryReason)}',
                  ),
                  onTap: () => m.select(r.runId.value),
                ),
            ],
            if (m.selectedId != null)
              SelectableLabel('Selected run ID: ${m.selectedId}'),
            if (m.detailLoading) const Text('Reading persisted detail…'),
            if (m.detailError != null)
              Text(
                m.detailError!.core == CoreErrorCode.notFound
                    ? 'This run ID does not currently exist. It may have been deleted or maintained. Session facts remain separate.'
                    : 'Detail read failed: ${m.detailError!.code}',
              ),
            if (m.detail case final run?) HistoryDetail(run: run),
            button('Refresh selected record', () {
              if (m.selectedId != null) m.select(m.selectedId!);
            }, enabled: m.selectedId != null && !m.detailLoading),
            button(
              'Delete selected record',
              () => m.deleteSelected(
                (run) async =>
                    await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete this diagnostic record?'),
                        content: SelectableLabel(
                          'Run ID: ${run.runId.value}\n${run.operation.name} • ${run.preparedAt.toIso8601String()}\nCore checks eligibility and active pins at commit. There is no force delete.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete this record'),
                          ),
                        ],
                      ),
                    ) ??
                    false,
              ),
              enabled: m.detail != null && !m.deleting && !m.confirming,
            ),
            if (m.deleting)
              Text('Deleting ${m.deleteTargetId}; waiting for commit…'),
            if (m.deletedId != null)
              SelectableLabel(
                'Deletion committed for ${m.deletedId}. Independent retention may remove other records.',
              ),
            if (m.deleteError != null)
              Text(
                m.deleteError!.core == CoreErrorCode.conflict
                    ? 'Delete conflict for ${m.deleteTargetId}: eligibility or an active recording pin protects this record. Refresh explicitly; no automatic retry.'
                    : 'Delete failed for ${m.deleteTargetId}: ${m.deleteError!.code}',
              ),
            const Divider(),
            const Text('History maintenance'),
            report('Latest observed report', h?.latestReport),
            report('Unacknowledged failure', h?.unacknowledgedReport),
            Text('Unacknowledged failure executions: ${h?.failureCount ?? 0}'),
            const Text(
              'Run maintenance applies the existing global Settings retention limit across all operations, independently of this filter. Deferred eligible excess pins are normal protection. Failed reports can include already committed deletions. Refresh does not retry or acknowledge.',
            ),
            Wrap(
              children: [
                button(
                  'Refresh status',
                  m.refreshMaintenance,
                  enabled: !m.maintenanceRefreshing,
                ),
                button(
                  'Run maintenance',
                  m.maintain,
                  enabled: !m.maintenanceStarting && action?.done != false,
                ),
                button(
                  'Acknowledge failures',
                  m.acknowledge,
                  enabled: !m.acknowledging && (h?.failureCount ?? 0) > 0,
                ),
              ],
            ),
            if (m.maintenanceStarting)
              const Text('Requesting maintenance admission…'),
            if (action != null) ...[
              Text(
                'Explicit maintenance action ${action.id}: ${action.done ? 'settled' : 'accepted; waiting for observation'}',
              ),
              report('Explicit action report', action.report),
              if (action.error != null)
                Text('Action observation error: ${action.error!.code}'),
            ],
            if (m.maintenanceError != null)
              Text(
                'Maintenance request: ${m.maintenanceError!.code}. A stale acknowledgment leaves newly observed failures for explicit confirmation.',
              ),
            const Divider(),
            const Text(
              'Export makes a fresh bounded selection with this applied filter, size and page input cursor. Records may differ from the screen. It creates one new JSON file; existing targets cannot be replaced. This redacted summary is not anonymous data or a restorable backup.',
            ),
            button(
              'Export one page of redacted summaries',
              () => output.start(m.selection!),
              enabled: m.canExport && !output.busy,
            ),
            if (job != null) ...[
              Text(
                'Export job ${job.id}: ${job.phase.name} • summary generated: ${job.generated} • writer admitted: ${job.writerAdmitted} • file published: ${job.published}',
              ),
              if (job.count != null)
                Text(
                  'Generated rows: ${job.count}; more available: ${job.more}',
                ),
              if (job.canceled)
                const Text(
                  'Export canceled before writer admission. Accepted generation or staging work is still observed until settled.',
                ),
              if (job.failure != null)
                Text(
                  'Export failure: ${job.failure!.name}${job.generationError == null ? '' : ' (${job.generationError!.code})'}',
                ),
              if (job.published)
                SelectableLabel(
                  'New file generated: ${job.target}\nExported rows: ${job.count}; more available: ${job.more}',
                ),
              if (job.cleanupWarning)
                const Text(
                  'Staging cleanup warning. A published target remains intact.',
                ),
              if (!job.settled && !job.canceled && !job.writerAdmitted)
                button('Cancel export', output.cancel),
              if (!job.settled && job.writerAdmitted)
                const Text(
                  'Waiting for write, flush/close, exclusive publish and staging cleanup. Quit waits for this host work.',
                ),
            ],
          ],
        ),
      );
    },
  );
}
