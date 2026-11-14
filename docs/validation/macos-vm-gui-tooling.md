# macOS VM GUI tooling packaging validation

Date: November 14, 2026 (Europe/Dublin, UTC+0).

This record validates the repository skill and packaged scripts. The prior
30-round host-input isolation trials remain separate historical evidence in
[the VM guide](../macos-vm-gui-testing.md#historical-validation-november-14-2026).
No new concurrent-host isolation trial was requested or counted during packaging.

## Environment and static checks

- Host: Apple M2 Max, arm64, macOS 27.2.1; guest macOS 27.2.1,
  VirtualMac2,1, SIP enabled; UTM 5.0.8, Shared Network.
- Interpreter: `/opt/homebrew/bin/python3`, Python 3.15.2. The isolated validator
  environment was created from this interpreter at
  `/private/tmp/meshchan-vm/validation-venv`; PyYAML 6.0.3 was installed there only.
- Native helpers: Xcode Apple clang 21.0.0, arm64, ad hoc signatures. Final build
  succeeded; the obsolete activation option was replaced with its effective
  modern value. Official cliclick 5.1 archive matched the pinned SHA-256.
- `quick_validate.py`: passed. All three guest shell scripts passed `bash -n`.
- Seven offline behavioral checks passed using `scripts/check_tooling.py` and
  the built helpers: missing configuration, invalid stage, native refusal on the
  host, shell refusal of incorrect identity, identity guard covering compound
  commands, unapproved preedit timeout, and independent saved-text verification
  including corruption/interruption rejection. The review wait was accelerated
  with a test-local sleep function; no wall-clock 150/300-second timeout trial
  was performed.
- Git whitespace validation passed. Build output, private configuration,
  authentication, screenshots and evidence remain outside the repository.

Reproduce the offline checks from the repository root:

```bash
/opt/homebrew/bin/python3 .agents/skills/macos-vm-gui-testing/scripts/check_tooling.py \
  /private/tmp/meshchan-vm/build
bash -n .agents/skills/macos-vm-gui-testing/scripts/guest.sh \
  .agents/skills/macos-vm-gui-testing/scripts/pinyin.sh \
  .agents/skills/macos-vm-gui-testing/scripts/stop-guest.sh
```

## Guest runs

The deployed signed executor was preserved. No guest or host privacy grants were
added, and no input-source settings were changed. All event generation occurred
inside the guest through the existing GUI-session app; host orchestration used
SSH/SCP only.

| Run | Observed result |
| --- | --- |
| `20261114T101248Z-baseline-4908` | Failed window preflight because the guest had auto-locked; excluded from passes. |
| `20261114T101315Z-pinyin-4978` | Same locked-session failure, before text input; excluded from passes. |
| `20261114T101457Z-baseline-5113` | After user unlock: 3/3 rounds, exact saved text, focus JSON and screenshots, exit 0. |
| `20261114T101548Z-pinyin-5224` | Both real compositions visually reviewed, natural Space commits, exact saved text and original Latin source restored, exit 0. |
| `20261114T101710Z-baseline-5468` | Deliberately interrupted via independent `stop`; exit 143, lock cleanup confirmed. Excluded from passes. |
| `20261114T101825Z-baseline-5605` | Final native-helper build, including explicit mouse-button release: 3/3 rounds, exact text, exit 0. |

The lock failure led to an explicit locked-desktop preflight. An initial version
used an array key path for the session plist; inspection showed a dictionary and
the check was corrected to `IOConsoleLocked`. The final controller refuses a
locked session before launching the executor.

For the Pinyin run, both screenshots showed underlined preedit and the intended
candidate in the owned `probe-pinyin-5224.txt` document. The 14 JSON records
identified TextEdit PID 2679 and verified the actual focused AXTextArea. The
controller approved each gate only after viewing its screenshot and JSON.
The saved file SHA-256 was
`c45ed9ed25dca15ac81f2092745f3b89301565dd55bd424b006cdcf64d1c177b`:

```text
ABC
中文
ABC
你好
ABC
```

The successful ASCII saved file SHA-256 was
`dd9bae839abee5c947c1e057b953127a552511d6d554610153d1c4942bad13d5`.
The final addition checking the fallback shortcut was compared with the observed
live guest configuration (hotkey 61 enabled, keycode 49, modifier 786432).

Evidence was collected under `/private/tmp/meshchan-vm/evidence/` and retained in
`/Users/xiaoyu/.codex/visualizations/2026/11/14/01a1d8b9-b1c9-7832-8dad-efcb6a0af09a/utm-vm-tooling/`.
These local paths are not installation dependencies for another agent.
The evidence verifier confirms saved bytes and machine-readable preconditions;
visual candidate inspection and user reports remain separate observations.

## Coverage limits

The probes validate TextEdit and the packaged control/collection path. They do
not validate Meshchan fields or imply a new host-input isolation result. Fresh
permission onboarding and a custom-root installation were documented and built
but not repeated on this already-authorized VM. Sleep, lock and reboot recovery
remain outside unattended-operation coverage.

At completion, `stop` returned `IDLE` and the temporary SSH control connection
was closed. The VM, test documents, existing grants and evidence were retained.
