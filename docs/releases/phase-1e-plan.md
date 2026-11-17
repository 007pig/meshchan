# Phase 1E release contract — 0.1.0

## Purpose and verified baseline

1E will deliver a sustainably downloadable, installable, and upgradeable
`0.1.0` through GitHub Releases. **1E.1 defines this contract; it does not
complete 1E or release the product.** The next development step is 1E.2.

The November 17, 2026 documentation review used clean `master` at
`0f89fe81823e58d524ad5a35a1f18a454b6fa4bc`, matching the planning reference.
This is the reviewed source baseline, not the future release commit or proof
that the historical candidate was built from this exact commit.

| Evidence class | Verified baseline and reuse |
| --- | --- |
| Repository records | [1D local beta](phase-1d-beta1.md) and the [1D.11 completion](../validation/phase-1d11-rf-matrix-completion.md) close 1A–1D's local handoff with documented limits: complete build 5 App and matching CLI; GUI exact PING/PONG in both directions, real unplug/error/explicit Check recovery, expected timeout, receiving Cancel, active native Quit, offline Save/reopen, History, and safe export. Their original source cuts and artifact inventories remain authoritative. |
| Read-only source checks in 1E.1 | The [root workspace](../../pubspec.yaml) has four members and one [lockfile](../../pubspec.lock). Link/core/CLI are `0.1.0-beta.1`; App is `0.1.0-beta.1+5`. The existing [version checker](../../tool/check_product_version.py) passed, including internal constraints, CLI constant, and App fallbacks. Lock SHA-256: `e25ed2f37c339206d8587e42e00a0b901bb37874554813840e2025b03bbf847c`. |
| Reusable engineering foundation | [CI configuration](../../.github/workflows/ci.yml) defines Ubuntu and macOS jobs: locked resolution, version checks, analysis, Flutter/Dart/Python tests, process ownership/persistence checks, native CLI builds, Debug/Release App builds, XCTest, and complete-App relocation. [1D.11](../validation/phase-1d11-rf-matrix-completion.md) records local native/software checks and matching CLI smoke; [1D.10](../validation/phase-1d10-regression-compatibility.md#historical-schema-1-compatibility) records historical-data compatibility. These results retain their original inputs; no suites or builds were rerun here. |
| Distribution still open | Complete local App/CLI candidates exist in the historical delivery record. Project licensing, final App/CLI materials, repeatable release packaging, Developer ID, notarization, installation, clean-environment acceptance, and public distribution remain 1E work. Local ad hoc signature checks are not public-release acceptance. |

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
modified-library loading under formal signing conditions.

The subsequent candidate-evidence repair selects App build `7` with the same
`0.1.0-rc.1` product version. Fresh automatic notices include the approved root
GPL text, so the changed App content does not reuse build `6`. The old 1E.2
products/records remain immutable. Current complete source-input/build/output
and replacement receipts are linked from the 1E.3 validation record; they do not
replace the separate 1E.4 build-entry or 1E.6 formal-signing acceptance.

The separate [CLA](../../CLA.md) and [contribution guide](../../CONTRIBUTING.md)
define explicit, recorded incoming grants to 007pig for GPL community and
closed-source commercial editions. Contributors keep copyright. This policy
does not amend the community GPL or establish past contributors' acceptance.

## Release scope and platform support

| Item | First release commitment |
| --- | --- |
| Products | Complete `Meshchan.app` and same-product-version complete `meshctl` bundle, including native assets. |
| Platform | macOS arm64. |
| Connection | An explicitly selected USB Companion; no automatic device selection or connection. |
| Existing capabilities | Offline drafts, profiles/presets, settings, finite device checks, diagnostics, History, and safe summary export, within the [host scope](../architecture/flutter-host.md#product-scope-and-decision-status). |
| Channel and download | GitHub Releases; one DMG containing the App, full CLI directory, and installation materials. |
| Data continuity | Preserve current Beta drafts, profiles, settings, and diagnostic history. |

Keep these platform facts separate:

| Fact | Status and evidence |
| --- | --- |
| Engineering deployment target | macOS `12.0` in the [Xcode project](../../apps/meshchan_app/macos/Runner.xcodeproj/project.pbxproj); this is a build setting. |
| Recorded runtime environments | Build 5 preparation records macOS 27.2 arm64; the completion records the inventory-matched VM on macOS 27.2.1 (26B131). [1D.10](../validation/phase-1d10-regression-compatibility.md#actual-toolchain) also records macOS 27.2.1 arm64. These are historical tested environments, not a supported-version range. |
| Final minimum supported macOS | **Pending 1E.9 limited clean-environment validation and maintainer approval.** Record exact tested versions and choose a defensible minimum before publication; do not claim macOS 12 and later are all accepted. |

A universal executable's Intel slice does not establish Intel runtime support.
Android/iOS dependency probes do not establish mobile product support. The
source-only [openHop peer](../openhop-acceptance.md) remains a development
acceptance tool, excluded from the product. BLE, background reception, content
publication/synchronization, and automatic retry/resend are outside this release.

## Product identity, versions, and compatibility

These are rules for subsequent work; 1E.1 changes no versions or configuration.

| Identity | Required correspondence |
| --- | --- |
| Full product version | Final `0.1.0`; candidates may use `0.1.0-rc.1`, etc. The four member manifests, internal constraints, CLI constant, and App fallback/build definitions must agree on the product version. The root workspace has no product version. |
| App build | A positive, increasing integer for each new distributable App build, never reused for changed content. Current build is `5`; the next must be at least `6`, rechecked against actual state in 1E.2. App runtime/new App diagnostic records identify `<product-version>+<build>`. |
| Apple numeric versions | Final `CFBundleShortVersionString` must be `0.1.0`; `CFBundleVersion` must equal the App build. 1E.2 must define and check the numeric mapping for prereleases without losing the full product version or confusing build ordering. |
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
Compute download checksums after signing, notarization/stapling as applicable,
and final packaging. If RC-to-final changes embedded versions or any other
product content, regenerate and validate the final candidate; renaming an RC
file or reusing its hash is insufficient. Publish accepted files without a
publication-time rebuild. “Reproducible” here means inputs, dependencies, steps,
and results can be rebuilt and traced; timestamped signatures are not promised
to be byte-identical.

## Planned deliverables

The following names describe future release assets, not existing files:

| Deliverable | Responsibility |
| --- | --- |
| `Meshchan-0.1.0-macos-arm64.dmg` | Complete App, full CLI directory (`bin/meshctl` plus native libraries), and installation materials. Build records verify actual architecture of executables/libraries; filename alone is insufficient. |
| `SHA256SUMS` | SHA-256 of the final DMG and other immutable download attachments, excluding the checksum file itself. |
| `build-info.json` | Full source commit, product version, App build and Apple versions, root lockfile identity/hash, actual Flutter/Dart/Python/Xcode/compiler/SDK versions, architectures, build recipe, and product inventory reference. |
| License and source materials | Maintainer-selected project license, third-party notices for actual App and CLI contents, and applicable native/runtime source, build, and relinking materials with provenance. Separate attachments are permitted. |
| User instructions | Installation, CLI layout/use, supported macOS/USB scope, Beta upgrade and data directory/ownership behavior, known limits, and support/reporting instructions. |
| Acceptance summary | Gate results, exact test environments and limitations, bound to the frozen source commit and final DMG/asset hashes. Evidence can be retained separately with stable references; raw private evidence is not a release attachment. |

No private databases, device credentials, private peer configuration, or raw test
data belong in release assets. Existing
[CLI material collection and loader checks](../../tool/package_1c_candidate.py),
[App relocation checks](../../apps/meshchan_app/tool/check_macos_runtime.py), and
[CLI smoke checks](../../tool/smoke_cli.py) are reusable foundations, not a
complete App/CLI release packager or proof that materials are complete.

## Release gates and required evidence

All final-candidate gates below are **pending**. Existing evidence supplies a
baseline only; the later steps must attach candidate-specific results and close
each gate before marking all of 1E complete.

| Gate | Existing foundation | Required final-release evidence | Responsible steps |
| --- | --- | --- | --- |
| Source and version consistency | Four-member checker, locked workspace, configured CI and local Beta records. | Frozen commit, dependency/lock identities, actual tools and architecture, version/Apple metadata/diagnostic agreement, build-info, and successful applicable CI tied to the candidate source. | 1E.2, 1E.4, 1E.8 |
| Artifact completeness | Complete Beta inventories, whole-App and CLI relocation, native-asset/loader checks. | Full App/CLI inventories, native asset provenance, internal symlink targets, permissions and load paths; no checkout/SDK/pub-cache dependency; integrity after signing and final DMG extraction. | 1E.4–1E.7, 1E.9 |
| License and provenance materials | Collected package/native notices and source fragments; recorded completeness gaps. | Project license decision and distribution materials mapped to actual App/CLI dependencies, Flutter/Dart runtime, native libraries and applicable corresponding source/build/relinking requirements. Inclusion alone is not completeness. | 1E.3, 1E.5 |
| Formal signing and notarization | Local ad hoc signing checks only. | Developer ID identity/team, signatures on applicable App/CLI nested code, applicable Hardened Runtime, actual final entitlements, post-sign runtime checks, accepted notarization and applicable stapled-ticket verification for final deliverables. | 1E.6, 1E.7 |
| Download and clean installation | Relocated local products and hardware-free VM UI records. | Real downloaded candidate, macOS quarantine/Gatekeeper checks with normal security settings, ordinary installation, App and CLI offline Save/reopen/settings/History/export and independence from development tools; exact OS/architecture and minimum support decision. | 1E.9; public recheck 1E.12 |
| Upgrade and data continuity | Historical schema-1 producer/App/CLI interoperability and exclusive ownership. | Closed Beta fixture upgraded using the final candidate; drafts/profiles/settings/history and original run versions preserved, default-directory continuity, GUI/CLI contention and orderly handoff, normal Quit/reopen. | 1E.2, 1E.9 |
| Limited real USB acceptance | 1D.11 finite exact round trips, fault/recovery, timeout, Cancel/Quit, with unresolved initialization limits. | Final packaged App/CLI identity; explicit selected-device Check, real exact round trip, active-operation Cancel or normal Quit and independent resource/process-release evidence. Retain failures and known limits; no reliability claim. | 1E.10 |
| Publication and download verification | Channel and asset policy defined here; no final release evidence. | Tag/source correspondence, user instructions and acceptance summary available; uploaded files equal accepted files; actual public downloads match final checksums/build-info and required materials. | 1E.8, 1E.11, 1E.12 |

Signing, notarization, and App Sandbox are separate concerns. Current
[Release entitlements](../../apps/meshchan_app/macos/Runner/Release.entitlements)
request none; local configuration does not establish a usable Developer ID
identity. 1E.6 decides and verifies actual signing/runtime entitlements while
preserving the adopted data-directory contract; enabling Sandbox is not implied
by notarization.

Follow [AGENTS.md](../../AGENTS.md): hardware-free GUI work uses the existing
macOS VM and applicable VM instructions; real USB work uses the host Mac.
An existing development VM is not automatically a clean machine without build
dependencies. Test ordinary default-directory behavior only in a dedicated
environment without user production data. Record VM blockers and continue
independent work, without switching hardware-free tests to host automation.

## Dependencies and open decisions

These unknowns do not block 1E.1. Record decisions/evidence at the responsible
step; no keychain scan, credential access, Apple login, or secret collection is
needed to complete this contract.

| Item | Current evidence/status | Owner step | Blocks |
| --- | --- | --- | --- |
| Project license | Closed in 1E.3: GPL-3.0-only; Copyright (c) 2026 Meshchan Contributors. Root LICENSE/COPYRIGHT and the approved decision record preserve 007pig's authority/no-exceptions confirmation. | Maintainer / 1E.3 | License decision closed; GPL corresponding-source and later release gates remain. |
| App and CLI third-party materials | Beta preserves notices for its graph; [earlier material gaps](phase-1c-dev3.md#materials-and-distribution-limits) and 1D.11 retain native source/build/relinking and AOT runtime correspondence work. Final Flutter/App and CLI coverage is unverified. | 1E.3, integrated in 1E.5 | License gate and final distributable contents. |
| Developer ID, Apple team, notarization credentials | No repository evidence establishes usable certificates/private keys, team access, or notarization credentials. Ad hoc configuration is insufficient; maintainer availability confirmation is pending. | Maintainer / 1E.6–1E.7 | Formal signing, notarization and final DMG. |
| Minimum macOS and clean test coverage | Deployment target 12.0; recorded 27.2/27.2.1 runtime evidence does not establish an older supported minimum. Test environment/version selection and limited acceptance are pending. | Maintainer / 1E.9, documented in 1E.11 | Supported-version promise and installation gate. |
| Final build and signing environments | Existing local toolchain and CI provide a foundation. No final release executor, actual tool versions, signing environment, or artifact-transfer/retention arrangement has been selected and verified. | 1E.4, 1E.6, 1E.8 | Traceable builds, signing and preservation of the accepted candidate. |

## Remaining steps and handoff

| Step | Goal | Main dependencies and expected output |
| --- | --- | --- |
| 1E.2 | Unify version, App identity, and compatibility checks. | This contract and actual build state; checked full/Apple version mapping, increasing build policy, stable Bundle ID/directory, generated metadata and new-record expectations. |
| 1E.3 | Complete license and third-party distribution materials. | Maintainer license decision and actual App/CLI closure; notices and applicable source/build/relinking materials with provenance and remaining gaps closed. |
| 1E.4 | Establish a reproducible Release build entry. | 1E.2 and selected executor/toolchain; locked App/CLI build recipe, explicit source inputs, build-info and inventories. |
| 1E.5 | Package complete products and check integrity. | 1E.3–1E.4; full App/CLI staging, materials, symlink/mode/native-loader checks and extraction verification. |
| 1E.6 | Apply Developer ID signing and verify runtime. | Staged products, identity/team and signing environment; signed nested products, actual entitlements/Hardened Runtime and runtime evidence. |
| 1E.7 | Notarize and produce the final DMG. | 1E.6, notarization access and complete contents; accepted notarization/tickets, final DMG, post-processing inventories and hashes. |
| 1E.8 | Provide CI, release entry, and candidate retention. | 1E.4–1E.7 as available; source-specific CI results, controlled release entry and immutable candidate/evidence retention for later publication. |
| 1E.9 | Accept clean installation and Beta upgrade. | Retained final candidate, owned Beta fixtures and suitable clean macOS environments; real-download/install/offline/upgrade evidence and minimum OS decision. |
| 1E.10 | Run limited USB acceptance on the final package. | Final candidate, explicit hardware authorization and host test setup; finite Check/exact round trip/Cancel-or-Quit release evidence. |
| 1E.11 | Complete user-facing release documentation. | Scope, material and install/upgrade decisions; prepared installation, upgrade, support and known-limit instructions, finalized before source freeze. |
| 1E.12 | Publish and verify actual downloads. | All prior gates closed, final source/tag choice and accepted immutable assets; GitHub Release plus public-download/hash/material verification. |

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

**All of 1E is complete** only when every release gate has candidate-specific
passing evidence, external decisions are resolved, user-facing support/limits
are accurate, and the public downloads match the accepted final assets.
1E.2 can start from build 5, the checked member/constant/fallback versions, the
observed Apple-version mapping risk, and the preserved identity/data contracts
above; it must recheck actual source state before making its changes.
