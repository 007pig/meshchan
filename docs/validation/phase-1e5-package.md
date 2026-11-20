# Phase 1E.5 engineering package validation

## Accepted source and tool identities

The November 20, 2026 run used the
[recipe 55 handoff](phase-1e4-build.md#recipe-55-handoff). The PR #42 merge at
`3b362ecc6346c3aec8ccee26e571e76b7a0571c8` is the packaging development
baseline. The App, CLI, and materials come from frozen product commit
`a29430b608658a8b56d619f641dc8600346b6d27` in
`build/phase-1e4/frozen-recipe-55/`, run `build/phase-1e4/run-001` relative to
that checkout. The App is `0.1.0-rc.1+8`, the CLI is `0.1.0-rc.1`, and the
Apple identity is `org.meshchan.meshchan`, short version `0.1.0`, build string
`8`. The upstream comparison build retained its independent `NOT_RUN` materials
status.

| Upstream file relative to the selected run | SHA-256 |
| --- | --- |
| `build-info.json` | `e9e2eb640af06cdf8e70696a82cf45ce124e1682784b364698d4a9d73c3c56ef` |
| `evidence/build-receipt.json` | `5b99f6daf49b0af123e66641ba16ae20939a5b8fa6d2cda2dc941bee1a5d458a` |
| `evidence/candidate-inventories.json` | `5261f1f685d9b63e0d6003fbc722ce866789cfa7cdfdfefadc54a4292eabfcaa` |
| `materials/materials-manifest.json` | `335519433a4e48d2e683563d7104b2b84ff35f274a5895bb7f8329a1cd909733` |

The host ran macOS 27.2.1 (26B131) arm64 and used
`/opt/homebrew/bin/python3`, Python 3.15.2. The original frozen check
reconfirmed Flutter 3.50.0, Dart 3.14.0, Xcode 27.2 (27B52), and macOS SDK
27.2 from the accepted toolchain. The private VM configuration and SSH
credentials stayed outside the package and validation records.

From the retained frozen checkout, the original command passed with
`status=PASS`, `buildStatus=PASS`, and `materialsStatus=PASS`:

```sh
/opt/homebrew/bin/python3 -B tool/build_release.py check \
  --output build/phase-1e4/run-001 --require-frozen
```

Each packaging or independent check repeats this command in that source
checkout, with a per-command timeout. The packaging receipt records the
frozen verification result and four ledger references, including the strict
materials recheck. The original checker appended those verification ledgers
and left the original receipt, accepted materials, and product inventories
in place.

## Package and independent check commands

Run from the development checkout. The actual external extraction parent was
`/private/tmp/meshchan-1e5.yxdpahHu`, created by
`mktemp -d /private/tmp/meshchan-1e5.XXXXXXXX`. Retained extraction paths
contain spaces. Use a fresh parent and a new package run for a repeat.

```sh
MESHCHAN_FROZEN_CHECKOUT="$PWD/build/phase-1e4/frozen-recipe-55"
MESHCHAN_BUILD_INFO_SHA=e9e2eb640af06cdf8e70696a82cf45ce124e1682784b364698d4a9d73c3c56ef
MESHCHAN_EXTRACT_PARENT=/private/tmp/meshchan-1e5.yxdpahHu
MESHCHAN_VM_CONFIG="$HOME/.config/meshchan-vm/config.json"
/opt/homebrew/bin/python3 -B tool/package_release.py package \
  --source-checkout "$MESHCHAN_FROZEN_CHECKOUT" \
  --build-run build/phase-1e4/run-001 \
  --expected-build-info-sha256 "$MESHCHAN_BUILD_INFO_SHA" \
  --output build/phase-1e5/run-002 \
  --extract-root "$MESHCHAN_EXTRACT_PARENT/package extraction" \
  --timeout 900 --vm-config "$MESHCHAN_VM_CONFIG"

/opt/homebrew/bin/python3 -B tool/package_release.py check \
  --source-checkout "$MESHCHAN_FROZEN_CHECKOUT" \
  --build-run build/phase-1e4/run-001 \
  --expected-build-info-sha256 "$MESHCHAN_BUILD_INFO_SHA" \
  --package-run build/phase-1e5/run-002 \
  --extract-root "$MESHCHAN_EXTRACT_PARENT/independent extraction" \
  --timeout 900 --vm-config "$MESHCHAN_VM_CONFIG"
```

## Tests and diagnostic run

The focused packaging suite passed 18 tests. Full Python tool discovery passed
352 tests with the same Python 3.15.2. The full log is
`build/phase-1e5/run-002/evidence/test-results/python-suite.log`
(SHA-256 `a9958a0ee1dc03195bf022f5f5cbf197b9e9c4b43252c42deed5d83ce270335b`).

```sh
/opt/homebrew/bin/python3 -m unittest discover -s tool -p 'package_release_test.py'
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
```

The first engineering attempt at `build/phase-1e5/run-001/` passed the frozen
check, actual extraction and relocated static checks. Its version gate failed
because the packager compared the CLI's line-terminated stdout with an
un-terminated expectation. After fixing that comparison, the CLI and VM App
passed separate diagnostic reruns on the first extracted product. The original
1E.5 run-001 receipt remains `FAIL`. The final run uses a fresh staging and
extraction. Its archive verifier also checks the tar end markers and rejects
appended data. The focused suite covers both regressions.

The VM used the existing authorized executor and an identity-verified SSH
session. For a repeat, run the VM skill's `vm.py check` in a separate host
process with the same private configuration before packaging. This checks
the configured connection without making the packaging process own the SSH
control master. The VM harness signs its own test helper for deployment.
The candidate App's existing signature is verified on the host and in the
guest.

## Selected package and 1E.6 handoff

The package run passed all five gates at 17:55:56 UTC. The selected local
staging root is
`build/phase-1e5/run-002/stage/Meshchan-0.1.0-rc.1-macos-arm64/`. Use its
complete `Meshchan.app/` and `meshctl/` trees for the 1E.6 signing input,
alongside the accepted `materials/` and exact `package-info.json`.
Use new owned copies for signing. Preserve the staged bytes and the
ad hoc package receipt. Rebind inventories, signatures, and acceptance
evidence to the separately signed bytes.

| Artifact relative to `build/phase-1e5/run-002/` | SHA-256 |
| --- | --- |
| `archives/Meshchan-0.1.0-rc.1-macos-arm64.tar` (792,483,840 bytes) | `974dbbcae149291166326851b64ebcb5ba2bc13766d257e36b4fcbc43beb85e8` |
| `stage/Meshchan-0.1.0-rc.1-macos-arm64/package-info.json` | `c43fe73e9c625b9899e19ac073097f80aef3c26736443b48f59809545acec8ff` |
| `evidence/package-receipt.json` | `ac8e649f3938cab85adf26a6e7c71f51b7c8076560e0f33a8fb9e53f7b092ece` |
| `evidence/relocated-products.json` | `f54e8cf85cee4f9fb189dc6273a4cf35a1de74a44d7f8da78f97b02b260ff395` |
| `evidence/cli-runtime.json` | `0af4511b61f3d74f4bf8b2d3e8e7a0a81e0383ef9eadf18e09f3f5608f0ba3e7` |
| `evidence/vm-app/runtime.json` | `06a38fac1935ad92f7d34acfb5d647c52a2d8764a8c059839ff9baedc8932a1a` |

The 622-entry payload inventory includes the staging root, the full 74-entry
App and six-entry CLI inventories, all 12 raw framework links, the 331 files
listed by the materials manifest, and the original manifest itself.
The external receipt covers the self-excluded `package-info.json`.
`provenance/` contains the original build index, receipt, and product
inventory. Their hashes and the hash of `materials/materials-manifest.json`
match the upstream table. The original corresponding-source archives remain
under `materials/source-materials/`. The retained App runner and CLI
executable have SHA-256
`e088a994fccc9f04c7d64490d41e839c18f459f773de3b9c510f48851c04d37f` and
`52620b3c4c8ef5a6f51ff292e96747de8320b4cdeb5eb66120387ce52f6c62ed`,
respectively. Whole-product verification includes their libraries, assets,
modes, and links.

The packager ran from `codex/phase-1e5-package` at the PR #42 merge commit
with uncommitted implementation files. The separate
`stage/Meshchan-0.1.0-rc.1-macos-arm64/packaging-source/` tree and the
external receipt record the bytes and modes of all 30 packaging inputs.
The tool SHA-256 values are:

| Packaging source input | SHA-256 |
| --- | --- |
| `tool/package_release.py` | `c1b7f13bb6c9407ffeaf54ceadbb116ba46425dfda289e911a834887a8ec7d0f` |
| `tool/release_package_archive.py` | `0e1643350c6945401df2f844b9781c3f18f2a571dd6d0624667709a925dad9c5` |
| `tool/package_release_vm.py` | `ab579b90a1d979f56440774d91ffce2caf1d1bcc8b1e68473819ea2acff91bd7` |
| `docs/releases/phase-1e5-package.md` | `7954ee8223f7008ece6f4af5c3d5514277ea45a1556d92efe7ecc90c9325e02c` |

Python resolved to
`/opt/homebrew/Cellar/python@3.15/3.15.2/Frameworks/Python.framework/Versions/3.15/bin/python3.15`
(SHA-256 `6cc907e4a022fefc843bcd93954eaf5a2cbfc77a095640bfadeeed96154190c5`).
The material and product copies retain `GPL-3.0-only`,
`Copyright (c) 2026 Meshchan Contributors`, and the approved license sources.
The original root GPL, copyright, CLA, and contribution texts were copied as
separate packaging inputs.

## Runtime and integrity evidence

The frozen product validator passed on the actual extracted bundle. It checked
the plist identity, all Mach-O slices, native dependency paths and runpaths,
App AOT exports, native assets mapping, and existing signatures, including
nested code via strict recursive verification. The receipt records
`com.apple.provenance` as the only extended attribute observed on the source,
stage, and extracted paths. The archive itself carries data, modes and raw
links. The local filesystem can attach its own provenance attributes.
No resource forks, extended ACLs, or file flags were observed.

CLI `--version` returned `meshctl 0.1.0-rc.1`. The separate create and reopen
processes exited successfully and reported closed storage. Both loaded
`meshctl/lib/libsqlite3.dylib` from the actual extraction. The fixture database
passed `quick_check` and contained the exact draft row returned by both
processes. Its SHA-256 is
`6bf025180738b04393c772b0c9f71d9660f7d3fa6663e556d051ecaa37aa2741`.

Guest run `20261120T175545Z-product-22440` used macOS 27.2.1 (26B131) arm64.
The whole App matched the accepted inventory before and after runtime.
The existing signature passed in the guest. The write process and reopened
read process reported `0.1.0-rc.1+8`, observed the same persisted draft, loaded
their own App bundle's `sqlite3.framework/Versions/A/sqlite3`, and completed
the normal native shutdown barrier. PIDs 22527 and 22619 were absent after
their respective zero exits. The independent database read confirmed the
draft after shutdown. The test executor also exited normally.

The final integrity cut rechecked the protected source, staging, archive,
and extracted inventory after runtime. The accepted build receipt, products,
materials manifest, and corresponding-source content retained their original
identities.

## Independent check and remaining release gates

The separate `check` command finished at 18:00:08 UTC with all five gates
`PASS`. It reread the frozen source and strict materials, independently
compared staging and the archive, and used
`/private/tmp/meshchan-1e5.yxdpahHu/independent extraction/`.
It confirmed the same package manifest and archive SHA-256, reran static
and local signature checks, and produced new offline CLI and App evidence.
Guest run `20261120T180000Z-product-22772` confirmed normal zero exits and
absent PIDs 22866 and 22967. The independent check receipt is
`build/phase-1e5/run-002/evidence/check-dplrbd4n/package-receipt.json`
with SHA-256
`d5952d398139c8d6e274cff315b8e171c10147a027f45c1303a7ac52e2f7a786`.
The original package receipt retained its recorded SHA-256.

Phase 1E.5 is complete for this candidate. The passing arm64 host and guest
runs cover the bounded offline storage workflows and the actual relocated
bundles. Full GUI and input-method testing, Intel and minimum macOS runtime,
clean installation and upgrade, and USB/RF acceptance were outside this run.
Developer ID signing, Hardened Runtime verification, notarization, the final
DMG, and public release remain later steps.

## Review follow-up recheck

On November 20, 2026, the reviewed tool completed a new check of the
retained `run-002` package on macOS 27.2.1 arm64 with
`/opt/homebrew/bin/python3` 3.15.2. The check used the same frozen checkout
and build-info digest as above, the original receipt digest through
`--expected-package-receipt-sha256`, and the fresh external path
`/private/tmp/meshchan-1e5-review.hV4zAkNC/review extraction`. The original
receipt anchors the archived packager inputs. The new check receipt records
the reviewed verifier inputs separately.

```sh
MESHCHAN_REVIEW_EXTRACT_PARENT=/private/tmp/meshchan-1e5-review.hV4zAkNC
/opt/homebrew/bin/python3 -B .agents/skills/macos-vm-gui-testing/scripts/vm.py \
  --config "$MESHCHAN_VM_CONFIG" check
/opt/homebrew/bin/python3 -B tool/package_release.py check \
  --source-checkout "$MESHCHAN_FROZEN_CHECKOUT" \
  --build-run build/phase-1e4/run-001 \
  --expected-build-info-sha256 "$MESHCHAN_BUILD_INFO_SHA" \
  --package-run build/phase-1e5/run-002 \
  --expected-package-receipt-sha256 ac8e649f3938cab85adf26a6e7c71f51b7c8076560e0f33a8fb9e53f7b092ece \
  --extract-root "$MESHCHAN_REVIEW_EXTRACT_PARENT/review extraction" \
  --timeout 900 --vm-config "$MESHCHAN_VM_CONFIG"
```

All five gates passed. Guest run `20261120T181300Z-product-23198` confirmed
normal zero exits and absent PIDs 23285 and 23375. The review recheck receipt
is `build/phase-1e5/run-002/evidence/check-8iyv0qyz/package-receipt.json` with
SHA-256 `97e5ebfac319ea35615feb45cca4005287df8c70dc009d50cfd47d2d5bd6d3b1`.
Its artifact digests match the selected staging and archive above. The
original receipt retains its recorded digest.

Full Python tool discovery passed 358 tests, including 24 packaging tests.
The added regression cases cover case-insensitive path aliases, staging
ancestor changes during runtime, frozen checker drift, retained package
receipt binding, and SSH and guest PID verification.

## VM startup ownership follow-up

A subsequent review changed how the packager attaches to an executor run.
The verifier now checks the installed launcher and runner scripts, passes a
unique launch argument to the existing signed executor, and checks the
active runner PID and its parent before using the job queue or requesting
shutdown. The installed executor on this VM uses the default guest root
even when given a different root argument. An initial private-root attempt
therefore failed. Its executor parent carried that attempt's exact argument,
which was verified before requesting normal shutdown. The run exited and
released the shared lock.

The final targeted check passed on November 20, 2026 with Python 3.15.2 and
the existing macOS 27.2.1 arm64 VM. It reused the actual App extraction from
`evidence/check-8iyv0qyz/` and verified the App inventory and bundled SQLite
again. Guest run `20261120T182502Z-product-25306` recorded normal zero exits
and absent PIDs 25405 and 25488. The executor exited normally and the shared
guest lock was confirmed idle. The original package and full recheck receipts
retain their recorded hashes.

```sh
MESHCHAN_REVIEW_APP_ROOT="$MESHCHAN_REVIEW_EXTRACT_PARENT/review extraction/Meshchan-0.1.0-rc.1-macos-arm64"
MESHCHAN_VM_OWNERSHIP_EVIDENCE=build/phase-1e5/run-002/evidence/vm-ownership-review.Ac6DKKdz/runtime
/opt/homebrew/bin/python3 -B tool/package_release_vm.py \
  --config "$MESHCHAN_VM_CONFIG" \
  --app "$MESHCHAN_REVIEW_APP_ROOT/Meshchan.app" \
  --package-info "$MESHCHAN_REVIEW_APP_ROOT/package-info.json" \
  --evidence "$MESHCHAN_VM_OWNERSHIP_EVIDENCE"
```

The focused VM receipt is in the evidence directory above at `runtime.json`
with SHA-256 `2a7d94a75f428299024dd954190408181c82bd0aaf6ac4f809aab3ad0e99116c`.
Full Python tool discovery passed 361 tests during this review. After adding
explicit startup diagnostics, all 27 focused packaging tests passed again.
The added cases cover startup argument binding, rejection of another launch
or stale PID, and cleanup after an unverified startup.

## Descriptor-relative extraction follow-up

A later review found that a destination pathname could change after archive
validation and before extraction writes. The extractor now creates its root
relative to open parent directories, opens each child directory without
following symlinks, and writes using those descriptors. The packager checks
the extraction root's filesystem identity before using the extracted
products and again after the runtime checks.

Full Python tool discovery passed 364 tests, including 30 focused packaging
tests, with `/opt/homebrew/bin/python3` 3.15.2. The added cases verify that replacing a
destination name cannot redirect extraction into an unrelated directory,
that root creation rejects symlinked ancestors, and that a byte-identical
replacement of the extraction root fails the final integrity check.

The retained 792,483,840-byte `run-002` archive was extracted into
`/private/tmp/meshchan-1e5-dirfd-review.5ltzeod9/external extraction`
using the reviewed extractor. All 623 expected entries, including the package
manifest, matched the retained staging inventory. The original archive,
manifest, and package receipt matched their previously recorded hashes.
The extracted App and CLI signatures passed strict verification, and the
extracted CLI reported `meshctl 0.1.0-rc.1`.
The focused result is
`build/phase-1e5/run-002/evidence/extraction-review-y6ehpkow/result.json`
with SHA-256 `1b5ecfd3ff698ebc9931d92ddb6b616f4db131793d16f3f10b24948dfed74ae3`.

## Guest inventory archive follow-up

On November 20, 2026, a macOS tar fixture showed that the guest's USTAR
export could omit a valid long resource name and link target while returning
zero. The verifier now uses restricted PAX for the guest inventory stream.
The stream carries file data, modes, and raw link targets for the exact
inventory comparison.

Full Python tool discovery passed 365 tests, including 31 packaging tests,
with `/opt/homebrew/bin/python3` 3.15.2. The regression fixture used the macOS
system tar. A focused VM check used the App and package manifest
from `extraction-review-y6ehpkow`. The before and after inventories matched.
Guest run `20261120T183713Z-product-25720` passed bundled SQLite write and
reopen, with normal exit and absent PIDs 25816 and 25908. The executor
exited with code zero. The focused receipt is
`build/phase-1e5/run-002/evidence/vm-inventory-review.WHKzjwLg/runtime/runtime.json`
with SHA-256 `5cd251548cfd4898a3572308d6bc1cabdfaeeb62acd8c856941625259a5d43e8`.
The original archive, package manifest, and receipt retain their recorded
identities.

## VM App receipt binding follow-up

The packager now compares the verifier's guest run ID with the one in the
retained VM receipt. It checks the receipt's App path, release identity,
package manifest hash, and App inventory hash against the extracted
candidate. It also requires passing guest inventories and signature checks
and a zero executor exit status. The hash in the package check receipt comes
from the exact VM receipt bytes that passed this comparison.

Full Python tool discovery passed 366 tests with
`/opt/homebrew/bin/python3` 3.15.2, including 32 packaging tests. The
packaging fixture accepts matching evidence and rejects an older extraction,
a different package-manifest hash, a different App-inventory hash, a
different guest run, and an incomplete shutdown even when the verifier
reports success to the caller. The new check also accepted the earlier
confirmed guest receipt reported in the previous section using identities
independently anchored to the preserved package and extraction.

The independent package check command for this follow-up was:

```sh
MESHCHAN_RECEIPT_REVIEW_PARENT=/private/tmp/meshchan-1e5-receipt-review.OLQUoorn
/opt/homebrew/bin/python3 -B .agents/skills/macos-vm-gui-testing/scripts/vm.py \
  --config "$MESHCHAN_VM_CONFIG" check
/opt/homebrew/bin/python3 -B tool/package_release.py check \
  --source-checkout "$MESHCHAN_FROZEN_CHECKOUT" \
  --build-run build/phase-1e4/run-001 \
  --expected-build-info-sha256 "$MESHCHAN_BUILD_INFO_SHA" \
  --package-run build/phase-1e5/run-002 \
  --expected-package-receipt-sha256 ac8e649f3938cab85adf26a6e7c71f51b7c8076560e0f33a8fb9e53f7b092ece \
  --extract-root "$MESHCHAN_RECEIPT_REVIEW_PARENT/review extraction" \
  --timeout 900 --vm-config "$MESHCHAN_VM_CONFIG"
```

The independent check completed at 18:47:28 UTC. Frozen inputs and materials,
actual extraction, the CLI and VM App runtime checks, and post-runtime
integrity all passed. Guest run `20261120T184722Z-product-26116` recorded
normal exit and absent PIDs 26215 and 26303. The new verifier bound the
VM receipt at `evidence/check-nik38kc1/vm-app/runtime.json` to the extracted
App with SHA-256 `5b508b9cc8bb8cba7aeb8834d89271c40fd66994586bba1f40cf3b002f0bda73`.
The independent receipt is
`build/phase-1e5/run-002/evidence/check-nik38kc1/package-receipt.json` with
SHA-256 `5a070cf0e4564afb1b1b1892bde13f42c815c7a8e71c46a745a68c049c340c0e`.
The selected stage, archive, manifest, and original receipt match their
previously recorded identities.

## Exact-byte receipt and inventory follow-up

The packager now verifies the bytes it parses for the original build receipt
and candidate inventories. The relocated native validator also receives
the accepted build receipt hash and verifies the exact bytes before using
the receipt to select native hooks. Upstream verification ledger references
hash the same bytes checked for a passing status. The VM receipt's manifest
hash now comes from the bytes used to select its App inventory.

All 35 packaging tests passed with `/opt/homebrew/bin/python3` 3.15.2. The
added cases cover indexes replaced between hashing and parsing, rejection
of a different build receipt before native validation, and binding the VM
receipt to its parsed manifest bytes.

The relocated native validator passed on the App and CLI extracted by
`check-nik38kc1`, using the frozen build receipt already bound by the
original package. The four upstream verification ledger digests also
matched the independent check. The focused native result is
`build/phase-1e5/run-002/evidence/native-receipt-review-8m6edwtw/result.json`
with SHA-256 `7058a0a46fb167f1af3f91a588fa4404db306ebd5ed98b6dd2a14630f437002a`.

## Guest lock release follow-up

The packager records the filesystem identity of the shared test lock while
attesting its guest runner. A zero exit receipt is accepted only after the
owned lock has gone from the shared slot. If a subsequent guest test has
already acquired the slot with a different lock directory, the previous
run can still complete. The verifier never removes another run's lock.
The package check requires the VM receipt's `guestLockReleased` field.

Full Python tool discovery passed 370 tests with
`/opt/homebrew/bin/python3` 3.15.2, including 36 packaging tests.
The added cases cover a zero exit with an unreleased lock, a released lock
followed by a later owner's lock, and rejection of incomplete lock-release
evidence at the package gate.

The focused VM check used the App and package manifest from
`check-nik38kc1`. Guest run `20261120T185800Z-product-26537` completed the
SQLite write and reopen with normal exit and absent PIDs 26638 and 26727.
It recorded executor exit zero and release of its own guest lock. The focused
receipt is
`build/phase-1e5/run-002/evidence/vm-lock-review.tReIUsps/runtime/runtime.json`
with SHA-256 `7c06db0f8f447180652a530fdf2b9644c5d4ade62a969a138ba598e8a37441d9`.

## Guest status receipts and relative evidence paths

The shared product harness and packaging verifier wait for complete guest
status lines. A pending reply does not resubmit the job. Failure receipts
keep the original runtime error and a separate, redacted cleanup diagnostic.
The macOS shell regression covers a partially written executor status file.

Guest run `20261120T191003Z-product-26956` finished both App operations and
released its lock, but its verifier failed when constructing the SQLite file
URI from the relative evidence path. The failure receipt is
`build/phase-1e5/run-002/evidence/vm-status-review.2RaMiihJ/runtime/runtime.json`.
The verifier now makes the evidence path absolute before creating files.

Full Python tool discovery passed 373 tests. All 38 packaging tests passed
again with the final status polling change. Both used
`/opt/homebrew/bin/python3` 3.15.2.

The focused VM check reran against the App and manifest from `check-nik38kc1`
using a fresh relative `--evidence` path. Guest run
`20261120T191158Z-product-27639` passed the offline write,
reopen, and SQLite integrity check. The App exited normally both times, PIDs
27739 and 27820 were absent, and the executor exited zero and released its
lock. The packaging verifier confirmed the receipt's binding to the frozen
App inventory and the extracted package manifest. The final VM receipt is
`build/phase-1e5/run-002/evidence/vm-status-review.gj7k3Ihm/runtime/runtime.json`
with SHA-256 `1685a20cb5180031766df80befb451e87a93f9eb5a84f15c5d10805e5c322c0c`.

## VM receipt type verification

The package verifier requires an integer zero for the guest executor exit
and a JSON boolean for lock release. The regression cases reject a boolean
or floating-point exit code and a numeric lock-release value. All 373 Python
tool tests passed with `/opt/homebrew/bin/python3` 3.15.2.

The independent check reran the retained `run-002` archive with the original
package receipt hash and extracted it into
`/private/tmp/meshchan-1e5-typed-receipt.vDguG53Z/review extraction`. It passed
the frozen build and materials rechecks, relocated native and signature
checks, offline CLI and VM App checks, and post-runtime integrity checks at
19:20:20 UTC. Guest run `20261120T192014Z-product-28014` recorded both App
processes exiting normally with PIDs 28115 and 28207 absent, executor exit
zero, and lock release. The archive, stage manifest, and original receipt
digests match the selected package in the signing handoff.

The independent receipt is
`build/phase-1e5/run-002/evidence/check-9s1st7td/package-receipt.json`
with SHA-256 `657db08d7f949e100c5a02db03e7563167aabf7216f2e2205b7b3b0fc4752b10`.

## CLI and original package receipt types

The CLI verifier and original package receipt reader now use the same
type-and-value check as the VM receipt verifier. The regression tests reject
malformed CLI exit, success, schema, and draft revision fields and a boolean
package format version. All 375 Python tool tests passed, including 40
packaging tests, with `/opt/homebrew/bin/python3` 3.15.2.

The focused check used `/opt/homebrew/bin/python3` 3.15.2. It accepted the
pinned original package receipt, rechecked the VM receipt binding from
`check-9s1st7td`, and ran the already extracted CLI from a fresh external
working directory. Both CLI operations closed normally and loaded the SQLite
library from the extracted bundle. The reopened draft and the independent
SQLite integrity check passed. The focused receipt is
`build/phase-1e5/run-002/evidence/cli-receipt-review.fde1ax78/cli-runtime.json`
with SHA-256 `d5ecacbd24c0f23bf8a634d8dcb72770d99e41d0630833592deca6b2cc7b5fff`.

The final verifier passed a separate end-to-end check of the retained archive
at 19:45:55 UTC with `/opt/homebrew/bin/python3` 3.15.2. It used the original
receipt hash and a new extraction under
`/private/tmp/meshchan-1e5-final-review.oJdv5aW3/`. All 623 entries matched
across staging and extraction. The frozen and materials checks, relocated
native checks, CLI and VM App runtime, and post-runtime integrity all passed.
Guest run `20261120T194548Z-product-28538` recorded normal exit and absent
PIDs 28639 and 28730, executor exit zero, and lock release. The complete
receipt is `build/phase-1e5/run-002/evidence/check-1kls66v9/package-receipt.json`
with SHA-256 `eb6c56b98efcadf4395a55bb8386ac0d6df57b391d2bf7a5863414261439c140`.
