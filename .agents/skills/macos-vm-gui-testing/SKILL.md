---
name: macos-vm-gui-testing
description: Run real macOS GUI automation inside a UTM VM over SSH, including background input isolation and Pinyin composition tests. Use for guest desktop tests and preparing product GUI fixtures; ordinary unit tests do not need this skill.
---

# macOS VM GUI Testing

Read [the project guide](../../../docs/macos-vm-gui-testing.md) for first-time
installation, permissions, command examples, historical evidence and recovery.
Use `scripts/vm.py --help` for orchestration. Use the project's verified Python
3.15+ interpreter; on the validated host this is `/opt/homebrew/bin/python3`.
Copy `config.example.json` outside the repository and verify its identity values.
If the user explicitly asks to retain the disposable VM's credentials, use a
private file outside Git and reference it with `credentials_file` in the private
configuration. On this host the user-requested file is
`~/.config/meshchan-vm/credentials.json`. Read the guide's authentication section;
never copy that file into a skill, example, log or test artifact.

## Execution boundary

Run key events, pointer actions, focus queries and screenshots **inside the
identified guest**. The host controller uses SSH/SCP only. Before every remote
operation it checks VirtualMac hardware, the expected hardware UUID and the
console user. Preserve strict SSH host-key verification. Independently verify a
new host key in the VM before accepting it; do not trust ssh-keyscan alone.

Reuse the existing signed guest executor during ordinary reruns. Build/deploy
only when needed. Initial permission grants belong to the guest and require the
current task's authorization; previous chat approvals are not transferable.
Do not edit TCC, disable SIP or add AppleEvents permissions for these probes.
Keep the guest logged in, unlocked and awake, with a virtual display attached.

## Choose and run a probe

- `baseline`: three click/key rounds in a fresh TextEdit document.
- `background` / `minimized`: 30 rounds each. Have the user arrange the UTM
  window and operate a **host** application. Do not send host GUI events during
  measurement. The script cannot prove UTM window state or host input isolation;
  record the user's observations separately. Do not count typing in the VM as
  concurrent host operation.
- `pinyin`: Latin → Pinyin → Latin twice, using actual letter keycodes and Space.
  Inspect the guest's enabled sources and shortcut first. The bundled probe
  supports verified Control+Space/Control+Option+Space bindings and fails closed
  on a different primary binding. Adapt guest keycodes only after inspecting the
  actual configuration; do not apply this host's Command+Space mapping to a VM.

`run` prints a unique ID. Use that ID for status, review, approval and collection;
never approve a gate using an unverified `latest-run`. At each Pinyin gate run
`review`, view the original `*-preedit.png` and inspect its JSON. Verify the exact
owned document, foreground/focus PID, underlined composition, intended candidate
and absence of launcher overlays. Only then issue `approve --visual-confirmed`.
A selected input-source ID alone does not prove Chinese mode. Never automatically
approve both gates. Missing review times out without Save or forced commit.

Collect the run and invoke `verify`. The verifier checks actual saved bytes,
focus evidence, input-source restoration and expected artifacts; it does not
replace visual review or the user's host-interference report. Stop with `stop`
if needed, collect failed evidence, and disconnect when finished. Do not remove
a stale lock until process identity and termination have been established.

## Extend to Meshchan

The bundled baseline/Pinyin probes target TextEdit only. Meshchan's product
runner is [tool/macos_vm](../../../apps/meshchan_app/tool/macos_vm/host.py);
read the guide's Meshchan section before using it. Its `product` stage reuses the
authorized executor and requires a separately deployed product-owned script.
TextEdit's `verify` deliberately refuses product results.

For product testing, deploy the intended
app and use an owned fixture directory outside protected Documents paths and
outside the product's default data directory. Verify its exact PID, arguments,
window and actual focused control before sending input. Capture real marked text
and candidates before Save/navigation/Quit, then commit naturally and verify
persistence using the project's normal close barrier and independent reopen.
Never replace real IME composition with pasted Chinese, Unicode injection,
AX value assignment or direct document edits. Restore the intended input source
and verify it with actual input when possible. If focus/composition is uncertain,
stop before Save and retain evidence; do not switch repeatedly during preedit.

Flutter's unfocused accessibility proxies can have empty values. Verify the
actual focused native input, exact expected text and selected range; a key event
being posted does not prove that Select All or another shortcut was applied.
Use the product helper's tested modifier sequence rather than assuming the
TextEdit keyboard path establishes Flutter's hardware-key state.

After a guest reboot, reconnect and recheck identity, unlock state and processes.
Treat the old run as interrupted unless it has a normal shutdown receipt. Archive
a stale lock only after verifying that its runner and product owner are gone;
do not reuse old PIDs or count reboot termination as a resource-release pass.
USB passthrough and serial forwarding are different. A newly visible SPICE port
does not identify the selected physical device; verify the mapping and obtain
explicit selection before opening it. See the guide's USB section for macOS 27.
Check upstream fixes against the actual backend: a macOS-host USB fix can affect
only QEMU and provide no evidence for an Apple Virtualization guest.
