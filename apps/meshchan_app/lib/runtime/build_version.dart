/// Manifest-validated fallbacks for direct Dart processes and tests.
/// Flutter builds supply the actual name and number through build defines.
const String appBuildName = '0.1.0-beta.1';
const String appBuildNumber = '5';
const String appVersion =
    '${String.fromEnvironment('FLUTTER_BUILD_NAME', defaultValue: appBuildName)}+${String.fromEnvironment('FLUTTER_BUILD_NUMBER', defaultValue: appBuildNumber)}';
