# Phase 1E.8 CI and engineering retention

The release profile is `local-adhoc`. The complete macOS arm64 App and CLI
carry local ad hoc code signatures. The DMG container is unsigned and Apple
has not notarized it. Use the accepted build 8 bytes for retention and later
engineering installation. The [release contract](phase-1e-plan.md) governs
any future change to the signing profile.

## CI evidence

Push and pull request runs execute the existing Ubuntu `check` and arm64
`macos-app` jobs. The Ubuntu job also discovers the retention and CI
evidence Python tests. CI captures actual checkout and toolchain information,
workflow bytes, check results, and hashed logs. A pull request's head and
its tested merge checkout have separate fields. The job report records steps
before artifact upload. The completed run, exact attempt, and jobs returned
by GitHub establish the final conclusion.

Each job uploads its own report, workflow, and log archive for 30 days under
`meshchan-ci-<checkout SHA>-<run ID>-<attempt>-<job>`. The immutable upload
uses a pinned action and distinct names for reruns. A required report file
missing from the job fails the evidence step. Checkout and setup action logs
are available through the GitHub attempt logs. Hosted runners produce their
own check output and have no access to the accepted image on the maintainer's
Mac.

`tool/release_ci_evidence.py collect` uses the authenticated GitHub CLI to
read the exact attempt, all job and artifact pages, workflow bytes, and
original logs. Use an account with read access. For a new retention-tool push
run, require both artifacts. Downloaded ZIPs must match the GitHub artifact
size and SHA-256, and their report, workflow, and log contents must match the
selected job identities. The collector prints a SHA-256 for the local
snapshot manifest. Preserve it separately from the snapshot directory.

```sh
MESHCHAN_FROZEN_SOURCE=a29430b608658a8b56d619f641dc8600346b6d27
/opt/homebrew/bin/python3 -B tool/release_ci_evidence.py verify \
  --directory "$PWD/build/phase-1e8/ci-snapshots/frozen-source" \
  --source "$MESHCHAN_FROZEN_SOURCE" --run-id 44747988036 --attempt 1 \
  --workflow-sha256 eeef7fe89a6bd97c446cde9f816082ab2f50045253154ab2eaf9905942fbf6a4 \
  --snapshot-sha256 0682d0c89ac4e752df8611232ec5abfd595048b2f2150f1c52c3139baa7f3659
```

The historical product run and Step 7 tool runs have original attempt logs
and zero listed artifacts. Their historical workflows and toolchain
observations remain part of the record. See the
[validation record](../validation/phase-1e8-ci-retention.md) for the actual
retention-tool run and downloads.

## Seal the selected image and evidence

Use `retain_release.py retain` on the original machine with the accepted
inputs present. The selection JSON names the exact DMG, its checksum report,
creation and payload records, signed manifest, independent signing and
DMG acceptance, upstream package checker snapshot, and independently pinned
CI snapshots. It lists allowed original roots for receipt-bound lookup. Use a
separate pin for the selection JSON. The accepted chain and fixed assertions
determine the inventory. Historical source and tool identities stay distinct.

Run on the recorded retention source checkout before adding validation records
to the branch. The [validation record](../validation/phase-1e8-ci-retention.md)
gives the selection pin and actual source for this handoff. The archive parent
must exist and belong to the current user. Select fresh work and output names
when repeating the operation.

```sh
MESHCHAN_ARCHIVE="$HOME/Documents/my_projects/Meshchan Engineering Archive"
MESHCHAN_SELECTION="$PWD/build/phase-1e8/rc1-build8-selection.json"
/opt/homebrew/bin/python3 -B tool/retain_release.py retain \
  --selection "$MESHCHAN_SELECTION" --selection-sha256 "$MESHCHAN_SELECTION_SHA256" \
  --work "$PWD/build/phase-1e8/rc1-build8-seal" \
  --destination "$MESHCHAN_ARCHIVE/RC1 Build 8 - 1E.8"
```

Keep the printed receipt pin outside the object. The sealed directory contains
the external receipt, a manifest with the original-to-archive mapping, the
PAX tar, and a copy of the verification source. The receipt binds the manifest
and entire tar. The manifest binds the retained source snapshot, selection, and
every file, directory, and link. The original DMG and `SHA256SUMS` keep their
original data and checksums. Permission modes, internal symlink text, and
hidden files are preserved. Owner, timestamps, extended attributes, ACLs,
and filesystem flags are outside the portable data model. Original receipts
preserve historical paths, process IDs and SQLite device/inode observations.
The receipts distinguish creation, acceptance, and restoration.

Keep the sealed object on the private, persistent local archive volume.
Treat it as append-only and write later verification records beside it.
The engineering image and its original checksum are the transferable assets.
The archive contains maintainer evidence, including owned runtime databases
and process logs, and remains private. Copy the exact DMG out for a later
engineering download. The archive supplements the original DMG checksum
and the finite-lived GitHub artifacts with independently pinned local copies.

## Check and restore from the sealed object

Use a trusted verifier from the recorded retention source. The copy under
`verifier/` is part of the receipt-bound inventory and supports running
without the checkout. Set `MESHCHAN_RECEIPT_SHA256` from the
[validation record](../validation/phase-1e8-ci-retention.md). The shell commands
below use fresh names. The check removes its scratch extraction after
verification. Restore keeps the verified files and writes a separate report.
The archive and restore roots must be outside the checkout and temporary
directories and must be disjoint from each other.

```sh
MESHCHAN_ARCHIVE="$HOME/Documents/my_projects/Meshchan Engineering Archive"
MESHCHAN_SEAL="$MESHCHAN_ARCHIVE/RC1 Build 8 - 1E.8"
MESHCHAN_VERIFIER="$MESHCHAN_SEAL/verifier/tool/retain_release.py"
printf '%s  %s\n' "$MESHCHAN_RECEIPT_SHA256" "$MESHCHAN_SEAL/retention-receipt.json" |
  shasum -a 256 -c -
/opt/homebrew/bin/python3 -B "$MESHCHAN_VERIFIER" check \
  --retention "$MESHCHAN_SEAL" --receipt-sha256 "$MESHCHAN_RECEIPT_SHA256" \
  --work "$MESHCHAN_ARCHIVE/RC1 Build 8 - check evidence"
/opt/homebrew/bin/python3 -B "$MESHCHAN_VERIFIER" restore \
  --retention "$MESHCHAN_SEAL" --receipt-sha256 "$MESHCHAN_RECEIPT_SHA256" \
  --work "$MESHCHAN_ARCHIVE/RC1 Build 8 - restore evidence" \
  --destination "$MESHCHAN_ARCHIVE/RC1 Build 8 - restored"
```

Verification pins the tar before materializing its files and resolves every
historical path through the mapping. On macOS the restore also verifies the
original DMG's format, partition filesystem, structural checksum, and
unsigned container. A restored file's inode is its current filesystem
identity. The restore does not launch the products. For an original-environment
runtime recheck, use the [1E.7 command and matching tool checkout](../validation/phase-1e7-dmg.md#tests-and-1e8-handoff)
with the original evidence and configured VM.

## Phase 1E.9 input

Use the exact restored DMG recorded under `restoredDmg` in the verification
JSON and the matching checksum from the same retained creation run. Its
SHA-256 is `b42021e054e65e47893d84437100a6b9e51a2ea93eb7a060c12e70fdb4a6ca28`
and its size is 675,911,154 bytes. The image already carries its materials.
Use the same manifest and accepted receipts to identify the full internal
evidence. Quarantine, clean installation, Beta migration, and the oldest
supported macOS version remain 1E.9 work. Real USB/RF and publication are
later gates.
