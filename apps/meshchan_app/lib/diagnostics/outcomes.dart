import 'package:flutter/material.dart';
import 'package:meshchan_core/meshchan_core.dart';

import '../runtime/protocol.dart';

String observed(Object? value) => value == null
    ? 'Not observed'
    : value is Enum
    ? value.name
    : '$value';

/// Explicit public-result allowlist. Never accepts execution input or errors.
List<(String, Object?)> logicalFacts(LogicalSummary s) => [
  ('Operation', s.operation),
  ('Reason', s.reason),
  ('Stage', s.stage),
  ...failureFacts('Failure', s.failure),
  if (s is SendSummary) ...sendFacts('Send', s.send),
  if (s is ListenSummary) ...[
    ...receptionFacts(s.reception),
    ('Listen reception reason', s.receptionReason),
    ('Listen published entries', s.publishedEntries),
    ('Processed entries', s.processedEntries),
    ('Matching datagrams', s.matchingDatagrams),
    ('Filtered datagrams', s.filteredDatagrams),
    ('Ordinary messages', s.ordinaryMessages),
  ],
  if (s is PingSummary) ...[
    ...sendFacts('Send', s.send),
    ...receptionFacts(s.reception),
    ('Processed entries', s.processedEntries),
    ('Matching PONG observed', s.matchingPongObserved),
    ('Exact content validated', s.exactContentValidated),
    ('Round trip succeeded', s.roundTripSucceeded),
    ('First matching PONG elapsed (µs)', s.firstMatchingPongElapsedUs),
    ('Successful application RTT (µs)', s.applicationRttUs),
    ('Matching PONG duplicates', s.matchingPongDuplicates),
  ],
  if (s is RespondSummary) ...[
    ...receptionFacts(s.reception),
    ('Processed entries', s.processedEntries),
    ('Listen stop reason', s.listenStopReason),
    ('Response attempts', s.responseAttempts),
    ('Local responses confirmed', s.localResponsesConfirmed),
    ('Duplicates', s.duplicates),
    ('Conflicts', s.conflicts),
    ('Cache capacity rejections', s.cacheCapacityRejections),
    ('Return capacity rejections', s.returnCapacityRejections),
    ...sendFacts('Last send only', s.lastSend),
  ],
];
List<(String, Object?)> receptionFacts(ReceptionSummary? s) => [
  ('Reception reason', s?.reason),
  ('Published entries', s?.publishedEntries),
  ('Dispatched reads', s?.dispatchedReads),
  ('Completed reads (including failed)', s?.completedReads),
];
List<(String, Object?)> sendFacts(String label, SendFacts? s) => [
  ('$label attempted', s?.attempted),
  ('$label pending at termination', s?.pendingAtTermination),
  ('$label device acceptance confirmed', s?.deviceAcceptanceConfirmed),
  ('$label dispatched', s?.dispatched),
  ('$label local write completed', s?.localWriteCompleted),
  ('$label matching local OK observed', s?.localOkObserved),
  ('$label command failure', s?.commandFailure == null ? null : 'Observed'),
  if (s?.commandFailure case final f?) ...[
    ('$label failed command opcode', f.commandOpcode),
    ('$label failed command dispatched', f.dispatched),
    ('$label failed command write completed', f.localWriteCompleted),
    ('$label failed command response observed', f.matchingResponseObserved),
    ...sessionFacts('$label command session failure', f.sessionFailure),
  ],
];
List<(String, Object?)> sessionFacts(String label, SessionFailureSummary? f) =>
    [
      ('$label kind', f?.kind),
      ('$label stage', f?.stage),
      ('$label command opcode', f?.commandOpcode),
      ('$label expected response opcode', f?.expectedResponseOpcode),
      ('$label device error code', f?.deviceErrorCode),
      ('$label device error name', f?.deviceErrorName),
    ];
List<(String, Object?)> failureFacts(String label, FailureSummary? f) => [
  ('$label domain', f?.domain),
  ('$label kind', f?.kind),
  ('$label stage', f?.stage),
  ('$label host cleanup stage', f?.hostCleanupStage),
  if (f?.session != null) ...sessionFacts('$label session', f!.session),
];

List<(String, Object?)> configurationFacts(DiagnosticRun run) {
  final c = run.configuration;
  return [
    ('Recorded operation', c.operation),
    ('App version', run.appVersion),
    ('Saved profile ID', run.profileId?.value),
    ('Diagnostic summary version', run.diagnosticSummaryFormatVersion),
    ('App target version', c.appTargetVersion),
    ('Max queued commands', c.maxQueuedCommands),
    ('Request timeout (s)', c.budgets.requestTimeoutSeconds),
    ('Initialization timeout (s)', c.budgets.initializationTimeoutSeconds),
    ('Startup delay (ms)', c.budgets.startupDelayMilliseconds),
    ('Task timeout (s)', c.budgets.taskTimeoutSeconds),
    if (c is SendConfiguration) ...[
      ('Send channel', c.sendChannelIndex),
      ('Data type', c.dataType),
      ('Route descriptor', c.route.routeDescriptor),
      ('Route path bytes', c.route.pathByteCount),
      ('Payload bytes', c.payloadByteLength),
    ],
    if (c is ListenConfiguration) ...[
      ('Receive channel', c.receiveChannelIndex),
      ('Data type filter (null means all)', c.dataType),
      ('Listen duration (s)', c.listenDurationSeconds),
      ('Max entries', c.maxEntries),
      ('Max reads per batch', c.maxReadsPerBatch),
    ],
    if (c is TaskConfiguration) ...[
      ('Send channel', c.sendChannelIndex),
      ('Receive channel', c.receiveChannelIndex),
      ('Route descriptor', c.route.routeDescriptor),
      ('Route path bytes', c.route.pathByteCount),
      ('Max entries', c.maxEntries),
      ('Diagnostic wire version', c.diagnosticWireVersion),
      ('Diagnostic data type', c.diagnosticDataType),
      ('Max reads per batch', c.maxReadsPerBatch),
    ],
    if (c is PingConfiguration) ...[
      ('Response timeout (s)', c.responseTimeoutSeconds),
      ('Content bytes', c.contentByteLength),
    ],
    if (c is RespondConfiguration) ...[
      ('Listen duration (s)', c.listenDurationSeconds),
      ('Max responses', c.maxResponses),
      ('Cache capacity', c.cacheCapacity),
      ('Cache TTL (µs)', c.cacheTtlUs),
    ],
  ];
}

class DiagnosticOutcomes extends StatelessWidget {
  const DiagnosticOutcomes({super.key, required this.value});
  final OperationSnapshot value;
  Widget facts(List<(String, Object?)> facts) =>
      SelectableText(facts.map((e) => '${e.$1}: ${observed(e.$2)}').join('\n'));
  Widget save(String label, SaveSnapshot? s) => facts([
    ('$label save', s?.state),
    ('$label error', s?.error?.code),
    ('$label cleanup unconfirmed', s?.cleanupUnconfirmed),
    ('$label final cleanup', s?.finalCleanup),
  ]);
  Widget scope(String label, CleanupScopeSummary? s) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      facts([
        ('$label cleanup', s?.state),
        ('$label failure count', s?.failureCount),
      ]),
      if (s != null)
        for (final f in s.failures) facts(failureFacts(label, f)),
    ],
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Divider(),
      const Text('Current / latest session attempt'),
      facts([
        ('Host attempt', value.attemptId),
        ('Gate lease', value.generation),
        ('Cancel requested', value.cancelRequested),
      ]),
      SelectableText(
        value.runId == null
            ? 'No committed run ID observed.'
            : 'Run ID: ${value.runId}',
      ),
      if (value.noResourcesAcquired)
        const Text('No device resources acquired. Recording was not started.'),
      if (value.error != null) Text('Preparation error: ${value.error!.code}'),
      if (value.registration?.snapshot case final run?)
        facts(configurationFacts(run)),
      const Text('Logical result'),
      if (value.summary case final s?)
        facts(logicalFacts(s))
      else
        const Text('Logical result: Not observed'),
      const Text(
        'Local acceptance does not prove peer receipt. Unconfirmed acceptance or write completion does not prove zero RF or zero bytes. A matching PONG does not replace local OK. Zero Responder responses do not establish a round trip.',
      ),
      const Divider(),
      const Text('Resource cleanup'),
      scope('Core', value.cleanup?.core),
      scope(
        'Core-managed host subscriptions',
        value.cleanup?.hostSubscriptions,
      ),
      facts([
        ('Aggregate cleanup', value.aggregate),
        ('App observation failure', value.observationFailure),
        ('App observer cleanup complete', value.observerCleanupComplete),
        ('App observer cleanup', value.observerCleanup),
        (
          'App observer cleanup failure count',
          value.observerCleanupFailureCount,
        ),
        ('Core done observed', value.coreDoneObserved),
        ('Adapter settled', value.done),
        ('Resources confirmed released', value.resourcesReleased),
      ]),
      facts(failureFacts('Coordination', value.coordination)),
      const Divider(),
      const Text('Independent save outcomes'),
      save('Registration', value.registration),
      save('Logical', value.logicalSave),
      save('Cleanup', value.cleanupSave),
      facts([
        (
          'Core fully successful (task, cleanup and required saves)',
          value.fullySuccessful,
        ),
      ]),
      for (final (i, s) in value.saves.indexed)
        save('Attempt ${i + 1} (${observed(s.phase)})', s),
      const Text(
        'Waiting for observation differs from notAttempted. A committed intermediate cleanup save is not a final record. finalCleanup alone proves neither commit nor release. Saves follow the current history retention policy. Unsaved facts may be unavailable after exit. Maintenance and storage close are separate runtime outcomes.',
      ),
    ],
  );
}
