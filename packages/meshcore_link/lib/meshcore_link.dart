/// Reusable, Flutter-independent communication core for MeshCore applications.
///
/// Serial diagnostics do not identify devices or establish protocol sessions.
library;

export 'src/protocol/companion_messages.dart'
    show
        encodeAppStart,
        encodeDeviceQuery,
        encodeSendChannelData,
        encodeSyncNextMessage,
        decodeCompanionResponse,
        CompanionResponse,
        SelfInfoResponse,
        DeviceInfoResponse,
        DeviceErrorResponse,
        OkResponse,
        MessageWaitingResponse,
        NoMoreMessagesResponse,
        ChannelDataResponse,
        QueuedMessageResponse,
        QueuedMessageKind,
        UnhandledCompanionResponse,
        CompanionProtocolException,
        CompanionProtocolExceptionKind;
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
export 'src/session/meshcore_session.dart'
    show
        meshCoreSessionAppTargetVersion,
        MeshCoreSession,
        MeshCoreSessionInfo,
        MeshCoreSessionState,
        MeshCoreSessionFailure,
        MeshCoreSessionFailureKind,
        MeshCoreSessionQueueFull,
        MeshCoreSessionCommandFailure,
        MeshCoreReception,
        MeshCoreReceptionResult,
        MeshCoreReceptionStopReason,
        MeshCoreSessionEvent,
        MeshCoreSessionStateChanged,
        MeshCoreSessionUnassociatedResponse,
        MeshCoreSessionFailed;
export 'src/transport/companion_transport.dart' show CompanionTransport;
export 'src/transport/serial_transport.dart'
    show SerialTransport, SerialTransportFailure, SerialTransportFailureKind;
