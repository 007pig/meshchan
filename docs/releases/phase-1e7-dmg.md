# Phase 1E.7 engineering DMG

The sample run paths and historical acceptance references come from the
Build 8 handoff. In the full release checkout, the
[1E.11 handoff](phase-1e11-release-materials.md#build-10-replacement-candidate)
identifies the held Build 10 public-layout image and its pins.

If you are reading this guide under `dmg-source/`, use the full release
checkout for `docs/releases/phase-1e11-release-materials.md`,
`docs/releases/phase-1e-plan.md`, and `docs/validation/phase-1e7-dmg.md`.
Run the separate payload privacy audit from that checkout with
`tool/audit_release_payload.py`.

The [current release contract](phase-1e-plan.md) selects local ad hoc signing
for the complete Meshchan App and CLI. The read-only, compressed UDIF DMG
uses the `UDZO` format and an HFS+ volume. The image is unsigned and the
engineering release is not Apple-notarized. Verify SHA-256
against a trusted handoff to establish byte identity. Local signing and SHA-256
do not establish the publisher's identity with Apple or guarantee automatic
Gatekeeper approval.

## Inputs and outputs

Use a macOS arm64 host with stable Python 3.15 or newer and the host tools
recorded by the packaging workflow. For the GUI part use the configured,
identity-checked macOS VM and its existing authorized executor. Follow the
[VM guide](../macos-vm-gui-testing.md) and keep the VM configuration private.

Use the complete `signedRoot` named by the independent local acceptance
receipt from [1E.6](phase-1e6-signing.md). Retain the manifest and acceptance
receipt SHA-256 pins outside the candidate. The receipt must record
`signingProfile: local-adhoc` and `status: PASS`. Have the upstream checkout,
frozen build, and packaging evidence available as identified by the candidate
and acceptance. Retain the selected upstream check's extraction and runtime
workspaces and the original 1E.6 workspace at their recorded paths. The
local CLI evidence also uses the retained SQLite library's device and inode.
The [validation record](../validation/phase-1e7-dmg.md) supplies the selected
paths, pins, and tested environments when the handoff is complete.

Both commands require fresh output runs below `build/phase-1e7/`. Use a
dedicated workspace parent on a local filesystem outside the checkout,
separate from candidate paths, caches, user data, and VM runtime paths. The
commands create their owned working paths below that parent. The example uses
a private temporary parent. Retain the workspaces referenced by acceptance
receipts with their evidence.

For a distributable image, use `--public-payload` in both commands as shown
below. The accepted private signed root remains the
input. The tool generates an independent public signed-product manifest
and a public materials inventory from the verified files. The projection
omits private receipts and provenance files. Check the actual extracted
payload and native binaries for local paths before handing off a public
image. The earlier engineering-only layout remains available for rechecking
existing images.

## Create and independently check the image

Run from the repository root. Set the four upstream variables from the
selected 1E.6 handoff, using the exact file paths and hashes reported by
`sign_release.py check`. The manifest digest is the published
`signedInfo.sha256`. The separate acceptance digest is `receiptSha256`.

```sh
MESHCHAN_CANDIDATE=/absolute/path/to/accepted/signed/product
MESHCHAN_CANDIDATE_SHA=accepted_signed_product_info_sha256
MESHCHAN_ACCEPTANCE=/absolute/path/to/independent/signing-receipt.json
MESHCHAN_ACCEPTANCE_SHA=accepted_signing_receipt_sha256
MESHCHAN_VM_CONFIG="$HOME/.config/meshchan-vm/config.json"
MESHCHAN_DMG_WORKSPACE="$(mktemp -d /private/tmp/meshchan-1e7.XXXXXXXX)"

meshchan_dmg() {
  meshchan_dmg_action="$1"
  shift
  /opt/homebrew/bin/python3 -B tool/package_dmg.py "$meshchan_dmg_action" \
    --candidate "$MESHCHAN_CANDIDATE" \
    --candidate-sha256 "$MESHCHAN_CANDIDATE_SHA" \
    --acceptance-receipt "$MESHCHAN_ACCEPTANCE" \
    --acceptance-sha256 "$MESHCHAN_ACCEPTANCE_SHA" \
    --workspace-parent "$MESHCHAN_DMG_WORKSPACE" \
    --vm-config "$MESHCHAN_VM_CONFIG" --timeout 900 "$@"
}

MESHCHAN_DMG_RUN=build/phase-1e7/local-dmg-001
meshchan_dmg create --public-payload --output "$MESHCHAN_DMG_RUN"
```

The historical Build 8 run used the engineering-only layout and yielded
`Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg`. The image name comes from the
selected product identity. In that example the App reported `0.1.0-rc.1+8`,
the CLI reported `0.1.0-rc.1`, and the Apple short version and build string
were `0.1.0` and `8`. Record the generated
`image-record.json`, the image file, and its `SHA256SUMS` outside the image.
`CREATED` indicates image creation and payload checks. Runtime acceptance is
a separate check. Preserve the recorded image SHA-256 to pin that check.

```sh
MESHCHAN_DMG_IMAGE="$(jq -er 'select(.status == "CREATED") | .image.path' \
  "$MESHCHAN_DMG_RUN/image-record.json")"
MESHCHAN_DMG_SHA=sha256_from_the_create_record
MESHCHAN_DMG_CHECK_RUN=build/phase-1e7/local-dmg-check-001
meshchan_dmg check --public-payload --output "$MESHCHAN_DMG_CHECK_RUN" \
  --image "$MESHCHAN_DMG_IMAGE" --image-sha256 "$MESHCHAN_DMG_SHA"
```

The independent check validates the externally pinned image with
`hdiutil verify`, mounts it read-only at an owned path, and checks the
complete volume contents against the expected inventory. It copies the payload
to a new external path and checks every extracted code item against the local
signing policy before detaching the owned mount. After detach it checks native
and AOT correspondence, runs a limited offline CLI write and reopen, and
transfers the extracted App to the configured guest
for a limited write, reopen, and normal Quit. Runtime records bind the actual
executable, SQLite image, and exit status. The guest check also verifies
storage and owner release, worker termination, PID absence, executor exit, and
guest lock release. The final checks reread the inputs, extracted payload,
image, and bound evidence. Use the independent `dmg-acceptance.json` and its
recorded digest to identify the accepted image for retention.

## Audit the independent public extraction

Record `receiptSha256` from the independent `check` command's final JSON. Use
that pin and the selected DMG SHA-256 to identify the extraction and its
inventory. Run the audit from the checkout and retain its JSON output with
the 1E.11 evidence. Include any additional absolute build roots as repeated
`--local-prefix` arguments.

```sh
(
  set -euC
  receipt="$MESHCHAN_DMG_CHECK_RUN/dmg-acceptance.json"
  receipt_sha=receipt_sha256_from_the_independent_check
  audit_report="$MESHCHAN_DMG_WORKSPACE/public-payload-audit.json"
  test "$(shasum -a 256 "$receipt" | cut -d ' ' -f 1)" = "$receipt_sha"
  payload="$(jq -er --arg image_sha "$MESHCHAN_DMG_SHA" '
    select(.status == "PASS" and .command == "check"
      and .image.sha256 == $image_sha and .payloadProfile == "public-engineering-v1")
    | .extraction.root' "$receipt")"
  inventory_sha="$(jq -er .payloadManifest.sha256 "$receipt")"
  /opt/homebrew/bin/python3 -B tool/audit_release_payload.py "$payload" \
    --image-inventory-sha256 "$inventory_sha" > "$audit_report"
  jq -e --arg inventory_sha "$inventory_sha" '
    .status == "PASS" and .imageInventorySha256 == $inventory_sha' "$audit_report"
)
```

The audit must report `PASS` for that exact payload before publication. Use a
fresh report path for a repeat audit. File-level findings remain in the JSON
when the audit exits with status 1.
Retain earlier engineering images and their original integrity and runtime
receipts for historical replay.

Keep failed and interrupted runs with their command and cleanup evidence.
Retry with a fresh output run and fresh owned workspace paths. Use the same
pinned image for repeat acceptance. If a failure leaves an owned attachment,
follow the recorded device and mount identity to recover it before retrying.
Preserve any attachment whose ownership cannot be established.

## Volume layout and release handoff

The volume contains `README-engineering.md`, `dmg-source/`,
`image-payload.json`, and the candidate directory. The candidate contains
`Meshchan.app`, the entire `meshctl/` folder, license and corresponding-source
materials, and signing and packaging tools. Keep `meshctl/bin/meshctl` with its
bundled native libraries. The public layout records
`payloadProfile: public-engineering-v1`. Its outer manifest binds the public
signed-product manifest and the digest of the private signed-product manifest.
Use the public manifest digest with the App and CLI in the copied public
candidate. Use the private manifest and acceptance receipt to create or check
the image and to retain the complete release evidence.
The candidate's `signing-materials/` includes the user library replacement
guide. The tooling and source records under `dmg-source/` identify the
independent container tooling and applicable license. The outer inventory
excludes its own file. The external checksum file identifies the final image.

Retain the exact accepted image, `SHA256SUMS`, image record, independent
acceptance receipt, local acceptance manifest and receipt, and the associated
source materials and evidence for 1E.8. Subsequent steps use those same image
bytes for installation and Beta upgrades, finite real USB/RF testing,
publication, and download comparison. Tested user approval and installation
instructions belong to 1E.9 and 1E.11. The 1E.7 VM and host runtime checks cover
only their recorded OS versions and environments.
