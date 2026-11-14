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

## macOS VM GUI automation

- Before running real GUI, host-input isolation, or Chinese input-method tests
  inside a macOS VM, read
  [the macos-vm-gui-testing skill](.agents/skills/macos-vm-gui-testing/SKILL.md).
- Use its guest-side event execution and SSH orchestration when the test must
  leave the host mouse and keyboard available. Follow its identity, focus,
  Pinyin evidence and owned-fixture requirements.
- Ordinary unit tests do not require loading this skill.
