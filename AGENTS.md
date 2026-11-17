# Agent Guidance

## Local Python toolchain

- Run Python scripts with `python3`, never `python`.
- Python code that launches Python tooling must use `sys.executable`, preserving
  the selected interpreter instead of resolving `python3` from PATH again.
- On this Mac, use the latest installed stable Python **3.15 or newer**. Verify
  its version before running project scripts or tests. Do not use the older
  `/usr/bin/python3` selected by an Apple-compiler-first PATH.
- The verified interpreter is `/opt/homebrew/bin/python3` (Python 3.15.2).
  Call that path explicitly, or use the Python-only PATH entry documented in
  [the developer guide](docs/development.md#local-python-toolchain).
- Do not install or upgrade Python or change global PATH/settings automatically.
  Record the actual interpreter path and version in new validation records;
  preserve historical records with their original toolchain facts.

## Host macOS GUI testing

- Prefer the existing **macOS VM** for UI testing whenever real USB/serial
  hardware is not required. This includes navigation, offline editing and
  Save/Quit, Profiles/Settings, History/export, and Chinese input-method tests.
- Use this Mac's **Computer Use** only for UI steps that require real
  USB/serial hardware. Do not substitute AppleScript, System Events, CGEvent,
  or accessibility-driver scripts for those host interactions.
- Do not fall back to host GUI automation for hardware-free tests when the VM
  is unavailable or blocked. Record the specific VM blocker and continue other
  independent work.
- Builds, owned-fixture preparation, CLI tests, and independent process/file
  verification may use their normal command-line tools. Guest UI and input-method
  tests follow the applicable VM skill and guide.

## macOS VM GUI automation

- Before running real GUI, host-input isolation, or Chinese input-method tests
  inside a macOS VM, read
  [the macos-vm-gui-testing skill](.agents/skills/macos-vm-gui-testing/SKILL.md).
- Use its guest-side event execution and SSH orchestration for hardware-free UI
  tests, leaving the host mouse and keyboard available. Follow its identity,
  focus, Pinyin evidence and owned-fixture requirements.
- Ordinary unit tests do not require loading this skill.
- Run real USB/serial hardware validation on the host Mac, including native port
  enumeration, device checks, Cancel/cleanup and quit with active hardware.
  Use the VM for hardware-free UI, Pinyin, navigation, offline quit and fake tests.
- Do not continue VM USB passthrough or SPICE-port hardware testing under this
  routing policy. Preserve the historical VM results as historical evidence.
