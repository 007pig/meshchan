"""Real process-tree interruption and checkout-lock regressions; no native builds."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import regression_1d10 as regression


class GateInterruptionTest(unittest.TestCase):
    def wait_for(self, condition, description, timeout=15):
        deadline = time.monotonic() + timeout
        while not condition():
            if time.monotonic() >= deadline:
                self.fail('Timed out observing ' + description)
            time.sleep(0.02)

    def exercise_interruption(self, *, detached=False, signum=signal.SIGINT,
                              stubborn=False, during_manifest=False,
                              interrupt_at=None, failed_exit=False,
                              successful_exit=False, interrupt_while_waiting=False):
        late_interrupt = bool(during_manifest or interrupt_at)
        natural_exit = successful_exit or late_interrupt
        with tempfile.TemporaryDirectory(prefix='meshchan-gate-interrupt-') as directory:
            folder = Path(directory)
            checkout = folder / 'checkout'
            checkout.mkdir()
            wrapper = folder / 'runner.py'
            wrapper.write_text(
                'import os, signal, sys, time\nfrom pathlib import Path\n'
                'from types import SimpleNamespace\n'
                f'sys.path.insert(0, {str(Path(__file__).resolve().parent)!r})\n'
                'import regression_1d10 as runner\n'
                f'runner.ROOT = Path({str(checkout)!r})\n'
                'manifest_calls = 0\n'
                'def manifest():\n'
                '    global manifest_calls\n'
                '    manifest_calls += 1\n'
                f'    if {during_manifest!r} and manifest_calls == 2 and '
                'Path(sys.argv[sys.argv.index("--evidence") + 1]).name == "first":\n'
                '        os.kill(os.getpid(), signal.SIGINT)\n'
                '    output = runner.ROOT / "worker-output.txt"\n'
                '    return {"worker-output.txt": runner.digest(output)} if output.exists() else {}\n'
                'runner.source_manifest = manifest\n'
                'original_observe = runner.OwnedGate.observe\n'
                'def observe(owner):\n'
                '    result = original_observe(owner)\n'
                f'    pid_file = Path({str(folder / "leaf-pid")!r})\n'
                f'    if Path({str(folder / "ready")!r}).exists() '
                'and pid_file.exists() and int(pid_file.read_text()) in owner.members:\n'
                f'        Path({str(folder / "observed")!r}).touch()\n'
                '    return result\n'
                'runner.OwnedGate.observe = observe\n'
                f'interrupt_at = {interrupt_at!r}\n'
                'published_interrupt = False\n'
                'def interrupt_once():\n'
                '    global published_interrupt\n'
                '    if not published_interrupt:\n'
                '        published_interrupt = True\n'
                f'        os.kill(os.getpid(), {int(signum)})\n'
                'original_write = runner.write_json\n'
                'def write_json(path, value):\n'
                '    original_write(path, value)\n'
                '    if interrupt_at == "result" and path.name == "result.json" '
                'and path.parent.parent.name == "first" and value["status"] == "PASS":\n'
                '        interrupt_once()\n'
                'runner.write_json = write_json\n'
                'original_open = Path.open\n'
                'class ReceiptStream:\n'
                '    def __init__(self, stream): self.stream = stream\n'
                '    def __getattr__(self, name): return getattr(self.stream, name)\n'
                '    def __enter__(self): self.stream.__enter__(); return self\n'
                '    def __exit__(self, *args): return self.stream.__exit__(*args)\n'
                '    def write(self, value):\n'
                '        result = self.stream.write(value)\n'
                '        interrupt_once()\n'
                '        return result\n'
                'def open_path(path, *args, **kwargs):\n'
                '    stream = original_open(path, *args, **kwargs)\n'
                '    if interrupt_at == "ledger" and path.name == "ledger.jsonl" '
                'and path.parent.name == "first":\n'
                '        return ReceiptStream(stream)\n'
                '    return stream\n'
                'Path.open = open_path\n'
                'original_mask = signal.pthread_sigmask\n'
                'def mask(how, signals):\n'
                '    result = original_mask(how, signals)\n'
                '    if interrupt_at == "seal" and how == signal.SIG_BLOCK '
                'and Path(sys.argv[sys.argv.index("--evidence") + 1]).name == "first":\n'
                '        interrupt_once()\n'
                '    return result\n'
                'signal.pthread_sigmask = mask\n'
                # Advance the escalation clock only after the contender has
                # observed the lock, independent of CI scheduling/load.
                f'runner.INTERRUPT_GRACE_SECONDS = {0.3 if stubborn else 10}\n'
                f'if {stubborn!r}:\n'
                '    runner.time = SimpleNamespace(sleep=time.sleep, monotonic=lambda: '
                f'float(Path({str(folder / "escalate")!r}).exists()))\n'
                'raise SystemExit(runner.main())\n')
            leaf = folder / 'leaf.py'
            leaf.write_text(
                'import os, signal, time\nfrom pathlib import Path\n'
                f'folder = Path({str(folder)!r})\n'
                'signal.signal(signal.SIGINT, signal.SIG_IGN)\n'
                'def terminate(*_):\n'
                '    print("owned helper shutdown output", flush=True)\n'
                '    (folder / "term").write_text("observed")\n'
                'signal.signal(signal.SIGTERM, terminate)\n'
                '(folder / "leaf-pid").write_text(str(os.getpid()))\n'
                '(folder / "ready").touch()\n'
                f'while {stubborn!r} or not (folder / "release").exists():\n'
                '    time.sleep(0.02)\n'
                '(folder / "checkout/worker-output.txt").write_text("helper completed")\n'
                'print("owned helper completion output", flush=True)\n')
            gate = folder / 'gate.py'
            gate.write_text(
                'import os, signal, subprocess, sys, time\nfrom pathlib import Path\n'
                f'folder = Path({str(folder)!r})\n'
                'signal.signal(signal.SIGINT, signal.SIG_IGN)\n'
                'signal.signal(signal.SIGTERM, signal.SIG_IGN)\n'
                '(folder / "gate-pid").write_text(str(os.getpid()))\n'
                f'child = subprocess.Popen([sys.executable, {str(leaf)!r}], '
                f'start_new_session={detached!r})\n'
                'while not (folder / "ready").exists() or not (folder / "observed").exists():\n'
                '    time.sleep(0.01)\n'
                f'raise SystemExit({7 if failed_exit else 0} if '
                f'{bool(natural_exit or failed_exit or interrupt_while_waiting)!r} else child.wait())\n')
            children = []

            def start(label, target):
                evidence = folder / label
                evidence.mkdir()
                (evidence / 'baseline.json').write_text('{}')
                if label == 'first' and interrupt_at:
                    (evidence / 'ledger.jsonl').write_text('{"name": "earlier", "status": "PASS"}\n')
                plan = folder / (label + '-plan.json')
                gates = [{'name': 'gate', 'cwd': str(checkout),
                          'argv': [sys.executable, str(target)]}]
                if label == 'first':
                    gates.append({'name': 'must-not-run', 'cwd': str(checkout),
                                  'argv': [sys.executable, '-c',
                                           'from pathlib import Path\n'
                                           f'if {successful_exit!r} and Path("worker-output.txt").read_text() != "helper completed":\n'
                                           '    raise SystemExit(9)\n'
                                           f'Path({str(folder / "next-gate")!r}).touch()']})
                plan.write_text(json.dumps(gates))
                log = (folder / (label + '.log')).open('wb')
                try:
                    child = subprocess.Popen([sys.executable, str(wrapper), '--evidence',
                                              str(evidence), '--plan', str(plan)],
                                             stdout=log, stderr=subprocess.STDOUT,
                                             start_new_session=True)
                finally:
                    log.close()
                children.append(child)
                return child, evidence

            other = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'],
                                     start_new_session=True)
            children.append(other)
            try:
                controller, evidence = start('first', gate)
                self.wait_for(lambda: (folder / 'ready').exists(), 'grandchild readiness')
                if natural_exit or interrupt_while_waiting:
                    def parent_exited():
                        state = regression.process_table().get(int((folder / 'gate-pid').read_text()))
                        return state is None or state['state'].startswith('Z')
                    self.wait_for(parent_exited, 'successful immediate parent exit')
                elif not failed_exit:
                    controller.send_signal(signum)
                if not (natural_exit or interrupt_while_waiting):
                    self.wait_for(lambda: (folder / 'term').exists() or controller.poll() is not None,
                                  'cleanup start')
                sentinel = folder / 'sentinel'
                success = folder / 'success.py'
                success.write_text(f'from pathlib import Path\nPath({str(sentinel)!r}).touch()\n')
                contender, _ = start('contender', success)
                self.assertNotEqual(contender.wait(timeout=15), 0,
                                    'Checkout lock was released while the grandchild was live')
                self.assertFalse(sentinel.exists())
                self.assertFalse((folder / 'next-gate').exists())
                if natural_exit or interrupt_while_waiting:
                    self.assertEqual(json.loads((evidence / 'gate/result.json').read_text())['status'],
                                     'RUNNING')
                    self.assertFalse((folder / 'term').exists())
                    self.assertFalse((checkout / 'worker-output.txt').exists())
                if interrupt_while_waiting:
                    controller.send_signal(signum)
                    self.wait_for(lambda: (folder / 'term').exists(), 'cleanup of the draining helper')
                if not stubborn:
                    self.assertIsNone(controller.poll())
                    # A repeated interrupt must not unwind the cleanup/lock scope.
                    if not failed_exit and not natural_exit:
                        controller.send_signal(signal.SIGINT)
                    time.sleep(0.1)
                    self.assertIsNone(controller.poll())
                    (folder / 'release').touch()
                else:
                    (folder / 'escalate').touch()
                expected_code = 0 if successful_exit else (1 if failed_exit else 128 + signum)
                self.assertEqual(controller.wait(timeout=15), expected_code)
                record = json.loads((evidence / 'gate/result.json').read_text())
                self.assertEqual(record['status'], 'PASS' if successful_exit else 'FAIL')
                if failed_exit or successful_exit:
                    self.assertEqual(record['exitCode'], 7 if failed_exit else 0)
                    self.assertNotIn('outcome', record)
                else:
                    self.assertEqual(record['outcome'], 'interrupted')
                    self.assertEqual(record['interruptSignal'], signum)
                self.assertTrue(record['processTree']['exited'])
                self.assertTrue(record['processTree']['childReaped'])
                self.assertTrue(all(item['exitObserved'] for item in record['processTree']['members']))
                table = regression.process_table()
                for name in ('gate-pid', 'leaf-pid'):
                    state = table.get(int((folder / name).read_text()))
                    self.assertTrue(state is None or state['state'].startswith('Z'))
                self.assertEqual((folder / 'next-gate').exists(), successful_exit)
                ledger = (evidence / 'ledger.jsonl').read_text()
                self.assertEqual(len(ledger.splitlines()), 1 + bool(interrupt_at) + successful_exit)
                if interrupt_at:
                    self.assertTrue(ledger.startswith('{"name": "earlier", "status": "PASS"}\n'))
                rows = [json.loads(line) for line in ledger.splitlines()]
                self.assertEqual(next(row for row in rows if row['name'] == 'gate'), record)
                output = (evidence / 'gate/output.log').read_text()
                self.assertIn('owned helper completion output' if natural_exit else
                              'owned helper shutdown output', output)
                self.assertEqual(record['logSha256'], regression.digest(evidence / 'gate/output.log'))
                self.assertIn('finishedUtc', record)
                if natural_exit:
                    self.assertEqual(record['processTree']['signalsSent'], [])
                    final_source = json.loads((evidence / 'gate/source-after.json').read_text())
                    self.assertEqual(final_source['worker-output.txt'],
                                     regression.digest(checkout / 'worker-output.txt'))
                else:
                    self.assertIn('SIGTERM', record['processTree']['signalsSent'])
                if stubborn:
                    self.assertIn('SIGKILL', record['processTree']['signalsSent'])
                elif not failed_exit and not natural_exit:
                    self.assertGreaterEqual(record['interruptCount'], 2)
                self.assertIsNone(other.poll(), 'Cleanup signaled an unrelated process')
                successor, _ = start('successor', success)
                self.assertEqual(successor.wait(timeout=15), 0)
                self.assertTrue(sentinel.exists())
            finally:
                (folder / 'release').touch()
                # Exact test-owned PIDs only, including cleanup after a pre-fix failure.
                for name in ('leaf-pid', 'gate-pid'):
                    path = folder / name
                    if path.exists():
                        try:
                            os.kill(int(path.read_text()), signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                for child in children:
                    if child.poll() is None:
                        child.kill()
                    child.wait(timeout=15)

    def test_sigint_holds_checkout_lock_until_grandchild_exits(self):
        self.exercise_interruption()

    def test_detached_grandchild_is_owned_until_exit(self):
        self.exercise_interruption(detached=True)

    def test_sigterm_is_recorded_and_holds_checkout_lock(self):
        self.exercise_interruption(signum=signal.SIGTERM)

    def test_stubborn_grandchild_is_killed_before_unlock(self):
        self.exercise_interruption(stubborn=True)

    def test_interrupt_during_final_manifest_still_settles_descendants(self):
        self.exercise_interruption(during_manifest=True)

    def test_nonzero_exit_settles_surviving_descendant_before_unlock(self):
        self.exercise_interruption(failed_exit=True)

    def test_interrupt_during_result_write_corrects_both_receipts(self):
        self.exercise_interruption(interrupt_at='result', signum=signal.SIGTERM)

    def test_interrupt_during_ledger_append_corrects_both_receipts(self):
        self.exercise_interruption(interrupt_at='ledger')

    def test_pending_interrupt_at_final_seal_is_recorded(self):
        self.exercise_interruption(interrupt_at='seal', signum=signal.SIGTERM)

    def test_successful_parent_waits_for_helper_before_next_gate(self):
        self.exercise_interruption(successful_exit=True)

    def test_successful_parent_waits_for_detached_observed_helper(self):
        self.exercise_interruption(successful_exit=True, detached=True)

    def test_interrupt_while_successful_parent_helper_drains_stays_failed(self):
        self.exercise_interruption(interrupt_while_waiting=True, signum=signal.SIGTERM)

    def test_ledger_revision_refuses_to_truncate_another_writer(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'ledger.jsonl'
            prefix = b'{"name": "earlier", "status": "PASS"}\n'
            path.write_bytes(prefix)
            slot = regression.GateLedgerSlot(path)
            slot.publish({'name': 'owned', 'status': 'PASS'})
            with path.open('ab') as stream:
                stream.write(b'{"name": "unexpected writer"}\n')
            unexpected = path.read_bytes()
            with self.assertRaisesRegex(OSError, 'Ledger tail changed'):
                slot.publish({'name': 'owned', 'status': 'FAIL'})
            self.assertEqual(path.read_bytes(), unexpected)
            self.assertTrue(unexpected.startswith(prefix))

    def test_receipt_recording_error_preserves_settled_owner_and_stays_failed(self):
        write_json = regression.write_json
        injected = OSError('injected final receipt failure')
        failed = False

        def write_once(path, record):
            nonlocal failed
            write_json(path, record)
            if path.name == 'result.json' and record['status'] == 'PASS' and not failed:
                failed = True
                raise injected

        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory)
            with patch.object(regression, 'source_manifest', return_value={}), \
                    patch.object(regression, 'process_table', return_value={}), \
                    patch.object(regression, 'OwnedGate') as owner, \
                    patch.object(regression, 'write_json', write_once):
                owner.return_value.wait_for_exit.return_value = {'exited': True, 'childReaped': True}
                with self.assertRaises(OSError) as caught:
                    regression.run_gate(evidence, 'recording-failed',
                        [sys.executable, '-c', 'print("completed")'], evidence, os.environ.copy())
                self.assertIs(caught.exception, injected)
                owner.return_value.wait_for_exit.assert_called_once()
                owner.return_value.stop.assert_not_called()
            record = json.loads((evidence / 'recording-failed/result.json').read_text())
            self.assertEqual(record['status'], 'BLOCKED')
            self.assertEqual(record['outcome'], 'recording_failed')
            self.assertEqual(record['exitCode'], 0)
            self.assertIn('injected final receipt failure', record['recordingError'])
            self.assertEqual(record['logSha256'], regression.digest(evidence / 'recording-failed/output.log'))
            self.assertEqual(json.loads((evidence / 'ledger.jsonl').read_text()), record)

    def test_unavailable_process_observation_blocks_before_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory)
            with patch.object(regression, 'source_manifest', return_value={}), \
                    patch.object(regression, 'process_table', side_effect=OSError('ps unavailable')), \
                    patch.object(regression.subprocess, 'Popen') as launch:
                self.assertFalse(regression.run_gate(evidence, 'blocked', ['unused'], evidence,
                                                     os.environ.copy()))
                launch.assert_not_called()
            record = json.loads((evidence / 'blocked/result.json').read_text())
            self.assertEqual(record['status'], 'BLOCKED')
            self.assertEqual(record['error'], 'ps unavailable')
            self.assertIsNone(record['logSha256'])

    def test_observation_failure_after_launch_still_reaps_child(self):
        observe = regression.OwnedGate.observe
        calls = 0

        def fail_once(owner):
            nonlocal calls
            calls += 1
            if calls == 1:
                raise OSError('lost initial observation')
            if calls == 2:
                raise OSError('transient cleanup observation failure')
            return observe(owner)

        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory)
            with patch.object(regression, 'source_manifest', return_value={}), \
                    patch.object(regression.OwnedGate, 'observe', fail_once):
                self.assertFalse(regression.run_gate(evidence, 'observation-failed',
                    [sys.executable, '-c', 'import time; time.sleep(60)'], evidence,
                    os.environ.copy()))
            record = json.loads((evidence / 'observation-failed/result.json').read_text())
            self.assertEqual(record['status'], 'BLOCKED')
            self.assertEqual(record['error'], 'lost initial observation')
            self.assertTrue(record['processTree']['exited'])
            self.assertTrue(record['processTree']['childReaped'])
            self.assertIn('transient cleanup observation failure', record['processTree']['cleanupErrors'])


if __name__ == '__main__':
    unittest.main()
