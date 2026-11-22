# Meshchan RC1 engineering guide for macOS

This guide applies to Meshchan App `0.1.0-rc.1+9` and `meshctl 0.1.0-rc.1`
from the same Apple silicon disk image. About Meshchan shows `0.1.0-rc.1 (9)`.
The Apple bundle short version is `0.1.0`, its build is `9`, and its identifier
is `org.meshchan.meshchan`. The product was built from
`01cfacb7fc166a0078962a99d9e673750aabad65`.

Use Drafts, Profiles and saved diagnostic presets, Settings, and diagnostic
History offline. History can export one page of redacted summaries. For device
work, the App provides an explicit USB Device Check, one finite PING or
Responder operation, and recording of those diagnostics. The complete CLI also
offers offline commands and finite USB diagnostics. Select a MeshCore USB
Companion each time. The source-only OpenHop peer is a development acceptance
tool. The release connection path is USB. The scope excludes BLE, background
receiving, content syncing and distribution, automatic reconnect or resend,
mobile platforms, and Intel Macs.

Both installed products carry local ad hoc code signatures. The read-only DMG
is unsigned and unnotarized. macOS may require approval for individual items.
Build 9 had finite installed USB and RF checks on macOS 27.2.1 (26B131) arm64.
The recorded first install with quarantine and Beta build 5 upgrade on that
macOS version used RC build 8. See the [engineering release notes](rc1-engineering-release-notes.md).

## Verify the download

The planned download entry is GitHub Releases. Use the entry for this engineering
build when it provides the actual DMG, `release-manifest.json`,
`RELEASE-SHA256SUMS`, and the original image `SHA256SUMS`. Compare the entry and
checksums with the identity below before opening the image. Keep the downloaded
file and its original download attributes. [Meshchan Releases](https://github.com/007pig/meshchan/releases)

| Check | Expected value |
| --- | --- |
| File name | `Meshchan-0.1.0-rc.1-build9-macos-arm64-local.dmg` |
| Size in bytes | `676240035` |
| SHA-256 | `49e25d6580486276850177fc51f68093462c26212daa0b12770ed7b6e26d66f2` |

Open Terminal. If you saved the file elsewhere, set `MESHCHAN_DOWNLOAD` to the
actual download folder. Use the same Terminal session for the later steps.

```sh
MESHCHAN_DOWNLOAD="$HOME/Downloads"
MESHCHAN_DMG="$MESHCHAN_DOWNLOAD/Meshchan-0.1.0-rc.1-build9-macos-arm64-local.dmg"
/usr/bin/stat -f '%z' "$MESHCHAN_DMG"
/usr/bin/shasum -a 256 "$MESHCHAN_DMG"
```

Stop if the file name, byte count, or full digest differs. The original
`SHA256SUMS` covers the DMG. `RELEASE-SHA256SUMS` covers the final attachment
set and manifest. To check either list with Terminal, put all the files named
in that list together in the download folder first.

```sh
(cd "$MESHCHAN_DOWNLOAD" && /usr/bin/shasum -a 256 -c SHA256SUMS)
(cd "$MESHCHAN_DOWNLOAD" && /usr/bin/shasum -a 256 -c RELEASE-SHA256SUMS)
```

## Install the complete App, CLI, and materials

If you already use Meshchan, start with [Back up and upgrade](#back-up-and-upgrade).
In Finder, open the verified DMG. In Terminal, run `/usr/bin/hdiutil info -plist`.
Find the attachment whose `image-path` is the exact downloaded file. Confirm
that `writeable` is false and note the `mount-point` under `/Volumes`. If the
attachment is ambiguous or writable, stop before copying.

The example below creates a fresh installation under your account's
Applications folder. Set `MESHCHAN_VOLUME` to the mount point just verified.
For a custom installation, set `MESHCHAN_INSTALL_PARENT` to an absolute folder
path and `MESHCHAN_INSTALL` to a new folder inside it. Keep the quotes around
these paths. Use a separate folder from your Meshchan data.

```sh
MESHCHAN_VOLUME='/Volumes/Meshchan 0.1.0-rc.1 build 9'
MESHCHAN_INSTALL_PARENT="$HOME/Applications"
MESHCHAN_INSTALL="$MESHCHAN_INSTALL_PARENT/Meshchan Engineering Build 9"
MESHCHAN_PAYLOAD='Meshchan-0.1.0-rc.1-macos-arm64'
MESHCHAN_SIGNED_ROOT="$MESHCHAN_INSTALL/$MESHCHAN_PAYLOAD"
MESHCHAN_APP="$MESHCHAN_SIGNED_ROOT/Meshchan.app"
MESHCHAN_CLI="$MESHCHAN_SIGNED_ROOT/meshctl/bin/meshctl"

(
  set -e
  mkdir -p "$MESHCHAN_INSTALL_PARENT"
  mkdir "$MESHCHAN_INSTALL"
  /usr/bin/ditto "$MESHCHAN_VOLUME/$MESHCHAN_PAYLOAD" "$MESHCHAN_SIGNED_ROOT"
  for MESHCHAN_ITEM in README-engineering.md dmg-source image-payload.json; do
    /usr/bin/ditto "$MESHCHAN_VOLUME/$MESHCHAN_ITEM" "$MESHCHAN_INSTALL/$MESHCHAN_ITEM"
  done
  /usr/bin/codesign --verify --deep --strict --all-architectures "$MESHCHAN_APP"
  for MESHCHAN_CODE in "$MESHCHAN_CLI" \
    "$MESHCHAN_SIGNED_ROOT/meshctl/lib/liblibserialport_plus.dylib" \
    "$MESHCHAN_SIGNED_ROOT/meshctl/lib/libsqlite3.dylib"; do
    /usr/bin/codesign --verify --strict --all-architectures "$MESHCHAN_CODE"
  done
)
```

Continue only if the copy and every signature check succeeded. An existing
destination makes the copy stop before it overwrites those files. Keep all of
`meshctl/` together, including `bin/meshctl`, the serial library, and the SQLite
library. Keep the complete product folder and the accompanying image materials
for source and replacement access. The signature checks verify code integrity.
Use the trusted release identity and checksums to verify the download's origin.

In Finder, eject the verified image. You can also use
`/usr/bin/hdiutil detach "$MESHCHAN_VOLUME"` after rechecking its mount point.
Confirm it is gone from Finder before launching the installed App and CLI.

## Open the installed products

In Finder, go to the new installation folder, open
`Meshchan-0.1.0-rc.1-macos-arm64`, and open its `Meshchan.app`. Confirm
**Storage ready** and the RC build in About. Open that copy for subsequent use.
In Terminal, check the full installed CLI from your home folder.

```sh
cd "$HOME"
"$MESHCHAN_CLI" --version
"$MESHCHAN_CLI" --help
```

Expect `meshctl 0.1.0-rc.1`. `MESHCHAN_CLI` must be the absolute path to the
installed `meshctl/bin/meshctl` in any new Terminal session. Ordinary use of the
complete bundle requires only macOS and its built-in tools. Flutter, Dart,
Python, Homebrew, and Xcode are development or rebuild tools.

If macOS blocks an item because it cannot check or identify its developer, first
confirm the verified download and installed signatures and check which item the
alert names. If you trust that item and macOS offers an exception, select
**Done** to dismiss the alert, open **System Settings → Privacy & Security**,
and use the approval offered for that specific item. For the App this may be
**Open Anyway**. For a CLI item, retry the same command after the item approval
and follow the confirmation or authentication prompt. Leave Gatekeeper, System
Integrity Protection, and download quarantine in place. If the system reports
damage or malware, or there is no permitted exception, stop and report the
exact alert. [Safely open apps on your Mac](https://support.apple.com/en-us/102445)

The Build 8 first-install guest required separate App, CLI executable, and CLI
SQLite approvals. The local Build 9 hardware run successfully loaded the
installed serial library during device work. Its record covers that load and
operation. An independent serial-library approval prompt for a quarantined
Build 9 download remains unverified. Expect macOS behavior to vary by system
policy and by the source of the download.

If the system moved a CLI executable or library to Trash, treat that CLI as
incomplete. Use the verified DMG to copy the entire installation into a fresh
folder, recheck the signatures, eject the image, and repeat normal item approval
for the new path.

## Use the data directory and quit normally

The App and CLI default to `~/Library/Application Support/meshchan` on macOS.
The directory is separate from the installed App and CLI. One process owns the
directory at a time, including for reads. If the App owns it, CLI business
commands return `data_directory_busy` with exit code `69`. To switch owners, use
**Meshchan → Quit Meshchan** or Command-Q, resolve any unsaved edits, and wait for
the process to exit. Normal Quit settles active work, closes resources and
storage, and waits for the worker and directory owner to release. Wait for the
CLI process to finish before opening the App again. Keep the ownership file and
SQLite files intact if a close stalls or reports unconfirmed cleanup.

The following reads use the default directory. Run them only after the App has
quit. A business read can perform startup recovery or apply history retention.
Back up the closed data directory before opening it for inspection if you need
to preserve its exact bytes.

```sh
"$MESHCHAN_CLI" draft list --json
"$MESHCHAN_CLI" profile list --json
"$MESHCHAN_CLI" settings show --json
"$MESHCHAN_CLI" history list --json
```

To use a different data directory, choose an absolute path you own. Use the
same path for both products, one at a time. Put the CLI's global `--data-dir`
before the business command. Pass the App's `--data-dir=/absolute/path` at
launch, after all running copies have quit. The App requires an absolute path
without dot segments. Adjust this example to your actual directory.

```sh
MESHCHAN_DATA="$HOME/Library/Application Support/Meshchan Test Data"
"$MESHCHAN_CLI" --data-dir "$MESHCHAN_DATA" draft list --json
/usr/bin/open -a "$MESHCHAN_APP" --args "--data-dir=$MESHCHAN_DATA"
```

`ports`, `port-check`, `info`, and `watch` bypass business storage. Use them
without `--data-dir`. Finite `datagram` commands use business storage, including
when recording is off. Put `--data-dir` before `datagram` if you need an override.

## Back up and upgrade

1. Check About and `meshctl --version` for your existing products and identify
   the directory they use. Save intended changes, quit normally, and wait for
   the App and every CLI process using the directory to exit.
2. Copy the entire closed data directory to a fresh private backup. Preserve
   every file, including any SQLite `-wal`, `-shm`, or `-journal` companions.
   Keep the original directory closed until the backup is complete. In this
   example, substitute your actual data directory if you used an override.

   ```sh
   MESHCHAN_DATA="$HOME/Library/Application Support/meshchan"
   (
     set -e
     test -f "$MESHCHAN_DATA/meshchan.sqlite"
     MESHCHAN_BACKUP=$(/usr/bin/mktemp -d "$HOME/Library/Application Support/meshchan-backup.XXXXXXXX")
     /usr/bin/ditto "$MESHCHAN_DATA" "$MESHCHAN_BACKUP/data"
     printf 'Closed data backup: %s\n' "$MESHCHAN_BACKUP/data"
   )
   ```

3. Verify the new DMG, install the complete App, CLI, and materials in a fresh
   location, and eject the image. Switch your Finder and CLI launch paths to
   the new pair. Keep the retired pair closed. If you replace files at an
   existing installation location, replace the complete App and complete CLI
   directory together after checking that location is yours.
4. Open the installed App on the same data directory. Check About, then verify
   existing drafts, profiles, settings, and History. Make one intended offline
   save, quit normally, and wait for exit. Confirm the old and new records with
   the matching installed CLI, or reopen the App and check the saved change.
   Quit normally again.

The recorded Beta upgrade was `0.1.0-beta.1+5` to `0.1.0-rc.1+8` on macOS
27.2.1 (26B131) arm64. Build 9's local host install for finite hardware checks
used a separate fixture. Full clean downloaded first install and Beta upgrade
remain open for this image. Keep a closed backup for recovery. Downgrade,
automatic restore, and import are outside this engineering procedure. To remove
the installation, first quit and wait for exit, then remove your chosen App and
CLI installation. Keep the separate data directory for future use or backup.

## Use a selected USB Companion

1. Connect the intended USB Companion. In **Device**, select **Refresh** and
   explicitly choose the current port for that device. Recheck the selection
   if the device is moved or replugged. Startup and page navigation leave USB
   alone.
2. Select **Check device** and wait for its result and resource close. Check
   opens and configures the port, can reset some boards, and changes the device
   session state. A successful closed Check provides a historical snapshot.
   RF exchange and sustained connectivity require separate evidence.
3. For a finite RF diagnostic, go to **Diagnostics**, choose PING or Responder,
   and review the preset and effective parameters in Preview. Start and record
   only the intended operation. Preview is offline. Use an authorized radio
   setup and wait for the result and cleanup. A local send confirmation alone
   gives no peer receipt. An exact PONG from the intended peer provides a
   finite round trip.
4. To stop an active operation, select **Cancel** and wait for the terminal
   result and confirmed cleanup. Normal **Quit Meshchan** also waits for
   cleanup and worker exit. If initialization fails, record the stage and
   cleanup result. When cleanup is unknown, leave the operation undisturbed
   and report the state before another attempt.

To see the installed CLI's equivalent option contracts, use the help commands.
`port-check` opens then closes a specific port and can reset some boards.
`info` initializes once and prints a closed-connection snapshot. `watch`
observes one session and can take a finite `--duration`. All three take an
explicit `--port` with the actual current device path. Close the App's device
operation before handing the port to the CLI.

```sh
"$MESHCHAN_CLI" ports --help
"$MESHCHAN_CLI" port-check --help
"$MESHCHAN_CLI" info --help
"$MESHCHAN_CLI" watch --help
"$MESHCHAN_CLI" datagram --help
```

The App and CLI share a Build 9 initialization compatibility path for the
recognized Heltec V4.3 OLED USB Companion. It helps handle a bounded startup
prefix and uses a device-specific completion query. Initialization can still
fail. Tested behavior is limited to the selected board and finite runs. Board
coverage, range, throughput, and long-run reliability are unverified. The
follow-up implementation in PR #49 uses different source and binary bytes.
Read the technical description pinned to this image's source cut. [Build 9 Device Check source notes](https://github.com/007pig/meshchan/blob/01cfacb7fc166a0078962a99d9e673750aabad65/apps/meshchan_app/README.md#explicit-finite-device-checks-1d6)

## Report an issue

Review the smallest relevant excerpt before submitting. CLI `info` may contain
the actual serial path, a node name, and a public key prefix. Review these fields
and remove identifying details as needed. History's one-page redacted summary
is still data to review before sharing, and a restorable backup needs the full
closed directory. Keep full databases, draft contents, all logs, channel keys,
BLE PINs, private peer endpoints or credentials, and raw frames out of public
reports. [Meshchan Issues](https://github.com/007pig/meshchan/issues)

For a startup issue, Build 9 has optional `MESHCHAN_USB_INITIALIZATION_TRACE=1`
for the affected App or CLI process. The trace writes JSON lines to stderr with
`usbInitialization` events. Depending on the event, it can report prefix or
buffered byte counts, a recovery flag, and stage, transport, or framing error
kinds. It is off by default. Use it only for a startup operation you are already
authorized to repeat. Review other stderr diagnostics separately before sharing
an excerpt. [Build 9 trace implementation](https://github.com/007pig/meshchan/blob/01cfacb7fc166a0078962a99d9e673750aabad65/packages/meshcore_link/lib/src/transport/usb_initialization_transport.dart)

```text
App version and build:
CLI version:
DMG name, SHA-256, and installation source:
macOS version and build, architecture:
Companion model, firmware, protocol code (if known):
Date, time, and time zone:
Steps to reproduce (redact serial paths and display names):
Expected result:
Actual result and error kind, stage, or exit code:
Cleanup or Quit result (confirmed, failed, or unknown):
Small reviewed output excerpt, if relevant:
```

## Find source, licenses, or replacement instructions

Start at `materials/` inside the installed `Meshchan-0.1.0-rc.1-macos-arm64/`
folder. The [source and materials index](rc1-engineering-source-materials.md)
maps the project license, third-party notices, corresponding sources, and
rebuild and native-library replacement materials inside this exact disk image.
