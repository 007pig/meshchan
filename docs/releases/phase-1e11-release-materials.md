# Phase 1E.11 engineering release handoff

## Build 10 replacement candidate

The revised Build 10 image replaced Build 9 as the 1E.11 review candidate. Its
external review set is retained. Follow-up checks found two host-specific
temporary path residues in both retained Build 10 images. The packaged CLI
Mach-O embeds a `snapshot.aot` path, and `docs/development.md` inside the
first-party source archive contains a macOS temporary-directory prefix.
Publication remains **BLOCKED** and **NOT_PUBLISHED**.

| Identity | Recorded value |
| --- | --- |
| Products | App `0.1.0-rc.1+10` and meshctl `0.1.0-rc.1`, macOS arm64 |
| Apple metadata | `0.1.0`, build `10`, bundle `org.meshchan.meshchan` |
| Frozen compiled source | `be88abba92c47e3814e5bca4b8cc1e8c1efd6ad7` |
| Revised DMG tool snapshot | `fefc67caa5097b12bbb5e60b86fa2a7eefdb9f7a` |
| Image | `Meshchan-0.1.0-rc.1-build10-macos-arm64-local.dmg`, 669,238,209 bytes |
| Image SHA-256 | `4fbb88c824d696e688e8d049db94ba1f408ff03dc7872607a9f115c049bc937a` |
| Signing and image | `local-adhoc` App and CLI, unsigned and unnotarized read-only UDIF/UDZO with HFS+ |
| Public signed-product manifest SHA-256 | `21c5cdf04678cefa29a4ff09c7e80d3dbceb5c8dd86c3fcacab2904447db7228` |
| Original proposed tag and target | `v0.1.0-rc.1` at `be88abba92c47e3814e5bca4b8cc1e8c1efd6ad7` |

The frozen product CI and revised DMG tool CI both passed on attempt 1. The
revised DMG retained all 80 App and CLI inventory entries from the first Build
10 image. The acceptance below applies to the recorded source, tools, and image
bytes. Later code and tool revisions require their own applicable validation.
[Product CI](https://github.com/007pig/meshchan/actions/runs/45014763866),
[DMG tool CI](https://github.com/007pig/meshchan/actions/runs/45044813094)

| Build 10 gate | Recorded outcome |
| --- | --- |
| Frozen build, corresponding source and original package | The strict materials check and independent extracted App and CLI runtime passed. Recipe 56's original build-path check reported PASS for eight Mach-O files. |
| Image integrity and public payload privacy | Local signatures and read-only extraction passed. The original audit reported PASS after checking 693 image inventory entries, 403 first-party source-archive entries, and eight Mach-O files. The later CLI and source-archive path findings supersede the original privacy conclusion for publication. The privacy gate is OPEN. |
| Shipped libserialport replacement | PASS on the maintainer's independent extraction. The re-signed CLI and VM App copies loaded the synthetic replacements and exited. The held tool rejects quarantine attributes on otherwise matching signed inputs. |
| Quarantined download and clean install | PASS for the tested split placement on macOS 27.2.1 (26B131) arm64. Finder copied the App to `~/Applications`. The complete CLI and materials were copied into a separate support directory. Safari download, individual approvals, offline Save, GUI-held CLI exit 69, normal Quit, and independent reopen passed. The co-located layout in the user guide awaits separate verification. |
| Beta CLI-closed data continuity | PASS. The revised App opened the owned fixture, saved a draft and quit. The exact CLI independently verified drafts, profiles, settings and History. |
| Full Beta Finder replacement | BLOCKED. The retained signed Beta App lacked 15 required entries. A complete historical signed App and verified close evidence are still needed. |
| Installed USB Device Check | PASS. The host App completed one selected Heltec V4.3 OLED Check, released the session and port, and quit normally. |
| Finite RF and active Cancel | NOT RUN. Native screenshot evidence could not be saved for the planned sequence. No application-layer RF sends occurred. |
| Durable retention and restoration | PASS. The independently restored DMG matched the selected image SHA-256. |

The ignored `build/phase-1e11/20261122-rc1-build10/public/` review set in the
release workspace retains the image, corresponding documents, inventories,
original `SHA256SUMS`, `release-manifest.json`, and `RELEASE-SHA256SUMS` from
before the follow-up path findings. The private handoff retains the exact
source, receipt and asset pins for that set. The tracked
[user guide](rc1-build10-engineering-guide.md),
[source and license index](rc1-build10-source-materials.md),
[release notes](rc1-build10-release-notes.md), and
[validation summary](rc1-build10-validation-summary.md) incorporate the
follow-up findings. The original staged documents retain their pinned bytes.

### Build 10 handoff to 1E.12

Working-tree recipe 57 review build `review-recipe57-1795369879006` passed
App and CLI product verification, including the path scan across all eight
Mach-O files. The replacement still needs a frozen build and its own exact
image acceptance.

| Replacement gate | Evidence to retain |
| --- | --- |
| Frozen build, materials, package and signing | Capture the exact compiled source, strict materials, independent package check and `local-adhoc` signing receipt. Run CI on the frozen compiled source and DMG tools with their exact attempts. [Build](phase-1e4-build.md#candidate-specific-validation-and-materials), [package](phase-1e5-package.md), [signing](phase-1e6-signing.md#independent-acceptance), [CI](phase-1e8-ci-retention.md#ci-evidence) |
| Image integrity and privacy | Retain the independent image check for the selected DMG hash. Record a passing privacy audit against that check's extraction and pinned inventory. [Privacy audit](phase-1e7-dmg.md#audit-the-independent-public-extraction) |
| Shipped native library replacement | Bind both tests to the exact public signed manifest. Run the local CLI and App procedure on the complete installed copy with its quarantine and normal approvals. Repeat the paired VM experiment from the independently checked engineering extraction. Record both loads and normal App Quit with each procedure's evidence. [Replacement procedure](phase-1e6-user-library-replacement.md#verify-both-replacement-products-for-release-acceptance) |
| Installation and Beta upgrade | Repeat the quarantined clean install using the release guide's exact placement, normal macOS item approvals, offline Save, contention, normal Quit and independent reopen. Verify full Finder replacement of a complete historical Beta App and its closed data. [Install and upgrade](phase-1e9-install-upgrade.md) |
| Installed USB and finite RF | Verify the selected device Check, exact finite round trip with the authorized peer, active Cancel, normal Quit, and resource and process release. |
| Retention and restoration | Seal the selected image, products, corresponding source and exact evidence. Restore independently and compare the image and its material pins. [Retention and restore](phase-1e8-ci-retention.md#check-and-restore-from-the-sealed-object) |

For the guide's co-located layout, use the admitted candidate's
`verify_installation(vm, app, destination, scratch=host_evidence_dir, unified=True)`
on the actual guest installation. Set `destination` to the selected direct
child of the verified guest user's `~/Applications` and `app` to its candidate
folder's `Meshchan.app`. Retain the full inventory, signatures, and quarantine
observations with the separate approval and runtime records.

### Stage and verify the release attachments

Use a fresh attachment directory for the selected replacement. Copy the
original DMG and its `SHA256SUMS` from the image run with status `CREATED`, then
compare the DMG to the independent check's pinned SHA-256. Stage the
matching external documents and derive the material inventory from the
independently checked `image-payload.json`. Record the size and SHA-256 of
each staged file in `release-manifest.json`. Build `RELEASE-SHA256SUMS`
from those files and the completed manifest. Exclude `RELEASE-SHA256SUMS`
itself and record its digest with the manifest digest in the private handoff.

Set the directory, source commit, image SHA-256 and both outer-file SHA-256
pins from the replacement's private handoff. Use the same checks on the
staged and downloaded files.

```sh
MESHCHAN_RELEASE_ASSETS=/absolute/path/to/replacement/review-assets
MESHCHAN_RELEASE_SOURCE=frozen_compiled_source_commit
MESHCHAN_RELEASE_DMG_SHA=accepted_dmg_sha256
MESHCHAN_RELEASE_MANIFEST_SHA=pinned_release_manifest_sha256
MESHCHAN_RELEASE_SUMS_SHA=pinned_release_checksums_sha256
(
  set -eu
  cd "$MESHCHAN_RELEASE_ASSETS"
  for name in release-manifest.json RELEASE-SHA256SUMS; do
    test -f "$name" && test ! -L "$name" || exit 1
  done
  test "$(/usr/bin/shasum -a 256 release-manifest.json | cut -d ' ' -f 1)" = "$MESHCHAN_RELEASE_MANIFEST_SHA"
  test "$(/usr/bin/shasum -a 256 RELEASE-SHA256SUMS | cut -d ' ' -f 1)" = "$MESHCHAN_RELEASE_SUMS_SHA"
  names="$(jq -er '.assets |
    if all(.[]; .name | test("^[A-Za-z0-9][A-Za-z0-9_.-]*$")) then .[].name
    else error("Expected release asset basenames") end' release-manifest.json)"
  expected="$(printf '%s\n' "$names" release-manifest.json RELEASE-SHA256SUMS | LC_ALL=C sort)"
  actual="$(find . -mindepth 1 -maxdepth 1 -print | cut -c 3- | LC_ALL=C sort)"
  test "$actual" = "$expected"
  printf '%s\n' "$names" | while IFS= read -r name; do
    test -f "./$name" && test ! -L "./$name" || exit 1
  done
  /usr/bin/shasum -a 256 -c SHA256SUMS
  /usr/bin/shasum -a 256 -c RELEASE-SHA256SUMS
  test "$(jq -er .candidate.compiledSource release-manifest.json)" = "$MESHCHAN_RELEASE_SOURCE"
  test "$(jq -er .proposedTag.target release-manifest.json)" = "$MESHCHAN_RELEASE_SOURCE"
  test "$(jq -er .candidate.dmgSha256 release-manifest.json)" = "$MESHCHAN_RELEASE_DMG_SHA"
  image="$(jq -er .candidate.dmg release-manifest.json)"
  test "$(/usr/bin/shasum -a 256 "./$image" | cut -d ' ' -f 1)" = "$MESHCHAN_RELEASE_DMG_SHA"
  assets="$(jq -er '.assets[] | [.name, .sizeBytes, .sha256] | @tsv' release-manifest.json)"
  printf '%s\n' "$assets" | while IFS="$(printf '\t')" read -r name size digest; do
    test "$(/usr/bin/stat -f '%z' "./$name")" = "$size"
    test "$(/usr/bin/shasum -a 256 "./$name" | cut -d ' ' -f 1)" = "$digest"
  done
)
```

Before authorized publication, recheck tag availability. Verify the created
tag resolves to the frozen compiled source. Upload the verified manifest
entries, `release-manifest.json` and `RELEASE-SHA256SUMS` unchanged.
Download the actual release assets to a clean directory, run the checks above,
and verify the tag target, image layout and usable corresponding sources.

## Historical Build 9 handoff

| State | Value |
| --- | --- |
| Materials status | **INCOMPLETE** for public distribution. The review copies, original bytes, and asset map are staged. Embedded private provenance and synthetic test logs prevent clearing the proposed image as an upload asset. |
| Publication readiness | **BLOCKED**. The selected image also needs its own exact-source CI, durable retention and recovery, and downloaded first-install and Beta upgrade evidence. |
| Publication state | **NOT_PUBLISHED**. |

### Original candidate

The original 1E.10 candidate selection and admission receipt identify the
same original Build 9 image. PR #49 merged into master on November 22, 2026
as `183f906fa82831c4af2a708c9ad47251b497328e`. Its head and the merge tree
carry the later product changes. The original package receipts, source
archive and hardware acceptance identify the earlier compiled commit.
[PR #49](https://github.com/007pig/meshchan/pull/49)

| Identity | Selected value |
| --- | --- |
| Product | App `0.1.0-rc.1+9`, meshctl `0.1.0-rc.1`, macOS arm64 |
| Apple metadata | `0.1.0`, build `9`, bundle `org.meshchan.meshchan` |
| Frozen compiled source | `01cfacb7fc166a0078962a99d9e673750aabad65` |
| Local signatures and image | `local-adhoc` App and CLI, unsigned and unnotarized read-only UDIF/UDZO with HFS+ |
| Original image | `Meshchan-0.1.0-rc.1-build9-macos-arm64-local.dmg`, 676,240,035 bytes |
| Original image SHA-256 | `49e25d6580486276850177fc51f68093462c26212daa0b12770ed7b6e26d66f2` |
| Original checksum SHA-256 | `83378b0812f2768441c78c191f15afec29acff5624f10817ccd2e8451231e168` |
| Proposed release title | Meshchan 0.1.0-rc.1 Build 9 engineering release |
| Proposed tag and target | `v0.1.0-rc.1` at `01cfacb7fc166a0078962a99d9e673750aabad65` for these bytes only |
| Documentation baseline | Working-tree documents on `183f906fa82831c4af2a708c9ad47251b497328e`. The manifest pins the actual document bytes independently of the compiled source. |

The November 22 read-only GitHub and local checks found no existing tag or
release occupying the proposed slot. Recheck tag and release state before
publication. A replacement candidate requires its own source target and
receipts. Changed distributable App contents require a new increasing build
number.

### Review copy and intended asset names

The [engineering user guide](rc1-engineering-guide.md),
[release notes](rc1-engineering-release-notes.md),
[source and license index](rc1-engineering-source-materials.md), and
[public acceptance summary](../validation/phase-1e10-hardware-acceptance.md)
are the authoritative document sources. The asset copies preserve their
exact bytes and basenames.

The ignored handoff is `build/phase-1e11/20261122-rc1-build9/`. Its `public/`
directory stages external records for review. The original DMG remains in
its 1E.7 output and is held. The manifest describes a **proposed** attachment
set and distinguishes that held asset from the staged records. There is no
approved upload set while the publication status is blocked.

| Name | Purpose |
| --- | --- |
| `Meshchan-0.1.0-rc.1-build9-macos-arm64-local.dmg` | Original candidate bytes at the pinned private mapping |
| `SHA256SUMS` | Original one-image checksum, staged byte-for-byte |
| `rc1-engineering-guide.md` | Install, verify, run, back up, upgrade, and report issues |
| `rc1-engineering-release-notes.md` | Proposed release body and exact scope |
| `rc1-engineering-source-materials.md` | License, corresponding source, rebuild, and replacement entry points |
| `phase-1e10-hardware-acceptance.md` | Public summary of original host evidence and separate historical results |
| `release-materials-inventory.json` | Derived in-image material paths, sizes and hashes |
| `release-manifest.json` | Derived build identity, document revision, leaf assets, and release gates |
| `RELEASE-SHA256SUMS` | SHA-256 for the leaf assets and manifest, excluding itself |

The private `handoff.json` maps every proposed name to its actual file and
pins both outer records. It carries the original selection, signing/DMG pins,
private evidence index and recovery notes. Keep private records outside the
upload set. A public checksum and locally signed code support byte integrity.
The engineering profile uses local ad hoc signing and normal macOS approvals.

### Original publication blockers

| Gate | Current evidence | Closing action |
| --- | --- | --- |
| Public image contents | The original image places host directory structure in inventory/provenance records and includes synthetic replacement logs. The App and CLI also contain build path strings. New external records use a public field allowlist. | Prepare and validate a candidate with a public-safe payload under the existing signing profile. Establish the required treatment of the binary path strings. Changing distributable App bytes requires a higher build number. Changing the image or embedded materials requires new image and material receipts and applicable acceptance. Keep the original image and pins as historical evidence. |
| Source-specific CI | Run `45007478263` passed at `1152097eebd91b13b45d29dbd60cef794d7a5c3d`. No visible Actions run was found at `01cfacb7fc166a0078962a99d9e673750aabad65`. | Obtain the exact compiled-source run, attempt, matching job reports, and pinned artifacts for the candidate going to publication. |
| Durable retention | The original Build 9 outputs and receipts remain readable. The durable engineering archive contains Build 8. Build 9 also used a locally modified DMG and signing probe. | Preserve the exact tool snapshot and close the retention tool's committed-source and CI requirements. Seal the selected image, products, sources/materials and evidence, then verify restoration from the independent seal. |
| Downloaded clean install and Beta upgrade | The Build 9 extracted offline checks and the limited host hardware installation passed. Build 8 separately passed quarantined download, clean install and Beta build 5 upgrade. | Exercise the final selected bytes after an engineering download in the approved arm64 environment. Record actual approvals for App, executable, and libraries as needed. Verify closed Beta fixture continuity, exclusive ownership, normal Quit, and independent reopen. |
| Release and actual downloads | No tag, release or verified public asset exists for this candidate. | After clearing prepublication gates, verify all mapped bytes and names again. Confirm the tag resolves to the actual compiled commit. Bind the release body to the actual assets and upload the approved files unchanged. Download the release assets to a clean directory and run both checksum checks, compare every leaf size and hash to the manifest, and verify the tag, image layout, and usable corresponding sources. |

The [validation record](../validation/phase-1e11-release-materials.md)
documents the rechecks and receipt boundaries. Developer ID Application,
Apple Team, timestamping, notarization, and stapling are deferred under the
active [1E contract](phase-1e-plan.md#current-signing-decision).
