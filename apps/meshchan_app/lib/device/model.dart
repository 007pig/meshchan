import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meshcore_link/meshcore_link.dart' show SerialPortDescription;

import '../runtime/controller.dart';
import '../runtime/protocol.dart';

/// Application-session selection and raw inputs. Widgets own no check lifetime.
final class DeviceModel extends ChangeNotifier {
  DeviceModel(this.runtime) {
    for (final c in inputs) {
      c.addListener(_changed);
    }
    _states = runtime.changes.listen((_) => _notify());
  }
  final AppRuntime runtime;
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  final request = TextEditingController(text: '5');
  final initialization = TextEditingController(text: '15');
  final startup = TextEditingController(text: '0');
  List<TextEditingController> get inputs => [request, initialization, startup];
  late final StreamSubscription<RuntimeSnapshot> _states;
  List<SerialPortDescription> ports = const [];
  String? selected;
  DeviceFailure? refreshFailure;
  RuntimeFault? actionFailure;
  bool refreshing = false, listed = false, stale = false, starting = false;
  int listGeneration = 0;
  DeviceCheckHandle? handle;
  int? cancelRequested;
  RuntimeSnapshot get snapshot => runtime.snapshot;
  bool get composing => inputs.any(
    (c) => c.value.composing.isValid && !c.value.composing.isCollapsed,
  );
  bool get available =>
      selected != null && ports.any((p) => p.path == selected);
  bool get canAccess =>
      snapshot.phase == RuntimePhase.ready &&
      !snapshot.admissionPaused &&
      snapshot.gate == DeviceGateState.free &&
      !refreshing &&
      !starting;
  static int? _decimal(String value) =>
      !value.contains('\n') &&
          !value.contains('\r') &&
          RegExp(r'^[0-9]+$').hasMatch(value)
      ? int.tryParse(value)
      : null;
  DeviceCheckOptions? get options {
    final r = _decimal(request.text),
        i = _decimal(initialization.text),
        s = _decimal(startup.text);
    if (r == null || i == null || s == null) return null;
    final value = DeviceCheckOptions(
      requestSeconds: r,
      initializationSeconds: i,
      startupMilliseconds: s,
    );
    return value.valid ? value : null;
  }

  String? get inputError => options == null
      ? 'Use decimal integers: request and initialization 1–86400 seconds; startup 0–86399999 ms and less than initialization × 1000.'
      : null;
  void _changed() => _notify();
  bool allowAction() => !composing;
  void select(String path) {
    if (!allowAction() || !ports.any((p) => p.path == path)) return;
    selected = path;
    _notify();
  }

  Future<void> refresh() async {
    if (!canAccess || !allowAction()) return;
    final generation = ++listGeneration;
    refreshing = true;
    actionFailure = null;
    _notify();
    try {
      final result = await runtime.refreshDevicePorts(generation);
      if (result.generation != listGeneration) return;
      refreshFailure = result.failure;
      stale = result.failure != null && listed;
      if (result.failure == null) {
        ports = result.ports;
        listed = true;
        if (!available) selected = null;
      }
    } catch (e) {
      actionFailure = RuntimeFault.from(e);
      stale = listed;
    } finally {
      refreshing = false;
      _notify();
    }
  }

  Future<void> check() async {
    if (!canAccess ||
        !allowAction() ||
        !available ||
        stale ||
        options == null) {
      return;
    }
    starting = true;
    actionFailure = null;
    cancelRequested = null;
    final next = handle = runtime.startDeviceCheck(selected!, options!);
    _notify();
    try {
      await next.accepted;
    } catch (e) {
      actionFailure = RuntimeFault.from(e);
    } finally {
      starting = false;
      _notify();
    }
  }

  Future<void> cancel() async {
    final id = starting ? handle?.id : snapshot.deviceCheck?.id;
    if (id == null || !allowAction()) return;
    cancelRequested = id;
    _notify();
    try {
      await runtime.cancelDeviceCheck(id);
    } catch (e) {
      actionFailure = RuntimeFault.from(e);
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_states.cancel());
    for (final c in inputs) {
      c.dispose();
    }
    super.dispose();
  }
}
