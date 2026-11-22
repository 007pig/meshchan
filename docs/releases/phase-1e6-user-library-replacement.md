# Rebuilding and replacing the bundled libserialport

The App and CLI each carry a dynamically loaded libserialport from the
same archived source package. The replacement experiment starts with the
complete `local-adhoc` candidate and copies both products before changing the
library. It uses local tools to apply a new ad hoc signature to each
affected code item. The original products, signed manifest, and license
materials remain the baseline for the release.

## Build and exercise the synthetic replacement

Use an arm64 Mac with Xcode's macOS SDK and Clang and Python 3.15 or later.
The original signature check uses a version of `codesign` that reports
`Total signatures` and `Chosen signature` with `--display --verbose=4`.
The signed root ships its corresponding scripts in `signing-source/`. The
replacement script can run directly from there without another checkout.
Before running the bundled script, verify the containing release artifact
against its independently published digest. You can also use a trusted
checkout of the matching signing tools as `MESHCHAN_SIGNING_TOOLS`.
Use the full repository for cross-references in `AGENTS.md` and the release
guides, or for first-time VM setup. The shipped VM workflow uses a configured
guest and its existing authorized executor.
Start with the SHA-256 of its `signed-product-info.json` from the release
handoff. For a public engineering DMG, use the public signed manifest's SHA-256
and the complete signed folder copied from that image. For a private signing
handoff, use its private signed manifest SHA-256 and complete signed root.
Keep its `materials/` and signature record, and choose a fresh output
directory in an existing parent.
The command below is the CLI and preparation portion of the experiment.

```sh
MESHCHAN_SIGNED_ROOT=/absolute/path/to/selected/signed/product
MESHCHAN_SIGNED_INFO_SHA256=published_signed_product_info_sha256
MESHCHAN_SIGNING_TOOLS="$MESHCHAN_SIGNED_ROOT/signing-source"
MESHCHAN_REPLACEMENT_OUTPUT='/private/tmp/meshchan user library test'
/opt/homebrew/bin/python3 -B "$MESHCHAN_SIGNING_TOOLS/tool/release_signed_replacement.py" \
  --signed-root "$MESHCHAN_SIGNED_ROOT" \
  --signed-info-sha256 "$MESHCHAN_SIGNED_INFO_SHA256" \
  --output "$MESHCHAN_REPLACEMENT_OUTPUT"
```

The tool verifies the original code signatures, the selected signed inventory,
and the exact source archive bound by the original materials manifest. It
extracts that archive into the new test output, patches `sp_list_ports` to
return a synthetic empty list before any OS backend call, and emits a unique
run token and process ID to stderr when the patched function is called. It
compiles the archive's `serialport.c`, `timing.c`, and `macosx.c` against
the shipped headers and macOS SDK, using one library for each product's
original install name and architecture set. The command receipts include the
actual compiler arguments. No Flutter or Dart SDK is needed for the rebuild.

The tool checks the exported symbols and actual install names for every
architecture. It copies the libraries to the following paths inside the
separate user products and rechecks the install names after local signing.

| Product | Replacement path |
| --- | --- |
| App | `Meshchan.app/Contents/Frameworks/libserialport_plus.framework/Versions/A/libserialport_plus` |
| CLI | `meshctl/lib/liblibserialport_plus.dylib` |

It re-signs the changed framework before the outer App and the CLI dylib before
the CLI executable. Each main executable keeps Hardened Runtime. Local main
executables retain `com.apple.security.cs.disable-library-validation=true`
for bundled libraries with local signatures. The CLI also retains
`com.apple.security.cs.allow-unsigned-executable-memory=true` for its embedded
Dart AOT snapshot.
Libraries receive empty entitlements. Other nested libraries keep their
original signatures. The tool verifies the flags, identifier, ad hoc signature,
and entitlements for each re-signed item. The recorded signature differences
also cover the rebuilt targets, the two main executables, and the relevant
bundle seals.

To check a compatible edit of your own, use the supplied source archive and
the compiler arguments recorded for each target. Preserve the install names,
exported interface, architecture sets, and bundle symlinks. Replace the rebuilt
libraries in independent App and CLI copies. Repeat the recorded local
`codesign` commands for those copies using the generated
`evidence/user-app.entitlements` and `evidence/user-cli.entitlements` files.
The recorded commands use the ordinary user's ad hoc selector `-`, which
requires no maintainer key or paid Developer ID identity. The ad hoc copies carry the user's local
signature without a Developer ID Authority, Team, or secure timestamp. The
local entitlement policy preserves the same runtime allowances as the original
engineering candidate.

After running without a guest configuration, check
`evidence/replacement-receipt.json` for `status: INCOMPLETE`,
`cli.status: PASS`, and `finalIntegrity: PASS`. Those results confirm the
prepared copies passed their final integrity checks and the copied CLI ran
successfully. Open the prepared App with a fresh, separate data directory
to confirm the synthetic list directly.

```sh
"$MESHCHAN_REPLACEMENT_OUTPUT/user products/Meshchan.app/Contents/MacOS/Meshchan" \
  --data-dir="$MESHCHAN_REPLACEMENT_OUTPUT/manual-app-fixture"
```

On **Device**, click **Refresh**, confirm the message **No available ports
were reported**, and quit normally. The synthetic library also prints the
current run marker to the launching terminal.

## Verify both replacement products for release acceptance

For maintainers repeating the paired experiment, read the VM skill at
`signing-source/.agents/skills/macos-vm-gui-testing/SKILL.md` in the signed
root or `.agents/skills/macos-vm-gui-testing/SKILL.md` in the working tree.
Use the configured, identity-checked guest and previously authorized GUI executor.
Connect the guest first. Set the path to the existing private configuration
and use a new output path.

```sh
MESHCHAN_VM_CONFIG="$HOME/.config/meshchan-vm/config.json"
MESHCHAN_REPLACEMENT_OUTPUT='/private/tmp/meshchan paired user library test'
/opt/homebrew/bin/python3 -B "$MESHCHAN_SIGNING_TOOLS/tool/release_signed_replacement.py" \
  --signed-root "$MESHCHAN_SIGNED_ROOT" \
  --signed-info-sha256 "$MESHCHAN_SIGNED_INFO_SHA256" \
  --output "$MESHCHAN_REPLACEMENT_OUTPUT" \
  --vm-config "$MESHCHAN_VM_CONFIG"
```

The CLI runs from its own working directory. Its `ports --json` result must
contain an empty array, the marker must name the launched process, and the
process must exit zero. In the guest the harness compares the transferred App's
entire inventory and verifies its signature. It checks the exact replacement
hash before clicking Device **Refresh**. It then verifies the displayed
empty-list result, the marker for that App PID, normal Quit, owner and worker
release, PID absence, the returned inventory, and release of the guest
executor lock.

Read `evidence/replacement-receipt.json` and its bound logs in the output.
Without a guest configuration the receipt records the CLI result and remains
`INCOMPLETE` after a successful CLI and final integrity check. The command
exits 1 in that mode to distinguish it from paired release acceptance.
Require `formatVersion: 2` and `signingProfile: local-adhoc` in the receipt.
Both execution checks and the final product inventory and metadata checks
must pass for an overall `PASS`. Keep failed evidence and pick fresh output
for a retry.

## Distribution and installation information

The release materials include the exact source archive, its hash and the
original licenses, the rebuild procedure, and the signing policy and tooling
for the affected products. Keep the signed originals for installation and
release acceptance. The local instructions above preserve the ability to
use an interface-compatible replacement, including how to reseal the modified
App without access to the distributor's private key. Record the actual local
runtime results when this gate is performed and assess any additional
installation requirements during 1E.9 engineering download and installation
validation.
See “LGPL source, rebuilding and replacement” in
`signing-source/docs/releases/phase-1e3-licenses.md` or the corresponding
repository document.
