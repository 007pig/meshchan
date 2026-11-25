# Phase 1E.6 macOS local release signing

This step consumes the accepted [1E.5 engineering package](phase-1e5-package.md#signing-handoff)
and produces a separately sealed, locally signed candidate for
[1E.7](phase-1e7-dmg.md). The [validation record](../validation/phase-1e6-signing.md)
identifies the actual input, current local status, and historical Developer ID
attempts.

## Local signing policy

On a macOS arm64 signing host, verify the project's stable Python 3.15+
and Xcode selection. The selected profile is `local-adhoc`. It uses
`codesign --force --sign - --timestamp=none` for every code item with the
applicable identifier, entitlements, and runtime options. The workflow runs
without an official identity scan, Developer ID selector, Team ID, maintainer
key, or secure timestamp service. The [maintainer's signing decision](phase-1e-plan.md#current-signing-decision)
defers the official signing route until explicitly requested.

The [versioned policy](../../tool/release_signing_policy.json) covers every
discovered Mach-O and signing target. The current candidate has eight signing
targets. Sign the versioned App frameworks from the inside out, then the outer
App. Sign both CLI dylibs before the standalone CLI executable. Both main
executables require Hardened Runtime and
`com.apple.security.cs.disable-library-validation=true` to load the bundled
libraries with local signatures. The CLI main executable also requires
`com.apple.security.cs.allow-unsigned-executable-memory=true` for the embedded
Dart AOT runtime. Libraries and frameworks use empty entitlements and their
non-main executable runtime policy. The validation record retains the
diagnostic CLI startup and Library Validation results behind this policy.

Independent checks read each slice's ad hoc status, identifier, signature
flags, entitlements, and the absence of Developer ID Authority, Team, and a
secure timestamp. Use a macOS signing host whose
`codesign --display --verbose=4` reports `Total signatures` and
`Chosen signature`. The policy requires one signature per slice and
verification of the strict nested App seal.

## Recheck the accepted engineering input

Run from the checkout retaining the selected `build/phase-1e5/run-002`.
The selected build is the frozen recipe 55 `run-001` under
`build/phase-1e4/frozen-recipe-55`. Use the prior acceptance record for both
original pins. The following commands describe the candidate in the current
[handoff](../validation/phase-1e5-package.md#selected-package-and-1e6-handoff).

```sh
/opt/homebrew/bin/python3 --version
MESHCHAN_FROZEN_CHECKOUT="$PWD/build/phase-1e4/frozen-recipe-55"
MESHCHAN_BUILD_RUN=build/phase-1e4/run-001
MESHCHAN_PACKAGE_RUN=build/phase-1e5/run-002
MESHCHAN_BUILD_INFO_SHA=e9e2eb640af06cdf8e70696a82cf45ce124e1682784b364698d4a9d73c3c56ef
MESHCHAN_PACKAGE_RECEIPT_SHA=ac8e649f3938cab85adf26a6e7c71f51b7c8076560e0f33a8fb9e53f7b092ece
MESHCHAN_VM_CONFIG="$HOME/.config/meshchan-vm/config.json"
MESHCHAN_UPSTREAM_PARENT="$(mktemp -d /private/tmp/meshchan-1e6-upstream.XXXXXXXX)"

/opt/homebrew/bin/python3 -B .agents/skills/macos-vm-gui-testing/scripts/vm.py \
  --config "$MESHCHAN_VM_CONFIG" check
/opt/homebrew/bin/python3 -B tool/package_release.py check \
  --source-checkout "$MESHCHAN_FROZEN_CHECKOUT" \
  --build-run "$MESHCHAN_BUILD_RUN" \
  --expected-build-info-sha256 "$MESHCHAN_BUILD_INFO_SHA" \
  --package-run "$MESHCHAN_PACKAGE_RUN" \
  --expected-package-receipt-sha256 "$MESHCHAN_PACKAGE_RECEIPT_SHA" \
  --extract-root "$MESHCHAN_UPSTREAM_PARENT/upstream extraction" \
  --timeout 900 --vm-config "$MESHCHAN_VM_CONFIG"
```

Use the [VM guide](../macos-vm-gui-testing.md#build-connect-and-deploy) to
establish any required existing authorized connection. The full verifier
checks frozen source and materials, archive and extraction integrity, CLI,
guest App, and post-runtime integrity. Select the fresh
`evidence/check-*/package-receipt.json` for this exact run and record its SHA-256.
The original package receipt pin continues to identify
`evidence/package-receipt.json`. The two pins have different roles.

## Prepare, sign, and check

Set `MESHCHAN_UPSTREAM_CHECK_RECEIPT` to the fresh passing check receipt found
above and `MESHCHAN_UPSTREAM_CHECK_SHA` to its recorded hash. For example, the
validation record identifies one exact recheck and its hash. Keep the
original package checkout and the frozen source available for all three
commands. Retain the selected package check's evidence directory and its
external extraction root, including the CLI runtime workspace beside the
extracted product. Signing rechecks the package, retained extraction,
process logs, and runtime databases from that exact run. The receipts record
the product source, archived packager inputs, and signing inputs separately.

An ignored checkout-root `build` may link to a canonical external directory.
The package run, its check receipt, and the signing output accept paths through
that link or paths on the external volume. Pass the canonical frozen checkout
and keep `--build-run` relative to it. Use a check workspace outside both
checkouts and their build roots. For a new handoff, use the paths and pins from
its own build, package, and fresh package check.
For a linked frozen build, the signed manifest records the canonical run path
for [retention](phase-1e8-ci-retention.md#seal-the-selected-image-and-evidence)
alongside its checkout-relative run identifier.

```sh
meshchan_sign_release() {
  meshchan_sign_action="$1"
  shift
  /opt/homebrew/bin/python3 -B tool/sign_release.py "$meshchan_sign_action" \
    --signing-profile local-adhoc \
    --source-checkout "$MESHCHAN_FROZEN_CHECKOUT" \
    --build-run "$MESHCHAN_BUILD_RUN" \
    --expected-build-info-sha256 "$MESHCHAN_BUILD_INFO_SHA" \
    --package-run "$MESHCHAN_PACKAGE_RUN" \
    --expected-package-receipt-sha256 "$MESHCHAN_PACKAGE_RECEIPT_SHA" \
    --upstream-check-receipt "$MESHCHAN_UPSTREAM_CHECK_RECEIPT" \
    --expected-upstream-check-sha256 "$MESHCHAN_UPSTREAM_CHECK_SHA" "$@"
}

meshchan_sign_release prepare --output build/phase-1e6/local-prepare-001

meshchan_sign_release sign --output build/phase-1e6/local-sign-001

MESHCHAN_SIGNED_WORKSPACE="$(mktemp -d /private/tmp/meshchan-1e6-runtime.XXXXXXXX)"
meshchan_sign_release check --output build/phase-1e6/local-sign-001 \
  --expected-signed-info-sha256 "$MESHCHAN_SIGNED_INFO_SHA" \
  --workspace-parent "$MESHCHAN_SIGNED_WORKSPACE" --vm-config "$MESHCHAN_VM_CONFIG"
```

Optional `prepare` creates a fresh input copy and reports `PREPARED`. It
inventories every source file, maps all Mach-O and bundle items, and rechecks
the frozen loader graph and AOT/native relationships. `sign` uses its own
fresh run and verifies a complete locally signed copy before moving it to
`signed/<candidate>/`. Copy the printed `signedInfo.sha256` from the actual
successful sign result to `MESHCHAN_SIGNED_INFO_SHA` before invoking
`check`. `SIGNED` records successful signature and static transformation
checks. A separate `check` receipt with `PASS` is required for handoff.

The local manifest and receipts use format version 2 and record
`signingProfile: local-adhoc`. Historical format version 1 records retain
their original profile and outcome. Keep logs and failed receipts. Use new
output names for a new prepare or sign attempt and a new external workspace
parent for a check retry. Keep the original and previously sealed trees
available. Independent checks require the same signing tool inputs, including
the snapshotted guides, used when sealing the candidate. Changes to those
inputs require resealing a new candidate.

## Independent acceptance

- Inventory the actual candidate using the externally pinned, self-excluding
  `signed-product-info.json`. Recheck the actual signatures without
  modifying the bundle. Verify the bounded signature transformation against
  the accepted staging tree, including the Mach-O payload, load commands,
  AOT and native origins, and the remaining files, modes, and raw symlinks.
  Read filesystem security metadata before and after relocation. This policy
  observes macOS-managed provenance when present and rejects other xattrs,
  extended ACLs, and file flags.
- Copy the sealed whole products and materials to a fresh external location
  with spaces and verify the copy. Run finite CLI storage write/reopen tests
  in a controlled environment and App storage write/reopen/normal Quit in the
  identity-checked VM. Each invocation must identify the actual executable
  and prove the bundled SQLite image is loaded in that process. The owned
  process observer uses macOS process and mapped-vnode metadata. It does
  not rely on `DYLD_PRINT_LIBRARIES`, which can be suppressed by Hardened
  Runtime. Absent or ambiguous current image evidence leaves the runtime
  gate open. [Apple DTS explanation](https://developer.apple.com/forums/thread/839028)
- Run the [user library replacement procedure](phase-1e6-user-library-replacement.md)
  from a separate copy of this signed candidate, with its own CLI and VM
  runtime evidence and local signing policy. Verify both the sealed and
  relocated originals again after the experiment.

`materials/` and its original source archives remain bound byte for byte to
1E.5. `upstream-provenance/` contains the historical engineering manifest and
receipts. `signing-source/` carries the separately identified source inputs.
`signing-materials/` carries the new instructions and project license
texts. The new signed product manifest binds those files to the initial
inventory and actual signed outputs. Read runtime and modified-library
results in the distinct acceptance receipt and its referenced evidence.
Retain the external runtime workspace named in that receipt with the run's
evidence directory. It holds the CLI database and image observations and the
user replacement receipt and logs.

## Handoff to 1E.7

Hand off the complete candidate named by the independent `PASS` receipt
and its `signedInfo` digest. Preserve the exact receipt and manifest SHA-256
pins outside the candidate. Keep the acceptance run and external workspace
with the private handoff evidence. The [1E.7 guide](phase-1e7-dmg.md) uses those
pins to build and independently accept the read-only unsigned DMG. The
engineering download, installation and Beta upgrade follow in 1E.9.
