import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:test/test.dart';

import '../tool/channel_audit.dart' show ChannelAuditConfig;
import '../tool/support/channel_audit.dart';

final class _Transport implements CompanionTransport {
  final StreamController<Uint8List> framesController;
  final sent = <List<int>>[];
  final receivedPrivateFrames = <Uint8List>[];
  final Map<int, (bool, List<int>)> channels;
  final int capacity;
  bool wrongIndex = false,
      longKey = false,
      missingReply = false,
      writeFailure = false;
  int closes = 0, opens = 0;
  Future<void>? closeGate;
  void Function()? afterQuery;
  void Function()? afterReply;
  void Function()? beforeClose;
  _Transport(this.channels, {this.capacity = 3, bool syncFrames = false})
    : framesController = StreamController<Uint8List>(sync: syncFrames);
  @override
  Stream<Uint8List> get frames => framesController.stream;
  @override
  Future<void> open() async {
    opens++;
  }

  @override
  Future<void> sendFrame(Uint8List content) async {
    sent.add(List<int>.from(content));
    switch (content.first) {
      case 0x16:
        framesController.add(
          Uint8List.fromList([
            0x0d,
            14,
            25,
            capacity,
            ...List.filled(76, 0),
            1,
            254,
          ]),
        );
      case 1:
        framesController.add(
          Uint8List.fromList([5, 0, 0, 22, ...List.filled(54, 0)]),
        );
      case 0x1f:
        afterQuery?.call();
        framesController.add(Uint8List.fromList([9, 0, 0, 0, 0]));
        framesController.add(Uint8List.fromList([0x83]));
        if (missingReply) return;
        final slot = content[1];
        final channel = channels[slot] ?? (false, List.filled(16, 0));
        final frame = Uint8List.fromList([
          0x12,
          wrongIndex ? slot + 1 : slot,
          channel.$1 ? 65 : 0,
          ...List.filled(31, 0),
          ...channel.$2,
          if (longKey) ...List.filled(16, 99),
        ]);
        receivedPrivateFrames.add(frame);
        if (afterReply == null) {
          framesController.add(frame);
        } else {
          // Let the write settle before delivering the reply and failure in
          // the same input turn, before the awaiting query can resume.
          Timer.run(() {
            framesController.add(frame);
            afterReply!();
          });
        }
        if (writeFailure) throw StateError('PRIVATE_SECRET_AND_URL');
      default:
        throw StateError('Unexpected host opcode');
    }
  }

  @override
  Future<void> close() async {
    closes++;
    beforeClose?.call();
    await closeGate;
    await framesController.close();
  }
}

ChannelAuditRunner _runner(
  _Transport a,
  _Transport b, {
  Duration command = const Duration(milliseconds: 100),
  List<int>? aSlots,
  List<String> endpoints = const ['A', 'B'],
}) => ChannelAuditRunner(
  createA: () => a,
  createB: () => b,
  aSlots: aSlots,
  bSlots: [0, 1, 2],
  commandTimeout: command,
  initializationTimeout: const Duration(seconds: 1),
  endpointTimeout: const Duration(seconds: 2),
  requestedEndpoints: endpoints,
);

void main() {
  for (final syncFrames in [true, false]) {
    test(
      'a malformed frame after the final channel reply fails with syncFrames=$syncFrames',
      () async {
        final a = _Transport({
          0: (true, List.filled(16, 7)),
        }, syncFrames: syncFrames);
        a.afterReply = () => a.framesController.add(Uint8List.fromList([5]));
        final b = _Transport({0: (true, List.filled(16, 7))});
        final report = await _runner(a, b, aSlots: [0]).run();
        expect(report['status'], 'FAIL');
        expect(report['exitCode'], 69);
        final endpoint = (report['endpoints'] as List).single as Map;
        expect(endpoint['reason'], 'protocolFailed');
        expect(endpoint['channels'], hasLength(1));
        expect(endpoint['cleanup']['state'], 'succeeded');
        expect(report['comparisonPerformed'], isFalse);
        expect(report['matchingPairs'], isEmpty);
        expect(report['sameReturned16ByteKeyFound'], isNull);
        expect(b.opens, 0);
        expect(a.closes, 1);
        expect(a.framesController.hasListener, isFalse);
        expect(a.sent.map((frame) => frame.first), [0x16, 1, 0x1f]);
        expect(a.receivedPrivateFrames.single.every((b) => b == 0), isTrue);
        expect(report['applicationDatagramsSent'], 0);
        expect(report['queueReadCommandsSent'], 0);
      },
    );
  }

  for (final endpoints in [
    ['A'],
    ['A', 'B'],
  ]) {
    test(
      '${endpoints.join(" then ")} retains transport failure immediately after the final channel reply',
      () async {
        final a = _Transport({0: (true, List.filled(16, 7))}, syncFrames: true);
        a.afterReply = () =>
            a.framesController.addError(StateError('PRIVATE_SECRET_AND_URL'));
        final b = _Transport({});
        final report = await _runner(
          a,
          b,
          aSlots: [0],
          endpoints: endpoints,
        ).run();
        expect(report['status'], 'FAIL');
        expect(report['exitCode'], 69);
        final endpoint = (report['endpoints'] as List).single as Map;
        expect(endpoint['status'], 'FAIL');
        expect(endpoint['reason'], 'transportFailed');
        expect(endpoint['queriesDispatched'], 1);
        expect(endpoint['channels'], hasLength(1));
        expect(endpoint['cleanup']['state'], 'succeeded');
        expect(report['comparisonPerformed'], isFalse);
        expect(report['matchingPairs'], isEmpty);
        expect(report['sameReturned16ByteKeyFound'], isNull);
        expect(report['applicationDatagramsSent'], 0);
        expect(report['queueReadCommandsSent'], 0);
        expect(b.opens, 0);
        expect(a.closes, 1);
        expect(a.framesController.hasListener, isFalse);
        expect(a.sent.map((frame) => frame.first), [0x16, 1, 0x1f]);
        expect(a.sent.last, [0x1f, 0]);
        expect(a.receivedPrivateFrames.single.every((b) => b == 0), isTrue);
        expect(jsonEncode(report), isNot(contains('PRIVATE_SECRET_AND_URL')));
      },
    );
  }

  test('a transport failure during final cleanup prevents success and waits for release', () async {
    final closing = Completer<void>(), release = Completer<void>();
    final a = _Transport({0: (true, List.filled(16, 7))}, syncFrames: true)
      ..closeGate = release.future;
    a.beforeClose = () {
      a.framesController.addError(StateError('PRIVATE_SECRET_AND_URL'));
      closing.complete();
    };
    final b = _Transport({});
    var finished = false;
    final done = _runner(a, b, aSlots: [0]).run().then((report) {
      finished = true;
      return report;
    });
    await closing.future;
    expect(finished, isFalse);
    expect(b.opens, 0);
    release.complete();
    final report = await done;
    expect(report['status'], 'FAIL');
    expect(report['exitCode'], 69);
    final endpoint = (report['endpoints'] as List).single as Map;
    expect(endpoint['reason'], 'transportFailed');
    expect(endpoint['cleanup']['state'], 'succeeded');
    expect(endpoint['channels'], hasLength(1));
    expect(report['comparisonPerformed'], isFalse);
    expect(b.opens, 0);
    expect(a.closes, 1);
    expect(a.framesController.hasListener, isFalse);
    expect(jsonEncode(report), isNot(contains('PRIVATE_SECRET_AND_URL')));
  });

  for (final side in ['A', 'B']) {
    test(
      '$side-only reads once without opening the other endpoint or claiming a comparison',
      () async {
        final a = _Transport({}), b = _Transport({});
        final report = await _runner(a, b, endpoints: [side]).run();
        expect(report['status'], 'PASS');
        expect(report['comparisonPerformed'], isFalse);
        expect(report['sameReturned16ByteKeyFound'], isNull);
        expect(a.opens, side == 'A' ? 1 : 0);
        expect(b.opens, side == 'B' ? 1 : 0);
      },
    );
  }
  test(
    'configuration rejects invalid endpoint, slots, and budgets before I/O',
    () {
      Map<String, dynamic> config() => {
        'aPort': '/dev/explicit',
        'aSlots': 'allReported',
        'bSlots': [0, 1],
        'baseUrl': 'http://127.0.0.1/',
        'companionName': 'peer',
        'endpointLabel': 'peer',
        'jwt': {'env': 'SYNTHETIC_UNUSED'},
        'idleTimeoutSeconds': null,
        'session': {
          'commandSeconds': 5,
          'initializationSeconds': 15,
          'taskSeconds': 90,
          'startupDelayMilliseconds': 0,
        },
      };
      expect(ChannelAuditConfig(config()).aSlots, isNull);
      for (final pair in [
        ('aSlots', [0, 0]),
        ('bSlots', [40]),
        ('aPort', ''),
        ('baseUrl', 'http://host/?token=PRIVATE'),
        ('endpoints', ['A,B']),
        ('endpoints', ['B', 'A']),
      ]) {
        final data = config()..[pair.$1] = pair.$2;
        expect(() => ChannelAuditConfig(data), throwsFormatException);
      }
    },
  );

  test('serialized readback matches slots, skips empty/zero keys and wipes private frames', () async {
    final key = List.generate(16, (i) => i + 17);
    final a = _Transport({
      0: (false, key),
      1: (true, key),
      2: (true, List.filled(16, 0)),
    });
    final b = _Transport({2: (true, key)});
    final report = await _runner(a, b).run();
    expect(report['status'], 'PASS');
    final pairs = report['matchingPairs'] as List;
    expect(pairs, hasLength(1));
    expect(pairs.single['aSendSlot'], 1);
    expect(pairs.single['bSendSlot'], 2);
    expect(report['selectedSlots'], isNull);
    for (final transport in [a, b]) {
      expect(transport.sent.map((f) => f.first), [0x16, 1, 0x1f, 0x1f, 0x1f]);
      expect(transport.sent.skip(2), [
        [0x1f, 0],
        [0x1f, 1],
        [0x1f, 2],
      ]);
      expect(
        transport.receivedPrivateFrames.every((f) => f.every((b) => b == 0)),
        isTrue,
      );
      expect(transport.opens, 1);
      expect(transport.closes, 1);
      expect(transport.framesController.hasListener, isFalse);
    }
    expect(
      jsonEncode(report),
      isNot(
        contains(key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()),
      ),
    );
    expect(report['queueReadCommandsSent'], 0);
    expect(report['applicationDatagramsSent'], 0);
  });

  test(
    'duplicate PSKs are reported as ambiguity without selecting a channel',
    () async {
      final key = List.filled(16, 7);
      final report = await _runner(
        _Transport({0: (true, key), 1: (true, key)}),
        _Transport({2: (true, key)}),
      ).run();
      final pairs = report['matchingPairs'] as List;
      expect(pairs, hasLength(2));
      expect(pairs.first['aDuplicateKeySlots'], [0, 1]);
      expect(report['selectedSlots'], isNull);
    },
  );

  test(
    'unsupported advertised capacity closes A without querying or opening B',
    () async {
      final a = _Transport({}, capacity: 0), b = _Transport({});
      final report = await _runner(a, b).run();
      expect(report['status'], 'FAIL');
      expect(a.sent.map((f) => f.first), [0x16, 1]);
      expect(a.closes, 1);
      expect(b.opens, 0);
    },
  );

  for (final kind in ['wrong-index', 'long-key', 'write-failure', 'timeout']) {
    test('$kind fails closed, preserves cleanup, and never opens B', () async {
      final key = List.filled(16, 7);
      final a = _Transport({0: (true, key)})
        ..wrongIndex = kind == 'wrong-index'
        ..longKey = kind == 'long-key'
        ..writeFailure = kind == 'write-failure'
        ..missingReply = kind == 'timeout';
      final b = _Transport({});
      final report = await _runner(a, b, aSlots: [0]).run();
      expect(report['status'], 'FAIL');
      expect(report['exitCode'], 69);
      expect(
        (report['endpoints'] as List).single['cleanup']['state'],
        'succeeded',
      );
      expect(report['matchingPairs'], isEmpty);
      expect(b.opens, 0);
      expect(jsonEncode(report), isNot(contains('PRIVATE_SECRET_AND_URL')));
      expect(a.sent.map((f) => f.first), [0x16, 1, 0x1f]);
      expect(
        a.receivedPrivateFrames.every((f) => f.every((b) => b == 0)),
        isTrue,
      );
    });
  }

  test(
    'canceling an active query waits for actual cleanup and prevents B',
    () async {
      final closed = Completer<void>(), queried = Completer<void>();
      final a = _Transport({})
        ..missingReply = true
        ..closeGate = closed.future;
      a.afterQuery = queried.complete;
      final b = _Transport({});
      final runner = _runner(a, b, aSlots: [0]);
      var finished = false;
      final completion = runner.run().then((r) {
        finished = true;
        return r;
      });
      await queried.future;
      runner.cancel('sigint');
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      expect(b.opens, 0);
      closed.complete();
      final result = await completion;
      expect(result['exitCode'], 130);
      expect(
        (result['endpoints'] as List).single['cleanup']['state'],
        'succeeded',
      );
      expect(a.framesController.hasListener, isFalse);
    },
  );
}
