import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

class Peer {
  Peer._(this.process) {
    lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    errors = process.stderr.transform(utf8.decoder).join();
  }
  final Process process;
  late final StreamIterator<String> lines;
  late final Future<String> errors;
  bool _exited = false;

  static Future<Peer> start(String mode, Directory directory) async => Peer._(
    await Process.start(Platform.resolvedExecutable, [
      'run',
      'test/storage/process_peer.dart',
      mode,
      directory.path,
    ]),
  );
  Future<String> line() async {
    expect(await lines.moveNext().timeout(const Duration(seconds: 45)), isTrue);
    return lines.current;
  }

  void send(String value) => process.stdin.writeln(value);
  Future<void> finish([int code = 0]) async {
    expect(await process.exitCode.timeout(const Duration(seconds: 45)), code);
    _exited = true;
    // The SDK reports native build-hook checks even from a warm cache. Permit
    // only that exact known tool message, never arbitrary process diagnostics.
    expect(
      (await errors).replaceAll('Running build hooks...', '').trim(),
      isEmpty,
    );
    await lines.cancel();
    await process.stdin.close();
  }

  Future<void> dispose() async {
    if (!_exited) {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(const Duration(seconds: 45));
      await errors;
      await lines.cancel();
    }
  }
}
