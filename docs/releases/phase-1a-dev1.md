# Phase 1A development candidate 0.1.0-dev.1

Recorded November 9, 2026. This is a local development delivery from
`master` at `e1e16e28c2d99be197a9ed18a1df269f522e5c40` (Step 8 PR #7 merge).
The starting worktree and compilation inputs were clean. Only delivery and
validation documentation changed after compilation. The product version,
Dart source, dependency constraints, root lockfile, native hooks and CI are unchanged.
No tag, Release or other remote publication was created.

## Acceptance decision

| Dimension | Actual status | Scope / limit |
| --- | --- | --- |
| Software gate | passed | Fresh locked resolution, format (25 files, 0 changed), fatal-info analysis, 68 core tests, 27 CLI tests, both new native bundles, macOS 46 shared smoke cases, whitespace check. |
| Basic hardware gate | passed | Fixed H2–H7 on one selected Companion USB device and this Mac; H4a and H4b each passed independently. |
| Additional scenarios | H1/H8/H9 PASS; H10 startup FAIL (3); ready-state disconnect NOT_RUN; post-replug R1 FAIL, R2 PASS | User performed one later unplug/replug outside a watch, reselected the exact port, and explicitly requested each info call; all cleanups succeeded. |
| Artifact integrity | complete | Actual tar.gz extracted to another fresh outside-checkout directory; all member checksums, layout, modes, binary/native asset hashes, version/help and missing-port rejection passed. |
| Redistribution readiness | local-development-only / pending-license-or-signing-review | Missing explicit Meshchan license; native corresponding source and license conditions/materials, Dart runtime third-party notices, Developer ID/notarization and download behavior need review. |
| Recommendation | development-with-known-limitations | Original basic matrix passed; three H10 DEVICE_INFO timeouts, one later SELF_INFO timeout and a standalone info success do not establish stable initialization or a completed H10. USB cause remains unresolved. |

The [hardware record](../hardware-validation.md#step-9-device-acceptance-on-november-9-2026)
contains every invocation's UTC times, command, result, exit and cleanup evidence.
All 10 initial fixed invocations passed their specific assertions, including H8's expected
69 and signal cases' expected 130/143. In that initial matrix there were no initialization timeouts,
failed cases, unconfirmed cleanups, retries, forced kills, or manual interventions.
H4 snapshot equality was checked in memory; raw snapshots/NDJSON were not saved.
Six sessions completed initialization; H9 was canceled before ready. No physical
disconnect result is claimed. A successful finite matrix does not establish that
the historical intermittent USB fault is fixed or estimate reliability.

A subsequent [H10 follow-up](../hardware-validation.md#step-9-h10-follow-up-on-november-9-2026)
was authorized after the initial delivery. Its two watch startups both failed
before ready while waiting for DEVICE_INFO (command 0x16, expected 0x0D), with
requestTimeout, actual exit 69 and cleanup succeeded. The first lasted 5.201052 s;
the separately user-authorized second lasted 5.131309 s. Both returned naturally,
with one failure end and no ready, signals, stack or pending process. The user
confirmed the device stayed connected for the first attempt; no physical action
was requested during either attempt. No raw receive bytes were collected, so this
is not evidence for the specific historical missing-64-byte mechanism.

At the end of those H10 attempts, disconnect detection and recovery were NOT_RUN
because readiness was never met. Across the initial matrix and that follow-up: 12 calls,
10 selected-port open attempts, six complete initializations, two initialization
timeouts, and zero unconfirmed cleanups. There was no automatic retry; the second
attempt required and received explicit new authorization. The initial basic gate
is preserved as dated evidence, while the current recommendation records these
later failures. This documentation-only archive supersedes the initial archive's
acceptance overview and retains exactly the same executable and native library.

A later [post-replug follow-up](../hardware-validation.md#step-9-post-replug-follow-up-on-november-9-2026)
records one user-assisted unplug/replug outside an active watch, one newly
requested metadata enumeration and explicit path reselection. R1 info then
failed at APP_START/SELF_INFO (0x01 / 0x05) after 5.225721 s, naturally exiting 69
with cleanup succeeded and no complete snapshot. The user separately requested
R2 after discussing elapsed time; it passed in 0.256838 s, naturally exiting 0
with one complete closed snapshot. No additional delay or timeout was configured,
no further physical change occurred, and neither call required a signal or force.
R1 started at least about 40 s after enumeration; R2 started about 150 s after R1.
No firmware/reset telemetry or raw bytes were captured, so success cannot be
attributed to waiting or a repair of the historical 64-byte problem.

At the end of the post-replug sequence, counts were 15 calls, 12 selected-port
open attempts, seven full initializations and three request timeouts, with all
cleanups confirmed. H10
ready-state disconnect detection remains NOT_RUN; the later replug/info sequence
is separate evidence (R1 FAIL, R2 PASS), not a completed H10 cycle or a stable
recovery claim. The current recommendation remains development-with-known-limitations.
This archive supersedes both earlier acceptance overviews while keeping identical
native files; the earlier archives remain unchanged dated snapshots.

The user then explicitly requested [one more H10 watch](../hardware-validation.md#step-9-h10-third-startup-on-november-9-2026)
after the standalone info success. Attempt 3 again timed out at DEVICE_INFO
(0x16 / 0x0D), with zero ready and one end: failure / 69 / succeeded. It ran from
21:06:27.516 to 21:06:33.100 UTC, 5.583720 s including startup and cleanup,
and returned naturally without signal, force, stack or pending process. No unplug
instruction was given. H10 disconnect/recovery remains NOT_RUN.

Current combined counts: 16 calls, 13 selected-port open attempts, seven complete
initializations and four request timeouts; every cleanup was confirmed. The
preceding info success is preserved, and the later watch failure is not hidden.
The latest archive supersedes earlier acceptance overviews without changing
native files, product code, defaults or recommendation.

## Candidate contents and provenance

Candidate directory and archive basename:
`meshchan-1a-0.1.0-dev.1-macos-arm64-e1e16e28c2d9-h10-attempt3`.

**Artifact availability at PR preparation:** the temporary outside-checkout
delivery directories were no longer present when preparing this documentation
PR. The results and native hashes below describe the earlier completed build,
hardware checks and archive extraction; the archive was not reverified during PR
preparation. This PR includes documentation only and attaches no binary package.
A subsequent delivery needs a fresh build and artifact verification with its own
provenance and hashes; do not assume a rebuild has identical binary contents or
automatically reuse the earlier hardware evidence for changed binaries.

The new complete `bundle/` was copied as a unit outside the checkout before native
hardware acceptance. It contains `bin/meshctl` and
`lib/liblibserialport_plus.dylib`; no bundle asset was selected out or replaced.
The observation example was built for regression checks and is excluded from delivery.

The package adds `README.md`, standard-JSON `build-info.json`,
`acceptance-summary.md`, `THIRD_PARTY_NOTICES.md`, original license/notice texts
under `licenses/`, and `SHA256SUMS`. The manifest records source/compilation-input
hashes, actual toolchain evidence, lockfile hash, serial package, build commands,
asset hashes, signing and acceptance scope, without home paths or device identifiers.
The `.tar.gz.sha256` beside the archive checks the final archive itself;
`SHA256SUMS` checks all package files except itself. `archive-verification.json`
beside the archive records the actual fresh-extraction checks. Neither the archive
nor the manifest contains a circular archive self-hash.

No Dart/Flutter SDK, Python runtime, pub cache, observation binary, raw hardware
output, device configuration, key material or unrelated temporary scripts are
included. The external working directory additionally retains software-gate logs,
a sanitized structural hardware summary and temporary preparation tools; these
are not archive members and are not committed.

Native SHA-256 values:

- `bin/meshctl`: `51d4e7e10e3f7ea64927797f252a436b7f72ab775bfea262356aa837dce6b914`
- `lib/liblibserialport_plus.dylib`: `6a3fbe15228b7e860b0cd9ec3fd8a60b55f0e40fbbe2ef3b5cef0f3a7ea4a56d`

Build start: `2026-11-09T20:39:00Z`. Host: macOS 27.2 (26B123), arm64;
Apple Clang 21.0.0 (`clang-2100.4.1.1`); direct bundled Dart 3.13.7;
Python 3.15.2 for development checks. Both SDK wrappers failed on sandbox cache
writes; Flutter 3.47.9 / revision `c197ca5199e9ee5661e865596c9c07294dfab51c`
is existing SDK metadata, not a successful fresh Flutter version command.
No SDK/global configuration or pub-cache source was edited. Root lockfile SHA-256:
`9d31c319b24e72356feed7168a457671dd49cd356513f6ab77414edc473e504c`.
See [testing](../testing.md) for the existing sequential checks and
[development evidence](../development.md#step-9-build-and-delivery-on-november-9-2026).

## Run after extraction

No Dart, Flutter or Python installation is required to use this native bundle.
Keep its complete `lib/` next to `bin/`; run from a terminal:

```bash
cd meshchan-1a-0.1.0-dev.1-macos-arm64-e1e16e28c2d9-h10-attempt3
shasum -a 256 -c SHA256SUMS
./bin/meshctl --version
./bin/meshctl ports --json
# Set PORT yourself to the exact selected and authorized path.
: "${PORT:?Select and authorize an exact port first}"
./bin/meshctl port-check --port "$PORT"
./bin/meshctl info --port "$PORT" --json
./bin/meshctl watch --port "$PORT" --json --duration 3
```

`ports` lists metadata and does not select a port. `port-check` checks local
open/close only. `info` returns one complete closed snapshot; watch emits NDJSON.
`info/watch` open/configure the serial device and send DEVICE_QUERY and APP_START;
these affect device session state and driver behavior may reset a board. Obtain
permission for the device and choose its exact path for each task. They request
no new LoRa transmission, but device RF activity under its existing configuration
was not monitored. Requested info/ready output includes device text and public-key
prefixes; avoid publishing raw output. See the repository [CLI contract](../cli.md)
for schema, units, full exit behavior and cancellation.

Exit codes: 0 success; 64 invalid usage/missing port; 69 expected serial/session/
cleanup failure; 70 unexpected process error; 74 output failure; 130 SIGINT;
143 SIGTERM. Signals request awaited cleanup. Product cleanup has no forced deadline.

## Support and known limitations

| Environment / feature | Status |
| --- | --- |
| This macOS 27.2 arm64 host and one authorized USB device | Fresh software and fixed basic hardware gate passed; native outside-checkout info proves native loading and USB session I/O here. |
| Minimum supported macOS version | Unknown / not validated; build metadata is not a tested minimum. |
| Other Macs, Intel/Rosetta, clean machines and downloaded/quarantined archives | Not run; no general installation claim. |
| Linux | Historical Step 8 CI software success only; enumeration intentionally blocked with libserialport_plus 1.0.5; actual serial hardware unverified. |
| Windows / Android | Enumeration blocked; Windows explicit-port operations blocked before unsafe native handle use; no runtime/hardware acceptance here. |
| Device identity / firmware | User-selected Companion USB; model/firmware data device-reported, not independently confirmed or authenticated; protocol code 14 with target 3 is not full protocol-14 support. |
| Physical disconnect / recovery | H10 startup failed three times; ready-state detection NOT_RUN. One later real replug followed by standalone info: R1 FAIL, R2 PASS. No complete H10 cycle or stable recovery claim. |
| LoRa / Phase 1B | Not implemented or tested; no two-device round trip. |

The historical intermittent response-delivery problem remains unresolved.
Earlier evidence includes incomplete 64-byte bodies and independent POSIX
reproduction without Dart/libserialport_plus. The initial matrix had no timeout; the later H10 startup attempts both timed out
waiting for DEVICE_INFO. A later post-replug info timed out at SELF_INFO, and a
separately requested info passed; the next authorized H10 watch then timed out
at DEVICE_INFO again. No part captured USB bytes, so this adds
no byte-level diagnosis or repair claim. Defaults
remain 5/15-second budgets and zero startup delay. No retries, reconnect, polling,
heartbeat, flush, reset, additional query or configuration workaround were added.

Both Mach-O arm64 files passed read-only `codesign --verify`; their signatures
are **ad-hoc**, with no Developer ID/team identity or notarization evidence.
No signing or security-setting changes were made. The complete bundle links host
system libraries/frameworks, including IOKit/CoreFoundation for serial access.
Help/version after relocation alone do not prove device I/O; the separate successful
outside-checkout AOT info cases provide that evidence only on this setup.

No explicit Meshchan project license exists in the checkout; no license was
chosen here. The actual libserialport_plus 1.0.5 wrapper license is MIT, while its
bundled C library is LGPLv3-or-later. Native source version metadata differs
(config.h 0.1.1 versus configure.ac 0.1.2); the wrapper archive hash identifies the
source package, while the exact upstream native revision remains unknown.
The package retains original dependency notices for 23 resolved production-graph
packages (including build-hook tooling), native notices and the Dart SDK license.
Before public native distribution, verify/supply corresponding source and build
materials, incorporated GPLv3 terms, applicable distribution/relinking conditions,
and complete Dart runtime third-party notices. The included notices are not a
complete legal-compliance claim. See package `THIRD_PARTY_NOTICES.md`.

Next work includes the unexecuted disconnect/recovery scenario after readiness
can be established, the existing USB delivery investigation, public distribution
license/signing/material review and compatibility testing. Two-device real LoRa
exchange requires a separate Phase 1B task; no database, BBS, UI, new connection
method, release framework or external publication was added.
