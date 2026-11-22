# Phase 1E.5 engineering packaging

Use the preserved, accepted 1E.4 checkout and run from the
[build handoff](../validation/phase-1e4-build.md#recipe-55-handoff). Copy its
accepted build-info SHA-256 from the handoff. The packager verifies that digest
before reading the original indexes. The frozen checkout must still have its
original products, accepted materials, package configuration, SDK and caches.
The packager checks the checkout commit and the recorded checker and helper
hashes, then runs the original checkout's `build_release.py check
--require-frozen`. It records the four new verification ledgers, including
the strict materials check. The packager uses the same checkout
lock for snapshots, copying, and acceptance. It compares both sides of the
lock handoff to the frozen checker and checks the protected inputs again after
staging, archiving, and runtime acceptance.

The commands below use example paths and an illustrative historical build
pin. For a real package run, set the frozen checkout, build run, and pin
from that candidate's accepted build handoff. See the
[1E.11 handoff](phase-1e11-release-materials.md#build-10-replacement-candidate)
for the exact Build 10 identity. Run from the development checkout with the
existing stable Python and configured, logged-in macOS test VM. The VM follows the
[guest executor guide](../macos-vm-gui-testing.md). The VM configuration stays
private. Resolve paths to their canonical forms, including the existing parents
of the external extraction directories.

```sh
/opt/homebrew/bin/python3 --version
MESHCHAN_FROZEN_CHECKOUT="$PWD/build/phase-1e4/frozen-recipe-55"
MESHCHAN_BUILD_INFO_SHA=e9e2eb640af06cdf8e70696a82cf45ce124e1682784b364698d4a9d73c3c56ef
MESHCHAN_VM_CONFIG="$HOME/.config/meshchan-vm/config.json"
MESHCHAN_EXTRACT_PARENT="$(mktemp -d /private/tmp/meshchan-1e5.XXXXXXXX)"
MESHCHAN_PACKAGE_RUN="build/phase-1e5/$(basename "$MESHCHAN_EXTRACT_PARENT")"
/opt/homebrew/bin/python3 .agents/skills/macos-vm-gui-testing/scripts/vm.py \
  --config "$MESHCHAN_VM_CONFIG" check
/opt/homebrew/bin/python3 tool/package_release.py package \
  --source-checkout "$MESHCHAN_FROZEN_CHECKOUT" \
  --build-run build/phase-1e4/run-001 \
  --expected-build-info-sha256 "$MESHCHAN_BUILD_INFO_SHA" \
  --output "$MESHCHAN_PACKAGE_RUN" \
  --extract-root "$MESHCHAN_EXTRACT_PARENT/package extraction" \
  --vm-config "$MESHCHAN_VM_CONFIG"

/opt/homebrew/bin/python3 tool/package_release.py check \
  --source-checkout "$MESHCHAN_FROZEN_CHECKOUT" \
  --build-run build/phase-1e4/run-001 \
  --expected-build-info-sha256 "$MESHCHAN_BUILD_INFO_SHA" \
  --package-run "$MESHCHAN_PACKAGE_RUN" \
  --extract-root "$MESHCHAN_EXTRACT_PARENT/independent extraction" \
  --vm-config "$MESHCHAN_VM_CONFIG"
```

With a configured password file, the initial `vm.py check` establishes the
SSH control connection. The packager uses this connection in batch mode.
For an interactive SSH setup, connect as described in the guest executor
guide before running these commands.

Use a fresh direct run directory under the ignored `build/phase-1e5/` for
each package attempt. The default is `build/phase-1e5/run-001`. The extraction
path must be a fresh child of an existing external directory. Paths can have
spaces. Preserve failed directories and logs. The exit codes are 0 for all
checks passing and 1 for failure or interruption. An exit code of 2 with an
`INCOMPLETE` JSON result means the host checks passed without `--vm-config`.
The argument parser also uses exit code 2 for invalid usage and emits an
error instead of a JSON result. An independent check
uses a separate `evidence/check-*/` ledger and can repeat acceptance against
an existing archive with recorded artifact identities. It leaves the original
package receipt intact.

## Layout and integrity

```text
build/phase-1e5/<run>/
  stage/Meshchan-<version>-macos-arm64/
    Meshchan.app/
    meshctl/bin/
    meshctl/lib/
    materials/
    provenance/
    packaging-source/
    README.md
    package-info.json
  archives/Meshchan-<version>-macos-arm64.tar
  evidence/package-receipt.json
```

The App and CLI inventories are bound by the frozen build receipt. Material
file identities come from the accepted manifest, including the original
corresponding-source archives. The packager rejects unlisted and aliased
material files. The three original provenance indexes are copied as-is. The
original materials and their manifest stay in `materials/`. The outer
`packaging-source/` carries the actual packager, related helpers, tests, guide
and root GPL and contribution texts. Its byte and mode identities come from
the running development checkout. The external receipt records the Git
commit and working-tree state for those inputs independently of the product
source commit.

The package manifest records a full inventory rooted at the staging directory,
including the directory's own mode. Its only self-exclusion is
`package-info.json`, which the external receipt covers alongside the archive
size and digest. The package manifest is regenerated from the accepted source,
current tool inputs, and defined layout during a check. The check compares
that expected content with the actual staging files, archive members,
and extracted files. It also compares the archive identity recorded by
packaging. Editing a staged file and rewriting the package manifest cannot
change any of those independent expectations. For a retained package whose
packaging inputs differ from the current checkout, add
`--expected-package-receipt-sha256` with the original receipt digest from
the trusted validation record. This checks the archived packaging inputs
against that receipt and records the current verifier separately.

The engineering archive is an uncompressed PAX tar written and read with
Python's `tarfile`. It carries complete regular-file data, directory and file
modes, and exact relative framework links. Validation checks the full graph
and file contents on an open archive descriptor. Extraction writes relative
to the newly created directory's open descriptor. The packager opens child
directories without following links and checks that the requested extraction
path still names the owned directory before checking its inventory. This
preserves mode and raw link semantics that
the [tar data extraction filter](https://docs.python.org/3.15/library/tarfile.html#extraction-filters)
can normalize. The package rejects nonzero data after the tar end markers.
The writer clears owner and group information and carries timestamps as
informational fields. Extraction uses the current
owner and fresh timestamps. The receipt inventories observed system-managed
`com.apple.provenance` attributes. The data copy and archive omit them and
fail on other observed extended attributes, including resource forks,
or on ACLs and file flags. The tool checks the existing code signatures
after extraction and never re-signs candidate code.

The extracted products are verified using the original package configuration,
native hook snapshot and frozen build validator. The verifier checks the
build receipt's digest against the bytes it uses to select the native hook
snapshot. The runtime witness uses
the extracted CLI for offline draft create and reopen and checks the SQLite
database and exact loader trace. With VM configuration it also verifies the
guest's transferred whole App inventory before and after offline write and
reopen, checks its signature and bundled SQLite trace, and retains the normal
shutdown and absent-PID evidence. The guest inventory stream uses restricted
PAX to preserve long resource paths and raw link targets. The packager binds
the VM receipt to the current extracted App path, package manifest and App
inventory, and the guest run returned by the verifier. The VM verifier
runs in the configured guest's GUI session with the signed executor already
installed there. Each check uses a fresh fixture directory and attaches to
the guest job queue only after matching the runner's PID and the unique
launch argument of its executor parent. It shares the existing guest lock
with the other VM probes and verifies that the lock directory it owned is
released before accepting the executor's exit. A later probe may already
hold a different lock. The verifier leaves the installed executor and
shared scripts in place. The installed
`guest.sh` and `product.sh` must match the reviewed scripts in this checkout.

## Signing handoff

Use the exact `stage` paths, package manifest, and archive identity in the
[validation record](../validation/phase-1e5-package.md). A complete handoff
requires passing frozen, integrity, CLI, VM App, and final integrity checks in
the receipt.
Keep those products and records intact. Sign a separate owned copy and bind
the resulting bytes to new signatures, inventories and runtime evidence.
The archive digest identifies this internal engineering snapshot. The
[1E.6 signing guide](phase-1e6-signing.md) describes the explicit local ad hoc
profile and independent acceptance of the complete candidate for 1E.7. The
final DMG, engineering installation and upgrades, minimum macOS, and real
hardware have their own candidate-specific gates. Intel runtime is outside
this release's macOS arm64 scope.
