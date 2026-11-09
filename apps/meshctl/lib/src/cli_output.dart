import 'dart:async';
import 'dart:collection';
import 'dart:io';

/// A small per-channel queue. Its 128-record limit includes the active record;
/// it does not bound buffering inside IOSink or the operating system.
final class CliOutput {
  CliOutput(StringSink output, StringSink error) {
    _output = _Channel(output, () => _fail(false));
    _error = _Channel(error, () => _fail(true));
  }

  late final _Channel _output;
  late final _Channel _error;
  bool failed = false;
  void Function()? onFailure;

  void out(String record) => _output.add(record);
  void err(String record) => _error.add(record);

  void _fail(bool isError) {
    if (failed) return;
    failed = true;
    if (!isError) _error.add('Error: CLI output failed.');
    onFailure?.call();
  }

  Future<void> drain() async {
    await _output.drain();
    await _error.drain();
  }
}

final class _Channel {
  _Channel(this.sink, this.onFailure) {
    if (sink case final IOSink io) {
      // Register before the first write. Never await an open stdout.done.
      unawaited(
        io.done.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {
            _fail();
          },
        ),
      );
    }
  }

  final StringSink sink;
  final void Function() onFailure;
  final _pending = Queue<String>();
  final _failed = Completer<void>();
  Completer<void>? _idle;
  bool _broken = false;
  bool _writing = false;

  void add(String record) {
    if (_broken) return;
    if (_pending.length + (_writing ? 1 : 0) >= 128) {
      _fail();
      return;
    }
    _pending.add(record);
    if (!_writing) {
      _idle = Completer<void>();
      _writing = true;
      unawaited(_pump());
    }
  }

  Future<void> _pump() async {
    try {
      while (!_broken && _pending.isNotEmpty) {
        sink.writeln(_pending.removeFirst());
        if (sink case final IOSink io) await io.flush();
      }
    } catch (_) {
      _fail();
    } finally {
      _writing = false;
      _idle!.complete();
    }
  }

  void _fail() {
    if (_broken) return;
    _broken = true;
    _pending.clear();
    _failed.complete();
    onFailure();
  }

  Future<void> drain() async {
    final idle = _idle;
    if (idle != null) await Future.any([idle.future, _failed.future]);
  }
}
