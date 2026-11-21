# Phase 1E.6 macOS signing validation

## Current engineering profile

On November 21, 2026, the maintainer selected `local-adhoc` for the
macOS arm64 engineering release. The
[active release contract](../releases/phase-1e-plan.md) and
[signing guide](../releases/phase-1e6-signing.md) define the current gates.
The historical Developer ID block and preparation and diagnostic results
below retain their original status.

PR [#45](https://github.com/007pig/meshchan/pull/45) was already merged
at `e36690b` when this work began. The full upstream check cited in that
PR is `build/phase-1e5/run-002/evidence/check-saa6bwr4/package-receipt.json`.
Its SHA-256 is
`3fa4cd3cd2e0c352796a91bccafa3bb33855120dac2937b0ac3c1df124a0e3aa`.
The receipt records `PASS` for frozen inputs and materials, package
integrity, CLI, VM App, and post-runtime integrity. Its original package
receipt pin is `ac8e649f3938cab85adf26a6e7c71f51b7c8076560e0f33a8fb9e53f7b092ece`.
The VM evidence is `evidence/check-saa6bwr4/vm-app/runtime.json`, relative
to the package run, with SHA-256
`6b7c38057296b4f8df7e365aada27876fac39e3bf01cbc81ad60e95ab41dfa62`.

### Independent acceptance and 1E.7 handoff

The current candidate is `build/phase-1e6/local-sign-005/`. Its independent
check finished at 12:58:17 UTC on November 21, 2026. The bundled standalone
replacement tool now permits disjoint output when a consumer cannot traverse
the publisher's recorded paths. The path check still protects the nearest
inspectable ancestor. An unprivileged fixture exercised both the inaccessible
publisher path and the permitted consumer output.

| File in `local-sign-005/` | SHA-256 |
| --- | --- |
| `signed/Meshchan-0.1.0-rc.1-macos-arm64/signed-product-info.json` | `58565d17e1c8659f6a73d6164ea37afabee1b75a03c1b20a01615ade467c18d9` |
| `evidence/signing-receipt.json` (`SIGNED`) | `bea5758133cf0d06fbebddffa0c6d400541e2b759b103929fe911e2a870546d7` |
| `evidence/check-1nivpup_/signing-receipt.json` (`PASS`) | `17b203af6191d574d7d77fed472fb04050690aaf87e0b312ef1e02fa6eb474f0` |
| `evidence/check-1nivpup_/cli-runtime.json` | `02f6c48e90a7d901878846b814e4106ff6ff93ed0045bd691c6ca2670a1e21fb` |
| `evidence/check-1nivpup_/vm-app/runtime.json` | `6c184d292684ff59ad8e08e34c71157714cb4ae684dc56540f9c6c5899bf2565` |
| `evidence/check-1nivpup_/build-receipt.json` | `2c6da7ede2c48cedd4545c482a2f2bfc7ab0288a751ea1a5e7b2e76160515a7f` |

All seven upstream, signature, material, runtime, and final integrity gates
passed for App `0.1.0-rc.1+8` and CLI `0.1.0-rc.1`. CLI PIDs `92458` and
`92466` completed offline write and reopen. App PIDs `54175` and `54287` in
guest run `20261121T125725Z-product-54037` mapped SQLite vnode
`16777233:386596` in both runs and passed normal Quit. Both systems used
macOS 27.2.1 (26B131) arm64. Retain the workspace
`/private/tmp/meshchan-1e6-publisher-review.TtxdL8az/Meshchan signing runtime`,
including the paired replacement receipt under
`user modified products/evidence/` with SHA-256
`afcc52005b074a04b899904e514e07003b19e4afa0203df4e9db10bdf932e7f0`.
That receipt records CLI, App, and final integrity `PASS`. The
[current DMG handoff](phase-1e7-dmg.md) uses this candidate and pins.

## Prior local acceptance after isolation review

The prior candidate was `build/phase-1e6/local-sign-004/`. Its independent
check finished at 12:43:15 UTC on November 21, 2026. The acceptance replay
binds the VM and replacement results to the actual process arguments and
requires the same SQLite vnode across VM write and reopen. Signing and
replacement subprocesses and host VM archive transfers use owned scratch
directories. The original upstream extraction is protected during
standalone replacement.

| File in `local-sign-004/` | SHA-256 |
| --- | --- |
| `signed/Meshchan-0.1.0-rc.1-macos-arm64/signed-product-info.json` | `41505574cb49596c1a0d26c61ddbf1838a9ee631d73791a67b84fc659f380a11` |
| `evidence/signing-receipt.json` (`SIGNED`) | `59fe380f6a16464f7cfaafd040cbc90421a3d3e1c2c257fe47260a0641a84fcd` |
| `evidence/check-vb6jvzuh/signing-receipt.json` (`PASS`) | `0a688d7a0ca1d505a97fbc472d9b9a88cd713f6010e2a5be2533e0b356ee5d7c` |
| `evidence/check-vb6jvzuh/cli-runtime.json` | `cb7efe030ea767649d5c086942164bcf5d4b3f836e27f5090a054ec8903224f9` |
| `evidence/check-vb6jvzuh/vm-app/runtime.json` | `06c942f4ec81679a708f65df47ab6fe1bfaf9ca2fd66cc6ee4e606ea90ba4421` |
| `evidence/check-vb6jvzuh/build-receipt.json` | `737f452c2003e0d61e2a6cf8b856d6d1a9b090c0a33d0d5a89e7d8d0a29d3d4a` |

All signing, material, and runtime gates passed for App
`0.1.0-rc.1+8` and CLI `0.1.0-rc.1`. CLI PIDs `76432` and `76442`
passed write and reopen. App PIDs `52672` and `52779` in guest run
`20261121T124218Z-product-52534` used the same SQLite vnode
`16777233:385840` and passed normal Quit and executor cleanup. Both systems
used macOS 27.2.1 (26B131) arm64. Retain the workspace
`/private/tmp/meshchan-1e6-isolation-review.1U3oiMa6/Meshchan signing runtime`,
which contains the paired replacement receipt under
`user modified products/evidence/` with SHA-256
`d3ca63b1412c42cf157f25b2f6a75009f04b120dcc821887450c2ba36b50568e`.
The [prior DMG handoff](phase-1e7-dmg.md#prior-accepted-dmg-after-isolation-review)
uses this candidate and pins.

## Prior local acceptance after evidence review

This run remains evidence for its matching source snapshot.

That candidate was `build/phase-1e6/local-sign-003/`. The reviewed
verifier replayed the exact upstream check identified above. It confirmed
the original extraction, same-run process outputs, CLI SQLite load traces,
and both runtime databases. Keep
`/private/tmp/meshchan-1e6-pre-pr.pSSigZQg/independent extraction/` together
with the original package check evidence at the recorded paths.

The independent check finished at 12:28:29 UTC on November 21,
2026. All eight code targets and 13 architecture slices passed, together
with the upstream, material, CLI, VM App, modified-library, and post-runtime
checks. The App is still `0.1.0-rc.1+8` and the CLI is `0.1.0-rc.1`. The
host and guest used macOS 27.2.1 (26B131) arm64.

| File in `local-sign-003/` | SHA-256 |
| --- | --- |
| `signed/Meshchan-0.1.0-rc.1-macos-arm64/signed-product-info.json` | `e6f74bdba940dfcc87a9969e4ef01302ed56350c7923adaaf4e7bf34f2961e7e` |
| `evidence/signing-receipt.json` (`SIGNED`) | `b521d0af996808f4c5a340df29921ba390f8273716dfbc865ce47d0deebffd33` |
| `evidence/check-li3f96k0/signing-receipt.json` (`PASS`) | `8f636f7368f46eb6652edf93413698bebd6aacdbf2b0b1cbf67f8a5e4e1d7601` |
| `evidence/check-li3f96k0/cli-runtime.json` | `fc73a2645636d25b2cf95ed8bfd3b6fcbde713a1b80c19b6042b89f8e7021451` |
| `evidence/check-li3f96k0/vm-app/runtime.json` | `d9b8d3e11c3fc06f187ecec706e4f1772b667af483a1c0062040069fa27b0d25` |
| `evidence/check-li3f96k0/build-receipt.json` | `97f3b95e8e5884a3113dfce7005cb6a655fe00c938fe6dc973fee2c7f643ba09` |

Retain the original workspace
`/private/tmp/meshchan-1e6-evidence-review.AtLvyga3/Meshchan signing runtime`.
CLI PIDs `58652` and `58668` wrote and reopened the fixture. App PIDs
`51156` and `51260` did the same in guest run
`20261121T122738Z-product-51017` and passed normal Quit and executor cleanup.
The paired replacement passed with CLI PID `59944` and App PID `51514`
in guest run `20261121T122758Z-product-51419`. The replacement receipt in
`user modified products/evidence/` has SHA-256
`9709bbf2a473b11d246326fece9d9cca115cdc83f40bae6bf2b95581a4263576`.

## Prior local acceptance after initial tool review

The following run remains evidence for its earlier signing tool snapshot.

The reviewed signing tools sealed a fresh candidate in
`build/phase-1e6/local-sign-002/` from the same accepted 1E.5 package and
frozen product. The code and material gates passed for all eight signing
targets and 13 architecture slices. The independent check finished at
12:12:53 UTC on November 21, 2026, with `PASS` for upstream admission,
signatures, material transformation, CLI, VM App, library replacement, and
post-runtime integrity. The App remains `0.1.0-rc.1+8` and the CLI remains
`0.1.0-rc.1`. The host and guest used macOS 27.2.1 (26B131) arm64 and the
host invoked `/opt/homebrew/bin/python3` 3.15.2.

| File in `local-sign-002/` | SHA-256 |
| --- | --- |
| `signed/Meshchan-0.1.0-rc.1-macos-arm64/signed-product-info.json` | `89caa167ba7465c1415344da9df667d148e7095c2fc2a8efe9ea5e3c2b2b1cbd` |
| `evidence/signing-receipt.json` (`SIGNED`) | `c8702c7afe0c23f2bb5b97dfedc020120bfd31bc2d163114263b459c0050c356` |
| `evidence/check-2qhsultx/signing-receipt.json` (`PASS`) | `6ca8f1e1342a3d34c108d21bc0cc47dadf489e69eec41df1268ad7b01d65bdec` |
| `evidence/check-2qhsultx/cli-runtime.json` | `896f8709de76181baf231fd8e389bd50bceabd209df2e8fc79588c04fc4d8ad3` |
| `evidence/check-2qhsultx/vm-app/runtime.json` | `077e2cca891a4d06b4e76263579f6841f87aa874ed4f4ff5a796e6d344b43522` |
| `evidence/check-2qhsultx/build-receipt.json` | `a5ed7e0ada08abc20a956d5bf7b1e51c8fc56b47435c23b31796643fc1d83a6f` |

The external workspace is
`/private/tmp/meshchan-1e6-review-runtime.p9rFnO04/Meshchan signing runtime`.
CLI PIDs `42576` and `42596` completed offline write and reopen with
verified argv, exit, original stdout, and live SQLite mappings. The App's
actual architecture set and CodeDirectory hashes matched the guest
requirements. App PIDs `49588` and `49697` in guest run
`20261121T121157Z-product-49442` wrote and reopened the fixture and quit
normally. The executor exited zero and released its lock. The paired library
replacement passed with CLI PID `44133` and App PID `49959` in guest run
`20261121T121223Z-product-49859`. Its external
`user modified products/evidence/replacement-receipt.json` has SHA-256
`e4b9f9f99bfff0d1748af1e6ce835b492438bf59ce480555698990e60f99e3c5`.
This workspace and the 47 signing inputs are paired with the
[prior accepted DMG](phase-1e7-dmg.md#prior-accepted-dmg-after-initial-tool-review).

## Initial local candidate before tool review

The following receipts describe the initial tool snapshot and retain their
original status.

### Initially signed RC build 8

The owned local signing run is `build/phase-1e6/local-sign-001/`. It
used the repository checkout at `e36690be02d7a213a6ab391c6f6b903d247e1521`
with separately inventoried working-tree signing inputs. Product compilation
continues to identify recipe 55 at `a29430b608658a8b56d619f641dc8600346b6d27`.
The host used macOS 27.2.1 (26B131) arm64, Xcode 27.2 (27B52), and
`/opt/homebrew/bin/python3` 3.15.2.

The candidate root is
`signed/Meshchan-0.1.0-rc.1-macos-arm64/`, relative to the signing run.
App `0.1.0-rc.1+8`, CLI `0.1.0-rc.1`, Bundle ID
`org.meshchan.meshchan`, and Apple short version/build `0.1.0`/`8`
match the upstream identity. The candidate inventory covers 694 entries
including its manifest. The bounded signature transformation, native loader
graph, AOT correspondence, and original materials passed. The original
materials manifest SHA-256 remains
`335519433a4e48d2e683563d7104b2b84ff35f274a5895bb7f8329a1cd909733`.

Code signature readback covered eight code items and 13 architecture slices.
Each slice reported an ad hoc signature without Authority, Team or secure
timestamp. The App main executable uses Hardened Runtime with
`disable-library-validation`. The CLI main executable also uses
`allow-unsigned-executable-memory`. The frameworks and CLI libraries use
empty entitlements and carry no Hardened Runtime flag.

| Local signing record in `local-sign-001/` | SHA-256 |
| --- | --- |
| `signed/Meshchan-0.1.0-rc.1-macos-arm64/signed-product-info.json` | `5241033d916d87a32928afdb6ee7659f7bd1da7ef97d4ea97d6c622bd5cc851d` |
| `evidence/signing-receipt.json` (`SIGNED`) | `e5c0e324729da45bf38cdb4942fa43e016464a5a761260a57e7bfb7caafab223` |

### Initial independent acceptance and handoff

The `local-adhoc` check completed at 11:47:56 UTC with `PASS` for
upstream admission, signatures, material transformation, CLI, VM App, user
library replacement, and post-runtime integrity. This accepted the initial
1E.6 engineering candidate and its separate manifest and receipt pins.

| Acceptance file | SHA-256 |
| --- | --- |
| `evidence/check-wa4rw1l1/signing-receipt.json` | `755a95c341bf68580c829d26ecf2609f008d001ea648951b8b0ab9ca9823c7bf` |
| `evidence/check-wa4rw1l1/cli-runtime.json` | `aa6b5d9c8fbc0c205a968a29bdfb2c2a6bd31c501713ce034898a77a5e4d5352` |
| `evidence/check-wa4rw1l1/vm-app/runtime.json` | `ab99cdaa033b455399b92c952aa5514e984ca952fa8cbf982de8830e09bb1939` |
| `evidence/check-wa4rw1l1/build-receipt.json` | `62604c97e6c92be96543e697f50ff85087a61f56a9e6514b152a920fd903fc44` |
| `user modified products/evidence/replacement-receipt.json` in the external workspace | `95d5e48d44be82bc511766a4702ca244a727c28762b65c440dee297778793d72` |

The workspace is
`/private/tmp/meshchan-1e6-runtime.vaArAu2r/Meshchan signing runtime`.
The offline CLI reported `meshctl 0.1.0-rc.1`, wrote a draft as PID
`12357`, and reopened it as PID `12364`. Both processes closed storage,
exited normally, and mapped the relocated CLI's SQLite library. Guest run
`20261121T114701Z-product-47452` used the inventory-matched App on macOS
27.2.1 (26B131) arm64. App PIDs `47593` and `47717` mapped the guest
copy's SQLite image, wrote and reopened the fixture, and released storage,
the owner, and the worker on normal Quit. Both PIDs were absent after exit.
The executor exited zero and released its lock.

The modified-library exercise rebuilt libserialport from the candidate's
included source archive and used separate copies. CLI PID `13517` and App
PID `47977` each observed the synthetic empty-list marker in the intended
process. Guest run `20261121T114729Z-product-47881` passed normal Quit,
App PID absence, executor exit zero, and lock release. The final checks
reverified affected signatures and original candidate bytes. The initial
workspace retains both image observations, the SQLite fixture, and
replacement evidence for that run.

## Historical Developer ID route

**November 20, 2026 status: BLOCKED at Developer ID identity preflight.**
The selected upstream engineering package passed its full recheck. An owned
preparation run passed. The signing host's unrestricted
`security find-identity -p codesigning -v` returned
`0 valid identities found`. There is no selected Developer ID Team or
certificate for this candidate. See the [Developer ID guide at the historical source cut](https://github.com/007pig/meshchan/blob/f69c2811e91e4bd698dba81e3194cd563f1d1855/docs/releases/phase-1e6-signing.md).

### Selected input and source identities

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

### Preparation and identity preflight

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

### Locally signed development diagnostics

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

### Final tool checks

`/opt/homebrew/bin/python3 -B -m unittest discover -s tool -p '*_test.py'`
passed all 406 tests on Python 3.15.2. The suite includes 31 new signing,
provenance, runtime evidence, and replacement tests and the existing 1E.5
packaging coverage. The prepared snapshot's 44 signing input modes, sizes,
and SHA-256 digests matched both the live tooling and the retained
`signing-source/` copy. The new Markdown links and anchors and
`git diff --check` passed.

### November 21 review follow-up

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

### November 21 guest lifecycle follow-up

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

### November 21 evidence and output review

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

### November 21 interruption and manifest review

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

### November 21 VM evidence directory review

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

### November 21 log, VM configuration, and local signing review

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

### Historical handoff at the Developer ID evidence cut

The historical route required the maintainer's Developer ID Application
certificate and matching private key in the local signing keychain, the public
certificate SHA-1 and exact Team ID, and a fresh signing output using the
same upstream pins. The signing transformation, formal runtime, library
replacement, and phase acceptance required fresh evidence under the
[Developer ID guide at that cut](https://github.com/007pig/meshchan/blob/f69c2811e91e4bd698dba81e3194cd563f1d1855/docs/releases/phase-1e6-signing.md).
There was no selected signed payload for 1E.7 at that cut. Notarization,
ticket and stapling, DMG, Gatekeeper, public download, installation, and
hardware checks were separate gates. The
[current engineering profile](#current-engineering-profile) supersedes this
handoff.
