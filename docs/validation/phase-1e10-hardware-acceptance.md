# Meshchan RC1 Build 9 acceptance summary

Phase 1E.11 compiled this summary from the original Phase 1E.10 records.
The Build 9 host run took place on November 22, 2026, from 07:24 to 07:29
UTC. The offline evidence review completed at 07:32 UTC that day.

## Candidate

| Identity | Recorded value |
| --- | --- |
| App and CLI | App `0.1.0-rc.1+9`, CLI `0.1.0-rc.1` |
| Apple bundle | `org.meshchan.meshchan`, short version `0.1.0`, build `9` |
| Compiled source | [`01cfacb7fc166a0078962a99d9e673750aabad65`](https://github.com/007pig/meshchan/commit/01cfacb7fc166a0078962a99d9e673750aabad65) |
| Image | `Meshchan-0.1.0-rc.1-build9-macos-arm64-local.dmg`, 676,240,035 bytes |
| Image SHA-256 | `49e25d6580486276850177fc51f68093462c26212daa0b12770ed7b6e26d66f2` |
| Signing and image | Ad hoc signed App and complete CLI. Read-only UDZO/HFS+ image, unsigned and unnotarized. |
| Host | macOS 27.2.1 (26B131) arm64 with Gatekeeper and SIP enabled |
| Selected Companion | Heltec V4.3 OLED, reported firmware `v1.18.0-81dbae5`, protocol code `14` |

The hardware run used the complete App and CLI copied from the independently
accepted local image into an isolated host installation with controlled data.
The host receipt records signature checks, successful attach and detach, and
no quarantine attribute on the installed inventory. A separate system
approval for the CLI serial library was not recorded in this workflow.

## Original host results

| Check | Reviewed result |
| --- | --- |
| Selected-device Check | **PASS.** Native enumeration and explicit App selection identified the USB Companion. The finite Check returned the recorded device metadata, closed the session, and released the observed port handles. |
| Limited OpenHop RF | **PASS.** The App Responder and a controlled source-only peer completed one finite exact-content round trip. The retained peer result reports 3.634360 seconds of application elapsed time. The reviewed run accounted for two application send attempts within the plan's limit of three. |
| Active Cancel | **PASS.** The App Responder was observed active before Cancel. It reached the expected `canceled` terminal state with the logical result and cleanup saved. |
| Normal Quit and resource release | **PASS.** The App quit normally after Cancel. Independent observations established App and peer process absence and release of the App's selected port. |
| Packaged CLI USB information | **PASS.** A separate bounded `meshctl info` returned the matching Companion metadata and exited. The port was released. |
| Independent History | **PASS.** After App exit, the packaged CLI read the settled canceled Responder record and its persisted cleanup from the closed case fixture. |
| Final product integrity | **PASS.** The host recheck matched the accepted product and materials inventories and verified signatures after the run. |

The retained original automated validator ended `UNKNOWN` when it attempted to
read a wrapper field absent from the History summary. A corrected offline
replay read the directly emitted summary and persisted cleanup fields and
ended `REVIEW_REQUIRED`. Manual review of the retained records, GUI captures,
and independent observations then recorded the results above. The correction
and review reused existing records without replaying live USB or RF attempts.

The RF result covers the measured device, firmware, and controlled setup.
The elapsed time includes application work and supplies no throughput, range,
or reliability measurement. The source-only peer is an engineering test tool.
The shipped App and CLI access the explicitly selected USB Companion.

## Other evidence and remaining scope

| Product or source | Verified scope and limits |
| --- | --- |
| Original Build 9 image above | Independent signing and DMG checks covered signatures, relocated CLI, offline App operation, and signed input integrity. The isolated App and CLI replacement test loaded a synthetic empty-port serial library. The host run covered the specific USB/RF operations above. Exact-source GitHub Actions evidence and a quarantined clean install and Beta upgrade for this image remain outstanding. |
| Historical Build 8, source `a29430b608658a8b56d619f641dc8600346b6d27` | The independent Safari first install, per-item macOS approval, and Beta Build 5 to RC Build 8 upgrade passed on macOS 27.2.1 (26B131) arm64. A separate Build 8 host USB Check on November 22, 2026, failed during initialization and recorded successful cleanup. The Build 8 results belong to the historical product. [Phase 1E.9 validation](https://github.com/007pig/meshchan/blob/9941ec57dbd3e921e0bf6ebc5dc38bd20e44733b/docs/validation/phase-1e9-install-upgrade.md) |
| Later Build 9 source `1152097eebd91b13b45d29dbd60cef794d7a5c3d` | Software tests, clean Release product checks, strict materials, isolated replacement, and offline App Quit and CLI fixture reopen were recorded for this source. GitHub Actions run `45007478263`, push attempt 1, passed both jobs on this exact commit. This source changes the CLI and USB startup and framing behavior. The USB/RF results above apply to the `01cfacb7` image. [Later source](https://github.com/007pig/meshchan/commit/1152097eebd91b13b45d29dbd60cef794d7a5c3d), [CI run](https://github.com/007pig/meshchan/actions/runs/45007478263), [PR #49](https://github.com/007pig/meshchan/pull/49) |

On November 22, 2026, an exact-source GitHub Actions query returned no runs
for `01cfacb7fc166a0078962a99d9e673750aabad65`. The original image's local
acceptance and the later source's successful CI have separate evidence.
Candidate-specific sealed retention and the review of embedded provenance for
public distribution remain open. Public release and download verification are
pending.

## Record provenance

The retained hardware run is identified as `20261122-build9-01`.
Its candidate admission records the exact image, original checksum list,
image record and payload inventory, and independent signing and DMG checks.
The approved plan and execution receipts bind the host installation and each
operation to that admission. The private evidence index records the preflight,
operation, cleanup, and final integrity receipts, the original automated
result, the offline replay, and the final manual review. Phase 1E.11 matched
the sizes and SHA-256 values of all 275 entries in that index.
