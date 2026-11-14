import 'dart:async';

import 'package:meshcore_link/meshcore_link.dart';

import 'device_protocol.dart';

/// Worker-owned single attempt. The dispatcher registers its full settlement
/// barrier before run() can construct anything. No native objects leave here.
final class FiniteDeviceCheck {
  FiniteDeviceCheck(
    this.id,
    this.port,
    this.options, {
    required this.createTransport,
    required this.publish,
    MeshCoreSession Function(CompanionTransport, DeviceCheckOptions)?
    createSession,
    Future<void> Function(StreamSubscription<MeshCoreSessionEvent>)?
    cancelObserver,
  }) : createSession = createSession ?? _session,
       cancelObserver = cancelObserver ?? _cancelObserver;
  static MeshCoreSession _session(
    CompanionTransport transport,
    DeviceCheckOptions o,
  ) => MeshCoreSession(
    transport: transport,
    appName: 'Meshchan',
    requestTimeout: Duration(seconds: o.requestSeconds),
    initializationTimeout: Duration(seconds: o.initializationSeconds),
    startupDelay: Duration(milliseconds: o.startupMilliseconds),
  );
  static Future<void> _cancelObserver(
    StreamSubscription<MeshCoreSessionEvent> subscription,
  ) => subscription.cancel();
  final int id;
  final String port;
  final DeviceCheckOptions options;
  final CompanionTransport Function(String) createTransport;
  final MeshCoreSession Function(CompanionTransport, DeviceCheckOptions)
  createSession;
  final Future<void> Function(StreamSubscription<MeshCoreSessionEvent>)
  cancelObserver;
  final void Function(DeviceCheckSnapshot) publish;
  MeshCoreSession? _sessionValue;
  Future<void>? _closing;
  bool _cancel = false, _settled = false;
  MeshCoreSessionState _state = MeshCoreSessionState.idle;
  DeviceCleanup _cleanup = DeviceCleanup.notRequired,
      _observer = DeviceCleanup.notRequired;
  DeviceFailure? _failure, _cleanupFailure, _observerFailure;
  DeviceInformation? _info;
  DeviceCheckSnapshot get snapshot => DeviceCheckSnapshot(
    id: id,
    port: port,
    options: options,
    state: _state,
    cancelApplied: _cancel,
    sessionCleanup: _cleanup,
    observerCleanup: _observer,
    failure: _failure,
    cleanupFailure: _cleanupFailure,
    observerFailure: _observerFailure,
    info: _info,
    settled: _settled,
  );
  void _emit() => publish(snapshot);
  void cancel() {
    if (_settled) return;
    _cancel = true;
    _emit();
    if (_sessionValue != null) _close();
  }

  Future<void> _close() => _closing ??= _observeClose();
  Future<void> _observeClose() async {
    _cleanup = DeviceCleanup.pending;
    _state = MeshCoreSessionState.closing;
    _emit();
    try {
      await _sessionValue!.close();
      _cleanup = DeviceCleanup.succeeded;
    } catch (e) {
      _cleanup = DeviceCleanup.failed;
      _cleanupFailure = DeviceFailure.from(e);
    }
    _state = _sessionValue!.state;
    _emit();
  }

  Future<void> run() async {
    CompanionTransport? unowned;
    StreamSubscription<MeshCoreSessionEvent>? observer;
    try {
      // A processable stop/cancel checkpoint precedes construction/open.
      await Future<void>.delayed(Duration.zero);
      if (_cancel) return;
      unowned = createTransport(port);
      _cleanup = DeviceCleanup.pending;
      final session = _sessionValue = createSession(unowned, options);
      unowned = null; // Session exclusively owns transport, including close.
      observer = session.events.listen(
        (event) {
          if (_settled) return;
          if (event is MeshCoreSessionStateChanged) _state = event.state;
          if (event is MeshCoreSessionFailed &&
              event.failure.kind != MeshCoreSessionFailureKind.cleanup) {
            _failure ??= DeviceFailure.from(event.failure);
          }
          _emit();
        },
        onError: (Object _) {
          _observerFailure = const DeviceFailure('observationFailed');
          cancel();
        },
      );
      _observer = DeviceCleanup.pending;
      if (_cancel) return;
      try {
        final info = await session.connect();
        _info = DeviceInformation(info, port, DateTime.now().toUtc());
        _state = session.state;
        _emit(); // Information is visible even if close never settles.
      } catch (e) {
        _failure ??= DeviceFailure.from(e);
        _emit();
      }
    } catch (e) {
      _failure ??= DeviceFailure.from(e);
      _emit();
    } finally {
      if (_sessionValue != null) {
        await _close(); // Same actual close result on every path.
      } else if (unowned != null) {
        try {
          await unowned.close();
          _cleanup = DeviceCleanup.succeeded;
        } catch (e) {
          _cleanup = DeviceCleanup.failed;
          _cleanupFailure = DeviceFailure.from(e);
        }
      }
      final primary = _sessionValue?.lastFailure;
      if (primary != null &&
          primary.kind != MeshCoreSessionFailureKind.cleanup) {
        _failure ??= DeviceFailure.from(primary);
      }
      if (observer != null) {
        try {
          await cancelObserver(observer);
          _observer = _observerFailure == null
              ? DeviceCleanup.succeeded
              : DeviceCleanup.failed;
        } catch (_) {
          _observer = DeviceCleanup.failed;
          _observerFailure = const DeviceFailure('observerCleanup');
        }
      }
      _settled = true;
      _emit();
    }
  }
}
