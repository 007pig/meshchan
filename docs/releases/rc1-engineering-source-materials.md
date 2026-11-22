# Meshchan RC1 Build 9 source and license materials

This index applies to `Meshchan-0.1.0-rc.1-build9-macos-arm64-local.dmg` and
compiled source `01cfacb7fc166a0078962a99d9e673750aabad65`. The DMG's SHA-256 is
`49e25d6580486276850177fc51f68093462c26212daa0b12770ed7b6e26d66f2`.
The image and these instructions are prepared for an engineering release whose
publication is pending. The exact Git tree is available now.
[Compiled source commit](https://github.com/007pig/meshchan/tree/01cfacb7fc166a0078962a99d9e673750aabad65)

## Where to find the files

After verifying the image following the [engineering user guide](rc1-engineering-guide.md),
mount it and open `Meshchan-0.1.0-rc.1-macos-arm64/`. All paths below are
relative to that folder. Copy the complete folder to a writable location if
you want to keep the materials and work on a separate copy. The
`release-materials-inventory.json` release attachment gives byte counts and
SHA-256 for the indexed files, including the original dependency archives.
The in-image `materials/materials-manifest.json` is the original material
record. Its SHA-256 is
`0806faa011146a1314279b59d1f725cee0e751028ceb27410f03f5014fe91469`.

| Material | Path and coverage |
| --- | --- |
| Project license and attribution | `materials/licenses/meshchan/LICENSE` and `materials/licenses/meshchan/COPYRIGHT`. The project uses GPL-3.0-only, Copyright (c) 2026 Meshchan Contributors. The CLA in the first-party source is a separate contribution agreement. |
| First-party corresponding source | `materials/source-materials/meshchan/meshchan-source.tar.gz`, SHA-256 `975e01bcf77cbebdc4183a80da79b93a1ffa82da51ae455698bdb370c633e230`. It carries the four workspace members, manifests and lock, generated inputs and checked-in code, Runner, configuration, original assets, tools and build guides. |
| Flutter framework | `materials/source-materials/flutter/framework-build-source.tar.gz` and `DEPS` in the same folder. Flutter 3.50.0 framework revision `ab2912035e160d9cad6306df307576da6128ebdb`. |
| App engine and CLI Dart AOT runtime | `materials/source-materials/sdk/source-inputs.json`, `sdk/archives/` and `sdk/source-metadata/` under `materials/source-materials/`. The App engine revision is `371f77202a73e8dff57a8b3bff75bca55c090aee`. The CLI uses Dart 3.14.0 revision `fa8c1270c374c1346931583a17c3b7f278d3822d`. The SDK inventory maps the original engine, Dart, native and toolchain-source closures separately for each target. See `materials/rebuild/sdk-sources.md` and its adjacent scripts and pins. |
| Pub packages and helpers | `materials/source-materials/archives/` contains the original production and build-helper Pub archives at their locked hashes. Start with `materials/THIRD_PARTY_NOTICES.md`, original notices in `materials/licenses/` and the App's captured notices in `materials/licenses/app/`. |
| libserialport | `materials/source-materials/archives/libserialport_plus-1.0.5.tar.gz`, SHA-256 `9246f3a0909e4bc87ef2ac1366bbc2eb350d139f976a277dd5c29b8d3dc085e3`. See the complete C source, headers, config and hook under `materials/source-materials/libserialport_plus/`. The MIT Dart wrapper notices and native LGPL-3.0-or-later notices are under `materials/licenses/libserialport_plus/` and `materials/licenses/libserialport-native/`. Keep the native README, COPYING and GPL text. |
| SQLite | `materials/source-materials/archives/sqlite3-3.9.1.tar.gz` and the MIT wrapper notice in `materials/licenses/sqlite3/`. The native SQLite 3.54.1 amalgamation, upstream license and build helper sources are in `materials/source-materials/sqlite-native/`. The native correspondence and compile options are recorded separately from the wrapper. |
| Material Icons | `materials/licenses/fonts/MaterialIcons_LICENSE.txt` is the original CC-BY-4.0 license and attribution supplement. The App carries the subset font at `Meshchan.app/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/fonts/MaterialIcons-Regular.otf`. The original Flutter font archive and pre-subset font have their own pinned identities in the material manifest. |
| Build and packaging tools | Start with the first-party archive's `docs/releases/phase-1e4-build.md` and the disk's `materials/rebuild/`. The complete signed folder also carries `packaging-source/`, `signing-source/`, `signing-materials/`, and the original build provenance. The top level of the volume carries `dmg-source/`. |

Build recipe 55 used Flutter 3.50.0 with bundled Dart 3.14.0, Xcode 27.2
(27B52), macOS SDK 27.2, Apple Clang 21.0.0 and Python 3.15.2. The original
strict check verified the pinned SDK and native source closures, the workspace
snapshot and material correspondence for this App and CLI. This provides
traceable rebuild inputs. A bit-identical rebuild was outside that check.
GitHub's automatic source archives contain the Git tree. The complete SDK
and native corresponding sources are supplied in the image layout above.

For the Material Icons input, the original Flutter ZIP has SHA-256
`e56fa8e9bb4589fde964be3de451f3e5b251e4a1eafb1dc98d94add034dd5a86`.
The original OTF has SHA-256
`d9865b671a09d683d13a863089d8825e0f61a37696ce5d7d448bc8023aa62453`.
Flutter subsetting produced the bundled OTF with SHA-256
`65666ba1a370938ce1c3668cea3559b9eb7197e6cb80c34322013ed528180188`.
The image carries the license and bundled font. The original archive is
available from Flutter's pinned download. [Original Flutter font archive](https://storage.googleapis.com/flutter_infra_release/flutter/fonts/3012db47f3130e62f7cc0beabff968a33cbec8d8/fonts.zip)

## Rebuild or replace libserialport

For the supported replacement procedure, use an arm64 Mac with Xcode's SDK,
Clang, and Python 3.15 or later. Work from a writable copy of the complete
signed folder. The shipped procedure and scripts are at
`signing-materials/phase-1e6-user-library-replacement.md` and
`signing-source/tool/release_signed_replacement.py`. The procedure verifies
the signed input and source archive, compiles a synthetic replacement and
re-signs separate App and CLI copies. Choose a new, unused output path.

```sh
SIGNED_ROOT="$HOME/Downloads/Meshchan-0.1.0-rc.1-macos-arm64"
REPLACEMENT_OUTPUT="$HOME/Downloads/Meshchan replacement test"
python3 -B "$SIGNED_ROOT/signing-source/tool/release_signed_replacement.py" \
  --signed-root "$SIGNED_ROOT" \
  --signed-info-sha256 a227775b6edf803f29d6a3d2818211ad51572e6223584f28f02aacb928d48361 \
  --output "$REPLACEMENT_OUTPUT"
```

Set `SIGNED_ROOT` to your actual copied folder. The output evidence records the
actual compiler arguments and signing commands. The original archive includes
`serialport.c`, `timing.c`, `macosx.c`, headers and configuration. For compatible
edits, preserve the exported symbols, architectures, install names, and bundle
symlinks. The App framework's `Versions/Current` points to `A`. Its top-level
binary and `Resources` symlinks go through `Versions/Current`.

| Product | Native library path | Install name and slices |
| --- | --- | --- |
| App | `Meshchan.app/Contents/Frameworks/libserialport_plus.framework/Versions/A/libserialport_plus` | `@rpath/libserialport_plus.framework/libserialport_plus`, arm64 and x86_64 |
| CLI | `meshctl/lib/liblibserialport_plus.dylib` | `@rpath/lib/liblibserialport_plus.dylib`, arm64 |

Follow the recorded commands to ad hoc sign with `codesign -s -` in the copies.
Sign the changed framework before its enclosing App and the CLI dylib before
the CLI executable. Use the generated user entitlements for the main
executables. No maintainer signing keys are needed.

The signed Build 9 check confirmed that the synthetic empty-port library loaded
in both the CLI and the VM App and that both products settled. This tested
replacement only. Real USB and RF results have their own evidence. Without
guest configuration, a successful CLI and preparation run records
`cli.status: PASS` and `finalIntegrity: PASS` with overall `INCOMPLETE`
and exits 1. See the shipped replacement guide for an optional local App
check and the paired VM procedure.
