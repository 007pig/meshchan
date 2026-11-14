import 'dart:async';

import 'package:meshchan_core/meshchan_core.dart';

import '../device/model.dart';
import '../profiles/preview.dart';
import '../runtime/controller.dart';
import '../runtime/protocol.dart';

/// Session-owned invocation inputs. Preview is never the execution authority.
final class DiagnosticsModel extends ParameterPreview {
  DiagnosticsModel(AppRuntime runtime, this.device)
    : super(runtime, operation: DiagnosticOperation.ping) {
    _states = runtime.changes.listen((_) => notify());
    device.addListener(notify);
  }
  final DeviceModel device;
  late final StreamSubscription<RuntimeSnapshot> _states;
  DiagnosticHandle? handle;
  bool starting = false;
  RuntimeFault? actionFailure;
  // Explicit local input context, separate from safe result snapshots.
  String? frozenPort;
  EffectiveParameterRequest? frozenRequest;
  ({int id, String? port})? _previousResultPort;
  int? cancelRequested;
  OperationSnapshot? get attempt {
    final observed = runtime.snapshot.operation;
    // A pending Start has its own local inputs. Do not label the previous
    // attempt's outcomes with those inputs while its admission is unknown.
    return starting && observed?.attemptId != handle?.id ? null : observed;
  }

  String? get attemptPort {
    final id = runtime.snapshot.operation?.attemptId;
    if (id == null) return null;
    if (id == handle?.id) return frozenPort;
    return id == _previousResultPort?.id ? _previousResultPort?.port : null;
  }

  bool get locked =>
      starting ||
      (attempt != null &&
          !attempt!.done &&
          runtime.snapshot.phase != RuntimePhase.fault);
  bool get canStart =>
      !locked &&
      device.canAccess &&
      device.available &&
      device.listed &&
      !device.stale &&
      !runtime.snapshot.stopReceived;
  bool allowChange() => !locked && !deferChangeForComposition();

  void changeOperation(DiagnosticOperation operation) {
    if (!allowChange() ||
        ![
          DiagnosticOperation.ping,
          DiagnosticOperation.respond,
        ].contains(operation)) {
      return;
    }
    form.changeType(operation);
    fieldGeneration++;
    invalidate();
  }

  Future<void> startDiagnostic() async {
    if (!canStart || deferChangeForComposition()) return;
    final observedId = runtime.snapshot.operation?.attemptId;
    if (observedId != null && observedId == handle?.id) {
      _previousResultPort = (id: observedId, port: frozenPort);
    }
    try {
      final request = form.request(
        profileId: profileId,
        content: form.operation == DiagnosticOperation.ping ? bytes : null,
      );
      final port = device.selected!;
      starting = true;
      actionFailure = null;
      cancelRequested = null;
      final current = handle = runtime.startRecordedDiagnostic(port, request);
      frozenPort = port;
      frozenRequest = request;
      notify();
      await current.accepted;
    } catch (e) {
      // A lost ACK does not prove rejection. Keep the latest Start identity and
      // captured input; any retained older result uses its own port association.
      actionFailure = e is FormatException
          ? const RuntimeFault(core: CoreErrorCode.invalidInput)
          : RuntimeFault.from(e);
    } finally {
      starting = false;
      notify();
    }
  }

  Future<void> cancelDiagnostic() async {
    final current = handle;
    if (current == null ||
        deferChangeForComposition() ||
        cancelRequested == current.id) {
      return;
    }
    cancelRequested = current.id;
    notify();
    try {
      await runtime.cancelRecordedDiagnostic(current);
    } catch (e) {
      actionFailure = RuntimeFault.from(e);
      notify();
    }
  }

  @override
  void dispose() {
    device.removeListener(notify);
    unawaited(_states.cancel());
    super.dispose();
  }
}
