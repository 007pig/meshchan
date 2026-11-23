# Meshchan RC1 Build 10 source and license materials

Use this index with `Meshchan-0.1.0-rc.1-build10-macos-arm64-local.dmg` and
compiled source `c5cd5021da5e62c60127678b650d970721263296`. Use the matching
release manifest for the actual DMG bytes and public signed-product digest.

## Where to find the files

After verifying the image with the [engineering user guide](rc1-build10-engineering-guide.md),
mount it and open `Meshchan-0.1.0-rc.1-macos-arm64/`. All paths below are
relative to that product folder unless specified. Copy the complete folder
to a writable location for rebuild or replacement work.

The in-image `materials/materials-manifest.json` is the public materials
record. It identifies the compiled source and lock digest and gives byte
counts and SHA-256 values for the delivered material files. The volume-level
`image-payload.json` identifies all shipped files. The matching release
attachment `release-materials-inventory.json` indexes its material-file
subset. The product's public
`signed-product-info.json` ties the distributable folder to the accepted
`local-adhoc` products. Use the exact public digest in the release manifest
when a procedure requires independent verification of that file.

| Material | Path and coverage |
| --- | --- |
| Project license and attribution | `materials/licenses/meshchan/LICENSE` and `materials/licenses/meshchan/COPYRIGHT`. The project uses GPL-3.0-only, Copyright (c) 2026 Meshchan Contributors. The CLA in the first-party source covers contribution terms separately. |
| First-party corresponding source | `materials/source-materials/meshchan/meshchan-source.tar.gz`. Use its entry in `materials/materials-manifest.json` for the exact archive size and digest. It carries the workspace members, manifests and lock, generated inputs and checked-in code, Runner, configuration, original assets, tools, and build guides. |
| Flutter framework | `materials/source-materials/flutter/framework-build-source.tar.gz` and `DEPS` in the same folder. |
| App engine and CLI Dart AOT runtime | `materials/source-materials/sdk/source-inputs.json`, `sdk/archives/`, and `sdk/source-metadata/` under `materials/source-materials/`. The SDK inventory maps the original engine, Dart, native and toolchain sources separately for each target. See `materials/rebuild/sdk-sources.md` and its adjacent scripts and pins. |
| Pub packages and helpers | `materials/source-materials/archives/` holds the original production and build-helper Pub archives at their locked hashes. See `materials/THIRD_PARTY_NOTICES.md`, original notices in `materials/licenses/`, and the App's captured notices in `materials/licenses/app/`. |
| libserialport | `materials/source-materials/archives/libserialport_plus-1.0.5.tar.gz`. The complete C source, headers, config, and hook are under `materials/source-materials/libserialport_plus/`. The MIT Dart wrapper notices and native LGPL-3.0-or-later notices are under `materials/licenses/libserialport_plus/` and `materials/licenses/libserialport-native/`. Keep the native README, COPYING, and GPL text. |
| SQLite | `materials/source-materials/archives/sqlite3-3.9.1.tar.gz` and the MIT wrapper notice in `materials/licenses/sqlite3/`. The native amalgamation, upstream license, and rebuild helper sources are in `materials/source-materials/sqlite-native/`. |
| Material Icons | `materials/licenses/fonts/MaterialIcons_LICENSE.txt` contains the original CC-BY-4.0 license and attribution supplement. The App carries the subset at `Meshchan.app/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/fonts/MaterialIcons-Regular.otf`. The subset is pinned by the image inventory. |
| Build and packaging tools | Start with the first-party archive's `docs/releases/phase-1e4-build.md` and the disk's `materials/rebuild/`. The product folder carries `packaging-source/`, `signing-source/`, and `signing-materials/`. The top level of the volume carries `dmg-source/`. |

The image supplies the pinned SDK and native inputs needed alongside the
first-party archive. The release manifest identifies the actual build recipe
and toolchain. GitHub's generated source archives are repository snapshots.
The disk image supplies the complete corresponding materials for this
engineering release, including the pinned dependencies and native inputs.

The pinned Flutter font archive has SHA-256
`e56fa8e9bb4589fde964be3de451f3e5b251e4a1eafb1dc98d94add034dd5a86`.
The original OTF has SHA-256
`d9865b671a09d683d13a863089d8825e0f61a37696ce5d7d448bc8023aa62453`.
Flutter subsets that font for the App. [Original Flutter font archive](https://storage.googleapis.com/flutter_infra_release/flutter/fonts/3012db47f3130e62f7cc0beabff968a33cbec8d8/fonts.zip)

## Rebuild or replace libserialport

For quarantined inputs, the shipped tool checks that the prepared copies
retain their original download quarantine event. Use normal macOS item
approval for those same copies. The [validation summary](rc1-build10-validation-summary.md)
describes the engineering-extraction run and the separate installed-copy
runtime test.

Use an arm64 Mac with Xcode's SDK, Clang, and Python 3.15 or later. Work from
a writable copy of the complete signed folder. The shipped procedure and
script are at `signing-materials/phase-1e6-user-library-replacement.md` and
`signing-source/tool/release_signed_replacement.py`. The script verifies the
public signed input and source archive, compiles a synthetic replacement,
and re-signs separate App and CLI copies.

Set `SIGNED_ROOT` to the complete candidate folder from the verified
installation, `RELEASE_MANIFEST` to the matching release manifest, and
`REPLACEMENT_OUTPUT` to a new path in an existing folder. Keep the
download attributes on the installation and copied products.

```sh
SIGNED_ROOT="$HOME/Applications/Meshchan Engineering Build 10/Meshchan-0.1.0-rc.1-macos-arm64"
RELEASE_MANIFEST="$HOME/Downloads/release-manifest.json"
REPLACEMENT_OUTPUT="$HOME/Downloads/Meshchan Build 10 replacement test"

(
  set -e
  SIGNED_INFO_SHA256=$(/usr/bin/plutil -extract publicSignedInfoSha256 raw -o - "$RELEASE_MANIFEST")
  python3 -B "$SIGNED_ROOT/signing-source/tool/release_signed_replacement.py" \
    --signed-root "$SIGNED_ROOT" \
    --signed-info-sha256 "$SIGNED_INFO_SHA256" \
    --output "$REPLACEMENT_OUTPUT"
)
```

The expected digest is the release manifest's `publicSignedInfoSha256` for the
in-image `signed-product-info.json`. The in-image manifest’s
`privateSignedInfoSha256` identifies the original private signed-product
manifest.

The output evidence records the actual compiler arguments and signing
commands. The original archive includes `serialport.c`, `timing.c`,
`macosx.c`, headers, and configuration. For compatible edits, preserve the
exported symbols, architectures, install names, and bundle symlinks. The App
framework's `Versions/Current` points to `A`. Its top-level binary and
`Resources` symlinks go through `Versions/Current`.

| Product | Native library path | Install name and slices |
| --- | --- | --- |
| App | `Meshchan.app/Contents/Frameworks/libserialport_plus.framework/Versions/A/libserialport_plus` | `@rpath/libserialport_plus.framework/libserialport_plus`, arm64 and x86_64 |
| CLI | `meshctl/lib/liblibserialport_plus.dylib` | `@rpath/lib/liblibserialport_plus.dylib`, arm64 |

Follow the recorded commands to ad hoc sign with `codesign -s -` in the user
copies. Sign the changed framework before its enclosing App and the CLI dylib
before the CLI executable. Use the generated user entitlements for the main
executables. No maintainer signing keys are needed.

A successful run on a quarantined installation prepares the separate
products and records `finalIntegrity: PASS`, `cli.status: NOT_RUN`, and
`app.status: NOT_RUN`. The overall preparation result is `INCOMPLETE`
and the command exits 1. Use the exact prepared paths and normal approval
sequence in the shipped guide. The report and separate runtime evidence
determine the observed result. App approval can open the copy using the
account’s default Meshchan data directory, as it did during the VM test.
Use a separate macOS account or VM to isolate the approval from normal
Meshchan data. If approval opens the App, quit it normally and relaunch
the same approved copy with the fixture argument from the shipped guide.
An unquarantined engineering extraction can execute the CLI automatically
and supports a paired VM test.
