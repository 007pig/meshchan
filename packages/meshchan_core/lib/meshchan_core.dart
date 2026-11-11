/// Offline business values and asynchronous persistence contracts.
/// No production database, repository implementation, or device I/O.
library;

export 'src/errors.dart' show CoreErrorCode, CoreException;
export 'src/models/app_settings.dart' show AppSettings;
export 'src/models/connection_profile.dart'
    show
        ProfileBudgets,
        ProfileRoute,
        ProfileTestEndpoints,
        ProfileParameters,
        SendProfileParameters,
        ListenProfileParameters,
        PingProfileParameters,
        RespondProfileParameters,
        ProfileContent,
        ConnectionProfile;
export 'src/models/diagnostic_codes.dart'
    show
        DiagnosticRecordState,
        RecoveryReason,
        CleanupState,
        LogicalReason,
        DiagnosticStage,
        ReceptionReason,
        ListenStopReason,
        FailureDomain,
        FailureKind,
        SessionStage,
        HostCleanupStage,
        DeviceErrorName;
export 'src/models/diagnostic_configuration.dart'
    show
        DiagnosticRoute,
        DiagnosticConfiguration,
        SendConfiguration,
        ListenConfiguration,
        TaskConfiguration,
        PingConfiguration,
        RespondConfiguration;
export 'src/models/diagnostic_run.dart'
    show
        diagnosticSummaryFormatVersion,
        SessionFailureSummary,
        FailureSummary,
        CommandFailureFacts,
        SendFacts,
        ReceptionSummary,
        LogicalSummary,
        SendSummary,
        ListenSummary,
        PingSummary,
        RespondSummary,
        CleanupScopeSummary,
        CleanupSummary,
        DiagnosticRun;
export 'src/models/draft.dart' show DraftContent, Draft;
export 'src/repositories.dart'
    show
        DraftRepository,
        ProfileRepository,
        SettingsRepository,
        HistoryQuery,
        DiagnosticHistory;
export 'src/values.dart'
    show
        LocalId,
        DiagnosticOperation,
        PageSize,
        UpdatedCursor,
        HistoryCursor,
        Page;
