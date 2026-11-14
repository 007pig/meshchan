# macOS VM GUI testing with UTM

Run the event generator inside a logged-in macOS guest and orchestrate it over
SSH. This leaves the host pointer and keyboard available while the guest changes
focus, clicks and types. The repository skill is
[macos-vm-gui-testing](../.agents/skills/macos-vm-gui-testing/SKILL.md).
The bundled executable probes exercise TextEdit; Meshchan needs its own product
fixture and input-target checks.

## Install and configure a new guest

On an Apple silicon Mac, install UTM and create an Apple-virtualized macOS VM
using UTM's macOS installation flow and a compatible restore image. Retain a
virtual display and use Shared Network. Complete Setup Assistant inside the VM,
create a local test account, and enter the desktop. An Apple Account is not
needed for these probes. Let the operator choose the password; never put it in
configuration, scripts, reports or version control.

The historical VM was already installed when this work began. Setup Assistant
was completed by the user. Its restore-image URL, installation clicks, disk size
and initial installation duration were not recorded. The preceding paragraph is
setup guidance, not a claim that those installation steps were observed.

In the **guest**, open System Settings → General → Sharing → Remote Login.
Enable it for only the local test account. In the validated setup the access
list contains `meshchantest`, and Full Disk Access for remote users remains off.
Use the guest's network settings or `ifconfig` to find its Shared Network IP.
DHCP addresses can change; verify rather than assuming the example IP persists.

Record identity from a guest Terminal:

```bash
sw_vers
sysctl -n hw.model
ioreg -rd1 -c IOPlatformExpertDevice | awk -F '"' '/IOPlatformUUID/ {print $(NF-1)}'
stat -f %Su /dev/console
csrutil status
system_profiler SPDisplaysDataType
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

On the host, obtain the candidate public key using `ssh-keyscan -t ed25519 IP`,
compare its `ssh-keygen -lf` fingerprint with the guest Terminal output, and only
then save the verified entry to a dedicated known-hosts file. Scanning alone does
not authenticate a guest. Preserve `StrictHostKeyChecking=yes`. If the key or
UUID changes, re-establish identity before updating private configuration.

Keep the guest logged in and unlocked and both machines awake during a run.
Release UTM input capture before concurrent host-use testing. Initial setup may
operate the VM window; formal isolation measurements use SSH only on the host.

## Build, connect and deploy

The following commands run from the repository root on the validated host.
Python is `/opt/homebrew/bin/python3` (3.15.2); verify it before running scripts.
Building also requires Xcode's Apple clang/macOS SDK, `codesign`, and network
access for the pinned cliclick release on the first build. No Homebrew install
inside the guest is required.

```bash
/opt/homebrew/bin/python3 --version
mkdir -p /private/tmp/meshchan-vm
cp .agents/skills/macos-vm-gui-testing/config.example.json /private/tmp/meshchan-vm/config.json
/opt/homebrew/bin/python3 .agents/skills/macos-vm-gui-testing/scripts/vm.py build \
  --output /private/tmp/meshchan-vm/build
```

Edit the private JSON: `host`, `user`, `uuid`, `known_hosts`, `runtime_dir`,
`evidence_dir`, and `guest_root`. Use a dedicated guest path under the test
account's home. Runtime sockets, build output and collected evidence belong
outside the repository. The example identity describes the historical VM only.
The JSON is data, not a shell script; it contains no password.

For the remaining examples, define a shell function:

```bash
vm() {
  /opt/homebrew/bin/python3 .agents/skills/macos-vm-gui-testing/scripts/vm.py \
    --config /private/tmp/meshchan-vm/config.json "$@"
}
vm connect
vm check
vm deploy --build-dir /private/tmp/meshchan-vm/build
```

`connect` lets SSH prompt normally for authentication, opens a temporary control
connection and checks guest identity. It does not store a password or install an
SSH key. Every subsequent remote action uses batch authentication, strict host
keys, exact hardware UUID, a VirtualMac model and the test account's console
session. A closed control connection requires reconnecting unless another
already-authorized SSH authentication method is available.

### Optional local credentials

When the user explicitly requests stored credentials for a disposable test VM,
the private configuration can contain `credentials_file`, pointing to a regular
file owned by the host user with mode `0600`, outside the repository. That JSON
has `user`, `host`, `uuid` and `password` fields. The first three must exactly
match the private VM configuration. On this host the user requested
`~/.config/meshchan-vm/credentials.json`; only its location is documented here.
The durable private configuration and independently verified host key are kept
alongside it as `config.json` and `known_hosts`, so host temporary-directory
cleanup does not discard those setup facts. Verify their current identity before
reuse; these local files are not repository or installation dependencies.
Do not print, collect or commit its contents. No credential is provided by the
repository example or installed automatically for another user.

The controller uses SSH's askpass protocol with the selected `sys.executable`;
the password is not a command-line argument. With this option it can establish
a new temporary connection before an operation if the control socket is gone.
It preserves strict known-host checking and does not retry a remote command
after an uncertain result. Without the option, run `connect` and authenticate in
the operator's terminal. Use the complete script and configuration paths if
running from a different directory; `vm.py` and `config.json` are not root files.

The build downloads official [cliclick 5.1](https://github.com/BlueM/cliclick/releases/tag/5.1),
checks archive SHA-256
`710910fd2dade6a3b5889594bfc019e7d4c2beee09fd777503e71ea82acc91bc`,
and builds the bundled arm64 Objective-C helpers with ad hoc signatures.
cliclick supplies clicks; keyboard helpers emit actual virtual keycodes with
explicit modifier flags. cliclick's keyboard path produced incorrect modifiers
in the original experiment and is not used for typing.

Deployment refuses an active run. It preserves an existing `UTMUIProbe.app` so
routine reruns do not replace its authorized signature. The historical app
supports `~/utm-ui-isolation`; a newly built app also accepts a configured root.
Reusing an existing app at a custom root requires checking its compatibility;
the controller refuses that ambiguous case. To intentionally replace an app,
stop all tests and retain a backup before installing the new build; expect macOS
to require authorization again.

## Authorize and start the GUI executor

`vm run baseline` launches the guest app using LaunchServices in the logged-in
user session. On a fresh deployment it may exit before producing a run ID while
requesting permissions. In the **guest** System Settings → Privacy & Security,
authorize UTMUIProbe for Accessibility and Screen & System Audio Recording, and
allow Quit & Reopen when requested. Retry only after the grants are effective.
Obtain authorization for these guest privileges within the current task; this
guide does not transfer an earlier operator's approval.

The native app supplies the permission identity and runs shell/native helpers
as children. Do not replace it with a plain SSH-launched key generator when
that process lacks GUI permissions. TextEdit is opened with LaunchServices and
its owned window is placed using Accessibility. The probe needs no TextEdit
AppleEvents grant. Keep SIP enabled; do not edit TCC databases or reset privacy
settings to bypass a failure.

## Run and inspect tests

```bash
vm run baseline
vm status RUN_ID
vm collect RUN_ID
vm verify /private/tmp/meshchan-vm/evidence/RUN_ID
```

Replace `RUN_ID` with the unique ID printed by `run`; it is never an instruction
to reuse the latest run blindly. A baseline creates an empty dedicated plain-text
file and performs three rounds. Each round clicks the editing area, verifies the
focused TextEdit field, sends a numbered ASCII line through key events and presses
Return. Command-S saves; verification independently reads the resulting file.
No content is injected via file writes, paste or Accessibility value assignment.
The longer stages perform 30 rounds with approximately two-second delays plus
UI and screenshot overhead. They have a 150-second deadline; Pinyin has 300 seconds.

For host-input isolation, have the operator leave UTM open in the background,
focus a **host** scratch document and continue typing, selecting text, moving
the pointer and switching apps. Run `vm run background`. Repeat with UTM
minimized using `vm run minimized`; do not close or pause the VM. During each
measurement the agent uses SSH and local evidence inspection only. Record the
operator's observations of pointer movement, focus, missing input, leaked test
characters and stuck modifiers. Guest success without this feedback proves
background execution only. Typing inside the VM invalidates a concurrent-host
measurement.

Each run retains timestamps, environment, log, screenshots, expected and actual
text, diff and exit code. New ASCII runs also retain per-round focus JSON.
`verify` generates `verified-results.json`; a guest PASS does not automatically
claim host isolation or visual Pinyin correctness.

### Real Pinyin composition

In the guest, enable system Pinyin – Simplified alongside U.S. or ABC if needed.
Inspect `vm check` output and the guest's Keyboard Shortcuts settings. The
validated VM uses Control+Space for previous source and Control+Option+Space for
next source. The host's customized Command+Space mapping is unrelated. The
bundled probe checks the guest's primary binding and stops on a different one;
inspect and adapt the guest helper before testing another mapping, rather than
changing system preferences automatically.

Start in U.S. or ABC and run:

```bash
vm run pinyin
vm status RUN_ID
vm review RUN_ID zhongwen
```

View the collected original `zhongwen-preedit.png` and its JSON. Confirm the
owned document, actual focused AXTextArea and matching foreground/focus-owner
PID, underlined `zhong wen`, the intended candidate `中文`, and no launcher
overlay. Only after that review:

```bash
vm approve RUN_ID zhongwen --visual-confirmed
vm status RUN_ID
vm review RUN_ID nihao
```

Inspect the second screenshot and focus record for underlined `ni hao` and
candidate `你好`, then explicitly approve it:

```bash
vm approve RUN_ID nihao --visual-confirmed
vm status RUN_ID
vm collect RUN_ID
vm verify /private/tmp/meshchan-vm/evidence/RUN_ID
```

Each gate waits at most 120 seconds. Never automate approvals based only on
source IDs or expected strings. Missing/failed review stops before Save, without
forcing a candidate or repeatedly switching sources during composition. On an
interrupted run inspect pending preedit and restore the intended mode through
normal guest UI once it is safe; cleanup does not force input-mode changes.

Natural Space commits should produce exactly these saved UTF-8 lines, including
a final newline:

```text
ABC
中文
ABC
你好
ABC
```

The probe switches to Latin between Chinese inputs and restores the original
Latin source, confirmed by actual `ABC` input. Its uppercase markers avoid
TextEdit's observed automatic sentence capitalization. Input-source IDs alone
are insufficient evidence; screenshots establish composition and candidate UI.

## Stop, recover and revoke

Use `vm stop` in another host terminal to stop the owned runner, then collect its
run. The stop script checks UUID and the exact runner path before signaling it;
cleanup releases modifiers and mouse buttons, terminates the active child and removes its lock.
Do not delete a lock or signal a PID without verifying ownership. Deadlines and
interrupts produce nonzero exit codes. Leave failed documents and evidence for
inspection. Finish with `vm disconnect`. If temporary `caffeinate` is used,
track and terminate that test-owned process; these scripts do not install a
persistent keep-awake service.

| Failure | Check and next action |
| --- | --- |
| SSH connection/key | Check VM network/IP and guest fingerprint. Reconnect; do not weaken host-key checking. |
| Identity/session | Compare UUID/model and console account in the guest; unlock/login before retrying. |
| No run ID/permissions | Read guest `executor.log`; verify guest Accessibility and Screen Recording for the app and reopen it. |
| Focus/extra text | Inspect exact document/PID, screenshots and manual guest input. Exclude failed preflights from passes. |
| Pinyin/shortcut | Inspect guest sources/hotkeys, real marked text and candidate UI. Do not assume host bindings. |
| Background failure | Check guest remains running, unlocked and displayed; use its GUI-session executor. |
| Host interference | Stop, retain evidence and record the host observation separately from guest success. |

To retire the setup, stop and disconnect, revoke the app's guest Accessibility
and Screen Recording grants, disable guest Remote Login, and delete the owned
guest test directory after preserving needed evidence. Remove host private
configuration, known-hosts entry and runtime directory when no longer needed.
Remove any user-requested local credential file separately when retiring its VM.
The VM and documents remain until explicitly removed. No host privacy grant is
required by this workflow.

## Historical validation: November 14, 2026

| Item | Observed value |
| --- | --- |
| Host | Apple M2 Max, Mac14,6, 64 GB, arm64, macOS 27.2.1 (26B131) |
| UTM / VM | 5.0.8 / `macOS`, Shared Network, 8124 MiB RAM |
| Guest | macOS 27.2.1 (26B131), VirtualMac2,1, SIP enabled |
| Guest network | `192.168.64.34`, NIC `36:5c:78:52:a8:10` |
| Hardware UUID | `15B75AC9-E5C6-56CD-9FAA-86EC9AAF57A2` |
| ED25519 fingerprint | `SHA256:ZlvBd48EvojAjFPeZJWor0WHpjIiJEnUCvRGJc97QxQ` |
| Display | Configured 1920×1200 with dynamic resolution; observed screenshots 5120×2880 |
| Toolchain | Python 3.15.2 at `/opt/homebrew/bin/python3`; Apple clang 21.0.0 (clang-2100.4.1.1) |

| Valid run | Result |
| --- | --- |
| `20261114T091615Z-baseline-2895` | 3/3 lines, exit 0 |
| `20261114T092230Z-minimized-3321` | 30/30 lines, exit 0; user confirmed host operation had no interference |
| `20261114T092700Z-background-3665` | 30/30 lines, exit 0; user confirmed host operation had no interference |
| `20261114T095019Z-pinyin-4526` | Two natural Chinese commits, four switches, 14 focus checks, exact file match, exit 0 |

The earlier background attempt was invalid because the user typed in the guest.
An initial Pinyin attempt composed Chinese successfully but failed its whole-file
comparison because TextEdit capitalized `abc` to `Abc`; the valid rerun used
`ABC`. Original cliclick keyboard events and AppleEvents authorization attempts
were abandoned in favor of the native-key/Accessibility workflow above.

Large evidence remains local, outside Git, under
`/Users/xiaoyu/.codex/visualizations/2026/11/14/01a1d8b9-b1c9-7832-8dad-efcb6a0af09a/`:
`utm-ui-isolation/` and `utm-pinyin/`, with matching ZIP archives. These are local
artifact locations, not portable prerequisites. Historical reports retain their
original toolchain facts. New packaged-script reruns are recorded separately in
[the packaging validation record](validation/macos-vm-gui-tooling.md).

The evidence covers a logged-in unlocked guest, TextEdit and this configuration.
It does not cover lock/sleep/reboot unattended operation, arbitrary remote-control
implementations, or Meshchan product text fields. Product IME regression needs
real marked text, its own target/focus checks, normal Save/close behavior and an
independent reopen against an owned fixture.

## Meshchan product UI runner

The product-specific tools are in `apps/meshchan_app/tool/macos_vm/`. They reuse
the existing signed `UTMUIProbe.app`: its child dispatches the explicitly deployed
`product.sh`. No replacement executor signature or new privacy grant is needed
on the already-authorized VM. The host controller sends commands over the
identity-checked SSH channel; key, pointer, focus and screenshot operations run
inside the guest. It never drives the host keyboard for product testing.

Use a new ignored evidence directory for each run. The app, working directory,
fixture, output and screenshots reside below the guest's dedicated
`~/utm-ui-isolation/products/RUN_ID-MODE/`, outside Documents and the default
Meshchan directory. Full Debug and Release app bundles must pass
`codesign --verify --deep --strict --all-architectures` before and after copying.
The native helper refuses the host and verifies the exact executable, PID,
Bundle ID, `--data-dir`, foreground application and actual input owner.

From the repository root, using an already built and verified app:

```bash
product() {
  /opt/homebrew/bin/python3 apps/meshchan_app/tool/macos_vm/host.py \
    --config /private/tmp/meshchan-vm/config.json \
    --evidence build/phase-1d6/vm-RUN_ID "$@"
}
scenario() {
  /opt/homebrew/bin/python3 apps/meshchan_app/tool/macos_vm/scenario.py \
    --config /private/tmp/meshchan-vm/config.json \
    --evidence build/phase-1d6/vm-RUN_ID "$@"
}
product prepare
product launch Debug /absolute/path/to/verified/Debug/Meshchan.app
scenario Debug initial
scenario Debug preedit device
```

`preedit` stops after collecting its original screenshot and focused-field JSON.
View both: confirm the precise fixture, matching foreground/focus PID, marked
`zhong wen`, candidate `中文` and no overlay. Then test the composing controls,
view their retained images, and commit through one natural Space:

```bash
scenario Debug defer device navigation
scenario Debug defer device menu
scenario Debug defer device quit
scenario Debug commit device --visual-confirmed
scenario Debug preedit draft
# Review this new screenshot and JSON independently before its commit.
scenario Debug defer draft save
scenario Debug defer draft navigation
scenario Debug defer draft quit
scenario Debug commit draft --visual-confirmed
scenario Debug quit 'Continue editing'
scenario Debug quit Save
product settled Debug
```

Run Release with a separate product fixture in the same executor run or use a
new run. `product finish` requires normal resource-release/worker-exit receipts
and zero pending requests/receive ports. It stops the executor, not the app by
force. Read a collected fixture independently only after normal close. Product
results use their own assertions and shutdown receipts; the TextEdit verifier
rejects a `product` run instead of reporting a misleading pass.

Fresh `DebugDiscard` / `ReleaseDiscard` fixtures support the `discard` scenario
without changing the saved Pinyin fixtures. Explicit native checks use fresh
`DebugDevice` / `ReleaseDevice` fixtures and require the separate opt-in command
`scenario MODE check --port /exact/authorized/guest/path`. The helper keeps that
path verbatim, records primary failure and cleanup separately, and never picks
another port or adjusts budgets after failure. Meshchan's product helper currently
uses the default dedicated guest root, `~/utm-ui-isolation`; custom-root TextEdit
deployments are a separate supported path described above.

If interrupted by a reboot, retain the old evidence and classify it as
interrupted. Verify no matching runner or Meshchan process remains before
archiving `active.lock`; do not simply delete it or reuse a saved PID. Confirm
the new desktop is unlocked and begin a new run. A product runner deadline or
external termination is not a successful application shutdown.

## USB passthrough and serial forwarding

On macOS 27+, UTM's Apple backend supports USB passthrough. First assign the
specific device to UTM using the **host** menu-bar **Virtual Machine Accessories**
item, then confirm the connection in the VM toolbar's **USB Devices** list.
Unassigned devices are absent from that list; an empty/querying UTM menu does not
prove that the backend lacks USB support. See the current
[official USB guide](https://docs.getutm.app/guest-support/sharing/usb/).
Changing this mapping is a setup action, outside any host-isolation measurement.

Forwarding a host serial device through a VM Serial configuration can instead
produce `/dev/cu.com.redhat.spice.*` paths in the guest. Those names alone do not
prove which physical device is attached. Verify the exact host-to-guest mapping
and explicit user selection before checking a forwarded port. Never open the
guest tools console port or substitute the first/only enumerated path. Use the
product's explicit Refresh/Select/Check flow; VM metadata alone is not a finite
USB initialization result. Record direct USB, forwarded serial, and no-device
results separately, including the actual guest source path.

Confirm three layers independently: the selected USB device is visible in guest
System Information; its compatible driver has created a serial node listed by
Meshchan's explicit Refresh; and a user-selected finite Check has obtained
Companion information and actually closed. A USB row is not a serial node or a
successful session. In the November 14 product follow-up, Espressif `303a:1001`
was visible with `AppleUSBCDCCompositeDevice`, but its interfaces had no serial
driver children and Refresh still listed only SPICE ports. Do not substitute a
SPICE console, invent a USB path or patch the app enumerator for that condition.
Retain the binding/metadata evidence and resolve the guest device/driver setup.
A user-controlled disconnect/reconnect of the same assigned accessory can request
fresh enumeration, with possible board reset; this is separate from an app check.

### Upstream research, November 14, 2026

The [same-device UTM report #7947](https://github.com/utmapp/UTM/issues/7947)
uses Espressif `303A:1001`, macOS host/guest 27.0.1, UTM 5.0.6 and the Apple
backend. It remains open with no posted workaround. Its device was absent from
guest System Information, unlike this run's visible USB device with no serial
driver binding. It is a related report, not proof of an identical root cause.

The apparently relevant [replug fix #8133](https://github.com/utmapp/UTM/pull/8133)
was merged on November 12, after the current
[5.0.8 release](https://github.com/utmapp/UTM/releases/tag/v5.0.8) on October 17.
Its actual diff changes only
`Platform/macOS/Display/VMDisplayQemuDisplayController.swift`. It is a QEMU/SPICE
fix, not evidence of an Apple-backend CDC fix; do not recommend a development
build solely on that title.

[Espressif #18516](https://github.com/espressif/esp-idf/issues/18516) concerns
location-based macOS port names caused by colons in this device's USB serial
descriptor. It explains path changes, not the absence of every USB serial node.
[Espressif #19192](https://github.com/espressif/esp-idf/issues/19192) reports a C6
USB-Serial/JTAG endpoint stuck after a bus reset; its reporter recovered by a
power cycle. That is a different failure stage/chip report and not a verified
fix for this guest. The operator's physical unplug/replug here did not create
a serial node.

No matching, validated Apple-backend CDC repair was found. A full UTM process
restart followed by explicit accessory assignment is a possible diagnostic
comparison, not a published successful workaround. Preserve the current tree,
metadata and narrowly scoped CDC-driver diagnostics for an upstream report.
Do not change firmware, kernel extensions, signing or security settings based
on unrelated old driver workarounds. Do not publish a report without the user's
instruction to send it.
