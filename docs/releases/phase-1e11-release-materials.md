# Phase 1E.11 engineering release handoff

| State | Value |
| --- | --- |
| Materials status | **INCOMPLETE** for public distribution. The review copies, original bytes, and asset map are staged. Embedded private provenance and synthetic test logs prevent clearing the proposed image as an upload asset. |
| Publication readiness | **BLOCKED**. The selected image also needs its own exact-source CI, durable retention and recovery, and downloaded first-install and Beta upgrade evidence. |
| Publication state | **NOT_PUBLISHED**. |

## Selected candidate

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

## Review copy and intended asset names

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

## Remaining gates and Step 12

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
