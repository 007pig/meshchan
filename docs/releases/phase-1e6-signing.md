# Phase 1E.6 macOS release signing

This step starts with the accepted [1E.5 engineering package](phase-1e5-package.md#signing-handoff).
It produces a separately sealed Developer ID candidate for [1E.7](phase-1e-plan.md#remaining-steps-and-handoff)
after independent runtime and materials acceptance. The [validation record](../validation/phase-1e6-signing.md)
identifies the actual input and current gate status.

## Signer and policy

On the macOS arm64 signing host, verify the project's stable Python 3.15+
and Xcode selection. Use the trusted maintainer Team ID and exact SHA-1 selector
for an accessible **Developer ID Application** certificate and its matching
private key. Inspect the current identities with `security find-identity -p
codesigning -v`. An installed public certificate alone does not supply the
identity. Verify the Team with the maintainer if it is ambiguous. The selector
and Team are public, and the key remains in the operator's keychain.

The [versioned policy](../../tool/release_signing_policy.json) enumerates the
eight code items in the selected candidate. Sign the four versioned App
frameworks from the inside out, then the outer App. Sign both CLI dylibs and
then the standalone CLI executable, using stable identifiers. All use the
same Developer ID Application certificate and secure timestamp. Both main
executables require Hardened Runtime and retain default Library Validation.
Version 1 gives only the CLI main executable
`com.apple.security.cs.allow-unsigned-executable-memory`. In two local
diagnostic runs on copies of the selected CLI, Hardened Runtime terminated
the actual AOT program during Dart startup. The CLI started after enabling
this exception. The App and all libraries use an empty embedded entitlement
dictionary (including an absent blob). Actual Developer ID runtime acceptance
must confirm this policy on both original signed products. See the
[validation record](../validation/phase-1e6-signing.md) for the diagnostic scope.
Apple documents the exception under
[Allow Unsigned Executable Memory](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.cs.allow-unsigned-executable-memory).

The installer identity, development identity and ad hoc fallback do not satisfy
the formal policy. During signing, a timestamp failure leaves the attempt
failed. Use Apple's [distribution signing guidance](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)
and [verification guidance](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)
when investigating identity or timestamp failures. Independent checks read
each slice's certificate, Team, identifier, embedded entitlements, flags and
`Timestamp` and also verify the strict nested App seal. Use a macOS signing
host whose `codesign --display --verbose=4` reports both `Total signatures`
and `Chosen signature`. The policy requires a single signature per slice.

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
commands. The script binds the actual verifier receipt bytes to the original
receipts, rechecks the upstream package, and records the product source,
archived packager inputs, and signing inputs separately.

```sh
meshchan_sign_release() {
  meshchan_sign_action="$1"
  shift
  /opt/homebrew/bin/python3 -B tool/sign_release.py "$meshchan_sign_action" \
    --source-checkout "$MESHCHAN_FROZEN_CHECKOUT" \
    --build-run "$MESHCHAN_BUILD_RUN" \
    --expected-build-info-sha256 "$MESHCHAN_BUILD_INFO_SHA" \
    --package-run "$MESHCHAN_PACKAGE_RUN" \
    --expected-package-receipt-sha256 "$MESHCHAN_PACKAGE_RECEIPT_SHA" \
    --upstream-check-receipt "$MESHCHAN_UPSTREAM_CHECK_RECEIPT" \
    --expected-upstream-check-sha256 "$MESHCHAN_UPSTREAM_CHECK_SHA" "$@"
}

meshchan_sign_release prepare --output build/phase-1e6/prepare-001

meshchan_sign_release sign --output build/phase-1e6/sign-001 \
  --identity "$MESHCHAN_CERTIFICATE_SHA1" --expected-team "$MESHCHAN_TEAM_ID"

MESHCHAN_SIGNED_WORKSPACE="$(mktemp -d /private/tmp/meshchan-1e6-runtime.XXXXXXXX)"
meshchan_sign_release check --output build/phase-1e6/sign-001 \
  --identity "$MESHCHAN_CERTIFICATE_SHA1" --expected-team "$MESHCHAN_TEAM_ID" \
  --expected-signed-info-sha256 "$MESHCHAN_SIGNED_INFO_SHA" \
  --workspace-parent "$MESHCHAN_SIGNED_WORKSPACE" --vm-config "$MESHCHAN_VM_CONFIG"
```

`prepare` creates a new unsigned-for-distribution copy of the accepted local
products and reports `PREPARED`. It inventories every source file, maps all
Mach-O and bundle items, and rechecks the frozen loader graph and AOT/native
relationships on the copy. `sign` takes another new run, preflights the
explicit identity, signs a separate full copy, and verifies it before
moving it to `signed/<candidate>/`. Copy the printed `signedInfo.sha256`
from the actual successful sign result to `MESHCHAN_SIGNED_INFO_SHA`.
`SIGNED` certifies completion of the signature and static transformation
checks. The independent `check` must still return `PASS`.

The signing commands retain logs and a receipt in each run's evidence
directory. Missing or unselected identities yield a `BLOCKED` receipt.
A failed run or an interrupted run must be preserved. Choose new output
names for a new prepare or sign attempt and a new external workspace parent
for a check retry. The original snapshot and any previously sealed signed
tree stay available for inspection. Use the normal authorized keychain UI
to unlock or select the maintainer's existing identity if needed. The tool
has no keychain write or certificate enrollment operation.

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
  runtime evidence and local signing policy. Verify both the formal and
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

Use only a `PASS` acceptance receipt and its identified `signedRoot`,
`signedInfo` digest, and complete App and CLI trees, plus their bound
distribution materials. Preserve the exact receipt hash and signed-info
digest outside the candidate. The private local evidence directory is for
maintainer handoff. Notarization submission, ticket/stapling, the final DMG,
Gatekeeper and download/installation tests still require their own acceptance.
