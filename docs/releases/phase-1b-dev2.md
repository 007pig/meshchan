# Phase 1B local development candidate 0.1.0-dev.2

Initially recorded November 10, 2026; authorized H2/H7 follow-up on November 11.
Build ID:
`0.1.0-dev.2-macos-arm64-20261110T193252Z`.
Recommendation: **development-with-known-limitations**.
The [hardware record](../hardware-validation.md#1b9-usb-and-openhop-acceptance-on-november-10-2026)
retains every actual attempt and distinguishes initialization from RF evidence.

| Dimension | Actual status | Scope |
| --- | --- | --- |
| Software gate | PASS | Locked resolution, format (50 Dart files, no changes), fatal-info analysis; 180 core/72 CLI tests; three fresh sequential bundles; 69 macOS source/AOT smoke checks. |
| B development compatibility | H0 PASS; limited RF interoperability observed | Repeater 1.1.5.dev231/Core 1.1.4.dev9 differs from reviewed Core 1.1.3. Real WS/session cleanup and 95-second passive window passed after another client was released. Exact configured idle timeout remains unknown; REST running=false discrepancy is retained. |
| A candidate USB initialization | PASS | Exact selected port, actual native executable and dylib, protocol 14, firmware report v1.18.0-81dbae5, real cleanup, exit 0. |
| Basic Direct RF round trips | Latest H0-H7 PASS with retained failures | A slot 1/B slot 3, zero-hop Direct. H2 local acceptance and H7 cancellation passed the authorized B-command-15-second/A-5-second comparison on November 11. Every earlier failed trial and initialization remains. |
| Specified relay path | NOT_RUN | Independent paths not supplied. Multi-radio Fabric is not a claimed relay acceptance. |
| Active responder cancellation / physical unplug | H7 PASS with earlier FAIL / NOT_RUN | Later B exact PONG and active A preceded SIGINT; A exit 130, correct first cause and actual cleanup. Earlier missing-gate failure remains; physical unplug has not run. |
| Final archive integrity | PASS | Final tar.gz actually extracted outside checkout; member checksums/layout/execute mode/native hashes and four no-device process checks verified. See external verification JSON. |
| Public redistribution | NOT_READY | Local unsigned-by-Developer-ID candidate; existing license/materials/runtime-notice, signing/notarization, download quarantine and clean-machine work remains. |

## Provenance and retained output

Starting worktree: clean `master` at
`40ab5bcd5638751f4b2362b05792e0de74c92f62`, including PR #16 head
`bbe2efbd34aa52d3d25bf7c5106e17ae1609cc32`. The candidate is built from this
commit plus recorded uncommitted compilation inputs. `build-info.json` does not
label the old commit as a clean dev.2 source. Product changes are the workspace
version/constraint update only; no production state machine, USB defaults,
protocol, cleanup contract, or external dependency changed. Historical dev.1
records remain historical. No production defect fix is claimed.

All paths below are relative to the checkout root:

```text
build/phase-1b9/20261110T193252Z/
  software-gate.json
  compilation-inputs.json
  hardware/execution-plan.json
  hardware/H0-results.json
  hardware/H0-B-prepared-results.json
  hardware/deployment-metadata.json
  hardware/radio-and-timeout-metadata.json
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z/
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z.tar.gz
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z.tar.gz.sha256
  archive-verification.json
```

The candidate includes the entire product bundle, README, build-info,
acceptance summary, original notices/licenses and SHA256SUMS. It excludes the
observation/probe bundles, peer/tool code, SDK/Python/pub cache, credentials,
channel configuration and original hardware logs. SDK metadata is a manifest
value, not a shipped SDK. The separate builds remain in the ignored build
folder for developer inspection.

Native hashes, recorded before H0 and rechecked after final extraction:

| File | SHA-256 |
| --- | --- |
| `bin/meshctl` | `ca9f250eb31a8c9cef71ae24730100c2c7337e5992bd650e199a19d38f01d356` |
| `lib/liblibserialport_plus.dylib` | `6a3fbe15228b7e860b0cd9ec3fd8a60b55f0e40fbbe2ef3b5cef0f3a7ea4a56d` |

`tool/package_dev_candidate.py` verifies captured inputs and tested native
hashes, retains original dependency notices, produces an archive and external
hash sidecar, then extracts that final archive to a fresh `/private/tmp` directory.
The package SHA256SUMS covers ordinary files except itself; its archive hash is
external. `archive-verification.json` records the actual extracted path, count,
hashes, modes, commands/exits and UTC verification time. Help/version/invalid
argument checks use the extracted executable from an outside-checkout cwd.
Original archive SHA-256 (preserved):
`4d6b0eeb06e119120e51eb197d5a0ffcf77b1a057c6a978050a42d78533e0333`.
Verification completed at `2026-11-10T19:47:00.186398Z`: 32 ordinary files
verified after extraction to
`/private/tmp/meshchan-dev2-extracted-8c1tmpoj/0.1.0-dev.2-macos-arm64-20261110T193252Z/`.
The extracted version/help checks exited 0; missing info/ping arguments each
exited 64 before device access. No no-device command is described as USB/RF evidence.

## Compatibility and evidence limits

Actual A/B RF reports agree on 869.618 MHz, BW 62.5 kHz, SF 8, CR 4/8; A TX is
10 dBm and B TX is 16 dBm. openHop exposes slots 0-7. A later finite read-only
audit found eight matching 16-byte Companion key representations. The selected
trial pair was A slot 1/B slot 3, with actual RF receipts and exact PONGs.
The actual host uses Fabric bridge mode with two
modem_tcp radios, origin_tx=all, default=local. Configured endpoint labels do
did not establish which physical modem was distinct from A. After that snapshot,
the user confirmed the remaining local modem is a separate physical device and
reported link off; these are user-provided facts. No radio configuration
was changed to fit a two-device assumption. Companion idle timeout has no
explicit config value. The user subsequently identified the modem as openHop
1.4.0 on Heltec V4.3; independent firmware image/source verification is incomplete.

The source-only [openHop peer guide](../openhop-acceptance.md) explains JWT
acquisition, secret references, queue consumption, single client ownership,
finite commands and readiness. B local write means only local WS submission;
Companion OK is separate, and only exact PONG establishes an application round
trip. The peer shares Meshchan core, so it is not an independent protocol oracle.
Product CLI support remains USB-only. No HTTP/WS/file/IPC payload return path is
used to manufacture RF evidence.

The initial B source command failed before networking because the Apple-first
PATH was omitted (exit 255). Its record is retained. Correcting only that process
environment allowed the planned single B session check; A was not rerun. This
does not hide an RF failure or add a retry loop. Historical incomplete USB bodies
and failed H10 startups remain unresolved; this new H0 success proves no repair
or stability percentage.

Both current arm64 native files passed read-only codesign verification; the
product executable reports ad-hoc signing, no TeamIdentifier, no Developer ID.
There is no notarization/clean-machine/download-quarantine evidence. Original
libserialport_plus MIT and native LGPLv3-or-later notices, production-graph
package notices and Dart SDK LICENSE are included. They are not a complete legal
compliance determination. Meshchan's project license is still unselected;
corresponding native source/build/relinking materials, incorporated GPLv3 terms
and complete Dart runtime third-party notices still require review. No license
was selected, security setting changed, tag pushed, GitHub Release created,
binary uploaded, or signing identity used.


## Later read-only metadata follow-up

After this archive was finalized, a separately requested
[finite channel audit](../hardware-validation.md#read-only-channel-audit-on-november-10-2026)
found eight A/B matching 16-byte Companion key representations. Two preceding A
initialization timeouts remain in the record. A development-only WS cleanup
correction then waited for receive EOF beyond sink close, with 84 CLI tests and
an independent B-only live cleanup check passing. No product bytes, archive or
SHA sidecar changed, and no new source helper is retroactively included in the
old build manifest. The packaged acceptance summary remains its earlier snapshot.
The available channel mappings are now known within the audit's readback scope;
selected-pair, physical path and effective idle-window prerequisites were still
pending at that earlier snapshot. The subsequent actual matrix is recorded below.

## Direct RF snapshot on November 10

The [complete dated record](../hardware-validation.md#direct-rf-matrix-on-november-10-2026)
retains initial client evictions, the user's MeshCore One client release, a
95-second passive control-window observation, all H1-H7 attempts, and a finite
H2 follow-up. Initial H1/H3/H4/H5/H6 passed. H3/H4/H5 exact PONG RTTs were
3,538,069 / 4,574,680 / 4,762,750 us, with 15 / 0 / 131 content bytes.
H2 still failed B local acceptance despite A receiving matching structural
metadata. H7 failed before the exact-PONG gate, so no cancellation signal was
sent. Every started session completed actual cleanup. The application send
attempt count was 11 of the original 12 ceiling; the separate command-budget
comparison proposal is pending approval and is not an executed result.

The later complete CLI suite passed **88 tests**, including passive-window and
unknown-timeout validation. No product source input or native asset changed.
The older archive and its H0-only manifest remain intact; an acceptance-metadata
revision retains the same native files and original notices while documenting
these later facts. Its exact path/hash/extraction check is recorded below when
the revision is produced. Source-only tools and per-attempt logs stay outside
the product package. No later source helper is falsely attributed to the old
compilation snapshot. This remains development-with-known-limitations, with
specified relay paths/physical unplug NOT_RUN and public distribution NOT_READY.

### RF acceptance metadata archive, actually verified

The original H0 archive above remains byte-for-byte unchanged. The later revision
was produced and verified at `2026-11-10T20:54:23.032188Z`:

```text
build/phase-1b9/20261110T193252Z/
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261110T205422Z/
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261110T205422Z.tar.gz
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261110T205422Z.tar.gz.sha256
  archive-verification-rf-20261110T205422Z.json
  latest-archive.json
  hardware/rf-matrix-20261110T202035Z/rf-summary.json
```

November 10 revision whole-archive SHA-256:
`600268d2df82591e2cc308a69f89701c96636f4ceec855575caaca2afaf47176`.
The final tar.gz was actually extracted to
`/private/tmp/meshchan-rf-extracted-r_ufqrbl/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261110T205422Z/`.
All 32 ordinary-file checksums (excluding SHA256SUMS itself), exact member layout,
0755 native modes, original product/native hashes and 27 original notice/license
files were verified. Extracted version/help exited 0; missing info/ping parameters
exited 64 from an outside-checkout cwd. No device was opened by these checks.
The old archive still hashes to `4d6b0eeb06e119120e51eb197d5a0ffcf77b1a057c6a978050a42d78533e0333`.

The revision retains the original native compilation-input snapshot and explicitly
records `nativeRebuiltForRevision: false`. Later source-tool hashes and RF evidence
are separate manifest fields. No openHop helper, observation/acceptance probe,
SDK, Python, credentials, channel configuration or raw hardware logs are packaged.
This integrity PASS leaves the H2/H7 failures and distribution limits intact.

## Authorized H2/H7 comparison on November 11

The user approved the pending finite comparison with cumulative application
send ceiling 15, B command=15 seconds and A command=5 seconds. All original
limits/routes/slots and production defaults otherwise remained unchanged.
The [dated evidence](../hardware-validation.md#authorized-command-budget-comparison-on-november-11-2026)
retains three A initialization failures in the first H2 invocation, which sent
nothing, then an H7 pass, and a final H2 pass with one preceding A initialization
failure. H2 used its still-unused one-send allocation only once. H7 used two
application sends, obtained an exact PONG (RTT 5,468,891 us), then signaled the
still-active A; exits were A=130/B=0 with correct cause and actual cleanup.
H2 exits were 0/0 with B local write/OK/acceptance and A expected structural
receipt, finite duration and actual cleanup. H2 does not prove full payload
bytes or sender identity from A's output.

Cumulative actual application attempts: **14 / 15**. Latest basic results are
**PASS_WITH_RETAINED_FAILURES**; H0-H7 each have a passing record across the dated
trials and explicit budgets. Earlier failed trials and all initialization
failures remain. No success rate or causal fix from the larger B budget is
inferred, and historical USB findings remain unresolved. The exact configured
idle timeout is still unknown; the earlier passive 95-second window is dated
observational evidence. No product/native file was changed or rebuilt. Existing
software-gate results remain associated with their original native hashes.

The November 10 archives above remain preserved snapshots. A new metadata
revision records this comparison and the retained failures without including
credentials, configs, raw device logs or development tools. The local candidate
remains development-with-known-limitations; relay paths and physical unplug are
NOT_RUN, and public distribution is NOT_READY.

### Comparison archive, actually extracted on November 11

The new complete product candidate and final archive are retained at:

```text
build/phase-1b9/20261110T193252Z/
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T052311Z/
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T052311Z.tar.gz
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T052311Z.tar.gz.sha256
  archive-verification-rf-20261111T052311Z.json
  latest-archive.json
```

Whole-archive SHA-256:
`ac278ca7b2cde0fad2f618c8efe603d2ea89b2fc804961599e28a0de9d8093d7`.
At `2026-11-11T05:23:11.901971Z`, this final tar.gz was actually extracted to
`/private/tmp/meshchan-rf-extracted-_cs1d7hm/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T052311Z/`.
Verification passed all 32 ordinary-file checksums, exact layout, native 0755
modes, original tested product/native hashes, 27 unchanged notice/license files,
and extracted version/help/missing-info/missing-ping checks with exits 0/0/64/64.
The external verification records RF-summary hash
`be15dbfc01b18a8c64c629f012fc066a5c1135cc64f25f802ea98cc0451193e9`.
Both earlier archives were separately checked unchanged. No production source
input or native binary changed, and `nativeRebuiltForRevision` remains false.
The comparison summary records approval, per-case allocation and all retained
failed trials; the packaged human summary also preserves initialization failures.

## Development-tool review fixes and metadata revision on November 11

Three later source-only review fixes address raw read-failure send accounting,
WS close before open/with paused public delivery, and matrix operation/response
limits checked before device-process startup. The [software follow-up](../development.md#development-tool-review-fixes-on-november-11-2026)
records the reproductions and full **91 CLI / 6 Python** passing tests, clean
fatal-info analysis and 56-file format check. Python tests were added to the
existing CI job; remote CI was not run. Product/core inputs and both tested
native hashes are unchanged, so no native rebuild or new hardware run occurred.
The real RF trials retain their earlier helper hashes; later helper source was
verified offline only. Recounting actual records still yields 14/15 attempts.

A new complete product metadata revision was actually extracted and verified
at `2026-11-11T05:44:05.570303Z`:

```text
build/phase-1b9/20261110T193252Z/
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T054404Z/
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T054404Z.tar.gz
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T054404Z.tar.gz.sha256
  archive-verification-rf-20261111T054404Z.json
  review-fixes-20261111T054035Z/software-followup.json
  review-fixes-20261111T054035Z/retained-evidence-verification.json
```

Archive SHA-256:
`2e6f1c97ec405246e666f5e93f5e30e3c625324393f493f6d2760c2b51c26607`.
Fresh outside-checkout extraction:
`/private/tmp/meshchan-rf-extracted-0cv75a69/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T054404Z/`.
The final archive passed 32 ordinary-file checksums, exact layout, 0755 native
modes and original native hashes, 27 unchanged notices/licenses, and four extracted
no-device checks with exits 0/0/64/64. The RF-summary hash remains
`be15dbfc01b18a8c64c629f012fc066a5c1135cc64f25f802ea98cc0451193e9`.
All three earlier archives were checked unchanged. Tools, configs, logs and
credentials remain excluded. The candidate stays development-with-known-limitations;
relay paths, physical unplug, historical USB repair and public-distribution
limits are unchanged.

## Settlement/native-evidence review revision on November 11

A second Python-only follow-up fixes failed/pending process settlement and
native evidence attribution. Every started finite peer is observed before the
runner stops; partial failed/blocked cases retain known sends and uncertainty.
The summary now checks per-execution native captures against each other and the
current bundle before emitting a report. Changed/missing/mixed evidence cannot
be assigned a passing hardware result. See the
[dated software record](../development.md#settlement-and-native-evidence-fixes-on-november-11-2026).

The complete Python suite passed **17 tests**. No Dart/product input changed;
the earlier 91 CLI result remains explicitly earlier evidence, not a new run.
The new independent summary preserves 11 trials, four failed trials, the latest
outcomes/exits/RTTs, and **14/15** application sends, with five captured native
plans. The old RF summary remains unchanged; no new hardware/API connection,
consuming read, signal or RF send occurred. All four prior archives were checked
unchanged. Fixed Python source was verified offline only.

A new complete product metadata revision was generated and actually extracted
at `2026-11-11T06:24:53.098406Z`:

```text
build/phase-1b9/20261110T193252Z/
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T062452Z/
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T062452Z.tar.gz
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T062452Z.tar.gz.sha256
  archive-verification-rf-20261111T062452Z.json
  review-evidence-fixes-20261111T061833Z/software-followup.json
  review-evidence-fixes-20261111T061833Z/rf-summary-verified.json
```

Archive SHA-256:
`ed62904f0154d93ac76d3cb8597506fd623e195eef00e3217380eac7bfba8c83`.
Fresh extraction directory:
`/private/tmp/meshchan-rf-extracted-5k108r8n/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T062452Z/`.
Verification passed all 32 ordinary-file checksums, exact layout, 0755 native
modes and original native hashes, 27 unchanged notices/licenses, and extracted
version/help/missing-info/missing-ping exits 0/0/64/64. Build-info identifies the
new separately verified RF summary (SHA-256
`328a8a554579de8c21a619c776c2deba6d702972e27753738acacf2c8bcdb67a`),
without replacing the original report or relabeling the earlier tool source.
The candidate remains development-with-known-limitations, with specified relay,
physical unplug, historical USB and public-distribution limits unchanged.

## Later process/input-schema software follow-up

The [interrupted-run/configuration review](../development.md#interrupted-runconfiguration-review-fixes-on-november-11-2026)
fixed process metadata omitted from partial result summaries, leading-zero
receive-channel parsing after execution, and flat probe report input. Local
verification passed **25 Python tests and all 91 CLI tests**, including the
review environment's blocked loopback cases, with clean fatal-info analysis
and a 56-file zero-change format check. Existing actual evidence reconciled
23 process files, 11 trials and five native captures, preserving the same four
failed trials, latest outcomes/exits/RTTs and 14/15 application-send accounting.
Saved actual probe stdout also generated an offline plan without a wrapper or
new observation; the plan was not executed.

Product/core compilation inputs and executable/native hashes remain unchanged.
No new hardware/API access, RF send or product rebuild occurred. All five existing
archives and the original RF summary remain unchanged. The most recent product
archive above stays its original dated snapshot; these package-excluded source
tool fixes and their new software validation are recorded separately at
`build/phase-1b9/20261110T193252Z/review-config-fixes-20261111T065713Z/`.
No later source is retroactively attributed to the real RF trials.

## Ledger, session and original-archive review revision

The [next offline follow-up](../development.md#ledger-raw-session-and-archive-provenance-fixes-on-november-11-2026)
passed **31 Python tests and all 92 CLI tests**, clean fatal-info analysis and
a 56-file zero-change format check. It fixes omitted unknown execution directories,
raw OK-then-session-failure success reporting, and archive revision provenance.
Original RF evidence still accounts for 11 trials, four failed trials, 23 process
files, five captured native plans and 14/15 application sends. No device/API access
or RF send occurred; current helper source was verified offline only.

The reviser now verifies and extracts the original tar.gz directly against its
external whole-archive/native/checksum verification before copying the bundle.
Regenerated sibling delivery metadata cannot substitute a different executable
while claiming no rebuild. The original archive remains SHA-256
`4d6b0eeb06e119120e51eb197d5a0ffcf77b1a057c6a978050a42d78533e0333`.
All five earlier archives and the original RF summary were checked unchanged.
Product compilation inputs and native hashes are unchanged; no rebuild occurred.

The new complete metadata archive was actually extracted and verified at
`2026-11-11T09:22:55.128828Z`:

```text
build/phase-1b9/20261110T193252Z/
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T092254Z/
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T092254Z.tar.gz
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T092254Z.tar.gz.sha256
  archive-verification-rf-20261111T092254Z.json
  review-ledger-provenance-20261111T092140Z/software-followup.json
  review-ledger-provenance-20261111T092140Z/original-archive-source-verification.json
  review-ledger-provenance-20261111T092140Z/rf-summary-verified.json
```

Archive SHA-256:
`83ee30d543de0e5d4f1503338ad4da8b6dd890d173c0d78640db480ec8aa8e07`.
Fresh extraction:
`/private/tmp/meshchan-rf-extracted-ret2z49d/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T092254Z/`.
The final archive passed all 32 ordinary-file checksums, exact layout, native
0755 permissions, the original tested native hashes, 27 unchanged notice/license
files and extracted version/help/missing-info/missing-ping exits 0/0/64/64.
The external record binds the separately verified RF-summary hash
`2b7e30fe5ae24c9d55130f1bdb6643c8689f1d433c6f79668ba4cfa535010ab3`.
Tools, credentials, configs and raw device logs remain excluded. Status remains
development-with-known-limitations; specified relay paths, physical unplug,
historical USB explanations and public-distribution limits are unchanged.

## Python 3.15 verified archive follow-up

The user requested the latest installed stable Python 3.15 or newer for future
local scripts. `/opt/homebrew/bin/python3` reported **3.15.2**. The interpreter
selection, separate Apple Clang PATH and policy are documented in the
[developer guide](../development.md#local-python-toolchain) and project AGENTS.md.
No interpreter installation/upgrade or global setting change occurred.

The sequential gate was rerun with Python 3.15.2 selected: **31 Python tests,
all 92 CLI tests**, clean fatal-info analysis, 56-file zero-change formatting
and independent retained-evidence summary. Core/product/native inputs remain
unchanged; hardware was not rerun. The 11 trials, four failed trials, 23 process
files, five captured plans and 14/15 sends retain their original evidence.

The latest complete product metadata revision was created by that interpreter
from a fresh verified extraction of the original tar.gz and verified at
`2026-11-11T09:29:41.473093Z`:

```text
build/phase-1b9/20261110T193252Z/
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T092940Z/
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T092940Z.tar.gz
  delivery/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T092940Z.tar.gz.sha256
  archive-verification-rf-20261111T092940Z.json
  review-python315-20261111T092825Z/software-followup.json
  review-python315-20261111T092825Z/python-toolchain.json
```

Archive SHA-256:
`f22aaacee76fb7f49baebf19d94f583ccce2d082d3d24825414207b42f4ec4ed`.
Actual final extraction:
`/private/tmp/meshchan-rf-extracted-c3s5g8qx/0.1.0-dev.2-macos-arm64-20261110T193252Z-rf-20261111T092940Z/`.
All 32 member checksums, exact file layout, original tested native hashes,
0755 native permissions, 27 original notice/license files and four extracted
no-device checks (exits 0/0/64/64) passed. The verification binds RF-summary hash
`4729b226ffc112674a8f405e16a64f673085c1e90b74b61bb7d58b4c3d0e7d52`.
All six prior archives remain unchanged. Current helper code was tested offline
only. Status remains development-with-known-limitations, with relay, physical
unplug, historical USB explanations and public-distribution limits unchanged.

## Later channel-audit source-only follow-up

The [channel-audit race fix](../development.md#channel-audit-final-query-failure-fix-on-november-11-2026)
retains a transport failure following the final channel reply and reconciles it
before endpoint success or opening B. Three regressions and the full local gate
passed: 95 CLI tests (all loopback cases executed), 31 Python tests under 3.15.2,
clean fatal-info analysis and zero-change formatting. No product/core/native
input changed, no hardware/API connection or RF send occurred, and no archive
was regenerated. The archive above remains its actual earlier software snapshot;
later tool hashes and logs are separate. Original evidence still retains
11 trials, four failed trials and 14/15 sends, without attributing historical
device results to the corrected helper.

## Later protocol-input and evaluation-accounting follow-up

The next [offline review fixes](../development.md#protocol-input-and-evaluation-accounting-fixes-on-november-11-2026)
retain protocol faults after the final channel reply, validate required evaluation
metadata before execution, and persist settled records/send counts if evaluation
unexpectedly fails. The local gate passed 97 CLI tests including all loopback
cases, 34 Python tests using 3.15.2, clean fatal-info analysis and unchanged
formatting. Product/core/native inputs, all seven archives and original hardware
records are unchanged; no hardware/API/RF execution or archive revision occurred.
The current product archive retains its earlier software snapshot. Updated
development source hashes and logs remain separate from historical 14/15-send
evidence, with all four failed trials retained.

## Later content, ledger and interpreter follow-up

The [Python-only review fixes](../development.md#content-invocation-ledger-and-interpreter-fixes-on-november-11-2026)
bind content metadata to initiating arguments, enforce/check the actual 131-byte
Direct H5 boundary, reconcile cached counters with every invocation and preserve
the selected interpreter in child tests. All 41 Python tests passed using 3.15.2;
all 35 observed Python children used that same interpreter despite a system-Python
PATH fallback. The separately validated historical summary still retains 14/15
sends, 11 trials, four failed trials and unchanged latest results. Product/native
inputs, original evidence and all seven archives remain unchanged. Dart/core
gates were not rerun, no hardware/API/RF access occurred and no archive was revised.
The existing candidate continues to represent its original dated software snapshot.

## Later runner cancellation, exit and empty-content follow-up

The [next Python-only review fixes](../development.md#runner-cancellation-exits-and-empty-content-fixes-on-november-11-2026)
retain SIGINT through finite peer settlement/evidence persistence, return a
nonzero aggregate exit for failed acceptance, and enforce H4's zero-content
boundary. All 46 Python tests pass under 3.15.2; all 40 observed Python children
use that interpreter. Synthetic cancellation preserves both peer records, send
counts and actual cleanup facts before exit 130, without extra peer signals or
forced termination. A later accepted case cannot erase an earlier failed exit.
Product/Dart/core/native inputs, all seven archives and original hardware records
remain unchanged. No new hardware/API/RF execution or archive revision occurred;
the historical summary retains 14/15 attempts and all four failed trials.
