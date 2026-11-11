import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshctl/src/cli_display.dart';

/// This exception never retains frames, keys, names, URLs, or original errors.
final class ChannelAuditFailure implements Exception {
  const ChannelAuditFailure(this.reason, {this.slot});
  final String reason;
  final int? slot;
  @override
  String toString() => 'ChannelAuditFailure($reason, slot: $slot)';
}

final class _Channel {
  _Channel(this.slot, this.named, this._key);
  final int slot;
  final bool named;
  final Uint8List _key;
  bool get eligible => named && _key.any((b) => b != 0);
  void dispose() => _key.fillRange(0, _key.length, 0);
  Map<String, Object> summary() => {
    'slot': slot,
    'namePresent': named,
    'keyLengthBytes': _key.length,
    'eligibleForComparison': eligible,
  };
}

final class _Query {
  _Query(this.slot);
  final int slot;
  final result = Completer<_Channel>();
  Timer? timer;
  _Channel? response;
  bool written = false;
}

/// A development-only extension around one otherwise unchanged session.
/// The session exclusively owns lifecycle and initialization. This adapter
/// intercepts private channel replies on its single underlying subscription;
/// they never reach the production parser/events. After ready, this tool sends
/// only serialized 0x1F queries: no production ready command/task/reception is
/// started, and the production FIFO remains empty throughout.
final class _AuditTransport implements CompanionTransport {
  _AuditTransport(this.inner) {
    _frames = StreamController<Uint8List>(
      onListen: () {
        _input = inner.frames.listen(
          _receive,
          onError: (Object _, StackTrace _) {
            fail(const ChannelAuditFailure('transportFailed'));
          },
          onDone: () {
            if (!_closing) fail(const ChannelAuditFailure('disconnected'));
          },
        );
      },
      onPause: () => close().ignore(),
      onCancel: () => close().ignore(),
    );
  }
  final CompanionTransport inner;
  late final StreamController<Uint8List> _frames;
  StreamSubscription<Uint8List>? _input;
  _Query? _pending;
  ChannelAuditFailure? _failure;
  Future<void>? _writing, _closed;
  bool _closing = false;
  bool readyForQueries = false;
  int queriesDispatched = 0;
  final opcodes = <int>[];
  ChannelAuditFailure? get failure => _failure;

  @override
  Stream<Uint8List> get frames => _frames.stream;
  @override
  Future<void> open() => inner.open();
  @override
  Future<void> sendFrame(Uint8List content) {
    // The unchanged session may only initialize through this boundary.
    if (content.isEmpty || ![0x16, 0x01].contains(content.first)) {
      return Future.error(const ChannelAuditFailure('writeNotAllowlisted'));
    }
    opcodes.add(content.first);
    return inner.sendFrame(content);
  }

  Future<_Channel> query(int slot, Duration budget) {
    if (_failure case final error?) return Future.error(error);
    if (_closing || !readyForQueries || _pending != null) {
      return Future.error(const ChannelAuditFailure('invalidQueryState'));
    }
    final query = _pending = _Query(slot);
    query.result.future.ignore();
    query.timer = Timer(budget, () {
      fail(ChannelAuditFailure('channelTimeout', slot: slot));
    });
    queriesDispatched++;
    opcodes.add(0x1f);
    _writing =
        Future.sync(() => inner.sendFrame(Uint8List.fromList([0x1f, slot])))
            .then<void>(
              (_) {
                if (!identical(_pending, query)) return;
                query.written = true;
                _complete(query);
              },
              onError: (Object _, StackTrace _) {
                fail(ChannelAuditFailure('channelWriteFailed', slot: slot));
              },
            );
    return query.result.future;
  }

  void _receive(Uint8List frame) {
    if (frame.isNotEmpty && frame.first == 0x12) {
      try {
        // Validate observed input even while cleanup drains the subscription.
        // Never silently truncate a longer or shorter key representation.
        if (frame.length != 50) {
          throw ChannelAuditFailure(
            'invalidChannelReply',
            slot: _pending?.slot,
          );
        }
        if (_closing) return;
        final query = _pending;
        if (query == null || query.response != null) {
          throw const ChannelAuditFailure('unexpectedChannelReply');
        }
        if (frame[1] != query.slot) {
          throw ChannelAuditFailure('invalidChannelReply', slot: query.slot);
        }
        query.response = _Channel(
          query.slot,
          frame[2] != 0,
          Uint8List.fromList(Uint8List.sublistView(frame, 34, 50)),
        );
        _complete(query);
      } on ChannelAuditFailure catch (error) {
        fail(error);
      } finally {
        // Do not retain the original secret-bearing response after extraction.
        frame.fillRange(0, frame.length, 0);
      }
      return;
    }
    // The session's asynchronous input can lose a protocol error when a final
    // query continuation closes it first. Reuse its decoder now, without
    // retaining decoded payloads or raw errors, then forward valid input only.
    try {
      decodeCompanionResponse(frame);
    } on CompanionProtocolException {
      fail(const ChannelAuditFailure('protocolFailed'));
      return;
    }
    if (_closing) return;
    if (_pending != null && frame.isNotEmpty && frame.first == 0x01) {
      fail(ChannelAuditFailure('channelRejected', slot: _pending!.slot));
      return;
    }
    // Notices/current-time stay unrelated observations; never cause queue reads
    // or renew the pending metadata query's fixed deadline.
    _frames.add(frame);
  }

  void _complete(_Query query) {
    if (!query.written || query.response == null) return;
    _pending = null;
    query.timer?.cancel();
    query.result.complete(query.response!);
    query.response = null;
  }

  void fail(ChannelAuditFailure error) {
    // Query completion can precede asynchronous session error delivery. Retain
    // the first fault independently; ordinary close cancellation is not a fault.
    if (error.reason != 'canceled') _failure ??= error;
    final retained = _failure ?? error;
    final pending = _pending;
    _pending = null;
    pending?.timer?.cancel();
    pending?.response?.dispose();
    if (pending != null && !pending.result.isCompleted) {
      pending.result.completeError(retained);
    }
    if (!_closing) _frames.addError(retained);
  }

  @override
  Future<void> close() {
    if (_closed case final closed?) return closed;
    _closing = true;
    fail(const ChannelAuditFailure('canceled'));
    final closed = _closed = _close();
    closed.ignore();
    return closed;
  }

  Future<void> _close() async {
    var failed = false;
    try {
      await inner.close();
    } catch (_) {
      failed = true;
    }
    await _writing;
    try {
      await _input?.cancel();
    } catch (_) {
      failed = true;
    }
    final ended = _frames.close();
    ended.ignore();
    if (_frames.hasListener) await ended;
    if (failed) throw const ChannelAuditFailure('cleanupFailed');
  }
}

final class ChannelAuditRunner {
  ChannelAuditRunner({
    required this.createA,
    required this.createB,
    required this.aSlots,
    required this.bSlots,
    required this.commandTimeout,
    required this.initializationTimeout,
    required this.endpointTimeout,
    this.requestedEndpoints = const ['A', 'B'],
  });
  final CompanionTransport Function() createA, createB;
  final List<int>? aSlots, bSlots;
  final Duration commandTimeout, initializationTimeout, endpointTimeout;
  final List<String> requestedEndpoints;
  final _a = <_Channel>[], _b = <_Channel>[];
  _AuditTransport? _active;
  MeshCoreSession? _session;
  ChannelAuditFailure? _stop;
  bool _used = false;

  void cancel(String reason) {
    _stop ??= ChannelAuditFailure(reason);
    _active?.fail(_stop!);
    _session?.close().ignore();
  }

  Future<Map<String, Object?>> run() async {
    if (_used) throw const ChannelAuditFailure('singleUse');
    _used = true;
    final endpoints = <Map<String, Object?>>[];
    final started = DateTime.now().toUtc().toIso8601String();
    try {
      if (requestedEndpoints.contains('A')) {
        endpoints.add(await _read('A', createA, aSlots, _a));
      }
      if (requestedEndpoints.contains('B') &&
          _stop == null &&
          (endpoints.isEmpty || endpoints.single['status'] == 'PASS')) {
        endpoints.add(await _read('B', createB, bSlots, _b));
      }
      final metadataComplete =
          _stop == null &&
          endpoints.length == requestedEndpoints.length &&
          endpoints.every((e) => e['status'] == 'PASS');
      final complete = metadataComplete && endpoints.length == 2;
      final pairs = <Map<String, Object?>>[];
      if (complete) {
        for (final a in _a.where((e) => e.eligible)) {
          for (final b in _b.where((e) => e.eligible)) {
            var difference = 0;
            for (var i = 0; i < 16; i++) {
              difference |= a._key[i] ^ b._key[i];
            }
            if (difference == 0) {
              final aDuplicates = _a
                  .where((e) => e.eligible && _equal(e, a))
                  .map((e) => e.slot)
                  .toList();
              final bDuplicates = _b
                  .where((e) => e.eligible && _equal(e, b))
                  .map((e) => e.slot)
                  .toList();
              pairs.add({
                'aSendSlot': a.slot,
                'aReceiveSlot': aDuplicates.length == 1 ? a.slot : null,
                'bSendSlot': b.slot,
                'bReceiveSlot': bDuplicates.length == 1 ? b.slot : null,
                'keyLengthBytes': 16,
                'sameReturnedKeyConfirmed': true,
                'aDuplicateKeySlots': aDuplicates,
                'bDuplicateKeySlots': bDuplicates,
              });
            }
          }
        }
      }
      return {
        'schemaVersion': 1,
        'tool': 'channel_audit',
        'startedUtc': started,
        'endedUtc': DateTime.now().toUtc().toIso8601String(),
        'status': metadataComplete ? 'PASS' : 'FAIL',
        'requestedEndpoints': requestedEndpoints,
        'comparisonPerformed': complete,
        'exitCode': metadataComplete
            ? 0
            : _stop?.reason == 'sigint'
            ? 130
            : _stop?.reason == 'sigterm'
            ? 143
            : 69,
        'endpoints': endpoints,
        'matchingPairs': pairs,
        'selectedSlots': null,
        'sameReturned16ByteKeyFound': complete ? pairs.isNotEmpty : null,
        'confirmationScope': 'Equal 16-byte Companion readback only; hidden extended-key configuration is not observable',
        'namesKeysAndFingerprintsOmitted': true,
        'applicationDatagramsSent': 0,
        'queueReadCommandsSent': 0,
        'configurationWriteCommandsSent': 0,
        'keyBuffersCleared': true,
      };
    } finally {
      for (final channel in [..._a, ..._b]) {
        channel.dispose();
      }
      _a.clear();
      _b.clear();
    }
  }

  static bool _equal(_Channel a, _Channel b) {
    var difference = 0;
    for (var i = 0; i < 16; i++) {
      difference |= a._key[i] ^ b._key[i];
    }
    return difference == 0;
  }

  Future<Map<String, Object?>> _read(
    String label,
    CompanionTransport Function() factory,
    List<int>? selected,
    List<_Channel> channels,
  ) async {
    if (_stop != null) {
      return {'endpoint': label, 'status': 'BLOCKED', 'reason': _stop!.reason};
    }
    final started = DateTime.now().toUtc().toIso8601String();
    final transport = _active = _AuditTransport(factory());
    final session = _session = MeshCoreSession(
      transport: transport,
      appName: 'Meshchan',
      requestTimeout: commandTimeout,
      initializationTimeout: initializationTimeout,
    );
    Timer? timer;
    String? reason;
    Map<String, Object?>? failure;
    var cleanup = 'pending';
    final summary = <String, Object?>{'endpoint': label, 'startedUtc': started};
    try {
      timer = Timer(endpointTimeout, () => cancel('endpointTimeout'));
      final info = await session.connect();
      summary.addAll({
        'initializationCompleted': true,
        'protocolVersion': info.deviceInfo.protocolVersion,
        'reportedChannelCapacity': info.deviceInfo.maxChannels,
      });
      final capacity = info.deviceInfo.maxChannels;
      if (capacity < 1 || capacity > 40) {
        throw const ChannelAuditFailure('unsupportedChannelCapacity');
      }
      final slots = selected ?? List.generate(capacity, (i) => i);
      if (slots.any((s) => s >= capacity)) {
        throw const ChannelAuditFailure('slotExceedsReportedCapacity');
      }
      transport.readyForQueries = true;
      for (final slot in slots) {
        if (_stop != null) throw _stop!;
        channels.add(await transport.query(slot, commandTimeout));
        if (transport.failure case final error?) throw error;
        if (session.state != MeshCoreSessionState.ready) {
          throw const ChannelAuditFailure('sessionNoLongerReady');
        }
      }
    } catch (error) {
      reason =
          _stop?.reason ??
          (error is ChannelAuditFailure ? error.reason : 'sessionFailed');
      failure = {
        if (error is ChannelAuditFailure) 'slot': error.slot,
        if (error is MeshCoreSessionFailure) 'session': failureFields(error),
      };
    } finally {
      timer?.cancel();
      try {
        await session.close();
        cleanup = 'succeeded';
      } catch (_) {
        cleanup = 'failed';
        reason ??= 'cleanupFailed';
      }
      _session = null;
      _active = null;
    }
    // Also reconcile faults observed while cleanup drained the input. Session
    // close can suppress its queued error event, but cannot erase this evidence.
    if (transport.failure case final error?) {
      reason ??= _stop?.reason ?? error.reason;
      failure ??= {'slot': error.slot};
    }
    summary.addAll({
      'status': reason == null ? 'PASS' : 'FAIL',
      'reason': reason,
      'failure': failure,
      'cleanup': {'state': cleanup},
      'queriesDispatched': transport.queriesDispatched,
      'hostCommandOpcodes': transport.opcodes,
      'channels': channels.map((e) => e.summary()).toList(),
      'endedUtc': DateTime.now().toUtc().toIso8601String(),
    });
    return summary;
  }
}
