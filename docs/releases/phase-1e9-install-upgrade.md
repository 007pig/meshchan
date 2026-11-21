# Phase 1E.9 engineering installation and Beta upgrade

This procedure uses the accepted macOS arm64 engineering candidate. The App
and complete CLI have local ad hoc code signatures. The read-only DMG is
unsigned and Apple has not notarized it. The ongoing profile is `local-adhoc`.
Use the exact image and checksum from the trusted engineering handoff.

| Item | Identity |
| --- | --- |
| Disk image | `Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg`, 675,911,154 bytes |
| Image SHA-256 | `b42021e054e65e47893d84437100a6b9e51a2ea93eb7a060c12e70fdb4a6ca28` |
| Original `SHA256SUMS` SHA-256 | `8f26a0821bb39bd1c93d48e57622164fd4b4eaf87d59d9ac80ae503d1023da53` |
| App / CLI | `0.1.0-rc.1+8` / `0.1.0-rc.1` |
| Apple version / build | `0.1.0` / `8` |
| Bundle identifier | `org.meshchan.meshchan` |

The [1E.8 retention guide](phase-1e8-ci-retention.md) explains how to recover
the engineering assets. Only the image and original checksum are needed for
download. Keep the internal seal, runtime evidence, and VM configuration
private. The [1E.9 validation record](../validation/phase-1e9-install-upgrade.md)
identifies the evidence and the limits of each acceptance result.

## Download and open the image

Use Safari to download the DMG from the authorized engineering address. If
Safari asks whether the site may download files, select **Allow** for that
address. Wait for the download to finish and use the exact file in Downloads.
The observed Safari 27.2 download used a private UTM HTTP endpoint. Its original
Safari quarantine and download-source metadata were recorded before opening.

Check the byte count and digest in Terminal before opening the DMG. Compare
with the values in the trusted handoff, including when a checksum file is also
available from the download address.

```sh
MESHCHAN_DMG="$HOME/Downloads/Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg"
/usr/bin/stat -f '%z' "$MESHCHAN_DMG"
/usr/bin/shasum -a 256 "$MESHCHAN_DMG"
/usr/bin/xattr -p com.apple.quarantine "$MESHCHAN_DMG"
```

Stop if the size or digest differs. Preserve the downloaded file and its
extended attributes throughout installation. In Finder, double-click this DMG
in Downloads. On the recorded guest, Finder mounted the image read-only.
Safari displayed its own download permission before the transfer. macOS
assessed the App separately after installation.

Before copying, run `/usr/bin/hdiutil info -plist`. Find the single attachment
whose `image-path` is the verified file in Downloads. Check that its
`writeable` value is false and that its `system-entities` list contains one
`mount-point` under `/Volumes`. Use that exact mount point in Finder and
Terminal. The recorded mount point was
`/Volumes/Meshchan 0.1.0-rc.1 build 8`. Resolve any missing or ambiguous match
before continuing.

## Install the App, CLI, and materials

Open `Meshchan-0.1.0-rc.1-macos-arm64` on the verified volume in Finder.
Copy `Meshchan.app` to the account's `~/Applications` folder. Create the folder
if it is absent. If `Meshchan.app` already exists, use the [upgrade procedure](#upgrade-from-beta-build-5)
after identifying the installed product. The Finder copy in this test carried
the native download quarantine to the installed App.

Use a fresh directory below `~/Library/Application Support/meshchan-engineering`
for the complete CLI and the accompanying materials. This directory is separate
from the App and CLI's actual data directory. The recorded installation used
`ditto` for the ancillary copy, including the signed manifest, license and
source materials, and the volume's packaging records. Run the following on the
account that mounted the DMG. Set `MESHCHAN_VOLUME` to the verified mount point
and choose a fresh `MESHCHAN_INSTALL_ID`. Use the same Terminal session for the
later snippets so the paths remain available. These example assignments use
the case ID shown in the maintainer procedure and the recorded mount point.
Adjust both for your run before copying any files.

```sh
MESHCHAN_INSTALL_ID=rc1-build8-first-install
MESHCHAN_VOLUME='/Volumes/Meshchan 0.1.0-rc.1 build 8'
```

```sh
MESHCHAN_PAYLOAD='Meshchan-0.1.0-rc.1-macos-arm64'
MESHCHAN_ENGINEERING="$HOME/Library/Application Support/meshchan-engineering"
MESHCHAN_INSTALL="$MESHCHAN_ENGINEERING/$MESHCHAN_INSTALL_ID"
MESHCHAN_INSTALLED_PRODUCT="$MESHCHAN_INSTALL/$MESHCHAN_PAYLOAD"

(
  set -e
  : "${MESHCHAN_INSTALL_ID:?Set the installation ID for this case}"
  : "${MESHCHAN_VOLUME:?Set the verified volume mount point}"
  mkdir -p "$MESHCHAN_ENGINEERING"
  mkdir -m 755 "$MESHCHAN_INSTALL"
  mkdir -m 755 "$MESHCHAN_INSTALLED_PRODUCT"
  for MESHCHAN_ITEM in README.md materials meshctl packaging-source provenance \
      signed-product-info.json signing-materials signing-source upstream-provenance; do
    /usr/bin/ditto "$MESHCHAN_VOLUME/$MESHCHAN_PAYLOAD/$MESHCHAN_ITEM" \
      "$MESHCHAN_INSTALLED_PRODUCT/$MESHCHAN_ITEM"
  done
  for MESHCHAN_ITEM in README-engineering.md dmg-source image-payload.json; do
    /usr/bin/ditto "$MESHCHAN_VOLUME/$MESHCHAN_ITEM" "$MESHCHAN_INSTALL/$MESHCHAN_ITEM"
  done
)
```

Preserve the complete `meshctl/` directory, including `bin/meshctl` and both
native libraries under `lib/`. Verify the installed signatures before ejecting
the disk image. Stop if the copy or any signature check fails.

```sh
MESHCHAN_CLI="$MESHCHAN_INSTALLED_PRODUCT/meshctl/bin/meshctl"
(
  set -e
  /usr/bin/codesign --verify --deep --strict --all-architectures "$HOME/Applications/Meshchan.app"
  for MESHCHAN_CODE in "$MESHCHAN_CLI" "$MESHCHAN_INSTALLED_PRODUCT/meshctl/lib/"*.dylib; do
    /usr/bin/codesign --verify --strict --all-architectures "$MESHCHAN_CODE"
  done
)
```

The image manifest and `signed-product-info.json` support full inventory
verification. Recheck the attachment's `image-path` and `mount-point` before
ejecting it with `/usr/bin/hdiutil detach "$MESHCHAN_VOLUME"`.
Confirm that the image and its mount are absent before launching the installed
products.

## Open and use the installed products

Open `~/Applications/Meshchan.app` from Finder. The recorded ordinary
LaunchServices open of this path showed **“Meshchan” Not Opened** with
**Move to Trash** and **Done**. The alert said Apple could not verify Meshchan
for malware. After the verified download and signature checks, the operator
selected **Done**, then **System Settings → Privacy & Security → Open Anyway**,
followed by **Open Anyway** in the confirmation dialog. macOS then requested
the guest administrator's credentials. After the administrator authenticated,
the installed App opened, reached **Storage ready**, and showed
`0.1.0-rc.1 (8)` in About. Keep Gatekeeper and SIP enabled and confirm the
installed app reaches the same ready state. [Open apps safely on your Mac](https://support.apple.com/en-us/102445)

After system assessment, use Terminal to run the full installed CLI by its
path from outside the product directory. The expected version is
`meshctl 0.1.0-rc.1`. The read commands use
the same account's default directory as the App, `~/Library/Application Support/meshchan`.
Run them after quitting Meshchan normally and waiting for its process to exit.
Run `--version` first so you can complete its approval and confirm its output
before trying the first database command.

```sh
cd "$HOME"
MESHCHAN_CLI="$MESHCHAN_INSTALLED_PRODUCT/meshctl/bin/meshctl"
"$MESHCHAN_CLI" --version
```

The installed executable has its own assessment. The recorded guest showed
**“meshctl” Not Opened** when Terminal assessed the verified CLI. The operator chose
**Done**, selected **Allow Anyway** for `meshctl` in **Privacy & Security**,
then reran the exact Terminal command. The system asked to **Open Anyway**
and authenticate. Use the app-specific approval for this verified executable
if macOS offers it. Moving an executable or library to Trash leaves the CLI
directory incomplete. For regular use, reopen the verified DMG, check the
exact mount again, and copy the whole CLI and its materials into a fresh
installation directory as described above. Verify the installation, detach
the image, and repeat the applicable approval from the new CLI path.

```sh
"$MESHCHAN_CLI" draft list --json
```

The first database command can trigger a separate assessment of the CLI's
bundled `libsqlite3.dylib`. In the recorded run the operator chose **Done**,
selected **Allow Anyway** for that library in Privacy & Security, retried
the same command, then selected **Open Anyway** and authenticated. The
command read the default directory and exited 0 with storage closed while
the guest was offline. After this command succeeds, the other read commands
can use the same installed CLI.

```sh
"$MESHCHAN_CLI" profile list --json
"$MESHCHAN_CLI" settings show --json
"$MESHCHAN_CLI" history list --json
```

A CLI business command issued while the GUI owns the data directory is
expected to exit `69` with `data_directory_busy`, including read commands.
After normal Quit and release, the installed CLI can open the directory.
Wait for the CLI to finish before reopening the App in Finder. See the
[CLI guide](../cli.md) for the output and storage lifecycle contracts.

## Upgrade from Beta build 5

Identify the existing `~/Applications/Meshchan.app` as Beta build 5 using its
About information and the accepted Beta provenance. Beta App runtime is
`0.1.0-beta.1+5`, Beta CLI is `0.1.0-beta.1`, and the old Apple version and build
strings are `0.1.0.1` and `5`. The Bundle ID stays `org.meshchan.meshchan` in
RC build 8. Preserve both bundles' original version metadata.

1. Quit Beta using **Meshchan → Quit Meshchan**. Wait for the process to exit
   and finish any CLI commands that use the same data. Keep both products
   closed while backing up `~/Library/Application Support/meshchan` to a fresh
   private directory. Preserve the entire directory, including any SQLite
   companions. For an account with an existing Beta database, the copy can
   be made from the same Terminal session.

   ```sh
   MESHCHAN_DATA="$HOME/Library/Application Support/meshchan"
   (
     set -e
     test -f "$MESHCHAN_DATA/meshchan.sqlite"
     MESHCHAN_BACKUP=$(/usr/bin/mktemp -d "$HOME/Library/Application Support/meshchan-beta-backup.XXXXXXXX")
     /usr/bin/ditto "$MESHCHAN_DATA" "$MESHCHAN_BACKUP/data"
     printf 'Closed Beta backup: %s\n' "$MESHCHAN_BACKUP/data"
   )
   ```

   Confirm that the backup completed before proceeding. The maintainer
   upgrade evidence captures `meshchan.sqlite` and every existing
   `-wal`, `-shm`, or `-journal` companion while holding the same ownership lock
   the product uses. Keep that copy with the prior inventory and business
   projection. Backups should remain private.
2. Verify the pinned DMG and open it in Finder, then copy the RC App into the
   same Applications folder. Verify the existing item is the owned Beta copy
   before choosing **Replace**. The observed Finder prompt described the
   installed `Meshchan` as older and the copied `Meshchan` as newer. This was
   observed on the recorded guest, with the actual `0.1.0.1` and `0.1.0` Apple
   version strings and builds `5` and `8`.
3. Install the RC CLI and materials as above, check the complete installed code,
   and eject the volume. Open RC from the same installed App path. Keep the
   account's default data directory in use and check About for `0.1.0-rc.1 (8)`.
4. Check the existing drafts, profiles, settings, and History, then make one
   intended save. Quit normally and verify both old and new data using the
   installed CLI. Reopen the installed App and check the saved changes. The
   recovery copy is an upgrade safeguard. Downgrade to Beta remains outside
   this procedure.

## Maintainer repeat and support scope

For a first install, use a documented pre-contact snapshot or provision an
independent Apple arm64 guest. Record the VM and snapshot identities before
serving the candidate. The first-install case used UTM Host Only networking.
Set the test guest's network to Host Only before connecting, and keep that
mode through the approvals and both measured launches. Record the UTM
network mode and retain the before and after guest probe receipts. Direct
public IPv4 and IPv6 connections must fail while the private SSH path
remains available. Use the existing [VM setup](../macos-vm-gui-testing.md#build-connect-and-deploy)
and [guest permission workflow](../macos-vm-gui-testing.md#authorize-and-start-the-gui-executor)
to verify the guest identity and authorize the signed `UTMUIProbe` helper.

### Start the case

From the repository root, set `MESHCHAN_VM_CONFIG` to the verified private VM
settings file and `MESHCHAN_ARCHIVE` to the absolute parent directory
containing the trusted seal, restore evidence, and engineering assets.
Use a fresh case ID, and use it for `MESHCHAN_INSTALL_ID` in the guest
copy commands. Begin the case before Safari contacts the download server.
For a maintainer Beta upgrade repeat, run preflight before staging Beta
or its data in this guest.

```sh
MESHCHAN_CASE=rc1-build8-first-install
MESHCHAN_EVIDENCE="$PWD/build/phase-1e9/$MESHCHAN_CASE"
mkdir -p "$PWD/build/phase-1e9"
meshchan_case() (
  action=$1
  shift
  /opt/homebrew/bin/python3 -B tool/accept_installed_release.py "$action" \
    --vm-config "$MESHCHAN_VM_CONFIG" --run "$MESHCHAN_CASE" \
    --evidence "$MESHCHAN_EVIDENCE" "$@"
)
meshchan_case preflight &&
meshchan_case network --label before
```

Preflight records the guest identity and vacant target paths. It requires a
macOS arm64 guest with SIP and Gatekeeper enabled. The tool checks both
protections again during installed-file verification and before each
measured App launch. Without an independent first-exposure record, the
absence of a prior run leaves the first-exposure state unverified. Check
that `network-before.json` reports
`PASS` before proceeding. After a transient observation failure, rerun the
same network label if its receipt says `UNVERIFIED`. The tool retains each
earlier attempt. If an observation is interrupted, the tool saves the probe
results already collected before it exits. A `REACHABLE` receipt ends the
offline attempt for that case, including when another probe was interrupted.

After preflight, the tool reports collection and receipt errors and saves a
numbered `<action>-failure-<number>.json` when the case directory is writable.
It records the action, time, and error type. Keep these files with any pending
launch or other native evidence. Use the interrupted step's recovery
instructions before repeating a command.

Authenticate the frozen RC handoff before serving the candidate.

```sh
/opt/homebrew/bin/python3 -B tool/accept_installed_release.py inputs \
  --archive "$MESHCHAN_ARCHIVE" --output "$MESHCHAN_EVIDENCE/rc-inputs.json"
```

### Establish the Beta baseline for an upgrade repeat

For the upgrade case, set `MESHCHAN_BETA_EVIDENCE` to the absolute path
of the retained Beta build 5 evidence root. In the host Terminal, admit
the exact Beta App, complete CLI, and historical closed fixture, then
stage their owned copies after preflight.

```sh
/opt/homebrew/bin/python3 -B tool/accept_installed_release.py inputs \
  --beta-evidence "$MESHCHAN_BETA_EVIDENCE" \
  --output "$MESHCHAN_EVIDENCE/beta-inputs.json" &&
meshchan_case beta-stage --beta-evidence "$MESHCHAN_BETA_EVIDENCE"
```

The stage supplies `~/Applications/Meshchan.app`, the separate reference CLI
at `~/Library/Application Support/meshchan-engineering/beta-reference/<case ID>/meshctl/bin/meshctl`,
and the closed database set at `~/Library/Application Support/meshchan`.
The guest only receives the admitted SQLite files from the historical
fixture. The original Beta products and fixture stay intact on the host.
The tool verifies the private guest copy before publishing any destination.
If publication fails, it rolls back the destinations it can still identify as
owned by that attempt. If SSH disconnects before the host records a successful
stage, retry `beta-stage` with the same case ID and Beta evidence before
opening Beta. When the guest has committed the stage, the tool uses its
case-specific marker and rechecks the App, CLI, and closed SQLite files before
restoring the host receipt. If existing targets cannot be matched to that
publication, keep the failed attempt and use a verified vacant environment
for another case. The staging command refuses to replace occupied targets.

In the guest Terminal open the installed Beta App through LaunchServices
and retain its output in a fresh session.

```sh
BETA_SESSION=$(/usr/bin/mktemp -d "$HOME/utm-ui-isolation/package.XXXXXXXX") &&
  printf '%s\n' "$BETA_SESSION" &&
  /usr/bin/open --stdout "$BETA_SESSION/app.stdout" --stderr "$BETA_SESSION/app.stderr" \
    "$HOME/Applications/Meshchan.app"
```

Verify Beta's About information and wait for **Storage ready**. In the host
Terminal, set `BETA_SESSION` to the printed guest path and `MESHCHAN_PID`
to the Beta App's actual guest PID. Bind the live process to the admitted
Beta and this launch.

```sh
meshchan_case beta-observe --beta-evidence "$MESHCHAN_BETA_EVIDENCE" \
  --pid "$MESHCHAN_PID" --guest-session "$BETA_SESSION"
```

Quit Beta normally and wait for its process to disappear. Then capture
the typed Beta shutdown, closed default-directory SQLite files, and
complete public CLI projection. The case checks the guest database
against the admitted historical fixture and independently checks the
guest CLI output against a reference read of a disposable fixture copy.
It saves the resulting public projection for comparison with the
installed RC.

```sh
meshchan_case beta-baseline --beta-evidence "$MESHCHAN_BETA_EVIDENCE"
```

Keep the Beta closed database and its receipt until the case is complete.
If a later CLI read fails, run the same `beta-baseline` command again. It
rechecks the saved shutdown and SQLite files before retrying the CLI reads.

### Download and install the RC

For both cases, capture the native disk-image inventory and start the
console download verifier before Safari contacts the candidate. The mount
baseline requires the successful pre-exposure network probe. An upgrade
case must also have its verified Beta baseline before recording the RC mount.

```sh
meshchan_case mount-baseline &&
meshchan_case executor-start
```

The native disk-image inventory and its digest are saved together in
`mount-baseline.json`. If receipt publication was interrupted, retry
`mount-baseline` while the guest's download path is still vacant and
before opening the engineering URL. The download start time must be at or
after the saved baseline time. Later case commands recheck this order.

In a second host Terminal at the repository root, set `MESHCHAN_EVIDENCE`
to the same case evidence directory. Set `MESHCHAN_HOST_IPV4` and
`MESHCHAN_GUEST_IPV4` to the observed host and guest addresses on the private
Host Only network. The command below reads the asset directory from the
authenticated admission receipt. The server returns the pinned DMG and original
`SHA256SUMS` to that guest.

```sh
(
  set -e
  MESHCHAN_VERIFIED_DMG=$(jq -er '.engineeringDmg.path' "${MESHCHAN_EVIDENCE:?Set the case evidence directory}/rc-inputs.json")
  /opt/homebrew/bin/python3 -B tool/accept_installed_release.py serve \
    --assets "$(/usr/bin/dirname "$MESHCHAN_VERIFIED_DMG")" \
    --bind "${MESHCHAN_HOST_IPV4:?Set the private host IPv4 address}" \
    --client "${MESHCHAN_GUEST_IPV4:?Set the private guest IPv4 address}"
)
```

Set `MESHCHAN_DOWNLOAD_URL` to the URL printed by the server. In the first
host Terminal, set `MESHCHAN_DOWNLOAD_STARTED_AT` with
`/bin/date -u '+%Y-%m-%dT%H:%M:%SZ'` before entering the URL in guest Safari.
Use the same command to record `MESHCHAN_DOWNLOAD_FINISHED_AT` after Safari
finishes the transfer. Stop the server with Control+C and keep its log and
the browser records in the private evidence. Run the case download verifier
with the observed time bounds.

```sh
meshchan_case download --gui --url "$MESHCHAN_DOWNLOAD_URL" \
  --started-at "$MESHCHAN_DOWNLOAD_STARTED_AT" \
  --finished-at "$MESHCHAN_DOWNLOAD_FINISHED_AT"
```

The `--gui` option reads the original Safari file in the bound guest console
session. If macOS asks whether `UTMUIProbe` may read Downloads, use the native
per-folder grant for the integrity and metadata check. Let a pending read
finish. If the command has already returned an error, retry the read-only
verifier with the same download and time bounds after granting access.
Leave Gatekeeper, SIP, and the download's quarantine in effect. Once the
download receipt is recorded, run `meshchan_case executor-finish` to stop the
case executor while its guest run is still active. The mount command requires
the normal exit receipt for that same download executor. If SSH disconnects during
executor startup or finish, reconnect and check for the completed command
receipt. If it is missing, retry the interrupted command with the same
case ID. The tool can attest an executor that was already started or confirm
that the recorded executor finished. If `executor/launch.json` exists but
the guest run never bound to it, preserve the attempt and start a fresh
case once the earlier request has settled.

If you abandon a case before collecting the verified download, run
`meshchan_case executor-finish --abort` to stop its owned executor and
record the interruption. Start a fresh case for another attempt.

After opening the verified file in Finder, record its exact mount with
`meshchan_case mount` before copying. The tool checks the read-only volume's
UUID and hashes `image-payload.json` directly on that volume against the
accepted image manifest. Install the App in Finder and copy the CLI and
materials as described above. For the Beta upgrade, check the
existing App and capture the actual Finder replacement prompt before
choosing **Replace**. Verify the installed files against the same archive
while the measured image is still attached. The install and detach receipts
both identify that mount. The tool requires the matching install receipt
before detaching the image. Detach it before first launch.

```sh
meshchan_case install --label before --archive "$MESHCHAN_ARCHIVE" &&
meshchan_case detach
```

If SSH disconnects during detach, reconnect and check for `detach.json`
and the original attachment in the current disk-image inventory. When
the receipt is missing and the same attachment is still present, retry
`meshchan_case detach` with the same case ID. When the receipt is missing
and the attachment is already absent, preserve the case as interrupted
and start a fresh case. Acceptance requires the recorded detach of the
original attachment, so an unobserved absence leaves the case incomplete.

First open the installed App from Finder and complete its native approval.
Record that first launch separately and quit normally. macOS can redirect
output during approval. Complete the separate CLI approvals and verify its
use as described above.

If the App or a CLI component was moved to Trash during measured approval,
preserve the interrupted case and start a fresh one. Its install and detach
receipts bind one measured mount and cannot be regenerated for a recovery
copy. Restore the documented pre-contact snapshot or use an independent
guest again for a first-install claim. For a Beta repeat, start from vacancy
and stage the retained Beta products and closed fixture again.

### Measure installed offline use

With system approvals complete and the App closed, capture the installed
CLI's baseline public projection and observe the bundled SQLite image
that the CLI actually loads.

```sh
meshchan_case cli --label before &&
meshchan_case cli --label mapping &&
meshchan_case open-request --label initial
```

Collect both CLI observations before the initial measured launch. The tool
validates the initial projection and the SQLite mapping receipt before
requesting that launch.

If SSH disconnects during either `open-request`, reconnect and inspect
the matching `launch-<label>.json` receipt. If it exists, use the recorded
session. When its `open-exit` is `0` and the original App is live, use the
matching `runtime` command with its observed PID. If the recorded launch
cannot be attested, preserve the receipt and use a fresh case after the
pending request has settled. With no launch receipt, the request can be
run again after checking that the App has no live process.

The baseline for a first install has an empty draft list, no profiles or
History, and default settings. The Beta upgrade baseline must preserve
the public projection collected from the closed Beta case. The CLI
mapping observation checks the installed SQLite file against the live
device and inode and its frozen digest. The observer is built on the
host and runs as a test helper in the guest. If the observation is interrupted,
its `cli-mapping-attempt-package.*` directory records the guest session and log
path. Keep this receipt with the case evidence.

Wait for the installed App to show **Storage ready**. Set `MESHCHAN_PID`
to its observed guest PID and record the launch and directory owner. The
separate installed CLI read must return `data_directory_busy` with exit
69 while the App still owns the default directory.

```sh
meshchan_case runtime --label initial --pid "$MESHCHAN_PID" &&
meshchan_case cli --label busy
```

Before writing, choose the exact draft title and UTF-8 multiline body to save
and record both as expected input. For example, in the host Terminal:

```sh
TITLE='Engineering acceptance 中文 🛰️'
MESHCHAN_BODY_FILE="$MESHCHAN_EVIDENCE/expected-draft-body.txt"
(set -C; printf '%s\n%s\n%s' 'First line' '第二行 🙂' 'Last line' > "$MESHCHAN_BODY_FILE")
```

In the guest App, create and save one draft using that title and body. In
**Profiles and settings → Settings**, change **Diagnostic history limit**
to 1002 and choose **Save settings**. Keep every other setting and
existing record intact.
Preserve GUI evidence of the saved draft and the setting. Quit normally
and wait for the process to disappear before collecting the typed shutdown
receipt and locked SQLite snapshot. Then use the installed CLI to read the
updated default directory with the App closed.

If extracting or checking the SQLite copy fails, keep the App closed and
retry the same `closed` command after resolving the error. The snapshot
directory and its receipt are published together after SQLite projection
succeeds. If writing the outer case receipt is interrupted, retry the same
command. It verifies the archived shutdown and database for that launch
before restoring the case receipt.

```sh
meshchan_case closed --label initial &&
meshchan_case cli --label after &&
meshchan_case open-request --label reopen
```

Capture the CLI contention observation while the initial App is still
running, before collecting its close receipt. Save the settled CLI
projection after that close and before requesting the measured reopen.

After the App reopens, confirm the exact title, multiline body, and setting
in the GUI. Set `MESHCHAN_PID` to the new PID. Record that runtime, quit
normally, and capture the close and final network probe.

```sh
meshchan_case runtime --label reopen --pid "$MESHCHAN_PID"
```

After Quit and process exit:

```sh
meshchan_case closed --label reopen &&
meshchan_case network --label after
```

For a first install, compare the captured records to the empty baseline.

```sh
meshchan_case compare --title "$TITLE" --body-file "$MESHCHAN_BODY_FILE" --history-limit 1002
```

For the upgrade, compare the original Beta data with the RC baseline, the
two closed RC snapshots, and the CLI readback.

```sh
meshchan_case compare --beta --title "$TITLE" --body-file "$MESHCHAN_BODY_FILE" --history-limit 1002
```

After the comparison passes, recheck the installed files and frozen inputs.
Comparison reopens disposable copies of the archived SQLite files and
verifies their hashes against the close receipts. It also binds each close
to its launch session and checks the saved network and CLI mapping evidence.
The final install check repeats that evidence comparison before verifying
the installed files. For an upgrade, it also reauthenticates the original
Beta App, CLI, source materials, and closed fixture recorded when Beta was
staged. Keep the admitted Beta evidence available at the original path
until this check passes.

Keep the case image detached and the App and CLI closed through this final
verification. The tool checks the live image attachment, App processes, and
default storage ownership before and after validating the installed files.
It also rechecks Gatekeeper and SIP at the end and records the final
observations in `install-after.json`. If the tool reports an active owner
or an attached case image, close the owner normally or eject the case
image before retrying.

```sh
meshchan_case install --label after --archive "$MESHCHAN_ARCHIVE"
```

Keep the evidence of the native approvals and all case receipts. Use the
VM guide to disconnect and retire temporary access. Run
`/opt/homebrew/bin/python3 -B tool/accept_installed_release.py --help`
for the command list.

### Engineering support scope

The engineering support scope for this candidate is **macOS 27.2.1
(26B131) arm64**. The independent first install and the separate
Beta-to-RC upgrade both passed on that system, including native approval
and offline App and CLI use. This is the lowest tested macOS version.
The candidate's App plist declares macOS 12.0. The embedded serial and
SQLite libraries require macOS 13.0, and the CLI executable requires
macOS 14.0. Those values describe the static loader requirements. Earlier
macOS versions are outside the measured engineering support scope.
