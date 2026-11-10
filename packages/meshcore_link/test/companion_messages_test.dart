import 'dart:convert';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:test/test.dart';

void main() {
  test('command vectors are fresh inner content with verbatim names', () {
    final app = encodeAppStart();
    expect(app, [
      0x01,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0x4d,
      0x65,
      0x73,
      0x68,
      0x63,
      0x68,
      0x61,
      0x6e,
    ]);
    expect(encodeAppStart(appName: ''), [0x01, 0, 0, 0, 0, 0, 0, 0]);
    final query = encodeDeviceQuery(appTargetVersion: 3);
    expect(query, [0x16, 0x03]);
    app.fillRange(0, app.length, 0xff);
    query[1] = 0xff;
    expect(encodeAppStart()[0], 0x01);
    expect(encodeDeviceQuery(appTargetVersion: 3), [0x16, 3]);

    const verbatim = ' MiXeD e\u0301 节点😀 ';
    expect(encodeAppStart(appName: verbatim).sublist(8), utf8.encode(verbatim));
  });

  test(
    'commands enforce UTF-8 byte limits, NUL policy, and uint8 versions',
    () {
      // 42 four-byte emoji and 56 three-byte characters both use all 168 bytes.
      for (final name in ['😀' * 42, '界' * 56, 'a' * 168]) {
        expect(encodeAppStart(appName: name).length, 176);
        expect(() => encodeAppStart(appName: '${name}a'), throwsArgumentError);
      }
      const rejectedName = 'synthetic-private-name\u0000suffix';
      expect(
        () => encodeAppStart(appName: rejectedName),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'safe diagnostic',
            isNot(contains('synthetic-private-name')),
          ),
        ),
      );
      for (final version in [0, 255]) {
        expect(encodeDeviceQuery(appTargetVersion: version), [0x16, version]);
      }
      for (final version in [-1, 256]) {
        expect(
          () => encodeDeviceQuery(appTargetVersion: version),
          throwsRangeError,
        );
      }
    },
  );

  test(
    'SELF_INFO reads signed power, independent radio units, and full name',
    () {
      for (final name in [' 节点🛰 ', 'n' * 50]) {
        final response = decodeCompanionResponse(
          selfInfo(name: utf8.encode(name)),
        ) as SelfInfoResponse;
        expect(response.opcode, 0x05);
        expect(
          response.advertType,
          0xee,
        ); // Unknown types are still information.
        expect(response.txPowerDbm, -3);
        expect(response.maxTxPowerDbm, 250); // Distinct unsigned byte.
        expect(response.publicKey, syntheticKey);
        expect(response.radioFrequencyKhz, 869525);
        expect(response.radioBandwidthHz, 250000);
        expect(response.radioSpreadingFactor, 11);
        expect(response.radioCodingRate, 7);
        expect(response.nodeName, name);
        expect(response.contentLength, 58 + utf8.encode(name).length);
      }
    },
  );

  test(
    'content and SELF_INFO lengths fail structurally before field reads',
    () {
      for (final length in [36, 57]) {
        expect(
          () => decodeCompanionResponse(selfInfo().sublist(0, length)),
          throwsA(
            protocolFailure(CompanionProtocolExceptionKind.truncatedResponse)
                .having((e) => e.opcode, 'opcode', 0x05)
                .having((e) => e.requiredLength, 'requiredLength', 58),
          ),
        );
      }
      expect(
        (decodeCompanionResponse(selfInfo()) as SelfInfoResponse).nodeName,
        '',
      );
      for (final content in [Uint8List(0), Uint8List(177)..[0] = 0x05]) {
        expect(
          () => decodeCompanionResponse(content),
          throwsA(
            protocolFailure(
              CompanionProtocolExceptionKind.invalidContentLength,
            ).having((e) => e.contentLength, 'contentLength', content.length),
          ),
        );
      }
      final full = selfInfo(name: List.filled(118, 0x61));
      expect(full.length, maxSerialFrameContentLength);
      expect(
        (decodeCompanionResponse(full) as SelfInfoResponse).nodeName,
        'a' * 118,
      );
    },
  );

  test('DEVICE_INFO separates capacities, build, model, and firmware text', () {
    final response =
        decodeCompanionResponse(deviceInfo(3)) as DeviceInfoResponse;
    expect(response.protocolVersion, 3);
    expect(response.maxContacts, 246);
    expect(response.maxChannels, 17);
    expect(response.firmwareBuildDate, 'Nov 09 2026!');
    expect(response.hardwareModel, 'Synthetic Vendor / 型号');
    expect(response.firmwareVersion, 'v1.2.3-dev+wire');
    expect(response.repeatEnabled, isNull);
    expect(response.pathHashMode, isNull);
  });

  test(
    'DEVICE_INFO requires version-specific prefixes and gates new fields',
    () {
      for (final (version, length, repeat, pathHash) in [
        (3, 80, null, null),
        (8, 80, null, null),
        (9, 81, true, null),
        (10, 82, true, 0xe7),
      ]) {
        final content = deviceInfo(version);
        expect(content.length, length);
        final response = decodeCompanionResponse(content) as DeviceInfoResponse;
        expect(response.repeatEnabled, repeat);
        expect(response.pathHashMode, pathHash);
        expect(
          () => decodeCompanionResponse(content.sublist(0, length - 1)),
          throwsA(
            protocolFailure(CompanionProtocolExceptionKind.truncatedResponse)
                .having((e) => e.requiredLength, 'requiredLength', length)
                .having((e) => e.protocolVersion, 'protocolVersion', version),
          ),
        );
      }
      // Extra bytes never enable a field absent from the reported version.
      for (final version in [3, 8, 9]) {
        final response = decodeCompanionResponse(
          deviceInfo(version, length: 82),
        ) as DeviceInfoResponse;
        expect(response.repeatEnabled, version >= 9 ? isTrue : isNull);
        expect(response.pathHashMode, isNull);
        expect(response.ignoredTailLength, version >= 9 ? 1 : 2);
      }
      final repeatOff = deviceInfo(9)..[80] = 0;
      expect(
        (decodeCompanionResponse(
          repeatOff,
        ) as DeviceInfoResponse).repeatEnabled,
        isFalse,
      );
      expect(
        () => decodeCompanionResponse(deviceInfo(10, length: 80)),
        throwsA(
          protocolFailure(CompanionProtocolExceptionKind.truncatedResponse),
        ),
      );
    },
  );

  test(
    'DEVICE_INFO distinguishes unsupported early layouts from truncation',
    () {
      expect(
        () => decodeCompanionResponse(Uint8List.fromList([0x0d])),
        throwsA(
          protocolFailure(CompanionProtocolExceptionKind.truncatedResponse)
              .having((e) => e.requiredLength, 'requiredLength', 2),
        ),
      );
      for (final version in [0, 1, 2]) {
        for (final length in [2, 82]) {
          final content = Uint8List(length)..setRange(0, 2, [0x0d, version]);
          expect(
            () => decodeCompanionResponse(content),
            throwsA(
              protocolFailure(
                CompanionProtocolExceptionKind.unsupportedDeviceInfoVersion,
              ).having((e) => e.protocolVersion, 'protocolVersion', version),
            ),
          );
        }
      }
      for (final version in [11, 255]) {
        for (final length in [82, 176]) {
          final response = decodeCompanionResponse(
            deviceInfo(version, length: length),
          ) as DeviceInfoResponse;
          expect(response.protocolVersion, version);
          expect(response.pathHashMode, 0xe7);
          expect(response.ignoredTailLength, length - 82);
          expect(response.firmwareVersion, 'v1.2.3-dev+wire');
        }
      }
    },
  );

  test('device errors are valid responses, including unknown error codes', () {
    const names = [
      'unsupported command',
      'not found',
      'table full',
      'bad state',
      'file I/O error',
      'illegal argument',
    ];
    for (final code in [1, 2, 3, 4, 5, 6, 0, 254]) {
      final response = decodeCompanionResponse(
        Uint8List.fromList([0x01, code, 0xff]),
      ) as DeviceErrorResponse;
      expect(response.errorCode, code);
      expect(
        response.knownName,
        code >= 1 && code <= 6 ? names[code - 1] : null,
      );
    }
    expect(
      () => decodeCompanionResponse(Uint8List.fromList([0x01])),
      throwsA(
        protocolFailure(CompanionProtocolExceptionKind.truncatedResponse),
      ),
    );
  });

  test(
    'unimplemented and unknown codes remain private structural summaries',
    () {
      for (final opcode in [0x0f, 0x0e, 0xfe]) {
        final content = Uint8List.fromList([
          opcode,
          ...utf8.encode('hidden-tail'),
        ]);
        final response = decodeCompanionResponse(content);
        expect(response, isA<UnhandledCompanionResponse>());
        expect(response.opcode, opcode);
        expect(response.contentLength, 12);
        content.fillRange(0, content.length, 0);
        expect(response.toString(), isNot(contains('hidden-tail')));
        expect(response.opcode, opcode);
      }
    },
  );

  test(
    'display text honors field boundaries, first NUL, and replacement UTF-8',
    () {
      final content = deviceInfo(10);
      content.fillRange(8, 80, 0);
      content.setRange(8, 20, utf8.encode(' D\u0000ignored!! '));
      final model = utf8.encode(' 型号😀 \u0000hidden');
      content.setRange(20, 20 + model.length, model);
      content.setRange(60, 65, [0x41, 0xc3, 0x28, 0xff, 0x42]);
      var response = decodeCompanionResponse(content) as DeviceInfoResponse;
      expect(response.firmwareBuildDate, ' D');
      expect(response.hardwareModel, ' 型号😀 ');
      expect(response.firmwareVersion, 'A\ufffd(\ufffdB');

      // No NUL: use the whole field, including spaces and a broken last byte.
      content.fillRange(8, 20, 0x20);
      content[19] = 0xc3;
      content.fillRange(20, 60, 0x4d);
      content[20] =
          0xa9; // Cannot complete the preceding field's UTF-8 sequence.
      content.fillRange(60, 80, 0x20);
      response = decodeCompanionResponse(content) as DeviceInfoResponse;
      expect(response.firmwareBuildDate, '${' ' * 11}\ufffd');
      expect(response.hardwareModel, '\ufffd${'M' * 39}');
      expect(response.firmwareVersion, ' ' * 20);

      for (final (nameBytes, expected) in [
        ([...utf8.encode(' 节点😀 '), 0, 0x58, 0xff], ' 节点😀 '),
        ([0x41, 0xc3, 0x28, 0xff, 0x42], 'A\ufffd(\ufffdB'),
      ]) {
        expect(
          (decodeCompanionResponse(
            selfInfo(name: nameBytes),
          ) as SelfInfoResponse).nodeName,
          expected,
        );
      }
    },
  );

  test(
    'offset views own retained keys and default diagnostics omit private data',
    () {
      final original = selfInfo(name: utf8.encode('synthetic-private-node'));
      final storage = Uint8List.fromList([0xff, 0xfe, 0xfd, ...original, 0xfc]);
      final view = Uint8List.sublistView(storage, 3, 3 + original.length);
      final response = decodeCompanionResponse(view) as SelfInfoResponse;
      final device = deviceInfo(10);
      final deviceStorage = Uint8List.fromList([0xff, ...device, 0xff]);
      final info = decodeCompanionResponse(
        Uint8List.sublistView(deviceStorage, 1, 1 + device.length),
      ) as DeviceInfoResponse;
      expect(response.radioFrequencyKhz, 869525);
      expect(response.publicKey, syntheticKey);
      expect(info.maxContacts, 246);
      expect(info.firmwareVersion, 'v1.2.3-dev+wire');

      CompanionProtocolException? failure;
      try {
        decodeCompanionResponse(Uint8List.sublistView(view, 0, 57));
      } on CompanionProtocolException catch (error) {
        failure = error;
      }
      expect(failure, isNotNull);
      final summaries = '$response $info $failure';
      for (final sensitive in [
        'synthetic-private-node',
        'Synthetic Vendor',
        'Nov 09 2026!',
        'v1.2.3-dev+wire',
        syntheticKey.toString(),
        original.sublist(36, 44).toString(),
        '305419896', // Synthetic BLE PIN: 0x12345678.
      ]) {
        expect(summaries, isNot(contains(sensitive)));
      }
      storage.fillRange(0, storage.length, 0);
      deviceStorage.fillRange(0, deviceStorage.length, 0);
      expect(response.publicKey, syntheticKey);
      expect(response.nodeName, 'synthetic-private-node');
      expect(info.hardwareModel, 'Synthetic Vendor / 型号');
      expect(() => response.publicKey[0] = 0, throwsUnsupportedError);
    },
  );

  test('framing wraps commands once and hands device content directly to parser', () {
    expect(encodeSerialFrame(encodeDeviceQuery(appTargetVersion: 3)), [
      0x3c,
      0x02,
      0x00,
      0x16,
      0x03,
    ]);
    // Independent device-direction frame, not encodeSerialFrame's host output.
    final decoder = SerialFrameDecoder();
    final result = decoder.add(
      Uint8List.fromList([0x3e, 0x02, 0x00, 0x01, 0x06]),
    );
    expect(result.error, isNull);
    final response = decodeCompanionResponse(result.frames.single);
    expect(response, isA<DeviceErrorResponse>());
    expect((response as DeviceErrorResponse).errorCode, 6);
    expect(decoder.finish().error, isNull);
  });
}

TypeMatcher<CompanionProtocolException> protocolFailure(
  CompanionProtocolExceptionKind kind,
) => isA<CompanionProtocolException>().having((e) => e.kind, 'kind', kind);

// Entirely synthetic fixtures, with explicit wire offsets independent of the
// production parser. Skipped bytes deliberately contain nonzero sentinels.
const syntheticKey = [
  0xa0,
  0xa1,
  0xa2,
  0xa3,
  0xa4,
  0xa5,
  0xa6,
  0xa7,
  0xa8,
  0xa9,
  0xaa,
  0xab,
  0xac,
  0xad,
  0xae,
  0xaf,
  0xb0,
  0xb1,
  0xb2,
  0xb3,
  0xb4,
  0xb5,
  0xb6,
  0xb7,
  0xb8,
  0xb9,
  0xba,
  0xbb,
  0xbc,
  0xbd,
  0xbe,
  0xbf,
];

Uint8List selfInfo({List<int> name = const []}) => Uint8List.fromList([
  0x05, 0xee, 0xfd, 0xfa, // 0..3: opcode, type, -3 dBm, max byte 250.
  ...syntheticKey, // 4..35: public key.
  0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0, // 36..43: skipped.
  0x31, 0x42, 0x53, 0x64, // 44..47: settings, not zero padding.
  0x95, 0x44, 0x0d, 0x00, // 48..51: 869525 kHz, little-endian.
  0x90, 0xd0, 0x03, 0x00, // 52..55: 250000 Hz, little-endian.
  11, 7, // 56..57: SF, CR.
  ...name, // 58 onward: all remaining bytes belong to the name region.
]);

Uint8List deviceInfo(int version, {int? length}) {
  final size = length ?? (version >= 10 ? 82 : (version >= 9 ? 81 : 80));
  final content = Uint8List(size);
  content.setRange(0, 8, [
    0x0d, version, 123, 17, // Opcode, protocol, contacts / 2, channels.
    0x78, 0x56, 0x34, 0x12, // 4..7: synthetic skipped BLE PIN.
  ]);
  final build = utf8.encode('Nov 09 2026!'); // 8..19: all 12 bytes, no NUL.
  final model = utf8.encode('Synthetic Vendor / 型号'); // 20..59.
  final firmware = utf8.encode('v1.2.3-dev+wire'); // 60..79.
  content.setRange(8, 20, build);
  content.setRange(20, 20 + model.length, model);
  content.setRange(60, 60 + firmware.length, firmware);
  if (size > 80) content[80] = 0x02; // Nonzero repeat flag, not just 1.
  if (size > 81) content[81] = 0xe7; // Raw path-hash mode.
  if (size > 82) content.fillRange(82, size, 0xad);
  return content;
}
