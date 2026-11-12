# Phase 1C local development candidate 0.1.0-dev.3

Recorded November 12, 2026. Status: **development-with-known-limitations**.
Public distribution remains **NOT_READY**. This record separates software,
local runtime/archive, CI, clean environment and hardware evidence.

## Baseline and compatibility

Work started on clean `master`, `33dca83b109f4b9a22e218e29fde96d4c2adc493`,
the actual PR #25 merge. It contains the reviewed
`e237be5c2fb9e4fd1cf2f2c26717582f34a5e757` head. The candidate adds recorded
uncommitted dev.3 inputs to that baseline; it is not attributed to an old clean
commit. No history rewrite, automatic commit, push, tag, merge, release or binary
upload was performed.

All three members, their internal constraints and the CLI constant move to
`0.1.0-dev.3`. External dependencies, the root lockfile, Flutter/Dart and native
library selections are unchanged. The root workspace has no product version.
Database schema/snapshot **1**, diagnostic summary **1**, CLI schema **1** and
diagnostic wire version remain independent and unchanged. Historical appVersion
values and dated development/hardware/release records retain their original facts.

The delivered 1C APIs cover persistent drafts, complete operation profiles,
typed settings, presence-aware parameter resolution, opt-in finite recording,
startup recovery, bounded history, guarded deletion, retention and safe summary
export. See the [existing CLI contract](../cli.md#offline-business-commands-and-storage-1c8).
This step changes no production state machine, protocol, retry behavior or schema.

## Reproducible local gate and retained outputs

Build ID: `0.1.0-dev.3-macos-arm64-20261112T180913Z`.
The ignored build directory is:

```text
build/phase-1c9/0.1.0-dev.3-macos-arm64-20261112T180913Z/
```

`validation.json` records each command, cwd, UTC start/end, exit, log/hash, actual
source/branch/worktree status, independent product and verification input maps,
toolchain and recursive bundle inventories. Product inputs include all three
libraries, CLI bin, `database.g.dart`, schema input, member/workspace pubspecs,
lockfile and relevant build configuration. Added and modified files are hashed
from disk, rather than hidden behind HEAD. Documentation is separately bound at
packaging time. Generated schema, snapshot and helper differences are checked.

Use the installed toolchain without upgrading or changing global settings:

```sh
MESHCHAN_DART=/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
MESHCHAN_PYTHON=/opt/homebrew/bin/python3
"$MESHCHAN_DART" --version
"$MESHCHAN_PYTHON" --version
# Choose a fresh nonexisting version/OS/architecture/UTC build directory.
"$MESHCHAN_PYTHON" tool/validate_dev_candidate.py \
  --dart "$MESHCHAN_DART" --build-directory "$MESHCHAN_BUILD"
"$MESHCHAN_PYTHON" tool/check_schema_compatibility.py \
  --dart "$MESHCHAN_DART" --build-directory "$MESHCHAN_BUILD"
"$MESHCHAN_PYTHON" tool/package_1c_candidate.py \
  --build-directory "$MESHCHAN_BUILD" \
  --acceptance-summary "$MESHCHAN_BUILD/acceptance-summary.md"
```

The sequential gate uses enforced resolution, core build_runner/schema checks,
format, fatal-info analysis, Python tests, complete core/CLI/link suites, then
fresh `dart build cli` targets for product, serial observation and datagram
acceptance, shared smoke and whitespace review. CLI `concurrency: 1` is retained.
The development bundles and databases stay outside the product candidate.
Actual environment: macOS 27.2.1 arm64, Flutter cache 3.47.9 stable (framework
`c197ca5199e9ee5661e865596c9c07294dfab51c`), bundled Dart 3.13.7 (SDK revision
`416e33b0ffaef062a60ec966bb8c82ed2b83f128`), Apple Clang 21.0.0
`clang-2100.4.1.1`, and reverified `/opt/homebrew/bin/python3` 3.15.2
(actual executable `/opt/homebrew/opt/python@3.15/bin/python3.15`). Native commands
used a process-local Apple-compiler-first PATH. Python child tooling uses
sys.executable. No installed toolchain/global settings changed.

| Final prearchive dimension | Observed result |
| --- | --- |
| Locked resolution / production generation / schema / generated diff | PASS; root lockfile and all frozen generated/schema artifacts unchanged |
| Root format / fatal-info analyze | PASS; 139 Dart files, zero formatting changes; no issues |
| Python complete discovery | 56 passed, including 7 new packaging regressions and historical revision tests |
| Complete meshchan_core / meshctl / meshcore_link suites | 362 / 271 / 180 passed, sequentially; actual loopback access available |
| Three fresh complete native bundles | PASS; product, serial observation and development datagram acceptance |
| Shared source/AOT/relocation smoke | 101 process checks passed; retained legacy scenarios and real SQLite, plus nonempty synthetic recording/product history export |
| Real schema-1 compatibility / rejected future/corrupt preservation | PASS; 8 recorded process checks, actual old/new file row comparisons |
| Product and all three bundle inventories after testing | Unchanged; packaging-tool-only refinements reran all 56 Python tests and retained the original validation snapshots |
| Final dev.3 CI / independent clean environment | NOT_RUN/PENDING / NOT_RUN |
| Public distribution / RF-USB-relay new evidence | NOT_READY / no new conclusion |

The formal software/native run spans `2026-11-12T18:10:44Z` through the final
smoke/diff-check times in validation.json. Schema compatibility ran
`18:14:50Z`–`18:14:56Z`. Packaging-only refinements retain
`validation-before-tools-*.json` and separate `python-tools-*.log` records;
product/three tested bundle bytes did not change, so native rebuilds were not
repeated for those metadata/provenance refinements.

Pre-gate development failures are retained in development-iterations.json:
the first privacy assertion falsely matched permitted payloadByteCount (5 pass,
1 fail), a synthetic symlink test fixture had the wrong tar content size (6 pass,
1 error), and analysis reported one missing-braces info. Each was corrected
before the corresponding final successful gate. Original outputs are in the
conversation; uncaptured start/end times are not fabricated. No formal test was
skipped and no blocked loopback test was called passing.

## Recording and real schema-1 compatibility

The existing five fixed serial-byte scenarios remain shared by tests and the
source/AOT probe. Added recording checks reuse those vectors through runCli/core:
successful send, one-end recorded listen, and logical success followed by actual
controlled native close failure. Every required save commits; actual database
close precedes a new owner/read/export. Runtime checks throw in AOT, and VM probe
runs enable assertions. Accepted TX frames are checked exactly, with no save retry
or verification resend. The development probe is synthetic; it is not product
RF recording or a real device-input test.

Shared smoke retains real SQLite draft/profile/settings and empty history checks
in source, product AOT and relocated complete bundle. It also retains closed
probe databases, reads/exports their nonempty history through the product AOT,
and checks null/false/zero, independent cleanup scopes, six-digit UTC and sensitive
field exclusion. Final archive verification uses the same business gate and a
copy of that closed native-probe file in a separate process/data directory.

`check_schema_compatibility.py` archives the exact PR #25 head into the ignored
build folder, overlays only the new development harness, and runs its unchanged
dev.2 production CLI/core to create a real schema-1 file with draft, profile,
default settings and a terminal old-version diagnostic. It retains the original
closed file, then runs dev.3 AOT recording and a new product business commit.
Read-only row comparisons preserve all old IDs/revisions/times/configuration,
old appVersion and settings. New rows use dev.3. Future-version/corrupt files
fail explicitly and retain original bytes. Existing suites independently cover
recovery, retention, sidecars, ownership and failure preservation. This is file
compatibility acceptance, not an import/backup feature or arbitrary cross-system
copy guarantee.

## CI, platforms and evidence boundaries

PR #25 is merged. Its historical jobs were queried again and their checkout
objects inspected in actual logs:

- [PR run 43260401317](https://github.com/007pig/meshchan/actions/runs/43260401317):
  completed/success; actual merge-test checkout
  `8cb38d782f9acd790d09ea08fa23c843741463f2`, merging `e237be5c...` into `8f2165ec...`.
- [Push run 43260386553](https://github.com/007pig/meshchan/actions/runs/43260386553):
  completed/success; actual checkout `e237be5c2fb9e4fd1cf2f2c26717582f34a5e757`.

Both historical Ubuntu 26.04.1 x64 logs show Dart 3.13.7 and 94 smoke checks.
They validate that dev.2 head, not these uncommitted dev.3 inputs or archive.
Final dev.3 CI is **NOT_RUN/PENDING** until the reviewed changes are committed
and pushed with authorization. Existing CI automatically discovers the new
Python regressions and runs the updated shared smoke/version/recording checks.
No redundant workflow, third-party action change or remote run was added.

| Platform | Code allowance | This build/runtime | Independent clean environment | Public distribution |
| --- | --- | --- | --- | --- |
| macOS arm64 | Supported ownership ABI; existing serial restrictions retained | See final local results | NOT_RUN | NOT_READY |
| Linux x64 | Supported ownership ABI; serial enumeration guard retained | Final dev.3 NOT_RUN; historical CI above is separate | Final dev.3 NOT_RUN | NOT_READY |
| macOS x64 | Supported ownership ABI | NOT_RUN | NOT_RUN | NOT_READY |
| Linux arm64 | Supported ownership ABI | NOT_RUN | NOT_RUN | NOT_READY |
| Windows | Business owner ABI unsupported; serial handle/enumeration safety guards retained | Unsupported product scope | NOT_RUN | Unsupported |
| Mobile/other ABI | Outside this delivery commitment | NOT_RUN | NOT_RUN | Outside scope |

Moving a whole bundle outside checkout, using another cwd, or restricting a
process PATH proves same-host relocation only. It does not prove a machine
without SDK/pub cache or other installed build tools. No independent machine,
VM or artifact-only runner was available for this unpushed local candidate.

## Materials and distribution limits

The candidate includes the entire product runtime, README, build-info,
prearchive acceptance summary, original notices/licenses, explicitly classified
native source/hook materials and SHA256SUMS. It excludes development executables,
SDK/Python/cache copies, product source checkout, business databases/owners and
sidecars, credentials, radio configuration and raw hardware logs.

Materials are collected from the actual production closure and package config.
All workspace members, including meshchan_core, are first party. Hook/build
support and dev-only dependencies are identified independently of AOT-reachable
runtime code. Missing third-party original package notices fail packaging.
The MIT serial wrapper and LGPLv3-or-later native source are listed separately;
original native source/configuration/hook and COPYING/README are retained. The
native upstream revision remains unknown because package version metadata is
inconsistent. SQLite's MIT wrapper, precompiled native asset and locked
hook/hash sources are separate. System SQLite was not substituted. The original precompiled SQLite asset hash
`38c4a60bacdf3f4fddcb90fae011e06e5ebade251870a960cbb5284cb64783ea`
matches both the locked hook table and retrieved release asset metadata.
The SDK bundler changes install names/signatures; delivered hashes are recorded
separately. The official unmodified GNU GPLv3 text was retrieved and included,
alongside original release metadata and request provenance. Dart SDK
LICENSE and installed archive notice pointer are retained. Attempts to obtain
the runtime third-party directory by both version tag and installed SDK revision
returned HTTP 404; complete runtime notice correspondence remains unverified.
An initial sandbox DNS limitation and subsequent successful material retrievals
remain in additional-materials-provenance.json.

Public distribution remains blocked by the unselected project license,
unverified completeness of native corresponding source/build/relinking and Dart
AOT runtime notices, Developer ID/notarization/download quarantine, independent
clean-environment acceptance and final dev.3 CI. Collected materials are not a
complete legal-compliance conclusion. Ad-hoc signatures are reported accurately.

RF/USB/relay evidence is unchanged. Refer to the
[Direct matrix](../hardware-validation.md#direct-rf-matrix-on-november-10-2026),
[authorized H2/H7 comparison](../hardware-validation.md#authorized-command-budget-comparison-on-november-11-2026)
and [historical dev.2 record](phase-1b-dev2.md). Physical unplug, relay paths and
historical intermittent USB delivery causes were not retested or resolved here.
No real port, inbox, radio send or radio setting was accessed by this step.

## Handoff to 1D

Flutter should call the public core repositories, resolver and recording/history
APIs directly for drafts/profiles/settings/history/recording. CLI JSON is a host
projection, not the UI business API. The UI host supplies an explicit directory,
owned storage lifecycle and current explicit device authorization; a stored port
hint never supplies authorization. Preserve absent versus explicitly supplied
values, including empty path/content and a cleared listen filter.

Await actual recording cleanup, unpin/maintenance and storage close. Keep logical
outcome, core/host cleanup, persistence, sticky maintenance failure, close and UI
output independently visible. A later save failure must not resend, rewrite a
committed fact or claim released ownership after closeUnconfirmed. Keep the
current operation/signal owner through host resolution, execution and final close.
No Flutter page, directory plugin, schema or next-stage product feature is added.

## Final archive result and exact artifact locations

The final archive passed extraction and execution at
`2026-11-12T18:19:39.796237Z`. There are **82 checksum-covered files plus
SHA256SUMS**. Exact archive member set, safe member types/paths, every file hash,
file mode, all runtime hashes and the checksum file were verified. The extracted
product then passed **17 process checks**: exact dev.3 version, current business
help, required ID/revision/port rejections before creating storage, Unicode/
emoji/mixed-newline draft and UTF-8 length, profile/settings commit/close/reopen,
and nonempty safe history query/export from the closed AOT probe fixture.
After execution, extracted files, archive and native bytes remained unchanged.
Only then was external archive-verification.status written as PASS.

| Delivery dimension | Final status |
| --- | --- |
| Final source software gate | PASS, bound to actual dirty product input hashes |
| Local source/AOT real business SQLite | PASS |
| Synthetic VM/AOT recording and product nonempty history/export | PASS, not RF/product device-input evidence |
| Complete same-host relocation | PASS, outside checkout with spaces and different cwd |
| Final archive integrity and actual extracted business execution | PASS, 17 checks |
| Final dev.3 remote CI | NOT_RUN/PENDING; no remote commit contains these uncommitted inputs |
| Independent clean environment / other unexecuted ABIs | NOT_RUN, as listed above |
| Public distribution | NOT_READY, with the concrete material/signing/environment gaps above |
| RF / USB unplug / relay | No new conclusion; historical records remain independent |

All retained paths are relative to the repository root:

```text
build/phase-1c9/0.1.0-dev.3-macos-arm64-20261112T180913Z/
  validation.json
  validation-before-tools-*.json
  python-tools-*.log
  ci-evidence.json
  schema-compatibility.json
  schema-compatibility-attempt-1.json
  schema-compatibility-attempt-1.log
  schema-compatibility/original closed fixture/meshchan.sqlite
  recording-evidence/source recorded database/meshchan.sqlite
  recording-evidence/native recorded database/meshchan.sqlite
  recording-evidence/process-checks.json
  loader-review.json
  additional-materials-provenance.json
  development-iterations.json
  package-attempt-1.log
  archive-verification.json
  delivery/0.1.0-dev.3-macos-arm64-20261112T180913Z/
    bin/meshctl
    lib/liblibserialport_plus.dylib
    lib/libsqlite3.dylib
    README.md
    build-info.json
    acceptance-summary.md
    THIRD_PARTY_NOTICES.md
    licenses/
    source-materials/
    SHA256SUMS
  delivery/0.1.0-dev.3-macos-arm64-20261112T180913Z.tar.gz
  delivery/0.1.0-dev.3-macos-arm64-20261112T180913Z.tar.gz.sha256
```

The archive was actually extracted outside checkout to:

```text
/private/tmp/meshchan dev3 final archive newakhhn/0.1.0-dev.3-macos-arm64-20261112T180913Z/
```

| Exact delivered file | SHA-256 |
| --- | --- |
| Final tar.gz | `6528394052e999de748323090db78d22344db7be1d9264a5ea1f8e35cfa4afe0` |
| Product `bin/meshctl` | `e261fb30a5fef81c43927bd1d0237c61b6ba804ff8938b9a848c9d97eed42ac5` |
| `lib/liblibserialport_plus.dylib` | `6a3fbe15228b7e860b0cd9ec3fd8a60b55f0e40fbbe2ef3b5cef0f3a7ea4a56d` |
| `lib/libsqlite3.dylib` | `25bcc2da4d154c4bf6d0f516cfc66f257cf13d68a8aad94e45255c446258e5d9` |

All three runtime files are Mach-O arm64. Product and serial modes are 0755;
SQLite is 0644. All three existing signatures pass read-only codesign verification
and are ad-hoc, with no Developer ID/notarization claim. otool reports bundle
relative native install names and ordinary /usr/lib or /System/Library dependencies,
with no inspected checkout/SDK/pub-cache/Homebrew/temp absolute loader binding.
The local packager currently uses macOS file/otool/codesign tools; these results
are not an independently executed Linux packaging implementation.

build-info contains the exact production/verification hashes, toolchain, gate
logs, complete runtime inventory, original native hook-output/input mappings,
separate downloaded/bundled native hashes, declared production dependency graph
and 13 build-hook-only dependencies, 30 third-party production-graph packages'
original notices, 75 original/material files, original source locations/URLs and
known unknowns. The full installed package graph is not labeled runtime code.
The GNU GPLv3 original has SHA-256
`3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`.

Candidate SHA256SUMS excludes itself; final archive hash/verification remain
external. Embedded acceptance describes completed prearchive gates. This release
record adds final archive facts externally, avoiding a self-containing hash cycle.
The candidate binds the README/core/CLI/development/testing document bytes present
at packaging; final-review.json separately binds this completed release record
and all current delivery documents to the unchanged archive.

1C software and this local macOS development candidate are complete. Final remote
CI, independent clean environment, other ABI execution and public distribution
remain explicitly open; they do not block reviewing/using this isolated local
candidate within its recorded scope. The 1D handoff above is documentation only.

## Delivery-tool review follow-up on November 12, 2026

Three subsequent Python-only review findings were fixed: the compatibility
script now passes its prepared compiler environment to children; smoke canonicalizes
relative evidence paths before differing child cwds; and packaging resolves the
actual installed SDK behind a Flutter launcher/Homebrew symlink before collecting
notices. SDK layout checks prevent the Flutter framework LICENSE from being
mislabeled as the Dart SDK license. Validation records the discovered SDK directory
and version and uses it to locate Flutter cache metadata as well.

Complete Python discovery passed **61 tests**, including five added environment,
relative-path and SDK-material regressions. The actual schema-compatibility command
passed **8 checks** with Homebrew Clang 18 first in the caller PATH and the standard
`/opt/homebrew/bin/dart` launcher. Complete source/AOT/relocation smoke passed
**101 checks** with that launcher and a relative evidence directory. Real launcher
material collection produced the actual SDK license SHA-256
`2cfa3ee8e7512e6d44c854b986510810fadc815f93f890373b3a81c1b6ccd256`;
it differs from the Flutter framework LICENSE and matches the original candidate.

Review evidence is preserved under
`build/phase-1c9/review-delivery-tools-20261112T190351Z/`, particularly
review-gates.json, launcher-materials-verification.json and review-verification.json.
The [development follow-up](../development.md#1c9-delivery-tool-environmentpath-review-follow-up-on-november-12-2026)
records the fixes, original failures and exact execution boundaries.

This review changed no product input or any of the three native bundles. The
original archive/hash and external verification above are preserved. That archive
used the direct SDK binary and already contained the correct license, so no
replacement archive was issued for these tooling-only corrections. Its embedded
verification-tool/document hashes remain the original snapshots; this new review
record binds the updated tooling and documents independently. Final dev.3 remote
CI, clean-environment, other-platform and public-distribution states remain open.

## Schema-path review follow-up on November 12, 2026

The schema-compatibility tool now percent-escapes an absolute SQLite file URI
before appending its read-only query and explicitly closes the comparison
connection. Relative `--dart` paths are resolved and validated by the shared
executable parser before creating/extracting build files. This corrects both
unintended database selection/write access and child-cwd executable failures.

Final Python discovery passed **65 tests**, including **9 targeted delivery tests**.
The real relative-Dart compatibility workflow passed **8 process checks**.
A genuine closed old schema-1 file in a directory containing literal `#`, `%`,
`?`, spaces and Chinese text passed escaped read-only row comparison and **4
native process checks** for recording, product commit, reopen/query and export.
Old rows were preserved and no URI-truncated database was created.

The separate combined attempt that also placed legacy source under such a path
remains **BLOCKED**: the installed Dart 3.13.7 native-hook launcher rejected its
hook.dill path before database recording/comparison. Its failed exit/log remain;
the passing database and normal-source-cwd checks do not replace that result.
No SDK/upstream/cache workaround or product state-machine change was made.

See `build/phase-1c9/review-schema-paths-20261112T191824Z/review-verification.json`
and the [development follow-up](../development.md#1c9-schema-path-review-follow-up-on-november-12-2026)
for command/log/input bindings and the retained blocker. Product inputs, all
three native bundles and the original archive/hash are unchanged. No replacement
archive was issued; previous manifests remain historical snapshots.

## Retained-artifact analyzer review follow-up on November 12, 2026

The root analyzer now excludes `build/**`. Retained incomplete native source
materials previously caused 28 unrelated diagnostics and prevented the next
candidate's root analysis gate from completing. Original materials, archives and
output layouts are preserved; normal workspace source remains analyzed.

A deliberate temporary error under core lib produced exactly one expected type
diagnostic, demonstrating that the exclusion does not suppress first-party
analysis. After removing that owned probe, root `dart analyze --fatal-infos`
passed with no issues while the retained candidates remained. Root format checked
707 files with zero changes, complete Python discovery passed 65 tests and
whitespace checks passed. See
`build/phase-1c9/review-analyzer-scope-20261112T193239Z/review-verification.json`
and the [development follow-up](../development.md#1c9-retained-artifact-analyzer-review-follow-up-on-november-12-2026).

Only the analysis configuration changes in the captured product-input map;
compiled Dart source, dependencies, all three native bundles and the original
archive remain unchanged. Old manifests/gates retain their original config hash.
No rebuilt candidate or new remote/distribution result is asserted by this review.
