#!/usr/bin/env python3
"""Run only fixed, hardware-free source and native process checks."""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "apps/meshctl"
CORE = ROOT / "packages/meshcore_link"
WATCHDOG = 60
LINUX_REFUSAL = (
    "Error: Serial port enumeration is unavailable on Linux with "
    "libserialport_plus 1.0.5: the native backend can open unselected ports."
)
USAGE = "Usage: dart run example/serial_transport_check.dart <port>"
DATAGRAM_EXITS = {
    "raw_send": 0,
    "bounded_listen": 0,
    "ping_round_trip": 0,
    "responder_reply": 0,
    "partial_pong_timeout": 69,
}


def datagram_report(stdout):
    """Validate evidence from the fixed probe, including expected CLI failure."""
    if len(stdout) > 8192:
        raise ValueError("Probe report exceeds 8192 characters")
    report = json.loads(stdout)
    if not isinstance(report, dict):
        raise ValueError("Probe report must be an object")
    if report.get("probe") != "meshchan.datagram-acceptance.1b8":
        raise ValueError("Unexpected probe identifier")
    if type(report.get("schemaVersion")) is not int or report["schemaVersion"] != 1:
        raise ValueError("Expected probe schemaVersion 1")
    scenarios = report.get("scenarios")
    if not isinstance(scenarios, list) or len(scenarios) != len(DATAGRAM_EXITS):
        raise ValueError("Expected all five datagram scenarios")
    seen = set()
    for scenario in scenarios:
        if not isinstance(scenario, dict):
            raise ValueError("Scenario must be an object")
        name = scenario.get("id")
        if not isinstance(name, str) or name not in DATAGRAM_EXITS or name in seen:
            raise ValueError(f"Unexpected or duplicate scenario ID: {name!r}")
        seen.add(name)
        if scenario.get("passed") is not True:
            raise ValueError(f"Scenario did not pass: {name}")
        code = scenario.get("cliExitCode")
        if type(code) is not int or code != DATAGRAM_EXITS[name]:
            raise ValueError(f"{name}: unexpected actual CLI exit code: {code!r}")
    if seen != set(DATAGRAM_EXITS):
        raise ValueError("Missing datagram scenario IDs")
    for field, expected in (("completed", len(seen)), ("passed", len(seen)), ("failed", 0)):
        if type(report.get(field)) is not int or report[field] != expected:
            raise ValueError(f"Inconsistent probe {field} count")


def executable(value):
    path = Path(value).expanduser().resolve()
    if not path.is_file() or path.stat().st_size == 0 or not os.access(path, os.X_OK):
        raise argparse.ArgumentTypeError(f"Expected a nonempty executable: {path}")
    return path


def bundle(value):
    path = Path(value).expanduser().resolve()
    if not path.is_dir():
        raise argparse.ArgumentTypeError(f"Bundle directory does not exist: {path}")
    return path


def bundle_executable(path, name):
    library = {
        "darwin": "liblibserialport_plus.dylib",
        "linux": "liblibserialport_plus.so",
    }[sys.platform]
    asset = path / "lib" / library
    if not asset.is_file() or asset.stat().st_size == 0:
        raise ValueError(f"Missing or empty native library: {asset}")
    return executable(str(path / "bin" / name))


def run(command, cwd, broken_pipe=False):
    """Drain both streams and bound every child, including its build-hook group."""
    write_fd = None
    if broken_pipe:
        read_fd, write_fd = os.pipe()
        os.close(read_fd)  # No reader exists before the child can write.
    try:
        child = subprocess.Popen(
            command,
            cwd=cwd,
            stdin=subprocess.DEVNULL,
            stdout=write_fd if broken_pipe else subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
    finally:
        if write_fd is not None:
            os.close(write_fd)
    try:
        stdout, stderr = child.communicate(timeout=WATCHDOG)
    except BaseException:
        # Only this child's new process group; never touch other Dart processes.
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        child.communicate()
        raise
    return child.returncode, stdout or "", stderr


class Checks:
    def __init__(self):
        self.count = 0

    def check(self, name, command, cwd, code=0, out=None, err=(),
              broken_pipe=False, options=None, validate=None):
        try:
            actual, stdout, stderr = run(command, cwd, broken_pipe)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise ValueError(
                f"{name}: command={shlex.join(map(str, command))}; "
                f"expected completion within {WATCHDOG}s; {error}"
            ) from error
        failures = []
        if actual != code:
            failures.append(f"expected exit {code}, got {actual}")
        if out is None and stdout:
            failures.append("expected empty stdout")
        elif out is not None and out not in stdout:
            failures.append(f"expected stdout containing {out!r}")
        for diagnostic in err:
            if diagnostic not in stderr:
                failures.append(f"expected stderr containing {diagnostic!r}")
        if code == 0 and "Error:" in stderr:
            failures.append("unexpected error diagnostic on successful path")
        if "Unhandled exception" in stderr or re.search(r"#\d+\s", stderr):
            failures.append("unexpected application exception or stack trace")
        if options is not None:
            # Inspect option declarations, not mentions in explanatory prose.
            actual_options = set(re.findall(
                r"^\s*(?:-\w,\s+)?--([\w-]+)", stdout, re.MULTILINE,
            ))
            if actual_options != options:
                failures.append(
                    f"expected options {sorted(options)}, got {sorted(actual_options)}"
                )
        if validate is not None:
            try:
                validate(stdout)
            except ValueError as error:
                failures.append(f"invalid JSON evidence: {error}")
        if failures:
            raise ValueError(
                f"{name}: command={shlex.join(map(str, command))}; cwd={cwd}\n"
                + "; ".join(failures)
                + f"\nactual stdout={stdout!r}\nactual stderr={stderr!r}"
            )
        self.count += 1
        print(f"PASS {self.count}: {name}", flush=True)
        return stdout

    def help(self, name, prefix, cwd, command=None):
        arguments = [command, "--help"] if command else ["--help"]
        expected = {"help", "json"}
        if command is None:
            expected = {"help", "version"}
        elif command != "ports":
            expected.add("port")
            if command in ("info", "watch"):
                expected.update(("verbose", "timeout", "init-timeout", "startup-delay"))
                if command == "watch":
                    expected.add("duration")
        usage = f"Usage: meshctl {command} " if command else "Usage: meshctl [options]"
        self.check(name, prefix + arguments, cwd, out=usage, options=expected)

    def datagram_help(self, name, prefix, cwd, operation=None):
        arguments = ["datagram"] + ([operation] if operation else []) + ["--help"]
        expected = {"help"}
        if operation:
            expected.update(("json", "verbose", "port", "timeout", "init-timeout",
                             "startup-delay", "task-timeout"))
            if operation != "listen":
                expected.update(("send-channel", "route-descriptor", "path-hex"))
            if operation != "send":
                expected.update(("receive-channel", "max-entries"))
            if operation in ("ping", "respond"):
                expected.update(("local-id", "peer-id"))
            else:
                expected.add("data-type")
            if operation in ("send", "ping"):
                expected.update(("text", "payload-hex" if operation == "send" else "content-hex"))
            if operation == "ping":
                expected.add("response-timeout")
            if operation in ("listen", "respond"):
                expected.add("duration")
            if operation == "respond":
                expected.add("max-responses")
        self.check(name, prefix + arguments, cwd, out="Usage: meshctl datagram ", options=expected)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart", required=True, type=executable)
    parser.add_argument("--cli-bundle", required=True, type=bundle)
    parser.add_argument("--observation-bundle", required=True, type=bundle)
    parser.add_argument("--datagram-acceptance-bundle", required=True, type=bundle)
    args = parser.parse_args()
    if sys.platform not in ("darwin", "linux"):
        parser.error("This smoke script supports macOS and Linux hosts only.")
    try:
        native = bundle_executable(args.cli_bundle, "meshctl")
        observation = bundle_executable(args.observation_bundle, "serial_transport_check")
        acceptance = bundle_executable(args.datagram_acceptance_bundle, "datagram_acceptance")
        # Read the existing application constant; do not duplicate a version here.
        definition = (CLI / "lib/src/version.dart").read_text(encoding="utf-8")
        version = re.search(r"const String meshctlVersion = '([^']+)';", definition)
        if version is None:
            raise ValueError("Cannot read the application version from lib/src/version.dart")
        expected_version = f"meshctl {version[1]}\n"
        checks = Checks()
        rejections = [
            (["info"], "--port"),
            (["watch"], "--port"),
            (["info", "--port="], "--port"),
            (["watch", "--port", " \t "], "--port"),
            (["info", "--timeout=0"], "--timeout"),
            (["info", "--init-timeout=86401"], "--init-timeout"),
            (["watch", "--duration=NaN"], "--duration"),
            (["watch", "--startup-delay=-1"], "--startup-delay"),
            (["port-check"], "--port"),
            (["port-check", "--port", " \t "], "--port"),
            (["unknown-command"], "Unknown command"),
            (["--unknown-option"], "unknown-option"),
            (["datagram", "send"], "--port"),
            (["datagram", "unknown"], "Invalid datagram command syntax"),
            (["datagram", "listen", "--help", "extra"], "Invalid datagram command syntax"),
            (["datagram", "ping", "--port=unused", "--task-timeout=0"], "--task-timeout"),
        ]
        for label, prefix in (
            ("source", [str(args.dart), "run", "bin/meshctl.dart"]),
            ("native", [str(native)]),
        ):
            checks.check(f"{label}: no arguments", prefix, CLI, out="Usage: meshctl")
            checks.help(f"{label}: help", prefix, CLI)
            checks.check(f"{label}: version", prefix + ["--version"], CLI, out=expected_version)
            for command in ("ports", "port-check", "info", "watch"):
                checks.help(f"{label}: {command} help", prefix, CLI, command)
            checks.check(f"{label}: datagram group", prefix + ["datagram"], CLI,
                         out="Usage: meshctl datagram <operation>")
            for operation in (None, "send", "listen", "ping", "respond"):
                checks.datagram_help(f"{label}: datagram {operation or 'group'} help", prefix, CLI, operation)
            for arguments, diagnostic in rejections:
                checks.check(
                    f"{label}: reject {arguments!r}", prefix + arguments, CLI,
                    code=64, err=("Error:", "meshctl --help", diagnostic),
                )
            if sys.platform == "linux":
                for arguments in (["ports"], ["ports", "--json"]):
                    checks.check(
                        f"{label}: Linux refusal {arguments!r}", prefix + arguments,
                        CLI, code=69, err=(LINUX_REFUSAL,),
                    )
        if sys.platform != "linux":
            print("NOT APPLICABLE: Linux enumeration refusal (host is macOS).")
        for label, prefix in (
            ("source", [str(args.dart), "run", "example/serial_transport_check.dart"]),
            ("native", [str(observation)]),
        ):
            for arguments in ([], [" \t "]):
                checks.check(
                    f"{label}: observation usage {arguments!r}", prefix + arguments,
                    CORE, code=64, err=(USAGE,),
                )
        checks.check(
            "native: closed stdout pipe", [str(native), "--help"], CLI,
            code=74, err=("Error: CLI output failed.",), broken_pipe=True,
        )
        # Use a system directory outside the checkout, even if TMPDIR points into it.
        with tempfile.TemporaryDirectory(prefix="meshchan smoke ", dir="/tmp") as temporary:
            destination = Path(temporary).resolve()
            if destination.is_relative_to(ROOT):
                raise ValueError("Relocation destination must be outside the repository")
            moved = destination / "relocated bundle"
            shutil.copytree(args.cli_bundle, moved)
            relocated = [str(bundle_executable(moved, "meshctl"))]
            checks.check("relocated: version", relocated + ["--version"], destination, out=expected_version)
            checks.help("relocated: info help", relocated, destination, "info")
            checks.datagram_help("relocated: ping help", relocated, destination, "ping")
            checks.check(
                "relocated: missing port", relocated + ["info"], destination,
                code=64, err=("Error:", "--port", "meshctl --help"),
            )
            checks.check(
                "source: datagram synthetic acceptance",
                [str(args.dart), "run", "tool/datagram_acceptance.dart"], CLI,
                out="", validate=datagram_report,
            )
            checks.check(
                "native: datagram synthetic acceptance outside checkout",
                [str(acceptance)], destination, out="", validate=datagram_report,
            )
        print(f"PASS: {checks.count} process checks on {sys.platform}; "
              "CLI, observation, and development acceptance bundles contain native assets; "
              "five datagram scenarios passed in source and AOT.")
        return 0
    except (OSError, ValueError, argparse.ArgumentTypeError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
