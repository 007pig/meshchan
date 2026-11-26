import '../connection_target.dart';
import 'companion_transport.dart';
import 'serial_transport.dart' show createUsbCompanionTransport;

/// Creates a fresh, unopened transport for one explicit [ConnectionTarget].
///
/// Compose and invoke the factory in the same isolate. The caller owns
/// subscription, opening, and closing. Creation does not acquire the device
/// or establish a session.
typedef CompanionTransportFactory = CompanionTransport Function(
  ConnectionTarget target,
);

/// The configured factory has no adapter for [kind].
final class UnsupportedCompanionTransportException implements Exception {
  const UnsupportedCompanionTransportException(this.kind);

  final CompanionTransportKind kind;

  @override
  String toString() =>
      'UnsupportedCompanionTransportException: '
      'This factory has no ${kind.name} adapter.';
}

/// Returns a factory that uses the existing USB initialization transport.
///
/// The host selects [appCompletionQueries] for USB initialization. The
/// factory forwards each USB path verbatim and returns a new wrapper.
/// TCP and BLE targets throw [UnsupportedCompanionTransportException]
/// synchronously, before any connection work.
CompanionTransportFactory createCompanionTransportFactory({
  required bool appCompletionQueries,
}) => companionTransportFactoryWithUsbBuilder(
  appCompletionQueries: appCompletionQueries,
  createUsbTransport: createUsbCompanionTransport,
);

/// Internal composition seam. The USB builder returns a fresh, unopened
/// transport without acquiring resources for the connection.
CompanionTransportFactory companionTransportFactoryWithUsbBuilder({
  required bool appCompletionQueries,
  required CompanionTransport Function(
    String portPath, {
    required bool appCompletionQueries,
  })
  createUsbTransport,
}) =>
    (target) => switch (target) {
      UsbSerialTarget(:final portPath) => createUsbTransport(
        portPath,
        appCompletionQueries: appCompletionQueries,
      ),
      TcpTarget() ||
      BleTarget() => throw UnsupportedCompanionTransportException(target.kind),
    };
