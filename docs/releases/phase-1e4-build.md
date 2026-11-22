# Repeatable local Release builds (1E.4)

The supported executor is the existing macOS arm64 host, stable Python 3.15+
(`/opt/homebrew/bin/python3`), Xcode, and `/opt/homebrew/share/flutter` with its
bundled Dart. The actual identities are observed, not inferred from this guide.
The selected SDK must match `tool/release_sdk_sources.json`: framework, engine,
content hash, Dart revision and engine source tree. Never switch SDK channel or
update dependencies to make a check pass. This recipe does not rebuild the SDK.

The source version decision is `Runner/Configs/Version.xcconfig`, checked against
all four members, internal constraints, constants and native metadata. Current
products are App `0.1.0-rc.1+10` and CLI `0.1.0-rc.1`, Apple short `0.1.0`, build
string `10`. Rebuilding the same inputs does not allocate a build number.
The commands below illustrate a local build. Use the
[1E.11 handoff](phase-1e11-release-materials.md) to identify the already
accepted image and its original inputs. A new distributable App with changed
contents requires a higher build number.

For review fixes to the build or verification tools, run the unit tests that
cover the change. Complete the applicable real rebuilds, product checks, runtime
and installation tests, and strict materials verification before opening the PR.
Follow the [validation workflow](../development.md#review-fixes-and-pre-pr-validation)
and the candidate-specific requirements below when qualifying a Release handoff.

## Build and inspect

When starting from the delivered `meshchan-source.tar.gz`, unpack it into a
new directory and run these commands from the extracted root. The archive
contains the root `.gitignore` used by the builder to distinguish owned outputs
and generated package configuration from source.

```sh
git init
git add -- .
git commit -m "Record extracted Meshchan source"
```

Use your configured Git author identity for the local commit. This commit
identifies the extracted snapshot in your own checkout.

Run from the repository root:

```sh
/opt/homebrew/bin/python3 tool/build_release.py build --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-001
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-001
```

Normal builds require a clean working tree. During implementation, add
`--allow-dirty` explicitly; the receipt records Git status, commit, actual source
hashes and helper hashes. This is engineering evidence, not a frozen release
commit. Optional `--expected-version 0.1.0-rc.1 --app-build 10` asserts the source
decision; these flags never edit source or override Flutter version inputs.
For a clean build, the entry compares source bytes and executable modes with
the recorded Git tree. Each first-party compilation input must match this
verified source, including when Git status hides an index-marked change.

Every run must use a **new** ignored directory below `build/phase-1e4/` in the
actual checkout. Existing directories, symlink aliases, nested runs and tracked
source overlaps are rejected. Paths containing spaces are passed as argv arrays.
The shared `.dart_tool/meshchan-1d10.lock` coordinates the existing regression
runner. The entry validates output ownership while holding that lock, before
creating the run directory. It opens a real checkout-local `.dart_tool` directory without
following links and opens the lock relative to that directory. Other ad hoc
commands must also respect this lock or use another checkout;
no advisory lock can coordinate a program that ignores it. Never run Flutter,
native hooks or Xcode concurrently in this checkout.
Before Pub runs, any existing package configuration, package graph, and
Flutter version stamp (`.dart_tool/version`) must be single-link regular
files. Flutter rewrites the stamp in place. The builder checks those paths
again before Flutter configuration and when reading generated configuration.
Before locked resolution, bundled Dart lists the effective workspace without
needing an existing package configuration. The builder checks each package's
`.dart_tool/pub` directory chain and any existing `workspace_ref.json` that
Pub can rewrite. It also checks the `.dart_tool` directories and stray
`package_config.json` files at member roots and along their paths to the
workspace root, where Pub may remove old package configs. The directories
must be checkout-local and existing metadata must be single-link regular files.
The macOS `GeneratedPluginRegistrant.swift` must also be a single-link regular
file when present. The builder checks it before Pub and Flutter configuration.
The App's `.dart_tool/flutter_build` cache is also checked before Flutter
starts and before Xcode can write intermediates. The checkout must own the
directory, its parents within the checkout, and the files under it.
Before Pub and again before `--config-only`, the builder checks the SwiftPM
`SourcePackages` cache and its parents under the effective Flutter `build-dir`.
The default is `apps/meshchan_app/build/macos/SourcePackages`. The entry
validates the active Flutter settings file before the SDK version probe.
It reads the legacy `.flutter_settings` file when present, or
`.config/flutter/settings` under the controlled home directory. Malformed
settings and nonregular files at the selected path stop the probe so Flutter
cannot delete or block on the file while loading it.
The same path ownership rules apply to `.dart_tool/hooks_runner`. Under the
checkout lock, the builder saves the existing developer cache and starts the
CLI and App compilers with a fresh cache for the run. It restores the developer
cache before validation or on failure. The run retains its own hook cache
under `native-hooks/`. Product and strict material checks use that saved cache.
If an uncatchable interruption leaves `.previous-native-hooks` in the run,
it holds the original developer cache. Once the checkout has no active build,
move the interrupted cache aside before restoring the original to
`.dart_tool/hooks_runner`.

The controlled child environment selects Apple tools before Homebrew and retains
only OS user-location variables. It excludes inherited Git, compiler, dyld,
Flutter, version and signing overrides. Git queries for HEAD, source files and
output ignore rules use that same environment. Git replacement objects are
disabled when verifying the checkout and the SDK. The existing
Release signing, entitlements, Hardened Runtime and team settings are preserved.
The builder passes its recorded Python executable to Xcode as
`MESHCHAN_BUILD_PYTHON`. Both native version-check phases use that executable.
Ordinary Xcode builds use the Homebrew interpreter or `python3` from `PATH`
when the setting is unset.
The SDK's Git HEAD and cached source pins are checked before Flutter starts.
Each tracked SDK file's bytes and executable mode, or its raw symlink target,
must match the pinned Git tree even when Git status reports a clean checkout.
The SDK must have no local `bin/internal/bootstrap.sh`. Its presence fails
preflight because Flutter can source it before starting the tool.
The SDK's `bin/cache` path must use real directories. Flutter updates
`engine.stamp` and `engine.realm`, opens `lockfile` for writing, and can
rewrite `flutter.version.json`. Flutter can also create the legacy `version`
file at the SDK root. Existing destinations must be single-link regular
files. The version cache is checked for required fields, field types,
and metadata that would trigger regeneration before its first identity read.
The pinned version command refreshes tags and metadata on `main` and
`master`, so those cached channels fail preflight. The version cache hash
is also checked across the version probe.
The version probe checks informative artifacts. Locked Pub resolution,
macOS configuration, and Xcode's Flutter assemble phase also check
universal or macOS artifacts. The builder requires current, single-link
regular stamps for those caches, including `engine_stamp.stamp` and
`macos-sdk.stamp`. It verifies their versions against the pinned SDK and
checks the required cache directories and files before launching Flutter.
Release commands require an existing Flutter tool snapshot, a tool stamp that
matches the pinned revision and controlled arguments, and a `flutter_tools`
lockfile at least as recent as its manifest. The tool's package config must
contain valid JSON, and each resolved package's `pubspec.yaml` must already
be present. A partial SDK dependency cache would trigger Flutter's own Pub
resolution before the workspace's locked resolution. The builder binds the prepared cache files,
package config, and resolved tool manifest hashes before the version probe and
verifies them again after it.
The verifier accepts the pinned CRLF checkout conversion for Windows files
declared by the SDK's Git attributes. Toolchain probes run under the checkout lock with the same
owned process supervisor and deadline as build commands. This includes Flutter,
Dart, Xcode, Clang, the macOS SDK and the Git checks for the pinned SDK.
Before launching Flutter, the toolchain check requires regular Dart SDK
`version` and `revision` files and records both hashes.

The entry snapshots source and the root lockfile before running
`flutter --no-version-check pub get --enforce-lockfile`, so it can start from
a fresh checkout. Release configuration also disables Flutter's version check.
The generated macOS `Flutter/ephemeral` directories and files must be owned
by the checkout. The builder rejects links and special entries before Flutter
can write configuration, and checks the same paths when reading the snapshot.
It rejects source changes from resolution before running the Dart input parser.
It then compares compilation inputs across
`flutter build macos --release --no-pub --config-only` and saves the full
before-build map before executing these commands.

```text
# cwd: apps/meshctl; Dart is the selected Flutter SDK's bundled executable
dart build cli --packages <repo>/.dart_tool/package_config.json --target lib/src/meshctl.dart --output <run>/cli --depfile <run>/evidence/compiler/cli.d
# cwd: apps/meshchan_app/macos
/usr/bin/xcrun xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Release -destination generic/platform=macOS -derivedDataPath <run>/app-derived OBJROOT=<run>/app-derived/Build/Intermediates.noindex SYMROOT=<run>/app-derived/Build/Products COMPILER_INDEX_STORE_ENABLE=NO
```

The map is independently recomputed after each compiler. It covers first-party
compilation, declared resources including Flutter shaders, native configuration,
and root/member notice declarations.
The inventory includes Flutter's resolution variants for declared files and
literal local shader includes, including transitive includes. It applies the
same check to Flutter's built-in `ink_sparkle.frag` and `stretch_effect.frag`.
It checks the App project directory and the shader's directory before the
fingerprinted SDK include tree, following the pinned compiler's search order.
The entry fails
if a first-party asset or shader declares a transformer, or a shader uses a
nonliteral include. These inputs cannot be bound by the current inventory.
Files listed under `flutter.licenses` are also included because
Flutter reads them into `NOTICES.Z`.
After each compiler runs, the builder checks its depfile against the original
source snapshot, the verified resolved packages, and pinned Flutter source.
It requires fresh App kernel and asset depfiles from the same Flutter build
cache directory for the current DerivedData run. Dart imports outside the
inventoried directories must match the path and bytes captured in the original
source snapshot. Engineering builds also accept ignored Dart files already
hashed in the first-party compilation inventory. The materials gate still
requires those files in the corresponding-source map.
The builder reads workspace and hosted shader declarations using the workspace
package config and Flutter's URI rules for string and map entries. A
package-qualified shader uses the resolved package when the declaring member
has no file at that path. The builder matches these declarations to the App
asset depfile and resolves literal includes in the pinned Impeller search order.
The compiler-input report binds the selected shader sources and physically
resolved headers. A symlink followed by a parent traversal fails validation
when it changes which header opens. Selected hosted shader transformers
require separate input verification and currently fail the build.
The report binds local and hosted asset files listed in the App asset depfile,
including assets from deferred components and files expanded from directories.
Flutter's generated native asset manifest is checked separately against the
bundled libraries. Absent wildcard rerun markers are the other generated
depfile exception. Applicable regular asset transformers are rejected when
their assets appear in that depfile. Automatic hosted notices continue to
use the notice gate, which also covers development-only packages.
All remaining asset depfile paths must belong to the verified workspace,
the pinned Flutter source, or a recorded hosted package. Selected SDK
notices and the cached Material Icons font have separate artifact checks.
SDK hashes, resolved graph,
generated configuration, compatible native hook provenance and source pins have
separate identities. The SDK snapshot hashes the Release platform kernel
(`flutter_patched_sdk_product/platform_strong.dill`) used by the App compiler
and the bundled Dart CLI product kernel (`lib/_internal/vm_platform_product.dill`).
The bundled `dartvm` used for the Dart input parser is also hashed. The
snapshot inventories the cached Release `FlutterMacOS.framework`, including
its public headers, module map, engine binary and framework symlinks.
The Release XCFramework must contain only the pinned `macos-arm64_x86_64`
platform directory among directories whose names begin with `macos-`. The
builder checks the selected framework against the recorded inventory before
Flutter configuration and again before App compilation.
It also records the cached `impellerc` executable and its `shader_lib` include
tree used to compile the App's bundled shaders. The builder verifies the
cached tree's file paths and bytes against the pinned Flutter revision's
`engine/src/flutter/impeller/compiler/shader_lib`. Strict materials verification
repeats this check and compares the verified inventory with the build receipt.
The framework build-source archive is assembled from the same pinned Git
revision's original source blobs and modes.
It also hashes `engine/darwin-x64/font-subset` and the cached
`material_fonts/MaterialIcons-Regular.otf` that it reads to generate the
shipped tree-shaken icon font.
The strict materials gate compares the official source font with both the
installed cache and the build receipt's original font hash.
The generated configuration snapshot includes both Dart's package configuration
and Flutter's `.dart_tool/package_graph.json`, plus the SwiftPM files under the
Runner's generated package tree. The CLI compiler is given that workspace
package configuration explicitly. Build snapshots and materials collection pass
the same config to the Dart input parser. `check` compares the config hash
with the build receipt before running the parser. The receipt separately records the
`dart pub deps --json` report. Standalone materials collection also compares
the workspace package configuration with the receipt.
The external input snapshot also records the resolved SDK package `NOTICES`
or `LICENSE` files that Flutter uses. Selection follows Flutter's
`NOTICES`-before-`LICENSE` precedence. Selected files must match the pinned
Flutter tree or the pinned `sky_engine/LICENSE` member of the verified SDK
archive. The standalone materials collector uses the same check.
The receipt also records the automatic notice selected for every hosted
package in Flutter's package config. Material collection and strict verification
derive the expected selection from each exact locked Pub archive, using the same
`NOTICES`-before-`LICENSE` precedence. They require it to match the build record,
including a recorded absence and packages outside the declared runtime closure.
The builder measures case sensitivity in each hosted package directory using
its existing manifest. The materials verifier uses the receipt-bound case
behavior for notice selection, preserves the archive member's spelling in the
materials, and rejects ambiguous case aliases.
Hosted packages can be reached through a symlinked Pub cache root. Notice
files and their parent directories within a package must be real entries.
The prebuild snapshot treats every file in the locked `libserialport_plus` and
`sqlite3` package trees as a potential native hook input, including headers
absent from hook dependency metadata. Material collection and strict
verification require each recorded path and hash to match the locked archive.
An extra cache file in either package blocks materials even if it was removed
after compilation. The checks for the bundled native outputs still use the
saved hook cache.
The entry recomputes this snapshot after the CLI and immediately before the App
build, then checks it again before declaring success. All source,
helper, SDK and generated-configuration identities are checked again before
declaring success. After product validation, the builder rechecks compilation
inputs, including ignored engineering inputs, and the generated configuration.
It requires both products and the saved native hook cache to match their
pre-validation inventories.
Both build modes recheck repository source bytes before publishing the
receipt. Clean builds also recheck committed file modes. There is no fixed
input-count test. Before returning success after live validation, the
independent check rechecks source bytes and metadata, compilation inputs,
generated configuration, the products, and the saved native hook cache.
The compilers can reuse compatible native hook outputs within the same run.
Each new Release run starts with a fresh hook cache, even when the compiler and
SDK paths are unchanged. Both build commands still execute.
Every Dart input snapshot uses the supervised command runner and has its own
log. Cancellation waits for owned processes to exit before releasing the lock.
Verification ledgers also record handled interruptions between child commands.

## Owned output and integrity

```text
<run>/cli/bundle/                          complete CLI and native libraries
<run>/app-derived/Build/Products/Release/Meshchan.app/
<run>/build-info.json                      index; build and material states differ
<run>/evidence/compilation-input-hashes.json
<run>/evidence/inputs-after-cli.json
<run>/evidence/inputs-after-app.json
<run>/evidence/prebuild-identities.json     source bytes and metadata, tools, helpers, generated config
<run>/evidence/compiler-inputs.json         Dart and hosted shader inputs, selected hosted notices, and raw depfile hashes
<run>/evidence/compiler/                   retained CLI, App kernel, and Flutter asset depfiles
<run>/native-hooks/                        run-specific hook outputs and dependency metadata
<run>/evidence/resolved-graph.json
<run>/evidence/candidate-checksums.txt      all real product files
<run>/evidence/candidate-inventories.json  files, symlinks, and directory modes
<run>/evidence/product-checks.json         loader slices, native asset mappings, provenance, signatures
<run>/evidence/build-receipt.json           compatible formatVersion 1
<run>/evidence/run_build.py                exact source copy of the executed entry
<run>/evidence/logs/                       separate .log (stdout) and .stderr.log streams
<run>/materials/                           separate collect/strict-check stage
```

`check` reads actual files, independently derives current inputs, validates the
receipt, source/helper/toolchain/configuration identities, every recorded log,
checksums, inventories, versions, per-slice loader resolution and native hook
provenance. It records relative internal Framework symlinks without traversing
them as directories. The inventory records the raw link text, including a
trailing slash or repeated separator. Unresolvable links, absolute targets,
and links that leave the bundle at any resolution step fail verification.
A directory scan failure invalidates the inventory.
After Dart builds the CLI, the recipe removes the inherited
`@loader_path/../../..` runpath from `bin/meshctl` and restores its local
ad hoc signature, preserving identifier, entitlements, and signing flags.
The receipt records both commands and the toolchain hashes the host tools.
Each Mach-O must contain arm64. Thin 32-bit Mach-O files fail validation.
Extra x86_64 slices confer
no Intel acceptance. Relative dependencies and runpaths must remain inside
the product at every resolution step, including traversal through symlinks.
For linked dylibs, the report records the search chain in order from the
requesting image through the intermediate loaders to the main executable.
Each relative runpath is expanded against its declaring image. After visiting
the linked graph and the manifest-loaded images, the validator uses the main
executable as the fallback context for the remaining images.
The raw expanded path is checked on disk before normalization so a trailing
slash or `/.` cannot turn a file into a valid directory component. The
selected file must be a Mach-O dylib in the loading slice. The dylib's
install ID is separate from the commands that actually load libraries.
The validator rejects a reused `@rpath` install name when different
dependencies resolve it to different images of the same architecture.
The App's `NativeAssetsManifest.json` must map the locked SQLite and serial
asset IDs to the bundled frameworks for every architecture the runner carries.
For these `dlopen` lookups, dyld searches the actual caller `FlutterMacOS`
first and then the runner. The product report records the caller, ordered
runpaths and resolved target. Each target must be a dylib in the requested
architecture. The manifest may contain only those target architectures and
the two reviewed asset IDs for each target.
The validator walks each manifest target's dependencies under that same caller
chain, with the requesting dylib's own runpaths searched first.
Canonical paths under `/usr/lib` and `/System/Library` are OS dependencies.
Required system libraries must be present on the validation host, either as
files or in the dyld shared cache. The report records the source of availability
and allows absent weak loads. After Xcode finishes, the builder removes the
pinned Flutter engine's factory `/usr/local/lib/.` runpath from the engine
embedded in this run's App. The SDK copy remains the source for section
correspondence. Before editing, the builder confirms the existing signatures
on every engine and App runner slice are local ad hoc. It then reseals the
framework and App with their existing identifier, entitlements, flags,
requirements, and runtime metadata. The run stops if Xcode uses a certificate
identity. If an actual dependency search reaches a host-writable runpath before
finding its bundled library, validation fails regardless of the host's files.
Xcode's Apple-controlled
`/usr/lib/swift` runpath can precede a bundled dependency only if neither
the operating system's files nor the dyld cache supplies that candidate.
Local deep/strict signatures and actual entitlements
are recorded; they do not prove Developer ID or notarization.
Bundle inventory, loader, and signature checks run before executing the CLI.
The product validator also requires the `arm64` dylib in `App.framework` to
export the Dart snapshot data and text that Flutter loads at startup.
Both CLI sibling dylibs are individually signature-verified. In the local
Release validation, the CLI runs `settings show --json` against an isolated
temporary data directory. The probe requires a successful storage close,
a valid SQLite file header, and the exact bundled `lib/libsqlite3.dylib`
in the command's dyld trace. The product report records the loaded library
and storage close. The check binds
the index, complete product paths, evidence and material references to the
selected run directory. The checkout HEAD must still match the build receipt,
even if committing the same source would leave all file hashes unchanged.
The prebuild identities file must match both the index and the original
receipt digest. Live toolchain, generated configuration and helper checks use
those receipt-bound values. The receipt binds the complete inventory and
resolved dependency graph. The receipt also binds the original product
validator report, including signing details and entitlements. The indexed
signing summary must match that report and a fresh validation. Standalone
material verification requires all three bindings for recipe 9 and later.
When a graph is bound, material collection and strict verification compare it
with the current parsed dependency graph before deriving license coverage.
Recipe 40 and later also bind the compiler-input report and raw depfiles.
The raw depfiles remain in local evidence because they contain absolute paths.
Recipe 41 records compiler-reported hosted inputs by package, relative path,
and hash. Both material collection and strict verification require each
compiled hosted file to match a member in its hash-pinned Pub archive.
Recipe 42 also binds selected hosted notices. Recipe 43 binds the App asset
depfiles and includes hosted shader sources and headers in the same locked
archive checks as Dart sources. Recipe 44 applies Flutter's URI rules and
package lookup to workspace and hosted shader declarations. Recipe 45 binds
the saved native hook cache to the receipt. Recipe 46 verifies the bound native
source package inventories against their locked archives and records hosted
notice filesystem casing. Recipe 47 verifies the cached shader include tree
against pinned source and binds hosted files from the App asset depfile to
their locked archives. Recipe 48 also binds local assets from that depfile
and rejects selected regular asset transformers. Recipe 49 requires verified
ownership for all asset depfile inputs and binds the original Material Icons
archive member to the recorded build-time font. Recipe 50 verifies that the
inventory bound by the receipt covers the exact products sent to validation.
Recipe 51 also checks the saved native hook cache before issuing that receipt.
Recipe 52 rejects aliased repository source directories before hashing or
archiving their files. Source symlinks must resolve within the checkout through
relative paths. Standalone SDK and materials checks also reject nonregular
Flutter cache metadata before reading it.
With recipe 53 tooling, standalone material collection and strict verification
validate a supplied build receipt and its recorded package configuration before
running Dart. An invalid receipt stops the attempt. When a receipt is supplied,
the candidate checksums must also match before the CLI version and SQLite probes.
Recipe 54 ships SDK source tooling that checks persistent `configure-build`
write destinations while preserving the pinned compiler and generated Xcode SDK links.
Recipe 55 binds the exact collected and independently checked manifest bytes
to the accepted materials reference. Independent handoff checks require the
same manifest digest. The embedded receipt digest and contents must match the
original build receipt indexed for the run.
Receipts from recipes 40 through 48 require a new candidate for the current
material gate.
Historical recipe 8 requires the inventory and graph. Unversioned receipts
use their original format-1 contract. The indexed
Git working-tree state, engineering
mode, build recipe, and source, compilation, lockfile and graph digests must
agree with the receipt and its verified evidence.
Inventory modes include the product root and all real subdirectories.
Unsupported entries such as FIFOs and sockets are rejected.
The complete product validator, including its CLI, Mach-O and signature
subprocesses, runs under the checkout lock with a deadline and owned-process
cleanup. The receipt hashes both stdout and stderr. Machine probes parse
stdout and preserve diagnostics separately, including failed signing checks.
Run verification checks that the index, receipt files, and build and material
logs are regular files before reading or hashing them.

A command, including the Git output-ownership, status, source enumeration, and
checkout commit probes, has a one-hour default deadline
(`--timeout` accepts a finite, positive number of seconds per command).
If the Git preflight
fails, the entry reports the error before creating a run directory or receipt
at the requested output path. Interrupt/failure
cleanup owns only isolated command groups and observed descendants, using the
existing 1D.10 PID/birth identity mechanism. Git file and ignore enumeration
reads the index and checkout directly with the optional filesystem monitor
disabled for those commands. Cleanup retains the
checkout lock until exit is observed and leaves failure logs and FAIL state.
On a nonzero command exit, cleanup starts immediately and the receipt retains
the original exit code. After a successful command exit, the runner waits for
owned helpers to finish writing logs before it seals the receipt.
SIGINT and SIGTERM are also recorded during product validation, inventory
generation and final publication. The build marks both outcome files FAIL
before releasing the checkout lock.
Never retry in the failed directory or use `flutter clean`/global cache deletion.
Choose a new run after fixing the cause. Hard power loss can leave RUNNING;
`check` rejects that state. Inspect OS processes before manual recovery.

## Candidate-specific validation and materials

The corresponding-source archive must contain every recorded first-party
compilation input with its build-time bytes. An engineering build can use
ignored files, but material collection and strict verification fail if the
source snapshot excludes one. Review and track intended source or assets
before building a candidate for handoff.

Compilation launches no GUI and touches no USB hardware. Obtain fresh native
replacement evidence with the existing `tool/rebuild_release_serial.py` on
isolated **complete copies**, then use the existing VM product harness and
`--attach-vm-evidence`. See the [VM guide](../macos-vm-gui-testing.md) and
[1E.3 material contract](phase-1e3-licenses.md). Its empty-list modification
returns before native enumeration. Never run real port enumeration as a release
smoke. The [validation record](../validation/phase-1e4-build.md) shows handoff
status and records reference runs and probes. Old candidate booleans/hashes
cannot be edited to approve a new candidate. Unavailable VM/probe leaves
materials NOT_RUN/FAIL.

Reuse only hash-verified downloads and the matching SDK source workspace:

```sh
/opt/homebrew/bin/python3 tool/release_sdk_sources.py check --workspace build/phase-1e3-source --flutter /opt/homebrew/share/flutter
/opt/homebrew/bin/python3 tool/build_release.py materials --output build/phase-1e4/run-001 --downloads build/phase-1e3/downloads --probe build/phase-1e4/run-001/validation/serial-rebuild.json --sdk-source-workspace build/phase-1e3-source
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-001
```

The materials stage explicitly supplies repo, SDK, App, complete CLI, new output,
downloads, probe, before-input map, candidate checksums, build receipt and SDK
source workspace to the existing collector and strict checker. Both independently
perform fresh SDK source/GN closure validation. Exit zero with REVIEW_REQUIRED
still fails this stage. Separate timestamped material ledgers preserve each
attempt. Keep writable download and SDK source caches separate from the
candidate products and the material output. The guard follows filesystem
directory identities, including case aliases and parents of new paths. Collection
rechecks cache separation after creating the output directory and before using
either cache.
SDK probe output paths require real directories and single-link regular files
at existing file destinations before collect or recheck writes SDK evidence.
All current SDK source commands and material collection share a lock in that
workspace. Collection holds it through verification and evidence copying.
Listed materials must be single-link regular files in real directories below
the run's material root. The handoff check and strict material verification
enumerate that directory without following links. Every file entry must appear
in the manifest, with `materials-manifest.json` as the sole exception.
Verification also checks the listed files against the independently regenerated
inventory and byte hashes.
Missing archives are downloaded to a file in a new private cache subdirectory.
Curl can reset that file for each retry. The pinned digest must match before
the downloaded file replaces the cache entry.
A failed attempt can be retried
with `--materials-name materials-retry` after obtaining matching evidence.
Prior directories remain available for inspection. Once a run has accepted
materials, use `check` to verify them again. The collector refuses to replace
an accepted binding. The manifest and embedded receipt must identify the
original build commit. SIGINT and SIGTERM during collection, verification, or
index publication mark the material attempt FAIL before the checkout lock is
released. The original build receipt remains available.
Collection and strict verification require the manifest's source map to match
the prebuild source map bound by the build receipt.
For recipe 22 and later, the standalone materials commands also compare the
checkout commit and source map with the original receipt before accepting
corresponding source. Frozen builds also verify archived file types and
executable modes against the committed Git tree. Recipe 33 and later bind
source metadata to the prebuild snapshot for both frozen and engineering
builds. Engineering receipts from recipes 22 through 32 lack this evidence
and require a new candidate for strict materials verification. Collection and
strict verification require archived bytes and metadata to match their verified
source. The archive includes recorded compilation inputs and compiler-reported
first-party dependencies at their repository-relative paths, including inputs
outside the standard source directories.

The GPL source archive includes `tool/build_release.py`, its helpers and tests,
this guide, and the matching VM skills, scripts, helper sources, and example
configuration for replacement evidence. Use your own verified guest settings
and authentication outside the checkout. The integration checks the delivered
entry, guides, VM files, and root `.gitignore` against the actual source bytes.
Only the two
fixed result reports `docs/validation/phase-1e3-materials.md` and
`docs/validation/phase-1e4-build.md` are excluded from the material source map to
avoid result/hash recursion. Other documentation, these instructions, all tracked
product inputs and Git overlap checks retain their coverage.

1E.5 consumes the exact complete products indexed by the selected run's
`build-info.json` after the validation record identifies an accepted handoff.
Build the handoff from a clean checkout of the frozen source
commit and retain that checkout at the path recorded in the run. A dedicated
checkout lets the development branch advance while that verification root stays
available. Verify it there before staging with
`tool/build_release.py check --output <run> --require-frozen` using the same
Python interpreter. This check requires the original commit, a clean-source
build without `--allow-dirty`, and accepted strict materials. Preserve the
complete products, materials, and the frozen commit. Staging, local ad hoc
signing, and DMG packaging must rebind changed bytes and repeat their
applicable checks. Do not silently rebuild after acceptance. No final-release
PASS, tag, publication, minimum OS, Intel or installation claim follows here.
