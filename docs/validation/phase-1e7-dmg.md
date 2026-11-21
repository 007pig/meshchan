# Phase 1E.7 engineering DMG validation

The [release contract](../releases/phase-1e-plan.md) selects the
`local-adhoc` profile for the complete macOS arm64 App and CLI. The
[DMG guide](../releases/phase-1e7-dmg.md) describes the unsigned,
unnotarized engineering image and its independent acceptance. The
[1E.6 record](phase-1e6-signing.md#current-engineering-profile) identifies
the original package and the separate local signing evidence.

## Current reviewed candidate and image

The current image uses the independently accepted `local-sign-005`
candidate from the
[current 1E.6 handoff](phase-1e6-signing.md#independent-acceptance-and-1e7-handoff).
The image tool verifies the extracted product signatures while the owned
volume is mounted read-only. It then detaches the volume before native and
AOT checks or product execution. The receipts record the signature and
detach gates separately.

`build/phase-1e7/local-dmg-008/` finished creation at 14:28:35 UTC on
November 21, 2026. The 675,911,154-byte unsigned image uses read-only
UDIF/UDZO with HFS+, volume name `Meshchan 0.1.0-rc.1 build 8`, and Apple
CRC32 `$88EDD0E4`. It contains the complete locally signed App
`0.1.0-rc.1+8` and CLI `0.1.0-rc.1` from recipe 55, commit
`a29430b608658a8b56d619f641dc8600346b6d27`.

| File in `local-dmg-008/` | SHA-256 |
| --- | --- |
| `Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg` | `b42021e054e65e47893d84437100a6b9e51a2ea93eb7a060c12e70fdb4a6ca28` |
| `SHA256SUMS` | `8f26a0821bb39bd1c93d48e57622164fd4b4eaf87d59d9ac80ae503d1023da53` |
| `image-record.json` (`CREATED`) | `8c108e73e60b9d29a879b489cc6312d65f4cfc6440f5046d891a101006a41245` |
| `evidence/image-payload.json` | `5abc9abee4004a9b9a1d3a8bfdb62e2d52893207308478d95f55b795ca8cdf62` |

## Independent acceptance

`build/phase-1e7/local-dmg-check-009/` finished at 14:29:40 UTC with
`PASS`. Creation and independent acceptance both mounted the image
read-only and extracted the same 763-entry payload. The inventory SHA-256
is `ba9bc043e9bdd8d8be4dd1e4fbaf5839a18e956adff97a733d53ba3bca036633`.

Both process ledgers show the signature checks for all eight code items
and 13 architecture slices completed before detach. Independent acceptance
finished its last signature check at 14:29:04.329 UTC and started detach
at 14:29:04.349 UTC. Detach finished at 14:29:07.404 UTC, before the native
dependency and AOT checks or product execution.

CLI PIDs `46944` and `46951` completed offline write and reopen. App PIDs
`56642` and `56747` in guest run `20261121T142918Z-product-56504` mapped
SQLite vnode `16777233:387944` in both runs and passed normal Quit. Host and
guest ran macOS 27.2.1 (26B131) arm64. Final integrity passed. A separate
cleanup audit confirmed both owned mounts, all eight recorded host PIDs,
all five recorded guest PIDs, and the guest executor lock were gone. The SSH
control connection closed.

| File in `local-dmg-check-009/` | SHA-256 |
| --- | --- |
| `dmg-acceptance.json` (`PASS`) | `b88f3f1647fe65e1f549e32d00de555b59dba09da366001c530f67626124b71f` |
| `evidence/static-products.json` | `eb72bc5979f0c125a2f432c7981f0763c5055a9ccbf4e663cbd38a7d6f7ee6e2` |
| `evidence/cli-runtime.json` | `838bad473743bcf9c6e5759fe07c475a7f62ee0908ac7602c527d693fabb7db0` |
| `evidence/vm-app/runtime.json` | `4d22c8782efc764f407f375f9e509a0499b8bc9934071cead4ff89155fcd8657` |
| `evidence/vm-image-binding.json` | `de09e2bbcedbcdd77a6816d36142352e439840b458936f583012311ce8676c7a` |
| `evidence/build-receipt.json` | `b3ece0c0b4ab34782cce045b4512098bbd545440ada1c39bab5e7926340ff3b9` |

## Tests and 1E.8 handoff

All 491 Python tool tests passed on `/opt/homebrew/bin/python3` 3.15.2,
including 35 focused DMG tests. The full log is
`/private/tmp/meshchan-1e7-signature-order-python.3ucGaTgt` with SHA-256
`723e341ed92fb9cd11da8b1aab21d0fb89ca0c8f69d7a67640af22aed6e0f3ca`.
The new fixture asserts that signature verification uses the complete
external copy during the owned mount and that a mismatch still detaches
the volume without accepting the payload.

1E.8 consumes the exact `local-dmg-008` image, `SHA256SUMS`, creation record
and evidence, the `local-dmg-check-009` receipt and evidence, and the
[pinned 1E.6 candidate and acceptance](phase-1e6-signing.md#independent-acceptance-and-1e7-handoff).
Retain the upstream extraction and CLI runtime workspace, the original
1E.6 workspace, and the two DMG workspaces named in the receipts under
`/private/tmp/meshchan-1e7-signature-order-review.EUCqJrjj/`. Replaying
acceptance uses the recorded 1E.6 workspace path and SQLite library device
and inode. Account for them when testing retention and restoration in 1E.8.

To repeat the check, use the original checkout, the recorded source
snapshots, and the connected VM. Choose an unused output name and run the
check when the frozen checkout's build lock is free.

```sh
MESHCHAN_CHECK_PARENT="$(mktemp -d /private/tmp/meshchan-1e7-recheck.XXXXXXXX)"
MESHCHAN_IMAGE_RUN=build/phase-1e7/local-dmg-008
MESHCHAN_LOCAL_RUN=build/phase-1e6/local-sign-005

/opt/homebrew/bin/python3 -B tool/package_dmg.py check \
  --candidate "$MESHCHAN_LOCAL_RUN/signed/Meshchan-0.1.0-rc.1-macos-arm64" \
  --candidate-sha256 58565d17e1c8659f6a73d6164ea37afabee1b75a03c1b20a01615ade467c18d9 \
  --acceptance-receipt "$MESHCHAN_LOCAL_RUN/evidence/check-1nivpup_/signing-receipt.json" \
  --acceptance-sha256 17b203af6191d574d7d77fed472fb04050690aaf87e0b312ef1e02fa6eb474f0 \
  --image "$MESHCHAN_IMAGE_RUN/Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg" \
  --image-sha256 b42021e054e65e47893d84437100a6b9e51a2ea93eb7a060c12e70fdb4a6ca28 \
  --output build/phase-1e7/local-dmg-recheck-010 \
  --workspace-parent "$MESHCHAN_CHECK_PARENT" \
  --vm-config "$HOME/.config/meshchan-vm/config.json"
```

## Prior accepted DMG after mount snapshot review

### Candidate and image after mount snapshot review

That image also used the independently accepted `local-sign-005` candidate.
That DMG tool added a second attachment snapshot after a temporary
`hdiutil info` failure during cleanup and compares device identities
independently of plist row order. The cleanup still requires a current
snapshot and the exact owned process, devices, and mount path before
detaching.

`build/phase-1e7/local-dmg-007/` finished creation at 13:10:15 UTC on
November 21, 2026. The 675,954,855-byte unsigned image uses read-only
UDIF/UDZO with HFS+, volume name `Meshchan 0.1.0-rc.1 build 8`, and Apple
CRC32 `$A55F66F6`. The payload retains the complete locally signed App
`0.1.0-rc.1+8` and CLI `0.1.0-rc.1` from recipe 55, commit
`a29430b608658a8b56d619f641dc8600346b6d27`.

| File in `local-dmg-007/` | SHA-256 |
| --- | --- |
| `Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg` | `b8c18e4280f467a5690392683235bf91bac73645b8b3a2490c4ebb0b73f89747` |
| `SHA256SUMS` | `a96086b342f00cdd06e0389b59005c32311af58cfec15e37389f795382e4f82a` |
| `image-record.json` (`CREATED`) | `8279cd62cbb2f68bf9424c2ff7dc6794976e42a566b8dd3871b719840829b184` |
| `evidence/image-payload.json` | `755f668f72ca5df91510966d8ac2b7c3b95292e35e4c8718672454d10b5f2a05` |

### Independent acceptance after mount snapshot review

`build/phase-1e7/local-dmg-check-008/` finished at 13:11:46 UTC with
`PASS`. Creation and independent acceptance each mounted the image
read-only and extracted the same 763-entry payload. Its inventory SHA-256
is `70555d6d5a428110f9eaea0ffcc03dd2faa6953ebe0ddc893edc9796fb44ffa2`.
The check detached the image before running the products. Static verification
covered all eight code items and 13 architecture slices, native load paths,
AOT, versions, and source correspondence.

CLI PIDs `7529` and `7536` completed offline write and reopen. App PIDs
`55662` and `55769` in guest run `20261121T131127Z-product-55524` mapped
SQLite vnode `16777233:387258` in both runs and passed normal Quit. Host and
guest ran macOS 27.2.1 (26B131) arm64. Final integrity passed. A separate
cleanup audit confirmed that both owned mounts, all eight recorded host
PIDs, the five recorded guest PIDs, and the guest executor lock were gone.
The SSH control connection closed.

| File in `local-dmg-check-008/` | SHA-256 |
| --- | --- |
| `dmg-acceptance.json` (`PASS`) | `c4b5977eb0383b8280884b7f9cc49483ee242d8f962394c6739a76a797f1cc73` |
| `evidence/static-products.json` | `3ed76812682b6e4c7eb83e9fd1f5f57799b896d1e9871ac31a86776ca188ea63` |
| `evidence/cli-runtime.json` | `8039c4209938a28be47d75f650e336255863dc8bc64d60ad5253f324b4f6ef42` |
| `evidence/vm-app/runtime.json` | `e9edb11e9d4c620e8f7925bed6540efda64dd4cdaa5f8376eb18374537058f27` |
| `evidence/vm-image-binding.json` | `9b1aef55df47c282577fdd969d742b97d9c807a36348f2a551c81d9b56005ca6` |
| `evidence/build-receipt.json` | `c3483b1d6fae8c7e8f33214f14c03af78ba5ea1ad62c8ef0c592ada17abc3257` |

### Tests and handoff after mount snapshot review

All 490 Python tool tests passed on `/opt/homebrew/bin/python3` 3.15.2,
including 34 focused DMG tests. The full log is
`/private/tmp/meshchan-1e7-mount-snapshot-python.RVIGZZT1` with SHA-256
`2fd42aeefe050bdb1b8e89ccc93dce819416019c626f46f22aa14c7673ce1328`.
The new fixtures cover transient pre- and post-detach snapshot errors,
reordered plist devices, persistent observation failure, and a changed
disk image process PID. Both extracted copies matched the original signed
candidate, including the bundled replacement tool exercised in the prior
publisher path review below.

The handoff at this cut identified the `local-dmg-007` image, `SHA256SUMS`,
creation record, the `local-dmg-check-008` receipt, associated evidence, and the
[pinned 1E.6 candidate and acceptance](phase-1e6-signing.md#independent-acceptance-and-1e7-handoff).
Retain the upstream extraction and CLI runtime workspace, the original
1E.6 workspace, and the two DMG workspaces named in the receipts under
`/private/tmp/meshchan-1e7-mount-snapshot-review.C6nff22e/`. Replaying
acceptance requires the recorded 1E.6 workspace path and its SQLite
library's device and inode. Account for both when testing 1E.8 retention
and restoration.

To repeat the check for this cut, use the original checkout, the recorded
source snapshots, and the connected VM. Choose an unused output name and
run the check when the frozen checkout's build lock is free.

```sh
MESHCHAN_CHECK_PARENT="$(mktemp -d /private/tmp/meshchan-1e7-recheck.XXXXXXXX)"
MESHCHAN_IMAGE_RUN=build/phase-1e7/local-dmg-007
MESHCHAN_LOCAL_RUN=build/phase-1e6/local-sign-005

/opt/homebrew/bin/python3 -B tool/package_dmg.py check \
  --candidate "$MESHCHAN_LOCAL_RUN/signed/Meshchan-0.1.0-rc.1-macos-arm64" \
  --candidate-sha256 58565d17e1c8659f6a73d6164ea37afabee1b75a03c1b20a01615ade467c18d9 \
  --acceptance-receipt "$MESHCHAN_LOCAL_RUN/evidence/check-1nivpup_/signing-receipt.json" \
  --acceptance-sha256 17b203af6191d574d7d77fed472fb04050690aaf87e0b312ef1e02fa6eb474f0 \
  --image "$MESHCHAN_IMAGE_RUN/Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg" \
  --image-sha256 b8c18e4280f467a5690392683235bf91bac73645b8b3a2490c4ebb0b73f89747 \
  --output build/phase-1e7/local-dmg-recheck-009 \
  --workspace-parent "$MESHCHAN_CHECK_PARENT" \
  --vm-config "$HOME/.config/meshchan-vm/config.json"
```

## Prior accepted DMG after publisher path review

### Candidate and image after publisher path review

That image also used the independently accepted `local-sign-005` candidate.
The bundled replacement tool includes the fix for inaccessible publisher
paths when a consumer chooses a disjoint output directory.

`build/phase-1e7/local-dmg-006/` finished creation at 13:00:03 UTC on
November 21, 2026. The 675,910,677-byte unsigned image uses read-only
UDIF/UDZO with HFS+, volume name `Meshchan 0.1.0-rc.1 build 8`, and
Apple CRC32 `$50B6D7C5`. The payload contains App `0.1.0-rc.1+8` and CLI
`0.1.0-rc.1` from recipe 55, commit
`a29430b608658a8b56d619f641dc8600346b6d27`. The complete App and CLI
retain their `local-adhoc` signatures.

| File in `local-dmg-006/` | SHA-256 |
| --- | --- |
| `Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg` | `de30cd268df7756f5cf75105bbe53bca40b45d538a4e28531fa74fc0ac6744bc` |
| `SHA256SUMS` | `f38896401a063b47f8c581933321166c32a53bf6c98253ce93f2442e78d73a9f` |
| `image-record.json` (`CREATED`) | `371275cf9b47ff75979caddec8abe5b4c820c3a2f9258c0900e19b5b32c0c497` |
| `evidence/image-payload.json` | `8095daa288896fb2f8a846f787bf9b606934da3207c9e0a0e5604a2a5de6c76d` |

### Independent acceptance after publisher path review

`build/phase-1e7/local-dmg-check-007/` finished at 13:02:47 UTC with
`PASS`. Creation and independent acceptance each mounted the image read-only
and extracted the same 763-entry payload with inventory SHA-256
`466765446afe1f00712adf4a753df2b46b0de5b5139a2bb0f0c5d7db8ed51bbd`.
The check detached the image before running the products. Static verification
covered all eight code items and 13 architecture slices, native load paths,
AOT, versions, and source correspondence.

CLI PIDs `98023` and `98029` completed offline write and reopen. App PIDs
`55175` and `55275` in guest run `20261121T130223Z-product-55034` mapped
SQLite vnode `16777233:387051` in both runs and passed normal Quit. The
host and guest used macOS 27.2.1 (26B131) arm64. Final integrity passed.
A separate cleanup audit confirmed that all three owned mounts, recorded
host and guest process IDs, and the guest executor lock were gone.
The SSH control connection closed.

The first check, `local-dmg-check-006`, detached successfully and stopped
before runtime because a concurrent verification held the frozen checkout's
build lock. Its `FAIL` receipt has SHA-256
`4f5e8211856271f1a6cf0b1637b9aff5db4952be51a20bf3806b2c646c7e4330`.
The successful retry used a new output directory and the same image bytes.

| File in `local-dmg-check-007/` | SHA-256 |
| --- | --- |
| `dmg-acceptance.json` (`PASS`) | `a6daa5fa9e14dbc0f003dee51b3fca2a660071a1cc7c3cddb2d3f0ad7e27178c` |
| `evidence/static-products.json` | `ae469f6a3f0ff123b3fc5dd7ee04af1fc7643a9d9139895beedae04b66c1a1ad` |
| `evidence/cli-runtime.json` | `27dd828779eb268969f337988ae87f5ce872603f0c90b183640c0597af8869b3` |
| `evidence/vm-app/runtime.json` | `b5c9f7f2787721bbab81ec066470e5576caf29c7107bb323842a3ab6bf730b33` |
| `evidence/vm-image-binding.json` | `aa89f2795026efdd17edaf3b8736277faf056b72bb9c9edfc051ab10a509c173` |
| `evidence/build-receipt.json` | `40c88a51f980a1ecc03421db6209f08e2a8734a6a1db2148e64978d54569f195` |

### Tests and handoff after publisher path review

All 486 Python tool tests passed on `/opt/homebrew/bin/python3` 3.15.2,
including 30 DMG tests and the new unprivileged replacement regression. The
full log is `/private/tmp/meshchan-1e7-publisher-path-review-python-tests.log`
with SHA-256
`97c4185d9bfb2994a83f86ac8a95b4edd15f9bb5934e3c917cbc2b98e4f9a5e1`.
The replacement tool bundled in the extracted image passed its CLI and final
integrity checks and returned the documented CLI-only `INCOMPLETE` status
and exit 1. Its receipt is in
`/private/tmp/meshchan-1e7-bundle-publisher-review.fZb8hNsX/replacement run/evidence/`
with SHA-256
`2403b3b2ab07b5a429666b1397502ad238217196fb79231cffd27b6722f6f94e`.

The handoff at this cut identified the `local-dmg-006` image, `SHA256SUMS`,
creation record and evidence, the `local-dmg-check-007` receipt and evidence,
and the
[pinned 1E.6 candidate and acceptance](phase-1e6-signing.md#independent-acceptance-and-1e7-handoff).
Retain the original upstream extraction and CLI runtime workspace, the
1E.6 workspace, and the DMG workspaces named in the receipts under
`/private/tmp/meshchan-1e7-publisher-review.17QbmK6A/`. Replaying acceptance
uses the recorded 1E.6 workspace path and its SQLite library's device and
inode. A copy can change those values. Account for them when testing retention
and restoration in 1E.8.

To repeat the check for this cut, use the original checkout, the recorded
source snapshots, and the connected VM. Choose an unused output name and
run the check when the frozen checkout's build lock is free.

```sh
MESHCHAN_CHECK_PARENT="$(mktemp -d /private/tmp/meshchan-1e7-recheck.XXXXXXXX)"
MESHCHAN_IMAGE_RUN=build/phase-1e7/local-dmg-006
MESHCHAN_LOCAL_RUN=build/phase-1e6/local-sign-005

/opt/homebrew/bin/python3 -B tool/package_dmg.py check \
  --candidate "$MESHCHAN_LOCAL_RUN/signed/Meshchan-0.1.0-rc.1-macos-arm64" \
  --candidate-sha256 58565d17e1c8659f6a73d6164ea37afabee1b75a03c1b20a01615ade467c18d9 \
  --acceptance-receipt "$MESHCHAN_LOCAL_RUN/evidence/check-1nivpup_/signing-receipt.json" \
  --acceptance-sha256 17b203af6191d574d7d77fed472fb04050690aaf87e0b312ef1e02fa6eb474f0 \
  --image "$MESHCHAN_IMAGE_RUN/Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg" \
  --image-sha256 de30cd268df7756f5cf75105bbe53bca40b45d538a4e28531fa74fc0ac6744bc \
  --output build/phase-1e7/local-dmg-recheck-008 \
  --workspace-parent "$MESHCHAN_CHECK_PARENT" \
  --vm-config "$HOME/.config/meshchan-vm/config.json"
```

## Prior accepted DMG after isolation review

### Candidate and image after isolation review

That image used the independently accepted `local-sign-004`
candidate from the
[prior 1E.6 handoff](phase-1e6-signing.md#prior-local-acceptance-after-isolation-review).
The review isolated temporary files in owned workspaces and moved the native
detach command's working directory outside the output. A real small image
fixture confirmed the native detach still succeeds after the output directory
is moved. The fixture retained failure status when it could not publish its
cleanup evidence.

`build/phase-1e7/local-dmg-005/` finished creation at 12:44:52 UTC on
November 21, 2026. The 675,906,534-byte unsigned image uses read-only
UDIF/UDZO with HFS+, volume name `Meshchan 0.1.0-rc.1 build 8`, and matching
Apple CRC32 `$A242F00E`. The payload contains App `0.1.0-rc.1+8` and CLI
`0.1.0-rc.1` from recipe 55, commit
`a29430b608658a8b56d619f641dc8600346b6d27`.

| File in `local-dmg-005/` | SHA-256 |
| --- | --- |
| `Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg` | `fe844e4c03b75356f70b15ff8018e9bb39921973dbf4d3de082fcdf8a2c4b061` |
| `SHA256SUMS` | `f7da2033dae9c70bfe1e9812a087a224c6cd5aacc45a148342e7c2b4e9982e55` |
| `image-record.json` (`CREATED`) | `dc3e855b69f3cbb46d23ceb65521a47a4265482bcd02428de3edfd01639602e6` |
| `evidence/image-payload.json` | `1284e60e2fe21ce91c612303403340a91895f81719fb9a07bab8d8d9b1821c2d` |

### Independent acceptance after isolation review

`build/phase-1e7/local-dmg-check-005/` finished at 12:46:10 UTC with
`PASS`. Both runs verified the read-only volume and complete extraction,
with the same 763-entry inventory SHA-256
`eca2db6924143b648ff3ad833eba1333d48ba5f60c55f64e449824ffbb2881bf`.
The image detached before either extracted product ran. Static checks
covered all eight code items and 13 architecture slices, native load paths,
AOT, versions, and source correspondence.

CLI PIDs `81670` and `81683` completed offline write and reopen. App PIDs
`53663` and `53760` in guest run `20261121T124550Z-product-53523` mapped
SQLite vnode `16777233:386292` in both runs and passed normal Quit. The host
and guest used macOS 27.2.1 (26B131) arm64. The final audit confirmed the
absence of owned mounts and their helpers, the host and guest product and
observer PIDs, and the guest executor lock. The SSH connection closed.

| File in `local-dmg-check-005/` | SHA-256 |
| --- | --- |
| `dmg-acceptance.json` (`PASS`) | `3bc0c901e7ed7130b91a07ccbaf602f6bdf89287b6c0a76665d915c8aacff3f0` |
| `evidence/static-products.json` | `5c0646b0d5bd514848f122f2863dbe1baf394ac2256a41a6f19a438304c55d44` |
| `evidence/cli-runtime.json` | `c549ed11c9f595b0b6587d763e7085da9f1647712df57d1d21ab3fb7b1e68dc5` |
| `evidence/vm-app/runtime.json` | `dc170db497406bddfdb783bbde7c48f424dbe1eae99092a7138b2cf873e10d65` |
| `evidence/vm-image-binding.json` | `4ee4f43398f05370fa17517891dcc760a92fc7e571df03713217f619ad441011` |
| `evidence/build-receipt.json` | `9ff2cb6663347efd85bed18a07eb717e5ff154420a2b64e383b1b654e77722de` |

### Tests and handoff after isolation review

All 485 Python tool tests passed on `/opt/homebrew/bin/python3` 3.15.2,
including 30 DMG tests. The full log is
`/private/tmp/meshchan-1e7-isolation-review-python-tests.log` with SHA-256
`d58906086ed26507138ab2eb9d62e910722389c4751ee2f11a3ff6522ba938fb`.
The bundled replacement tool from the image's extraction passed its CLI
and final integrity checks and returned the documented CLI-only
`INCOMPLETE` status and exit 1. The replacement receipt in
`/private/tmp/meshchan-1e7-bundle-isolation-review.zZjpGJwG/replacement run/evidence/`
has SHA-256 `33bd34010d953af5e30a5de998847a2336996115032a87f52c878dfb6119e86c`.

The handoff at this cut identified the `local-dmg-005` image, checksum and
creation record, the `local-dmg-check-005` receipt and evidence, and the
[pinned 1E.6 candidate and acceptance](phase-1e6-signing.md#prior-local-acceptance-after-isolation-review).
Retain the workspaces linked by the receipts, including the original
upstream extraction and CLI runtime workspace and both DMG workspaces
under `/private/tmp/meshchan-1e7-isolation-review.RAiKHEGK/`. Repeat
verification uses the recorded 1E.6 workspace path and its SQLite
library's device and inode. A regular copy can change those values.
1E.8 must account for this dependency when testing retention and restoration.

To repeat the check for this cut, use the original checkout, the recorded
source snapshots and the configured VM. Choose an unused output name.

```sh
MESHCHAN_CHECK_PARENT="$(mktemp -d /private/tmp/meshchan-1e7-recheck.XXXXXXXX)"
MESHCHAN_IMAGE_RUN=build/phase-1e7/local-dmg-005
MESHCHAN_LOCAL_RUN=build/phase-1e6/local-sign-004

/opt/homebrew/bin/python3 -B tool/package_dmg.py check \
  --candidate "$MESHCHAN_LOCAL_RUN/signed/Meshchan-0.1.0-rc.1-macos-arm64" \
  --candidate-sha256 41505574cb49596c1a0d26c61ddbf1838a9ee631d73791a67b84fc659f380a11 \
  --acceptance-receipt "$MESHCHAN_LOCAL_RUN/evidence/check-vb6jvzuh/signing-receipt.json" \
  --acceptance-sha256 0a688d7a0ca1d505a97fbc472d9b9a88cd713f6010e2a5be2533e0b356ee5d7c \
  --image "$MESHCHAN_IMAGE_RUN/Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg" \
  --image-sha256 fe844e4c03b75356f70b15ff8018e9bb39921973dbf4d3de082fcdf8a2c4b061 \
  --output build/phase-1e7/local-dmg-recheck-006 \
  --workspace-parent "$MESHCHAN_CHECK_PARENT" \
  --vm-config "$HOME/.config/meshchan-vm/config.json"
```

## Prior accepted DMG after evidence review

### Candidate and image at that cut

This image used the independently accepted `local-sign-003` candidate
from the [prior 1E.6 handoff](phase-1e6-signing.md#prior-local-acceptance-after-evidence-review).
The review bound the upstream verification to the selected extraction and
its process evidence, protected the frozen checkout from replacement writes,
and kept native detach independent of evidence writes. The signed product
still contains App `0.1.0-rc.1+8` and CLI `0.1.0-rc.1` from recipe 55,
commit `a29430b608658a8b56d619f641dc8600346b6d27`.

The creation run in `build/phase-1e7/local-dmg-004/` finished at 12:30:30 UTC
on November 21, 2026. It produced a 676,001,920-byte unsigned, read-only
UDIF/UDZO HFS+ image named `Meshchan 0.1.0-rc.1 build 8` with CRC32
`$E6CFFDAD`. The outer manifest records 51 DMG tool inputs and 47 signing
inputs, separately from the original engineering package and frozen build.

| File in `local-dmg-004/` | SHA-256 |
| --- | --- |
| `Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg` | `1dab502eea520eade134261ecf75f4dc983d6b21734860e93c234edf8a64149c` |
| `SHA256SUMS` | `740680c3d15004ed7006bd8ab302b0ae0574855e81eb5f223415a7659ab00b9c` |
| `image-record.json` (`CREATED`) | `033421811232767d15f1f438dfd50762ff10376ac606714c8a71269c1e8d91ef` |
| `evidence/image-payload.json` | `e0ab7c5081ba252be847146a1209992240299b8793fcc02baa8c632a0e950914` |

### Independent acceptance at that cut

`build/phase-1e7/local-dmg-check-004/` finished at 12:32:03 UTC with
`PASS`. The verifier matched the external SHA-256 and Apple structural
checksum, mounted the volume read-only, and verified 763 volume entries
including its complete 694-entry candidate. Creation and independent
acceptance agreed on the payload inventory SHA-256
`6ad24245bb829422f2c25298d90f727545ad304dbe7de7e3d773cdefcf4e19ea`.

The native detach completed and was recorded before running the extracted
products. The verifier checked all eight code items and 13 architecture
slices, native load paths, AOT, and version and source correspondence.
CLI PIDs `63755` and `63763` wrote and reopened an offline SQLite draft.
App PIDs `52167` and `52273` did the same in guest run
`20261121T123137Z-product-52011` and passed normal Quit. Host and guest
used macOS 27.2.1 (26B131) arm64. The final audit confirmed absence of both
owned mounts and DiskImages helpers, absence of the host and guest runtime
and observer PIDs, and release of the guest executor lock. The task SSH
connection was closed. The final `shasum -a 256 -c SHA256SUMS` returned
`OK`.

| File in `local-dmg-check-004/` | SHA-256 |
| --- | --- |
| `dmg-acceptance.json` (`PASS`) | `77403c668896aa408a896c5b44a0d79d65fe39acc357d7e11de28304c9473786` |
| `evidence/static-products.json` | `42126cf1f6b1ac31c51a2e053b503c49e6c2fe29d6bca6daa4802e5f82fee62a` |
| `evidence/cli-runtime.json` | `9a18d3db4dd042839916bcfbb358c56070eb246054f13f7089af875895d784f3` |
| `evidence/vm-app/runtime.json` | `755b6e1aa15b3821ffd961369a56c727a6ff25d5af73e4cba145df92d1b45109` |
| `evidence/vm-image-binding.json` | `e390df5b783153ca315338770e60060f90d9f132947a2a2ac67b6d11cadabc63` |
| `evidence/build-receipt.json` | `a626788afb7b236914eb9f1a8f1cd4ae462bead4d1286303d2d2edfab6641a14` |

### Tests and handoff at that cut

The full **481-test** Python tool suite passed on `/opt/homebrew/bin/python3`
3.15.2, including 28 DMG tests. The real small HFS+ fixture confirmed
read-only mount, exact-path detach, permission preservation, and helper exit.
Focused runs also covered cross-run evidence and replacement output isolation
under the [review validation workflow](../testing.md#review-fixes-and-pre-pr-validation).
The full test log is
`/private/tmp/meshchan-1e7-evidence-review-python-tests.log` with SHA-256
`2ff92754a0d92fe3662765f5b1cddfdce282ae62b2076ca79db4690520dd03ba`.

The extracted image's bundled replacement tool also passed the standalone
CLI and final integrity checks. With no guest configuration it returned
the documented `INCOMPLETE` status and exit 1. Its receipt is
`replacement run/evidence/replacement-receipt.json` under
`/private/tmp/meshchan-1e7-bundle-evidence-review.pnDg0EBg/` with SHA-256
`a7acbd929097c57d91a0e52f9c373616bc091c56fd94fc94e21a8fc3a5c7958a`.

The prior handoff identified the exact `local-dmg-004` image, checksum and creation record,
the `local-dmg-check-004` receipt and evidence, and the
[then-pinned 1E.6 candidate and acceptance](phase-1e6-signing.md#prior-local-acceptance-after-evidence-review).
Preserve the workspaces linked by those receipts, including the original
upstream extraction and CLI runtime workspace, and both DMG workspaces
under `/private/tmp/meshchan-1e7-evidence-review.UQizE0kY/`.
Repeat verification uses the recorded 1E.6 workspace path and the retained
SQLite library's device and inode. A regular copy can change those values.
1E.8 must account for this dependency when testing retention and restoration.

To repeat that historical check, use the original checkout with the recorded source
snapshots and configured VM. Use an unused output name and fresh workspace.

```sh
MESHCHAN_CHECK_PARENT="$(mktemp -d /private/tmp/meshchan-1e7-recheck.XXXXXXXX)"
MESHCHAN_IMAGE_RUN=build/phase-1e7/local-dmg-004
MESHCHAN_LOCAL_RUN=build/phase-1e6/local-sign-003

/opt/homebrew/bin/python3 -B tool/package_dmg.py check \
  --candidate "$MESHCHAN_LOCAL_RUN/signed/Meshchan-0.1.0-rc.1-macos-arm64" \
  --candidate-sha256 e6f74bdba940dfcc87a9969e4ef01302ed56350c7923adaaf4e7bf34f2961e7e \
  --acceptance-receipt "$MESHCHAN_LOCAL_RUN/evidence/check-li3f96k0/signing-receipt.json" \
  --acceptance-sha256 8f636f7368f46eb6652edf93413698bebd6aacdbf2b0b1cbf67f8a5e4e1d7601 \
  --image "$MESHCHAN_IMAGE_RUN/Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg" \
  --image-sha256 1dab502eea520eade134261ecf75f4dc983d6b21734860e93c234edf8a64149c \
  --output build/phase-1e7/local-dmg-recheck-005 \
  --workspace-parent "$MESHCHAN_CHECK_PARENT" \
  --vm-config "$HOME/.config/meshchan-vm/config.json"
```

## Prior accepted DMG after initial tool review

The following evidence belongs to the prior source snapshot.

### Prior reviewed candidate and image

Follow-up review tightened the binding between runtime receipts and their
process evidence, host App architecture checks, VM output and runtime path
isolation, and DMG attach and detach ownership. A new candidate and image
were generated because the corresponding tool sources are part of the
sealed payloads. The earlier accepted image and receipts are retained
below under their original source snapshot.

The reviewed image uses the accepted `local-sign-002` candidate from the
[then-selected 1E.6 handoff](phase-1e6-signing.md#prior-local-acceptance-after-initial-tool-review).
It still contains App `0.1.0-rc.1+8` and CLI `0.1.0-rc.1` from frozen
recipe 55, commit `a29430b608658a8b56d619f641dc8600346b6d27`. The candidate
manifest SHA-256 is
`89caa167ba7465c1415344da9df667d148e7095c2fc2a8efe9ea5e3c2b2b1cbd`. Its
independent acceptance receipt SHA-256 is
`6ca8f1e1342a3d34c108d21bc0cc47dadf489e69eec41df1268ad7b01d65bdec`.

`build/phase-1e7/local-dmg-003/` completed creation at 12:14:38 UTC on
November 21, 2026. The 675,932,327-byte image uses read-only UDIF/UDZO
with HFS+, volume name `Meshchan 0.1.0-rc.1 build 8`, and matching Apple
CRC32 `$4301C9ED`. Its container is unsigned. The outer manifest records
51 DMG tool inputs and identifies the separately pinned upstream and
signing sources.

| File in `local-dmg-003/` | SHA-256 |
| --- | --- |
| `Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg` | `4e5c4beade788b9feff32e76c187a14a9e4a794dea5fd8d1e4b8f2ebe33fc8cf` |
| `SHA256SUMS` | `9dbe21eb3613f0cc81fc1e5869aacc0fab8c4491652e8a2806263076f0a30b90` |
| `image-record.json` (`CREATED`) | `384a9405293d2a68e3ebce8d17380d3e5d0b5a1fe14f8f9f004bf898f8078293` |
| `evidence/image-payload.json` | `a07a1f3a84bc6b2cd7b24d731233081585480bac1928682bc3e225e950eaf130` |

### Prior independent acceptance

`build/phase-1e7/local-dmg-check-003/` finished at 12:16:05 UTC with
`PASS`. It verified the external image pin and Apple checksum, mounted the
image read-only, matched all 763 volume entries, and extracted the complete
694-entry candidate. Both runs observed exact file bytes, modes, and raw
links, with no unexpected volume entries. Creation and acceptance produced
inventory SHA-256
`e1ef9b550305efe89cb6987cec9b185b9f4bad7a59a894e9ab5526d9265e7cff`.

The verifier detached by the owned mount path before executing the extracted
products. It checked all eight code items and 13 architecture slices, the
native loader graph, AOT, source correspondence, and versions. CLI PIDs
`46576` and `46584` passed offline SQLite write and reopen with bound
process evidence. App PIDs `50572` and `50672` in guest run
`20261121T121538Z-product-50432` passed the offline write, reopen, and normal
Quit checks. The host and guest used macOS 27.2.1 (26B131) arm64.

Final verification reread the original package, candidate, evidence,
extracted payload, and image. A separate audit confirmed both owned mount
paths and DiskImages helpers were gone, the host and guest product and
observer PIDs were absent, and the guest executor lock was clear. The task
SSH connection closed. The post-acceptance `shasum -a 256 -c SHA256SUMS`
reported `OK`.

| File in `local-dmg-check-003/` | SHA-256 |
| --- | --- |
| `dmg-acceptance.json` (`PASS`) | `9c7a32247ae1a3b2ee74471cefb0ac6d129b3853d24a54f908d61a6623d43dfd` |
| `evidence/static-products.json` | `31948d22ecefbaf5eac4e9cacb3bea8b4284e64d6121fd3101969b11fb074c3f` |
| `evidence/cli-runtime.json` | `704d93e155484441e9aecae0b4ce97ccf337292b748f090786ed98546f2c4719` |
| `evidence/vm-app/runtime.json` | `125bc141150cb20b71005d924f4635da2ee583a0c9e9ba0a5ef686ae91d4fd77` |
| `evidence/vm-image-binding.json` | `5030d576eaaf48ddaf883c644c0de873ead712b737935de8a39a2b195e684143` |
| `evidence/build-receipt.json` | `e9bd70ce84cc339e60a5e5f013c53ea5efba2113aa9d48402deb58e7521eb532` |

### Prior tests and handoff

The reviewed tools passed 23 focused DMG tests and the full 474-test Python
tool suite with `/opt/homebrew/bin/python3` 3.15.2. An owned real HFS+ fixture
verified raw links, modes, read-only attachment, and normal detach by mount
path. The full-suite log is `/private/tmp/meshchan-1e7-review-python-tests.log`
with SHA-256
`b85ca81fbd42c4bf01ba12277e860d7fda177c676d01d8d683fe99e63a7eba67`.

The CLI-only user replacement command also ran directly from the reviewed
DMG's extracted `signing-source/`. It rebuilt and loaded the synthetic
library, passed CLI and final integrity, and returned the documented
`INCOMPLETE` status and exit 1 without a guest configuration. Its retained
receipt is `replacement run/evidence/replacement-receipt.json` under
`/private/tmp/meshchan-bundled-review-final.iHQGBfje/` with SHA-256
`9dbadfb91907c0e706c9ca7c779534ed5b8ed223034129353fc07abec2cabbb9`.

This earlier handoff identified the exact image, checksum, and creation receipt from
`local-dmg-003`, the independent receipt and evidence from
`local-dmg-check-003`, and the pinned `local-sign-002` candidate and
its acceptance. Preserve the receipt-linked workspace trees under
`/private/tmp/meshchan-1e7-review.X5Y8IqC3/` and the
[prior 1E.6 runtime workspace](phase-1e6-signing.md#prior-local-acceptance-after-initial-tool-review).
The extracted candidate includes the corresponding source, license,
and rebuild and replacement materials. Download quarantine and system
approval, installation, Beta upgrade, minimum support, USB/RF, and
publication retain their separate [release gates](../releases/phase-1e-plan.md#remaining-steps-and-handoff).

To repeat that historical check, use the original checkout and the source bytes
and modes recorded in both tool snapshots and the configured VM. Keep the
original receipt-linked 1E.6 workspace at its recorded path. The repeat
check compares the observed SQLite device and inode with that retained
library. A regular copy can change those values. 1E.8 must account for
this dependency when testing retention and restoration. Use an unused
output name and a fresh external workspace parent.

```sh
MESHCHAN_CHECK_PARENT="$(mktemp -d /private/tmp/meshchan-1e7-recheck.XXXXXXXX)"
MESHCHAN_IMAGE_RUN=build/phase-1e7/local-dmg-003
MESHCHAN_LOCAL_RUN=build/phase-1e6/local-sign-002

/opt/homebrew/bin/python3 -B tool/package_dmg.py check \
  --candidate "$MESHCHAN_LOCAL_RUN/signed/Meshchan-0.1.0-rc.1-macos-arm64" \
  --candidate-sha256 89caa167ba7465c1415344da9df667d148e7095c2fc2a8efe9ea5e3c2b2b1cbd \
  --acceptance-receipt "$MESHCHAN_LOCAL_RUN/evidence/check-2qhsultx/signing-receipt.json" \
  --acceptance-sha256 6ca8f1e1342a3d34c108d21bc0cc47dadf489e69eec41df1268ad7b01d65bdec \
  --image "$MESHCHAN_IMAGE_RUN/Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg" \
  --image-sha256 4e5c4beade788b9feff32e76c187a14a9e4a794dea5fd8d1e4b8f2ebe33fc8cf \
  --output build/phase-1e7/local-dmg-recheck-004 \
  --workspace-parent "$MESHCHAN_CHECK_PARENT" \
  --vm-config "$HOME/.config/meshchan-vm/config.json"
```

## Initial accepted DMG before tool review

### Accepted inputs at that cut

The compiled product uses recipe 55 at
`a29430b608658a8b56d619f641dc8600346b6d27`. The packaging tools verified the
accepted engineering package in `build/phase-1e5/run-002/` and its full
upstream check. They separately recorded the original package tool inputs,
the 47 local signing inputs, and the 51 DMG tool inputs. The latter two
sets were inventoried in the checkout based on
`e36690be02d7a213a6ab391c6f6b903d247e1521`.

| Input | Path relative to the checkout | SHA-256 |
| --- | --- | --- |
| Sealed candidate manifest | `build/phase-1e6/local-sign-001/signed/Meshchan-0.1.0-rc.1-macos-arm64/signed-product-info.json` | `5241033d916d87a32928afdb6ee7659f7bd1da7ef97d4ea97d6c622bd5cc851d` |
| Independent local acceptance | `build/phase-1e6/local-sign-001/evidence/check-wa4rw1l1/signing-receipt.json` | `755a95c341bf68580c829d26ecf2609f008d001ea648951b8b0ab9ca9823c7bf` |

The App is `0.1.0-rc.1+8`, Apple short version/build `0.1.0`/`8`,
Bundle ID `org.meshchan.meshchan`. The CLI is `0.1.0-rc.1`. The host and
guest run macOS 27.2.1 (26B131) arm64. Commands used
`/opt/homebrew/bin/python3` 3.15.2, resolved to
`/opt/homebrew/Cellar/python@3.15/3.15.2/Frameworks/Python.framework/Versions/3.15/bin/python3.15`.
The creation and acceptance ledgers include the Apple tool paths,
executed arguments, exit results, and log digests.

### Corrected image at that cut

The second creation run is `build/phase-1e7/local-dmg-002/`.
It completed at 11:54:01 UTC on November 21, 2026, from the same pinned
local candidate. The image carries the corrected DMG tooling. It is
675,872,090 bytes, unsigned, and unnotarized. Its UDIF/UDZO volume uses
HFS+ and is named `Meshchan 0.1.0-rc.1 build 8`. The structural checksum
was `$98557A53` (CRC32). Running `shasum -a 256 -c SHA256SUMS` in
the creation run reported `OK`.

| File in the creation run | SHA-256 |
| --- | --- |
| `Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg` | `9fb048fd5a4eafb89fa69bc31f16207231b561c404574e21276e6d18d82aa7bb` |
| `SHA256SUMS` | `98344f3fe5f621c7165bb77a98f98b060ea97df4695f0ad9212ecf69bb51840d` |
| `image-record.json` (`CREATED`) | `4ed45f05d863f974ab9a7067a15ed4ee81a4b9900d0a582be24c9ce2296a805a` |
| `evidence/image-payload.json` | `da3f9e6d2126d2d638427e87f48f87170bdcf3b744a22f3efc7c5f4d9a4765e8` |

### Initial independent acceptance

The independent `package_dmg.py check` completed at 11:55:24 UTC.
It read the externally pinned DMG, verified the Apple structural checksum
and unsigned container, and mounted it read-only at a fresh path with spaces.
It matched all 763 volume entries, including the outer manifest, and all
694 candidate entries, including the mode `0600` signed manifest. The volume
root reported mode `0755`, system-managed `com.apple.provenance`, and ownership
enforcement disabled on the mounted volume. No extra filesystem-generated
paths were present. Both runs produced the same full inventory digest
`21fed8ce17b61745ad365a368522837bd22445f328e25f3c7cf51d6022b232ed`.

Normal detach completed before static checks or execution of the extracted
products. All eight code items and 13 architecture slices matched the local
signature policy. Version, AOT, NativeAssetsManifest, native loader graph,
and upstream source correspondence matched the sealed candidate.

The extracted CLI reported `meshctl 0.1.0-rc.1`. The write and reopen used
PIDs `26728` and `26735`, both with zero exit status, closed SQLite storage,
and live image observations from the extracted CLI's SQLite library. The
guest used the independently transferred App in run
`20261121T115459Z-product-48891`. App PIDs `49028` and `49139` mapped the
guest copy's SQLite library, wrote and reopened the draft, and quit normally
with storage, worker, and owner release. The executor exited zero and the
guest lock cleared.

The final gate rechecked the pinned input image, extracted payload, original
engineering package, frozen source, accepted local candidate, and bound
runtime and process evidence. A separate final audit confirmed there was
no owned attachment, the host and guest product and observer PIDs were
absent, and the guest lock was clear. The task's SSH control connection was
closed. `shasum -a 256 -c SHA256SUMS` still reported `OK` after acceptance.

| File in `build/phase-1e7/local-dmg-check-002/` | SHA-256 |
| --- | --- |
| `dmg-acceptance.json` (`PASS`) | `7a5f0e7e6a5bf899be632b5169b7e4446f9b5ceab7e634cc876cc5b93bf33ed7` |
| `evidence/static-products.json` | `92036c01aed1379d5ea468046d3ed1a043aacc232d20b5ce84b34e2057f27f29` |
| `evidence/cli-runtime.json` | `4439e65e08d79654888bdee28807a725a12b8ca518a3cc33f14bb04a2b4329fa` |
| `evidence/vm-app/runtime.json` | `404dfb859d8c5606fdfceac7130d2ab60f903575ee84c58fc2cb0196a9552dcc` |
| `evidence/vm-image-binding.json` | `dcfe65a94a0f624e26e24192ee20536a3cba9933863d6954c95a9693a985b9d3` |
| `evidence/build-receipt.json` | `062aeaa490daace89a272be31acd2a1726b818c3880816360caa5cdc1936c81b` |

### Initial tests and handoff

The final 16 DMG tool tests and the full 462-test Python tool suite passed
with Python 3.15.2. The full-run log is
`/private/tmp/meshchan-1e7-postfix-python-tests.log` with SHA-256
`d6038503fec0cc24e6c84e3cacb9ebd55cdf497e6d4a63b30d897947c26ebeb6`.
Markdown local links, release shell examples, and `git diff --check` passed.

This cut accepted the exact `local-dmg-002` image, `SHA256SUMS`, creation
record, `local-dmg-check-002` acceptance and evidence, and the then-selected
1E.6 product and acceptance. The complete source, license, and
rebuild and replacement materials accompany the candidate inside its volume
directory. Also preserve the paths referenced by the private receipts,
including the external creation and acceptance workspaces
under `/private/tmp/meshchan-1e7.AglDRkuj/` and the
[initial 1E.6 runtime workspace](phase-1e6-signing.md#initial-independent-acceptance-and-handoff).
These hold the extracted copies, SQLite fixtures, and image observations.
When retaining them for later steps, use the digests above and the
[DMG guide](../releases/phase-1e7-dmg.md#create-and-independently-check-the-image).

To recheck this historical image from the original checkout with the configured
VM, use the signing and DMG tool bytes and modes recorded in the source
snapshots. Choose an unused output name and a new external workspace parent:

```sh
MESHCHAN_CHECK_PARENT="$(mktemp -d /private/tmp/meshchan-1e7-recheck.XXXXXXXX)"
MESHCHAN_IMAGE_RUN=build/phase-1e7/local-dmg-002
MESHCHAN_LOCAL_RUN=build/phase-1e6/local-sign-001

/opt/homebrew/bin/python3 -B tool/package_dmg.py check \
  --candidate "$MESHCHAN_LOCAL_RUN/signed/Meshchan-0.1.0-rc.1-macos-arm64" \
  --candidate-sha256 5241033d916d87a32928afdb6ee7659f7bd1da7ef97d4ea97d6c622bd5cc851d \
  --acceptance-receipt "$MESHCHAN_LOCAL_RUN/evidence/check-wa4rw1l1/signing-receipt.json" \
  --acceptance-sha256 755a95c341bf68580c829d26ecf2609f008d001ea648951b8b0ab9ca9823c7bf \
  --image "$MESHCHAN_IMAGE_RUN/Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg" \
  --image-sha256 9fb048fd5a4eafb89fa69bc31f16207231b561c404574e21276e6d18d82aa7bb \
  --output build/phase-1e7/local-dmg-recheck-003 \
  --workspace-parent "$MESHCHAN_CHECK_PARENT" \
  --vm-config "$HOME/.config/meshchan-vm/config.json"
```

The result applies to the tested macOS 27.2.1 arm64 environments. Actual
download quarantine and system approval, ordinary installation, Beta upgrade,
minimum OS selection, real USB/RF, and publication/download comparison
remain separate steps under the [release contract](../releases/phase-1e-plan.md#remaining-steps-and-handoff).

## First image and failed independent acceptance

`package_dmg.py create` finished at 11:49:59 UTC on November 21, 2026.
The run is `build/phase-1e7/local-dmg-001/`. It produced an unsigned,
unnotarized UDIF image, compressed as UDZO with an HFS+ volume named
`Meshchan 0.1.0-rc.1 build 8`. The exact image is 675,887,659 bytes.
`hdiutil verify` reported matching CRC32 `$AF91F11C`. Running
`shasum -a 256 -c SHA256SUMS` from the creation run reported `OK`.

| File in the creation run | SHA-256 |
| --- | --- |
| `Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg` | `36a67e26132c46c461b77b23e1ec9d9522a1330fad5fa6f5eb2a63d08b1c38db` |
| `SHA256SUMS` | `c6ae2e7346dccea2df3a903384619efc4d34ef21e22be4e12b5b2c2827df7c38` |
| `image-record.json` (`CREATED`) | `b11a7de440d1fc363808469f35f293f3eb0f99e2354f47684a9f7f8df6e5c712` |
| `evidence/image-payload.json` | `1e02825795a014d19de474bd0cf2f800c08b279b8d1104d758dc47c69026994b` |

Creation matched all 763 inventory entries, including the outer manifest,
from staging to read-only mount to external extraction. The candidate
subdirectory retained all 694 entries, including its original mode `0600`
manifest. The HFS+ mount presented ownership as the attaching account with
ownership enforcement disabled on that volume. It retained the recorded POSIX modes and
exposed only the expected payload paths. The volume root reported mode
`0755` and system-managed `com.apple.provenance`. The image was detached
normally before the extracted static and signature checks. Retain the
creation workspace identified in `image-record.json` with its evidence.

The first independent check performed read-only attachment, checked all
payload entries, extracted, detached, and passed both limited runtimes.
It returned `FAIL` at post-runtime integrity because the CLI working
directory had been created inside the extracted volume tree. The final
comparison identified exactly the added CLI workspace and its seven child
entries. It recorded no residual attachment. The failure receipt is
`build/phase-1e7/local-dmg-check-001/dmg-acceptance.json` with SHA-256
`9105247d8508c605cfe6182b109e763803f2db17bd8fd5b36af0ad7330f59deb`.

The verifier now builds the CLI workspace alongside the extracted payload
and checks physical disjointness before running the CLI. A regression
fixture writes a mock runtime database there and checks that the full
payload inventory is unchanged. Both first-attempt runs remain on disk.
A fresh image is required because it carries the DMG tool inputs.
