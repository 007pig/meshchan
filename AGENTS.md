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
