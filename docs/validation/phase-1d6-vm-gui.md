# Phase 1D.6 — macOS VM product GUI follow-up

Date: November 14, 2026, Europe/Dublin (UTC+0). Guest desktop time is Pacific.

## Scope and inputs

The user requested a rerun inside the existing UTM macOS guest, following the
new skill in commit `6d9facf917b351e84782e277f88131a10f1143b4`. The branch is
`codex/phase-1d6-device-check`; product implementation is commit `b6cd046`, based
on the real PR #31 merge `46c8937`. The working tree was clean initially.
This follow-up changes UI tooling, the skill and documentation. It does not
change app/core/link code, Runner, dependencies, schema, versions or protocol.
It does not advance to 1D.7.

The product apps are the complete, signed final Debug/Release bundles from the
[unlocked host acceptance](phase-1d6-device-check.md#unlocked-gui-and-explicitly-selected-usb-follow-up),
under `/private/tmp/meshchan-1d6-gui-uue0dyu8/apps/FinalVerifiedDebug/` and
`FinalVerifiedRelease/`. Product source is unchanged by the later skill commit
or this dirty tree. Native executable SHA-256 values are:

| App | SHA-256 |
| --- | --- |
| Debug | `3408d22e07d5de7b0370969c9b2f99e3a996412534a22e1824ca43186bf7a074` |
| Release | `2e4645d2416df23ed3623427d40917abb0c319e91316635f4c1a5570cb812127` |

`final-inputs.json` in the ignored evidence directory inventories tracked and
untracked final sources and hashes; the old HEAD alone is not the tooling input.
`session.json` identifies source bundles, exact guest fixture paths, PIDs and
shutdown receipts. No private configuration or credential is in that inventory.

## Environment and ownership

- Host: Apple silicon arm64, UTM 5.0.8. Python is
  `/opt/homebrew/bin/python3`, 3.15.2. Bundled Dart is 3.13.7, arm64; the existing
  apps were built with Flutter 3.47.9. No SDK/channel/dependency change was made.
- Guest: macOS 27.2.1 (26B131), `VirtualMac2,1`, expected hardware UUID
  `15B75AC9-E5C6-56CD-9FAA-86EC9AAF57A2`, console user `meshchantest`, SIP enabled.
  The desktop was verified unlocked after the user's reboot.
- Helper compiler: Apple Swift 6.4.2, `arm64-apple-macosx27.2.0`, macOS SDK 27.2.
  The helper refuses execution on the host. Actual app architecture is recorded
  as arm64 in focused-control JSON for both configurations.
- Guest shortcut inspection confirmed Control+Space and Control+Option+Space.
  The host's customized bindings were not applied to the guest. All four actual
  composition gates were viewed independently before natural Space commits.
- Full app, cwd, fixture, stdout/stderr and GUI activity were under
  `~/utm-ui-isolation/products/RUN_ID-MODE/`, outside guest Documents/default data.
  Host orchestration used SSH; native input was a child of the existing signed
  and authorized `UTMUIProbe.app`, whose signature was preserved. No automated
  TCC, SIP, keyboard or signing-setting changes were made.
- The user explicitly requested retaining disposable VM credentials locally.
  Private `config.json`, `known_hosts` and mode-0600 `credentials.json` are under
  `~/.config/meshchan-vm/`, outside Git. Askpass uses `sys.executable`, not password
  arguments or logs. Strict host-key and UUID/console guards remain enabled.

## Observed results

Primary product run: **`20261114T111429Z-product-4655`**. Evidence is
`build/phase-1d6/vm-final-20261114/` and the matching owned guest product roots.

| Check | Debug | Release | Evidence |
| --- | --- | --- | --- |
| Initial Device state, no selection, defaults 5/15/0 | PASS | PASS | `device-initial.json`, `default-*-focus.json`, original image |
| Explicit native metadata Refresh; no automatic first choice | PASS | PASS | `device-explicit-refresh.json`, `device-refresh.png` |
| Invalid request 0 and startup 15000/initialization 15; navigation retains state | PASS | PASS | `invalid-*.json`, `navigation-return.json` |
| Real Device Pinyin, marked `zhong wen`, candidate `中文` | PASS | PASS | `device-preedit.png` and focus JSON, independently viewed |
| Pointer port menu, navigation and native Cmd+Q defer during Device composition | PASS | PASS | `device-deferred-*.png/json`, unchanged focused text |
| Natural Device commit is exactly `5中文`; invalid text retained; restore Latin | PASS | PASS | `device-committed-focus.json`, `device-restored-focus.json` |
| Real Draft body Pinyin; pointer Save/navigation/Cmd+Q defer | PASS | PASS | `draft-preedit*`, `draft-deferred-*`, independently viewed |
| Natural Draft commit `中文`, explicit Cmd+S, Latin input and Undo | PASS | PASS | `draft-committed-focus.json`, `dirty-*`, `undo-after-continue-*` |
| Dirty Cmd+Q Continue, then Save and actual normal shutdown | PASS | PASS | quit images, final `app.stdout`, `session.json` |
| Dirty Cmd+Q Discard in a fresh fixture; actual shutdown | PASS | PASS | `DebugDiscard/`, `ReleaseDiscard/` |
| Independent external reopen of closed fixtures | PASS | PASS | `/private/tmp/meshchan-vm/product-results/vm-final-20261114/`; stored JSON |
| Deep/strict/all-architectures signature verification before/after transfer | PASS | PASS | deployment commands and exact app hashes in `session.json` |
| Authorized native check on `/dev/cu.com.redhat.spice.01` | opening failure | opening failure | `DebugDevice/hardware-result.json`, `ReleaseDevice/hardware-result.json` |
| Actual session and host observer cleanup after that failure | PASS | PASS | both cleanup facts succeeded; `Not connected`; normal quit receipts |

Primary app PIDs were Debug 4734 and Release 11606. Discard fixtures used 19620
and 20157; selected-port fixtures used 21679 and 23378. All six have normal
shutdown receipts: `resourcesReleased=true`, `workerExited=true`,
`pendingRequests=0`, `receivePorts=0`, owner released and no maintenance failure.
No worker was killed to generate these receipts.

The two saved Drafts have titles `vmdebug` / `vmrelease`, body exactly `中文abc`,
revision 2, unchanged default settings, no profiles and zero diagnostic history.
Discard fixtures and native-check fixtures are also independently checked after
normal close. These checks operate on external owned copies, never the default
database. A first Debug inspector invocation used an owned checkout clone; it is
excluded from the external-path process proof. The accepted verification uses
`/private/tmp/meshchan-vm/product-results/` with an external cwd.

The separate TextEdit baseline `20261114T104000Z-baseline-5925` passed 3/3 rounds,
actual saved text and focus checks. Its hash is
`dd9bae839abee5c947c1e057b953127a552511d6d554610153d1c4942bad13d5`.
No new concurrent-host background/minimized measurement was counted. Historical
user-confirmed isolation trials remain in the [VM guide](../macos-vm-gui-testing.md).

## Failures, corrections and excluded attempts

- Expired SSH authentication initially prevented reruns. Interactive connection
  was offered; after the user's explicit request, private local credentials and
  scoped askpass support were added. Remote commands are not replayed after an
  uncertain result. Offline checks reject mismatched identities, public file
  permissions and non-password prompts.
- A Swift geometry dictionary cast expected `Double` but contained `CGFloat`.
  The helper crashed before input; it was corrected. Flutter's unfocused AX
  proxies also returned empty values, so defaults are read from the actual
  focused native input instead.
- Generic Command flags alone did not apply Flutter Select All. The corrected
  helper emits actual left modifier transitions and their device-specific flags;
  selected range and actual replacement text proved the result. Failed input
  attempts are not passes.
- The first Undo assertion assumed `abc` formed one group. Actual evidence
  showed `中文ab` after one Undo. The test now observes each real group, stopping
  at saved `中文`, with a bound of three suffix groups. It does not erase/rewrite
  the editor buffer to manufacture an Undo result.
- The operator reboot interrupted `20261114T104427Z-product-6102`. Its runner
  and Meshchan processes were confirmed absent before the stale lock was
  archived inside that old run. No normal release is inferred from reboot.
  The corrected-driver preparation run `20261114T110904Z-product-1061` ended
  with a real clean Cmd+Q receipt before the final run began.
- Host UTM preference inspection was denied and a read-only `utmctl` discovery
  did not complete. Neither was used to infer a physical mapping; no privacy or
  AppleEvents permission was added as a workaround.

## USB evidence boundary and current follow-up

The user explicitly authorized guest `/dev/cu.com.redhat.spice.01`. Each product
configuration performed one explicit Refresh/Select/Check with defaults 5 s /
15 s / 0 ms. Both reported **`Initialization: transport · opening`**, obtained no
information and then confirmed actual session and observer cleanup. The `.0`
console path was never selected. No budget change, automatic retry, alternate
probe, inbox/RF command or recording was used.

The user's later System Information screenshot showed Espressif
`USB JTAG/serial debug unit`, VID/PID `303a:1001`, in the guest. SSH inspection of
the same VM confirmed an `IOUSBHostDevice`, an `AppleUSBCDCCompositeDevice` and
three interfaces with no serial-driver children. The product's new explicit
Refresh still listed only the two SPICE paths: **no USB serial node was yet
available**. This is a driver-binding prerequisite, not a successful Companion
initialization. The controlled binding tree, without serial numbers, is in
`build/phase-1d6/vm-usb-20261114/usb-driver-binding.json`; metadata is in
`usb-refresh.json`. Follow-up executor: `20261114T114054Z-product-25255`.

The user then physically unplugged and replugged the device. A fresh metadata-only
run, `20261114T115438Z-product-29595`, using the durable private configuration,
still listed only the two SPICE ports. The USB device remained attached to this
same verified guest. Its interfaces had class/subclass/protocol 2/2/0, 10/2/0 and
255/255/1, with no serial-driver children. Evidence is
`build/phase-1d6/vm-replug-20261114/ports-after-replug.json` and
`usb-binding-after-replug.json`. Both metadata-only follow-up apps exited through
normal Cmd+Q with full release receipts; no USB path was invented or opened.

Actual finite USB information, USB-scoped Cancel and occupied-check dirty quit
in this VM remain **BLOCKED / NOT_RUN** until the guest exposes an openable port
and the user explicitly selects its exact path. The prior host USB acceptance
is preserved separately and is not reused as a VM pass. Seeing a USB device,
seeing a serial path and obtaining Companion information are separate facts.
The [guide](../macos-vm-gui-testing.md#usb-passthrough-and-serial-forwarding) explains
the macOS 27 menu-bar assignment and the difference from Serial configuration.
It also records the requested upstream research: UTM #7947 is a same-device,
same-backend unresolved report; #8133 is a QEMU-only replug fix and is excluded
as an Apple-backend remedy. No verified repair for this guest was found.

## Reproduction and checks

Use the [product runner commands](../macos-vm-gui-testing.md#meshchan-product-ui-runner).
Explicit hardware testing additionally requires `scenario.py MODE check --port
/exact/authorized/guest/path`; there is no default device or scan. Do not use
the TextEdit verifier for product runs. Evidence collection and finish require
the exact run ID and real shutdown receipts.

The skill's eleven offline behavioral checks passed with Python 3.15.2; shell and
Python syntax checks, skill `quick_validate.py`, native helper host refusal and
Git whitespace checks passed. The app's prior 159 tests and isolated 11 native
XCTest results remain in the main 1D.6 record; the unchanged app/core/link suites
and builds were not repeated to inflate this tooling-only run. No GUI fixture
injection, CLI device adapter or new production testing backdoor was added.
