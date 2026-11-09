/// Reusable, Flutter-independent communication core for MeshCore applications.
///
/// Serial diagnostics do not identify devices or establish protocol sessions.
library;

export 'src/protocol/serial_framing.dart'
    show
        maxSerialFrameContentLength,
        encodeSerialFrame,
        SerialFrameDecoder,
        SerialFrameDecodeResult,
        SerialFrameDecodeError,
        SerialFrameDecodeErrorKind;
export 'src/serial_ports.dart'
    show SerialPortDescription, SerialPortFailure, SerialPorts;
export 'src/transport/companion_transport.dart' show CompanionTransport;
export 'src/transport/serial_transport.dart'
    show SerialTransport, SerialTransportFailure, SerialTransportFailureKind;
