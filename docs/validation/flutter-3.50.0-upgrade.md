# Flutter 3.50.0 upgrade — November 15, 2026

## Source and acceptance boundary

The upgrade starts from clean source revision
`8e7b81a9185540f5c139e0c54a99baf3d88655bb`. Local acceptance completed before
the changes were committed or published. This record establishes local results;
remote CI execution and distribution acceptance remain separate.
Acceptance is automated and hardware-free: full software suites, process
checks, native CLI bundles, macOS Debug/Release, isolated XCTest and finite
application persistence/shutdown checks. Actual GUI interaction, real Pinyin,
USB/serial enumeration or device opening, and RF acceptance are outside this run.
Prior dated validation and renderer investigations remain historical evidence.

Raw command logs and the command/result ledger are retained in the ignored
`build/flutter-3.50.0-20261115/` directory. Each ledger entry records the exact
argv, working directory, UTC start/end, exit status and selected Python path.
Failed exploratory checks are retained alongside the final gates.
`native-evidence-root.txt` identifies the separate owned temporary root for
process fixtures, application receipts, relocated products and XCTest results.
`source-manifest.json` and `product-manifest.json` retain final input/product
SHA-256 values; the latter covers complete app and CLI bundle contents.

## Installed toolchain

| Component | Actual value |
| --- | --- |
| Host | macOS 27.2.1 (26B131), arm64 |
| SDK installation | Existing Homebrew cask, `/opt/homebrew/share/flutter` |
| Flutter | 3.50.0 stable |
| Framework revision | `ab2912035e160d9cad6306df307576da6128ebdb` |
| Engine revision | `371f77202a73e8dff57a8b3bff75bca55c090aee` |
| Bundled Dart | 3.14.0 stable, `macos_arm64` |
| Xcode | 27.2, build 27B52; `/Applications/Xcode.app/Contents/Developer` |
| Compiler | Apple Clang 21.0.0 (`clang-2100.4.1.1`) |
| Python entry | `/opt/homebrew/bin/python3`, Python 3.15.2 |
| Python executable | `/opt/homebrew/opt/python@3.15/bin/python3.15` |

`brew update` completed, and `brew info --cask --json=v2 flutter` confirmed
installed 3.47.9 / available 3.50.0 before mutation. The approved
`HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade --cask --greedy flutter` completed
successfully. The cask downloaded Flutter's official arm64 archive with SHA-256
`ed2d08a3e3c023e84cbe9316d21bd88fda6ee9552f90c1eb4da41a07c170fb35`.
Both `/opt/homebrew/bin/flutter` and `/opt/homebrew/bin/dart` now link through
`/opt/homebrew/Caskroom/flutter/3.50.0/flutter/bin/`. No second SDK or separate
Dart installation was added. Native gates use a command-local PATH selecting
this SDK, Homebrew Python 3.15 and Apple Clang; global settings are unchanged.
The final Homebrew query reports both available and installed version 3.50.0.

`flutter doctor -v` reported the expected SDK and Xcode. It also reported
Android command-line tools/license configuration, an absent iOS simulator
runtime and absent CocoaPods. No Android/iOS acceptance or installation is
claimed; these observations are separate from this project's macOS build gates.

## Compatibility and dependency changes

- Both CI jobs pin Flutter 3.50.0. The app declares Flutter >=3.50.0; all
  workspace Dart constraints remain `^3.13.0`.
- All 20 app/test Material imports use `package:material_ui/material_ui.dart`,
  retaining existing import combinators. The app adds `material_ui: ^1.11.0`.
  Current UI code has no third-party legacy Material subtree requiring a bridge.
- The root lock adds `material_ui` 1.11.0, `cupertino_ui` 1.1.6,
  `flutter_localizations`, `intl` 0.20.3 and `listen` 1.0.1. Flutter's new test
  pin selects `test` 1.32.0, `test_api` 0.7.14 and `test_core` 0.6.20.
- Code generation initially warned that analyzer 13.3.0 understood Dart 3.13,
  older than the new SDK. A targeted analyzer upgrade selected analyzer 14.7.0
  and `_fe_analyzer_shared` 111.0.0. That exposed an API incompatibility in
  build_runner 2.16.1; a targeted build_runner upgrade selected compatible
  patch 2.16.2. Final generation has no language-version warning. No global
  `pub upgrade` was performed; serial, SQLite and Drift runtime versions remain
  unchanged.
- The format gate now checks every tracked Dart file, matching local and CI
  inputs. The original all-directory check encountered five ignored historical
  Dart fixtures under `build/`; none was edited. All 209 tracked Dart files pass
  with zero formatting changes.
- Public core/CLI APIs, product versions, schema 1, export format, native quit
  policy and default renderer settings remain unchanged. Generated production
  and probe code and published schema artifacts remain byte-for-byte unchanged.

The first macOS Debug build reused a Swift explicit precompiled module from the
old SDK output and failed with `FlutterPluginRegistrarMacOS.h has been modified
since the module file ... was built`. The completed failed output was moved from
`apps/meshchan_app/build/macos` to the evidence directory's
`stale-macos-build/`, preserving it rather than deleting or editing SDK headers.
Debug then built successfully from a fresh macOS output directory. No native
source or Xcode project change was needed for that failure.

The first Release attempt was blocked before AOT compiler entry by Gatekeeper.
Both `gen_snapshot_arm64` and `gen_snapshot_x64` waited at `_dyld_start`;
`syspolicyd` recorded a prompt awaiting response, and the user independently
reported the "Apple could not verify ... is free of malware" dialog. The
attempt ultimately exited with both snapshotters at -9; this is retained as
an unsuccessful build, not an AOT or runtime pass.

The user then explicitly authorized removing `com.apple.quarantine` from only
those two official SDK tools. Both universal binaries passed strict,
all-architecture signature verification with Flutter's Developer ID
`FLUTTER.IO LLC (S8QB4VV633)`. Original quarantine attributes, signature details
and before/after SHA-256 are retained in
`approved-compiler-quarantine.json`; both file hashes remained unchanged.
No global Gatekeeper, TCC, signing, renderer or Flutter feature setting was
changed. The subsequent Release build passed after that narrowly authorized
metadata change.

The migration follows Flutter's [Material package migration guide](https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui).
The [Homebrew Flutter cask](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/f/flutter.rb)
defines the official SDK archive, checksum and command links. Historical
3.47.9 SDK records are preserved rather than rewritten.

## Automated results

| Gate | Result |
| --- | --- |
| Locked dependencies and workspace membership | PASS; all four members and the root |
| Drift generation / schema checker | PASS; unchanged generated artifacts and schema 1 |
| Tracked Dart formatting | PASS; 209 files, zero changes |
| `flutter analyze --no-pub --fatal-infos` | PASS; no issues |
| Complete Flutter app suite | PASS; 228 tests |
| Complete offline core suite | PASS; 362 tests |
| Complete communication core suite | PASS; 180 tests |
| Complete CLI suite | PASS; 276 tests |
| Python tooling suite | PASS; 71 tests with Python 3.15.2 |
| Runtime / draft / profile / device / diagnostic / history process checks | PASS; all six hardware-free checkers |
| Product CLI / serial observation / datagram acceptance bundles | PASS; all three built with bundled Dart 3.14.0 |
| Source / AOT / relocated CLI smoke | PASS; 101 process checks, including five synthetic datagram scenarios in source and AOT and real-file SQLite reopen |
| macOS Debug / Release | PASS; fresh Debug output and approved-compiler Release build |
| Debug / Release signatures | PASS; `codesign --verify --deep --strict --all-architectures` |
| Native XCTest | PASS; 14 tests, zero failures; isolated TestAction retained |
| Production Release runtime and whole-app relocation | PASS; write, reopen, relocated read and verified signatures |
| Startup and live-owner normal quit | PASS; startup has no spawned worker; ready quit confirms actual release and worker exit; zero pending requests/receive ports |
| Finite Release SQLite probe | PASS; independent write/read, schema 1 and identical draft facts; serial enumeration NOT_RUN |
| Final formatting / generated-artifact / whitespace checks | PASS |

Debug is arm64. The standard Release command produced a universal x86_64/arm64
app (Flutter reported 48.6 MB); runtime acceptance was on the arm64 host only.
The tools' ARM-only feature suggestion and an Xcode generic-destination notice
did not prevent the standard build. No global architecture preference was set.
XCTest used fresh derived data under the owned temporary root and the existing
`MESHCHAN_TEST_HOST=disabled-owner-v1` TestAction, without changing privacy settings.

All final required automated gates passed. This does not establish actual GUI
appearance, real input-method behavior, a fix for historical striped text,
hardware operation, Intel runtime behavior, remote Linux/macOS CI execution or
clean-machine distribution acceptance. The original failures and their distinct
resolutions above remain part of the record. No app was launched against the
production default data directory; tests used owned fixtures and confirmed close.
