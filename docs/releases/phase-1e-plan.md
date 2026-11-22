# Phase 1E engineering release contract

## Purpose and verified baseline

1E delivers a repeatable, traceable, downloadable, installable, and upgradeable
local engineering release for macOS arm64 through GitHub Releases. The release
includes the complete Meshchan App and `meshctl`, applicable licenses,
corresponding source, and rebuild and replacement materials. Completion requires
DMG integrity and limited runtime checks, engineering installation and Beta
upgrade, limited real USB/RF acceptance, publication, and actual download
verification.

## Current signing decision

On November 21, 2026, the maintainer selected `local-adhoc` as the ongoing
engineering release policy. Both products receive verified local ad hoc code
signatures. The read-only DMG container is unsigned and the release is not
Apple-notarized. The policy has no expiry. Developer ID Application signing,
Apple Team credentials, signing keys, a secure timestamp service, notarization,
and stapling are deferred until the maintainer explicitly requests a new
official signing route. Their absence does not block any current release step.
The engineering workflow does not discover official identities or switch to
official signing when a certificate appears.

The previous contract's Developer ID and notarization requirements are
superseded for 1E. Earlier Developer ID blockers, preparation receipts, and
local diagnostics retain their original meanings. See the
[1E.6 signing validation record](../validation/phase-1e6-signing.md) for the
historical and current candidate evidence. Local code signatures and SHA-256
checks establish code integrity and byte correspondence for this workflow.
They do not authenticate an Apple-recognized publisher or promise automatic
Gatekeeper approval.

## Historical baseline

The November 17, 2026 documentation review used clean `master` at
`0f89fe81823e58d524ad5a35a1f18a454b6fa4bc`, matching the planning reference.
This is the reviewed source baseline, not the future release commit or proof
that the historical candidate was built from this exact commit.

| Evidence class | Verified baseline and reuse |
| --- | --- |
| Repository records | [1D local beta](phase-1d-beta1.md) and the [1D.11 completion](../validation/phase-1d11-rf-matrix-completion.md) close 1A–1D's local handoff with documented limits: complete build 5 App and matching CLI; GUI exact PING/PONG in both directions, real unplug/error/explicit Check recovery, expected timeout, receiving Cancel, active native Quit, offline Save/reopen, History, and safe export. Their original source cuts and artifact inventories remain authoritative. |
| Read-only source checks in 1E.1 | The [root workspace](../../pubspec.yaml) has four members and one [lockfile](../../pubspec.lock). Link/core/CLI are `0.1.0-beta.1`; App is `0.1.0-beta.1+5`. The existing [version checker](../../tool/check_product_version.py) passed, including internal constraints, CLI constant, and App fallbacks. Lock SHA-256: `e25ed2f37c339206d8587e42e00a0b901bb37874554813840e2025b03bbf847c`. |
| Reusable engineering foundation | [CI configuration](../../.github/workflows/ci.yml) defines Ubuntu and macOS jobs: locked resolution, version checks, analysis, Flutter/Dart/Python tests, process ownership/persistence checks, native CLI builds, Debug/Release App builds, XCTest, and complete-App relocation. [1D.11](../validation/phase-1d11-rf-matrix-completion.md) records local native/software checks and matching CLI smoke; [1D.10](../validation/phase-1d10-regression-compatibility.md#historical-schema-1-compatibility) records historical-data compatibility. These results retain their original inputs; no suites or builds were rerun here. |
| Distribution still open | Complete local App/CLI candidates exist in the historical delivery record. The original 1E.1 review left licensing, complete App/CLI materials, packaging, signing, installation, clean-environment acceptance, and public distribution open. Distribution and installation still require their own candidate-specific evidence. |

Workflow configuration is not evidence that remote CI passed at the reviewed
HEAD. This review did not query remote CI or recheck historical binaries.
Use the [developer guide](../development.md#current-flutter-sdk) for the current
Flutter 3.50.0 / bundled Dart 3.14.0 convention; actual release tools must be
recorded when building.

The [1D.11 limits](../validation/phase-1d11-rf-matrix-completion.md#limits-and-1e-handoff)
remain: intermittent USB initialization is unresolved; finite successes do not
prove a reliability fix. Physical detection latency, scheduling margin, and
host input/rendering and narrower GUI/IME coverage retain their recorded limits.
Signing or packaging does not resolve them. No complete 1A–1D rerun is required;
1E obtains the limited new evidence needed for its release changes.

## 1E.2 engineering candidate supplement

After PR #39 merged as `692ac28edaef1d4913639f7c652bfadbf525ef99`, 1E.2 selected
`0.1.0-rc.1` / App build `6`, following accepted Beta build `5`. The 1E.1 review
facts above and below remain historical facts. Full SemVer maps its numeric
core to Apple short `0.1.0`; build `6` remains separate. App runtime/new App
records identify `0.1.0-rc.1+6`; CLI/new CLI records identify `0.1.0-rc.1`.
Tracked native metadata and standard About preserve RC identity, with source,
raw-input, actual-plist and compiled-runtime checks. See the
[implementation/validation record](../validation/phase-1e2-version-identity.md)
for candidate-specific results and limitations and the
[developer contract](../development.md#product-version-and-native-identity-1e2)
for repeatable commands. Subsequent work is 1E.3 distribution-material review;
this supplement selects no license and closes no final-release gate.

## 1E.3 materials handoff

The [collection and distribution contract](phase-1e3-licenses.md) and
[current validation record](../validation/phase-1e3-materials.md) define the
dual-product material entry point. The [project license decision](project-license-decision.json)
now records GPL-3.0-only, Copyright (c) 2026 Meshchan Contributors, with
007pig confirming authority over all first-party contributions and no exceptions.
The [native SDK source rules](phase-1e3-sdk-sources.md) provide original
engine/Dart/LLVM source and build inputs; fresh native source closure verification
remains required for the complete material gate. 1E.4/1E.5 must rebind new products; 1E.6 repeats
modified-library loading from the selected local candidate.

The subsequent candidate-evidence repair selects App build `7` with the same
`0.1.0-rc.1` product version. Fresh automatic notices include the approved root
GPL text, so the changed App content does not reuse build `6`. The old 1E.2
products/records remain immutable. Current complete source-input/build/output
and replacement receipts are linked from the 1E.3 validation record; they do not
replace the separate 1E.4 build-entry or 1E.6 local signing and runtime acceptance.

The 1E.4 Release recipe selects App build `8` for the embedded Flutter
engine's runpath change. See the [build guide](phase-1e4-build.md) and
[candidate validation record](../validation/phase-1e4-build.md).

The separate [CLA](../../CLA.md) and [contribution guide](../../CONTRIBUTING.md)
define explicit, recorded incoming grants to 007pig for GPL community and
closed-source commercial editions. Contributors keep copyright. This policy
does not amend the community GPL or establish past contributors' acceptance.

## Release scope and platform support

| Item | Engineering release commitment |
| --- | --- |
| Products | Complete `Meshchan.app` and same-product-version complete `meshctl` bundle, including native assets. |
| Platform | macOS arm64. |
| Connection | An explicitly selected USB Companion; no automatic device selection or connection. |
| Existing capabilities | Offline drafts, profiles/presets, settings, finite device checks, diagnostics, History, and safe summary export, within the [host scope](../architecture/flutter-host.md#product-scope-and-decision-status). |
| Channel and download | GitHub Releases with the actual RC or release version labeled as an engineering build. One read-only, unsigned DMG carries the locally signed App, full CLI directory, and license and source materials. |
| Data continuity | Preserve current Beta drafts, profiles, settings, and diagnostic history. |

Keep these platform facts separate:

| Fact | Status and evidence |
| --- | --- |
| Engineering deployment target | macOS `12.0` in the [Xcode project](../../apps/meshchan_app/macos/Runner.xcodeproj/project.pbxproj); this is a build setting. |
| Recorded runtime environments | Build 5 preparation records macOS 27.2 arm64; the completion records the inventory-matched VM on macOS 27.2.1 (26B131). [1D.10](../validation/phase-1d10-regression-compatibility.md#actual-toolchain) also records macOS 27.2.1 arm64. These are historical tested environments, not a supported-version range. |
| Engineering macOS support and minimum tested | **macOS 27.2.1 (26B131) arm64** is the verified engineering scope for first install and Beta-to-RC upgrade. The complete arm64 App and CLI have a static loader floor of macOS 14.0. Earlier builds are outside the measured scope. See the [1E.9 validation](../validation/phase-1e9-install-upgrade.md). |

A universal executable's Intel slice does not establish Intel runtime support.
Android/iOS dependency probes do not establish mobile product support. The
source-only [openHop peer](../openhop-acceptance.md) remains a development
acceptance tool, excluded from the product. BLE, background reception, content
publication/synchronization, and automatic retry/resend are outside this release.

## Product identity, versions, and compatibility

The 1E.9 install and upgrade acceptance used App `0.1.0-rc.1+8` and CLI `0.1.0-rc.1`, with Apple short version `0.1.0` and build string `8`. Each later candidate has its own frozen source, artifact hashes, and acceptance record.

| Identity | Required correspondence |
| --- | --- |
| Full product version | Publish the actual embedded version, including the RC suffix if the selected product is an RC. The four member manifests, internal constraints, CLI constant, and App fallback/build definitions must agree on the product version. The root workspace has no product version. |
| App build | A positive, increasing integer for each new distributable App build, never reused for changed content. The RC selected for 1E.9 was build `8`, following Beta build `5` and RC builds `6` and `7`. App runtime/new App diagnostic records identify `<product-version>+<build>`. |
| Apple numeric versions | `CFBundleShortVersionString` uses the product version's numeric core. `CFBundleVersion` equals the App build. Preserve the full product version in App runtime identity and diagnostics. |
| CLI version | `meshctl --version` reports the full product version, including an RC suffix when applicable. CLI records may omit App build metadata; `build-info.json` identifies the matching App/CLI pair. |
| Source and Git tag | Select a full, frozen release commit. Final tag `v0.1.0` must point to that commit; any candidate tag uses its full version, such as `v0.1.0-rc.1`. Build metadata and acceptance identify that same commit and the exact artifacts, not just a branch name. |
| Build metadata | Record full product version, App build, Apple numeric versions, complete source commit, lock hash, actual toolchain/architecture, build inputs and steps, and the complete product inventory. |

The [Beta observation](../validation/phase-1d11-build5-gui-delay.md#source-and-complete-products)
was Apple short version `0.1.0.1`, build `5`, while Flutter used
`0.1.0-beta.1` / `5`. This is an explicit 1E.2 mapping risk, not an accepted
formal-version policy. The [Info.plist template](../../apps/meshchan_app/macos/Runner/Info.plist)
alone cannot prove generated values. In 1E.2 and subsequent candidate builds,
compare actual generated Info.plist, App version information, CLI output, build
metadata, and newly recorded diagnostic versions.

Retain Bundle ID `org.meshchan.meshchan` and the default directory
`~/Library/Application Support/meshchan`, as implemented in the
[App identity and directory decision](../../apps/meshchan_app/README.md#directory-and-sandbox-decision).
One directory has one owner, including reads: GUI and CLI must not open it
concurrently. Normal GUI Quit must confirm cleanup, storage/owner release and
worker exit, then OS process absence, before a CLI consumer opens it. Unknown
cleanup keeps resources quarantined; deleting ownership files is not recovery.

Product version, database schema (currently 1), diagnostic summary format
(currently 1), CLI JSON envelope schemaVersion (currently 1), and wireless
protocol version are managed independently. A release bump does not require a
data/protocol bump. Preserve historical diagnostic versions exactly. 1E.9 must
prove Beta-to-release business-data continuity with owned fixtures; the older
dev.2 compatibility record is supporting evidence, not that upgrade's result.

Test, upload, and user download must identify the same final artifact bytes.
Compute download checksums over the completed engineering DMG and final
release attachments. If RC-to-final changes embedded versions or any other
product content, regenerate and validate the final candidate; renaming an RC
file or reusing its hash is insufficient. Publish accepted files without a
publication-time rebuild, re-sign, or repackaging. Reproducibility here means
that recorded inputs, dependencies, and tools support repeating and tracing the
build and packaging steps. Retention and publication use the exact accepted
artifact bytes.

## Planned deliverables

The asset names and evidence below define the engineering release handoff.

| Deliverable | Responsibility |
| --- | --- |
| Local engineering DMG (1E.9 used `Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg`) | Complete local candidate directory with the App, full CLI (`bin/meshctl` plus native libraries), licenses, corresponding source, and rebuild and replacement instructions. The outer volume includes an engineering README, DMG tool source, and a payload inventory. Build records verify actual architecture of executables/libraries; filename alone is insufficient. |
| `SHA256SUMS` | SHA-256 of the final DMG and other immutable download attachments, excluding the checksum file itself. |
| `build-info.json` | Full source commit, product version, App build and Apple versions, root lockfile identity/hash, actual Flutter/Dart/Python/Xcode/compiler/SDK versions, architectures, build recipe, and product inventory reference. |
| License and source materials | Maintainer-selected project license, third-party notices for actual App and CLI contents, and applicable native/runtime source, build, and relinking materials with provenance. Separate attachments are permitted. |
| User instructions | Installation, CLI layout/use, supported macOS/USB scope, Beta upgrade and data directory/ownership behavior, known limits, and support/reporting instructions. |
| Acceptance summary | Gate results, exact test environments and limitations, bound to frozen compile source, original packaging inputs, current signing tools, DMG tools, accepted local candidate, and final DMG/asset hashes. Evidence can be retained separately with stable references; raw private evidence is not a release attachment. |

No private databases, device credentials, private peer configuration, or raw test
data belong in release assets. Existing
[CLI material collection and loader checks](../../tool/package_1c_candidate.py),
[App relocation checks](../../apps/meshchan_app/tool/check_macos_runtime.py), and
[CLI smoke checks](../../tool/smoke_cli.py) are reusable foundations, not a
complete App/CLI release packager or proof that materials are complete.

## Release gates and required evidence

Attach candidate-specific evidence for each gate. The original 1E.1–1E.5
acceptances remain part of the chain. The
[1E.6 signing](../validation/phase-1e6-signing.md) and
[1E.7 DMG](../validation/phase-1e7-dmg.md) records identify the actual
local candidate and image results.

| Gate | Existing foundation | Required final-release evidence | Responsible steps |
| --- | --- | --- | --- |
| Source and version consistency | Four-member checker, locked workspace, configured CI and local Beta records. | Frozen commit, dependency/lock identities, actual tools and architecture, version/Apple metadata/diagnostic agreement, build-info, and successful applicable CI tied to the candidate source. | 1E.2, 1E.4, 1E.8 |
| Artifact completeness | Complete Beta inventories, whole-App and CLI relocation, native-asset/loader checks. | Full App/CLI inventories, native asset provenance, internal symlink targets, permissions and load paths; no checkout/SDK/pub-cache dependency; integrity after signing and final DMG extraction. | 1E.4–1E.7, 1E.9 |
| License and provenance materials | Collected package/native notices and source fragments; recorded completeness gaps. | Project license decision and distribution materials mapped to actual App/CLI dependencies, Flutter/Dart runtime, native libraries and applicable corresponding source/build/relinking requirements. Inclusion alone is not completeness. | 1E.3, 1E.5 |
| Local code signing and DMG integrity | 1E.5 engineering package and 1E.6 local diagnostics. | Explicit `local-adhoc` profile, verified signatures for all actual code and architectures, exact Hardened Runtime and entitlement policy, CLI and VM App runtime, user library replacement, and independent verification of the read-only DMG and its fully extracted, relocated payload after unmount. | 1E.6, 1E.7 |
| Download and clean installation | Relocated local products and hardware-free VM UI records. | Real engineering download, actual quarantine and system prompts, a verified and documented user approval path under normal system protections, App and CLI offline behavior and independence from development tools, and a support conclusion tied to exact OS and architecture. Automatic Gatekeeper approval is outside the gate. | 1E.9; public recheck 1E.12 |
| Upgrade and data continuity | Historical schema-1 producer/App/CLI interoperability and exclusive ownership. | Closed Beta fixture upgraded using the final candidate; drafts/profiles/settings/history and original run versions preserved, default-directory continuity, GUI/CLI contention and orderly handoff, normal Quit/reopen. | 1E.2, 1E.9 |
| Limited real USB acceptance | 1D.11 finite exact round trips, fault/recovery, timeout, Cancel/Quit, with unresolved initialization limits. | Final packaged App/CLI identity; explicit selected-device Check, real exact round trip, active-operation Cancel or normal Quit and independent resource/process-release evidence. Retain failures and known limits; no reliability claim. | 1E.10 |
| Publication and download verification | Channel and asset policy defined here; no final release evidence. | Tag/source correspondence, user instructions and acceptance summary available; uploaded files equal accepted files; actual public downloads match final checksums/build-info and required materials. | 1E.8, 1E.11, 1E.12 |

1E.6 verifies the actual local signature and runtime entitlements on the
complete App and CLI. The build-time
[Release entitlements](../../apps/meshchan_app/macos/Runner/Release.entitlements)
and the local post-build signature policy have distinct roles. Keep the
established Sandbox setting, data directory, and exclusive ownership contract.
Installation validation uses normal system protections and a documented user
approval path. Disabling Gatekeeper or SIP, changing global protection settings,
or removing quarantine in bulk is outside that validation.

Follow [AGENTS.md](../../AGENTS.md): hardware-free GUI work uses the existing
macOS VM and applicable VM instructions; real USB work uses the host Mac.
An existing development VM is not automatically a clean machine without build
dependencies. Test ordinary default-directory behavior only in a dedicated
environment without user production data. Record VM blockers and continue
independent work, without switching hardware-free tests to host automation.

## Dependencies and open decisions

Record actual inputs and evidence at the responsible step. The engineering
route uses locally available coding and image tools and an owned VM workspace.

| Item | Current evidence/status | Owner step | Blocks |
| --- | --- | --- | --- |
| Project license | Closed in 1E.3: GPL-3.0-only; Copyright (c) 2026 Meshchan Contributors. Root LICENSE/COPYRIGHT and the approved decision record preserve 007pig's authority/no-exceptions confirmation. | Maintainer / 1E.3 | License decision closed; GPL corresponding-source and later release gates remain. |
| App and CLI third-party materials | Beta preserves notices for its graph; [earlier material gaps](phase-1c-dev3.md#materials-and-distribution-limits) and 1D.11 retain native source/build/relinking and AOT runtime correspondence work. Use the selected package receipts to bind actual Flutter/App and CLI coverage to the retained files. | 1E.3, integrated in 1E.5 | License gate and final distributable contents. |
| Developer ID, Apple Team, secure timestamps, notarization, and stapling | Inapplicable to the current profile. Deferred until explicitly requested by the maintainer. | Future official route | None for the engineering release. |
| Engineering macOS scope and clean test coverage | The independent first install and separate Beta upgrade passed on macOS 27.2.1 (26B131) arm64. Static floors are 12.0 in the App plist, 13.0 for the nested App code, and 14.0 for the full App and CLI. | Maintainer / 1E.9, carried forward in 1E.11 | Engineering installation gate is complete for the measured system. |
| Build, local signing, and retention environments | Consume the frozen 1E.4 build and accepted 1E.5 package. Record actual signing and DMG tools, the checked VM, source-specific CI, and artifact transfer and retention. | 1E.4–1E.8 | Traceable builds, local acceptance, and preservation of the accepted candidate. |

## Remaining steps and handoff

The [engineering handoff](#1e6-and-1e7-engineering-handoff) identifies the
accepted 1E.6 and 1E.7 outputs. See the
[1E.8 validation record](../validation/phase-1e8-ci-retention.md) for the
source-specific CI, the sealed and independently restored build 8, and
the exact engineering image for 1E.9.

| Step | Goal | Main dependencies and expected output |
| --- | --- | --- |
| 1E.1–1E.5 | Retain the completed release, version, materials, build, and engineering package foundations. | Preserve the original acceptance records and use this contract for the active signing and release policy. |
| 1E.6 | [Close the explicit local signing profile](phase-1e6-signing.md). | Accepted upstream package, complete locally signed App/CLI and materials, exact signature and runtime checks, user library replacement, and a new pinned candidate manifest and independent receipt. Complete as the prerequisite to 1E.7. |
| 1E.7 | [Build and independently accept the complete engineering DMG](phase-1e7-dmg.md). | Accepted local candidate, full image payload, read-only mount and complete extraction, owned detach, limited CLI and VM App runtime from the extracted copy, and final integrity and SHA-256. |
| 1E.8 | [Provide CI, controlled engineering handoff, and evidence retention](phase-1e8-ci-retention.md). | Source-specific CI, repeatable entry point, and immutable retention of the accepted image, App/CLI, materials, checksums, and evidence. |
| 1E.9 | [Accept engineering downloads, installation, and Beta upgrade](phase-1e9-install-upgrade.md). | Complete. The [validation record](../validation/phase-1e9-install-upgrade.md) covers the independent first install and the separate Beta build 5 upgrade on macOS 27.2.1 (26B131) arm64. Both used the pinned RC build 8 DMG. |
| 1E.10 | Run limited real USB/RF acceptance on the final package. | Explicit device identity and selected-device Check, a finite exact round trip, Cancel or normal Quit, and verified resource and process release. Preserve known limits. |
| 1E.11 | Finalize engineering release documentation and materials. | Local signing and notarization status, trusted source and checksum, tested installation and upgrade, full CLI, data directory and ownership, library replacement, and known limits. |
| 1E.12 | Publish engineering assets and verify actual downloads. | Upload the accepted bytes and matching source and materials to GitHub Releases under the actual selected version and corresponding source tag. Compare actual downloads to accepted SHA-256 values. |

License materials and user documentation may advance in parallel. Prepare
product changes, embedded materials, and user documentation before freezing the
release commit. Later acceptance reports bind to that commit and final artifact
hashes; retain them as release evidence without rebuilding accepted binaries
just to append reports to Git. Changes to product contents require a new
candidate and appropriate validation.

**1E.1 is complete** when this contract and necessary navigation are written,
baseline/version/path facts and local links are checked, Markdown and whitespace
checks pass (including the new file), and changes stay within documentation.
The documentation review used `/opt/homebrew/bin/python3`, Python 3.15.2
(resolved interpreter `/opt/homebrew/opt/python@3.15/bin/python3.15`) for the
existing version checker and targeted document checks. No build, remote CI,
GUI, hardware, signing, notarization, or release action is part of that result.

**All of 1E is complete** when the frozen source, actual tools, complete
products and materials, local signatures, and final image correspond. The
same accepted bytes must pass DMG extraction and limited runtime, engineering
installation and Beta upgrade, and limited real USB/RF acceptance. Completion
also requires source-specific CI, immutable retention of the accepted image,
products, materials, and evidence, accurate user documentation, and successful
verification of the actual GitHub Releases download.

## 1E.4 build entry

The [local Release entry](phase-1e4-build.md) implements repeatable complete
App/CLI builds, contemporaneous input/output receipts and explicit strict
material integration. [Its validation record](../validation/phase-1e4-build.md)
reports handoff status and identifies the exact products once accepted for 1E.5.
Later steps consume those bytes and rebind them after signing and packaging.
Final release acceptance follows the remaining gates in this contract.

## 1E.5 engineering packaging

The [package entry](phase-1e5-package.md) carries the complete accepted App,
CLI, and materials through staging and actual extraction. The
[package validation record](../validation/phase-1e5-package.md) identifies the
staging paths, immutable package evidence, and runtime acceptance for 1E.6.
The selected staging root is
`build/phase-1e5/run-002/stage/Meshchan-0.1.0-rc.1-macos-arm64/`.
Use an owned copy for local ad hoc signing and bind the resulting bytes and
acceptance evidence in new receipts.

## 1E.6 and 1E.7 engineering handoff

The selected build 8 candidate passed [independent local signing acceptance](../validation/phase-1e6-signing.md#independent-acceptance-and-1e7-handoff).
The complete [engineering DMG passed independent acceptance](../validation/phase-1e7-dmg.md#independent-acceptance)
after read-only mount, extraction, detach, and limited runtime from the
extracted copy. 1E.8 consumes the exact accepted image, checksum, and
receipts identified in the [retention handoff](../validation/phase-1e7-dmg.md#tests-and-1e8-handoff).
