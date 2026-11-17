import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import trace_usb_initialization as trace


PLAN = {"formatVersion": 1, "appName": "Meshchan", "appTargetVersion": 3,
        "deviceQuery": [60, 2, 0, 22, 3],
        "appStart": [60, 16, 0, 1, 0, 0, 0, 0, 0, 0, 0, *b"Meshchan"]}


def incoming(body):
    return bytes([62, len(body) & 255, len(body) >> 8]) + body


class StructureTest(unittest.TestCase):
    def test_exact_wire_contract_and_wrong_version(self):
        self.assertEqual([len(x) for x in trace.validate_wire_plan(PLAN)], [5, 19])
        for key, value in (("appTargetVersion", 4), ("appName", "Other"),
                           ("deviceQuery", [60, 2, 0, 22, 4])):
            with self.subTest(key=key), self.assertRaises(ValueError):
                trace.validate_wire_plan({**PLAN, key: value})

    def test_every_two_part_split_and_coalesced_frames(self):
        body = bytes([13, 14]) + bytes(80)
        packet = incoming(body) + incoming(bytes([5]) + bytes(63))
        for split in range(len(packet) + 1):
            parser = trace.FrameStructure()
            frames = parser.feed(packet[:split]) + parser.feed(packet[split:])
            self.assertEqual([len(x) for x in frames], [82, 64])
            self.assertFalse(parser.projection()["partial"])

    def test_header_only_and_missing_suffix(self):
        for packet, expected, received in ((bytes([62, 64, 0]), 67, 3),
                                            (bytes([62, 82, 0]) + bytes(18), 85, 21)):
            parser = trace.FrameStructure()
            self.assertEqual(parser.feed(packet), [])
            self.assertEqual(parser.projection()["expectedFrameBytes"], expected)
            self.assertEqual(parser.projection()["receivedFrameBytes"], received)

    def test_invalid_lengths_noise_limit_and_payload_redaction(self):
        for packet in (bytes([62, 0, 0]), bytes([62, 177, 0]), bytes(1025)):
            with self.subTest(packet=packet[:3]), self.assertRaises(ValueError):
                trace.FrameStructure().feed(packet)
        parser = trace.FrameStructure()
        parser.feed(incoming(b"sensitive-test-content"))
        self.assertNotIn("sensitive-test-content", json.dumps(parser.projection()))

    def test_trace_overflow_is_explicit(self):
        recorder = trace.Trace()
        for _ in range(4097):
            recorder.add("count")
        self.assertEqual(len(recorder.events), 4096)
        self.assertEqual(recorder.omitted, 1)

    def test_rejected_entry_does_not_open_device(self):
        with patch.object(trace.os, "open") as opening:
            with self.assertRaises(SystemExit):
                trace.main(["--port", "/dev/cu.test", "--wire-plan", "/missing"])
            opening.assert_not_called()
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "plan.json"
            file.write_text(json.dumps({**PLAN, "appTargetVersion": 4}))
            with patch.object(trace.sys, "platform", "darwin"), patch.object(trace.os, "open") as opening:
                with self.assertRaises(ValueError):
                    trace.main(["--port", "/dev/cu.test", "--wire-plan", str(file), "--execute"])
                opening.assert_not_called()


class AttemptTest(unittest.TestCase):
    def run_control(self, header_only=False, late_body=False, write_error=False,
                    probe_error=False):
        clock = [0.0]
        chunks = []
        writes = []

        def write(fd, packet):
            if write_error:
                raise OSError("Do not expose this raw native text")
            writes.append(packet)
            if packet[3] == 22:
                chunks.append(incoming(bytes([13, 14]) + bytes(80)))
            else:
                chunks.append(bytes([62, 64, 0]) if header_only else incoming(bytes([5]) + bytes(63)))
            return len(packet)

        def select_call(readers, writers, errors, timeout):
            if readers and chunks:
                clock[0] += 16 if late_body and len(writes) == 2 else 0.01
                return readers, [], []
            clock[0] += timeout
            return [], [], []

        def read(fd, size):
            if chunks:
                return chunks.pop(0)
            raise BlockingIOError

        def probe(fd):
            if probe_error:
                raise OSError("Do not expose probe error text")
            return {"inputWaitingBytes": 0, "selectReadable": False}

        with patch.object(trace.os, "open", return_value=23), patch.object(trace.os, "close") as close, \
                patch.object(trace.fcntl, "ioctl"), patch.object(trace, "configure", return_value={}), \
                patch.object(trace, "queue_projection", side_effect=probe), \
                patch.object(trace.os, "write", side_effect=write), patch.object(trace.os, "read", side_effect=read), \
                patch.object(trace.select, "select", side_effect=select_call), \
                patch.object(trace.time, "monotonic", side_effect=lambda: clock[0]), \
                patch.object(trace.time, "monotonic_ns", side_effect=lambda: int(clock[0] * 1_000_000_000)):
            result = trace.run_attempt("/dev/cu.test", trace.validate_wire_plan(PLAN))
            close.assert_called_once_with(23)
        return result, writes

    def test_success_has_only_two_commands_and_confirmed_close(self):
        result, writes = self.run_control()
        self.assertTrue(result["structuralRepliesMatched"])
        self.assertFalse(result["meshCoreSessionReady"])
        self.assertTrue(result["cleanupConfirmed"])
        self.assertEqual([x[3] for x in writes], [22, 1])
        self.assertEqual(result["applicationSendAttempts"], 0)
        self.assertEqual(result["inboxReads"], 0)

    def test_header_only_timeout_probes_same_fd_and_does_not_repair(self):
        result, writes = self.run_control(header_only=True)
        self.assertFalse(result["structuralRepliesMatched"])
        self.assertEqual(result["failure"], {"kind": "requestTimeout", "commandOpcode": 1,
                                             "expectedResponseOpcode": 5})
        self.assertEqual(len(writes), 2)
        self.assertEqual(result["finalInputProjection"]["receivedFrameBytes"], 3)
        self.assertEqual(result["finalInputProjection"]["expectedFrameBytes"], 67)
        self.assertEqual(result["deadlineOsProjection"]["finalReadBytes"], 0)
        self.assertTrue(result["cleanupConfirmed"])

    def test_late_complete_body_is_not_success(self):
        result, _ = self.run_control(late_body=True)
        self.assertFalse(result["structuralRepliesMatched"])
        self.assertEqual(result["failure"]["kind"], "requestTimeout")
        self.assertTrue(any(x.get("afterDeadline") for x in result["events"]))

    def test_probe_failure_does_not_replace_primary_timeout(self):
        result, _ = self.run_control(header_only=True, probe_error=True)
        self.assertEqual(result["failure"]["kind"], "requestTimeout")
        self.assertEqual(result["errorType"], "OSError")
        self.assertTrue(result["cleanupConfirmed"])
        self.assertNotIn("probe error text", json.dumps(result))

    def test_native_error_still_closes_without_raw_error_text(self):
        result, _ = self.run_control(write_error=True)
        self.assertTrue(result["cleanupConfirmed"])
        self.assertEqual(result["errorType"], "OSError")
        self.assertNotIn("Do not expose", json.dumps(result))


if __name__ == "__main__":
    unittest.main()
