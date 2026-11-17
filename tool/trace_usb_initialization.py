#!/usr/bin/env python3
"""One opt-in macOS POSIX control; no RF commands, inbox reads or repair I/O."""

import argparse
import array
import datetime
import fcntl
import json
import os
from pathlib import Path
import select
import signal
import sys
import termios
import time


def validate_wire_plan(value):
    """Check the public-codec plan against the independently fixed wire contract."""
    if value != {
        "formatVersion": 1,
        "appName": "Meshchan",
        "appTargetVersion": 3,
        "deviceQuery": [60, 2, 0, 22, 3],
        "appStart": [60, 16, 0, 1, 0, 0, 0, 0, 0, 0, 0, *b"Meshchan"],
    }:
        raise ValueError("Unexpected initialization wire plan")
    return [bytes(value["deviceQuery"]), bytes(value["appStart"])]


class FrameStructure:
    """Bounded independent counter; payload exists only in process memory."""

    def __init__(self):
        self.header = bytearray()
        self.body = bytearray()
        self.length = None
        self.noise = 0
        self.total_noise = 0

    def feed(self, chunk):
        frames = []
        for byte in chunk:
            if not self.header:
                if byte == 62:
                    self.header.append(byte)
                else:
                    self.noise += 1
                    self.total_noise += 1
                    if self.noise > 1024:
                        raise ValueError("Noise limit exceeded")
            elif len(self.header) < 3:
                self.header.append(byte)
                if len(self.header) == 3:
                    self.length = self.header[1] | self.header[2] << 8
                    if not 1 <= self.length <= 176:
                        raise ValueError("Invalid frame length")
            else:
                self.body.append(byte)
                if len(self.body) == self.length:
                    frames.append(bytes(self.body))
                    self.header.clear()
                    self.body.clear()
                    self.length = None
                    self.noise = 0
        return frames

    def projection(self):
        return {
            "partial": bool(self.header),
            "receivedFrameBytes": len(self.header) + len(self.body),
            "expectedFrameBytes": None if self.length is None else 3 + self.length,
            "receivedContentBytes": len(self.body),
            "discardedBytes": self.total_noise,
        }


class Trace:
    def __init__(self):
        self.origin = time.monotonic_ns()
        self.events = []
        self.omitted = 0

    def add(self, event, **fields):
        if len(self.events) == 4096:
            self.omitted += 1
            return
        self.events.append({"event": event, "elapsedUs":
                            (time.monotonic_ns() - self.origin) // 1000, **fields})


def queue_projection(fd):
    waiting = array.array("i", [0])
    fcntl.ioctl(fd, termios.FIONREAD, waiting, True)
    return {"inputWaitingBytes": waiting[0],
            "selectReadable": bool(select.select([fd], [], [], 0)[0])}


def configure(fd):
    attrs = termios.tcgetattr(fd)
    attrs[0] = attrs[1] = attrs[3] = 0
    attrs[2] &= ~(termios.CSIZE | termios.PARENB | termios.CSTOPB |
                  termios.CCTS_OFLOW | termios.CRTS_IFLOW | termios.CDSR_OFLOW |
                  termios.CDTR_IFLOW | termios.CCAR_OFLOW)
    attrs[2] |= termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[4] = attrs[5] = termios.B115200
    attrs[6][termios.VMIN] = attrs[6][termios.VTIME] = 0
    # TCSANOW: never flush input/output or explicitly manipulate RTS/DTR.
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    actual = termios.tcgetattr(fd)
    if actual[:6] != attrs[:6]:
        raise ValueError("TTY configuration did not match")
    return {"iflag": actual[0], "oflag": actual[1], "cflag": actual[2],
            "lflag": actual[3], "inputSpeed": actual[4], "outputSpeed": actual[5]}


def run_attempt(port, wire):
    trace = Trace()
    parser = FrameStructure()
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    fd = None
    acquired = False
    closed = False
    ready = False
    failure = None
    error_type = None
    close_error = None
    configuration = None
    command = 22
    expected = 13
    writes = []
    deadline_probe = None
    overall = time.monotonic() + 30
    try:
        trace.add("posix_open_begin")
        fd = os.open(port, os.O_RDWR | os.O_NONBLOCK | os.O_NOCTTY | os.O_CLOEXEC)
        acquired = True
        trace.add("posix_open_completed")
        fcntl.ioctl(fd, termios.TIOCEXCL)
        configuration = configure(fd)
        trace.add("posix_configured", **configuration)
        for packet, command, expected, expected_length in zip(
                wire, (22, 1), (13, 5), (82, 64), strict=True):
            deadline = min(time.monotonic() + 15, overall)
            write_deadline = min(time.monotonic() + 2, deadline)
            offset = 0
            while offset < len(packet):
                if time.monotonic() >= write_deadline:
                    raise TimeoutError("Write deadline")
                trace.add("posix_write_begin", commandOpcode=command,
                          offset=offset, requestedBytes=len(packet) - offset)
                try:
                    accepted = os.write(fd, packet[offset:])
                except BlockingIOError:
                    accepted = 0
                writes.append({"opcode": command, "requestedBytes": len(packet) - offset,
                               "acceptedBytes": accepted})
                trace.add("posix_write_returned", acceptedBytes=accepted)
                if time.monotonic() >= write_deadline:
                    raise TimeoutError("Write deadline")
                offset += accepted
                if offset < len(packet):
                    select.select([], [fd], [], max(0, write_deadline - time.monotonic()))
            matched = False
            while not matched:
                remaining = min(deadline, overall) - time.monotonic()
                if remaining <= 0:
                    failure = {"kind": "initializationTimeout" if overall <= deadline
                               else "requestTimeout", "commandOpcode": command,
                               "expectedResponseOpcode": expected}
                    trace.add("deadline", **failure)
                    deadline_probe = queue_projection(fd)
                    try:
                        late = os.read(fd, 4096)
                        deadline_probe["finalReadWouldBlock"] = False
                    except BlockingIOError:
                        late = b""
                        deadline_probe["finalReadWouldBlock"] = True
                    deadline_probe["finalReadBytes"] = len(late)
                    deadline_probe["after"] = queue_projection(fd)
                    trace.add("deadline_os_projection", **deadline_probe)
                    # Do not accept bytes observed after the unchanged deadline.
                    break
                if not select.select([fd], [], [], remaining)[0]:
                    continue
                chunk = os.read(fd, 4096)
                late = time.monotonic() >= min(deadline, overall)
                trace.add("posix_rx_chunk", bytes=len(chunk), afterDeadline=late)
                if not chunk:
                    raise EOFError("TTY input ended")
                if late:
                    # Receipt after the original deadline cannot become success.
                    continue
                for frame in parser.feed(chunk):
                    trace.add("complete_frame", opcode=frame[0], contentBytes=len(frame))
                    if frame[0] == expected:
                        if len(frame) != expected_length or (expected == 13 and frame[1] != 14):
                            raise ValueError("Selected-board response structure differs")
                        matched = True
                    else:
                        trace.add("unassociated_frame", opcode=frame[0], contentBytes=len(frame))
            if failure:
                break
        else:
            ready = True
    except BaseException as error:
        error_type = type(error).__name__
        if failure is None:
            failure = {"kind": "controlError", "commandOpcode": command,
                       "expectedResponseOpcode": expected}
        trace.add("control_error", errorType=error_type)
    finally:
        trace.add("input_projection", **parser.projection())
        if fd is not None:
            trace.add("posix_close_begin")
            try:
                os.close(fd)
                closed = True
                trace.add("posix_close_confirmed")
            except OSError as error:
                close_error = type(error).__name__
    return {"tool": "meshchan-posix-initialization-control", "formatVersion": 1,
            "pid": os.getpid(), "startedAt": started,
            "endedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "port": port, "requestSeconds": 15, "initializationSeconds": 30,
            "startupMilliseconds": 0, "nativeWriteSeconds": 2,
            "structuralRepliesMatched": ready, "meshCoreSessionReady": False,
            "failure": failure, "errorType": error_type, "closeErrorType": close_error,
            "acquisitions": int(acquired), "cleanupConfirmed": closed,
            "configuration": configuration, "writes": writes,
            "deadlineOsProjection": deadline_probe,
            "finalInputProjection": parser.projection(),
            "applicationSendAttempts": 0, "inboxReads": 0,
            "omittedEvents": trace.omitted, "events": trace.events}


def main(arguments=None):
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--port", required=True)
    cli.add_argument("--wire-plan", required=True, type=Path)
    cli.add_argument("--execute", action="store_true", required=True)
    args = cli.parse_args(arguments)
    if sys.platform != "darwin" or not args.port.startswith("/dev/cu.") or args.port.strip() != args.port:
        cli.error("An explicit macOS callout port is required")
    wire = validate_wire_plan(json.loads(args.wire_plan.read_text()))
    # A signal requests normal Python unwinding/close, never another attempt.
    def interrupt(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupt)
    result = run_attempt(args.port, wire)
    print(json.dumps(result))
    return 0 if (result["structuralRepliesMatched"] and result["cleanupConfirmed"]
                 and not result["omittedEvents"]) else 69


if __name__ == "__main__":
    sys.exit(main())
