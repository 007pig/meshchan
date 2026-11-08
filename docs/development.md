# Developer Guide

## Project language

Use American English for all project documentation, code comments, CLI output, and configuration text. Keep code identifiers in English as well.

## SDK and validation baseline

The local Flutter SDK is installed at `/opt/homebrew/share/flutter` and managed by Homebrew. Use its bundled Dart SDK. A separate Dart installation, FVM, mise, asdf, and Melos are not required.

The following local versions were verified on November 8, 2026:

| Tool | Verified version |
| --- | --- |
| Flutter | 3.47.9, stable |
| Dart | 3.13.7, stable, bundled with Flutter |

Set PATH for the current terminal session without changing the global shell configuration:

```bash
export PATH="/opt/homebrew/share/flutter/bin:$PATH"
flutter --version --machine
dart --version
```

To check the specified SDK directly:

```bash
/opt/homebrew/share/flutter/bin/flutter --version --machine
/opt/homebrew/share/flutter/bin/dart --version
```

All packages use `sdk: ^3.13.0`. This constraint includes the verified version and allows subsequent compatible Dart 3.x updates. Pub Workspaces require Dart 3.6 or later. Other SDK versions have not been validated for this project.

## Install dependencies and run the CLI

Start the following commands from the project root. When cloning the project with an existing lockfile, run:

```bash
dart pub get --enforce-lockfile
```

When generating the lockfile for the first time or intentionally changing dependencies, run `dart pub get`, review the lockfile changes, and then run `dart pub get --enforce-lockfile`. Let pub generate the lockfile; do not write it manually.

Run the CLI:

```bash
cd apps/meshctl
dart run bin/meshctl.dart --help
dart run bin/meshctl.dart -h
dart run bin/meshctl.dart --version
dart run bin/meshctl.dart
```

Help, version, and no-argument invocations write to stdout and exit with code `0`. Unknown options, such as `--unknown`, and unsupported positional arguments, such as `ports`, write a brief error and a help hint to stderr and exit with code `64`. Normal argument errors do not display stack traces. When both help and version are requested, help takes precedence. Invalid arguments are rejected before either action runs.

The application version is defined in `apps/meshctl/lib/src/version.dart`. When changing it, update `apps/meshctl/pubspec.yaml` and the version behavior test at the same time. The CLI does not read a pubspec in the current working directory to determine its version.

## Format, analyze, and test

Run these commands from the project root:

```bash
dart pub get
dart pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
```

When fixing formatting, format only the Dart files involved in the change. For this initial implementation, those files are in these directories:

```bash
dart format packages/meshcore_link/lib apps/meshctl/bin apps/meshctl/lib apps/meshctl/test
```

Run tests and smoke checks in the CLI package, which contains the project's tests:

```bash
cd apps/meshctl
dart test
dart run bin/meshctl.dart --help
dart run bin/meshctl.dart --version
dart run bin/meshctl.dart
```

Also check the error exit code and stderr on macOS or Linux:

```bash
dart run bin/meshctl.dart --unknown
echo $?
```

The expected exit code is `64`, which confirms the intended error handling. Unit tests inject `StringBuffer` instances to check stdout, stderr, and exit codes together. They do not access the network or hardware or start the Flutter engine. The `meshcore_link` package has no application logic yet, so it has no placeholder tests.

Local verification on November 8, 2026, completed successfully: dependency resolution and `--enforce-lockfile` validation passed; the formatting check found no changes needed in five Dart files; static analysis found no issues; and all four CLI test groups passed. Process-level checks confirmed that help, version, and no-argument invocations exit with code `0`. Unknown options and positional arguments write errors only to stderr and exit with code `64`. Running the CLI file directly from an unrelated working directory also produced the correct version output.

## Workspace and lockfile conventions

The root `pubspec.yaml` explicitly lists `packages/meshcore_link` and `apps/meshctl`. Both members set `resolution: workspace`, and all three pubspec files set `publish_to: none`.

Keep only the root `pubspec.lock` for the entire workspace and include it in version control with the source code. Member packages do not maintain separate lockfiles. Exclude `.dart_tool`, build output, caches, and temporary IDE files from version control.

The `meshctl` package declares a normal version dependency on `meshcore_link`. [Pub Workspace dependency resolution](https://dart.dev/tools/pub/workspaces#interdependencies-between-workspace-packages) selects the local member without `dependency_overrides`. List the workspace members from the project root:

```bash
dart pub workspace list
```

The CLI package declares `args` and `test`; the root package provides the shared `lints` configuration. Both workspace members are ordinary Dart packages with no Flutter SDK dependencies or Flutter version constraints.

## CI and SDK updates

The `.github/workflows/ci.yml` workflow runs on pushes, pull requests, and manual dispatches. It uses one `ubuntu-latest` job with `contents: read` permissions. CI pins Flutter to `3.47.9`, uses its bundled Dart SDK, installs dependencies according to the root lockfile, and runs formatting checks, static analysis, CLI tests, and help/version smoke checks.

Flutter setup uses the verified [subosito/flutter-action v2.23.0](https://github.com/subosito/flutter-action/tree/v2.23.0) release with explicit `channel` and `flutter-version` inputs. CI does not depend on the local Homebrew path or install another Dart SDK.

Homebrew can continue to manage the local SDK. After a Homebrew SDK update:

1. Record the actual Flutter and Dart versions and release channel with the correct PATH.
2. Run dependency resolution, lockfile validation, formatting checks, static analysis, tests, and CLI smoke checks from this guide.
3. Review any necessary lockfile changes. Resolve SDK compatibility issues before changing the CI baseline.
4. After all checks pass, update the verified versions and date in this guide together with the CI `flutter-version`. Adjust the compatible Dart SDK constraint if necessary.

The initial setup does not upgrade the SDK, switch release channels, reinstall Homebrew packages, or change SDK source code or the system PATH.

## Environment limitations and unverified scope

This phase is a pure Dart project. Android, iOS, Xcode, browser toolchains, and radio hardware are not required, and no graphical environment is started.

The first SDK invocation in the restricted sandbox could not write to the SDK cache. After normal execution permission approval, SDK version checks and all local acceptance checks above succeeded. If an execution environment still prevents SDK cache initialization or pub dependency downloads, it must provide the appropriate access. Do not use sudo or change permissions to bypass restrictions.

Before initialization, the project directory was empty and had no independent Git metadata. Git discovers a parent repository outside the project directory and reports a symbolic link loop while reading that repository's `.gitignore`. This setup created project files only within the project directory and preserved the existing Git state. It did not initialize a separate repository, commit, push, or change the parent repository's configuration. The CI workflow assumes this project directory is the repository root and should run in a GitHub repository rooted here.

Remote GitHub Actions have not been run. Local verification does not establish that the remote Ubuntu CI has passed. Other operating systems, other SDK versions, and device functionality remain unverified. The current implementation covers only Phase 1 / 1A / Step 1.
