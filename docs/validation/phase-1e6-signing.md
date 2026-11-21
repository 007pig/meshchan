# Phase 1E.6 macOS signing validation

**November 20, 2026 status: BLOCKED at Developer ID identity preflight.**
The selected upstream engineering package passed its full recheck. An owned
preparation run passed. The signing host's unrestricted
`security find-identity -p codesigning -v` returned
`0 valid identities found`. There is no selected Developer ID Team or
certificate for this candidate. See the [operating guide](../releases/phase-1e6-signing.md).

## Selected input and source identities

- Checkout `master` at `2c485289da90dea35c4bc1e8e23c139676d0e7ad` contains
  PR #43's merge `69272ec2c1088e675058f8d3d5ac8bf0688c70d4` and its
  head `59f26fc45b35f585f5adf07f1c4a5371d6227a98`. This is also the base for
  the signing implementation's working-tree inputs. The signing receipts
  record those inputs by exact path, mode, size, and SHA-256.
- Product compilation used frozen recipe 55 at
  `a29430b608658a8b56d619f641dc8600346b6d27` under
  `build/phase-1e4/frozen-recipe-55/build/phase-1e4/run-001/`.
- The accepted engineering package is `build/phase-1e5/run-002/`.
  The historical packaging tool ran at
  `3b362ecc6346c3aec8ccee26e571e76b7a0571c8` with working-tree inputs.
  The original package receipt and `packaging-source/` carry those exact
  files. The current upstream verifier ran at `2c485289da90dea35c4bc1e8e23c139676d0e7ad`
  and recorded its own input bytes separately.
- The App version is `0.1.0-rc.1+8`, Bundle ID `org.meshchan.meshchan`,
  Apple short version `0.1.0` and build string `8`. The CLI version is
  `0.1.0-rc.1`. The App and four frameworks have arm64 and x86_64 slices.
  The CLI and both of its dylibs are arm64.

| Bound input, relative to its selected run | SHA-256 |
| --- | --- |
| Frozen `build-info.json` | `e9e2eb640af06cdf8e70696a82cf45ce124e1682784b364698d4a9d73c3c56ef` |
| Engineering `archives/Meshchan-0.1.0-rc.1-macos-arm64.tar` (792,483,840 bytes) | `974dbbcae149291166326851b64ebcb5ba2bc13766d257e36b4fcbc43beb85e8` |
| Stage `package-info.json` | `c43fe73e9c625b9899e19ac073097f80aef3c26736443b48f59809545acec8ff` |
| Original `evidence/package-receipt.json` | `ac8e649f3938cab85adf26a6e7c71f51b7c8076560e0f33a8fb9e53f7b092ece` |
| Prior full `evidence/check-1kls66v9/package-receipt.json` | `eb6c56b98efcadf4395a55bb8386ac0d6df57b391d2bf7a5863414261439c140` |
| This step's full `evidence/check-ozo373ap/package-receipt.json` | `be95bfa1b40d4edd73d1e5bd27630de93b7c327e26390f694a550b371a17629c` |
| Stage `materials/materials-manifest.json` | `335519433a4e48d2e683563d7104b2b84ff35f274a5895bb7f8329a1cd909733` |

The new `package_release.py check` ran with the original receipt pin and
fresh extraction under `/private/tmp/meshchan-1e6-upstream.CdC9InXd/upstream extraction`.
All 623 entries matched. Frozen build and materials, package integrity,
relocated dependencies and signatures, CLI runtime, VM App runtime, and
post-runtime integrity passed at 21:50:50 UTC. Guest run
`20261120T215044Z-product-29784` observed write PID `29884` and reopen PID
`29974` exit normally. The executor exited zero and released its lock.
The VM receipt is under that recheck's `vm-app/runtime.json` with digest
`2bbf3ba9ff55c77c8054e15fba45ca67f124687ea2daa414c7a5371786f086e2`.

## Preparation and identity preflight

The host and VM used macOS 27.2.1 (26B131) arm64. Host Xcode was 27.2
(27B52) at `/Applications/Xcode.app/Contents/Developer`. Invocations used
`/opt/homebrew/bin/python3` 3.15.2, resolved to
`/opt/homebrew/Cellar/python@3.15/3.15.2/Frameworks/Python.framework/Versions/3.15/bin/python3.15`
with SHA-256 `6cc907e4a022fefc843bcd93954eaf5a2cbfc77a095640bfadeeed96154190c5`.

The first preparation attempt recorded the working tree's
`com.apple.quarantine` xattr on a copied reference entitlements file.
Repository source snapshots now copy the recorded file data and mode, which
are the version-controlled inputs. The first failed run remains at
`build/phase-1e6/prepare-001/`. Product and retained material copies continue
to apply the strict metadata policy.

`build/phase-1e6/prepare-004/prepared/` contains complete locally signed
App and CLI trees with the original materials, provenance and signing inputs.
Its `evidence/signing-receipt.json` has status `PREPARED` and SHA-256
`f4756c4edb4aab1ce2016d5089626da5997a85f079b7e259b9b9de6af763d2f4`.
The prepared inventory digest is
`861d9ac7acce80f92a296444175d540994895af6fcb858508520ad2d337cf89b`.
The prepared native/AOT record digest is
`f16ae98d84149d4f311fb5a407733fe01501769cccbe32fe0eb8d44123da5276`.
The recorded `tool/sign_release.py` digest is
`fcab6386699e2a00d7bae4aa7be1fbde48daf71d9766a128592f9ada40cd3d22`.
The versioned policy digest is
`3952f24cb3e99487429b941a4b498ba8c8e4de59f70151dddaaee92fd233ea34`.

Running the new `sign` entry against the same exact upstream recheck produced
`BLOCKED` and exit code 2 before making a signing copy. The receipt is
`build/phase-1e6/sign-blocked-no-identity-003/evidence/signing-receipt.json`
with SHA-256 `996fced5a5977d565ae56c633482b34683762bbef9861354751cacf81709af5d`.
Its stdout log captures the real identity count. The formal CLI, VM App,
and user replacement status fields remain `NOT_RUN`.

## Locally signed development diagnostics

The versioned signing policy keeps Hardened Runtime on both main executables
and default Library Validation on the formal originals. The CLI alone receives
`allow-unsigned-executable-memory=true`. Using separate copies of the actual
CLI, ad hoc signing with Hardened Runtime and empty entitlements caused
SIGKILL during Dart AOT startup even for `--version`. Enabling only the
unsigned-memory exception made `--version` return `meshctl 0.1.0-rc.1`.
In the synthetic replacement experiment, `allow-jit` plus the Library
Validation exception also exited with SIGKILL. The unsigned-memory exception
alone let the CLI start, then default Library Validation refused its ad hoc
replacement library. Both narrowly scoped exceptions passed on the
user-local CLI copy. The user-local App with Hardened Runtime and only the
Library Validation exception passed its bounded native UI check. These
observations support the candidate policy and local replacement recipe.
The formal policy must still be observed on the actual Developer ID binaries.

The production-shaped libproc observer captured live, executable, file-backed
bundled SQLite mappings in the two accepted 1E.5 CLI processes (PIDs
`63971` and `63976`) and in the two accepted 1E.5 App processes (guest
`20261120T215529Z-product-30134`, PIDs `30248` and `30344`). Both used
owned relocated bundles and confirmed write/reopen, SQLite persistence,
and normal exit. The guest executor exited zero and released its lock.
A separate relocatable copy exercise with Hardened Runtime tested the
signature order and bounded signature transform. The actual Developer ID
verification commands and certificate parsing were exercised on an
independently signed standalone executable, separate from Meshchan.

A paired developer experiment started with the accepted 1E.5 ad hoc
products and verified the supplied libserialport source archive
`9246f3a0909e4bc87ef2ac1366bbc2eb350d139f976a277dd5c29b8d3dc085e3`.
The rebuilt and locally signed CLI and App copies both invoked the patched
library and returned a synthetic empty port list. The CLI PID was `66667`.
Guest run `20261120T220007Z-product-37157` used App PID `37255` for
the Device Refresh and a normal Quit. The marker matched that PID,
resource/worker/owner release was observed, and the PID was absent after
exit zero. The executor exited zero, the lock was released, and the final
inventory matched. The actual rebuilt library hashes were
`7c1b7bc2a93a19c5b91ae40761e6efa3cf693c1b4a9668ef011c93fa300e7fa5` for
CLI and `8306a00c201497c85a302e4343ea861bce761846eb55864c25568e130feac944`
for App.

| Development-only receipt in `build/phase-1e6/diagnostics-001/` | SHA-256 |
| --- | --- |
| `cli-image-observer.json` | `6d2cd2e6c07d9bf458dadc885a885de46f5f5cbe927a2a5fdd7e73b7df3b9282` |
| `vm-image-observer.json` | `bd5489cc3a97ecf4ab718f8c0da2fc2d176d3d2d57f4f820c37f2e9dacb3f590` |
| `user-replacement-paired.json` | `5ff403487f86115b68da1b0c70e3d7601d4564056087ea7bf45b4506b7c56bfe` |

The final VM helper also passed the historical `--package-info` mode against
the accepted App extraction. Guest run `20261120T220635Z-product-37776`
confirmed App PIDs `37876` and `37963` exited zero and were absent after
shutdown. The executor exited zero and released its lock. The receipt at
`diagnostics-001/legacy-vm-runtime/runtime.json` has SHA-256
`053c293552726a7ab98c6eaa67104fb8ec3e1ddb904fa2e0739d2173e9816157`.

## Final tool checks

`/opt/homebrew/bin/python3 -B -m unittest discover -s tool -p '*_test.py'`
passed all 406 tests on Python 3.15.2. The suite includes 31 new signing,
provenance, runtime evidence, and replacement tests and the existing 1E.5
packaging coverage. The prepared snapshot's 44 signing input modes, sizes,
and SHA-256 digests matched both the live tooling and the retained
`signing-source/` copy. The new Markdown links and anchors and
`git diff --check` passed.

## November 21 review follow-up

The final review version passed all 420 tests with
`/opt/homebrew/bin/python3 -B -m unittest discover -s tool -p '*_test.py'`
on Python 3.15.2. The revised preparation entry rechecked the same accepted
1E.5 input, including the frozen generated configuration, and verified the
prepared inventory again before reporting `PREPARED`. Run
`build/phase-1e6/review-prepare-001/` records 47 signing inputs.
Its `evidence/signing-receipt.json` has SHA-256
`40d8b9adeb96f3d40fb64ee8b243b02230f7ea71d57e7e367c5192c22c6236be`.

The revised local replacement preflight passed on separate 1E.5 ad hoc
copies. CLI PID `77341` matched the launcher receipt. App PID `42010`
in guest run `20261121T054220Z-product-41912` produced the verified
Refresh transition. Both processes exited zero. The guest executor released
its lock and the final inventories matched. The exact preflight receipt in
`review-prepare-001/evidence/replacement-preflight.json` has SHA-256
`ad1de8e8ee27a934793c9ce203f9a83a3948ba09a37092a51a91e3b5190dd7db`.
The signing host still reported zero valid signing identities.

## November 21 guest lifecycle follow-up

The reviewed build-tool tree passed all 428 tests with
`/opt/homebrew/bin/python3 -B -m unittest discover -s tool -p '*_test.py'`
on Python 3.15.2. The new regressions cover a lost SSH submission or
cancellation reply, an interrupt immediately after the guest claims launch,
and interrupts before the supervisor records the forked PID. The tests also
check the replacement library's built install names and reject drift from
the verified transform inventory or unsupported filesystem metadata.

The accepted 1E.5 ad hoc products passed the revised replacement preflight.
CLI PID `97159` and App PID `43530` both exited zero, with the guest
App's Refresh transition and executor lock release verified in run
`20261121T055847Z-product-43430`. The original and modified inventories
matched the expected final states. The exact preflight receipt in
`build/phase-1e6/review-prepare-003/evidence/replacement-preflight.json`
has SHA-256 `dfda1e1daa112786481933367d804765e31accd9ec24064674c32441301118d4`.

The legacy `--package-info` entry also passed on the retained 1E.5
extraction in guest run `20261121T055856Z-product-43994`. Write PID
`44089` and reopen PID `44164` exited zero and were absent after shutdown.
The executor lock was released. The receipt at
`build/phase-1e6/review-vm-legacy-003/runtime.json` has SHA-256
`1ff231d757fd67362d2b2bfc65de5c79af3fadef7d079fb13b89fe6832f1a425`.

The current signing preparation run reported `PREPARED` after verifying
the same selected engineering package and current tool inputs. Its receipt at
`build/phase-1e6/review-prepare-003/evidence/signing-receipt.json` has SHA-256
`befc3062956043f12cee294da70013a02e42eb9dee7a5b1aac2c674771534068`.

## November 21 evidence and output review

The current revision passed 433 tests with
`/opt/homebrew/bin/python3 -B -m unittest discover -s tool -p '*_test.py'`
on Python 3.15.2. The new tests reject a substituted manifest or report
after writing, a swapped SQLite observation between two operations, and a
case-aliased replacement output inside the checkout's source tree.

Preparation reported `PREPARED` from the accepted 1E.5 input. Its receipt
at `build/phase-1e6/review-prepare-004/evidence/signing-receipt.json` has
SHA-256 `14019cbc6f71c8a766e7e9fd2168aed95b0c09bcc6c385c8126d2705014388fb`.

The revised image observer passed local write and reopen against an owned
copy of the 1E.5 ad hoc CLI. The observer and CLI PIDs were `9029` and
`9032` for write, and `9039` and `9041` for reopen. Both product PIDs
were absent after normal exit. The exact preflight receipt at
`build/phase-1e6/review-prepare-004/evidence/observer-pid-preflight.json`
has SHA-256 `70b1dca55e53ec81ff381a40bcf1d36d8679775cbdfc794f6bfd7203893d901e`.
The new regression fixture exercises guest observation binding.

## November 21 interruption and manifest review

The VM acceptance and standalone replacement harnesses now write the
primary failure receipt before waiting for guest cleanup. A local process
test with a simulated guest left `runtime.json` at `FAIL` with
`Interrupted by signal 15` when the outer runner escalated from SIGTERM to
SIGKILL. The receipt contained no executor exit or lock-release claims. A
separate regression exercises interruption during finish and rechecks the
same owned executor before recording exit and lock release.

The replacement preflight now checks the signed manifest's regular-file
type, mode `0600`, size, and pinned digest before running anything and
checks them again after runtime. A permission change after a successful CLI
operation leaves the overall result at `FAIL`. The replacement guide
describes how to establish trust in the scripts before executing them.

The complete Python tool suite passed all 433 tests with
`/opt/homebrew/bin/python3 -B -m unittest discover -s tool -p '*_test.py'`
on Python 3.15.2.

Preparation with the reviewed inputs and the same accepted 1E.5 package
reported `PREPARED`. The signing entry then reported `BLOCKED` and exit
code 2 during local identity preflight, before creating a signing copy.

| Receipt under `build/phase-1e6/` | SHA-256 |
| --- | --- |
| `review-prepare-005/evidence/signing-receipt.json` | `cef11ab97b7dc55f194ed284fbbb7e15673192862f0fb3dade5ae7fe3a33fd73` |
| `review-no-identity-005/evidence/signing-receipt.json` | `355255d8d8305bc9e45b47964993266e021de0ca4cbc68a343fa31acac9acf65` |

## November 21 VM evidence directory review

The VM verifier now checks physical directory identity before creating its
evidence directory. It rejects destinations inside the selected App or
complete product tree in both signed and engineering package modes.
Regression tests cover case aliases, a renamed App, an App copied away
from its manifest and a declared CLI that is missing. A detached App can
still use a separate evidence directory. The rejection tests use local
fixtures and confirm that no evidence directory is created.

All 43 tests in `package_release_test.py` and all 10 tests in
`release_signed_runtime_test.py` passed on Python 3.15.2. A fresh run
using the accepted 1E.5 package reported `PREPARED`. Its receipt at
`build/phase-1e6/review-prepare-006/evidence/signing-receipt.json` has
SHA-256 `343d96565e815d61c5448c19489031c93acac419284d0ad8951b843ec0707dff`.

## November 21 log, VM configuration, and local signing review

The release runner uses the same raw log bytes for the receipt digest and
for the validator's decoded input or attached command error. Preparation and
signed acceptance also recheck their directly referenced reports before
publishing success. Regression tests cover a changed log after ledger
publication and a changed preparation report before the final receipt.

The signed and engineering VM entry points check the configured
`runtime_dir` against selected release inputs by physical path identity.
They pass the checked configuration bytes through a temporary file with mode
`0600` outside the collected evidence. The standalone replacement process
keeps its own snapshot only while the local VM constructor reads it.

The replacement producer and the independent acceptance entry now inspect
the affected copies' actual local code signatures against the same policy.
A read-only check of the retained ad hoc products validated six architecture
slices. The verifier rejected a disposable CLI copy re-signed without
Hardened Runtime.

The historical 1E.5 App entry passed a real offline write and reopen in
guest run `20261121T064722Z-product-44642`. App PIDs `44742` and
`44829` exited zero and were absent afterwards. The guest executor
exited zero and released its lock. The temporary SSH connection was closed.
The VM receipt under
`review-prepare-007/evidence/legacy-vm-runtime-connected/runtime.json`
has SHA-256 `fa3bf9b9a7f0e8f1a8fe2e980bbea8d8e9e3862467f1ed6be346f7f3c4dbf89e`.

A new preparation of the same accepted 1E.5 input reported `PREPARED`.
Its receipt under `review-prepare-008/evidence/signing-receipt.json` has
SHA-256 `43ae4a06fb3d3f7257057735a3318711358e76e36a745117b0b97a87383f100e`.
All 442 Python tool tests passed with
`/opt/homebrew/bin/python3 -B -m unittest discover -s tool -p '*_test.py'`
on Python 3.15.2.

## Remaining handoff

Make the intended maintainer's Developer ID Application certificate and
matching private key available in the local signing keychain. Record the
public certificate SHA-1 and exact Team ID. With the same upstream pins, use
a fresh signing output and run the independent acceptance from the
[operating guide](../releases/phase-1e6-signing.md). The signing transformation,
formal runtime, replacement from the formal candidate, and phase acceptance
all need their own fresh evidence. There is no selected signed payload for
1E.7 at this cut. Notarization, ticket/stapling, DMG, Gatekeeper, public
download, and later installation and hardware checks remain separate gates.
