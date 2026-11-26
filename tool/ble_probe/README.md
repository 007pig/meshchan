# Meshchan BLE Probe

This standalone macOS Flutter host validates the Companion `DEVICE_QUERY` and
`APP_START` exchange over Nordic UART Service (NUS). It uses the public
`meshcore_link` session and codec from a fixed copy of the repository. The
private Bluetooth transport runs on the root isolate in both modes. In
worker cooperation mode, the existing runtime runs the session, device gate,
and external SQLite fixture on a spawned isolate. Both modes issue only
those two Companion commands.

The package is `meshchan_ble_probe`, the app is `Meshchan BLE Probe`, and its
bundle identifier is `org.meshchan.probe.ble2a3`. The host is non-sandboxed and
uses a local ad hoc signature. See the [Step 4 validation record](../../docs/validation/phase-2a4-ble-worker.md)
and [historical Step 3 record](../../docs/validation/phase-2a3-ble-host.md).

## Generate and verify the host

From the Meshchan checkout, use the repository's required Python toolchain
and the existing Flutter SDK. Choose a new absolute destination outside the
checkout. The preparation command resolves the generated host before returning.

```sh
probe_flutter=/opt/homebrew/share/flutter/bin/flutter
probe_dart=/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart
probe_root=/private/tmp/meshchan-2a4-probe
/opt/homebrew/bin/python3 --version
"$probe_flutter" --version
/opt/homebrew/bin/python3 tool/prepare_ble_probe.py \
  --destination "$probe_root" --flutter "$probe_flutter"

cd "$probe_root/host"
"$probe_dart" format --output=none --set-exit-if-changed lib test tool
"$probe_dart" analyze --fatal-infos
"$probe_flutter" test --no-pub --concurrency=1
env PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin \
  "$probe_dart" --disable-analytics run tool/check_worker_cooperation.dart
"$probe_flutter" build macos --release --no-pub

probe_app="$PWD/build/macos/Build/Products/Release/Meshchan BLE Probe.app"
probe_plist="$probe_app/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict --all-architectures --verbose=2 "$probe_app"
/usr/bin/codesign --display --verbose=4 "$probe_app"
/usr/bin/codesign --display --entitlements - "$probe_app"
/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$probe_plist"
/usr/bin/plutil -extract NSBluetoothAlwaysUsageDescription raw -o - "$probe_plist"
probe_executable=$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$probe_plist")
/usr/bin/lipo -archs "$probe_app/Contents/MacOS/$probe_executable"
```

The source snapshot defaults to `HEAD`. `--source` selects an explicit Git
commit for both package snapshots and the App runtime import closure.
Preparation copies the tracked package inputs and licenses into
`vendor/meshcore_link` and `vendor/meshchan_core`, removing
`resolution: workspace` from each copied manifest. The host resolves the
two copies by relative path and retains the runtime in `host/lib/runtime`.
The preparation receipt binds the Git snapshots, original and transformed
manifests, working-tree templates and patches, locked dependencies, and
generated native inputs to their hashes.

The host restores its own [`pubspec.lock`](pubspec.lock) and resolves with lock
enforcement. All three BLE modules use 6.2.1. The Darwin path override is
prepared from the hash-verified Pub archive and carries its original MIT notice.
[`darwin-observation.patch`](darwin-observation.patch) records structural
CoreBluetooth callback metadata alongside the plugin's existing delivery path.
The generator applies [`darwin-lifecycle.patch`](darwin-lifecycle.patch) after
the observation patch. It settles pending connection and cancellation requests
after a native terminal callback and lets a verified reconnect bind the freshly
discovered TX characteristic. The Phase 2A.3 ledger identifies the hashes
used in the real host runs and the separate software checks for this fix.
Use `--darwin-archive` with a local copy of that exact archive when needed.
`--offline` also requires the remaining locked hosted packages in the local Pub
cache. The [Phase 2A.2 archive record](../../docs/validation/phase-2a2-protocol-backends.md#ble-release-archives)
identifies the original release archives.

## Offline startup and synthetic UI

The normal app opens offline. **Start scan** is the first action that can create
the real BLE manager and invoke macOS Bluetooth authorization. For hardware-free
native GUI checks use the configured guest following the [VM guide](../../docs/macos-vm-gui-testing.md)
and [repository VM skill](../../.agents/skills/macos-vm-gui-testing/SKILL.md).
During the default offline launch, choose **View evidence** and **Read manager
counts** before starting a scan. This reads passive creation counters. Expect
zero central and zero peripheral managers and record any actual permission
prompt or its absence. Verify **Close** or Command-Q in the guest before running
the separate synthetic mode. With `probe_app` set to the deployed bundle path
in the guest, use the following command after the offline app has quit.

```sh
/usr/bin/open "$probe_app" --args --fake-backend
```

The title displays **Synthetic** in this mode. **Start scan** exposes one
in-memory result. Select **Synthetic Companion**, choose **Known fixture**, and
choose `4` for **On-wire node name bytes**. The fake delays connect briefly for
Cancel and responds to a successful attempt with 82 and 62 bytes. Its callbacks,
write limits, and release are synthetic. Widget tests inject the same fake
boundary and exercise controls without AppKit or a Bluetooth adapter.

## Worker cooperation

Launch the verified bundle with the worker mode flag. Both switches are exact
and can be combined for the hardware-free guest fixture.

```sh
/usr/bin/open -n "$probe_app" --args --worker-cooperation
/usr/bin/open -n "$probe_app" --args --worker-cooperation --fake-backend
```

Open one instance for the scenario. **Start worker** explicitly starts the
existing runtime and makes a new owned temporary directory for SQLite. The scan
control becomes available after the worker has committed and read a fixed
fixture draft. **Copy fixture path** provides the directory for an independent
process and should be handled separately from the structural receipt.
From the generated host directory, use the bundled Dart SDK:

```sh
env PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin \
  "$probe_dart" --disable-analytics run tool/check_cooperation_storage.dart busy "$probe_fixture"
env PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin \
  "$probe_dart" --disable-analytics run tool/check_cooperation_storage.dart reopen "$probe_fixture"
```

The explicit PATH selects Apple Clang for the locked native asset hooks.
Run `busy` while the probe's owner is active. Run `reopen` after the probe
has quit and an independent process check confirms exit. Reopen verifies the
exact fixture draft and empty diagnostic History. At startup, case settlement,
and Quit the worker mode writes a structural `cooperation-evidence.json` into
the fixture. **View evidence** offers the current receipt without showing
selection data, device information, raw frames, or the fixture path.
If the final file write fails after release, the probe opens **View evidence**
and keeps the window open. Retry **Close probe** to save the receipt again, or
use **Copy evidence JSON** and save the copied receipt to a controlled local
file before closing the probe. If the clipboard changes before Close, the
probe retries the file write. If it still fails, copy the final evidence again.

Follow the worker pass criteria in step 5 of [Run one real scenario](#run-one-real-scenario).
The worker's production Device Check encodes a 2-byte query and a 16-byte
start. The original root mode encodes a 26-byte start. The cooperation
runtime's own request deadline is 30 seconds. AppKit window Close, Command-Q,
and **Close probe** share the release barrier. The final receipt distinguishes
BLE, device check and observer, storage, runtime report and acknowledgement,
worker exit, and bridge port cleanup.

The cooperation harness wraps its private attempt token in a `UsbSerialTarget`
to enter the App's typed Device Check path. The injected worker factory
extracts the token for the existing bridge proxy, and the probe keeps physical
BLE ownership on the root isolate. The token stays inside the probe harness,
and the product App continues to admit only USB connections.

## Run one real scenario

Before using the real backend, privately confirm the exact target identity,
model, chip, firmware revision, BLE build mode and selection method. Confirm
the expected NUS service, device RX with-response write and device TX notify,
ordinary macOS permission/pairing, exclusive command access across every active
target interface, and the absence of pending replies from prior clients. Keep
the preconnection name length `N` as a byte count from an independent known
fixture or device configuration using the firmware's encoding and truncation
behavior. The pinned firmware copies the byte count before the first NUL from a
32-byte name field, with at most 31 bytes for a normally configured name. Its
response layout expects 82 bytes for `DEVICE_INFO` and `58 + N` bytes for
`SELF_INFO`. Keep the name and pairing material private.
[Name field](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/NodePrefs.h#L15) · [Response layout](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/MyMesh.cpp#L979-L1036)
Use only a separately confirmed and authorized control for a negative scenario
such as a peer disconnect, denial or powered-off state.

1. Launch the verified Release bundle on the authorized host Mac without
   `--fake-backend`. For worker mode, pass `--worker-cooperation` and click
   **Start worker** before scanning. In **Length source**, choose the
   preconnection basis and select `N` in **On-wire node name bytes**.
2. Click **Start scan**, handle any macOS permission request through system UI,
   and explicitly identify the intended result by the locally displayed name
   and identifier. **Stop scan** can end discovery before the 10-second budget.
   Proceed only with an identified target and confirmed scan stop.
3. Select that result and click **Connect and query** once. Handle any expected
   pairing in macOS system UI. Leave PINs out of probe entry fields, command
   histories, screenshots and shared artifacts. Initialization has one 15-second
   budget, including connect, GATT and notify readiness, and each Companion
   request has a separate 5-second limit within it.
4. **Cancel / Disconnect** ends an in-progress attempt. The probe also begins
   cleanup when logical execution finishes. Stop the scenario on an unexpected
   target, profile or pairing flow, an unconfirmed receipt, any mismatch or the
   first failure. Follow the separate negative-scenario prerequisites and record
   each outcome independently.
5. Read the final status after cleanup. Both modes require **Both response
   receipts confirmed** under **Notifications**.

   - In root mode, require **Query and start passed** under **Logical result**
     and **Release confirmed** under **Release**.
   - In worker mode, require **Worker query and start passed** under
     **Logical result**, **Root and worker release confirmed** under
     **Release**, and `caseSettled.passed: true` in the structural receipt.

   Use **View evidence** to
   replace the controls with the structural receipt, then **Copy evidence JSON**
   to export it to a controlled local file of your choosing. Capture screenshots
   from the evidence view rather than the selection or pairing UI. The export
   contains attempt, timing, state, opcode, lengths and outcome metadata. It
   omits peripheral identity, advertisements, node text, PIN and raw frames.
   Only structural evidence should enter the validation record.

Logical success requires independent notification provenance, both expected
length matches, and both correlated writes and responses. Release requires
observed local app-connection settlement, subscription retirement, and pending
platform work settlement. The release observation window runs for at most 10
seconds after the logical result. If it expires with incomplete evidence, the
window reports unconfirmed release and keeps the device slot unavailable.
Closing the window or using Command-Q requests the same cleanup. The window
stays open when release cannot be confirmed. The probe can offer one explicit
reconnect to the same target and fixture. Root mode requires confirmed release
and no notification provenance fault. Worker mode requires a passing case
in the same runtime.
The returned write maxima and observed query/start lengths only characterize
those operations. Maximum-size writes, notifications and channel activity
remain separate validation work.

## Finish the local run

Stop a running scan or cancel an active attempt, retain the structural export
and preparation receipt, and close the probe after confirmed release. Confirm
the owned probe process has exited. Record any exceptional process termination
as such and preserve its last known cleanup state. Retain the signed bundle
and its associated evidence for handoff. For a disposable run, remove only the
explicit external directory you created after its process has exited and its
required evidence has been saved.
