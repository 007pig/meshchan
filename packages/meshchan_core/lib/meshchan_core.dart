/// Offline business values and asynchronous persistence contracts.
/// Persistent drafts/profiles/settings and typed resolution without device I/O.
library;

export 'src/storage/database.dart' show databaseSchemaVersion;
export 'src/storage/storage.dart' show CoreStorage, StorageState;

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

export 'src/models/effective_parameters.dart'
    show
        BudgetOverrides,
        RouteOverrides,
        EndpointOverrides,
        DataTypeOverride,
        SendOverrides,
        ListenOverrides,
        PingOverrides,
        RespondOverrides,
        EffectiveParameterRequest,
        SendParameterRequest,
        ListenParameterRequest,
        PingParameterRequest,
        RespondParameterRequest,
        EffectiveParameters;
