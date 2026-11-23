# Phase 2A Step 1 connection baseline validation

## Scope and reviewed checkout

Phase 2A Step 1 covers documentation and source review for the USB baseline
and the future USB, TCP, and BLE adapter boundaries. The companion deliverable
is the [connection architecture](../architecture/companion-connections.md).

| Item | Reviewed value |
| --- | --- |
| Review date | November 23, 2026 (Europe/Dublin) |
| Repository | `/Users/xiaoyu/Documents/my_projects/meshchan` |
| Branch and HEAD | `master` at `02f39e060194351bad02006418905272fdc9aa47`, matching the planning reference and local `origin/master` |
| Remote | `origin` fetch and push both point to `https://github.com/007pig/meshchan.git` |
| Initial worktree | Clean index and worktree, including untracked files. Both Step 1 paths were absent. |
| Published product | macOS arm64 Build 10, App `0.1.0-rc.1+10` and CLI `0.1.0-rc.1`, frozen source `c5cd5021da5e62c60127678b650d970721263296`. [Publication record](../releases/phase-1e12-publication.md) |
| Checkout versus published source | The tree delta from the frozen source to HEAD consists of 12 Markdown paths covering README, CLI, release, and validation material. The [workspace](../../pubspec.yaml) and four member manifests retain the published identity. Review findings use the checked-out code. |
| Step 1 worktree delta | Two new Markdown documents under `docs/architecture/` and `docs/validation/`. Git HEAD remains the reviewed source revision. |

## Current source review

| Area | Evidence reviewed |
| --- | --- |
| Repository and version policy | [Agent guidance](../../AGENTS.md), [contribution guide](../../CONTRIBUTING.md), [README](../../README.md), [developer guide](../development.md), [testing guide](../testing.md#review-fixes-and-pre-pr-validation), and the [App](../../apps/meshchan_app/pubspec.yaml), [CLI](../../apps/meshctl/pubspec.yaml), [link](../../packages/meshcore_link/pubspec.yaml), and [business core](../../packages/meshchan_core/pubspec.yaml) manifests. Signing was checked against the [1E plan](../releases/phase-1e-plan.md#current-signing-decision), [1E.6 guide](../releases/phase-1e6-signing.md), and [policy JSON](../../tool/release_signing_policy.json). |
| Communication | [Link exports](../../packages/meshcore_link/lib/meshcore_link.dart), [frame API](../../packages/meshcore_link/lib/src/transport/companion_transport.dart), [serial and USB wrapper](../../packages/meshcore_link/lib/src/transport/serial_transport.dart), [completion policy](../../packages/meshcore_link/lib/src/transport/usb_initialization_transport.dart), and [startup synchronization](../../packages/meshcore_link/lib/src/transport/usb_startup_sync.dart). Traced the [session](../../packages/meshcore_link/lib/src/session/meshcore_session.dart), [inbox owner](../../packages/meshcore_link/lib/src/session/meshcore_reception.dart), and [diagnostic tasks and results](../../packages/meshcore_link/lib/src/diagnostics/). Compared the [session](../protocol/companion-session.md), [framing](../protocol/serial-framing.md), [datagram](../protocol/channel-datagrams.md), and [task](../protocol/diagnostic-tasks.md) contracts. |
| CLI | [Product dispatch](../../apps/meshctl/lib/meshctl.dart) to [session commands](../../apps/meshctl/lib/src/session_command.dart) or [serial inspection](../../packages/meshcore_link/lib/src/serial_ports.dart). Followed [datagram input](../../apps/meshctl/lib/src/datagram_options.dart) through [storage and parameter resolution](../../apps/meshctl/lib/src/stored_datagram_command.dart) to the [unrecorded](../../apps/meshctl/lib/src/datagram_command.dart) and [recorded](../../apps/meshctl/lib/src/recorded_datagram_command.dart) runners. Reviewed [output](../../apps/meshctl/lib/src/cli_output.dart) and [exit precedence](../cli.md#new-machine-schema-and-exit-precedence). |
| App | [Device](../../apps/meshchan_app/lib/device/model.dart) and [Diagnostics](../../apps/meshchan_app/lib/diagnostics/model.dart) models through [controller](../../apps/meshchan_app/lib/runtime/controller.dart), [request types](../../apps/meshchan_app/lib/runtime/protocol.dart), and [worker](../../apps/meshchan_app/lib/runtime/worker.dart). Followed [finite Check](../../apps/meshchan_app/lib/runtime/device_check.dart), [safe Check projections](../../apps/meshchan_app/lib/runtime/device_protocol.dart), [recording observation](../../apps/meshchan_app/lib/runtime/recording_adapter.dart), and the worker release handshake. Compared the [App README](../../apps/meshchan_app/README.md) and [host contract](../architecture/flutter-host.md). |
| Persistence and privacy | [Profile model](../../packages/meshchan_core/lib/src/models/connection_profile.dart), [parameter resolver](../../packages/meshchan_core/lib/src/parameter_resolver.dart), [owner lifecycle](../../packages/meshchan_core/lib/src/storage/storage.dart), [database](../../packages/meshchan_core/lib/src/storage/database.dart), [schema](../../packages/meshchan_core/lib/src/storage/schema.drift), [recording coordinator](../../packages/meshchan_core/lib/src/recording/recording.dart), [safe snapshot](../../packages/meshchan_core/lib/src/models/diagnostic_configuration.dart), [export](../../packages/meshchan_core/lib/src/history/history_repository.dart), and [offline core contract](../architecture/offline-core.md). |
| Development adapters and software coverage | [openHop transport source](../../apps/meshctl/tool/support/openhop_frame_transport.dart), [loopback test source](../../apps/meshctl/test/openhop_tcp_test.dart), [USB startup test source](../../packages/meshcore_link/test/usb_startup_sync_test.dart), and [openHop acceptance guide](../openhop-acceptance.md). The software sources are read-only evidence in Step 1. |

## Historical evidence

The table identifies observations from earlier validation. Dates, source cuts,
and limits apply to the recorded runs.

| Historical record | Evidence and scope |
| --- | --- |
| Beta Build 5, November 17, 2026 | The inventoried `0.1.0-beta.1+5` Release used baseline `0fd49a3495d972c88dee35fc709501db78a16d16` and manifested worktree changes. The selected USB A and openHop B completed exact Direct RF in both GUI directions, bounded timeout and Cancel, active native Quit, and one physical unplug/error with explicit replug/reselect/new Check. U02's scheduling-margin assertion failed and unplug error timing was unmeasured. The same App Release also has separate offline VM evidence. [Beta completion](phase-1d11-rf-matrix-completion.md) |
| Original RC1 Build 9, November 22, 2026 | The original image from `01cfacb7fc166a0078962a99d9e673750aabad65` recorded selected USB Check, packaged CLI Info, limited exact RF with the source-only peer, active Cancel, normal Quit, and closed History checks. The later `1152097eebd91b13b45d29dbd60cef794d7a5c3d` Build 9 source has distinct software and CI evidence. [Original Build 9 record](phase-1e10-hardware-acceptance.md) |
| Published RC1 Build 10, November 23, 2026 | The restored image from `c5cd5021da5e62c60127678b650d970721263296` first stopped on A's read-only audit initialization after a successful Device Check. A second same-image run passed the bounded host checks on macOS 27.2.1 arm64, including one exact Direct PING/PONG with direct TCP on B, active Cancel, normal Quit, and independent resource release and closed History. Exact-source CI, restored image, Beta upgrade, and anonymous-download evidence also belong to that candidate. [Build 10 validation](phase-1e12-publication.md) |
| openHop development, November 15–16, 2026 | The November 15 record preserved a binary WebSocket passive-window failure and a separately selected direct TCP continuation. The November 16 investigation observed standard TCP OK and a duty-cycle deferral beyond the original command budget. Later software/native loopback covered explicit delayed confirmation. A real B-only follow-up observed actual OK and the expected no-responder timeout within its plan. It did not reproduce OK later than 15 seconds. [TCP continuation](phase-1d8-hardware-2026-11-15.md#explicit-tcp-continuation-and-real-rf) · [Investigation](phase-1d11-openhop-ok-investigation.md) · [Client validation](phase-1d11-delayed-ok-client.md) · [B-only follow-up](phase-1d11-delayed-ok-rf.md) |
| Signing decision, November 21, 2026 | The ongoing `local-adhoc` route supersedes the former Developer ID prerequisite. PR #45's missing-identity result remains historical evidence, and PR #46 established the local route. The App and CLI keep local ad hoc signing until the maintainer explicitly requests Developer ID Application signing. [Current policy](../releases/phase-1e-plan.md#current-signing-decision) · [Historical route](phase-1e6-signing.md#historical-developer-id-route) |

## Checks executed for Step 1

| Check | Result |
| --- | --- |
| Checkout and scope | Passed. `git rev-parse`, `git branch -vv`, `git remote -v`, `git status --porcelain=v1 --untracked-files=all`, and commit-to-commit `git diff --name-status` established the baseline, published-source delta, and final path scope. |
| Source and history cross-check | Passed. Read the linked definitions and caller chains, including the CLI's explicit `false` and the App's implicit `true` USB policy, and reconciled candidate identities with the release and acceptance records. |
| Markdown and local links | Passed. A targeted `node --input-type=module` check verified UTF-8, LF and final newlines, heading hierarchy, table shape, and local link targets and heading fragments in both files. |
| Diff review | Passed. Ran `git diff --check` and, for each untracked file, `git diff --no-index --check -- /dev/null <file>`. Reviewed both complete new-file diffs against `/dev/null`. |

## Not executed

| Check | Scope reason |
| --- | --- |
| Flutter/Dart unit, integration, CLI process, storage, and network loopback tests | Not run. The task changes documentation only and reviews existing test source. |
| Builds, dependency or SDK commands, signing, installation, packaging, publication, and remote CI checks | Not run. There are no product or release changes and no new candidate. Historical CI results apply to the source named by the original records. |
| App launch and host or VM GUI testing | Not run. This step fixes a source baseline without changing the UI or executable. |
| USB enumeration, Companion connection, BLE or network discovery, TCP/WS trials, inbox reads, or RF | Not run. The hardware and network evidence above comes from earlier separately scoped work. |

## Open items and handoff

- Step 2 should pin the USB, TCP, and BLE protocol references and their applicable framing, initialization, and lifecycle contracts. Use the [compatibility inventory](../architecture/companion-connections.md#compatibility-inventory) to confirm target model, firmware or deployment version, and acceptance scope.
- Step 2 should compare candidate macOS BLE backends against explicit selection, permissions, GATT, notification/write semantics, and cancellation, disconnect, and release. Carry the execution-location and bridge question into Steps 3 and 4 for measurement.
- Record the limits of the selected openHop direct TCP deployment and keep binary WebSocket evidence tied to its own trials. Preserve the distinction between currently observed USB failures and the already documented finite recovery pass.
- The [developer guide's version section](../development.md#product-version-and-native-identity-1e2) still opens with Build 9 candidate wording. Its later Build 10 identity and the current manifests agree with the newer publication record. Any wording cleanup belongs to a separate documentation change.

**Phase 2A Step 1 completed.** The checked-out implementation, historical
candidate evidence, future responsibilities, and open questions are recorded.
[Step 2](../architecture/companion-connections.md#phase-and-step-handoffs) is
next. The remaining Phase 2A steps and production TCP and BLE support remain
planned.
