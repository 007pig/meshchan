import 'models/app_settings.dart';
import 'models/connection_profile.dart';
import 'models/diagnostic_codes.dart';
import 'models/diagnostic_run.dart';
import 'models/draft.dart';
import 'validation.dart';
import 'values.dart';

/// Contracts only: no storage implementation is provided in 1C.2.
///
/// Every mutation succeeds only after its transaction commits. Failures use
/// CoreException's stable categories and preserve the prior complete version.
/// The host supplies storage resources and exclusive directory ownership. All
/// business access, including reads, requires that ownership; contention fails
/// immediately with data_directory_busy. Directory identity and locks are 1C.3.
abstract interface class DraftRepository {
  /// Generates an ID and initial revision 1. Empty exact text is valid.
  Future<Draft> create(DraftContent content);

  /// Missing IDs fail with not_found.
  Future<Draft> read(LocalId id);

  /// Positive expected revision is required. Mismatch is conflict. Changed
  /// content increments revision once; unchanged content retains revision/time.
  Future<Draft> update(
    LocalId id,
    DraftContent content, {
    required int expectedRevision,
  });

  /// Explicit hard delete; missing ID is not_found, stale revision is conflict.
  Future<void> delete(LocalId id, {required int expectedRevision});

  /// updatedAt DESC, id DESC; omitted size means 50, allowed range 1..200.
  Future<Page<Draft, UpdatedCursor>> list({
    PageSize? size,
    UpdatedCursor? after,
  });
}

/// Mutations have the same committed-success and ownership contract as drafts.
abstract interface class ProfileRepository {
  Future<ConnectionProfile> read(LocalId id);

  /// Null ID creates a profile with a generated ID; a supplied ID must exist.
  /// Validates the complete operation-specific preset using existing route and
  /// capacity rules without I/O. Replaces incompatible operation fields
  /// atomically. Unchanged content retains updatedAt. No effective-parameter
  /// merge or current explicit-port authorization is performed by this method.
  Future<ConnectionProfile> save(ProfileContent content, {LocalId? id});

  /// Missing ID is not_found. Clears a matching defaultProfileId in the same
  /// transaction. Never deletes history or edits a historical run snapshot.
  Future<void> delete(LocalId id);

  /// updatedAt DESC, id DESC; default size 50, allowed range 1..200.
  Future<Page<ConnectionProfile, UpdatedCursor>> list({
    PageSize? size,
    UpdatedCursor? after,
  });
}

abstract interface class SettingsRepository {
  /// Absent settings use defaults; dangling profile references are not_found.
  Future<AppSettings> read();

  /// Validates a nonnull defaultProfileId in the same transaction as the save.
  /// No coercion/clamping. Success means commit, including both setting fields.
  /// Later bounded eligible-history pruning is scheduled on limit changes;
  /// pruning failure is reported without undoing an already committed save.
  Future<AppSettings> save(AppSettings settings);

  /// Explicitly restores the two defaults, preserving unrelated business data.
  Future<AppSettings> restoreDefaults();
}

final class HistoryQuery {
  HistoryQuery({
    this.operation,
    this.recordState,
    DateTime? preparedFromInclusive,
    DateTime? preparedUntilExclusive,
  }) : preparedFromInclusive = preparedFromInclusive == null
           ? null
           : requireUtc(preparedFromInclusive),
       preparedUntilExclusive = preparedUntilExclusive == null
           ? null
           : requireUtc(preparedUntilExclusive) {
    requireValid(
      preparedFromInclusive == null ||
          preparedUntilExclusive == null ||
          preparedFromInclusive.isBefore(preparedUntilExclusive),
    );
  }
  final DiagnosticOperation? operation;
  final DiagnosticRecordState? recordState;
  final DateTime? preparedFromInclusive;
  final DateTime? preparedUntilExclusive;
}

/// Read-only history. Field-specific writes belong to the later recording
/// coordinator; no API here can replace a run or turn failure into success.
abstract interface class DiagnosticHistory {
  /// A missing requested run is not_found. Requires directory ownership.
  Future<DiagnosticRun> read(LocalId runId);

  /// preparedAt DESC, runId DESC; default size 50, allowed range 1..200.
  /// Separate calls are not a snapshot. Invalid cursors/limits are invalid_input.
  Future<Page<DiagnosticRun, HistoryCursor>> query({
    HistoryQuery? filter,
    PageSize? size,
    HistoryCursor? after,
  });
}
