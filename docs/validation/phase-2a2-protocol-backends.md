# Phase 2A Step 2 protocol and BLE backend validation

## Scope and reviewed checkout

Step 2 is a static source and documentation review. The companion deliverable
is the [transport baseline](../architecture/companion-transport-baseline.md).
The [Step 1 ledger](phase-2a-connections.md) retains its original date,
source baseline, test scope, and handoff.

| Item | Reviewed value |
| --- | --- |
| Date | November 24, 2026 (Europe/Dublin) |
| Repository | `/Users/xiaoyu/Documents/my_projects/meshchan`, with fetch/push remote `https://github.com/007pig/meshchan.git`. |
| Branch and HEAD | `master` at `e313bc33a4f105eceeb830f657ea9ab410072059`, matching the local `origin/master` reference. This is the [PR #52 merge](https://github.com/007pig/meshchan/pull/52). |
| Initial worktree | Clean index and worktree, including untracked files. Both Step 1 documents were present. |
| Step 1 source cut | `02f39e060194351bad02006418905272fdc9aa47`. The committed delta to the Step 2 checkout consists of the two Step 1 Markdown paths. |
| Published Build 10 source | `c5cd5021da5e62c60127678b650d970721263296`, App `0.1.0-rc.1+10`, CLI `0.1.0-rc.1`. The committed delta to the Step 2 checkout consists of 14 Markdown paths. [Publication record](../releases/phase-1e12-publication.md) |
| Local toolchain inspected | Cache metadata at `/opt/homebrew/share/flutter/bin/cache/flutter.version.json` reported stable Flutter 3.50.0, Dart 3.14.0 and framework `ab2912035e160d9cad6306df307576da6128ebdb`. `/opt/homebrew/bin/python3 --version` reported Python 3.15.2. The Markdown check used bundled Node v24.22.3. |
| Final worktree scope | One modified architecture Markdown document and two new Markdown documents. No staged changes or modified historical ledger, manifests, lockfiles, code, native project, or release/signing inputs. |

## Source receipts

The access date for every row is November 24, 2026 (Europe/Dublin). The
[transport baseline](../architecture/companion-transport-baseline.md#evidence-and-source-baseline)
links the files and interprets the evidence at each pin.

| Source | Receipt and evidence scope |
| --- | --- |
| MeshCore stable protocol | The public [tag lookup](https://api.github.com/repos/meshcore-dev/MeshCore/commits/companion-v1.18.0) resolved to `81dbae592ffad40b4212bc0b37e82b38da08f4bc`. The [codeload source archive](https://codeload.github.com/meshcore-dev/MeshCore/tar.gz/81dbae592ffad40b4212bc0b37e82b38da08f4bc) had SHA-256 `b69ba98030bdc8519fb6bba98faef405f67b523b2f6d6c5227fd6fce1c5cdd92`. Source-reviewed Companion handlers, USB/Wi-Fi/Ethernet and ESP32/nRF52/RP2040 paths. The tag and historical device string establish source correspondence, with current flash and exact build provenance open. |
| MeshCore version comparisons | [Companion v1.14.0 tag](https://github.com/meshcore-dev/MeshCore/releases/tag/companion-v1.14.0) maps to `9f1a3eafcc04a1bb200e75ba8cd5921cc04ce203` and the old 172-byte definition. [Main snapshot](https://github.com/meshcore-dev/MeshCore/tree/75b04ef06def54b348400cb1b138afb6749ffd4f) archive SHA-256 `801728861666492f103f91619d9ef8c38c08afbb4f05952acf6cf4debf849e41`. The reviewed helper directory, Companion example directory and protocol Markdown matched the stable pin in the diff. No device firmware mapping to main was established. |
| BLE stack and ATT comparisons | The [MeshCore nRF52 configuration](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/platformio.ini#L81-L88) identifies Bluefruit commit `d541301665b40959682252911e57b11df3ee651a`. The ESP32 source comparison uses [Arduino ESP32 2.0.17](https://github.com/espressif/arduino-esp32/tree/5e19e086c43d0fa5e5a596497ff8f11a0a43f6c2). The [Bluetooth Core 6.2 ATT specification](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core-62/out/en/host/attribute-protocol--att-.html), Vol 3 Part F §§3.4.2, 3.4.6 and 3.4.7, documents MTU exchange, queued writes and notification sizing. |
| Official Python SDK | [v2.3.19](https://github.com/meshcore-dev/meshcore_py/releases/tag/v2.3.19), `50c92e960e0002d0a3a34af0fda23a518ead6331`, source-reviewed for BLE write and notification cross-check only. [BLE adapter](https://github.com/meshcore-dev/meshcore_py/blob/50c92e960e0002d0a3a34af0fda23a518ead6331/src/meshcore/ble_cx.py#L185-L241) |
| openHop comparators | Reopened the [pinned Repeater proxy](https://github.com/openhop-dev/openhop_repeater/blob/13eb8b2ea8b1cdb4a07ed6e282dc99e3aa8a5a8b/repeater/web/companion_ws_proxy.py) and [pinned Core server](https://github.com/openhop-dev/openhop_core/blob/e07722ea96093752ac8b3c6772d653f8b68224bf/src/openhop_core/companion/frame_server/server.py). The Repeater declared Core 1.1.3. The separate [Core development transport](https://github.com/openhop-dev/openhop_core/blob/63f9d305a7de79b3356123c07fe7d2f8d3f1e448/src/openhop_core/companion/frame_server/transport.py) supplies a versioned raw stream and client-slot comparator. These are source pins. Historical version reports and the actual deployment have separate provenance. |
| Flutter isolate contract | Rolling [Flutter isolate guide](https://docs.flutter.dev/perf/isolates#limited-plugin-messages-from-host-platform-to-flutter), marked Flutter 3.50 when accessed. In the installed framework corresponding to the checkout's toolchain, `packages/flutter/lib/src/services/platform_channel.dart` resolves the background messenger for non-root platform channels, and `_background_isolate_binary_messenger_io.dart` rejects inbound handler registration. Applies to the reviewed BasicMessageChannel and MethodChannel paths. |
| Apple platform contract | Rolling documentation. Reviewed [purpose key](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription) (macOS 11+), [sandbox Bluetooth entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.bluetooth) (10.7+), [authorization](https://developer.apple.com/documentation/corebluetooth/cbmanager/authorization-swift.type.property) (10.15+), [per-type write length](https://developer.apple.com/documentation/corebluetooth/cbperipheral/maximumwritevaluelength(for:)) (10.12+), and [peer identifier](https://developer.apple.com/documentation/corebluetooth/cbpeer/identifier) (10.13+). The [write](https://developer.apple.com/documentation/corebluetooth/cbperipheral/writevalue(_:for:type:)), [value delegate](https://developer.apple.com/documentation/corebluetooth/cbperipheraldelegate/peripheral(_:didupdatevaluefor:error:)-1xyna), [connect](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/connect(_:options:)) and [cancel](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/cancelperipheralconnection(_:)) pages apply from macOS 10.7. These document API behavior and availability. TCC prompts, pairing and release remain observations for the identified probe. |

### BLE release archives

The versioned pub.dev API provided an archive URL and SHA-256 for each
release. The downloaded archive hashes agreed with that metadata. The macOS
set comprises the facades and the two Darwin/interface pairs. Android 9.0.5
was inspected only to locate the candidate's build hook.

| Exact package metadata | Downloaded archive | Verified SHA-256 |
| --- | --- | --- |
| [bluetooth_low_energy 6.2.1](https://pub.dev/api/packages/bluetooth_low_energy/versions/6.2.1) | [Archive](https://pub.dev/api/archives/bluetooth_low_energy-6.2.1.tar.gz) | `ac70d6f95c54df943b40d58b0be6cce1ed49ae8b76219d03386cb6c56e06ba5a` |
| [bluetooth_low_energy_darwin 6.2.1](https://pub.dev/api/packages/bluetooth_low_energy_darwin/versions/6.2.1) | [Archive](https://pub.dev/api/archives/bluetooth_low_energy_darwin-6.2.1.tar.gz) | `63243add2f57ad201f09d42878a31bad6e5b93291c6ae3c36de24b5213178a0d` |
| [bluetooth_low_energy_platform_interface 6.2.1](https://pub.dev/api/packages/bluetooth_low_energy_platform_interface/versions/6.2.1) | [Archive](https://pub.dev/api/archives/bluetooth_low_energy_platform_interface-6.2.1.tar.gz) | `430a137fe0a662e2dd632390aa6e020a1c91335a5821ae07dacc9f319f9e590a` |
| [flutter_blue_plus 2.3.15](https://pub.dev/api/packages/flutter_blue_plus/versions/2.3.15) | [Archive](https://pub.dev/api/archives/flutter_blue_plus-2.3.15.tar.gz) | `13e09b4a1bf017e73be75a085039edb9b245d113dba3b69f0e787fac8a346389` |
| [flutter_blue_plus_darwin 9.0.5](https://pub.dev/api/packages/flutter_blue_plus_darwin/versions/9.0.5) | [Archive](https://pub.dev/api/archives/flutter_blue_plus_darwin-9.0.5.tar.gz) | `318cf00d98570616f6ca1a5f0664ae6acd21112a18e5cc3546891ce85a5b1ecb` |
| [flutter_blue_plus_platform_interface 9.0.4](https://pub.dev/api/packages/flutter_blue_plus_platform_interface/versions/9.0.4) | [Archive](https://pub.dev/api/archives/flutter_blue_plus_platform_interface-9.0.4.tar.gz) | `444c30197a19e735b565d082a0b58662da3953dfb15f395853211650f3215f13` |
| [flutter_blue_plus_android 9.0.5](https://pub.dev/api/packages/flutter_blue_plus_android/versions/9.0.5) | [Archive](https://pub.dev/api/archives/flutter_blue_plus_android-9.0.5.tar.gz) | `2ffce1f1f66ac0b1650cd3bf5227e864dd1b28f067fc0638e7318dc2b02cff6b` |

The three bluetooth_low_energy 6.2.1 release tags resolve to
[`b97633b24405ace7dea0f0b30a08c0599aece19e`](https://github.com/yanshouwang/bluetooth_low_energy/tree/b97633b24405ace7dea0f0b30a08c0599aece19e).
The flutter_blue_plus facade tag `flutter_blue_plus-2.3.15` resolves to
[`23261064bb2e4c75072e6346ce36b28010ea4e39`](https://github.com/chipweinberger/flutter_blue_plus/tree/23261064bb2e4c75072e6346ce36b28010ea4e39).
Relevant Dart and native code, manifests, native build specs and documentation
matched the published package contents at these commits. For flutter_blue_plus,
the Darwin and interface correspondence is established by content comparison.
Repository-only dotfiles and overrides and the example lockfile were outside
the archives. Review the packaged `LICENSE` as authoritative. The identical
`LICENSE.md` text supplies a readable fixed citation where the repository uses
a stub or symlink. The selection uses formal releases and checks the actual
macOS implementation packages.

## Executed checks

| Check | Command or method and result |
| --- | --- |
| Baseline and status | `git rev-parse HEAD`, `git branch -vv`, `git remote -v`, `git status --porcelain=v1 --untracked-files=all`, and commit-to-commit `git diff --name-status` confirmed the clean starting checkout and its relation to Step 1 and Build 10. Final scope inspection includes both untracked Markdown files. |
| Local source and policy tracing | Read guidance and handoff documents with `cat` and `sed`. Traced protocol, app worker/controller/Check, CLI USB factory, the development openHop adapters and loopback test source with `rg` and targeted reads. Compared project/SDK metadata, plist, entitlements and signing policy. No test was executed by reading its source. |
| Public protocol sources | Public sources opened in the web retrieval tool and via `curl -fsS` to GitHub API, codeload and raw source. `jq` checked tags, `tar -xzf` extracted public source in a temporary directory, and `rg -n` / `nl -ba` inspected implementations. `diff -qr` on helpers and the Companion example and `diff -u` on the protocol document found no differences between the pinned stable and comparison snapshots for those paths. |
| Public plugin evidence | `curl -fsS` and `jq` retrieved exact pub.dev metadata and archive URLs. `shasum -a 256 -c -` verified archives. `tar -tzf`, `tar -xzf`, `git diff --no-index --stat` and targeted source reads checked publication correspondence, native paths, SDK/build requirements, and licenses/notices. Source was read as data. |
| Published source citations | A targeted `node --input-type=module` check matched all seven documented archive versions, URLs and hashes to the metadata and downloaded bytes. It also verified the 17 fixed plugin source paths against the retrieved GitHub snapshots after correcting the FlutterBluePlus NOTICE link to its package path. |
| Source access limits | Default sandbox shell DNS could not resolve public GitHub/pub.dev hosts. Targeted public reads succeeded through the web tool or public shell network escalation. Apple's Markdown views supplied the reference content where the HTML view required JavaScript. The versioned pub.dev HTML license page was unavailable to the web tool. The exact release archives supplied all reviewed LICENSE/NOTICE contents. |
| Markdown and local links | Passed a targeted Node check rerun against the final three Markdown files. Verified UTF-8, LF and final newlines, heading structure, 22 tables, link definitions, and 156 local link occurrences, including heading fragments. |
| Diff and scope | Passed `git diff --check` and `git diff --no-index --check -- /dev/null <new-file>` for both new files, with no whitespace diagnostics. Reviewed the full tracked diff and both new-file diffs. Verified that all paths outside the requested three match the starting state. |

## Not executed

- Product unit/integration tests, network loopback tests, Flutter or Dart
  analysis/build, dependency resolution, package installation or hook
  execution, signing, packaging, remote CI, publication, and product upgrades.
- Host or guest GUI, Bluetooth scanning/pairing or authorization trials,
  USB enumeration, Companion initialization, connection to user TCP/WS
  endpoints, openHop REST preflight, inbox consumption, or RF transmit/receive.
  Only public documentation and source were retrieved over the network.
- Step 3 host creation, plugin integration or real-host probes. Step 4
  bridge implementation, worker cooperation exercises, or execution-location
  selection. Production TCP/BLE, migrations and recovery remain future work.

## Historical evidence

| Earlier work | Observation and coverage |
| --- | --- |
| Beta Build 5 | Finite real Direct RF in both GUI directions, active Cancel and Quit, and one actual USB unplug/error and explicit replug/Refresh/reselect/new Check. The U02 scheduling margin failed and unplug detection time was unmeasured. [Host matrix](phase-1d11-rf-matrix-completion.md#actual-host-matrix) |
| Published Build 10 | First same-image run stopped after A's Check at read-only audit initialization. Later same-image run passed selected Check/audit, one exact Direct PING/PONG with direct TCP B, active Cancel, normal Quit and independent release/closed History on macOS arm64. Current usability and broad reliability were outside this review. [First attempt](phase-1e12-publication.md#same-image-host-hardware-attempt) · [Later run](phase-1e12-publication.md#same-image-host-hardware-verification) |
| openHop development | REST/WS and later direct TCP are independently scoped. A WS passive failure preceded the explicitly selected TCP continuation. Historical TCP tests saw standard OK and server-side delay. The separately bounded B-only run saw OK and expected no-responder timeout without reproducing greater-than-15-second OK. [WS and TCP record](phase-1d8-hardware-2026-11-15.md#explicit-tcp-continuation-and-real-rf) · [OK investigation](phase-1d11-openhop-ok-investigation.md) · [B-only record](phase-1d11-delayed-ok-rf.md) |

## Open items

- Before [Step 3](../architecture/companion-transport-baseline.md#step-3-macos-ble-host),
  establish the available BLE unit, exact board/chip and firmware build, local
  host identity and effective permissions, and scope of the authorized run.
  Prioritize bluetooth_low_energy 6.2.1 with its 6.2.1 macOS dependency set.
  Verify real notification provenance, per-type write length, maximum
  notification risk, errors, and cleanup with the selected target. A safe
  no-RF boundary stimulus may be unavailable for the largest values.
- Carry actual host-to-worker event ordering, cancel/deadline handling,
  generation isolation and release evidence into
  [Step 4](../architecture/companion-transport-baseline.md#step-4-worker-cooperation).
  Record evidence before choosing plugin/session placement. The
  [fallback](../architecture/companion-transport-baseline.md#verification-order)
  is conditional on an identified backend-specific failure, relevant
  alternative behavior, and cleared terms for the intended use.
- Current A availability, B deployment and modem/firmware identity,
  actual client/inbox constraints and binary capability remain open for
  their later planned verification. Step 2 establishes the documented
  baseline and plans while preserving the historical evidence boundaries.

**Phase 2A Step 2 completed.** The
[minimal macOS BLE host](../architecture/companion-transport-baseline.md#step-3-macos-ble-host)
is the next planned step once its prerequisites are met.
