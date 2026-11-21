# Agent Guidance

## Validation

- For regressions spanning the app, CLI or native transport, trace the affected
  path and test plausible alternative causes before reporting a root cause.
- After fixing a review finding, run the unit tests that cover the changed
  behavior and regression risk. Passing those tests completes local review-fix
  verification, including follow-ups on an open PR.
- Before opening a PR, complete the applicable
  [validation workflow](docs/testing.md#review-fixes-and-pre-pr-validation)
  for the final changes. Report the checks run, their outcomes and any
  deferred or blocked checks.
- For visual changes, use the supplied reference or existing Meshchan UI as
  the baseline. Inspect and refine the result at its intended display size.
  Exercise the affected interactions when validating interactive changes.

## Local Python toolchain

- Run project scripts and tests with `python3` from the latest installed stable
  Python **3.15 or newer**. On this Mac, verify `/opt/homebrew/bin/python3` first.
  See the [developer guide](docs/development.md#local-python-toolchain) for
  the project-local PATH option. Leave global settings and installations alone.
- Launch Python subprocesses with `sys.executable`. Record the path and
  version used in new validation records and preserve historical toolchain facts.

## macOS GUI testing

- Use the existing VM for hardware-free GUI tests, including native Pinyin,
  navigation and offline Save/Quit. Read the [VM skill](.agents/skills/macos-vm-gui-testing/SKILL.md)
  before running guest UI or host-input isolation checks. If the VM is blocked,
  report the cause and continue independent work without a host GUI fallback.
- Run real USB/serial acceptance on the host Mac, including native port
  enumeration, device checks, Cancel/cleanup and quit with active hardware.
  Use Computer Use for these host UI steps. Keep VM passthrough and SPICE-port
  results as historical evidence.
- Use normal command-line tools for builds, owned fixtures, CLI tests and
  independent process or file verification.

## Shared workspace

- Use subagents as needed for substantial tasks with independent investigations
  or edits in separate files. Give each edit a single owner and keep one
  operator per VM desktop or hardware session.
- Coordinate resource-heavy builds and tests on the shared Mac. At handoff,
  stop temporary background jobs started for the task and remove temporary
  files that are no longer needed. Retain validation evidence.
