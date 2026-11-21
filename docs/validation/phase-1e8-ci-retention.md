# Phase 1E.8 CI and retention validation

## Accepted source and image

The repository base was the PR #46 merge,
`b00807de20cddede3122aa8cfd71b352d0ffbb08`. GitHub reported PR head
`e2d5432171f83b1a9c3e43284bacb1be1e5ba8f6`. The accepted image is the
675,911,154-byte `Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg`
from `local-dmg-008`, based on recipe 55 and product source
`a29430b608658a8b56d619f641dc8600346b6d27`. Its SHA-256 is
`b42021e054e65e47893d84437100a6b9e51a2ea93eb7a060c12e70fdb4a6ca28`.
See the [selected 1E.7 acceptance](phase-1e7-dmg.md#current-reviewed-candidate-and-image)
and the [retention procedure](../releases/phase-1e8-ci-retention.md).

## Historical GitHub records

The authenticated GitHub API queries ran from 15:04:34 to 15:04:42 UTC on
November 21, 2026. The retained
snapshots include the original run, attempt and paginated job and artifact
responses, exact workflow, and attempt-specific log ZIP. All were attempt 1
and completed successfully in both jobs. GitHub listed zero artifacts for
each run.

| Run | Event | Checkout | `check` | `macos-app` |
| --- | --- | --- | --- | --- |
| [44747988036](https://github.com/007pig/meshchan/actions/runs/44747988036) | Push | `a29430b608658a8b56d619f641dc8600346b6d27` | 136328165539 | 136328164805 |
| [44915147891](https://github.com/007pig/meshchan/actions/runs/44915147891) | Push | `e2d5432171f83b1a9c3e43284bacb1be1e5ba8f6` | 136879051561 | 136879051359 |
| [44915191801](https://github.com/007pig/meshchan/actions/runs/44915191801) | Pull request | `b3f698918ccf4f5031bb6357f9378c98696d601a` | 136879183662 | 136879183406 |

The PR run tested its merge checkout, whose second parent was the PR head.
The historical workflow has its own bytes for each checkout. All three runs
used Ubuntu 26.04.1 x86_64 and macOS 15.8.2 (24H232) arm64 and reported Flutter
3.50.0 and Dart 3.14.0. The macOS logs report Xcode 16.4, SDK 15.5 and Apple
Clang 17.0.0. In the product run, the Ubuntu runner logged Python 3.14.4 in
a probe. The frozen macOS Python version and historical Linux compiler
versions were not retained. The Step 7 runs reported CPython 3.15.2 on both
jobs.

| Snapshot | Manifest SHA-256 | Workflow SHA-256 |
| --- | --- | --- |
| Product source | `0682d0c89ac4e752df8611232ec5abfd595048b2f2150f1c52c3139baa7f3659` | `eeef7fe89a6bd97c446cde9f816082ab2f50045253154ab2eaf9905942fbf6a4` |
| Step 7 push | `7b3c4980d8f7f15a9ace62ba068c0dbbc0065c333f1d093e7fff45efa7d7923d` | `a0b5a7c8c8fa48a8b063719bd1be3e52c3e966c75113ccbf5da331d3faf8a591` |
| Step 7 PR merge | `9ca289a6aa0e6fd25c35d4bf01cc4cf1df4647b900da8afd26c4483ddb4135d1` | `a0b5a7c8c8fa48a8b063719bd1be3e52c3e966c75113ccbf5da331d3faf8a591` |

## Selected acceptance and source coverage

The admitted chain is `local-sign-005` → `local-dmg-008` →
`local-dmg-check-009`. The product App identifies as `0.1.0-rc.1+8` and
the CLI as `0.1.0-rc.1`. Apple short version is `0.1.0`, build string
`8`, and the bundle ID is `org.meshchan.meshchan`. The historical image
receipts record the 763-entry payload, eight code items and 13 architecture
slices. Historical App and CLI runtime acceptance used macOS 27.2.1
(26B131) arm64. See the [original-environment recheck](phase-1e7-dmg.md#tests-and-1e8-handoff)
for the original command, pinned inputs, and VM requirements.

| Accepted input | SHA-256 |
| --- | --- |
| Original `SHA256SUMS` | `8f26a0821bb39bd1c93d48e57622164fd4b4eaf87d59d9ac80ae503d1023da53` |
| DMG creation record | `8c108e73e60b9d29a879b489cc6312d65f4cfc6440f5046d891a101006a41245` |
| DMG image payload manifest | `5abc9abee4004a9b9a1d3a8bfdb62e2d52893207308478d95f55b795ca8cdf62` |
| Independent DMG acceptance | `b88f3f1647fe65e1f549e32d00de555b59dba09da366001c530f67626124b71f` |
| Local signed product manifest | `58565d17e1c8659f6a73d6164ea37afabee1b75a03c1b20a01615ade467c18d9` |
| Independent local signing acceptance | `17b203af6191d574d7d77fed472fb04050690aaf87e0b312ef1e02fa6eb474f0` |
| Original engineering package receipt | `ac8e649f3938cab85adf26a6e7c71f51b7c8076560e0f33a8fb9e53f7b092ece` |
| Independent upstream package verification | `3fa4cd3cd2e0c352796a91bccafa3bb33855120dac2937b0ac3c1df124a0e3aa` |

The original packaging record identifies checkout
`3b362ecc6346c3aec8ccee26e571e76b7a0571c8` and the full package verifier
records `2c485289da90dea35c4bc1e8e23c139676d0e7ad`, each with its own
recorded input inventory. The original stage carries the original packaging
snapshot. The independent package verifier snapshot was reconstructed from
`f69c2811e91e4bd698dba81e3194cd563f1d1855` and checked against the full
package verification receipt. The reconstructed `askpass.sh` copy keeps its
recorded `0700` mode.

The signing and DMG records retain their then-current checkout
`e36690be02d7a213a6ab391c6f6b903d247e1521` and recorded working-tree
status. The Step 7 push tested commit `e2d5432171f83b1a9c3e43284bacb1be1e5ba8f6`.
Every bound signing and DMG input matched that commit's bytes and Git
executable class. Original POSIX modes came from the historical snapshots.
The original source tree, build and materials records, and retained input
snapshots keep their respective identities.

## Local checks

The final source was checked on macOS 27.2.1 (26B131) arm64.

```sh
/opt/homebrew/bin/python3 -B -m unittest discover -s tool -p '*_test.py'
git diff --check
```

CPython 3.15.2 at `/opt/homebrew/bin/python3` passed 523 tests in 102.747
seconds. The full log SHA-256 is
`d287d5be7c17f95ca5e7537179faea7fdcd6c0e47418855a32254cb9c24356fa`.
The first attempt under the workspace sandbox was stopped after native
process tests received permission errors. The successful run used native
process observation. Psych parsed the workflow and Bash syntax-checked all
45 `run` blocks. Added local Markdown links and their anchors were checked.

The initial selection reached a dangling VM launch claim in the original
replacement workspace. This executor ownership marker is outside the receipt's
evidence. The final selection includes the replacement products, source,
entitlements, owned SQLite fixture, reports, and logs. The original workspace
and claim were untouched. The real candidate-only preflight passed admission
and its archive round trip, covering 1,118 roots and 8,127 inventory entries
before adding CI and supporting reports. That preflight uses a scratch area.
Its report SHA-256 is
`1cc466d0254435ee5a1875d5af1f5e9cab89187396bbc98c4e92a065f8b83e34`.

## Final retention-tool CI and downloads

The exact retention-tool checkout was
`562ee92663e0206a846dd98cddf8e846e7ce3c29` on the
`codex/phase-1e8-ci-retention` branch. The [push run](https://github.com/007pig/meshchan/actions/runs/44918791179)
was attempt 1. It started at 15:21:56 UTC, completed successfully at
15:34:42 UTC, and was collected at 15:34:45 UTC on November 21, 2026. Workflow
SHA-256 is
`b2dfb01c83296b2e9de168e003e3beec2b05bdd7369baa56da452cd9b13996fe`.
Both job checkouts, report workflow identities, and GitHub's run and attempt
records agree with this source. Both ZIPs were downloaded through the
artifact API. The download matched the GitHub ZIP object size and SHA-256,
and the expected report, workflow, and log members passed strict checks.

| Job and GitHub job ID | GitHub artifact | Bytes | Remote ZIP SHA-256 | GitHub expiry in UTC |
| --- | --- | ---: | --- | --- |
| `check` 136890048199 | [14712764025](https://github.com/007pig/meshchan/actions/runs/44918791179/artifacts/14712764025) | 37,816 | `64e45899377a0d94d431ca90e9659c4a746e7c59c83440f078b95855b4289ef6` | 2026-12-21 15:33:46 |
| `macos-app` 136890047973 | [14713476309](https://github.com/007pig/meshchan/actions/runs/44918791179/artifacts/14713476309) | 60,860 | `f91a44c612f5f68368193b2851a8922ee4e45729f1dc2b28f7e0528b1dfa5276` | 2026-12-21 15:34:34 |

The exact artifact names were
`meshchan-ci-562ee92663e0206a846dd98cddf8e846e7ce3c29-44918791179-1-check`
and `meshchan-ci-562ee92663e0206a846dd98cddf8e846e7ce3c29-44918791179-1-macos-app`.
The requested retention was 30 days. A copy of each ZIP, raw GitHub API
records, and the verified reports and logs is retained through the snapshot.
The external CI snapshot pin is
`a97174d5811ced93795ff95e9ff2e411be2dced797584c15746e95acc3ce46e1`.

The actual runners were Ubuntu 26.04.1 LTS on x86_64 and macOS 15.8.2
(24H232) on arm64. Both used CPython 3.15.2, Flutter 3.50.0 stable, and bundled
Dart 3.14.0. Ubuntu recorded GCC 15.2.0 and Clang 21.1.8. macOS recorded
Xcode 16.4 (16F6), SDK 15.5, and Apple Clang 17.0.0. Hosted Ubuntu ran 523
Python tests with 10 platform skips. Hosted macOS XCTest ran 22 tests with
zero failures.

Use the retained pin to verify the downloaded snapshot offline.

```sh
/opt/homebrew/bin/python3 -B tool/release_ci_evidence.py verify \
  --directory "$PWD/build/phase-1e8/ci-snapshots/retention-final" \
  --source 562ee92663e0206a846dd98cddf8e846e7ce3c29 \
  --run-id 44918791179 --attempt 1 --require-artifacts \
  --workflow-sha256 b2dfb01c83296b2e9de168e003e3beec2b05bdd7369baa56da452cd9b13996fe \
  --snapshot-sha256 a97174d5811ced93795ff95e9ff2e411be2dced797584c15746e95acc3ce46e1
```

The selected input file `build/phase-1e8/rc1-build8-selection.json` has
external SHA-256
`be687e30b98e8e3f7a77f20771808e1e74284c84bfb0389be02b39c15604de07`.
Use this value for `MESHCHAN_SELECTION_SHA256` in the
[seal procedure](../releases/phase-1e8-ci-retention.md#seal-the-selected-image-and-evidence).

## Sealed local object

The stable private parent is
`~/Documents/my_projects/Meshchan Engineering Archive`. The new sealed
object is `RC1 Build 8 - 1E.8` within that parent. It finished sealing
at 15:39:02 UTC on November 21, 2026, after archive-only verification
and rechecking the original input identities and bytes. The tar inventory
has 8,170 members across 1,130 mapped roots. The verifier has 73 separately
inventoried entries. The sealed directory has mode `0500` and its tar,
manifest, and receipt have mode `0400`. The original checksum stays in
the archive under its mapped original path.

| Object | Bytes | SHA-256 |
| --- | ---: | --- |
| `retained.tar` | 8,858,152,960 | `3b630a2225cea00a502c43b1d92712cd565a04d6115a90151418105aae89c3b5` |
| `retention-manifest.json` | 2,175,033 | `c83951e7db5de8313a0dfa84b7e85f5c77dd5947dd631cd7c47e2c758c0e95a2` |
| `retention-receipt.json` | 347 | `76221dc94d40c7f32aaa5933c849fd17b4eadf3aceda907f9475f971dc38fc8c` |

Use the receipt SHA-256 as `MESHCHAN_RECEIPT_SHA256` with
[check or restore](../releases/phase-1e8-ci-retention.md#check-and-restore-from-the-sealed-object).
The sealed evidence has a local copy of each CI snapshot and both new
artifact downloads. The retained copy depends on the local storage volume.
Off-machine backup has not been verified.

## Independent restore and 1E.9 handoff

The restore passed at 15:41:06 UTC on November 21, 2026. It ran the sealed
verifier from the persistent parent with spaces in its path and wrote to
the new `RC1 Build 8 - restored` directory. The macOS profile denied
network and reads of the original checkout, four original temporary
workspace parents, and the historical Python test log. Negative probes
confirmed all six read denials. The verifier used the sealed object, the
new restore and evidence directories, and host OS and Python resources.
Historical absolute paths were resolved only through the archive mapping.

The sibling `RC1 Build 8 - isolation boundary` directory includes the
exact `restore.sb` profile and `probes.json`. Their SHA-256 values are
`f250354b5683675288825435919b11ee34767c5465c7126300c445f656b69199` and
`8ab30365580dab524e5b98356bc9e6576efadfdba2e797cdac2700c44e29b005`,
respectively. The restore used CPython 3.15.2, invoked via
`/opt/homebrew/bin/python3`. It reported its resolved executable as
`/opt/homebrew/opt/python@3.15/bin/python3.15`.

These arguments record the historical restore from the locally created seal.
For a new run, follow the
[authenticated bootstrap procedure](../releases/phase-1e8-ci-retention.md#check-and-restore-from-the-sealed-object)
and choose fresh output names.

```sh
cd "$HOME/Documents/my_projects/Meshchan Engineering Archive"
MESHCHAN_ARCHIVE="$PWD"
MESHCHAN_SEAL="$MESHCHAN_ARCHIVE/RC1 Build 8 - 1E.8"
MESHCHAN_RECEIPT_SHA256=76221dc94d40c7f32aaa5933c849fd17b4eadf3aceda907f9475f971dc38fc8c
/usr/bin/sandbox-exec -f "$MESHCHAN_ARCHIVE/RC1 Build 8 - isolation boundary/restore.sb" \
  /opt/homebrew/bin/python3 -B "$MESHCHAN_SEAL/verifier/tool/retain_release.py" restore \
  --retention "$MESHCHAN_SEAL" --receipt-sha256 "$MESHCHAN_RECEIPT_SHA256" \
  --work "$MESHCHAN_ARCHIVE/RC1 Build 8 - restore evidence" \
  --destination "$MESHCHAN_ARCHIVE/RC1 Build 8 - restored"
```

The restore verified the exact inventory and accepted references, including
the retained observer, SQLite and replacement data. The restored image
matched 675,911,154 bytes and
`b42021e054e65e47893d84437100a6b9e51a2ea93eb7a060c12e70fdb4a6ca28`.
`hdiutil imageinfo` identified a read-only UDIF/UDZO image with HFS+.
`hdiutil verify` confirmed CRC32 `$88EDD0E4`. The container signature
check reported unsigned. Historical runtime, PID and vnode records were
preserved as evidence. Restore-time product execution was outside the
check. The `verification.json` in `RC1 Build 8 - restore evidence` has
SHA-256 `12c3ca8e302865182bfcd9f0a49f62c9c7e213ada9a2f6c0dce4439c02639fcf`.

The restored image and original checksum are mapped to
`inputs/0898-Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg` and
`inputs/0899-SHA256SUMS`. Independent copies under their original names
are available in `RC1 Build 8 - engineering assets`. Both copies passed
the original external pins. The corresponding materials accompany the
App and CLI inside the image. The pinned independent DMG and signing
receipts and their upstream evidence are available from the private seal.

```sh
cd "$HOME/Documents/my_projects/Meshchan Engineering Archive/RC1 Build 8 - engineering assets"
shasum -a 256 -c SHA256SUMS
```

The transfer record `handoff-assets.json` in the restore evidence
directory has SHA-256
`2d80a32ea0e46165259012e8968531bc72481bf31116e247e2be87660a7cab37`.
This local handoff supplies the exact bytes for the 1E.9 engineering
download, clean install, and Beta upgrade. Quarantine, normal approval,
data continuity, and the oldest supported macOS remain pending. Real
USB and RF acceptance, existing serial stability limits, and public
release gates carry forward unchanged.

## Branch review revalidation

The reviewed verifier restored the existing sealed object from an independent
tool copy under the recorded read-isolation profile. It verified the
original acceptance chain, exact archive inventory, and DMG structure.
The temporary restore's DMG matched the original SHA-256. The retained
`RC1 Build 8 - review restore evidence/verification.json` report has
SHA-256 `0b02e28ab97958998be8f2a36dbdb3cf8be72459fdffa3e5e8c6a16e5f654c66`.

The standalone bootstrap also verified the sealed historical verifier and
completed an isolated check, with its scratch extraction removed. Its
`RC1 Build 8 - review bootstrap evidence/verification.json` report has
SHA-256 `1f1b97479098862ff2466d719c180c978b78c5d21b23b8c3d3632c639bc9d14f`.
A separate bootstrap invocation rejected an output inside the original
checkout before creating a work or restore directory.

All four original CI snapshots verified again. Both job downloads for run
`44918791179` matched the independently read commit digests for
`pubspec.lock` and `tool/ci_evidence.py`. The historical seal and its
external receipt SHA-256 remained intact.

The final review changes passed all 543 local Python tool tests in 111.134
seconds with CPython 3.15.2 at `/opt/homebrew/bin/python3`. The
`build/phase-1e8/review-python-final-suite.log` SHA-256 is
`6969b4cafe56b90a9a6086ba166e9b2c53a263d4258d46ca49b26efdca7c9052`.

### Follow-up branch review

The follow-up review reverified all four CI snapshots and the two previously
downloaded job artifacts. The artifact toolchain descriptions matched their
captured probes. Historical VM and replacement invocations were checked
against the retained candidate paths and manifest pins without accessing
the private staged VM configuration.

The final verifier independently restored the same sealed object under the
original read-isolation profile. The restored image matched the original
SHA-256 and passed macOS UDIF/UDZO, HFS+, and CRC32 verification. The
temporary restore was removed after verification. The
`RC1 Build 8 - follow-up review recovery evidence/verification.json` report
has SHA-256
`366b8f77531101610c8a3a7b40a401172924003122c77a64b7ddece5e4881320`.
The original external receipt pin matched after the restore.

All 552 Python tool tests passed in 111.435 seconds with CPython 3.15.2 at
`/opt/homebrew/bin/python3`. The
`build/phase-1e8/followup-review-python-suite.log` SHA-256 is
`dccf86cf1dcaad5a38583755b5437c8fbd00384614106124337f08d1358e5d22`.

### Entry-point and historical image review

The CI reporter preserved the captured failed-step log when the lockfile was
absent from either the commit or the worktree. The reported evidence was
invalid in both cases. All four pinned CI snapshots and both archived job
downloads verified again. The revised standalone bootstrap authenticated
the existing verifier tree and launched its CLI, which displayed the check
and restore commands.

The current verifier restored the existing sealed object under the original
read-isolation profile. It checked the historical `hdiutil` and `diskutil`
outputs against both the creation and independent acceptance receipts,
including the selected image path, format, CRC, and mounted read-only
volume. The restored DMG independently matched the original SHA-256 and
passed native macOS image verification. The temporary restore was removed.
The `RC1 Build 8 - entry-point review evidence/verification.json` report has
SHA-256
`d2a0bd54f602fcdf36e65c2e4f904aadd07d24965027ad12c5982c68403490fc`.
The original external receipt pin matched after recovery.

All 557 Python tool tests passed in 108.656 seconds with CPython 3.15.2 at
`/opt/homebrew/bin/python3`. The
`build/phase-1e8/entry-point-review-python-suite.log` SHA-256 is
`8ae0ded7c0605a726c50f4b7ebc228627eba50c9618d433673ad6ca519f8132d`.

### Post-push branch review

The pushed checkout `117a82229036a59e54f7b0eb2a2ec697c781b163` produced
a 76-entry verifier snapshot. The standalone bootstrap authenticated the
snapshot and launched its CLI from a private copy.

The follow-up verifier bound the original `codesign` argument lists and raw
observations to the candidate's code items and architecture slices. Both
historical image records verified eight code items and 13 slices each.
The revised verifier then restored the original object under the recorded
read-isolation profile. The restored image passed native macOS verification
and matched the original DMG SHA-256. The original receipt pin also still
matched. The temporary recovery was removed. The
`RC1 Build 8 - post-push review evidence/verification.json` report has
SHA-256
`75a2232570d7e1728dcc0883f2f65b9a46b4a18fa8edecf0a4e6ef052fefdc91`.

All 559 Python tool tests passed in 121.071 seconds with CPython 3.15.2
at `/opt/homebrew/bin/python3`. The
`build/phase-1e8/post-push-review-python-suite.log` SHA-256 is
`5e9ec85de068c2033fca3e4d65dbf99cc62751e4682e71beb02d5e5dbcf13760`.

The [push CI run for `117a822`](https://github.com/007pig/meshchan/actions/runs/44924912092)
completed successfully on attempt 1. Job `check` uploaded artifact
`14715558197` and job `macos-app` uploaded artifact `14715244122`. Both ZIPs
were downloaded and verified against GitHub's sizes and SHA-256 values.
The embedded workflow, reports, logs, and input digests matched the pushed
commit. The snapshot at `build/phase-1e8/ci-snapshots/review-117a822` has
external SHA-256
`dc2908f1c51cc93c9fc77dec242c57fa2af79c9b89e515ecb066a58d3b62e232`.
The two follow-up fixes were verified in the local working tree.
