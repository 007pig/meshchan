# Phase 1E.9 installation and Beta upgrade validation

**The independent first install and the installed Beta upgrade both passed
on macOS 27.2.1 (26B131) arm64.** The same frozen engineering DMG was used in
both guests. The independent guest completed its first Safari download,
native system approvals, complete installation, and offline App and CLI
handoff. The separate upgrade guest established Beta data continuity.
See the [operator guide](../releases/phase-1e9-install-upgrade.md) for the
measured installation and approval sequence.

## Candidate and provenance

PR [#47](https://github.com/007pig/meshchan/pull/47) was merged into `master`
at `12913ca94246856a3e0c8dfeb92499b07b25706d`, with base parent
`b00807de20cddede3122aa8cfd71b352d0ffbb08` and PR head
`aa1dd9a9809db90d271486c24797b047ba553595`. The 1E.9 tools were developed
in that checkout. The installed product retains the frozen recipe 55 inputs
and the accepted `local-sign-005` → `local-dmg-008` →
`local-dmg-check-009` chain.

| Identity | Verified value |
| --- | --- |
| Compiled source | `a29430b608658a8b56d619f641dc8600346b6d27` |
| Original packaging tool checkout | `3b362ecc6346c3aec8ccee26e571e76b7a0571c8` |
| Signed candidate and DMG tool checkout | `e36690be02d7a213a6ab391c6f6b903d247e1521` for both |
| Upstream independent verifier | `2c485289da90dea35c4bc1e8e23c139676d0e7ad`, snapshot `f69c2811e91e4bd698dba81e3194cd563f1d1855` |
| Durable seal tool checkout | `562ee92663e0206a846dd98cddf8e846e7ce3c29`, CI run `44918791179` |
| 1E.9 acceptance tools | Working tree based on `12913ca`, file hashes in the private evidence index |
| Product | App `0.1.0-rc.1+8`, CLI `0.1.0-rc.1`, Apple `0.1.0` / `8`, bundle `org.meshchan.meshchan` |
| DMG | `Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg`, 675,911,154 bytes, read-only UDIF/UDZO with HFS+ |
| DMG SHA-256 | `b42021e054e65e47893d84437100a6b9e51a2ea93eb7a060c12e70fdb4a6ca28` |
| Original checksum list SHA-256 | `8f26a0821bb39bd1c93d48e57622164fd4b4eaf87d59d9ac80ae503d1023da53` |
| Independent DMG acceptance SHA-256 | `b88f3f1647fe65e1f549e32d00de555b59dba09da366001c530f67626124b71f` |
| Signed manifest SHA-256 | `58565d17e1c8659f6a73d6164ea37afabee1b75a03c1b20a01615ade467c18d9` |
| Independent local signing receipt SHA-256 | `17b203af6191d574d7d77fed472fb04050690aaf87e0b312ef1e02fa6eb474f0` |

The new 1E.8 lifecycle was authenticated from the separate
`build/phase-1e8/aa1dd9a-seal-and-recovery` records. The seal command recorded
receipt pin `024afca43d587fc1ae8e6a27127ece16e478c6718acdd722f97a51423ddf43cf`
at `.meshchan-aa1dd9a-lifecycle.x76sHJlo/New sealed candidate` below the
engineering archive parent. The matching isolated verification record
`fa42551b650a0e7858e039c23df45c7a0d479b93fed1e5e6353e30a2a4d99606`
reported PASS at 17:07:18 UTC on November 21, 2026, using the artifact set
for CI run `44926458093`. The recorded temporary seal and restored image
are absent. The historical receipts and CI snapshot remain available.

The download used the published engineering copy at
`~/Documents/my_projects/Meshchan Engineering Archive/RC1 Build 8 - engineering assets/`.
The selected durable seal `RC1 Build 8 - 1E.8` has receipt pin
`76221dc94d40c7f32aaa5933c849fd17b4eadf3aceda907f9475f971dc38fc8c`.
The original isolated verification and asset transfer pins are
`12c3ca8e302865182bfcd9f0a49f62c9c7e213ada9a2f6c0dce4439c02639fcf` and
`2d80a32ea0e46165259012e8968531bc72481bf31116e247e2be87660a7cab37`.
A full current-checkout `retain_release.py check` passed for the durable seal.
Its private report at
`build/phase-1e8/phase-1e9-durable-check-01/verification.json` has SHA-256
`075bcf78bf4dc2d1c3f76e5273ff873d94979c586e2f173350c5ac6deb0b25f3`.
It reports historical acceptance `MATCHED` and new product runtime `NOT_RUN`.
The candidate admission report independently binds the published asset,
original checksums, retained verifier inventory, and accepted receipt chain.

## Independent first-install guest

No pre-exposure snapshot was available for the configured upgrade guest.
A separate Apple-virtualized arm64 UTM guest,
`Meshchan-1E9-Clean-20261121` (`7A5C2C2F-6D58-4E42-A5C9-C87D052861D8`),
was provisioned on a new blank disk from the Apple universal restore image
for macOS 27.2.1 (26B131). Its stopped snapshot
`Before-Meshchan-First-Contact` (`28733F34-2295-4E8D-9733-0457CC4590B7`)
was created at 18:58:33 UTC on November 21, 2026, before the first boot
and Setup Assistant. The console fingerprint and strict SSH verified the
separate VirtualMac2,1 hardware UUID
`5CC7D2EF-581C-59BE-A531-6D397E7889C6` and dedicated local account.
Preflight found no App install, DMG, mounted image, or default data
directory. Gatekeeper and SIP were enabled. Xcode and the Command Line
Tools, Flutter, Dart, and Homebrew were absent.

On the isolated UTM Host Only network, Safari opened the private
engineering URL and displayed its first per-site download permission
dialog. After **Allow**, the host logged one complete 675,911,154-byte
transfer at 19:34:42 UTC. The SHA-256 of the original file in Downloads
matched the frozen DMG pin above. Safari quarantine event
`ED702724-1B6B-42A7-98F3-015B75A25610` matched the case time, agent and
download source corroborated by the browser metadata. The case's private
GUI adapter ran the digest and metadata checks under the console executor
with the native Downloads folder grant. Remote Login Full Disk Access
stayed disabled. The verifier bound the original file to the exact
read-only Finder mount. The scoped host download server stopped after
the transfer. The [operator guide](../releases/phase-1e9-install-upgrade.md#maintainer-repeat-and-support-scope)
describes the current release tool's equivalent console verification.

Finder copied the App to `~/Applications/Meshchan.app`. The full CLI
and engineering materials came from the same read-only mount. The CLI
was installed at
`~/Library/Application Support/meshchan-engineering/20261121-first-install-01/Meshchan-0.1.0-rc.1-macos-arm64/meshctl/bin/meshctl`.
The installed inventories matched all 74 App entries and 689 ancillary
entries. Strict App verification and all eight code items across 13
architecture slices matched the accepted signatures. Normal detach
removed the exact attested attachment. The initial detach attempt exposed
a case-tool comparison error involving the recorded mount-baseline hash.
The corrected command verified the baseline hash separately and detached
the same live attachment. The regression test covers the actual mount
and detach entry points and rejection of a different baseline.

The App's first ordinary LaunchServices open produced **“Meshchan” Not
Opened**. The operator chose **Done**, followed the App-specific **Open
Anyway** actions in Privacy & Security and the confirmation dialog, and
authenticated as the guest administrator. The App reached **Storage ready**
with an empty draft list. Live inspection bound the executable and SQLite
framework to the installed paths and verified ownership of the actual
default directory. The first App process exited after ordinary Cmd+Q.
Two subsequent launches supplied typed shutdown receipts.

Terminal ran the installed `meshctl` from the home directory. Gatekeeper
separately assessed the executable and `meshctl/lib/libsqlite3.dylib`.
For each item, the operator chose **Done**, selected **Allow Anyway** in
Privacy & Security, retried the exact command, selected **Open Anyway**,
and authenticated. The CLI printed `meshctl 0.1.0-rc.1` and exited 0.
The first successful `draft list --json` read an empty draft list from the
default directory and closed storage normally. The CLI image observation
matched the installed SQLite library's device, inode, and SHA-256.
Gatekeeper and SIP remained enabled. The Host Only network stayed in effect
during download, system approval, and offline use. Direct probes to two
public IPv4 and two public IPv6 addresses failed before and after the offline
run. The private SSH connection to the same guest remained available.

The App saved one Unicode multiline draft and changed the History limit
from 1000 to 1002 in `~/Library/Application Support/meshchan`. While it
held the directory, the installed CLI returned `data_directory_busy` and
exit 69. After ordinary Quit, the CLI matched the closed SQLite projection
and confirmed the draft and setting. A second ordinary App launch showed
the same draft and setting and Quit normally. Both closed snapshots matched
the public CLI projection. Both typed shutdown receipts reported release of
resources and the data owner, worker exit, zero pending requests, and zero
receive ports.

The post-run inventory and signature checks matched the initial install
and the frozen inputs. The guest still had its original download, installed
products, and owned test data. The pre-contact snapshot remained available
in UTM. The operator revoked the temporary Downloads access, stopped the
guest executor, disconnected SSH, and removed the temporary SSH key.

## Measured installation in the Beta upgrade guest

The strict-SSH VM controller verified the configured VirtualMac2,1 UUID and
logged-in console account `meshchantest`. The guest runs macOS **27.2.1
(26B131), arm64**. The 1E.7 acceptance run
`20261121T142918Z-product-56504` remains in this guest and had launched this
candidate. The UTM library examined contained the configured guest, with no
available documented pre-exposure snapshot or second ready guest. The 1E.9
run had no Meshchan process, no `/Applications/Meshchan.app` or user
`~/Applications` install, and no default Meshchan data directory at
preflight. SIP and Gatekeeper were enabled. The guest has Apple's Command
Line Tools and the approved VM executor. Flutter, Dart, Homebrew, and the
usual SDK/cache and shared-mount locations were absent from the inspected
environment.

Safari 27.2 (22625.2.8.11.9) opened the scoped UTM HTTP address
`http://192.168.64.1:49839/Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg`.
The host listened on the UTM bridge only and restricted requests to the
configured guest and the exact DMG and checksum routes. Safari prompted to
allow downloads from the host and the operator selected **Allow**. The
transfer completed at 17:43:26 UTC. Safari's download matched the external
size and hash. The native quarantine event matched the new GUID, Safari's
bundle ID, and the download time. The source and downloaded-date attributes
recorded the exact URL and time. The quarantine event's own source URL fields
were null. The service stopped after the transfer.

An initial LaunchServices request made from the executor displayed a
Downloads folder permission dialog for the executor. The operator declined
it and opened the exact downloaded file directly in Finder. Finder mounted
the image with no observed security prompt for the image. The new devices
were `/dev/disk6` and `/dev/disk6s1`, tied to the downloaded image and
the read-only HFS+ mount `/Volumes/Meshchan 0.1.0-rc.1 build 8`.

Finder copied the RC App into the owned `~/Applications/Meshchan.app`.
It described the installed Beta as older and the incoming RC as newer.
The operator selected **Replace**. The Apple short version actually changed
from `0.1.0.1` to `0.1.0` and the build from `5` to `8`.
The copy retained Safari's quarantine event, with flags changing from
`0083` on the image to `0183` on the App.

The complete CLI and all ancillary materials were copied with `ditto`.
The installed CLI is at
`~/Library/Application Support/meshchan-engineering/20261121-existing-guest-01/Meshchan-0.1.0-rc.1-macos-arm64/meshctl/bin/meshctl`.
The sibling materials, original candidate source and verification files,
and volume-level README, image manifest, and `dmg-source/` remain in that
version directory. The exact installation inventory matched 74 App entries
and 689 ancillary entries including the image manifest. The App passed strict
deep verification, and all eight accepted code items matched the CodeDirectory
requirements across 13 architecture slices. The temporary mounted image was
normally ejected and its download/mount attachment was subsequently absent.

The exact installed App was opened through LaunchServices with stdout/stderr
capture and no product flags. Gatekeeper displayed **“Meshchan” Not Opened**
and offered **Move to Trash** and **Done**. The operator selected **Done**,
opened **Privacy & Security**, selected **Open Anyway** beside the Meshchan
message, and selected **Open Anyway** again at the follow-up dialog. macOS
then asked for administrator authentication. While that dialog was open,
LaunchServices returned zero and the OS allocated PID 67391. At that point
the process mapped only the main binary and dyld. It had no SQLite mapping
or default-directory open. An installed CLI read attempted during this
period timed out without a business envelope or contention result.

The guest administrator completed the App authentication. The same PID
then became a live App from the expected install path with no product
arguments. The GUI showed storage ready, owner held, and four existing
drafts. About displayed `0.1.0-rc.1 (8)`. Live file inspection bound the
installed executable and its SQLite framework to the mapped device and
inode, and confirmed that PID 67391 held the original default-directory
database and owner lock. The first approved launch exited after ordinary
Quit. The system's approval launch connected stdout/stderr to `/dev/null`,
so this first process did not yield the product shutdown JSON.

The CLI also had a separate assessment. The initial request's executable
was found in Trash, with the installed `meshctl/bin` directory empty.
The test preserved the incomplete owned tree and restored the whole CLI
from the same verified Safari image, rechecked the signatures and detached
the image again. Terminal in the guest showed **“meshctl” Not Opened** for
the restored CLI. The operator chose **Done**, then **Allow Anyway** for the
specific CLI in **Privacy & Security**. On retry, Terminal displayed
**Open “meshctl”?**. Selecting **Open Anyway** led to a separate
administrator authentication dialog. After the administrator authenticated,
the original Terminal command printed `meshctl 0.1.0-rc.1` and exited 0.
The first database command triggered another assessment for the signed
`meshctl/lib/libsqlite3.dylib`. The operator selected **Done**, **Allow
Anyway**, and reran the database command. The library's **Open Anyway**
confirmation led to the third native administrator prompt. After that
authentication, the installed Terminal command finished offline, returned
the four original drafts, closed storage, and exited 0. These app-specific
approvals updated native quarantine flags. The original Safari quarantine
event remained attached to the installed App and executable.

Public IPv4 and IPv6 probes succeeded during the App and CLI executable
approvals. The bundled SQLite approval and actual business checks ran after
enabling a temporary guest-only packet filter anchor. The rules blocked
public IPv4 and IPv6 egress on the guest network interface and preserved
the private SSH management path. Both public probes timed out before the
business work began. The operator renewed the isolation using an overlapping
anchor before the first timed rollback. Direct public IPv4 and IPv6 probes
still timed out after the second normal Quit. The operator removed both
anchors and released their enable tokens. The guest again reached the
public endpoints in both address families.

## Beta input and data evidence

The standalone original Beta delivery was incomplete on this machine. Its App
had twelve missing regular inventory entries, including `Info.plist` and
signature resources. The known retained copy
`hardware/run-09-rf-restart/delivery-prepared-retained` under
`/private/tmp/meshchan-1d11-20261116-01` matched the original pinned
`metadata/products.json`
(`edcdf862edae4733ff430feafcd08537bbce5e56afa716e93553d42d3f4e5782`).
The retained App inventory of 41 entries and the CLI inventory of three files
matched and the original code signatures verified. Beta uses App
`0.1.0-beta.1+5` and CLI `0.1.0-beta.1`.

The compilation input manifest matched the original delivery and the recorded
base `0fd49a3495d972c88dee35fc709501db78a16d16` plus dirty-input provenance.
All build inputs matched the prepared source handoff's product files. The
prepared handoff manifest had 377 verified entries. Three original non-build
document revisions from the compilation cut were not recovered. Comparing
both manifests accounts for eight original non-build paths that changed or
were removed, plus the post-build addition
`docs/validation/phase-1d11-build5-gui-delay.md`.

The source fixture was the exact closed SQLite fixture identified by the
historical report `hardware/run-09-rf-restart/offline-host-verification.json`.
The database had no SQLite sidecars in the source snapshot and matched
`217277ba7672c02fa7ebf00f05b3e53797bb179dfb6df9e6338e51dbee23f3db`.
The owned copy was placed in the vacant real guest default directory,
`~/Library/Application Support/meshchan`. Beta ran from its actual
installation using LaunchServices with no data override. The live GUI showed
storage ready and owner held. Normal Quit produced a typed receipt for
resource, worker and owner release, zero pending requests/receive ports and
no error. PID 59450 was absent. The guest captured the upgrade-before
SQLite set under the product's BSD lock, and the Beta CLI independently read
all public rows.

The upgrade-before projection contains four drafts, six profiles, one settings
record with History limit 1001 and no default profile, and twelve settled
History records. Historical app provenance includes two build 3, four build 4,
and six build 5 rows. The schema, summary format, and CLI envelope versions
are each 1. The private baseline preserves full field values and order.

## Offline RC data continuity and normal handoff

With the image detached and the Internet isolated, the approved installed
RC CLI independently reproduced the complete Beta CLI projection before
any new writes. A live image observer bound installed CLI PID 89120 to its
bundled SQLite library and checked device and inode against the current
file. The installed RC App launched with no product flags at PID 89171.
Its live App and SQLite mapped vnodes and hashes matched the accepted
installed code. File observations show the real default database
`~/Library/Application Support/meshchan/meshchan.sqlite` and owner lock.
The data directory and database were the same ones used by Beta. The
inspection kept mapped Apple caches and ICU data separate from the code
mapping evidence. It found no loaded binaries from the checkout, SDK,
previous App copies, Homebrew, or the detached image. The guest's existing
Command Line Tools remained present. The installed products loaded native
libraries from their installed bundles.

The operator saved a single draft via the installed GUI with title
`Engineering upgrade 中文 🛰️` and body `First line\n第二行 🙂\nLast line`.
The actual focused native fields verified both values. The operator changed
only the diagnostic History limit from 1001 to 1002 in the GUI and saved
settings. While the App held the default directory, an installed CLI
`draft list --json` returned exit 69 with `data_directory_busy`,
`committed=false`, and no business or maintenance writes.

Normal GUI Quit at PID 89171 reported resource release, a spawned and
exited worker, owner released, no error, and zero pending requests and
receive ports. The PID was absent before the lock-guarded SQLite snapshot
and installed CLI readback. The RC public and SQLite comparisons matched
all original draft fields, all six profiles, and all 12 History rows,
including their IDs, order, terminal outcomes, original app versions and
provenance. The schema, summary and CLI envelope versions each remained 1.
The only business changes were the exact new draft at revision 1 and the
History limit change. The default profile remained unset.

The installed GUI reopened normally as PID 91238 after the CLI had exited.
The focused fields confirmed the exact draft title, three-line body,
unchanged default-profile setting, and History limit 1002. The second
normal Quit returned the same release facts and left the PID absent. The
final closed snapshot and both public and SQLite comparisons passed again.
The run preserved the original Beta fixture plus separate upgrade-before,
upgrade-after and reopen snapshots.

The separate host-only scoped compatibility test executed 87 real commands
against an owned copy of the Beta fixture and the accepted RC CLI. Before
changes the public and closed SQLite projections matched. The RC CLI added
one Unicode multiline draft, changed the History limit from 1001 to 1002,
retained the six profiles and twelve History records, and preserved all
existing drafts. A real BSD flock holder produced exit 69 with
`data_directory_busy` and the CLI read successfully after release. The
scope was a host fixture with an explicit data path and a lock holder.
The guest default-directory RC handoff remained a separate gate.

## Gates and support decision

| Gate | Status | Evidence |
| --- | --- | --- |
| Candidate, durable handoff, and real Beta source/fixture | PASS | Exact pins, accepted inventory, current durable seal verifier and closed input checks |
| Candidate-naive environment | PASS | Independent Apple arm64 guest, empty disk provisioning, stopped snapshot before first boot, native preflight before download |
| Real engineering Safari download and mounted-image provenance | PASS | Two native Safari transfers of the same pinned bytes, browser source and quarantine, exact read-only image and owned detach |
| Complete installed bytes, local signatures and versioned CLI layout | PASS | Post-copy inventory and every accepted signature, before product open |
| Finder Beta replacement and closed default-directory baseline | PASS | Same target, actual replacement prompt, normal Beta Quit and both pre-upgrade projections |
| Approved RC App and CLI start under normal macOS security | PASS | Both guests exercised item-specific approval for the App, CLI and CLI SQLite, followed by actual starts and data access |
| Installed RC offline business, installed loader paths and normal Quit | PASS | Public IPv4/IPv6 probes failed, live paths and vnodes matched, two typed RC shutdown receipts in each guest and absent PIDs |
| First-install empty directory, GUI/CLI ownership and persistence | PASS | Empty initial projection, limited GUI changes, busy exit 69, CLI and closed SQLite readback, GUI reopen |
| Beta default-directory continuity, GUI/CLI ownership, limited writes and reopen | PASS | Before/after public and SQLite projections, busy exit 69, finite GUI changes, CLI readback and GUI reopen |
| Final installed and original input integrity | PASS | Exact post-run inventories and signatures, plus unchanged durable candidate and Beta source pins |
| Engineering macOS support scope | PASS | macOS 27.2.1 (26B131) arm64 is the lowest tested version and the only covered system build |
| Earlier macOS releases | NOT_RUN | The complete static loader floor is 14.0. No earlier macOS build was exercised in 1E.9 |

Static loader checks across all accepted arm64 code show an App plist and
primary binary floor of 12.0, an effective App floor of 13.0 from the nested
serial and SQLite code, and a complete App-and-CLI floor of 14.0 from the CLI
binary. The current engineering support scope for both first install and
Beta-to-RC upgrade is **macOS 27.2.1 (26B131) arm64**. This is the minimum
verified in this round. Earlier macOS versions, Intel, and mobile are
outside this validation scope.

## Private evidence and next handoff

The independent first-install evidence is under
`build/phase-1e9/20261121-first-install-01/`. Its `case-result.json` indexes
the provisioning and snapshot records, verification of the frozen inputs,
each native approval, the closed database copies and public projections,
and the before/after installation records. It pins the original Beta
upgrade record as a separate case. The first-install index SHA-256 is
`b2142327b2aa2c7890cd288d75266fbfde65c14621df4f37e0e115eaaaaa5bb4`.

The [maintainer repeat procedure](../releases/phase-1e9-install-upgrade.md#maintainer-repeat-and-support-scope)
uses tracked actions for scoped Beta staging, private-network probes,
live CLI SQLite observation, and closed public and SQLite comparisons.
The retained first-install and upgrade results describe the original
guest runs and index the tools used at the time.

The private Beta upgrade evidence is under
`build/phase-1e9/20261121-existing-guest-01/`. It includes screenshots and
exact machine records, the closed SQLite snapshots, and the full public
projections. The `case-result.json` record pins the inputs, evidence and
tools and identifies the status of each gate. The downloaded image and
installed products and owned data remain in the guest. The temporary
server, network watchdogs, and two owned GUI executors were stopped.
The preserved upgrade index reports the overall 1E.9 status at the time
of that run, when the independent first-install gate was still blocked.
Its measured upgrade gates passed. The later first-install index closes
the remaining gate and pins the unchanged upgrade index at SHA-256
`715ebe4468115353f87bfb7b6478a89828fe59fe31029fa47b79bdae6bf906a7`.
The source and static audit reports are in
`build/phase-1e9/rc-inputs/run-01/` and
`build/phase-1e9/static-code-01/`. The host-only compatibility test is in
`build/phase-1e9/scoped-cli-compatibility/run-01/`. These records contain
private test data and remain outside Git and public CI artifacts.

The Python toolchain was CPython 3.15.2, invoked at
`/opt/homebrew/bin/python3` and resolved to
`/opt/homebrew/opt/python@3.15/bin/python3.15`. The standard command was
`/opt/homebrew/bin/python3 -B -m unittest discover -s tool -p '*_test.py'`.
Existing tests that need macOS process, signing, and file observations failed
under the restricted tool sandbox. The native-access rerun is the applicable
local suite record. Hosted CI's existing Python discovery includes the new
tests. The original native-access run passed **597 tests in 120.346 seconds**.
The first-install follow-up passed **598 tests in 121.195 seconds** after
fixing the mount receipt comparison. The focused installed-release suite
passed 39 tests. The private VM observations were run locally.

A subsequent review checked the maintainer procedure's phase ordering and
retry behavior. The updated tool requires the verified install before detach,
the verified Safari receipt before normal executor finish, and the timed CLI
evidence before the next measured App launch. An interrupted Beta baseline
can retry its CLI reads using the saved, verified closed snapshot. All 105
installed-release tests passed. The full native-access Python suite passed
**664 tests in 120.123 seconds**. Replaying both retained cases also matched
the closed SQLite files, CLI projections and contention responses, and the
draft text captured in the GUI. This follow-up used the original evidence
and local test fixtures. The two live guest runs are recorded above.

A further review exercised interrupted baseline and SQLite snapshot writes.
The mount baseline now publishes the native inventory and digest in a single
receipt, and the closed SQLite directory publishes only after projection
succeeds. Later commands recheck the preflight and Safari download order.
The live mount check also requires the accepted 1E.7 volume UUID and checks
the hash of `image-payload.json` on the read-only volume. Both retained guest
mount records report the same accepted UUID. The original case indexes retain
their recorded digests. That native-access Python run passed **668 tests
in 140.472 seconds**, including all 109 installed-release tests.

A follow-up simulated interruption after SQLite capture and before the case
receipt was published. The closed snapshot and its shutdown receipt now
publish together. The same command can recover the case receipt from this
archive after verifying the original runtime binding and SQLite files.
Network probes now retain previously observed public reachability through
SSH timeouts and operator interruptions. An incomplete probe set cannot
establish isolation. Both changes were exercised with local test fixtures,
and all five retained first-install, RC upgrade, and Beta shutdown snapshots
passed read-only replay. The native-access Python suite passed **672 tests
in 112.031 seconds**. All **113 installed-release tests** passed again after
the final check that the archived shutdown receipt is a regular file.

A separate review exercised the documented copy command with a nondefault
case ID, a mount path with a suffix, and `umask 077`. The copy kept both
selected values, and the two destination root modes matched the frozen
manifest. The final upgrade command also reauthenticates the original Beta
App, CLI, source, and closed fixture from the staging record. A read-only
check of the retained Beta inputs matched the current verifier's pinned
identities. The verifier recomputes its list of non-build handoff paths from
the pinned source manifests. The native-access Python suite passed **673
tests in 108.430 seconds**, including all **114 installed-release tests**.

A cleanup review verified that the case cannot advance past download while
its GUI executor lacks a matching normal-exit receipt. The final install
command also checks that the case image is detached, the App has exited,
and the existing default-directory lock is available before and after the
file and signature checks. It also rechecks SIP and Gatekeeper at the end.
Local regression fixtures exercised a different executor receipt, a final
remount, an active storage owner, and a change in system protection during
verification. The existing guest shutdown and cleanup records remain the
evidence for the original runs. The native-access Python suite passed **677
tests in 120.236 seconds**. All **118 installed-release tests** passed again
after adding the final system-protection observation.

The case runner now keeps numbered failure records alongside pending and
successful receipts. Regression tests verified that interrupting an install
or losing the response to a launch request preserves the case evidence. Beta
staging also records its expected publication before the transfer and commits
a matching marker in the guest once all three destinations are in place. A
retry after a lost reply can verify the original App, CLI, and closed SQLite
files without replacing them. A mismatched marker or changed installed
content fails that recovery check. A native test using the original signed
Beta and closed fixture in a temporary macOS directory exercised all three
outcomes. The native-access Python suite passed **681 tests in 197.931
seconds**, including all **122 installed-release tests**.

Use the exact frozen candidate and pinned engineering DMG above for 1E.10.
Device acceptance uses the complete, installed locally signed App and CLI
and the recorded digest. No real serial enumeration, RF, tagging, or
publication was performed in this phase.
