import 'dart:typed_data';

/// One connection attempt carrying complete inner Companion content.
/// Neither opening nor accepting outgoing bytes establishes a device session.
abstract interface class CompanionTransport {
  /// Single-subscription stream. Subscribe before opening and consume without
  /// pausing. Canceling or pausing requests connection shutdown.
  Stream<Uint8List> get frames;

  Future<void> open();
  Future<void> sendFrame(Uint8List content);
  Future<void> close();
}
