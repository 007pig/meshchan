---
name: macos-vm-gui-testing
description: Validate hardware-free macOS desktop behavior in the configured UTM guest over SSH. Use for Meshchan GUI fixtures and workflows, real Pinyin composition, or host-input isolation.
---

# macOS VM GUI Testing

Follow the [repository GUI routing](../../../AGENTS.md#macos-gui-testing). For
Meshchan behavior, use the [product runner](../../../apps/meshchan_app/tool/macos_vm/host.py)
with the intended signed app and an owned fixture. For executor readiness,
host-input isolation or a standalone IME check, use the TextEdit probes.
Choose the scenario that exercises the requested behavior.

## Keep input inside the guest

- Use [the VM controller](scripts/vm.py) over SSH/SCP for guest key and pointer
  events, focus queries and screenshots. Keep the guest awake, logged in,
  unlocked and attached to a virtual display. The controller verifies the
  VirtualMac model, expected hardware UUID and console user on each remote
  operation. Keep strict SSH host-key checking and independently confirm a new
  fingerprint in the guest.
- Reuse the private configuration and signed guest executor. For setup, use
  [the build and deployment guide](../../../docs/macos-vm-gui-testing.md#build-connect-and-deploy)
  and the [configuration example](config.example.json). Verify the identity
  values and keep private configuration and credentials outside Git and
  evidence. Store credentials only at the user's explicit request.
- For a new executor, follow the [permission setup](../../../docs/macos-vm-gui-testing.md#authorize-and-start-the-gui-executor)
  with authorization for the current task. Keep SIP enabled and use the
  executor's guest privacy grants. Leave TCC and AppleEvents permissions alone.

## Verify the requested outcome

- **TextEdit probes.** Follow the [probe guide](../../../docs/macos-vm-gui-testing.md#run-and-inspect-tests).
  Use the unique ID from `run` for status, review, approval and collection.
  Run `verify` on the collected evidence to check saved bytes, focus and
  source restoration as applicable. For `background` or `minimized`, have the
  user arrange UTM and use a host app during measurement. Record their
  observations of host input and focus separately from the guest result.
- **Meshchan workflows.** Follow the [product runner guide](../../../docs/macos-vm-gui-testing.md#meshchan-product-ui-runner).
  Deploy the intended build with an owned fixture outside protected Documents
  paths and the default data directory. Before input, confirm the executable,
  PID, fixture arguments, window and actual focused control. For text and
  shortcuts, verify the focused native field's text and selection using the
  product helper's modifier sequence. For Save or Quit, verify persistence by
  independently reopening the closed fixture. Require the normal
  resource-release and worker-exit receipts to pass a Quit check. Use the
  product assertions for Meshchan results.
- **Real Pinyin in either app.** Inspect the guest's enabled sources and
  shortcuts first. Follow the [Pinyin guide](../../../docs/macos-vm-gui-testing.md#real-pinyin-composition)
  for the TextEdit sequence or the product runner guide for Meshchan. Use
  actual letter keycodes and a natural Space commit. Keep paste, Unicode
  injection, AX value assignment and file edits out of IME checks.
  Before each approval or commit, review the original preedit screenshot and
  focus JSON for the owned target, matching foreground and focus PIDs, marked
  text, the intended candidate and absence of overlays. Approve each gate only
  after its own review. If focus or composition is uncertain, stop before Save
  and retain the evidence. Avoid repeated input-source switching during
  preedit. Verify the restored input source through actual input when possible.

## Close the run

Report the scenario, build or probe, result, evidence location and any
blocked checks. Preserve evidence from incomplete runs. Use the
[recovery procedure](../../../docs/macos-vm-gui-testing.md#stop-recover-and-revoke)
to stop the owned runner if needed and disconnect at the end. After a reboot,
recheck guest identity, desktop state and process ownership before starting a
new run. Archive a stale lock only after confirming its runner and product
process have exited. Treat a reboot or forced stop without a normal shutdown
receipt as an interrupted run.
