import 'dart:convert';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:test/test.dart';

void main() {
  group('channel data commands', () {
    test('independent vectors preserve binary bytes and encoded routes', () {
      for (final (channel, type, descriptor, path, payload, expected) in [
        (
          2,
          0xffff,
          0xff,
          <int>[],
          [0, 0x3c, 0x3e, 0x80, 0xff],
          [0x3e, 2, 0xff, 0xff, 0xff, 0, 0x3c, 0x3e, 0x80, 0xff],
        ),
        (7, 0x1234, 0, <int>[], <int>[], [0x3e, 7, 0, 0x34, 0x12]),
        (
          5,
          0xbeef,
          0x42,
          [0xaa, 0xbb, 0xcc, 0xdd],
          [0, 0xff],
          [0x3e, 5, 0x42, 0xaa, 0xbb, 0xcc, 0xdd, 0xef, 0xbe, 0, 0xff],
        ),
      ]) {
        expect(
          encodeSendChannelData(
            channelIndex: channel,
            dataType: type,
            routeDescriptor: descriptor,
            path: Uint8List.fromList(path),
            payload: Uint8List.fromList(payload),
          ),
          expected,
        );
      }
      // Preserve all valid zero-count descriptors and scalar endpoints.
      for (final descriptor in [0, 0x40, 0x80]) {
        for (final (channel, type) in [(0, 1), (255, 65535)]) {
          expect(send(channel: channel, type: type, descriptor: descriptor), [
            0x3e,
            channel,
            descriptor,
            type & 0xff,
            type >> 8,
          ]);
        }
      }
      expect(send(descriptor: 0x82, pathLength: 6).length, 11);
    });

    test('radio and serial budgets reject oversize input locally', () {
      final flood = send(payloadLength: 165);
      expect(flood.length, 170);
      expect(flood.sublist(5), List.filled(165, 0xa5));
      expect(() => send(payloadLength: 166), throwsArgumentError);
      final direct = send(descriptor: 0x60, pathLength: 64, payloadLength: 107);
      expect(direct.length, maxSerialFrameContentLength);
      expect(direct.sublist(3, 67), List.filled(64, 0xaa));
      expect(direct.sublist(69), List.filled(107, 0xa5));
      expect(
        () => send(descriptor: 0x60, pathLength: 64, payloadLength: 108),
        throwsArgumentError,
      );
    });

    test(
      'validates scalars, reserved hashes, path size, and exact path bytes',
      () {
        for (final channel in [-1, 256]) {
          expect(() => send(channel: channel), throwsRangeError);
        }
        for (final type in [-1, 0, 65536]) {
          expect(() => send(type: type), throwsRangeError);
        }
        for (final descriptor in [-1, 256]) {
          expect(() => send(descriptor: descriptor), throwsRangeError);
        }
        for (final (descriptor, length) in [
          (0xc0, 0), (0xc1, 4), (0xfe, 0), // Reserved four-byte hashes.
          (0x61, 66), (0x96, 66), // Products above 64 bytes.
          (0x42, 3), (0x42, 5), // Both short and long paths are invalid.
          (0xff, 1), (0, 1), // No path for Flood or zero-hop Direct.
        ]) {
          expect(
            () => send(descriptor: descriptor, pathLength: length),
            throwsArgumentError,
            reason: 'descriptor $descriptor, path bytes $length',
          );
        }
      },
    );

    test(
      'commands own their bytes and argument diagnostics retain no secrets',
      () {
        final path = Uint8List.fromList(utf8.encode('PATH'));
        final payload = Uint8List.fromList(utf8.encode('PAYLOAD_SECRET'));
        final encoded = encodeSendChannelData(
          channelIndex: 5,
          dataType: 0xbeef,
          routeDescriptor: 0x42,
          path: path,
          payload: payload,
        );
        for (final (descriptor, bytes) in [
          (0xff, payload),
          (0x42, Uint8List(166)),
        ]) {
          try {
            encodeSendChannelData(
              channelIndex: 5,
              dataType: 1,
              routeDescriptor: descriptor,
              path: path,
              payload: bytes,
            );
            fail('Invalid arguments must throw.');
          } on ArgumentError catch (error) {
            expect(error.invalidValue, isNot(isA<List<int>>()));
            for (final secret in [
              'PATH',
              'PAYLOAD_SECRET',
              '$path',
              '$bytes',
            ]) {
              expect(error.toString(), isNot(contains(secret)));
            }
          }
        }
        path.fillRange(0, path.length, 0);
        payload.fillRange(0, payload.length, 0);
        expect(encoded.sublist(3, 7), utf8.encode('PATH'));
        expect(encoded.sublist(9), utf8.encode('PAYLOAD_SECRET'));
        final sync = encodeSyncNextMessage();
        expect(sync, [0x0a]);
        sync[0] = 0;
        expect(encodeSyncNextMessage(), [0x0a]);
      },
    );
  });

  group('channel data responses', () {
    test(
      'independent vectors use fixed offsets, signed SNR, and opaque types',
      () {
        final direct = decodeCompanionResponse(
          Uint8List.fromList([
            0x1b,
            0xf2,
            0xa5,
            0x5a,
            5,
            0xff,
            0x34,
            0x12,
            4,
            0,
            0x3c,
            0x3e,
            0xff,
          ]),
        ) as ChannelDataResponse;
        expect(direct.opcode, 0x1b);
        expect(direct.contentLength, 13);
        expect(direct.snrQuarterDb, -14);
        expect(direct.snrDb, -3.5);
        expect(direct.channelIndex, 5);
        expect(direct.routeMetadata, 0xff);
        expect(direct.isDirect, isTrue);
        expect(direct.dataType, 0x1234);
        expect(direct.payload, [0, 0x3c, 0x3e, 0xff]);

        final flood = decodeCompanionResponse(
          Uint8List.fromList([0x1b, 0x1d, 0xff, 0x80, 2, 0x42, 0xcd, 0xab, 0]),
        ) as ChannelDataResponse;
        expect(flood.snrQuarterDb, 29);
        expect(flood.snrDb, 7.25);
        expect(flood.channelIndex, 2);
        expect(flood.routeMetadata, 0x42);
        expect(flood.isDirect, isFalse);
        expect(flood.dataType, 0xabcd);
        expect(flood.payload, isEmpty); // No path bytes follow metadata 0x42.

        for (final descriptor in [0, 0x40, 0x80, 0x60, 0x82]) {
          for (final type in [0, 1, 0xffff]) {
            final response = decodeCompanionResponse(
              datagram(descriptor: descriptor, type: type),
            ) as ChannelDataResponse;
            expect(response.routeMetadata, descriptor);
            expect(response.dataType, type);
          }
        }
        final full = decodeCompanionResponse(
          datagram(payload: List.generate(165, (i) => i)),
        ) as ChannelDataResponse;
        expect(full.contentLength, 174);
        expect(full.payload, List.generate(165, (i) => i));
      },
    );

    test('rejects short prefixes, excess length, tails, and invalid route metadata', () {
      final minimum = datagram();
      for (var length = 1; length < 9; length++) {
        expect(
          () => decodeCompanionResponse(minimum.sublist(0, length)),
          throwsA(
            protocolFailure(CompanionProtocolExceptionKind.truncatedResponse)
                .having((e) => e.requiredLength, 'requiredLength', 9),
          ),
        );
      }
      for (final declared in [166, 255]) {
        expect(
          () => decodeCompanionResponse(datagram(declaredLength: declared)),
          throwsA(
            protocolFailure(
              CompanionProtocolExceptionKind.invalidPayloadLength,
            ),
          ),
        );
      }
      for (final (declared, payload) in [
        (1, <int>[]),
        (0, [0xff]),
        (2, [0xff]),
      ]) {
        expect(
          () => decodeCompanionResponse(
            datagram(declaredLength: declared, payload: payload),
          ),
          throwsA(
            protocolFailure(
              CompanionProtocolExceptionKind.unexpectedResponseLength,
            ).having((e) => e.requiredLength, 'requiredLength', 9 + declared),
          ),
        );
      }
      for (final descriptor in [0xc0, 0xc1, 0xfe, 0x61, 0x96]) {
        expect(
          () => decodeCompanionResponse(datagram(descriptor: descriptor)),
          throwsA(
            protocolFailure(
              CompanionProtocolExceptionKind.invalidRouteDescriptor,
            ),
          ),
        );
      }
      expect(
        () => decodeCompanionResponse(Uint8List(177)..[0] = 0x1b),
        throwsA(
          protocolFailure(CompanionProtocolExceptionKind.invalidContentLength),
        ),
      );
    });

    test(
      'offset views produce owned read-only payloads and safe diagnostics',
      () {
        final secret = utf8.encode('PAYLOAD_SECRET');
        final frame = datagram(payload: secret, type: 0xbeef);
        final storage = Uint8List.fromList([0xfe, 0xfd, ...frame, 0xfc]);
        final view = Uint8List.sublistView(storage, 2, 2 + frame.length);
        final response = decodeCompanionResponse(view) as ChannelDataResponse;
        expect(response.dataType, 0xbeef);
        expect(response.payload, secret);
        for (final bad in [
          datagram(payload: secret, declaredLength: 0),
          datagram(payload: secret, declaredLength: 166),
          datagram(payload: secret, descriptor: 0xc0),
        ]) {
          try {
            decodeCompanionResponse(bad);
            fail('Malformed content must throw.');
          } on CompanionProtocolException catch (error) {
            for (final hidden in ['PAYLOAD_SECRET', '$secret', '$bad']) {
              expect('$response $error', isNot(contains(hidden)));
            }
          }
        }
        storage.fillRange(0, storage.length, 0);
        expect(response.payload, secret);
        expect(response.payload.buffer.lengthInBytes, secret.length);
        expect(() => response.payload[0] = 0, throwsUnsupportedError);
        expect(
          () => response.payload.buffer.asUint8List()[0] = 0,
          throwsUnsupportedError,
        );
      },
    );
  });

  group('control and ordinary queue responses', () {
    test('controls have distinct types and require exactly one byte', () {
      for (final (opcode, matcher) in [
        (0x00, isA<OkResponse>()),
        (0x83, isA<MessageWaitingResponse>()),
        (0x0a, isA<NoMoreMessagesResponse>()),
      ]) {
        final response = decodeCompanionResponse(Uint8List.fromList([opcode]));
        expect(response, matcher);
        expect(response.opcode, opcode);
        expect(response.contentLength, 1);
        expect(
          () => decodeCompanionResponse(
            Uint8List.fromList([opcode, ...utf8.encode('hidden-tail')]),
          ),
          throwsA(
            protocolFailure(
                  CompanionProtocolExceptionKind.unexpectedResponseLength,
                )
                .having((e) => e.requiredLength, 'requiredLength', 1)
                .having(
                  (e) => e.toString(),
                  'safe diagnostic',
                  isNot(contains('hidden-tail')),
                ),
          ),
        );
      }
    });

    test(
      'ordinary queue entries check only their prefixes and omit opaque bodies',
      () {
        for (final (opcode, minimum, kind) in [
          (0x07, 13, QueuedMessageKind.legacyContact),
          (0x10, 16, QueuedMessageKind.contactV3),
          (0x08, 8, QueuedMessageKind.legacyChannelText),
          (0x11, 11, QueuedMessageKind.channelTextV3),
        ]) {
          for (final tail in [
            <int>[],
            [0, 0xff, ...utf8.encode('CHAT_SECRET')],
          ]) {
            final content = Uint8List.fromList([
              opcode,
              ...List.filled(minimum - 1, 0xff),
              ...tail,
            ]);
            final response =
                decodeCompanionResponse(content) as QueuedMessageResponse;
            expect(response.kind, kind);
            expect(response.opcode, opcode);
            expect(response.contentLength, minimum + tail.length);
            content.fillRange(0, content.length, 0);
            expect(response.toString(), isNot(contains('CHAT_SECRET')));
            expect(response.opcode, opcode);
          }
          expect(
            () => decodeCompanionResponse(Uint8List(minimum - 1)..[0] = opcode),
            throwsA(
              protocolFailure(CompanionProtocolExceptionKind.truncatedResponse)
                  .having((e) => e.requiredLength, 'requiredLength', minimum),
            ),
          );
        }
      },
    );
  });
}

Uint8List send({
  int channel = 2,
  int type = 1,
  int descriptor = 0xff,
  int pathLength = 0,
  int payloadLength = 0,
}) => encodeSendChannelData(
  channelIndex: channel,
  dataType: type,
  routeDescriptor: descriptor,
  path: Uint8List(pathLength)..fillRange(0, pathLength, 0xaa),
  payload: Uint8List(payloadLength)..fillRange(0, payloadLength, 0xa5),
);

// Independent device-direction fixture, never produced by the host encoder.
Uint8List datagram({
  int descriptor = 0xff,
  int type = 0,
  int? declaredLength,
  List<int> payload = const [],
}) => Uint8List.fromList([
  0x1b,
  0xf2,
  0xa5,
  0x5a,
  5,
  descriptor,
  type & 0xff,
  type >> 8,
  declaredLength ?? payload.length,
  ...payload,
]);

TypeMatcher<CompanionProtocolException> protocolFailure(
  CompanionProtocolExceptionKind kind,
) => isA<CompanionProtocolException>().having((e) => e.kind, 'kind', kind);
