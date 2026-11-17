#!/usr/bin/env python3
"""Sequential four-member regression ledger; not the 1C candidate contract."""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
INTERRUPT_GRACE_SECONDS = 5


class GateInterrupted(Exception):
    def __init__(self, signum):
        self.signum = signum
        super().__init__('Gate interrupted by ' + signal.Signals(signum).name)


class DeferredInterrupts(list):
    """Defer signals until cleanup and receipt publication reach one stable cut."""
    signals = {signal.SIGINT, signal.SIGTERM}

    def __enter__(self):
        self.previous = {}
        self.sealed = False
        for signum in (signal.SIGINT, signal.SIGTERM):
            self.previous[signum] = signal.signal(signum, lambda number, _: self.append(number))
        return self

    def restore(self):
        for signum, handler in self.previous.items():
            signal.signal(signum, handler)

    def seal_if_unchanged(self, count):
        # Close the deferred-handler window atomically with its final check.
        # A pending signal received during this block must be handled and the
        # receipts republished. Signals after sealing belong to the caller.
        previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, self.signals)
        try:
            pending = signal.sigpending() & (self.signals - previous_mask)
            if len(self) != count or pending:
                return False
            self.restore()
            self.sealed = True
            return True
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)

    def __exit__(self, *_):
        if not self.sealed:
            self.restore()


class GateLedgerSlot:
    """Replace only this gate's last row when a late signal revises its receipt."""
    def __init__(self, path):
        self.path = path
        self.offset = path.stat().st_size if path.exists() else 0
        self.tail = b''

    def publish(self, record):
        payload = (json.dumps(record) + '\n').encode()
        with self.path.open('a+b') as stream:
            stream.seek(self.offset)
            if stream.read() != self.tail:
                raise OSError('Ledger tail changed outside the owned gate')
            stream.truncate(self.offset)
            stream.write(payload)
        self.tail = payload


def process_table():
    """Read identities/ancestry only, never other processes' argv or environment."""
    output = subprocess.check_output(
        ['/bin/ps', '-axo', 'pid=,ppid=,pgid=,stat=,lstart='], text=True,
        env={**os.environ, 'LC_ALL': 'C'})
    table = {}
    for line in output.splitlines():
        fields = line.split(maxsplit=4)
        if len(fields) != 5:
            raise OSError('Incomplete OS process identity')
        try:
            pid, parent, group = map(int, fields[:3])
        except ValueError as error:
            raise OSError('Invalid OS process identity') from error
        table[pid] = {'pid': pid, 'ppid': parent, 'pgid': group,
                      'state': fields[3], 'started': fields[4].strip()}
    if os.getpid() not in table:
        raise OSError('OS process observation unavailable')
    return table


class OwnedGate:
    """Own an isolated gate group and observed descendants, including new sessions.

    Gates must not daemonize and escape before ancestry can be observed. Normal
    compiler/hook children remain covered after reparenting by their PID/birth
    identity. No name-based process lookup or signaling is used.
    """
    def __init__(self, child):
        self.child = child
        self.members = {}
        self.signals_sent = []
        self.errors = []

    def observe(self):
        table = process_table()
        owned = {pid for pid, item in table.items()
                 if item['pgid'] == self.child.pid or
                 (pid in self.members and item['started'] == self.members[pid]['started'])}
        while True:
            descendants = {pid for pid, item in table.items() if item['ppid'] in owned}
            if descendants <= owned:
                break
            owned.update(descendants)
        self.members.update({pid: table[pid] for pid in owned})
        for pid, item in self.members.items():
            current = table.get(pid)
            item['exitObserved'] = (current is None or current['started'] != item['started']
                                    or current['state'][0] in ('Z', 'X'))
        return {pid: table[pid] for pid in owned if table[pid]['state'][0] not in ('Z', 'X')}

    def exit_receipt(self):
        return {'exited': True, 'childReaped': True,
                'members': list(self.members.values()),
                'signalsSent': self.signals_sent, 'cleanupErrors': self.errors}

    def wait_for_exit(self, interrupted):
        """Drain a successful gate naturally; only an interrupt requests stopping.

        A zero parent exit does not close descendant writers. Retain ownership
        without a wrapper deadline, then observe the final source/log cut only
        after every owned process has exited. Observation failures propagate to
        the existing failure/cleanup path.
        """
        while not interrupted:
            self.child.poll()
            if not self.observe() and self.child.poll() is not None:
                return self.exit_receipt()
            time.sleep(0.05)
        return None

    def stop(self):
        """Keep ownership until exit is observed, even if observation/signaling fails.

        TERM's grace period is an escalation deadline, never proof of exit. The
        checkout lock remains held through KILL and OS confirmation. Zombies are
        exited/non-mutating; the immediate Popen child is always reaped as well.
        """
        deadline = time.monotonic() + INTERRUPT_GRACE_SECONDS
        sent = set()
        while True:
            try:
                self.child.poll()  # Reap the immediate child, including a zombie.
                live = self.observe()
                if not live and self.child.poll() is not None:
                    return self.exit_receipt()
                signum = signal.SIGTERM if time.monotonic() < deadline else signal.SIGKILL
                # A group is signaled only while a current owned member proves
                # its identity; isolated groups cover concurrent child forks.
                for group in sorted({item['pgid'] for item in live.values()}):
                    if group <= 1 or group == os.getpgrp():
                        raise OSError('Refusing to signal a non-isolated process group')
                    if (group, signum) not in sent or signum == signal.SIGKILL:
                        try:
                            os.killpg(group, signum)
                        except ProcessLookupError:
                            pass
                        else:
                            label = signal.Signals(signum).name
                            if label not in self.signals_sent:
                                self.signals_sent.append(label)
                        sent.add((group, signum))
            except (OSError, subprocess.SubprocessError) as error:
                message = str(error)
                if message not in self.errors:
                    self.errors.append(message)
                    try:
                        print('CLEANUP PENDING: ' + message, file=sys.stderr, flush=True)
                    except OSError:
                        pass  # A broken diagnostic stream cannot release ownership.
                # Never release the checkout lock on an unconfirmed exit.
            time.sleep(0.05)


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def capture(argv):
    return subprocess.check_output(argv, cwd=ROOT).decode()


def source_manifest():
    names = capture(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard']).split('\0')
    return {name: digest(ROOT / name) for name in sorted(set(names))
            if name and (ROOT / name).is_file()}


def inventory(folder):
    result = {}
    for path in sorted(folder.rglob('*')):
        name = str(path.relative_to(folder))
        if path.is_symlink():
            result[name] = {'symlink': os.readlink(path)}
        elif path.is_file():
            result[name] = {'sha256': digest(path), 'size': path.stat().st_size,
                            'mode': path.stat().st_mode & 0o777}
    return result


def snapshot_sources(evidence, label):
    if not re.fullmatch(r'[A-Za-z0-9_-]+', label):
        raise ValueError('Invalid snapshot label')
    folder = evidence / ('source-' + label)
    folder.mkdir()
    manifest = source_manifest()
    for name in manifest:
        target = folder / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, target)
    write_json(evidence / ('source-' + label + '.json'), manifest)
    (evidence / ('source-' + label + '.diff')).write_text(capture(['git', 'diff', 'HEAD', '--binary']))


def run_gate(evidence, name, argv, cwd, env):
    if not re.fullmatch(r'[A-Za-z0-9_-]+', name):
        raise ValueError('Invalid gate name')
    folder = evidence / name
    folder.mkdir()  # Never overwrite an earlier attempt.
    before = source_manifest()
    write_json(folder / 'source-before.json', before)
    record = {'name': name, 'argv': argv, 'cwd': str(cwd),
              'startedUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'python': sys.executable, 'environment': {
                  key: env.get(key) for key in ('PATH', 'DEVELOPER_DIR', 'CC', 'CXX',
                                               'ANDROID_HOME', 'ANDROID_SDK_ROOT', 'JAVA_HOME')},
              'status': 'RUNNING'}
    write_json(folder / 'result.json', record)
    print('START ' + name, flush=True)
    with DeferredInterrupts() as interrupted:
        child = None
        owned = None
        failure = None
        unexpected = None

        def settle_owned():
            if child is not None and 'processTree' not in record:
                # Also covers exceptions immediately after Popen.
                record['processTree'] = (owned or OwnedGate(child)).stop()
                record['exitCode'] = child.returncode

        def update_receipt():
            if interrupted:
                record.update(status='FAIL', outcome='interrupted',
                              interruptSignal=interrupted[0], interruptCount=len(interrupted))
            log_path = folder / 'output.log'
            record['logSha256'] = digest(log_path) if log_path.exists() else None
            record['finishedUtc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
            write_json(folder / 'result.json', record)

        try:
            # Fail before launching a gate if safe process observation is unavailable.
            process_table()
            with (folder / 'output.log').open('xb') as log:
                child = subprocess.Popen(argv, cwd=cwd, env=env, stdout=log,
                                         stderr=subprocess.STDOUT, start_new_session=True)
                owned = OwnedGate(child)
                while not interrupted:
                    owned.observe()
                    try:
                        child.wait(timeout=0.25)
                        break
                    except subprocess.TimeoutExpired:
                        pass
            record.update(exitCode=child.returncode,
                          status='PASS' if child.returncode == 0 else 'FAIL')
            if child.returncode == 0 and not interrupted:
                receipt = owned.wait_for_exit(interrupted)
                if receipt is not None:
                    record['processTree'] = receipt
        except (OSError, subprocess.SubprocessError) as error:
            failure = error
            record.update(exitCode=None, status='BLOCKED', error=str(error))
        except BaseException as error:
            failure = error
            unexpected = error
            record.update(exitCode=None, status='FAIL', error=repr(error))

        slot = None
        try:
            slot = GateLedgerSlot(evidence / 'ledger.jsonl')
            while True:
                count = len(interrupted)
                if interrupted or failure is not None or (child is not None and child.returncode != 0):
                    settle_owned()
                write_json(folder / 'source-after.json', source_manifest())
                if len(interrupted) != count:
                    continue  # Settle a signal first received during the manifest query.
                # Hash only after this iteration's cleanup, including shutdown output.
                update_receipt()
                slot.publish(record)
                if interrupted.seal_if_unchanged(count):
                    break
                # A signal during result/ledger writing revises the same row;
                # no stale PASS or duplicate gate entry is left finalized.
        except BaseException as error:
            # Recording failures are unsuccessful gates too. Preserve the error
            # after settling owned processes, even if evidence storage is broken.
            settle_owned()
            record.update(status='BLOCKED' if isinstance(error, OSError) else 'FAIL',
                          outcome='recording_failed', recordingError=repr(error))
            try:
                write_json(folder / 'source-after.json', source_manifest())
                update_receipt()
                (slot or GateLedgerSlot(evidence / 'ledger.jsonl')).publish(record)
            except BaseException as diagnostic_error:
                error.add_note('Could not finalize failure receipt: ' + repr(diagnostic_error))
            raise
        if unexpected is not None:
            raise unexpected
        if interrupted:
            print('INTERRUPTED ' + name, flush=True)
            raise GateInterrupted(interrupted[0])
    print(record['status'] + ' ' + name, flush=True)
    return record['status'] == 'PASS'


def software_plan(evidence, flutter, dart, expected_version='0.1.0-dev.3', app_build=None):
    app = 'apps/meshchan_app'
    core = 'packages/meshchan_core'
    cli = 'apps/meshctl'
    link = 'packages/meshcore_link'
    plan = []
    def add(name, argv, cwd='.'):
        plan.append({'name': name, 'argv': list(map(str, argv)), 'cwd': str(ROOT / cwd)})
    if app_build is not None:
        add('R01-versions', [sys.executable, 'tool/check_product_version.py',
            '--expected-version', expected_version, '--app-build', app_build])
    add('R02-pub', [flutter, 'pub', 'get', '--enforce-lockfile'])
    add('R02-graph', [dart, 'pub', 'deps', '--json'])
    add('R03-generate', [dart, 'run', 'build_runner', 'build'], core)
    add('R04-schema', [dart, 'run', 'tool/check_schema.dart'], core)
    artifacts = [core + '/' + name for name in (
        'lib/src/storage/database.g.dart', 'test/support/dependency_probe_database.g.dart',
        'drift_schemas/drift_schema_v1.json', 'test/storage/generated/schema.dart',
        'test/storage/generated/schema_v1.dart')]
    add('R04-tracked', ['git', 'ls-files', '--error-unmatch', *artifacts])
    add('R04-diff', ['git', 'diff', '--exit-code', '--', 'pubspec.lock', *artifacts])
    sources = [p for p in source_manifest() if p.endswith('.dart')]
    add('R05-format', [dart, 'format', '--output=none', '--set-exit-if-changed', *sources])
    add('R05-analyze', [flutter, 'analyze', '--no-pub', '--fatal-infos'])
    add('R06-app', [flutter, 'test', '--no-pub', '--concurrency=1', '--reporter', 'expanded'], app)
    for checker in ('runtime', 'draft', 'profile', 'device', 'diagnostic', 'history'):
        add('R07-' + checker, [sys.executable, app + '/tool/check_' + checker + '_process.py',
            '--dart', dart, '--evidence-root', evidence / ('process-' + checker)])
    add('R08-python', [sys.executable, '-m', 'unittest', 'discover', '-s', 'tool', '-p', '*_test.py'])
    for name, cwd in [('R09-core', core), ('R10-cli', cli), ('R11-link', link)]:
        add(name, [dart, 'test', '--reporter', 'expanded'], cwd)
    for name, cwd, target in [('cli', cli, 'bin/meshctl.dart'),
            ('observation', link, 'example/serial_transport_check.dart'),
            ('acceptance', cli, 'tool/datagram_acceptance.dart')]:
        add('R12-' + name, [dart, 'build', 'cli', '--target=' + target,
                           '--output=' + str(evidence / name)], cwd)
    add('R13-smoke', [sys.executable, 'tool/smoke_cli.py', '--dart', dart,
        '--cli-bundle', evidence / 'cli/bundle', '--observation-bundle', evidence / 'observation/bundle',
        '--datagram-acceptance-bundle', evidence / 'acceptance/bundle',
        '--evidence-directory', evidence / 'smoke-recordings', '--expected-version', expected_version])
    add('R17-legacy', [sys.executable, 'tool/check_schema_compatibility.py',
                     '--dart', dart, '--build-directory', evidence, '--expected-version', expected_version])
    return plan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--init', action='store_true')
    parser.add_argument('--software', action='store_true')
    parser.add_argument('--expected-version', default='0.1.0-dev.3')
    parser.add_argument('--app-build', type=int)
    parser.add_argument('--plan', type=Path, help='JSON array of name/argv/absolute cwd records')
    parser.add_argument('--flutter', type=Path)
    parser.add_argument('--dart', type=Path)
    parser.add_argument('--inventory', type=Path)
    parser.add_argument('--inventory-label', help='Distinct label for bundles sharing a basename')
    parser.add_argument('--snapshot', help='Retain source bytes, manifest and dirty diff under a new label')
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    if evidence == ROOT or ROOT in evidence.parents:
        parser.error('Evidence must be external to the checkout')
    if args.init:
        evidence.mkdir(parents=True, exist_ok=False)
        write_json(evidence / 'baseline.json', {
            'head': capture(['git', 'rev-parse', 'HEAD']).strip(),
            'tree': capture(['git', 'rev-parse', 'HEAD^{tree}']).strip(),
            'branch': capture(['git', 'branch', '--show-current']).strip(),
            'status': capture(['git', 'status', '--porcelain=v1']),
            'python': sys.executable, 'pythonVersion': sys.version})
        (evidence / 'baseline.diff').write_text(capture(['git', 'diff', 'HEAD', '--binary']))
        snapshot_sources(evidence, 'initial')
    if not (evidence / 'baseline.json').is_file():
        parser.error('Initialize a new evidence directory first')
    # A checkout-wide advisory lock also protects separate invocations using different evidence roots.
    (ROOT / '.dart_tool').mkdir(exist_ok=True)
    with (ROOT / '.dart_tool/meshchan-1d10.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.snapshot:
            snapshot_sources(evidence, args.snapshot)
        if args.inventory:
            label = args.inventory_label or args.inventory.name
            if not re.fullmatch(r'[A-Za-z0-9_.-]+', label):
                parser.error('Invalid inventory label')
            output = evidence / ('inventory-' + label + '.json')
            with output.open('x') as stream:
                json.dump(inventory(args.inventory.resolve(strict=True)), stream, indent=2)
        plan = []
        if args.software:
            if not args.flutter or not args.dart:
                parser.error('--software requires absolute --flutter and --dart')
            for executable in (args.flutter, args.dart):
                if not executable.is_absolute() or not executable.is_file():
                    parser.error('SDK executable must be an existing absolute path')
            plan = software_plan(evidence, args.flutter, args.dart, args.expected_version, args.app_build)
        if args.plan:
            plan += json.loads(args.plan.read_text())
        env = dict(os.environ)
        env['PATH'] = '/usr/bin:/bin:/opt/homebrew/opt/python@3.15/libexec/bin:/opt/homebrew/bin:' + env.get('PATH', '')
        for gate in plan:
            cwd = Path(gate['cwd'])
            if not cwd.is_absolute() or not cwd.is_dir():
                raise ValueError('Gate cwd must be an existing absolute directory')
            try:
                if not run_gate(evidence, gate['name'], gate['argv'], cwd, env):
                    return 1
            except GateInterrupted as error:
                return 128 + error.signum
    return 0


if __name__ == '__main__':
    sys.exit(main())
