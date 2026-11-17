# Phase 1E.3 — App/CLI distribution materials validation

## Outcome and source

Validated on November 17, 2026. **Current complete 1E.3 acceptance is PASS for
newly built App `0.1.0-rc.1+7` and matching CLI `0.1.0-rc.1`.** The
[trusted build-7 supplement](#trusted-build-7-candidate-evidence-and-current-result)
records complete contemporaneous source/build/output evidence and fresh
replacement observations. The old 1E.2 build-6 record remains incomplete; it was
not retroactively repaired or relabeled. The earlier review correction remains
valid for that historical candidate. Native SDK source coverage, the approved
license and the CLA remain verified. Public release and final signed/DMG bytes
remain subsequent 1E work.

The project decision remains **GPL-3.0-only, Copyright (c) 2026 Meshchan
Contributors**. 007pig's authority confirmation over all first-party contributions
with no exceptions remains unchanged. Root LICENSE is the unmodified GNU GPLv3
text. The CLA/contribution policy remains separate, retaining contributor
ownership and requiring explicit acceptance for the commercial sublicensing grant.
No new authorization was inferred or requested.

Earlier review packages and open-gate results below are historical evidence;
they are not retroactively relabeled as passes. The native source supplement
closes their engine/runtime source blocker; the latest review correction records
the separate candidate compilation-binding gap.

Started on clean local `master`, HEAD
`cc99901ab31570fbc62657fc30ef404b0589c9bc`. GitHub PR #40 was rechecked:
MERGED at `2026-11-17T09:06:29Z`, merge commit equal to HEAD, head
`34749dcb4c6e46c72af0b78d7a24ee93940ebee3`. That head is an ancestor of the
local merge. This work adds reviewable uncommitted tools and documentation to
that baseline; the manifest records actual source-input hashes rather than
representing the unchanged merge commit as all collection inputs. No merge,
reset, cleanup, commit, tag, upload, dependency change or version bump occurred.

The [contract and executable commands](../releases/phase-1e3-licenses.md) are the
maintenance entry point. `candidate_common.production_closure()` now accepts
explicit roots and rejects missing/duplicate nodes. Its CLI root default, original
three-member default and `0.1.0-dev.3` historical contract remain intact. The new
collector uses one materials manifest, and keeps the old 1C packaging semantics.

## Actual inputs and identity

| Input | Observed value |
| --- | --- |
| Python command | `/opt/homebrew/bin/python3`, Python 3.15.2; actual `sys.executable` `/opt/homebrew/opt/python@3.15/bin/python3.15` |
| Host/compiler | macOS 27.2.1 arm64; Apple Clang 21.0.0 (`clang-2100.4.1.1`), existing Xcode 27.2/macOS SDK 27.2 |
| Flutter | Existing `/opt/homebrew/share/flutter`, 3.50.0 stable; framework `ab2912035e160d9cad6306df307576da6128ebdb`; tracked SDK tree clean |
| Engine | `371f77202a73e8dff57a8b3bff75bca55c090aee`; content hash `bf601093ad255aaf5c6d0fc5c4f9acfa60943b2a` |
| Bundled Dart | 3.14.0, revision `fa8c1270c374c1346931583a17c3b7f278d3822d` |
| Root lock SHA-256 | `e25ed2f37c339206d8587e42e00a0b901bb37874554813840e2025b03bbf847c`; unchanged after locked resolution |
| Product | CLI `0.1.0-rc.1`; App `0.1.0-rc.1+6`; Apple short `0.1.0`, build string `6` |
| Actual App | `apps/meshchan_app/build/macos/Build/Products/Release/Meshchan.app` |
| Complete CLI | `build/phase-1e2/cli/bundle` |

The actual current candidates were re-read, inventoried (including internal
framework symlinks), version-checked and bound to the independent 1E.2 compilation
input hash record and candidate checksums. Historical PASS statements were not
substituted for these checks. Current runner hash remains
`c258e8394578717ce7c332f25591d62d106aaa8b63e143fe1e209664248cf1e4`;
CLI remains `cb69ccea12c141f17097b5f98dc1e75cca673ecfdb2ca4e803da8db6eef6ac5c`.
App.framework/App remains
`a589a217c8ccade1c95e5181193d06dcb808051d18a5a27e7e05620a4c11e8ca`.
The original candidates were not edited or re-signed. Build 6 was not reused for
new distributable App contents; replacement experiments use isolated test copies.

## Original pre-decision review package and coverage

The preserved pre-decision local package is `build/phase-1e3/materials/`, about 14 MiB,
with **145 collected material files** plus `materials-manifest.json`.
It retains its original pending-license status; the GPL follow-up has a separate
package and records below.

- Manifest SHA-256: `0d5c3c2fe5eadcedaa07551230c375075d7c7d676647c4a69a05fa586c4cd721`.
- THIRD_PARTY_NOTICES.md SHA-256: `fe549d51b01cbf04c50aae8f9473fe0d97571c8ec84bf4135b533d3e6ad7dd2f`.
- Two collections with identical final inputs produced byte-identical manifests
  and material hashes (`materials/` and `repeat-delivery-materials/`).
- App closure: 43 nodes including first party; CLI closure: 33. The union has
  41 third-party components: 11 App-only, one CLI-only (`args`), 29 shared.
- All four members remain first party. Build-helper edges are annotated from
  the reviewed native hooks, never globally pruned by package name. Dev-only
  nodes are listed separately. This is conservative declared dependency coverage,
  not proof of symbol-level AOT inclusion.

For all hosted components, the exact pub archives were SHA-256 verified against
the lock and every original archive file was cross-checked against the actual
cache. No differences were found. Root and nested notices retain original bytes.
No cache was cleared or repaired. Fixed non-pub sources and hashes are recorded
in `tool/release_materials_sources.json`; large inputs stay in ignored downloads.

App coverage includes Flutter/framework and engine/Dart aggregate, ICU, App-only
material_ui 1.11.0 and related packages, raw/decoded NOTICES.Z, the actual
FontManifest/NativeAssetsManifest, shaders under their package/framework notices,
and the separately attributed Material Icons subset. `flutter_localizations` has
no independent package-root license: it is explicitly bound to the original
Flutter repository license rather than filled with a guessed license.

The generated App notices were textually compared against the independently
collected originals. libserialport_plus original/nested entries and the complete
sky_engine aggregate are not all present as exact text (the registry merges
aggregate entries); they remain separately collected supplements. The entire
Material Icons original text was also absent. Its actual SDK license is CC BY 4.0,
and font metadata says `Copyright 2019 Google LLC. All Rights Reserved.` Both
font and license were checked against the exact SDK-stamped font archive. Notices
supply attribution, source/license links and Flutter subsetting disclosure. There
is no bundled Roboto font in the actual FontManifest.

CLI coverage includes the complete native assets, CLI/shared declared components,
independently identified embedded AOT runtime and SDK-wide original aggregate.
The collector retrieves the official exact-revision sky_engine archive, verifies
its pin and its full 1,331,982-byte license against the installed original. Flutter
DEPS matches the actual Dart revision; all nonempty file-backed CLI runtime
sections match dartaotruntime, and App engine sections match the SDK release
framework. Empty reserved runtime metadata sections contain no bytes and are
excluded explicitly. This is a conservative official aggregate tied to actual
runtime inputs, not reliance on a root SDK LICENSE or the automatic App notices.
The aggregate may contain notices for more code than these products use.

## Native source and replacement results

libserialport_plus 1.0.5 MIT wrapper and embedded LGPL-3.0-or-later libserialport
are separate entries. The exact source archive SHA-256 is
`9246f3a0909e4bc87ef2ac1366bbc2eb350d139f976a277dd5c29b8d3dc085e3`.
Full archive, original source tree, headers, configuration, hook, metadata, LGPLv3,
GPLv3 and copyright notices are delivered. config.h 0.1.1 versus configure.ac
0.1.2 still prevents proof of an upstream tag; this noncritical metadata is
recorded as unknown without denying the actual exact corresponding source.

`tool/rebuild_release_serial.py` rebuilt the prepared unmodified source and used
only its package-version function through ctypes. It then inserted an early
empty-list return and unique marker into sp_list_ports and rebuilt a genuinely
modified library. All compiler argv, diagnostics, tool identity and source/output
hashes are in `evidence/serial-rebuild.json`; inputs remain under
`/tmp/meshchan-lgpl-0evl3r92` and copied output evidence is in the materials.
No bit-identical rebuild claim is made.

| Native evidence | Actual result |
| --- | --- |
| Original-source rebuilt dylib | `f7632abc7ad48e88f2985dc688122d69602295d6102f25d6836a5f6bbe7e757b` |
| Modified rebuilt dylib | `2c255c58d698934194b2070e9226e2deac804eb93facd615c074d09e4e4f196d` |
| CLI complete-copy replacement | PASS: `ports --json` returned an empty list and `MESHCHAN_MODIFIED_SERIAL_EMPTY_LIST` on stderr, proving the actual product called the replacement. No port OS backend was reached. |
| App complete-copy replacement | PASS under local ad hoc conditions: adjusted framework ID, signed isolated framework/App, verified deep signature, transferred to existing identity-checked VM and compared the guest replacement-library hash. Device/Refresh produced the same call marker. |
| App replacement signed library | `1681d044d7e39524aab3b83934fde367d3fece9791b143ef4ad92ca6084c5efb` |
| Normal VM Quit | PASS: resourcesReleased/workerExited true, owner released, pendingRequests/receivePorts zero, independent PID absence. Executor finished normally. |

The existing VM skill/product helper used guest run
`20261117T091722Z-product-95439`, dedicated console `meshchantest`, VirtualMac2,1,
macOS 27.2.1, owned fixture outside the default data directory. The exact
PID/arguments/focus checks preceded guest input. No host GUI automation, real
USB enumeration, port open, RF, user database, IME matrix or broader UI regression
was performed. The CLI's `--version` was not used as serial-loading proof.
App and CLI loading results are independent observations. Actual VM receipts,
normal shutdown and guest library hash are attached to the probe report.

The documented LGPL route is section 4(d)(1), with accompanying corresponding
library source/build materials and preserved modification/debugging rights.
Current About/help/version show version but no first-party copyright display;
the distribution notice remains prominent alongside both products. Formal
Developer ID/Hardened Runtime replacement behavior and installation information
conditions must be repeated/assessed in 1E.6. No entitlements, signing policy,
system security setting or original SDK/candidate was changed here.

SQLite wrapper 3.9.1 is MIT, while the actual default native SQLite is 3.54.1,
source ID `2026-10-16 14:45:20 555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76`.
The immutable package-release commit
`f144d1c56b22d5772d164c7c3f20eb1df482fcf3` recipes, workflow and SBOM generator
identify the default amalgamation, distinct from encryption variants. Its exact
amalgamation and original public-domain declaration were retained. Version/source
ID and compile options were read without opening a database. Raw download hashes
match the locked hook table: arm64 `38c4a60bacdf3f4fddcb90fae011e06e5ebade251870a960cbb5284cb64783ea`,
x64 `6de79c73a781d6ce54d2303dd2cc509a7f7f27040cec0576bb50b4443fe135c8`.

Actual hook input/output, source metadata, raw assets and every target slice were
cross-checked. Serial's macOS deployment configuration distinguishes CLI 12 from
App native 13; SQLite's precompiled selection does not compile to that input
minimum. Matching architecture/default source/hash table and file-backed sections
bind SQLite's raw and delivered assets. Install-name/signature differences are
recorded separately with raw and bundled loader records and hashes. Compatible
cross-product caches are allowed; stale, mismatched and ambiguous mappings fail.
App x64 material coverage establishes no Intel runtime support.

## Commands and results

Full local evidence is in `build/phase-1e3/evidence/`; reproducible full argv are
in the linked release contract and probe report. Python was invoked explicitly;
Python subprocess orchestration uses `sys.executable`.

| Command/gate | Result in this task |
| --- | --- |
| `flutter pub get --enforce-lockfile` with existing SDK/Apple tool PATH | PASS; unchanged lock, `pub-get.log` |
| Bundled Dart `pub deps --json` and `tool/release_materials_inputs.dart` | PASS; real graph, lock and four-member parsing; no dependency update |
| `release_materials.py collect` with actual App/CLI/SDK, downloads and probe paths | Exit 0, REVIEW_REQUIRED; 145 originals/evidence files, `collect-delivery.json` |
| Same `release_materials.py check` | Exit 1 intentionally; integrityAndCoverage PASS, thirdPartyMaterials PASS; sole failure project license, `check-delivery.json` |
| Repeat collection and `cmp` of manifests | PASS; identical final manifest/material hashes |
| Independent missing-source-hook and removed-manifest-entry checks on full copied materials | Both exit 1 with integrityAndCoverage/thirdPartyMaterials FAIL; each detected the concrete omission; `negative-checks-delivery.json` |
| `python3 -m unittest discover -s tool -p '*_test.py'` | PASS, 150 tests, `python-tests-delivery.log`; includes affected common/regression/version tooling |
| Final focused `release_materials_test.py` | PASS, 9 tests; dual roots/shared helper paths, first party, missing nodes/version/source, byte preservation, nested source/notices, omitted/tampered coverage, strict open gates, native target/section/metadata freshness and historical defaults |
| `dart analyze tool/release_materials_inputs.dart` / focused format gate | PASS, no issues/changes |
| `check_product_version.py --expected-version 0.1.0-rc.1 --app-build 6 --app <actual App>` | PASS; source and actual plist identity rechecked |
| Native original rebuild, independent version function, complete-copy CLI call, VM App Refresh and normal Quit | PASS within the explicit hardware-free/local signing scope above |
| `git diff --check` | PASS |

Preserved failures: initial sandbox Flutter resolution could not write its normal
cache lock/stamps, and direct curl could not resolve pub.dev. Permission-correct
runs succeeded without global settings changes. The initial CLI probe incorrectly
supplied --data-dir to the storage-free ports command and exited 64 before a port
call; corrected argv passed. The initial VM command used `act` instead of the
helper's `action` and exited at argument parsing; corrected guest action passed.
An initial sandbox regression test received BLOCKED instead of its expected child
failure because /bin/ps was denied; the normal-access full suite passed. An initial
Dart analyzer notice about the intentionally reused locked transitive YAML parser
was addressed with a tooling-specific explanatory suppression, without changing
product dependencies. Earlier collection iterations retain their original open
gates in their logs and are not relabeled as final passes.

Not run: full Dart/App business suites, USB/RF, the complete GUI/IME matrix, DMG,
Developer ID, notarization, installation/upgrade or minimum supported OS acceptance,
remote CI and publication. No product behavior changed to require those suites.

## Historical approved GPL follow-up and source gate

The maintainer approved GPL-3.0, Copyright (c) 2026 Meshchan Contributors,
and explicitly confirmed that 007pig has authority over every first-party
contribution with no exceptions. This is recorded as GPL-3.0-only; authorization
for later license versions is not inferred. No further maintainer license
confirmation is pending.

Root LICENSE is byte-identical to the previously retrieved, pinned GNU original:
`3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`.
Its FSF copyright applies to the license document, while project COPYRIGHT
(`0341970e78fa91e4da4c154c7de6c231db44cfa5ee82347486b9bc9557165999`)
and README state the Meshchan attribution and license scope. Both hashes are
bound to the approved decision and checked independently. Third-party originals
and terms are retained.

The current GPL collection is under `build/phase-1e3-gpl/`, separate from earlier
review packages. It adds an actual deterministic first-party source snapshot,
all hosted production/helper source archives at locked hashes, Flutter framework
and build-source snapshots, engine source/build definitions, and the actual
Dart VM/runtime and SDK-library source archives at revision
`fa8c1270c374c1346931583a17c3b7f278d3822d`. These were downloaded from the
exact official revision, SHA-256 pinned and collected, not merely linked.
COPYRIGHT and LICENSE are included with the first-party source and materials.
The original App/CLI bytes, version/build, root lock and native probe inputs
remain unchanged and are independently rechecked; no new App content was built.

The installed SDK lacks separate native DEPS source checkouts, specifically
`engine/src/flutter/third_party/skia`, `engine/src/flutter/third_party/icu`,
`engine/src/flutter/third_party/boringssl/src`, and the Dart checkout. Exact
Dart runtime/library sources were obtained separately, but the complete native
dependency/build-source closure for the combined products has not been
established. The delivered DEPS/build files and original notices identify
inputs; they are not a substitute for all required actual corresponding source.
No exemption as a System Library is assumed for bundled engine/runtime code.
This produces the explicit fatal gate:

```text
GPL corresponding-source closure for Flutter engine and Dart runtime native DEPS/build inputs is not verified
```

The project-license gate is closed even when this separate source gate fails.
Preserved original native rebuild and VM replacement receipts were rehashed and
matched to current products; they were not rerun or relabeled as new GUI tests.
New validation uses `/opt/homebrew/bin/python3`, Python 3.15.2, with the unchanged
Flutter 3.50.0/bundled Dart 3.14.0. The follow-up commands and exact current
manifest identity are recorded in the final result supplement below.

1E.3 needs the matching engine/runtime native sources and build-input coverage
audit before its complete gate can close. 1E.4 supplies fresh independent
compilation-input and candidate-checksum records; 1E.5 stages full matching source
with both GPL products or equivalent access on the same release entry. 1E.6
repeats replacement/installation-information validation under formal signing
conditions. Current source snapshots/material hashes are not final DMG checksums.

The collected engine snapshot is identified by the installed Flutter framework
checkout revision. Its correspondence to the prebuilt engine artifact revision
also belongs to the open GPL source audit; a nearby framework checkout is not
asserted to be the complete exact engine corresponding source.

## Historical GPL follow-up results

Current materials: `build/phase-1e3-gpl/materials/`, about **77 MiB**,
**186 collected files** plus the manifest. Earlier pre-decision and intermediate
packages remain separate and retain their original identities.

- Manifest SHA-256: `5f02da30f724275ec7e1ee687f93f80dfec8f1fe3870bf05d31b27c46963f411`.
- THIRD_PARTY_NOTICES.md SHA-256: `a7acef82a2b8bacfa3b1847db54291def78a9536a2793bc92343745651411e20`.
- First-party source snapshot: 330 selected actual files, including generated
  sources, native App configuration, build tools, license/decision and instructions.
- Flutter framework/build snapshot: 3,846 files; engine source/build snapshot:
  6,206 files, with safe internal source symlinks retained. These counts establish
  snapshot coverage, not completeness of the missing native DEPS closure.
- Root lock remains `e25ed2f37c339206d8587e42e00a0b901bb37874554813840e2025b03bbf847c`.
- Both products retain their original runner/executable hashes and RC/build identity.
- Actual root LICENSE and COPYRIGHT bytes match their collected copies and decision
  hashes. The checker also rejects a decision that calls the canonical GPL text MIT,
  preventing a mislabeled expression from skipping the GPL source rule.

Commands used the actual paths above and `/opt/homebrew/bin/python3` (3.15.2):

```sh
PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH" /opt/homebrew/share/flutter/bin/flutter pub get --enforce-lockfile
/opt/homebrew/bin/python3 tool/release_materials.py collect --flutter /opt/homebrew/share/flutter --app apps/meshchan_app/build/macos/Build/Products/Release/Meshchan.app --cli build/phase-1e2/cli/bundle --downloads build/phase-1e3/downloads --output build/phase-1e3-gpl/materials --probe build/phase-1e3/evidence/serial-rebuild.json
/opt/homebrew/bin/python3 tool/release_materials.py check --flutter /opt/homebrew/share/flutter --app apps/meshchan_app/build/macos/Build/Products/Release/Meshchan.app --cli build/phase-1e2/cli/bundle --downloads build/phase-1e3/downloads --output build/phase-1e3-gpl/materials --probe build/phase-1e3/evidence/serial-rebuild.json
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
/opt/homebrew/bin/python3 -m unittest discover -s tool -p 'release_materials_test.py' -v
/opt/homebrew/bin/python3 tool/check_product_version.py --expected-version 0.1.0-rc.1 --app-build 6 --app apps/meshchan_app/build/macos/Build/Products/Release/Meshchan.app
```

Use a fresh output directory when reproducing collection; the current canonical
materials directory was preserved from the final successful collection after
retaining earlier iterations separately.

| Follow-up gate | Actual result |
| --- | --- |
| Locked resolution | PASS, unchanged dependencies/lock; `build/phase-1e3-gpl/evidence/pub-get.log` |
| Root license/attribution and authorized decision binding | PASS; no pending-maintainer gate remains |
| Final real collection | Exit 0, REVIEW_REQUIRED, 186 files; `collect-bound-license.json` |
| Final strict check | Exit 1; integrityAndCoverage PASS, thirdPartyMaterials FAIL; sole failure is the GPL engine/runtime corresponding-source closure; `check-bound-license.json` |
| Repeat collection | Identical manifest/material hashes; `repeat-final-materials/`, `collect-repeat-final.json` |
| Missing collected COPYRIGHT in an isolated full material copy | Exit 1 with the precise missing/changed COPYRIGHT error, plus the independently open source gate; `check-negative-copyright.json` |
| Full Python tool suite | PASS, 152 tests; `python-tests.log` |
| Final focused material tests | PASS, 11 tests; `material-tests-bound-license.log`; approved attribution/authority/hash checks, wrong license expression, source snapshot stability/bytes and GPL archive expansion included |
| Source/actual App version check | PASS, unchanged `0.1.0-rc.1` / App build 6; `version-identity.json` |
| `git diff --check` | PASS |

The first GPL collection stopped on an internal SDK source symlink. The source
snapshot implementation was corrected to preserve internal links and reject
external links, and new collections completed. The failed partial directory is
retained as `failed-initial-materials`; it is not a successful material package.
No GUI, native rebuild, hardware, signing/notarization or publication task was
rerun in this follow-up. Prior native/VM receipts are reused only after byte and
candidate binding checks, with their original scope preserved.

**Historical state: the requested license/attribution decision is implemented and
verified; strict full material acceptance is FAIL for the explicit additional
GPL source gate. Complete 1E.3 and public distribution are not declared passed.**

## Historical contribution agreement follow-up

On November 17, 2026, the maintainer requested a separate CLA and contribution
policy. Root CLA.md version 1.0 (`meshchan-cla-1.0`) preserves contributor
ownership and explicitly grants 007pig nonexclusive permissions for the GPL
community edition and paid, closed-source commercial editions, including the
corresponding sublicenses. CONTRIBUTING.md and the PR template describe the
manual process. The root GPL text and project COPYRIGHT are unchanged.

Acceptance requires the contributor's own explicit PR comment referencing the
immutable CLA commit, document SHA-256, signing capacity, disclosed exclusions,
and covered PR head. New heads require updated acceptance, and every relevant
rights holder must be covered. 007pig or an expressly authorized representative
records the Recipient's acknowledgement and review before merge. A checkbox,
DCO sign-off, bot comment, or the act of submitting a PR is not acceptance.
No signing service was installed and no contributor acceptance was fabricated.
The policy does not retroactively establish proprietary rights in past work or
remove community GPL rights or third-party restrictions.

README, developer/release navigation and the approved decision record now link
or describe this policy. The decision record binds the CLA and guide hashes and
explicitly distinguishes the earlier GPL authority confirmation from commercial
relicensing permissions to be obtained from other rights holders. Material checks
reject missing/changed policy documents, and the actual source snapshot includes
CLA.md, CONTRIBUTING.md and the PR template byte-for-byte.

| Check | Actual result |
| --- | --- |
| Root LICENSE SHA-256 | Unchanged: `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986` |
| Root COPYRIGHT SHA-256 | Unchanged: `0341970e78fa91e4da4c154c7de6c231db44cfa5ee82347486b9bc9557165999` |
| CLA.md SHA-256 | `c8856d4695a8cd5388f8277064a8fcd3f1fd55f1cd5a93e763bffe9fb85704c3` |
| CONTRIBUTING.md SHA-256 | `729cb8d75f70f9bc35258c19a21d3771fbf5f2475737be3876e508c672f9a1fa` |
| Local documentation links and new-document whitespace | PASS; 170 file links; `build/phase-1e3-cla/evidence/document-checks-final.json` |
| Full Python tools suite | PASS, 153 tests; `python-tests.log` |
| Focused material tests | PASS, 12 tests, including missing/tampered CLA and contribution guide; `material-tests.log` |
| Direct actual GPL/CLA/guide identity checks | PASS |
| Fresh real collection | Exit 0, REVIEW_REQUIRED; 186 files; `build/phase-1e3-cla/materials/` |
| Source snapshot policy-file binding | PASS; 333 source files, including exact CLA/guide/template bytes; `source-policy-check-final.json` |
| Fresh strict material check | Exit 1; integrityAndCoverage PASS; only the existing GPL engine/runtime corresponding-source gate fails; `check-final.json` |
| `git diff --check` | PASS |

The current contribution-policy material manifest SHA-256 is
`b60a6f4cb4d68bf978b858ba73030fced04de39f0dd8a2f6f95e2394b34349d3`.
Earlier packages keep their recorded hashes and source cuts. Fresh collection
and checking used the existing actual App, full CLI, SDK, verified downloads and
original native probe report, with the same arguments as the GPL follow-up except
`--output build/phase-1e3-cla/materials`. Python was `/opt/homebrew/bin/python3`
3.15.2. No dependency, product version/build, original product byte, hardware,
GUI, signing, or publication work was changed or rerun.

The contribution-policy task is implemented. It does not close the independent
1E.3 engine/runtime corresponding-source gate or establish that any third party
has signed the CLA. Actual agreement acceptance references become available when
this policy's exact bytes are retained at an immutable repository commit.

## Native SDK source closure and pre-review 1E.3 result

This follow-up actually closes the previous engine/runtime source gate. It keeps
all project/CLA decisions and original product bytes intact. The current baseline
is still `master` at `cc99901ab31570fbc62657fc30ef404b0589c9bc`; a fresh
`git merge-base --is-ancestor 34749dcb4c6e46c72af0b78d7a24ee93940ebee3 HEAD`
returned 0. The implementation remains reviewable working-tree changes. Python
is `/opt/homebrew/bin/python3` 3.15.2 (subprocess `sys.executable` resolves to
`/opt/homebrew/opt/python@3.15/bin/python3.15`). Flutter, Dart, product version,
App build, lock, GPL text, COPYRIGHT, CLA and contribution-guide hashes remain
those recorded above.

The new [native source rules and executable instructions](../releases/phase-1e3-sdk-sources.md)
are implemented by `tool/release_sdk_sources.py` and its subordinate JSON source
specification, integrated into the existing `release_materials.py` collect/check
entry point. Source acquisition and checking are not a second product inventory.
No stored PASS flag can replace original archives or fresh coverage.

The real delivery is **`build/phase-1e3-final/materials/`**, with **268 material
files**, **724,870,897 bytes** of material content (about 691 MiB), plus the
manifest. It includes 337 selected first-party source/build/license/policy files,
5,025 Flutter framework/build-source files, 60 pinned SDK/native/LLVM subtree
archives plus the exact engine base archive, required Dart root/commit metadata,
original compiler configuration/provenance, original notices and native source,
and fresh graph/loader/rebuild evidence.

| Current delivery identity | SHA-256 |
| --- | --- |
| `materials-manifest.json` | `5bd448f40d0f305fead05bb776c93535fe30d5574a507d919c2455ecc0c2c0d9` |
| `THIRD_PARTY_NOTICES.md` | `af2d81f4af57be595a5a3d9e5dd34341e087f16cbcae36648aac181da594d18e` |
| Native SDK source specification | `768a83c38c9edb20cca47f7d9f8696e74e722573c03087a50362d0dd3dda2374` |
| Official engine-stamped Dart SDK archive | `d96bf733da6ede46f003524b593a2143c7e1cbb5052eab10ffbe789888e09a1c` |
| Official engine release framework archive | `3b66370c1c6aca9cffcc92b92738b37f08bd6053d121e1caa7270a5b46d4e317` |

The exact engine revision and the installed framework revision have equal
`engine/src` Git tree `63775f6f125fd281ef19073f3ac5e854774f1fbf`.
This was checked from both Git objects, not inferred from adjacent commit dates.
Engine/native source revisions and source URLs are verified against engine DEPS;
standalone Dart sources are separately verified against the exact Dart DEPS.
Their ICU and zlib pins differ and are both supplied. Every supplied original
archive is checked by SHA-256 and reconstructed Git tree, including omitted
optional Gitlinks. Required root files and the authentic Dart commit metadata
are verified as Git objects. Original licenses and nested source declarations
are retained unchanged inside full subtree archives.

The independent official binary downloads match installed SDK members byte for
byte: FlutterMacOS release framework, Dart dartaotruntime, Dart revision and
version. The existing per-section product comparisons separately bind these
SDK inputs to the actual App engine and CLI embedded runtime. CLI's original
SDK runtime SHA-256 is
`4d0a0d55e4f6e9d996aa8c0b0a905406c8731c1d2b46276620b76277aee0f329`.
Thus source identity is not based only on a root license, SDK version label,
automatic App notice or local cached binary.

The native source rules also cover the static C++/compiler runtime selected by
the build tools. Both compiler LLVM revisions have original libcxx, libcxxabi,
libunwind, compiler-rt, CMake, runtimes, llvm/cmake, llvm/include and llvm/utils
inputs. The original compiler package manifests, source provenance, license and
`__config_site` are retained. CLI uses the package's static libc++.a; it is not
silently mapped to engine's separately source-built libcxx revision. Compiler
executables and the full binary reference archives stay in ignored downloads;
these unmodified tools are separate from supplied runtime source.

Every native root was evaluated with the original GN definitions in a fresh
owned scratch output. The checker traversed its actual target dependencies,
checked source/input/script bytes, required generated-input producers, and
verified all evaluated GN build inputs. Fresh GN-created text is recorded
separately with path normalization, so stale output cannot masquerade as original
source and absolute scratch names do not destabilize graph identity.

| Native root | Targets | Original source inputs | Original/generated GN definition inputs |
| --- | ---: | ---: | ---: |
| App engine arm64 | 399 | 7,675 | 407 / 9 |
| App engine x64 | 570 | 7,678 | 376 / 8 |
| CLI AOT runtime arm64 | 42 | 2,089 | 121 / 1 |

Eight obsolete Perfetto header paths and inja's obsolete string_view.hpp entry
are narrowly recorded upstream metadata defects, with actual replacement headers,
original declarations and source include evidence. The checker rejects actual
includes of the obsolete paths. No missing compiled source or generator input
was excused as not applicable. The separate libserialport upstream-tag uncertainty
remains noncritical: its complete locked source/configuration/hook archive and
existing original/modified rebuild receipts are still present and reverified.

The full material check also independently recomputed the two pub production
closures, lock/configuration, actual candidate inventories, native-hook mappings,
fonts/resources, notices and license/CLA authorization. It rehashed the existing
libserialport rebuild and separate App/CLI replacement receipts against the same
candidates. Those native loading observations retain their original local ad hoc
and VM scope; they were not rerun or relabeled as new tests in this follow-up.

Actual commands used the paths below:

```sh
PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH" /opt/homebrew/share/flutter/bin/flutter pub get --enforce-lockfile
/opt/homebrew/bin/python3 tool/release_sdk_sources.py configure-build --workspace build/phase-1e3-source --flutter /opt/homebrew/share/flutter --target app-arm64 --target app-x64 --target cli-arm64
/opt/homebrew/bin/python3 tool/release_materials.py collect --flutter /opt/homebrew/share/flutter --app apps/meshchan_app/build/macos/Build/Products/Release/Meshchan.app --cli build/phase-1e2/cli/bundle --downloads build/phase-1e3/downloads --output build/phase-1e3-final/materials --probe build/phase-1e3/evidence/serial-rebuild.json --sdk-source-workspace build/phase-1e3-source
/opt/homebrew/bin/python3 tool/release_materials.py check --flutter /opt/homebrew/share/flutter --app apps/meshchan_app/build/macos/Build/Products/Release/Meshchan.app --cli build/phase-1e2/cli/bundle --downloads build/phase-1e3/downloads --output build/phase-1e3-final/materials --probe build/phase-1e3/evidence/serial-rebuild.json --sdk-source-workspace build/phase-1e3-source
/opt/homebrew/bin/python3 tool/release_sdk_sources.py prepare --workspace build/phase-1e3-restored --flutter /opt/homebrew/share/flutter --materials build/phase-1e3-final/materials
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
```

The initial source checkout used isolated acquisition/probe work under
`build/phase-1e3-source/`; the independently restored checkout was generated by
the delivered `prepare --materials` entry point. Only the unmodified GN tool and
two official binary reference archives were preseeded from verified downloads
for the restore, using immutable links in that owned directory. All required
corresponding-source archives and compiler configuration members were restored
from the actual delivery. No SDK, pub cache or original candidate was modified.

| Current check | Actual result and evidence |
| --- | --- |
| Locked resolution | Exit 0, lock unchanged; `build/phase-1e3-source/evidence/locked-resolution.log` |
| Real source collection | Exit 0, PASS, 268 files, openGates empty; `build/phase-1e3-final/evidence/collect.log` |
| Strict complete material check | Exit 0, status/integrityAndCoverage/thirdPartyMaterials all PASS, failures empty; `build/phase-1e3-final/evidence/check.log` |
| Independent fresh source restore and native graph check | Exit 0, PASS for all three roots; `build/phase-1e3-final/evidence/restore.log` |
| Restored versus delivered source/graph comparison | All three normalized GN graph hashes and source-input hash maps match; `build/phase-1e3-final/evidence/restore-comparison.json` |
| Native build-tool configuration | Exit 0 for all three persistent release outputs, existing Xcode paths and exact compiler packages; `build/phase-1e3-source/evidence/configure-build.log`, `build-configuration.json` |
| Complete native Ninja dry-run | Exit 0 through final link: arm64 engine 4,138 actions, x64 engine 5,957, CLI runtime 1,127; `build/phase-1e3-source/evidence/ninja-*-dry-run-2.log` |
| Python tools | Exit 0, **160 tests passed**, including seven new SDK source cases; `build/phase-1e3-final/evidence/python-tests.log` |
| Original GPL/CLA/COPYRIGHT/lock identity | Unchanged, verified by current strict check and independent hashes |
| `git diff --check` | Exit 0 |

The restored App configurations additionally evaluated original
`engine/src/build/mac/darwin_sdk.py` during cold SDK discovery (408/377 original
build-definition inputs). That file is already supplied and checked in the
engine archive; there are no changed original definitions. All three resulting
source-input maps and normalized target graphs match the delivered evidence.
No byte-identical compiler output claim follows from this graph comparison.

Preserved development failures are in `build/phase-1e3-source/evidence/`.
An obsolete in-progress check was terminated when implementation inputs changed.
Early GN probes failed after an upstream argument was removed and while generated
GN files were still being treated as original source; the implementation now
preserves upstream arguments and distinguishes fresh generated text. The first
Ninja dry-runs stopped at pending regeneration; explicit GN refreshes preceded
the complete dry-runs recorded above. A sandbox Python suite had 14 failures
because /bin/ps was denied for its synthetic descendants; permission-correct
runs passed (159 before the last new test, then 160). Upstream's sandbox memory
query was denied and selected one concurrent toolchain job; all recorded final
GN commands exited 0. No global security or toolchain setting was changed.

**Pre-review result (superseded below): the old checker reported complete
material acceptance PASS. Its independent candidate input coverage was incomplete;
this result no longer establishes full 1E.3 acceptance.**
The new source/build-input evidence does not claim an engine/runtime compilation
or bit-identical rebuild. Actual engine/runtime compilation, full GUI/IME,
USB/RF, new App content, formal signing, notarization, DMG, installation/upgrade,
minimum OS/Intel acceptance, CI dispatch and publication were not performed.

1E.4 must record fresh compilation inputs and candidate checksums and rerun these
rules. 1E.5 must stage all materials and complete matching source (or equivalent
source access on the same release entry), then rebind actual complete products
and archive layout. 1E.6 must repeat modified-library loading and assess required
installation information under the final signing conditions. Current source and
material hashes are not future DMG checksums. The RC/build identity remains
`0.1.0-rc.1` / `0.1.0-rc.1+6`; public distribution is still subject to those later
product release gates.

## Review correction — historical candidate binding and generated output

All three review findings were reproduced from the existing implementation and
fixed. This supplement supersedes the pre-review full PASS above. The actual
native SDK source and notice coverage remains verified, but **complete historical build-6
candidate material acceptance is REVIEW_REQUIRED**, because the independent
1E.2 compilation record does not cover the complete required input inventory.
The earlier permissive record check was insufficient to establish that gate.

1. `release_materials.py` now derives the required compilation map independently
   from workspace/pubspec/layout inputs. It includes all four members' source,
   CLI entry points, hooks, generation configuration, declared assets/fonts,
   and stable macOS source/project/workspace/scheme/configuration inputs. Empty
   and partial supplied records fail. Additional recorded paths must be safe,
   valid SHA-256 entries and unchanged. The manifest retains both the independently
   required map and the supplied record, rather than validating only supplied rows.
2. `attach_vm()` preserves `appOriginalSha256` and rejects a changed original
   candidate before creating a VM client or rewriting evidence. A shared binding
   check, also run by the material collector, compares the original App with the
   prepared replacement copy. App.framework and resources must be unchanged;
   runner sections must match across the expected local signing transform.
   Only the serial replacement framework and expected outer signing metadata
   are excluded. The VM record must also match the prepared runner's actual hash.
   This rejects both a changed runner and a new Dart payload with the same runner.
3. Repository source inventory explicitly excludes the declared output, download
   and SDK-source workspace trees in collect and fresh check, including non-ignored
   repository destinations. It rejects exclusions that overlap tracked source or
   Git metadata. A real collection/check under `dist/phase-1e3-review/materials`
   verified that generated notices, archives and manifests did not enter
   `sourceInputHashes` or cause independent source drift.

No old build hashes were filled with current file hashes to conceal missing
historical evidence. The current independently required map contains **135
inputs**; the preserved 1E.2 record contains **128**. Its seven missing paths are:

- `apps/meshchan_app/.metadata`
- `apps/meshchan_app/macos/Flutter/Flutter-Debug.xcconfig`
- `apps/meshchan_app/macos/Flutter/Flutter-Release.xcconfig`
- `apps/meshchan_app/macos/Flutter/GeneratedPluginRegistrant.swift`
- `apps/meshchan_app/macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`
- `apps/meshchan_app/macos/Runner.xcworkspace/contents.xcworkspacedata`
- `packages/meshchan_core/build.yaml`

Source, resources and SDK/native hooks have separate coverage, but their current
bytes do not retroactively prove the missing configuration's historical build
values. Closing this gate requires a complete trusted record for the actual
candidate build, or a fresh recorded build with matching candidate checksums and
replacement evidence. Follow the capture-before-build procedure in the updated
release contract and verify all inputs after building. Generating a complete
map now and attaching it to the old binary would not supply that missing proof.

The actual commands used Python `/opt/homebrew/bin/python3` 3.15.2 and the same
Flutter/App/CLI/native-probe inputs as the source supplement:

```sh
/opt/homebrew/bin/python3 -m unittest discover -s tool -p release_materials_test.py -v
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
/opt/homebrew/bin/python3 tool/release_materials.py collect --flutter /opt/homebrew/share/flutter --app apps/meshchan_app/build/macos/Build/Products/Release/Meshchan.app --cli build/phase-1e2/cli/bundle --downloads build/phase-1e3/downloads --output dist/phase-1e3-review/materials --probe build/phase-1e3/evidence/serial-rebuild.json --sdk-source-workspace build/phase-1e3-source
/opt/homebrew/bin/python3 tool/release_materials.py check --flutter /opt/homebrew/share/flutter --app apps/meshchan_app/build/macos/Build/Products/Release/Meshchan.app --cli build/phase-1e2/cli/bundle --downloads build/phase-1e3/downloads --output dist/phase-1e3-review/materials --probe build/phase-1e3/evidence/serial-rebuild.json --sdk-source-workspace build/phase-1e3-source
```

| Review validation | Actual result |
| --- | --- |
| Focused material tests | 18 passed, including six new regression cases for record completeness, added inputs, native/generated scope, generated output, original/prepared App binding and immutable attachment failure/success |
| Full Python tool tests | Exit 0, **166 passed**, including 25 material/SDK-source cases; `build/phase-1e3-review-fixes/evidence/python-tests.log` |
| Real non-ignored collection | Exit 0, REVIEW_REQUIRED, 268 files, one gate listing the seven missing historical inputs; `evidence/collect.log` |
| Real strict check in the same non-ignored output | Exit 1, FAIL; material integrity/independent inventory consistency PASS; exactly the compilation-record completeness gate, no source/output drift; `evidence/check-dist.log` |
| Native SDK source closure | PASS in the new manifest; original archive/tree/DEPS, official runtime origin and all three native GN roots rechecked |
| Existing App replacement binding | PASS: original runner and prepared-copy runner sections match, and all unchanged payload/resources match; no VM/GUI operation was performed |
| Original independent build/probe records | Byte-identical to the preserved records; no candidate identity or original evidence was rewritten |
| `git diff --check` | Exit 0 |

The full suite used normal process-inspection permission for its own synthetic
children. The review's sandbox-only 14 `/bin/ps` failures remain environmental
failures, not passing runs; the new permission-correct 166-test result is in a
separate log. No process-supervision code or global security settings changed.

After the real non-ignored round trip, the owned generated material directory
was moved to **`build/phase-1e3-review-fixes/materials/`** to keep large archives
out of untracked repository output. The manifest SHA-256 remains
`50e96ce9e9469ec1dc46653dc0eedc7dbf554ced8a5381d4e1cd89842b7e3773`.
Every material hash was rechecked after relocation; the repository source map
is identical before and after the move, and includes no `dist/` material entries.
`evidence/relocation-and-binding.json` records those assertions and the remaining
gate. The historical final package is retained unchanged under
`build/phase-1e3-final/`, but its former full PASS is superseded by this review.

The GPL-3.0-only/COPYRIGHT/CLA decisions, product versions, App build, original
App/CLI binaries, lock and original native evidence remain unchanged. No product
rebuild, VM interaction, USB/RF, signing, notarization or release publication was
performed. The review fixes and tests are complete; the missing trusted candidate
build-input evidence remains an explicit, failing gate for the historical binary.
The following supplement closes current acceptance using a new candidate.

## Trusted build-7 candidate evidence and current result

**PASS for the new App build 7 / matching CLI pair.** The previous historical
record gap was closed by a contemporaneously recorded new build, not by hashing
current files and adding their values to an old build record. All historical
products, checksums, compilation records, material packages and native receipts
remain unchanged and keep their original meanings.

The baseline remains local `master`, HEAD
`cc99901ab31570fbc62657fc30ef404b0589c9bc`, containing PR #40. Actual working-tree
inputs are captured by hashes; the old merge commit is not represented as all
current source bytes. License/COPYRIGHT/CLA/contribution-guide/decision bytes
remain unchanged. Host Python is `/opt/homebrew/bin/python3` 3.15.2, subprocess
`/opt/homebrew/opt/python@3.15/bin/python3.15`. The same installed Flutter 3.50.0,
Dart 3.14.0, Xcode 27.2, Apple Clang 21 and macOS SDK 27.2 were used without
upgrading or changing channels/settings.

### Product content and build identity

A preliminary isolated build using source build 6 succeeded, but inspection
showed new automatic notice content. The root workspace package `meshchan` is in
package_config; its newly approved root GNU license is now included in NOTICES.Z.
The decoded notice grew from 1,406,071 to 1,441,312 bytes. That changed App content
must not reuse distributable build 6. The preliminary outputs under
`build/phase-1e3-trusted-build/` are retained only as an unselected trial, with
`evidence/trial-disposition.json`; they are not the current delivery candidate.

The App manifest, source runtime build constant and Version.xcconfig now agree on
**`0.1.0-rc.1+7`**, Apple short `0.1.0`, build string `7`. CLI and the other member
versions/internal constraints stay `0.1.0-rc.1`. Current identity assertions in
the existing CI entry points, source tests and navigation were synchronized;
historical fixtures and validation records retain their build-6 facts. No new
CI release job was added. Storage/schema/wire contracts and product behavior are
unchanged; the App build identity and notice content are the intended changes.

Because root/member license declarations feed automatic resources, they are now
included in compilation input inventory as well. A regression test changes the
root LICENSE while leaving Dart source unchanged and requires binding failure.
The current complete map is **137 inputs**: the prior independent 135-input scope
plus root LICENSE/COPYRIGHT. This includes the seven uncaptured historical
configuration/source paths identified in the review.

### Actual before/build/after chain

The owned one-run driver is
`build/phase-1e3-trusted-build7/evidence/run_build.py`; its exact source and hash
are retained with the build ledger. It records command argv/cwd/start/end/exit
status, tool outputs and log hashes. It preserves complete historical candidate
inventories before starting. Locked resolution and Flutter `--config-only`
preparation preceded the captured build inputs; preparation changed no input
bytes. It then saved the full 137-entry map **before either actual build**.

Actual compilation commands, with the exact absolute argv/cwd also in the ledger:

```sh
# From apps/meshctl, using the existing bundled Dart:
/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart build cli --target bin/meshctl.dart --output /Users/xiaoyu/Documents/my_projects/meshchan/build/phase-1e3-trusted-build7/cli
# From apps/meshchan_app/macos, using the existing Xcode and isolated outputs:
/usr/bin/xcrun xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Release -destination generic/platform=macOS -derivedDataPath /Users/xiaoyu/Documents/my_projects/meshchan/build/phase-1e3-trusted-build7/app-derived OBJROOT=/Users/xiaoyu/Documents/my_projects/meshchan/build/phase-1e3-trusted-build7/app-derived/Build/Intermediates.noindex SYMROOT=/Users/xiaoyu/Documents/my_projects/meshchan/build/phase-1e3-trusted-build7/app-derived/Build/Products COMPILER_INDEX_STORE_ENABLE=NO
```

Both commands exited 0; Xcode reported BUILD SUCCEEDED. Fresh derived products
and intermediates were used without a destructive clean or replacing the old App.
The independently recomputed snapshots after CLI and after App compilation are
identical to the before-build map. Current repository inputs still match that
map after validation. Native hook caches may be reused only under the existing
compatible-input/section/source checks; cache use does not replace actual build
command evidence.

| Trusted build evidence | Identity/result |
| --- | --- |
| Input map | `evidence/compilation-input-hashes.json`, 137 entries; SHA-256 `6fa1acafe3687925b92413c45061ff8e8f1335ccb69653b794f24827e3928331` |
| CLI after snapshot | `evidence/inputs-after-cli.json`, identical map |
| App after snapshot | `evidence/inputs-after-app.json`, identical map |
| Build ledger | `evidence/build-receipt.json`, PASS, all command exits 0, originalCandidatesPreserved true |
| Candidate checksums | `evidence/candidate-checksums.txt`; SHA-256 `8b5500735832e867d31842588b8fcece7999747bac89e981b3379e714d0c08f8` |
| Complete product inventories | `evidence/candidate-inventories.json`, including actual internal framework symlinks |
| Historical product preservation | `evidence/preserved-products-before.json`, independently rechecked against unchanged originals |

The full paths are below `build/phase-1e3-trusted-build7/`. These build records
are newly captured evidence, not replacements for the old 128-entry JSON. The
material entry point now accepts `--build-receipt`; it verifies the actual
before/after files, runner-source hash, successful App/CLI steps, every local log
hash and the receipt's input/checksum/product bindings. It collects the ledger,
three source maps and driver source. Raw local build logs remain outside the
materials directory; the receipt carries their identities and actual argv.
This is a bounded evidence supplement, not the full 1E.4 build pipeline.

### Current actual products

- App: `build/phase-1e3-trusted-build7/app-derived/Build/Products/Release/Meshchan.app`.
- Complete CLI: `build/phase-1e3-trusted-build7/cli/bundle/`.

| Product member | SHA-256 |
| --- | --- |
| App Info.plist | `9c1790ce515afc1cff01a88406c3cfeb21d363af6375fa3888dc392550ecd4a4` |
| App runner | `9af5116db8c48f6e83029c2c2a440d899f26cb54864bccf4dffefcc51ab9d166` |
| App.framework AOT | `4fca58f6463d946e5d984d44ca2348fd4f665d84dff33e4a8f63cde24b1fbfb5` |
| CLI bin/meshctl | `e5d58b792b014abb205ad91f36bbe1ec842582472a0a4f9b25ddd371279f08c7` |
| App NOTICES.Z | `0bd2cff62a1d3a714a48036f88523920666c09ef63d6a18e17a9306829598337` |

Actual plist/source identity and CLI --version passed. App deep/strict/all-arch
signature verification passed under existing local ad hoc conditions. These
hashes identify these exact local candidates, not a future DMG or formal signing.
The newly decoded App notice contains the original root GPL text; project
attribution/third-party supplements remain separately preserved as before.

### Fresh replacement and VM runtime observations

The updated `rebuild_release_serial.py` was actually rerun for this exact pair.
It rebuilt unchanged locked sources, then recompiled the genuine empty-list/marker
modification and substituted the result only in new complete isolated copies.
The original candidates, SDK and pub cache were not patched or re-signed.

| New LGPL evidence | SHA-256/result |
| --- | --- |
| Unchanged-source rebuilt library | `628cc677d665af1c7fbf1224c392d3c80174db401a59c9ee61bf30b27b8eb120` |
| Modified rebuilt library | `bc948a54c3ff04ecf01867f73e06eb289fbb63e4657ec325dd8d9eb9491fb52b` |
| Signed App replacement library, matching guest | `344ef9fea569014f74d97ff36cdd79652a174ca385f35e4b9e8bdc039987dcf8` |
| New CLI product call | Exit 0, empty ports list and exact modification marker |
| New App product call | Device/Refresh produced the marker in the new identity-checked VM fixture |
| Normal modified-App Quit | resourcesReleased/workerExited true, owner released, pendingRequests/receivePorts zero, independent PID absence |

The VM skill/product harness reused the existing authorized executor, private
configuration and strict host-key/VirtualMac UUID/console checks. The explicit
run was `20261117T142817Z-product-99983`, VirtualMac2,1 / macOS 27.2.1, dedicated
`meshchantest` console. The modified App PID was 2896 in its exact owned fixture;
source/prepared runner identity, foreground/focus and argument guards preceded
input. Refresh was safe because the rebuilt function returned before its OS
backend. Neither real enumeration nor a selected port was invoked.

An independent original-App copy then passed bounded write, read and complete
relocation/read operations through that same guest GUI-session executor, using
`meshchan-1d3-sqlite` synthetic data outside the default directory. All three
reports identify compiled `appVersion: 0.1.0-rc.1+7`; resources/worker drained and
each PID was independently absent after normal exit. Reports are in
`evidence/vm-runtime-reports.json`. The executor finished normally, after which
the final VM receipts were attached with the preserved original candidate hash.
No host GUI automation or full IME/navigation matrix was run.

A failed runtime attempt is preserved separately: the initial fixture leaf was
`owned-sqlite`, which the existing runtime guard rejects. It emitted
invalid_arguments before bootstrap; its directory was never created. The
controller's wait expired while that resource-free error window remained open.
After checking its exact owned PID/argv, it was terminated solely for failed-test
cleanup; this is recorded as FAILED_INVALID_ARGUMENTS, not a normal-quit pass.
The corrected attempt used a new owned directory and all three normal exits
above. `failed-runtime-cleanup.json`, the failed log and corrected retry log are
retained. No user data or hardware was accessed during either attempt.

### Recollected material acceptance

The [current contract](../releases/phase-1e3-licenses.md) gives the complete
collect/check commands with the exact new App, CLI, probe, source workspace,
input map, checksums and build-receipt arguments. Actual results:

| Gate | Result |
| --- | --- |
| Locked resolution/configuration | Exit 0, no preparation input byte changes, unchanged lock SHA-256 `e25ed2f37c339206d8587e42e00a0b901bb37874554813840e2025b03bbf847c` |
| New CLI and isolated App builds | Exit 0; complete before/after identity, local signatures and build/version checks passed |
| Python tool suite | Exit 0, **168 passed**; `evidence/tests/python-tools-final.log` |
| App diagnostic-worker version tests | Exit 0, **2 passed**; `evidence/tests/app-diagnostic-version.log`, synthetic transports |
| Original App compiled runtime/persistence/relocation | All three runs PASS, actual build 7, normal close/PID absence |
| New CLI/App modified-library loading | Both PASS under the explicit hardware-free/local signing scope |
| Actual material collection | Exit 0, PASS, **273 files**, openGates empty; `evidence/collect.log` |
| Strict actual material check | Exit 0, PASS, integrityAndCoverage/thirdPartyMaterials PASS, failures empty; `evidence/check.log` |
| `git diff --check` | Exit 0 |

Current material directory: **`build/phase-1e3-trusted-build7/materials/`**.
Collected content is **725,054,646 bytes** (about 691 MiB), plus the manifest.
Manifest SHA-256:
`a6d76df997529d08c4e1ac256a37074eff30f70b17cb945769deda02533c96bf`.
It retains the original App/CLI dependency/notices/source/native/font/runtime
coverage and now carries the actual contemporaneous build ledger/source maps.
Actual native/SDK graphs and package/asset identity were freshly checked; no old
PASS statement was substituted for a new check.

**Current 1E.3 gate is CLOSED for this new build-7 pair.** The seven historical
missing inputs remain missing in the untouched old record, which is not used to
approve these new products. Root notices are explicitly captured for the new
build. GPL-3.0-only, Meshchan Contributors 2026 and the CLA/007pig authority
record remain unchanged. 1E.4 must still establish its sustainable build entry;
1E.5 must stage/rebind actual complete products and source; 1E.6 must repeat
replacement/installation-information checks under formal signing. No Developer
ID, notarization, DMG, installation/upgrade/minimum OS/Intel acceptance, USB/RF,
remote CI dispatch or public release was performed or pre-approved here.
