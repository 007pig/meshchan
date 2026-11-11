import '../validation.dart';
import '../values.dart';

/// The complete settings vocabulary for 1C, not an arbitrary key/value store.
final class AppSettings {
  AppSettings({this.defaultProfileId, this.diagnosticHistoryLimit = 1000}) {
    requireValid(
      diagnosticHistoryLimit >= 1 && diagnosticHistoryLimit <= 100000,
    );
  }
  final LocalId? defaultProfileId;
  final int diagnosticHistoryLimit;
}
