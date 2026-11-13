import 'dart:async';
import 'dart:convert';

import 'package:meshchan_app/runtime/controller.dart';
import 'package:meshchan_app/runtime/protocol.dart';

DraftSnapshot draft(
  String id, {
  int revision = 1,
  String title = '',
  String body = '',
}) => DraftSnapshot(
  id,
  revision,
  title,
  body,
  DateTime.utc(2026, 1, 1),
  DateTime.utc(2026, 1, 1, 0, 0, 0, revision),
  utf8.encode(body).length,
);

final class DraftRuntime implements AppRuntime {
  final states = StreamController<RuntimeSnapshot>.broadcast(sync: true);
  final writes = <WriteDraft>[];
  final deletes = <DeleteDraft>[];
  final records = <String, DraftSnapshot>{};
  Future<DraftSnapshot> Function(WriteDraft)? onSave;
  Future<DraftSnapshot> Function(String)? onRead;
  Future<DraftPage> Function(DraftCursor?)? onList;
  Future<String> Function(String, int)? onDelete;
  int starts = 0, shutdowns = 0, begins = 0, resumes = 0;
  DraftDecision? decision;
  @override
  RuntimeSnapshot snapshot = const RuntimeSnapshot(
    generation: 1,
    phase: RuntimePhase.ready,
    owner: OwnerFact.held,
  );
  void setPhase(RuntimePhase phase, {bool paused = false}) {
    snapshot = RuntimeSnapshot(
      generation: 1,
      phase: phase,
      owner: OwnerFact.held,
      admissionPaused: paused,
    );
    states.add(snapshot);
  }

  @override
  Stream<RuntimeSnapshot> get changes => states.stream;
  @override
  Stream<OfflineSnapshot> get offlineChanges => const Stream.empty();
  @override
  OfflineSnapshot? get offline => null;
  @override
  Future<void> start() async {
    starts++;
  }

  @override
  Future<OfflineSnapshot> refresh({
    int pageSize = 20,
    DraftCursor? after,
  }) async => OfflineSnapshot(null, 1000, [], null);
  @override
  Future<DraftPage> listDrafts({int size = 20, DraftCursor? after}) async =>
      onList != null ? onList!(after) : DraftPage(records.values, null);
  @override
  Future<DraftSnapshot> readDraft(String id) async =>
      onRead != null ? onRead!(id) : records[id]!;
  @override
  Future<DraftSnapshot> saveDraft({
    required String title,
    required String body,
    String? id,
    int? expectedRevision,
    DraftDecision? decision,
  }) async {
    final request = WriteDraft(
      title: title,
      body: body,
      id: id,
      expectedRevision: expectedRevision,
      decision: decision,
    );
    writes.add(request);
    if (onSave != null) return onSave!(request);
    if (snapshot.admissionPaused && decision != this.decision) {
      throw const RuntimeFault(host: CoordinationFault.stopped);
    }
    final value = draft(
      id ?? 'id-${writes.length}',
      revision: (expectedRevision ?? 0) + 1,
      title: title,
      body: body,
    );
    records[value.id] = value;
    return value;
  }

  @override
  Future<String> deleteDraft(String id, {required int expectedRevision}) async {
    deletes.add(DeleteDraft(id, expectedRevision));
    if (onDelete != null) return onDelete!(id, expectedRevision);
    records.remove(id);
    return id;
  }

  @override
  Future<DraftDecision> beginDraftDecision(int documentGeneration) async {
    begins++;
    decision = DraftDecision(begins, documentGeneration);
    setPhase(RuntimePhase.ready, paused: true);
    return decision!;
  }

  @override
  Future<void> endDraftDecision(DraftDecision decision) async {
    if (snapshot.phase != RuntimePhase.ready) {
      throw const RuntimeFault(host: CoordinationFault.invalidState);
    }
    resumes++;
    this.decision = null;
    setPhase(RuntimePhase.ready);
  }

  @override
  Future<ShutdownOutcome> shutdown() async {
    shutdowns++;
    return const ShutdownOutcome(true, true);
  }
}
