import 'package:meshchan_core/meshchan_core.dart';
import 'package:test/test.dart';

void main() {
  final id = LocalId('0123456789abcdef0123456789abcdef');
  final instant = DateTime.utc(2026, 11, 11, 12, 30, 0, 123, 456);
  final invalidInput = isA<CoreException>().having(
    (error) => error.code,
    'code',
    CoreErrorCode.invalidInput,
  );

  for (final (body, byteLength) in [
    ('', 0),
    ('中文', 6),
    ('🙂', 4),
    ('中🙂\r\nA\n', 11),
  ]) {
    test('draft preserves exact text and derives $byteLength UTF-8 bytes', () {
      final draft = Draft(
        id: id,
        content: DraftContent(title: '  \t', body: body),
        createdAt: instant,
      );
      expect(draft.title, '  \t');
      expect(draft.body, body);
      expect(draft.bodyUtf8ByteLength, byteLength);
      expect(draft.revision, 1);
      expect(draft.updatedAt, instant);
      expect(draft.toString(), isNot(contains(body.isEmpty ? 'Draft(' : body)));
    });
  }

  test('draft content larger than a radio packet is retained', () {
    final body = '中🙂\n' * 1000;
    final content = DraftContent(body: body);
    expect(content.body, body);
    expect(content.bodyUtf8ByteLength, 8000);
  });

  test('IDs accept only the opaque lowercase 32-hex representation', () {
    expect(LocalId(id.value), id);
    for (final value in [
      '',
      '01234567-89ab-cdef-0123-456789abcdef',
      '0123456789ABCDEF0123456789ABCDEF',
      '${id.value}0',
      '${id.value}\n',
      'g123456789abcdef0123456789abcdef',
    ]) {
      expect(() => LocalId(value), throwsA(invalidInput));
    }
  });

  test(
    'profile path, cleanup evidence, and page collections own their input',
    () {
      final bytes = [0x12, 0x34];
      final route = ProfileRoute(routeDescriptor: 2, path: bytes);
      final profile = ProfileContent(
        name: '  Saved preset  ',
        portHint: ' /local/hint ',
        parameters: SendProfileParameters(
          budgets: const ProfileBudgets(taskTimeoutSeconds: 10),
          sendChannelIndex: 1,
          route: route,
          dataType: 1,
        ),
      );
      bytes[0] = 255;
      bytes.add(1);
      expect(route.path, [0x12, 0x34]);
      expect(() => route.path[0] = 0, throwsUnsupportedError);
      expect(profile.name, '  Saved preset  ');
      expect(profile.portHint, ' /local/hint ');
      expect(profile.toString(), isNot(contains('/local/hint')));

      final failures = [const FailureSummary(domain: FailureDomain.cleanup)];
      final cleanup = CleanupScopeSummary(failures: failures);
      failures.clear();
      expect(cleanup.failureCount, 1);
      expect(() => cleanup.failures.clear(), throwsUnsupportedError);

      final items = [id];
      final page = Page<LocalId, UpdatedCursor>(items: items);
      items.clear();
      expect(page.items, [id]);
      expect(() => page.items.clear(), throwsUnsupportedError);
    },
  );

  test('pagination and settings defaults and inclusive boundaries', () {
    expect(PageSize().value, 50);
    expect(AppSettings().defaultProfileId, isNull);
    expect(AppSettings().diagnosticHistoryLimit, 1000);
    for (final limit in [1, 200]) {
      expect(PageSize(limit).value, limit);
    }
    for (final limit in [0, -1, 201]) {
      expect(() => PageSize(limit), throwsA(invalidInput));
    }
    for (final limit in [1, 100000]) {
      expect(
        AppSettings(diagnosticHistoryLimit: limit).diagnosticHistoryLimit,
        limit,
      );
    }
    for (final limit in [0, -1, 100001]) {
      expect(
        () => AppSettings(diagnosticHistoryLimit: limit),
        throwsA(invalidInput),
      );
    }
  });

  test('business instants/cursors require UTC and valid range', () {
    final local = DateTime(2026, 11, 11);
    expect(
      () => UpdatedCursor(updatedAt: local, id: id),
      throwsA(invalidInput),
    );
    expect(
      () => HistoryCursor(preparedAt: local, runId: id),
      throwsA(invalidInput),
    );
    expect(
      () => HistoryQuery(
        preparedFromInclusive: instant,
        preparedUntilExclusive: instant,
      ),
      throwsA(invalidInput),
    );
    expect(
      UpdatedCursor(updatedAt: instant, id: id).updatedAt.microsecond,
      456,
    );
  });

  test('unknown diagnostic facts stay unknown across independent scopes', () {
    final run = DiagnosticRun(
      runId: id,
      appVersion: '0.1.0-dev.2',
      configuration: const PingConfiguration(
        budgets: ProfileBudgets(taskTimeoutSeconds: 10),
        sendChannelIndex: 0,
        receiveChannelIndex: 1,
        route: DiagnosticRoute(routeDescriptor: 0, pathByteCount: 0),
        maxEntries: 128,
        responseTimeoutSeconds: 5,
        contentByteLength: 0,
      ),
      preparedAt: instant,
      result: const PingSummary(),
      cleanup: CleanupSummary(
        core: CleanupScopeSummary(state: CleanupState.succeeded),
      ),
    );
    final result = run.result! as PingSummary;
    expect(result.send, isNull);
    expect(result.reception, isNull);
    expect(result.reason, isNull);
    expect(result.matchingPongObserved, isNull);
    expect(result.roundTripSucceeded, isNull);
    expect(result.matchingPongDuplicates, isNull);
    expect(result.applicationRttUs, isNull);
    expect(run.logicalEndedAt, isNull);
    expect(run.cleanup.core.state, CleanupState.succeeded);
    expect(run.cleanup.hostSubscriptions.state, CleanupState.unconfirmed);
    expect(run.cleanup.aggregate, CleanupState.unconfirmed);

    const send = SendFacts(
      attempted: true,
      pendingAtTermination: true,
      deviceAcceptanceConfirmed: false,
    );
    expect(send.dispatched, isNull);
    expect(send.localWriteCompleted, isNull);
    expect(send.localOkObserved, isNull);
  });

  test('business error vocabulary is explicit and safe by default', () {
    expect(CoreErrorCode.values.map((value) => value.code), [
      'invalid_input',
      'not_found',
      'conflict',
      'data_directory_busy',
      'storage_open_failed',
      'storage_read_failed',
      'storage_write_failed',
      'unsupported_database_version',
      'database_corrupt',
    ]);
    expect(
      const CoreException(CoreErrorCode.storageWriteFailed).toString(),
      'CoreException(storage_write_failed)',
    );
    expect(DiagnosticRecordState.recoveredArchived.code, 'recovered_archived');
    expect(CleanupState.unconfirmedAfterExit.code, 'unconfirmed_after_exit');
    expect(RecoveryReason.cleanupUnconfirmed.code, 'cleanup_unconfirmed');
    expect(diagnosticSummaryFormatVersion, 1);
  });
}
