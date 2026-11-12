import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshchan_core/src/storage/codec.dart';
import 'package:meshchan_core/src/storage/storage.dart';
import 'package:meshcore_link/meshcore_link.dart';
import 'package:test/test.dart';

import '../repositories/draft_repository_test.dart' show Control;
import 'support.dart';

void main() {
  late Directory directory;
  final handles = <CoreStorage>[];
  final active = <RecordedOperation>[];
  Future<StorageHandle> open({
    StorageHooks hooks = const StorageHooks(),
  }) async {
    final s = await openStorage(directory, hooks: hooks) as StorageHandle;
    handles.add(s);
    return s;
  }

  setUp(() {
    directory = Directory.systemTemp.createTempSync('meshchan-recording-');
  });
  tearDown(() async {
    for (final op in active) {
      op.cancel().ignore();
    }
    for (final op in active) {
      await op.done;
    }
    active.clear();
    for (final s in handles.reversed) {
      await s.close();
    }
    handles.clear();
    directory.deleteSync(recursive: true);
  });
  RecordedOperation record(
    StorageHandle s,
    FakeCompanionTransport t,
    DiagnosticOperation operation, {
    List<RecordingSubscription> subscriptions = const [],
    int entries = 8,
    int? filter,
    int timeout = 5,
  }) {
    final op = s.record(
      parameters: input(
        operation,
        entries: entries,
        filter: filter,
        timeout: timeout,
      ),
      appVersion: 'actual-host-1.2.3',
      createTransport: () => t,
      subscriptions: subscriptions,
    );
    active.add(op);
    return op;
  }

  Future<void> ready(FakeCompanionTransport t) async {
    await until(() => t.sent.isNotEmpty);
    t.receive(deviceInfo());
    await until(() => t.sent.length >= 2);
    t.receive(selfInfo());
    await until(() => t.sent.length >= 3);
  }

  Future<void> sendOk(FakeCompanionTransport t) async {
    await ready(t);
    t.receive([0]);
  }

  Future<void> pingSend(FakeCompanionTransport t) async {
    await ready(t);
    expect(t.sent[2], [0x0a]);
    t.receive([0x0a]);
    await until(() => t.sent.any((b) => b[0] == 0x3e));
  }

  void pong(FakeCompanionTransport t) {
    final bytes = t.sent.firstWhere((b) => b[0] == 0x3e);
    // Flood has no path; parse only inside this test to answer the actual nonce.
    final ping = decodeDiagnosticPayload(Uint8List.fromList(bytes.sublist(5)))
        .message!;
    t.receive(
      channelFrame(
        encodeDiagnosticPayload(
          MeshchanDiagnosticMessage(
            kind: DiagnosticKind.pong,
            runNonce: ping.runNonce,
            requestId: ping.requestId,
            senderTestId: ping.targetTestId,
            targetTestId: ping.senderTestId,
            content: ping.content,
          ),
        ),
        type: diagnosticDataType,
      ),
    );
  }

  test('prepared commits before construction; logical save precedes native cleanup and close retains owner', () async {
    final s = await open();
    final t = FakeCompanionTransport();
    final release = Completer<void>();
    t.closing = () => release.future;
    final op = record(s, t, DiagnosticOperation.send);
    final prepared = await op.prepared;
    final id = prepared.snapshot!.runId;
    expect(prepared.state, RecordingSaveState.committed);
    expect((await stored(s, id)).recordState, DiagnosticRecordState.prepared);
    await sendOk(t);
    expect((await op.logical)!.reason, LogicalReason.completed);
    expect((await op.logicalSaved).state, RecordingSaveState.committed);
    expect(
      (await stored(s, id)).cleanup.aggregate,
      isNot(CleanupState.succeeded),
    );
    var closed = false;
    final closing = s.close().then((_) {
      closed = true;
    });
    try {
      await turns();
      expect(closed, isFalse);
      await expectLater(
        CoreStorage.open(dataDirectory: directory),
        throwsA(coreError(CoreErrorCode.dataDirectoryBusy)),
      );
      expect(
        () => s.record(
          parameters: input(DiagnosticOperation.send),
          appVersion: 'v',
          createTransport: () => t,
        ),
        throwsA(coreError(CoreErrorCode.storageWriteFailed)),
      );
    } finally {
      release.complete();
    }
    final result = await op.done;
    await closing;
    expect(result.fullySuccessful, isTrue);
    final reopened = await open();
    final row = await stored(reopened, id);
    expect(row.recordState, DiagnosticRecordState.settled);
    expect(row.recoveredAt, isNull);
    expect(row.cleanup.aggregate, CleanupState.succeeded);
    expect(t.openCount, 1);
    expect(t.listenCount, 1);
    expect(t.sent, hasLength(3));
  });

  for (final kind in ['insert', 'commit', 'id', 'clock']) {
    test(
      'registration $kind failure permits no factory and rolls back on the same handle',
      () async {
        final control = Control(readTable: 'stored_runs');
        final s = await open(
          hooks: StorageHooks(
            executorFactory: (file) =>
                NativeDatabase(file).interceptWith(control),
            runId: kind == 'id'
                ? () => throw const FormatException('PRIVATE')
                : null,
            clock: kind == 'clock'
                ? () => throw const FormatException('PRIVATE')
                : null,
          ),
        );
        if (kind == 'insert') {
          control.afterWrite = (_) async {
            throw StateError('PRIVATE');
          };
        }
        if (kind == 'commit') {
          control.beforeCommit = () async {
            throw StateError('PRIVATE');
          };
        }
        var factories = 0;
        final op = s.record(
          parameters: input(DiagnosticOperation.send),
          appVersion: 'v',
          createTransport: () {
            factories++;
            return FakeCompanionTransport();
          },
        );
        active.add(op);
        final r = await op.done;
        expect(r.registration.error!.code, CoreErrorCode.storageWriteFailed);
        expect(factories, 0);
        expect(r.logical, isNull);
        expect(r.logicalSave.state, RecordingSaveState.notAttempted);
        await s.useDatabase((db) async {
          expect(await db.select(db.storedRuns).get(), isEmpty);
        });
        if (kind == 'insert' || kind == 'commit') {
          final t = FakeCompanionTransport();
          final next = record(s, t, DiagnosticOperation.send);
          await sendOk(t);
          expect((await next.done).fullySuccessful, isTrue);
        }
      },
    );
  }

  test(
    'resolved historical profile remains recordable after deletion',
    () async {
      final s = await open();
      final profile = await s.profiles.save(
        ProfileContent(
          name: 'PRIVATE PROFILE',
          portHint: '/PRIVATE PORT',
          parameters: input(DiagnosticOperation.send).parameters,
        ),
      );
      final parameters = await s.resolveParameters(
        SendParameterRequest(profileId: profile.id, payload: [0, 128, 255]),
      );
      await s.profiles.delete(profile.id);
      final t = FakeCompanionTransport();
      final op = s.record(
        parameters: parameters,
        appVersion: 'v',
        createTransport: () => t,
      );
      active.add(op);
      await sendOk(t);
      final r = await op.done;
      expect(r.fullySuccessful, isTrue);
      expect(r.cleanupSave.snapshot!.profileId, profile.id);
      expect(r.cleanupSave.snapshot!.configuration, isA<SendConfiguration>());
    },
  );

  test('synchronous factory failure keeps prepared evidence, observes host failure and releases admission', () async {
    final s = await open();
    var calls = 0;
    final op = s.record(
      parameters: input(DiagnosticOperation.ping),
      appVersion: 'v',
      createTransport: () {
        calls++;
        throw const FormatException('PRIVATE PORT CONTENT');
      },
    );
    active.add(op);
    final r = await op.done;
    expect(calls, 1);
    expect(r.logical!.reason, LogicalReason.unexpectedFailure);
    expect(r.logical!.failure!.domain, FailureDomain.host);
    expect(r.logicalSave.state, RecordingSaveState.committed);
    expect(r.cleanup.aggregate, CleanupState.notRequired);
    expect(r.registration.snapshot!.result, isNull);
    await s.close();
  });

  test('invalid publicly constructed execution values are rejected without factory or registration', () async {
    final s = await open();
    var factories = 0;
    for (final bad in [
      EffectiveParameters(
        profileId: null,
        parameters: input(DiagnosticOperation.ping).parameters,
      ),
      EffectiveParameters(
        profileId: null,
        parameters: input(DiagnosticOperation.send).parameters,
        content: [256],
      ),
      EffectiveParameters(
        profileId: null,
        parameters: input(DiagnosticOperation.listen).parameters,
        content: [],
      ),
    ]) {
      expect(
        () => s.record(
          parameters: bad,
          appVersion: 'v',
          createTransport: () {
            factories++;
            return FakeCompanionTransport();
          },
        ),
        throwsA(coreError(CoreErrorCode.invalidInput)),
      );
    }
    expect(factories, 0);
    await s.useDatabase((db) async {
      expect(await db.select(db.storedRuns).get(), isEmpty);
    });
  });

  test('PING keeps queued send command facts separate from the preceding failed read', () async {
    final s = await open();
    final t = FakeCompanionTransport();
    final op = record(s, t, DiagnosticOperation.ping);
    await ready(t);
    t.receive([1, 5]);
    final r = await op.done;
    final p = r.logical as PingSummary;
    expect(p.send!.attempted, isTrue);
    expect(p.send!.dispatched, isFalse);
    expect(p.send!.commandFailure!.commandOpcode, 0x3e);
    expect(p.send!.commandFailure!.sessionFailure.commandOpcode, 0x0a);
    expect(p.failure!.session!.kind, FailureKind.deviceRejected);
    expect(p.reception!.completedReads, 1);
    expect(p.roundTripSucceeded, isFalse);
    expect(t.sent.where((b) => b[0] == 0x3e), isEmpty);
    expect(
      (await stored(s, r.registration.snapshot!.runId)).result,
      isA<PingSummary>(),
    );
  });

  test(
    'early matching PONG survives late write failure and real-file reopen',
    () async {
      final s = await open();
      final t = FakeCompanionTransport();
      final write = Completer<void>();
      t.sending = (b, _) => b[0] == 0x3e ? write.future : Future.value();
      final op = record(s, t, DiagnosticOperation.ping);
      await pingSend(t);
      pong(t);
      t.receive([0]);
      await turns();
      write.completeError(StateError('PRIVATE WRITE'));
      final r = await op.done;
      final p = r.logical as PingSummary;
      expect(p.matchingPongObserved, isTrue);
      expect(p.exactContentValidated, isTrue);
      expect(p.roundTripSucceeded, isFalse);
      expect(p.applicationRttUs, isNull);
      expect(p.firstMatchingPongElapsedUs, isNotNull);
      expect(p.send!.localOkObserved, isTrue);
      expect(p.send!.localWriteCompleted, isFalse);
      expect(p.send!.commandFailure!.matchingResponseObserved, isTrue);
      final id = r.registration.snapshot!.runId;
      await s.close();
      final reopened = await open();
      final storedP = (await stored(reopened, id)).result as PingSummary;
      expect(encodeLogicalSummary(storedP), encodeLogicalSummary(p));
    },
  );

  test(
    'successful PING retains RTT when native and host cleanup fail',
    () async {
      final s = await open();
      final t = FakeCompanionTransport();
      t.closing = () => Future.error(StateError('PRIVATE CLOSE'));
      var canceled = 0;
      final op = record(
        s,
        t,
        DiagnosticOperation.ping,
        subscriptions: [
          RecordingSubscription(
            stage: HostCleanupStage.signalSubscription,
            subscribe: (_) => cancellation(() async {
              canceled++;
              throw StateError('PRIVATE CANCEL');
            }),
          ),
        ],
      );
      await pingSend(t);
      t.receive([0]);
      pong(t);
      final r = await op.done;
      final p = r.logical as PingSummary;
      expect(p.roundTripSucceeded, isTrue);
      expect(p.applicationRttUs, isNotNull);
      expect(r.cleanup.core.state, CleanupState.failed);
      expect(r.cleanup.hostSubscriptions.state, CleanupState.failed);
      expect(r.cleanup.core.failureCount, 1);
      expect(canceled, 1);
      expect(r.fullySuccessful, isFalse);
      final id = r.registration.snapshot!.runId;
      await s.close();
      final reopened = await open();
      final row = await stored(reopened, id);
      expect(row.recordState, DiagnosticRecordState.settled);
      expect(row.recoveredAt, isNull);
    },
  );

  test('logical commit failure leaves prepared, but cleanup saves and queue continue', () async {
    final control = Control(readTable: 'stored_runs');
    final s = await open(
      hooks: StorageHooks(
        executorFactory: (file) => NativeDatabase(file).interceptWith(control),
      ),
    );
    final t = FakeCompanionTransport();
    final op = record(s, t, DiagnosticOperation.send);
    await op.prepared;
    await ready(t);
    control.beforeCommit = () async {
      throw StateError('PRIVATE LOGICAL COMMIT');
    };
    t.receive([0]);
    final r = await op.done;
    expect(r.logical!.reason, LogicalReason.completed);
    expect(r.logicalSave.error!.code, CoreErrorCode.storageWriteFailed);
    expect(r.cleanupSave.state, RecordingSaveState.committed);
    expect(r.fullySuccessful, isFalse);
    final row = await stored(s, r.registration.snapshot!.runId);
    expect(row.recordState, DiagnosticRecordState.prepared);
    expect(row.result, isNull);
    expect(row.cleanup.aggregate, CleanupState.succeeded);
    final nextT = FakeCompanionTransport();
    final next = record(s, nextT, DiagnosticOperation.send);
    await sendOk(nextT);
    expect((await next.done).fullySuccessful, isTrue);
  });

  test('two same-category host failures count once each while another cancel hangs', () async {
    final s = await open();
    final t = FakeCompanionTransport();
    final release = Completer<void>();
    final op = record(
      s,
      t,
      DiagnosticOperation.send,
      subscriptions: [
        for (var i = 0; i < 2; i++)
          RecordingSubscription(
            stage: HostCleanupStage.signalSubscription,
            subscribe: (_) => cancellation(() async {
              throw StateError('PRIVATE');
            }),
          ),
        RecordingSubscription(
          stage: HostCleanupStage.signalSubscription,
          subscribe: (_) => cancellation(() => release.future),
        ),
      ],
    );
    final pendingCommitted = Completer<void>();
    final progress = op.saveUpdates.listen((save) {
      if (save.snapshot?.cleanup.hostSubscriptions.state ==
              CleanupState.pending &&
          save.snapshot?.cleanup.hostSubscriptions.failureCount == 2 &&
          !pendingCommitted.isCompleted) {
        pendingCommitted.complete();
      }
    });
    await sendOk(t);
    await op.logicalSaved;
    try {
      await pendingCommitted.future;
      final row = await stored(s, (await op.prepared).snapshot!.runId);
      expect(row.cleanup.hostSubscriptions.state, CleanupState.pending);
      expect(row.cleanup.hostSubscriptions.failureCount, 2);
      expect(row.cleanup.aggregate, CleanupState.pending);
    } finally {
      release.complete();
    }
    final r = await op.done;
    await progress.cancel();
    expect(r.cleanup.hostSubscriptions.state, CleanupState.failed);
    expect(r.cleanup.hostSubscriptions.failureCount, 2);
    expect(r.cleanupSave.snapshot!.cleanup.hostSubscriptions.failureCount, 2);
  });

  test('registration commit barrier prevents factory, and admitted work completes after close begins', () async {
    final control = Control(readTable: 'stored_runs');
    final s = await open(
      hooks: StorageHooks(
        executorFactory: (file) => NativeDatabase(file).interceptWith(control),
      ),
    );
    final entered = Completer<void>(), release = Completer<void>();
    control.beforeCommit = () async {
      entered.complete();
      await release.future;
    };
    var factories = 0;
    final t = FakeCompanionTransport();
    final op = s.record(
      parameters: input(DiagnosticOperation.send),
      appVersion: 'v',
      createTransport: () {
        factories++;
        return t;
      },
    );
    active.add(op);
    await entered.future;
    expect(factories, 0);
    expect(t.calls, isEmpty);
    final closing = s.close();
    release.complete();
    await sendOk(t);
    expect((await op.done).fullySuccessful, isTrue);
    await closing;
    expect(factories, 1);
  });

  test('logical clock failure preserves process facts and permits independent cleanup save', () async {
    var clocks = 0;
    final s = await open(
      hooks: StorageHooks(
        clock: () {
          if (++clocks == 2) throw const FormatException('PRIVATE CLOCK');
          return instant;
        },
      ),
    );
    final t = FakeCompanionTransport();
    final op = record(s, t, DiagnosticOperation.send);
    await sendOk(t);
    final r = await op.done;
    expect(r.logical!.reason, LogicalReason.completed);
    expect(r.logicalSave.error!.code, CoreErrorCode.storageWriteFailed);
    expect(r.cleanupSave.state, RecordingSaveState.committed);
    expect(r.cleanupSave.snapshot!.recordState, DiagnosticRecordState.prepared);
    expect(r.cleanupSave.snapshot!.cleanup.aggregate, CleanupState.succeeded);
  });

  test('cancel during registration avoids every resource and records honest not-required cleanup', () async {
    final s = await open();
    var factories = 0;
    final op = s.record(
      parameters: input(DiagnosticOperation.ping),
      appVersion: 'v',
      createTransport: () {
        factories++;
        return FakeCompanionTransport();
      },
    );
    active.add(op);
    op.cancel().ignore();
    final r = await op.done;
    expect(factories, 0);
    expect(r.logical!.reason, LogicalReason.canceled);
    expect(r.cleanup.aggregate, CleanupState.notRequired);
    expect(r.logicalSave.state, RecordingSaveState.committed);
  });

  test('host construction failure cleans every returned subscription without claiming a task session', () async {
    final s = await open();
    final t = FakeCompanionTransport();
    var cancels = 0;
    final op = record(
      s,
      t,
      DiagnosticOperation.ping,
      subscriptions: [
        RecordingSubscription(
          stage: HostCleanupStage.signalSubscription,
          subscribe: (_) => cancellation(() async {
            cancels++;
          }),
        ),
        RecordingSubscription(
          stage: HostCleanupStage.sessionSubscription,
          subscribe: (_) => throw const FormatException('PRIVATE HOST'),
        ),
      ],
    );
    final r = await op.done;
    expect(cancels, 1);
    expect(t.openCount, 0);
    expect(t.closeCount, 0);
    expect(r.coordinationFailure!.domain, FailureDomain.host);
    expect(r.cleanup.core.state, CleanupState.notRequired);
    expect(r.cleanup.hostSubscriptions.state, CleanupState.succeeded);
    expect(r.fullySuccessful, isFalse);
  });

  test(
    'task cleanup arriving before done is buffered behind the logical save',
    () async {
      final s = await open();
      final t = FakeCompanionTransport();
      var logicalObserved = false, cleanupBeforeLogical = false;
      final op = record(
        s,
        t,
        DiagnosticOperation.ping,
        subscriptions: [
          RecordingSubscription(
            stage: HostCleanupStage.signalSubscription,
            subscribe: (cancelOperation) {
              cancelOperation();
              return cancellation(() async {});
            },
          ),
        ],
      );
      final updates = op.cleanupUpdates.listen((c) {
        if (c.core.state == CleanupState.notRequired && !logicalObserved) {
          cleanupBeforeLogical = true;
        }
      });
      op.logical.then((_) {
        logicalObserved = true;
      });
      final r = await op.done;
      await updates.cancel();
      expect(cleanupBeforeLogical, isTrue);
      expect(r.logical!.reason, LogicalReason.canceled);
      expect(
        r.logicalSave.snapshot!.cleanup.core.state,
        CleanupState.unconfirmed,
      );
      expect(
        r.cleanupSave.snapshot!.cleanup.core.state,
        CleanupState.notRequired,
      );
      expect(t.openCount, 0);
      expect(t.closeCount, 0);
      final phases = r.saves.map((save) => save.phase).toList();
      expect(
        phases.indexOf(RecordingPhase.logical),
        lessThan(phases.indexOf(RecordingPhase.cleanup)),
      );
    },
  );

  for (final operation in [
    DiagnosticOperation.send,
    DiagnosticOperation.listen,
  ]) {
    for (final cancellationFails in [false, true]) {
      test(
        'raw ${operation.code} synchronous cancellation observes all returned subscriptions, failure=$cancellationFails',
        () async {
          final s = await open();
          final t = FakeCompanionTransport();
          final release = Completer<void>();
          final subscriptions = <StreamSubscription<Object?>>[];
          final cancellations = [0, 0];
          final op = record(
            s,
            t,
            operation,
            subscriptions: [
              RecordingSubscription(
                stage: HostCleanupStage.signalSubscription,
                subscribe: (cancelOperation) {
                  cancelOperation();
                  cancelOperation();
                  final subscription = cancellation(() async {
                    cancellations[0]++;
                    if (cancellationFails) throw StateError('PRIVATE CANCEL');
                  });
                  subscriptions.add(subscription);
                  return subscription;
                },
              ),
              RecordingSubscription(
                stage: HostCleanupStage.signalSubscription,
                subscribe: (_) {
                  final subscription = cancellation(() {
                    cancellations[1]++;
                    return release.future;
                  });
                  subscriptions.add(subscription);
                  return subscription;
                },
              ),
            ],
          );
          final pendingSaved = Completer<RecordingSave>();
          final progress = op.saveUpdates.listen((save) {
            final host = save.snapshot?.cleanup.hostSubscriptions;
            if (save.state == RecordingSaveState.committed &&
                host?.state == CleanupState.pending &&
                host?.failureCount == (cancellationFails ? 1 : 0) &&
                !pendingSaved.isCompleted) {
              pendingSaved.complete(save);
            }
          });
          var cleanupFinished = false,
              operationFinished = false,
              closed = false;
          op.cleanupDone.then((_) {
            cleanupFinished = true;
          });
          op.done.then((_) {
            operationFinished = true;
          });
          Future<void>? closing;
          try {
            expect((await op.logical)!.reason, LogicalReason.canceled);
            expect(subscriptions, hasLength(2));
            expect(cancellations, [1, 1]);
            expect(t.calls, isEmpty);
            expect((await op.logicalSaved).state, RecordingSaveState.committed);
            final pending = await pendingSaved.future;
            final row = await stored(s, pending.snapshot!.runId);
            expect(row.cleanup.core.state, CleanupState.notRequired);
            expect(row.cleanup.hostSubscriptions.state, CleanupState.pending);
            expect(
              row.cleanup.hostSubscriptions.failureCount,
              cancellationFails ? 1 : 0,
            );
            expect(row.cleanup.aggregate, CleanupState.pending);
            expect(pending.finalCleanup, isFalse);
            closing = s.close().then((_) {
              closed = true;
            });
            await turns();
            expect(cleanupFinished, isFalse);
            expect(operationFinished, isFalse);
            expect(closed, isFalse);
            await expectLater(
              CoreStorage.open(dataDirectory: directory),
              throwsA(coreError(CoreErrorCode.dataDirectoryBusy)),
            );
          } finally {
            release.complete();
            // Also release the reproduction's leaked subscriptions before the fix.
            for (final subscription in subscriptions) {
              await subscription.cancel().then<void>(
                (_) {},
                onError: (Object _, StackTrace _) {},
              );
            }
            await op.done;
            await closing;
            await progress.cancel();
          }
          final result = await op.done;
          expect(cancellations, [1, 1]);
          final expectedState = cancellationFails
              ? CleanupState.failed
              : CleanupState.succeeded;
          expect(result.cleanup.hostSubscriptions.state, expectedState);
          expect(result.cleanup.aggregate, expectedState);
          expect(result.cleanupSave.state, RecordingSaveState.committed);
          expect(result.cleanupSave.finalCleanup, isTrue);
          expect(
            result.cleanup.hostSubscriptions.failureCount,
            cancellationFails ? 1 : 0,
          );
          final reopened = await open();
          final row = await stored(
            reopened,
            result.registration.snapshot!.runId,
          );
          expect(row.recordState, DiagnosticRecordState.settled);
          expect(row.cleanup.hostSubscriptions.state, expectedState);
          expect(
            row.cleanup.hostSubscriptions.failureCount,
            cancellationFails ? 1 : 0,
          );
          expect(row.recoveredAt, isNull);
        },
      );
    }

    test(
      'raw ${operation.code} synchronous cancellation cleans returned subscriptions when a later registration throws',
      () async {
        final s = await open();
        final t = FakeCompanionTransport();
        StreamSubscription<Object?>? returned;
        var cancellations = 0;
        final op = record(
          s,
          t,
          operation,
          subscriptions: [
            RecordingSubscription(
              stage: HostCleanupStage.signalSubscription,
              subscribe: (cancelOperation) {
                cancelOperation();
                return returned = cancellation(() async {
                  cancellations++;
                });
              },
            ),
            RecordingSubscription(
              stage: HostCleanupStage.sessionSubscription,
              subscribe: (_) => throw const FormatException('PRIVATE HOST'),
            ),
          ],
        );
        try {
          final result = await op.done;
          expect(cancellations, 1);
          expect(t.calls, isEmpty);
          expect(result.logical!.reason, LogicalReason.canceled);
          expect(result.coordinationFailure!.domain, FailureDomain.host);
          expect(result.cleanup.core.state, CleanupState.notRequired);
          expect(
            result.cleanup.hostSubscriptions.state,
            CleanupState.succeeded,
          );
          expect(
            result.cleanupSave.snapshot!.cleanup.hostSubscriptions.state,
            CleanupState.succeeded,
          );
        } finally {
          await returned?.cancel();
        }
      },
    );
  }

  test('initialization failure is a typed communication fact, separate from storage', () async {
    final s = await open();
    final t = FakeCompanionTransport();
    t.opening = () => Future.error(StateError('PRIVATE OPEN'));
    final op = record(s, t, DiagnosticOperation.send);
    final r = await op.done;
    expect(r.logical!.reason, LogicalReason.initializationFailed);
    expect(r.logical!.failure!.session!.kind, FailureKind.transport);
    expect((r.logical as SendSummary).send!.attempted, isFalse);
    expect(r.logicalSave.state, RecordingSaveState.committed);
    expect(t.sent, isEmpty);
  });

  for (final operation in [
    DiagnosticOperation.send,
    DiagnosticOperation.listen,
  ]) {
    for (final phase in ['initializing', 'ready']) {
      test(
        'raw ${operation.code} cancellation precedence retains the earlier $phase session failure',
        () async {
          final s = await open();
          final t = FakeCompanionTransport();
          final release = Completer<void>();
          t.closing = () => release.future;
          final op = record(s, t, operation);
          var cleanupFinished = false;
          op.cleanupDone.then((_) {
            cleanupFinished = true;
          });
          if (phase == 'initializing') {
            await until(() => t.sent.length == 1);
          } else {
            await ready(t);
          }
          // The session commits its root failure synchronously. Its public event
          // and command continuations have not run when cancel is called here.
          t.receiveError(StateError('PRIVATE TRANSPORT'));
          final canceled = op.cancel();
          LogicalSummary? summary;
          try {
            summary = await canceled;
            final expectedReason = phase == 'initializing'
                ? LogicalReason.initializationFailed
                : operation == DiagnosticOperation.send
                ? LogicalReason.sendFailed
                : LogicalReason.receptionFailed;
            final expectedStage = phase == 'initializing'
                ? DiagnosticStage.connecting
                : operation == DiagnosticOperation.send
                ? DiagnosticStage.sending
                : DiagnosticStage.receiving;
            final expectedOpcode = phase == 'initializing'
                ? 0x16
                : operation == DiagnosticOperation.send
                ? 0x3e
                : 0x0a;
            expect(summary!.reason, expectedReason);
            expect(summary.stage, expectedStage);
            expect(summary.failure!.domain, FailureDomain.session);
            expect(summary.failure!.kind, FailureKind.transport);
            expect(summary.failure!.stage, expectedStage);
            final root = summary.failure!.session!;
            expect(root.kind, FailureKind.transport);
            expect(
              root.stage,
              phase == 'initializing'
                  ? SessionStage.initializing
                  : SessionStage.ready,
            );
            expect(root.commandOpcode, expectedOpcode);
            expect(
              root.expectedResponseOpcode,
              phase == 'initializing'
                  ? 0x0d
                  : operation == DiagnosticOperation.send
                  ? 0x00
                  : null,
            );
            if (summary is SendSummary) {
              expect(summary.send!.attempted, phase == 'ready');
              expect(summary.send!.deviceAcceptanceConfirmed, isFalse);
              if (phase == 'ready') {
                expect(summary.send!.pendingAtTermination, isTrue);
                expect(summary.send!.commandFailure!.commandOpcode, 0x3e);
                expect(
                  summary.send!.commandFailure!.sessionFailure.kind,
                  FailureKind.transport,
                );
                expect(summary.send!.dispatched, isTrue);
                expect(summary.send!.localWriteCompleted, isTrue);
                expect(summary.send!.localOkObserved, isFalse);
              }
            } else if (summary is ListenSummary) {
              expect(summary.processedEntries, 0);
              expect(summary.publishedEntries, 0);
              expect(
                summary.receptionReason,
                phase == 'initializing' ? null : ReceptionReason.sessionFailed,
              );
              if (phase == 'initializing') {
                expect(summary.reception, isNull);
              } else {
                expect(summary.reception!.dispatchedReads, 1);
                expect(summary.reception!.completedReads, 1);
              }
            }
            final saved = await op.logicalSaved;
            expect(saved.state, RecordingSaveState.committed);
            final row = await stored(s, saved.snapshot!.runId);
            expect(
              encodeLogicalSummary(row.result!),
              encodeLogicalSummary(summary),
            );
            expect(cleanupFinished, isFalse);
            expect(t.closeCount, 1);
          } finally {
            release.complete();
            await op.done;
          }
          final result = await op.done;
          expect(result.cleanup.aggregate, CleanupState.succeeded);
          expect(result.coordinationFailure, isNull);
          expect(t.sent, hasLength(phase == 'initializing' ? 1 : 3));
          await s.close();
          final reopened = await open();
          final row = await stored(
            reopened,
            result.registration.snapshot!.runId,
          );
          expect(row.recordState, DiagnosticRecordState.settled);
          expect(row.recoveredAt, isNull);
          expect(
            encodeLogicalSummary(row.result!),
            encodeLogicalSummary(summary),
          );
        },
      );
    }

    test(
      'raw ${operation.code} cancellation precedence keeps cancellation before a later transport error',
      () async {
        final s = await open();
        final t = FakeCompanionTransport();
        final release = Completer<void>();
        t.closing = () => release.future;
        final op = record(s, t, operation);
        await ready(t);
        final canceled = op.cancel();
        t.receiveError(StateError('PRIVATE LATE TRANSPORT'));
        try {
          final summary = await canceled;
          expect(summary!.reason, LogicalReason.canceled);
          expect(summary.failure, isNull);
          expect(
            (await op.logicalSaved).snapshot!.result!.reason,
            LogicalReason.canceled,
          );
          expect(t.closeCount, 1);
        } finally {
          release.complete();
          await op.done;
        }
        final result = await op.done;
        await op.cancel();
        expect(
          (await stored(s, result.registration.snapshot!.runId)).result!.reason,
          LogicalReason.canceled,
        );
        expect(t.sent, hasLength(3));
      },
    );
  }

  for (final ending in ['success', 'write', 'rejected', 'cancel', 'timeout']) {
    test('raw send $ending preserves its own finite facts', () async {
      final s = await open();
      final t = FakeCompanionTransport();
      if (ending == 'write') {
        t.sending = (b, _) =>
            b[0] == 0x3e ? Future.error(StateError('PRIVATE')) : Future.value();
      }
      final op = record(
        s,
        t,
        DiagnosticOperation.send,
        timeout: ending == 'timeout' ? 1 : 5,
      );
      await ready(t);
      if (ending == 'success') t.receive([0]);
      if (ending == 'rejected') t.receive([1, 6]);
      if (ending == 'cancel') op.cancel().ignore();
      final r = await op.done;
      final send = (r.logical as SendSummary).send!;
      expect(send.attempted, isTrue);
      expect(send.deviceAcceptanceConfirmed, ending == 'success');
      if (ending == 'write') expect(send.localWriteCompleted, isFalse);
      if (ending == 'rejected') {
        expect(
          send.commandFailure!.sessionFailure.deviceErrorName,
          DeviceErrorName.illegalArgument,
        );
      }
      if (ending == 'cancel') expect(r.logical!.reason, LogicalReason.canceled);
      if (ending == 'timeout') {
        expect(r.logical!.reason, LogicalReason.taskTimeout);
      }
      expect(t.openCount, 1);
      expect(t.closeCount, 1);
      expect(t.listenCount, 1);
    });
  }

  test('raw listen counts normal final entries, filters and ordinary traffic without a second inbox consumer', () async {
    final s = await open();
    final t = FakeCompanionTransport();
    final op = record(s, t, DiagnosticOperation.listen, entries: 3, filter: 99);
    await ready(t);
    t.receive(channelFrame([1]));
    await until(() => t.sent.length >= 4);
    t.receive(channelFrame([2], type: 100));
    await until(() => t.sent.length >= 5);
    t.receive([0x08, 0, 0, 0, 0, 0, 0, 0]);
    final r = await op.done;
    final l = r.logical as ListenSummary;
    expect(l.reason, LogicalReason.completed);
    expect(l.receptionReason, ReceptionReason.entryLimit);
    expect(l.publishedEntries, 3);
    expect(l.processedEntries, 3);
    expect(l.matchingDatagrams, 1);
    expect(l.filteredDatagrams, 1);
    expect(l.ordinaryMessages, 1);
    expect(l.reception!.completedReads, 3);
    expect(t.listenCount, 1);
  });

  test('cancel listen before reception starts retains real zeros and null reception reason', () async {
    final s = await open();
    final t = FakeCompanionTransport();
    final opening = Completer<void>();
    t.opening = () => opening.future;
    final op = record(s, t, DiagnosticOperation.listen);
    await until(() => t.openCount == 1);
    op.cancel().ignore();
    await until(() => t.closeCount == 1);
    final l = (await op.logical) as ListenSummary;
    expect(l.reception, isNull);
    expect(l.receptionReason, isNull);
    expect(l.processedEntries, 0);
    expect(l.publishedEntries, 0);
    opening.complete();
    await op.done;
  });

  test(
    'responder records lastSend, limits and counters from the actual task',
    () async {
      final s = await open();
      final t = FakeCompanionTransport();
      final op = record(s, t, DiagnosticOperation.respond);
      await ready(t);
      t.receive(
        channelFrame(
          encodeDiagnosticPayload(diagnostic(kind: DiagnosticKind.ping)),
          type: diagnosticDataType,
        ),
      );
      await until(() => t.sent.any((b) => b[0] == 0x3e));
      t.receive([0]);
      final r = await op.done;
      final p = r.logical as RespondSummary;
      expect(p.reason, LogicalReason.completed);
      expect(p.listenStopReason, ListenStopReason.responseLimit);
      expect(p.responseAttempts, 1);
      expect(p.localResponsesConfirmed, 1);
      expect(p.lastSend!.deviceAcceptanceConfirmed, isTrue);
      expect(p.duplicates, 0);
      expect(p.conflicts, 0);
      expect(p.cacheCapacityRejections, 0);
      expect(p.returnCapacityRejections, 0);
      expect(r.fullySuccessful, isTrue);
    },
  );

  test('diagnostic rows contain only explicit whitelist and real lengths, never sensitive metadata', () async {
    final s = await open();
    final t = FakeCompanionTransport();
    final op = record(s, t, DiagnosticOperation.ping);
    await ready(t);
    t.receive([1, 5]);
    final r = await op.done;
    await s.useDatabase((db) async {
      final row = await db.select(db.storedRuns).getSingle();
      final json =
          '${row.configurationJson} ${row.resultJson} ${row.cleanupJson}';
      for (final secret in [
        'sessionInfo',
        'cause',
        'stack',
        'nonce',
        'localTestId',
        'peerTestId',
        'PRIVATE',
        'portHint',
        '"path":',
        'payload"',
        'argv',
        'deviceInfo',
        'publicKey',
      ]) {
        expect(json, isNot(contains(secret)));
      }
      expect(json, contains('"contentByteLength":3'));
      expect(json, contains('"pathByteCount":0'));
      expect(row.appVersion, 'actual-host-1.2.3');
      expect(row.runId, hasLength(32));
      expect(row.summaryFormatVersion, 1);
    });
    expect(r.registration.snapshot!.configuration, isA<PingConfiguration>());
  });
}
