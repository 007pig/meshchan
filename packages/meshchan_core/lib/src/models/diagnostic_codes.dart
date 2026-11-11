/// Explicit summary vocabulary. These are not communication enums or a mapper.
enum DiagnosticRecordState {
  prepared('prepared'),
  settled('settled'),
  recoveredArchived('recovered_archived');

  const DiagnosticRecordState(this.code);
  final String code;
}

enum RecoveryReason {
  interrupted('interrupted'),
  cleanupUnconfirmed('cleanup_unconfirmed');

  const RecoveryReason(this.code);
  final String code;
}

enum CleanupState {
  unconfirmed('unconfirmed'),
  pending('pending'),
  notRequired('not_required'),
  succeeded('succeeded'),
  failed('failed'),
  unconfirmedAfterExit('unconfirmed_after_exit');

  const CleanupState(this.code);
  final String code;
}

/// Task reasons retain their existing meaning; finite raw-operation reasons
/// are separate members, not additions to the communication task enum.
enum LogicalReason {
  completed('completed'),
  startRejected('startRejected'),
  nonceGenerationFailed('nonceGenerationFailed'),
  initializationFailed('initializationFailed'),
  sendFailed('sendFailed'),
  receptionFailed('receptionFailed'),
  sessionFailed('sessionFailed'),
  responseTimeout('responseTimeout'),
  taskTimeout('taskTimeout'),
  canceled('canceled'),
  entryLimit('entryLimit'),
  sigint('sigint'),
  sigterm('sigterm'),
  outputFailure('output_failure'),
  unexpectedFailure('unexpected_failure');

  const LogicalReason(this.code);
  final String code;
}

enum DiagnosticStage {
  startup('startup'),
  nonceGeneration('nonceGeneration'),
  connecting('connecting'),
  receiving('receiving'),
  sending('sending'),
  waiting('waiting'),
  settling('settling');

  const DiagnosticStage(this.code);
  final String code;
}

enum ReceptionReason {
  startRejected('startRejected'),
  stopped('stopped'),
  subscriptionCanceled('subscriptionCanceled'),
  durationElapsed('durationElapsed'),
  entryLimit('entryLimit'),
  sessionClosed('sessionClosed'),
  sessionFailed('sessionFailed');

  const ReceptionReason(this.code);
  final String code;
}

enum ListenStopReason {
  durationElapsed('durationElapsed'),
  responseLimit('responseLimit'),
  entryLimit('entryLimit');

  const ListenStopReason(this.code);
  final String code;
}

enum FailureDomain {
  task('task'),
  session('session'),
  host('host'),
  cleanup('cleanup');

  const FailureDomain(this.code);
  final String code;
}

/// Controlled classifications only; never an exception message or runtime type.
enum FailureKind {
  startRejected('startRejected'),
  nonceGenerationFailed('nonceGenerationFailed'),
  initializationFailed('initializationFailed'),
  sendFailed('sendFailed'),
  receptionFailed('receptionFailed'),
  sessionFailed('sessionFailed'),
  responseTimeout('responseTimeout'),
  taskTimeout('taskTimeout'),
  canceled('canceled'),
  transport('transport'),
  protocol('protocol'),
  deviceRejected('deviceRejected'),
  requestTimeout('requestTimeout'),
  initializationTimeout('initializationTimeout'),
  disconnected('disconnected'),
  cleanup('cleanup'),
  outputFailure('output_failure'),
  unexpectedFailure('unexpected_failure');

  const FailureKind(this.code);
  final String code;
}

enum SessionStage {
  idle('idle'),
  opening('opening'),
  initializing('initializing'),
  ready('ready'),
  closing('closing'),
  closed('closed'),
  failed('failed');

  const SessionStage(this.code);
  final String code;
}

enum HostCleanupStage {
  entriesSubscription('entriesSubscription'),
  sessionSubscription('sessionSubscription'),
  signalSubscription('signalSubscription');

  const HostCleanupStage(this.code);
  final String code;
}

enum DeviceErrorName {
  unsupportedCommand('unsupported command'),
  notFound('not found'),
  tableFull('table full'),
  badState('bad state'),
  fileIoError('file I/O error'),
  illegalArgument('illegal argument');

  const DeviceErrorName(this.code);
  final String code;
}
