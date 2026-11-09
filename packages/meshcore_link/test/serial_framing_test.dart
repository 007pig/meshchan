import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:test/test.dart';

void main() {
  test('encodes the fixed host vector without changing or sharing input', () {
    final content = Uint8List.fromList([0x01, 0x00, 0x3c, 0x3e, 0xff]);
    final frame = encodeSerialFrame(content);
    expect(frame, [0x3c, 0x05, 0x00, 0x01, 0x00, 0x3c, 0x3e, 0xff]);
    expect(content, [0x01, 0x00, 0x3c, 0x3e, 0xff]);
    content[0] = 0x80;
    expect(frame[3], 0x01);
    frame[4] = 0xff;
    expect(content[1], 0x00);

    final storage = Uint8List.fromList([0xff, 0x00, 0x11, 0x13, 0xff]);
    expect(encodeSerialFrame(Uint8List.sublistView(storage, 1, 4)), [
      0x3c,
      0x03,
      0x00,
      0x00,
      0x11,
      0x13,
    ]);
  });

  test('decodes independent device vectors as opaque content', () {
    for (final (wire, content) in [
      ([0x3e, 0x03, 0x00, 0x00, 0x80, 0xff], [0x00, 0x80, 0xff]),
      (
        [0x3e, 0x07, 0x00, 0x00, 0x3c, 0x3e, 0x11, 0x13, 0xff, 0x80],
        [0x00, 0x3c, 0x3e, 0x11, 0x13, 0xff, 0x80],
      ),
    ]) {
      final decoder = SerialFrameDecoder();
      final result = decoder.add(Uint8List.fromList(wire));
      expect(result.error, isNull);
      expect(result.frames, [content]);
      expect(decoder.finish().error, isNull);
    }
  });

  test(
    'handles every two-part split, single-byte chunks, and empty chunks',
    () {
      final wire = Uint8List.fromList([0x3e, 0x03, 0x00, 0x00, 0x80, 0xff]);
      for (var split = 0; split <= wire.length; split++) {
        final decoder = SerialFrameDecoder();
        final frames = <Uint8List>[];
        for (final chunk in [
          Uint8List.sublistView(wire, 0, split),
          Uint8List(0),
          Uint8List.sublistView(wire, split),
        ]) {
          final result = decoder.add(chunk);
          expect(result.error, isNull, reason: 'Split at $split');
          frames.addAll(result.frames);
        }
        expect(frames, [
          [0x00, 0x80, 0xff],
        ], reason: 'Split at $split');
        expect(decoder.finish().error, isNull);
      }

      final decoder = SerialFrameDecoder();
      final frames = <Uint8List>[];
      for (final byte in wire) {
        expect(decoder.add(Uint8List(0)).frames, isEmpty);
        final result = decoder.add(Uint8List.fromList([byte]));
        expect(result.error, isNull);
        frames.addAll(result.frames);
      }
      expect(frames, [
        [0x00, 0x80, 0xff],
      ]);
      expect(decoder.finish().error, isNull);
    },
  );

  test('delivers coalesced frames promptly while retaining only the tail', () {
    final decoder = SerialFrameDecoder();
    expect(
      decoder.add(Uint8List.fromList([0x3e, 0x02, 0x00, 0x11])).frames,
      isEmpty,
    );
    final result = decoder.add(
      Uint8List.fromList([
        0x13,
        0x3e,
        0x01,
        0x00,
        0x00,
        0x3e,
        0x02,
        0x00,
        0x3c,
      ]),
    );
    expect(result.error, isNull);
    expect(result.frames, [
      [0x11, 0x13],
      [0x00],
    ]);
    final tail = decoder.add(Uint8List.fromList([0x3e]));
    expect(tail.error, isNull);
    expect(tail.frames, [
      [0x3c, 0x3e],
    ]);
    expect(decoder.finish().error, isNull);
  });

  test('accepts 1 and 176 bytes and rejects invalid full 16-bit lengths', () {
    for (final length in [1, 176]) {
      final content = Uint8List.fromList(
        List.generate(length, (index) => (index * 37) & 0xff),
      );
      final encoded = encodeSerialFrame(content);
      expect(encoded, [0x3c, length, 0x00, ...content]);
      final decoder = SerialFrameDecoder();
      final decoded = decoder.add(
        Uint8List.fromList([0x3e, length, 0x00, ...content]),
      );
      expect(decoded.error, isNull);
      expect(decoded.frames, [content]);
      expect(decoder.finish().error, isNull);
    }
    for (final length in [0, 177]) {
      expect(() => encodeSerialFrame(Uint8List(length)), throwsArgumentError);
    }
    for (final length in [0, 177, 256, 65535]) {
      final decoder = SerialFrameDecoder();
      final result = decoder.add(
        Uint8List.fromList([0x3e, length & 0xff, length >> 8]),
      );
      expect(result.frames, isEmpty);
      expect(result.error?.kind, SerialFrameDecodeErrorKind.invalidLength);
      expect(result.error?.message, contains('$length'));
    }
  });

  test(
    'bounds noise across calls and renews the budget only after a frame',
    () {
      expect(
        () => SerialFrameDecoder(maxDiscardedBytes: -1),
        throwsArgumentError,
      );
      final decoder = SerialFrameDecoder(maxDiscardedBytes: 3);
      expect(decoder.add(Uint8List.fromList([0x3c, 0x01])).error, isNull);
      expect(decoder.add(Uint8List(0)).error, isNull);
      expect(decoder.add(Uint8List.fromList([0xff])).error, isNull);
      final result = decoder.add(
        Uint8List.fromList([0x3e, 0x01, 0x00, 0x80, 0x11, 0x13, 0x00]),
      );
      expect(result.frames, [
        [0x80],
      ]);
      expect(result.error, isNull);
      final overflow = decoder.add(
        Uint8List.fromList([0xff, 0x3e, 0x01, 0x00, 0x7f]),
      );
      expect(overflow.frames, isEmpty);
      expect(
        overflow.error?.kind,
        SerialFrameDecodeErrorKind.noiseLimitExceeded,
      );
      expect(() => decoder.add(Uint8List(0)), throwsStateError);
      expect(decoder.finish, throwsStateError);

      final defaultBudget = SerialFrameDecoder();
      expect(defaultBudget.add(Uint8List(1024)).error, isNull);
      expect(
        defaultBudget.add(Uint8List(1)).error?.kind,
        SerialFrameDecodeErrorKind.noiseLimitExceeded,
      );
      final noNoise = SerialFrameDecoder(maxDiscardedBytes: 0);
      expect(noNoise.add(Uint8List.fromList([0x3e, 0x01, 0x00, 0x00])).frames, [
        [0x00],
      ]);
      expect(
        noNoise.add(Uint8List(1)).error?.kind,
        SerialFrameDecodeErrorKind.noiseLimitExceeded,
      );
    },
  );

  test('keeps good frames before an error and requires explicit recovery', () {
    final decoder = SerialFrameDecoder();
    final result = decoder.add(
      Uint8List.fromList([
        0x3e,
        0x01,
        0x00,
        0x00,
        0x3e,
        0xb1,
        0x00,
        0x3e,
        0x01,
        0x00,
        0x7f,
      ]),
    );
    expect(result.frames, [
      [0x00],
    ]);
    expect(result.error?.kind, SerialFrameDecodeErrorKind.invalidLength);
    expect(
      () => decoder.add(Uint8List.fromList([0x3e, 0x01, 0x00, 0x7f])),
      throwsStateError,
    );
    expect(decoder.finish, throwsStateError);
    decoder.reset();
    decoder.reset();
    expect(decoder.add(Uint8List(0)).frames, isEmpty);
    final recovered = decoder.add(Uint8List.fromList([0x3e, 0x01, 0x00, 0xff]));
    expect(recovered.error, isNull);
    expect(recovered.frames, [
      [0xff],
    ]);
    expect(result.frames, [
      [0x00],
    ]);
  });

  test('finishes cleanly at a frame boundary or after allowed noise', () {
    for (final input in [
      <int>[],
      [0x3c, 0xff],
      [0x3e, 0x01, 0x00, 0x00],
    ]) {
      final decoder = SerialFrameDecoder();
      expect(decoder.add(Uint8List.fromList(input)).error, isNull);
      final result = decoder.finish();
      expect(result.error, isNull);
      expect(result.frames, isEmpty);
      expect(() => decoder.add(Uint8List(0)), throwsStateError);
      expect(decoder.finish, throwsStateError);
      decoder.reset();
      expect(decoder.add(Uint8List.fromList([0x3e, 0x01, 0x00, 0x80])).frames, [
        [0x80],
      ]);
    }
  });

  test(
    'detects truncated headers and content without resyncing at content >',
    () {
      for (final input in [
        [0x3e],
        [0x3e, 0x03],
        [0x3e, 0x03, 0x00],
        [0x3e, 0x03, 0x00, 0x80],
        [0x3e, 0x08, 0x00, 0x3e, 0x01, 0x00, 0x7f],
      ]) {
        final decoder = SerialFrameDecoder();
        final partial = decoder.add(Uint8List.fromList(input));
        expect(partial.frames, isEmpty);
        expect(partial.error, isNull);
        final result = decoder.finish();
        expect(result.frames, isEmpty);
        expect(result.error?.kind, SerialFrameDecodeErrorKind.truncatedFrame);
        expect(() => decoder.add(Uint8List(0)), throwsStateError);
        expect(decoder.finish, throwsStateError);
        decoder.reset();
        expect(decoder.finish().error, isNull);
      }
    },
  );

  test('reset clears partial headers, content, noise, and instance state', () {
    final independent = SerialFrameDecoder();
    independent.add(Uint8List.fromList([0x3e, 0x02]));
    for (final input in [
      [0x00, 0x00],
      [0x3e],
      [0x3e, 0x01],
      [0x3e, 0x02, 0x00, 0x80],
    ]) {
      final decoder = SerialFrameDecoder(maxDiscardedBytes: 2);
      decoder.add(Uint8List.fromList(input));
      decoder.reset();
      decoder.reset();
      final result = decoder.add(
        Uint8List.fromList([0x00, 0x00, 0x3e, 0x01, 0x00, 0xff]),
      );
      expect(result.error, isNull);
      expect(result.frames, [
        [0xff],
      ]);
    }
    expect(independent.add(Uint8List.fromList([0x00, 0x11, 0x13])).frames, [
      [0x11, 0x13],
    ]);
  });

  test('owns partial and returned bytes, including offset views', () {
    final storage = Uint8List.fromList([
      0xff,
      0x3e,
      0x03,
      0x00,
      0x11,
      0x13,
      0xff,
    ]);
    final decoder = SerialFrameDecoder();
    final partial = decoder.add(Uint8List.sublistView(storage, 1, 6));
    expect(partial.error, isNull);
    expect(partial.frames, isEmpty);
    storage.fillRange(0, storage.length, 0);
    final tail = Uint8List.fromList([0x80, 0x3e, 0x01, 0x00, 0xff]);
    final result = decoder.add(tail);
    expect(result.error, isNull);
    expect(result.frames, [
      [0x11, 0x13, 0x80],
      [0xff],
    ]);
    tail.fillRange(0, tail.length, 0);
    result.frames.last[0] = 0x7f;
    expect(decoder.add(Uint8List.fromList([0x3e, 0x01, 0x00, 0x00])).frames, [
      [0x00],
    ]);
    decoder.reset();
    expect(result.frames, [
      [0x11, 0x13, 0x80],
      [0x7f],
    ]);
  });
}
