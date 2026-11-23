# Phase 1E.12 publication validation

The November 23, 2026 review used the frozen macOS arm64 Build 10 image from
`c5cd5021da5e62c60127678b650d970721263296`. It contains Meshchan App
`0.1.0-rc.1+10` and the complete `meshctl 0.1.0-rc.1`. The
[1E.11 validation record](phase-1e11-release-materials.md#frozen-build-10-closeout)
records the original build, independent Safari first install, offline runtime,
and tested replacement-library scopes.

| Gate | Result |
| --- | --- |
| Exact-source CI | PASS. Both `check` and `macos-app` succeeded on push attempt 1 for the frozen commit. GitHub's original attempt log ZIP and both job artifact ZIPs were downloaded and verified offline. [Exact-source evidence](#exact-source-ci-and-retention) |
| Durable archive and independent restore | PASS. The full seal passed archive-only verification. An independent restore with the original inputs denied recovered the exact frozen image and CI evidence. [Retention evidence](#exact-source-ci-and-retention) |
| Historical Beta Finder upgrade | PASS. The recovered Beta inputs passed the historical verifier. Native Finder Replace upgraded the same App path from Beta build 5 to RC build 10, and the offline GUI, CLI, and SQLite checks established continuity. [Measured upgrade](#historical-beta-finder-upgrade) |
| Same-image USB and RF | PASS. The restored Build 10 passed USB Device Check, the A1/B3 read-only audit, one exact PING/PONG, active Cancel, normal Quit, and independent resource-release and closed History checks. [Successful host hardware verification](#same-image-host-hardware-verification) |
| GitHub prerelease and public download | PASS. All nine anonymous downloads matched their approved pins and both checksum lists. The downloaded image, materials, CLI offline fixture, and VM App Save, Quit, and reopen passed. [Public evidence](#public-release-and-anonymous-download) |

All nine original proposed attachments and 31 directly pinned private
evidence files matched their recorded bytes and digests. The existing staging
check passed with both checksum lists in `sh` and `zsh`. An independent
replay checked the receipt chain with the ten historical source document
paths mapped to the committed bytes in the frozen checkout. The extracted
App, CLI, and two CLI libraries passed strict signature checks. All 284
listed materials matched the independently extracted image inventory.

| Original attachment pin | SHA-256 |
| --- | --- |
| DMG (669,400,332 bytes) | `0f7232479e33cdfb28862b2253bfdd92aad623f985e4fbe9a89989cab949e4bb` |
| Public signed-product manifest inside the image | `11ce81325adf10da9a571167f3db42087d6ca7d03ca212631ab815827889e04e` |
| Public image inventory inside the image | `3c133cb18451e9c9b32997d571138ec9e85f51b556cf7b775985f1bbff7686ff` |
| Original proposed `release-manifest.json` | `cb06e35c3d3bf813f090434aacb6cb3f53e1835f21d75b96d47316e2af096862` |
| Original proposed `RELEASE-SHA256SUMS` | `78d914eab58cb4cfe3611e95f880fd399fa9c8f791bb21e4dfd7be694229002e` |

Local checks used CPython 3.15.2. The pins above retain the original
proposed attachment identity. The final manifest and outer checksum were
frozen separately after the four candidate-specific gates passed.
[Publication handoff](../releases/phase-1e12-publication.md)

## Exact-source CI and retention

The source checkout and workflow identity matched the frozen Build 10 in
the original attempt log archive. The successful `check` job
`137780578098` produced artifact `14832720137` and `macos-app` job
`137780577714` produced artifact `14831334677`. Both downloaded ZIPs matched
the GitHub sizes and SHA-256 digests. The offline verifier passed the full
artifact snapshot and the role-compatible product and DMG tool snapshot.
The original attempt `logs.zip` in both snapshots has SHA-256
`915af5e8fba56b83e7a457d96e5abf1a1b4de7fc2080bc45546043bc87e4ee1e`.
[Actions run 45199985149, push attempt 1](https://github.com/007pig/meshchan/actions/runs/45199985149)

The first recovery used a partial archive of the proposed assets, selected
historical acceptance evidence, recovered Beta inputs, and then-available CI
observations and decoded job logs. Its separate restore checked 978 files
with the network and original input roots denied. The restored image matched
the frozen size and digest and passed `hdiutil verify`.

The full seal preserves 8,983 manifest entries, including 6,739 regular
files and 120 symlinks, from 2,274 mapping roots. Sealing passed
archive-only verification. A standalone verifier restored the seal outside
the checkout with the network disabled and nine read-denial rules covering
all original mapping roots. The restored DMG matched the frozen byte count
and SHA-256, and its unsigned HFS+ image in UDZO format passed the CRC32
structural check. Copies of the restored DMG and `SHA256SUMS` under their
original release names passed checksum verification.

## Historical Beta Finder upgrade

The original host copies of the Beta App were missing 15 entries. A
read-only transfer from an intact copy in the historical guest matched all
41 entries and passed strict signatures on both systems. The original
run-09 host close receipt was recovered from the contemporaneous execution
record and matched the SHA-256 pinned at 1E.9. The historical verifier then
accepted the complete signed Beta App and CLI, 377 source handoff files,
and exact closed database and ownership lock.

The November 23, 2026 upgrade ran on the historical **macOS 27.2.1
(26B131) arm64** guest. The pinned local Build 10 DMG was transferred by SSH,
verified in the guest, and mounted read-only. Finder displayed the native
**Replace** prompt for the existing `~/Applications/Meshchan.app` and
replaced it in place. The installed inventory matched before and after
execution, covering 74 App entries, 619 ancillary entries, and eight
signature items. This upgrade uses the SSH transfer record. The separately
measured Safari download and quarantine event is recorded in 1E.11.

The Beta GUI quit normally before the full closed data directory was backed
up. Build 10 read the same default directory and reproduced four drafts,
six profiles, the History limit of 1001 with no default profile, and all
12 settled History records. The retained versions include Beta builds 3,
4, and 5. The App saved one offline draft. While it held the directory, the
installed CLI returned exit 69 with `data_directory_busy`.

The Build 10 App quit normally, and the installed CLI independently read
the committed draft from the released directory. The reopened GUI showed
the same title and body and quit normally again. All three normal exits
verified PID absence and ownership-lock release. The CLI and closed SQLite
comparisons matched the original fields, ordering, schema version, and
diagnostic provenance. The only observed business addition was the
revision-1 draft, bringing the total to five.

## Same-image host hardware attempt

On November 23, 2026, the arm64 host ran macOS 27.2.1 (26B131) with SIP
and Gatekeeper enabled. The independently restored DMG matched the frozen
size and SHA-256, passed its image check, and mounted read-only. The
complete installed inventory and eight signature items matched before and
after execution. The App ran with an isolated data directory and used one
approved hardware window of up to ten minutes.

The App refreshed its native port list and completed one USB Device Check
on the selected callout. Companion A identified itself as a Heltec V4.3
OLED with firmware `v1.18.0-81dbae5` and protocol code 14. The Check used a
5-second request budget and a 15-second initialization budget. The App
reported session close and observer cleanup. Independent OS sampling
confirmed both serial aliases were free before and after the Check. The
live handle was not captured by OS sampling.

A's Check and the current OpenHop management read for B agreed on the
frequency, bandwidth, spreading factor, and coding rate. The approved
Direct route used A slot 1 and B slot 3, with B selected for direct TCP.
The read-only channel audit stopped on A when
`APP_START` (`0x01`) timed out waiting for `SELF_INFO` (`0x05`). A's audit
cleanup succeeded. The raw audit recorded zero channel queries, zero queue
reads, zero configuration writes, and zero application datagrams. The audit
did not open B's direct TCP session or compare the two channel keys.

The App's Responder and B's PING were unrun, so active Cancel was unrun.
The App quit normally 128.162 seconds after Device Check dispatch. Its
shutdown report confirmed worker exit with zero pending requests and
receive ports. OS checks confirmed both launched processes were absent,
their TCP file descriptors were gone, and neither serial alias was held.
The storage ownership lock was independently available. The same-image CLI
opened the closed fixture and exported its empty History with a clean
close. SQLite integrity and byte comparisons passed before and after that
read. The private attempt archive preserves the screenshots, accessibility
captures, raw audit output, and release checks.

## Same-image host hardware verification

The second November 23, 2026 attempt used the same restored DMG and a
fresh isolated data directory on macOS 27.2.1 (26B131) arm64. After the
operator replugged A, IOKit and the App agreed on the selected USB
callout. The GUI Check again identified the Heltec V4.3
OLED with firmware `v1.18.0-81dbae5` and protocol code 14. The App reported
successful session and observer cleanup. Independent OS polling confirmed
both serial aliases were free before and after the Check. Its live handle
remained unsampled. The OS separately captured the App's open callout
descriptor during the subsequent Responder run.

The first read-only audit succeeded within the approved three-attempt
initialization limit. Both endpoints cleaned up successfully, and the
16-byte keys returned for A slot 1 and B slot 3 matched in memory. The
audit recorded zero application datagrams, queue reads, and configuration
writes. The A and B radio settings matched their settings from the first
attempt.

On the Direct zero-hop route, the selected OpenHop test peer used direct
TCP and had one locally accepted PING. It received one
matching PONG with exact content, zero matching duplicates, and an
application RTT of **4.552298 seconds**. The installed App recorded one
response attempt and one locally confirmed response. The actual RF
exchange used two application sends. B's session cleanup succeeded.

The App still held the same active Responder run after B verified the
PONG. GUI Cancel ended the run as `canceled`. Registration, logical result,
and final cleanup saves were committed. The App quit normally with exit
code 0, **143.383 seconds** after Device Check dispatch. Independent checks
confirmed process exit, worker shutdown, release of serial and TCP file
descriptors, and release of the data-directory owner lock. The installed
CLI reopened the closed fixture and exported one settled History entry
with the same run ID, Build 10 version, cancel result, response count, and
final cleanup. SQLite integrity and unchanged database bytes were verified.
The complete installed inventory and all eight signature items passed the
post-run check.

The private attempt archive preserves the native screenshots, accessibility
captures, typed App and B results, exact endpoint identifiers and radio
configuration, audit and OS observations, and closed History evidence.
The first stopped attempt has its own retained record.

## Public release and anonymous download

GitHub release `455893087` was published at 19:33:06 UTC on November 23,
2026 as the Build 10 engineering prerelease. The `v0.1.0-rc.1` tag
resolved independently to `c5cd5021da5e62c60127678b650d970721263296`
before and after release. The published Release was visible anonymously,
had `draft: false` and `prerelease: true`, and was excluded from Latest.
GitHub reported `immutable: false` for this Release.
[Build 10 on GitHub Releases](https://github.com/007pig/meshchan/releases/tag/v0.1.0-rc.1)

The nine published attachments have the same asset IDs as the verified
draft. A credential-free HTTPS session checked the Release page, rendered
body links, expanded asset list, and API, then downloaded all nine files
from the public asset addresses into a fresh directory. Every size and
SHA-256 matched the independently retained upload list. Both checksum
lists passed, and the manifest's seven leaf entries matched the downloaded
files. The 669,400,332-byte DMG was asset `784257599`.

| Final public file | SHA-256 |
| --- | --- |
| `release-manifest.json` | `32f3b7702327a890be07d40217c2896a53b2f35f2cf06dcd71e7e1da94e6b848` |
| `RELEASE-SHA256SUMS` | `c963f561042d1d6ced75019d3cda73429dabc55fe9bd1a6bc2c71f1b78c7e16e` |

The downloaded DMG passed its UDZO/HFS+ CRC32 check, mounted read-only,
and detached normally. The installation matched 692 inventory entries
and the image manifest. All eight signature items and 284 regular
materials matched, including the corresponding source, licenses, both
CLI libraries, and rebuild and replacement instructions. macOS added
its DiskImages checksum cache during verification. The download's
provenance attribute and file bytes were unchanged.

On macOS 27.2.1 (26B131) arm64, the installed CLI passed version and
help checks and wrote and read an isolated draft across separate
processes under a network-denying sandbox with an OS-only path. The
readback preserved Unicode and mixed line endings. Both processes
closed normally, the storage lock was released, and the closed SQLite
bytes remained identical across the readback.

A copy of that public DMG was transferred by SSH to the existing
isolated VM. The guest rehashed the transfer, verified and mounted the
image read-only, independently checked the installed App and CLI, and
normally detached the owned image. In the offline GUI, the installed
App saved a draft and quit normally. The same-image CLI read the closed
fixture, and a new App process reopened the exact title and body before
a second normal Quit. Both App exits confirmed resource and worker
release. Independent storage-lock checks and the closed SQLite byte
comparison passed. SIP and Gatekeeper remained enabled. The public
download used anonymous HTTPS on the host. The separate earlier Safari
first-install record supplies the same-image quarantine evidence.

The publication, anonymous download, and limited offline runtime gates
are complete for the frozen macOS arm64 engineering release.
