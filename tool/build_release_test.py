"""Release entry risks with owned fixtures and real isolated child processes."""
import argparse
from contextlib import ExitStack, contextmanager, redirect_stderr, redirect_stdout
import fcntl
import io
import json
import os
from pathlib import Path
import shlex
import signal
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

import build_release as b
from release_materials import FRESH_HOOK_RECIPE, digest, encoded, repository_source_hashes, source_archive


class StablePython(tuple):
    releaselevel = 'final'


WORKSPACE_MEMBERS = ('packages/meshcore_link', 'packages/meshchan_core', 'apps/meshctl', 'apps/meshchan_app')
ENGINE_STAMP = 'bin/cache/engine_stamp.stamp'


def make_flutter_tool_cache(flutter, pins):
    hosted = flutter/'fixture pub cache/hosted_package'
    package_config = {'configVersion': 2, 'packages': [
        {'name': 'flutter_tools', 'rootUri': '../', 'packageUri': 'lib/'},
        {'name': 'hosted_package', 'rootUri': hosted.as_uri(), 'packageUri': 'lib/'},
    ]}
    version = {'frameworkVersion': '3.50.0', 'channel': 'stable', 'frameworkCommitDate': 'fixture date',
               'repositoryUrl': 'https://github.com/flutter/flutter.git', 'dartSdkVersion': '3.14.0',
               'devToolsVersion': '2.0.0', 'flutterVersion': '3.50.0', **pins}
    files = {b.FLUTTER_TOOL_SNAPSHOT: 'tool snapshot',
             b.FLUTTER_TOOL_STAMP: pins['frameworkRevision']+':\n',
             b.FLUTTER_VERSION_CACHE: json.dumps(version),
             b.FLUTTER_TOOL_PUBSPEC: 'name: flutter_tools\n', b.FLUTTER_TOOL_LOCK: 'packages: {}\n',
             b.FLUTTER_TOOL_PACKAGE_CONFIG: json.dumps(package_config),
             'bin/cache/dart-sdk/version': '3.14.0\n', 'bin/cache/dart-sdk/revision': 'fixture revision\n',
             hosted/'pubspec.yaml': 'name: hosted_package\n'}
    for name, directories in b.FLUTTER_ENGINE_ARTIFACTS.items():
        files[f'bin/cache/{name}.stamp'] = pins['engineRevision']+'\n'
        for directory in directories:
            (flutter/'bin/cache'/directory).mkdir(parents=True, exist_ok=True)
    for name, required in b.FLUTTER_UNIVERSAL_ARTIFACTS.items():
        files[f'bin/internal/{name}.version'] = files[f'bin/cache/{name}.stamp'] = 'pinned '+name+'\n'
        (flutter/'bin/cache/artifacts'/name).mkdir(parents=True, exist_ok=True)
        files.update({f'bin/cache/artifacts/{name}/{path}': 'cached artifact' for path in required})
    for name, content in files.items():
        path = flutter/name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
    os.utime(flutter/b.FLUTTER_TOOL_PUBSPEC, ns=(1_000_000_000, 1_000_000_000))


def macho_header(file_type):
    return ('Mach header\n      magic  cputype cpusubtype  caps    filetype ncmds sizeofcmds      flags\n'
            f' 0xfeedfacf 16777228          0  0x00          {file_type}     1         64 0x00000000\n')


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='release path with spaces ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        subprocess.run(['git', 'init', '-q', self.root], check=True)
        subprocess.run(['git', '-C', self.root, 'config', 'user.email', 'fixture@example.invalid'], check=True)
        subprocess.run(['git', '-C', self.root, 'config', 'user.name', 'Fixture'], check=True)
        (self.root/'.gitignore').write_text('build/\n.dart_tool/\n')
        (self.root/'tool').mkdir()
        (self.root/'tool/build_release.py').write_bytes(Path(b.__file__).read_bytes())
        (self.root/'source.dart').write_text('source')
        subprocess.run(['git', '-C', self.root, 'add', '.'], check=True)
        subprocess.run(['git', '-C', self.root, 'commit', '-qm', 'Fixture'], check=True)
        self.out = self.root/'build/phase-1e4/run 1'

    def test_output_is_new_ignored_owned_and_never_source_or_alias(self):
        self.assertEqual(b.output_path(self.root, self.out, True), self.out)
        for path in (self.root, self.root/'.git/out', self.root/'tool', self.root/'build', self.root/'build/phase-1e3/old'):
            with self.subTest(path=path), self.assertRaises(ValueError):
                b.output_path(self.root, path, True)
        self.out.mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, 'existing'):
            b.output_path(self.root, self.out, True)
        link = self.root/'build/phase-1e4/alias'
        link.symlink_to(self.out, target_is_directory=True)
        with self.assertRaises(ValueError):
            b.output_path(self.root, link, True)
        (self.out/'build-info.json').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'overlaps'):
            b.output_path(self.root, self.out/'child', True)
        # An explicitly force-tracked file in build must still prevent exclusion.
        (self.out/'input.dart').write_text('tracked')
        subprocess.run(['git', '-C', self.root, 'add', '-f', str(self.out/'input.dart')], check=True)
        with self.assertRaisesRegex(ValueError, 'tracked source'):
            b.output_path(self.root, self.out)

    def test_build_rejects_parent_run_published_before_it_gets_the_checkout_lock(self):
        parent, child = self.out, self.out/'nested'
        self.assertEqual(b.output_path(self.root, child, True), child)
        real_lock = b.checkout_lock

        @contextmanager
        def checkout_lock(root):
            with real_lock(root):
                parent.mkdir(parents=True)
                b.write(parent/'build-info.json', {'buildStatus': 'FAIL'})
                yield

        args = argparse.Namespace(output=child, timeout=5, flutter=self.root/'sdk', allow_dirty=True)
        with (patch.object(b, 'ROOT', self.root), patch.object(b, 'checkout_lock', checkout_lock),
              self.assertRaisesRegex(ValueError, 'Output overlaps an existing run')):
            b.build(args)
        self.assertFalse(child.exists())

    def test_release_commands_require_a_finite_positive_timeout(self):
        material_options = ('--downloads', 'downloads', '--probe', 'probe.json', '--sdk-source-workspace', 'sdk')
        for verb, options in (('build', ()), ('check', ()), ('materials', material_options)):
            argv = ['build_release.py', verb, '--output', str(self.out), *options]
            with patch.object(b, verb, return_value=dict.fromkeys(
                    ('runIdentity', 'buildStatus', 'productChecksStatus', 'materials', 'compilationInputIdentity'))) as command:
                for value in ('nan', 'inf', '-Infinity', '1e400', '0', '-0.5'):
                    with (self.subTest(verb=verb, timeout=value),
                          patch.object(sys, 'argv', [*argv, '--timeout='+value]),
                          redirect_stderr(io.StringIO()) as errors, self.assertRaises(SystemExit) as failure):
                        b.main()
                    self.assertEqual(failure.exception.code, 2)
                    self.assertIn('finite, positive number of seconds', errors.getvalue())
                command.assert_not_called()
                with patch.object(sys, 'argv', [*argv, '--timeout=0.5']), redirect_stdout(io.StringIO()):
                    self.assertEqual(b.main(), 0)
                self.assertEqual(command.call_args.args[0].timeout, 0.5)

    def test_checkout_git_queries_ignore_inherited_foreign_repository(self):
        old = b.capture(['git', 'rev-parse', 'HEAD'], self.root)
        foreign = self.root/'build/foreign checkout'
        subprocess.run(['git', 'clone', '-q', '--no-hardlinks', self.root, foreign], check=True)
        subprocess.run(['git', '-C', foreign, 'rm', '--', '.gitignore'], check=True, capture_output=True)
        subprocess.run(['git', 'commit', '--allow-empty', '-qm', 'Actual checkout advanced'], cwd=self.root, check=True)
        head = b.capture(['git', 'rev-parse', 'HEAD'], self.root)
        before = repository_source_hashes(self.root, [self.out])
        with patch.dict(os.environ, {'GIT_DIR': str(foreign/'.git'), 'GIT_WORK_TREE': str(foreign),
                                     'GIT_INDEX_FILE': str(foreign/'.git/index')}):
            self.assertEqual(b.capture(['git', 'rev-parse', 'HEAD'], self.root), old)
            self.assertEqual(repository_source_hashes(self.root, [self.out]), before)
            self.assertEqual(b.output_path(self.root, self.out, True), self.out)
            runner = self.runner()
            b.require_checkout_commit(head, runner.command, 'correct-commit')
            with self.assertRaisesRegex(ValueError, 'checkout commit'):
                b.require_checkout_commit(old, runner.command, 'wrong-commit')

    def test_build_output_git_preflight_obeys_deadline_and_reaps_command(self):
        bin_dir = self.root/'fixture bin'
        bin_dir.mkdir()
        git = bin_dir/'git'
        git.write_text('''#!/bin/sh
for argument do
  if [ "$argument" = "$MESHCHAN_TEST_SLOW_GIT" ]; then
    printf '%s\\n' "$$" > "$MESHCHAN_TEST_GIT_PID"
    exec /bin/sleep 30
  fi
done
exec /usr/bin/git "$@"
''')
        git.chmod(0o755)
        pid_file = self.root/'fixture-git-pid'
        env = b.controlled_environment()
        env['PATH'] = str(bin_dir)+os.pathsep+env['PATH']
        env['MESHCHAN_TEST_GIT_PID'] = str(pid_file)
        for command, step in (('ls-files', 'output-tracked-files'), ('check-ignore', 'output-git-ignore')):
            with self.subTest(command=command):
                pid_file.unlink(missing_ok=True)
                env['MESHCHAN_TEST_SLOW_GIT'] = command
                with (patch.object(b, 'ROOT', self.root), patch.object(b, 'controlled_environment', return_value=env),
                      self.assertRaisesRegex(TimeoutError, 'Command deadline exceeded: '+step)):
                    b.build(argparse.Namespace(output=self.out, timeout=3))
                pid = int(pid_file.read_text())
                process = b.process_table().get(pid)
                self.assertTrue(process is None or process['state'][0] in ('Z', 'X'))
                self.assertFalse(self.out.exists())

    def test_source_enumeration_timeouts_seal_failed_build_receipts(self):
        original = b.Runner.command
        for kind in ('tracked', 'all'):
            with self.subTest(kind=kind):
                self.out = self.out.with_name('source-timeout-'+kind)
                step_name = 'source-before-resolution-'+kind

                def command(runner, name, argv, cwd=None, **kwargs):
                    if name == step_name:
                        self.assertIn('ls-files', argv)
                        self.assertEqual('--others' in argv, kind == 'all')
                        argv = ['/bin/sleep', '30']
                    return original(runner, name, argv, cwd, **kwargs)

                args = argparse.Namespace(output=self.out, timeout=0.7, flutter=self.root/'sdk',
                                          allow_dirty=True, expected_version=None, app_build=None)
                with (patch.object(b, 'ROOT', self.root), patch.object(b, 'identity'), patch.object(b, 'helpers'),
                      patch.object(b.Runner, 'command', command),
                      self.assertRaisesRegex(TimeoutError, 'Command deadline exceeded: '+step_name)):
                    b.build(args)
                receipt = b.read(self.out/'evidence/build-receipt.json')
                self.assertEqual(receipt['status'], 'FAIL')
                self.assertEqual(b.read(self.out/'build-info.json')['buildStatus'], 'FAIL')
                step = receipt['steps'][-1]
                self.assertEqual(step['name'], step_name)
                self.assertTrue(step['processTree']['exited'])
                self.assertIn('SIGTERM', step['processTree']['signalsSent'])
                with b.checkout_lock(self.root):
                    pass

    def test_frozen_source_and_sdk_checks_ignore_git_replacement_trees(self):
        root = self.root
        original = b.capture(['git', 'rev-parse', 'HEAD'], root)
        (root/'source.dart').write_text('replacement source')
        subprocess.run(['git', 'add', 'source.dart'], cwd=root, check=True)
        subprocess.run(['git', 'commit', '-qm', 'Alternative tree'], cwd=root, check=True)
        replacement = b.capture(['git', 'rev-parse', 'HEAD'], root)
        subprocess.run(['git', 'replace', original, replacement], cwd=root, check=True)
        subprocess.run(['git', 'switch', '--quiet', '--detach', original], cwd=root, check=True)
        self.assertEqual(b.capture(['git', 'rev-parse', 'HEAD'], root), original)
        self.assertEqual(b.capture(['git', 'status', '--porcelain'], root), '')
        source = repository_source_hashes(root, [])
        b.verify_committed_source(root, original, source, lambda name, argv: b.capture(argv, root))
        with (patch.dict(os.environ, {'GIT_NO_REPLACE_OBJECTS': ''}),
              self.assertRaisesRegex(ValueError, 'Clean source differs from recorded commit: source.dart')):
            env = b.controlled_environment()
            b.verify_committed_source(root, original, source, lambda name, argv: b.capture(argv, root, env))
        with self.assertRaisesRegex(ValueError, 'tracked modifications'):
            b.require_sdk_checkout(root, {'frameworkRevision': original},
                                   lambda name, argv, cwd: b.capture(argv, cwd, env))

    def test_shared_checkout_lock_coordinates_old_flow(self):
        with b.checkout_lock(self.root):
            with self.assertRaisesRegex(ValueError, 'lock is held'):
                with b.checkout_lock(self.root):
                    self.fail('Second build acquired shared lock')
            with (self.root/'.dart_tool/meshchan-1d10.lock').open('a') as old:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(old, fcntl.LOCK_EX | fcntl.LOCK_NB)
        with b.checkout_lock(self.root):
            pass

    def test_checkout_lock_rejects_aliased_dart_tool_and_lock_file(self):
        outside = Path(self.enterContext(tempfile.TemporaryDirectory(prefix='shared Dart state '))).resolve()
        package = outside/'package_config.json'
        package.write_text('another checkout')
        directory = self.root/'.dart_tool'
        lock = directory/'meshchan-1d10.lock'
        directory.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'real .dart_tool directory'):
            self.build_fixture(allow_dirty=True)
        self.assertFalse(self.out.exists())
        self.assertEqual(list(outside.iterdir()), [package])
        self.assertEqual(package.read_text(), 'another checkout')
        directory.unlink()
        directory.symlink_to(outside/'missing', target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'real .dart_tool directory'):
            with b.checkout_lock(self.root):
                self.fail('Acquired checkout lock through a dangling directory alias')
        self.assertFalse((outside/'missing').exists())
        directory.unlink()
        directory.mkdir()

        lock.symlink_to(outside/'external-lock')
        with self.assertRaisesRegex(ValueError, 'checkout-local build lock'):
            with b.checkout_lock(self.root):
                self.fail('Acquired checkout lock through a file alias')
        self.assertFalse((outside/'external-lock').exists())
        lock.unlink()
        os.link(package, lock)
        with self.assertRaisesRegex(ValueError, 'not an owned regular file'):
            with b.checkout_lock(self.root):
                self.fail('Acquired a hard-linked lock')
        self.assertEqual(package.read_text(), 'another checkout')

    def test_full_inventory_records_modes_and_framework_links_without_following(self):
        app = self.root/'Framework';(app/'Versions/A').mkdir(parents=True)
        binary = app/'Versions/A/code';binary.write_bytes(b'payload');binary.chmod(0o755)
        (app/'Versions/Current').symlink_to('A')
        (app/'code').symlink_to('Versions/Current/code')
        result = b.full_inventory(app)
        self.assertEqual(result['.']['type'], 'directory')
        self.assertEqual(result['Versions/A']['type'], 'directory')
        self.assertEqual(result['code']['type'], 'symlink')
        self.assertEqual(result['code']['symlink'], 'Versions/Current/code')
        self.assertEqual(result['Versions/A/code']['mode'], 0o755)
        self.assertNotIn('Versions/Current/code', result)
        (app/'escape').symlink_to('../source.dart')
        with self.assertRaisesRegex(ValueError, 'External'):
            b.full_inventory(app)
        (app/'escape').unlink()
        (app/'absolute').symlink_to(binary)
        with self.assertRaisesRegex(ValueError, 'Absolute product symlink'):
            b.full_inventory(app)

    def test_inventory_rejects_unscannable_directories(self):
        bundle = self.root/'product'
        hidden = bundle/'private'
        hidden.mkdir(parents=True)
        (hidden/'payload').write_bytes(b'unreadable payload')
        (bundle/'visible').write_bytes(b'public payload')
        hidden.chmod(0)
        try:
            with self.assertRaisesRegex(ValueError, 'Cannot scan product directory.*private'):
                b.full_inventory(bundle)
        finally:
            hidden.chmod(0o755)

    def test_inventory_rejects_links_that_leave_and_reenter(self):
        bundle = self.root/'product'
        (bundle/'lib').mkdir(parents=True)
        payload = bundle/'payload'
        payload.write_bytes(b'payload')
        link = bundle/'lib/link'
        link.symlink_to('../../product/payload')
        self.assertEqual(link.resolve(strict=True), payload)
        with self.assertRaisesRegex(ValueError, 'External product symlink'):
            b.full_inventory(bundle)
        link.unlink()
        # Resolving an intermediate relative link moves up a level before '..'.
        (bundle/'lib/root').symlink_to('..')
        link.symlink_to('root/../product/payload')
        self.assertEqual(link.resolve(strict=True), payload)
        with self.assertRaisesRegex(ValueError, 'External product symlink'):
            b.full_inventory(bundle)

    def test_inventory_preserves_raw_link_spelling_and_rejects_invalid_targets(self):
        bundle = self.root/'product'
        folder = bundle/'payloads'
        folder.mkdir(parents=True)
        (folder/'binary').write_bytes(b'payload')
        link = bundle/'link'
        link.symlink_to('payloads/')
        self.assertEqual(b.full_inventory(bundle)['link']['symlink'], 'payloads/')
        link.unlink()
        link.symlink_to('payloads//binary')
        self.assertEqual(b.full_inventory(bundle)['link']['symlink'], 'payloads//binary')
        link.unlink()
        link.symlink_to('payloads/binary/')
        with self.assertRaisesRegex(ValueError, 'Invalid product symlink'):
            b.full_inventory(bundle)

    def runner(self, timeout=5):
        self.out.mkdir(parents=True)
        return b.Runner(self.root, self.out, {'steps': [], 'status': 'RUNNING'}, b.controlled_environment(), timeout)

    def test_real_command_argv_spaces_and_failure_logs(self):
        runner = self.runner()
        arg = str(self.root/'a path with spaces')
        self.assertIn(arg, runner.command('argv', [sys.executable, '-c', 'import sys;print(sys.argv[1])', arg]))
        with self.assertRaises(subprocess.CalledProcessError):
            runner.command('failure', [sys.executable, '-c', 'print("owned failure");raise SystemExit(3)'])
        step = runner.receipt['steps'][-1]
        self.assertEqual(step['exitCode'], 3)
        self.assertEqual(step['logSha256'], digest(self.root/step['log']))
        self.assertTrue(step['processTree']['exited'])

    def test_machine_output_excludes_diagnostics_but_binds_both_streams(self):
        runner = self.runner()
        script = 'import sys; print("Building flutter tool...", file=sys.stderr); print(\'{"status":"PASS"}\')'
        output = runner.command('machine-probe', [sys.executable, '-c', script])
        self.assertEqual(json.loads(output), {'status': 'PASS'})
        step, = runner.receipt['steps']
        stderr = self.root/step['stderrLog']
        self.assertEqual(stderr.read_text(), 'Building flutter tool...\n')
        self.assertEqual(step['stderrLogSha256'], digest(stderr))

    def test_command_result_and_ledger_share_the_completed_log_snapshot(self):
        runner = self.runner()
        stdout, stderr = b'output\r\ncontinued\r', b'diagnostic\r\ncontinued\r'
        script = (f'import sys; sys.stdout.buffer.write({stdout!r}); '
                  f'sys.stderr.buffer.write({stderr!r}); sys.exit(int(sys.argv[1]))')
        save = runner.save
        for name, code, return_stderr, stream in (
            ('return-stdout', 0, False, 'log'),
            ('return-stderr', 0, True, 'stderrLog'),
            ('failed-stderr', 7, False, 'stderrLog'),
        ):
            with self.subTest(name=name):
                argv = [sys.executable, '-c', script, str(code)]

                def change_log_after_saving():
                    save()
                    step = runner.receipt['steps'][-1]
                    if stream+'Sha256' in step:
                        (self.root/step[stream]).write_bytes(b'later contents\n')

                with patch.object(runner, 'save', side_effect=change_log_after_saving):
                    if code:
                        with self.assertRaises(subprocess.CalledProcessError) as failure:
                            runner.command(name, argv)
                        self.assertEqual(failure.exception.returncode, code)
                        self.assertEqual(failure.exception.cmd, argv)
                        self.assertEqual(failure.exception.stderr, stderr)
                    else:
                        result = runner.command(name, argv, return_stderr=return_stderr)
                        self.assertEqual(result, ('diagnostic' if return_stderr else 'output')+'\ncontinued\n')

                step = b.read(self.out/'build-receipt.json')['steps'][-1]
                self.assertEqual(step['logSha256'], b.sha(stdout))
                self.assertEqual(step['stderrLogSha256'], b.sha(stderr))
                self.assertNotEqual(step[stream+'Sha256'], digest(self.root/step[stream]))

    def test_nonzero_parent_stops_live_helper_and_preserves_exit_code(self):
        runner = self.runner()
        helper = 'import time; print("ready", flush=True); time.sleep(30)'
        parent = (
            'import subprocess, sys\n'
            'helper = subprocess.Popen([sys.executable, "-c", sys.argv[1]], '
            'stdout=subprocess.PIPE, text=True)\n'
            'assert helper.stdout.readline().strip() == "ready"\n'
            'print(helper.pid, flush=True)\n'
            'raise SystemExit(9)\n'
        )
        with b.checkout_lock(self.root):
            with self.assertRaises(subprocess.CalledProcessError) as failure:
                runner.command('failed-parent', [sys.executable, '-c', parent, helper])
        self.assertEqual(failure.exception.returncode, 9)
        step = b.read(self.out/'build-receipt.json')['steps'][0]
        self.assertEqual(step['exitCode'], 9)
        log = self.root/step['log']
        self.assertEqual(step['logSha256'], digest(log))
        helper_pid = int(log.read_text().strip())
        tree = step['processTree']
        self.assertIn('SIGTERM', tree['signalsSent'])
        self.assertTrue(tree['childReaped'])
        self.assertTrue(next(p for p in tree['members'] if p['pid'] == helper_pid)['exitObserved'])

    def test_zero_parent_waits_for_helper_log_before_finalizing(self):
        runner = self.runner()
        helper = 'import time; time.sleep(0.25); print("helper complete", flush=True)'
        parent = 'import subprocess, sys; subprocess.Popen([sys.executable, "-c", sys.argv[1]])'
        result = runner.command('successful-parent', [sys.executable, '-c', parent, helper])
        self.assertEqual(result.strip(), 'helper complete')
        step = runner.receipt['steps'][0]
        self.assertEqual(step['logSha256'], digest(self.root/step['log']))
        self.assertEqual(step['processTree']['signalsSent'], [])

    def test_timeout_drains_owned_descendants_and_keeps_other_process(self):
        runner = self.runner(timeout=0.4)
        unrelated = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(30)'])
        self.addCleanup(lambda: (unrelated.terminate(), unrelated.wait()) if unrelated.poll() is None else None)
        marker = self.out/'late write'
        code = ('import subprocess,sys,time;subprocess.Popen([sys.executable,"-c",'
                '"import sys,time;from pathlib import Path;time.sleep(2);Path(sys.argv[1]).write_text(\'bad\')",sys.argv[1]]);time.sleep(30)')
        with self.assertRaises(TimeoutError):
            runner.command('timeout', [sys.executable, '-c', code, str(marker)])
        self.assertIsNone(unrelated.poll())
        self.assertTrue(runner.receipt['steps'][0]['processTree']['exited'])
        self.assertFalse(marker.exists())

    def test_signal_interrupt_records_failed_build_and_cleans_child(self):
        # Exercise the actual public build failure handler in a separate process.
        runner = self.runner()
        wrapper = self.out/'interrupt.py'
        wrapper.write_text('import sys\nsys.path.insert(0,'+repr(str(Path(b.__file__).parent))+')\n'
            'from pathlib import Path\nimport build_release as b\n'
            'r=b.Runner(Path('+repr(str(self.root))+'),Path('+repr(str(self.out))+'),{"steps":[],"status":"RUNNING"},b.controlled_environment())\n'
            'try:r.command("interrupt",[sys.executable,"-c","import time;print(\'ready\',flush=True);time.sleep(30)"])\n'
            'except BaseException:\n r.receipt["status"]="FAIL";r.save();raise\n')
        proc = subprocess.Popen([sys.executable, str(wrapper)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(lambda: (proc.kill(), proc.wait()) if proc.poll() is None else None)
        log = self.out/'logs/interrupt.log'
        for _ in range(100):
            if log.exists() and 'ready' in log.read_text():
                break
            time.sleep(0.03)
        else:
            self.fail('Child did not become ready')
        proc.send_signal(signal.SIGTERM)
        self.assertNotEqual(proc.wait(timeout=10), 0)
        receipt = b.read(self.out/'build-receipt.json')
        self.assertEqual(receipt['status'], 'FAIL')
        self.assertTrue(receipt['steps'][0]['processTree']['exited'])
        self.assertEqual(receipt['steps'][0]['logSha256'], digest(log))

    def build_fixture(self, *, mutate=None, mutate_path='source.dart', fail=None, missing=False, product_error=None,
                      allow_dirty=True, chmod_at=None, configuration=None, after_resolution=None, after_cli=None,
                      external_sources=None, release_framework=None, compiler_sources=(), inventoried_inputs=(),
                      shader_plan=(), asset_sources=(), transformed_assets=()):
        args = argparse.Namespace(output=self.out, flutter=self.root/'sdk', allow_dirty=allow_dirty,
                                  expected_version=None, app_build=None, timeout=5)
        product_id = {'productVersion': '0.1.0-rc.1', 'appBuild': '7'}
        observed = []
        package_config = self.root/'.dart_tool/package_config.json'
        real_compiler_inputs = b.compiler_inputs

        def fixture_compiler_inputs(root, depfiles, entry, *args):
            return real_compiler_inputs(root, depfiles, root/'source.dart', *args)

        def emit_depfile(path, targets, inputs):
            def escape(path):
                return str(path).replace('\\', '\\\\').replace(' ', '\\ ')
            path.parent.mkdir(parents=True, exist_ok=True)
            deps = ' '.join(map(escape, inputs))
            outputs = ' '.join(map(escape, targets))
            path.write_text(f'{outputs}: {deps}\n')

        def compile_inputs(*a, **kwargs):
            if not package_config.is_file():
                raise ValueError('Input parser requires resolved packages')
            return {name: digest(self.root/name) for name in ('source.dart', 'pubspec.lock', *inventoried_inputs)
                    if (self.root/name).is_file()}
        def command(runner, name, argv, cwd=None):
            if name in ('output-tracked-files', 'output-git-ignore', 'checkout-status', 'checkout-commit', 'checkout-commit-after-build',
                        'checkout-tree', 'checkout-tree-after-build'):
                return b.capture(argv, self.root)
            if name.startswith('source-') and 'ls-files' in argv:
                return b.capture(argv, self.root, b.controlled_environment())
            if name == 'list-pub-workspace':
                self.assertEqual(argv[1:], ['pub', 'workspace', 'list', '--json'])
                return json.dumps({'packages': [{'path': str(self.root/member)} for member in ('', *WORKSPACE_MEMBERS)]})
            if name == 'locked-resolution':
                self.assertEqual(argv[1:], ['--no-version-check', 'pub', 'get', '--enforce-lockfile'])
                self.assertFalse(package_config.exists())
                package_config.write_text('{}')
                if after_resolution is not None:
                    after_resolution()
            if name == 'configure-release':
                self.assertEqual(argv[1:], ['--no-version-check', 'build', 'macos', '--release', '--no-pub', '--config-only'])
            if name == 'app-asset-plan':
                self.assertEqual(argv[-3:], [self.root/'tool/release_materials_inputs.dart', self.root, '--asset-plan'])
                return json.dumps({'shaders': shader_plan, 'transformedAssets': transformed_assets})
            if mutate == name:
                (self.root/mutate_path).write_text('changed during '+name)
            if chmod_at == name:
                (self.root/'source.dart').chmod(0o755)
            if name in ('cli-build', 'app-build'):
                self.assertTrue((self.out/'evidence/compilation-input-hashes.json').is_file())
                if name == 'cli-build':
                    self.assertEqual(argv[0], '/usr/bin/env')
                    self.assertTrue(argv[1].startswith('TMPDIR='))
                    scratch = Path(argv[1].removeprefix('TMPDIR='))
                    self.assertEqual(scratch.parent.parent, self.out/'evidence/compiler')
                    self.assertTrue(scratch.is_dir())
                    self.assertEqual(argv[3:], ['build', 'cli', '--packages', package_config, '--target', 'lib/src/meshctl.dart',
                                                '--output', self.out/'cli', '--depfile', self.out/'evidence/compiler/cli.d'])
                else:
                    self.assertIn('MESHCHAN_BUILD_PYTHON='+sys.executable, argv)
                observed.append(name)
                if fail == name:
                    raise subprocess.CalledProcessError(9, argv)
                app, cli = b.product_paths(self.out)
                compiler_deps = (self.root/'source.dart', *compiler_sources)
                if name == 'cli-build':
                    emit_depfile(argv[-1], [cli/'bin/meshctl'], compiler_deps)
                    (self.root/b.HOOK_CACHE/'hook-output').write_text('current hook bytes')
                else:
                    depfile = self.root/b.APP_FLUTTER_CACHE/self.out.name/b.APP_KERNEL_DEPFILE
                    emit_depfile(depfile, [depfile.with_name('app.dill')], compiler_deps)
                    generated = depfile.with_name('native_assets.json')
                    generated.write_text('{}')
                    sentinel = self.root/'apps/meshchan_app/DOES_NOT_EXIST_RERUN_FOR_WILDCARD123'
                    emit_depfile(depfile.with_name(b.APP_ASSET_DEPFILE), [app/'shader 1', app/'shader 2'],
                                 (self.root/'source.dart', generated, sentinel, *asset_sources))
                if not missing:
                    target = cli/'bin/meshctl' if name == 'cli-build' else app/'Contents/MacOS/Meshchan'
                    target.parent.mkdir(parents=True);target.write_bytes(name.encode())
                if name == 'cli-build' and after_cli is not None:
                    after_cli()
            if name == 'validate-products':
                return json.dumps(product_check(self.root, *b.product_paths(self.out), product_id, {}))
            return '{}' if name == 'resolved-graph' else ''
        def product_check(root, app, cli, ident, env):
            if product_error is not None:
                raise product_error
            if not (app/'Contents/MacOS/Meshchan').exists() or not (cli/'bin/meshctl').exists():
                raise ValueError('Incomplete product')
            return {'status': 'PASS', 'signatures': {}}
        with ExitStack() as stack:
            for name, replacement in [('ROOT', self.root), ('identity', lambda *a: product_id),
                    ('toolchain', lambda *a, **kw: {'releaseFramework': {}, 'flutter': {'frameworkRevision': 'fixture'}}),
                    ('helpers', lambda *a: {}), ('inputs', compile_inputs), ('compiler_inputs', fixture_compiler_inputs),
                    ('configuration', configuration or (lambda *a: {}))]:
                stack.enter_context(patch.object(b, name, replacement))
            stack.enter_context(patch.object(b, 'external_sources', external_sources or Mock(return_value={})))
            stack.enter_context(patch.object(b, 'cli_dart_sdk', side_effect=lambda dart, overlay: dart))
            stack.enter_context(patch.object(b, 'normalize_app_engine_runpath'))
            stack.enter_context(patch.object(b, 'require_ready_flutter_launcher', side_effect=b.require_no_sdk_bootstrap))
            stack.enter_context(patch.object(b, 'release_framework_identity', release_framework or Mock(return_value={})))
            stack.enter_context(patch.object(b.Runner, 'command', command))
            return b.build(args), observed

    def test_clean_build_rejects_modified_assume_unchanged_file_before_resolution(self):
        subprocess.run(['git', 'update-index', '--assume-unchanged', 'source.dart'], cwd=self.root, check=True)
        (self.root/'source.dart').write_text('bytes hidden from git status')
        self.assertEqual(b.capture(['git', 'status', '--porcelain'], self.root), '')
        with self.assertRaisesRegex(ValueError, 'Clean source differs from recorded commit: source.dart'):
            self.build_fixture(allow_dirty=False)
        self.assertFalse((self.root/'.dart_tool/package_config.json').exists())
        self.assertEqual(b.read(self.out/'build-info.json')['buildStatus'], 'FAIL')

    def test_clean_build_compiles_verified_commit_and_rejects_ignored_inputs(self):
        (self.root/'pubspec.lock').write_text('locked')
        subprocess.run(['git', 'add', 'pubspec.lock'], cwd=self.root, check=True)
        subprocess.run(['git', 'commit', '-qm', 'Track fixture lock'], cwd=self.root, check=True)
        info, built = self.build_fixture(allow_dirty=False)
        self.assertEqual(built, ['cli-build', 'app-build'])
        self.assertFalse(info['engineeringDirtyMode'])
        with self.assertRaisesRegex(ValueError, 'Clean compilation inputs differ.*ignored.dart'):
            b.require_committed_compilation({}, {'ignored.dart': 'hash'})

    def test_phase_order_and_immutable_before_map(self):
        (self.root/'pubspec.lock').write_text('lock')
        info, observed = self.build_fixture()
        self.assertEqual(observed, ['cli-build', 'app-build'])
        self.assertEqual(info['buildStatus'], 'PASS')
        self.assertEqual(info['materials']['status'], 'NOT_RUN')
        before = b.read(self.out/'evidence/compilation-input-hashes.json')
        self.assertEqual(before, b.read(self.out/'evidence/inputs-after-cli.json'))
        self.assertEqual(before, b.read(self.out/'evidence/inputs-after-app.json'))

    def test_clean_build_checks_executable_modes_again_before_success(self):
        (self.root/'pubspec.lock').write_text('locked')
        subprocess.run(['git', 'add', 'pubspec.lock'], cwd=self.root, check=True)
        subprocess.run(['git', 'commit', '-qm', 'Track fixture lock'], cwd=self.root, check=True)
        before = digest(self.root/'source.dart')
        with self.assertRaisesRegex(ValueError, 'Clean source mode differs from recorded commit: source.dart'):
            self.build_fixture(allow_dirty=False, chmod_at='app-build')
        self.assertEqual(digest(self.root/'source.dart'), before)
        self.assertEqual(b.read(self.out/'evidence/build-receipt.json')['status'], 'FAIL')
        self.assertEqual(b.read(self.out/'build-info.json')['buildStatus'], 'FAIL')

    def test_engineering_build_rejects_mode_drift_from_the_prebuild_snapshot(self):
        with self.assertRaisesRegex(ValueError, 'source metadata after build'):
            self.build_fixture(chmod_at='app-build')
        prebuild = b.read(self.out/'evidence/prebuild-identities.json')
        self.assertFalse(prebuild['sourceMetadata']['source.dart']['executable'])
        self.assertEqual(prebuild['source']['source.dart'], digest(self.root/'source.dart'))
        self.assertEqual(b.read(self.out/'evidence/build-receipt.json')['status'], 'FAIL')

    def test_engineering_build_rechecks_source_bytes_after_product_validation(self):
        original = self.root/'guide.md'
        original.write_text('original guide')
        mode = original.stat().st_mode
        with self.assertRaisesRegex(ValueError, 'Identity drift during repository source before publication'):
            self.build_fixture(mutate='validate-products', mutate_path=original.name)
        self.assertEqual(original.stat().st_mode, mode)
        self.assertEqual(b.read(self.out/'build-info.json')['buildStatus'], 'FAIL')
        self.assertEqual(b.read(self.out/'evidence/build-receipt.json')['status'], 'FAIL')

    def test_engineering_build_rechecks_ignored_inputs_after_product_validation(self):
        name = 'apps/meshctl/lib/local.dart'
        ignore = self.root/'.gitignore'
        ignore.write_text(ignore.read_text()+'/'+name+'\n')
        imported = self.root/name
        imported.parent.mkdir(parents=True)
        imported.write_text('const local = 1;')
        with self.assertRaisesRegex(ValueError, 'Identity drift during compilation inputs before publication'):
            self.build_fixture(mutate='validate-products', mutate_path=name, inventoried_inputs=(name,),
                               compiler_sources=(imported,))
        self.assertEqual(b.read(self.out/'evidence/build-receipt.json')['status'], 'FAIL')

    def test_build_does_not_publish_products_changed_during_validation(self):
        app, _ = b.product_paths(self.out)
        payload = app/'Contents/MacOS/Meshchan'
        with self.assertRaisesRegex(ValueError, 'Identity drift during products during validation'):
            self.build_fixture(mutate='validate-products', mutate_path=payload.relative_to(self.root).as_posix())
        self.assertEqual(b.read(self.out/'evidence/build-receipt.json')['status'], 'FAIL')
        self.assertEqual(b.read(self.out/'build-info.json')['buildStatus'], 'FAIL')

    def test_build_does_not_publish_hook_cache_changed_during_validation(self):
        (self.root/'pubspec.lock').write_text('locked fixture')
        payload = self.out/b.NATIVE_HOOK_SNAPSHOT/'hook-output'
        with self.assertRaisesRegex(ValueError, 'Saved native hook cache differs'):
            self.build_fixture(mutate='validate-products', mutate_path=payload.relative_to(self.root).as_posix())
        self.assertEqual(b.read(self.out/'evidence/build-receipt.json')['status'], 'FAIL')
        self.assertEqual(b.read(self.out/'build-info.json')['buildStatus'], 'FAIL')

    def test_build_rechecks_generated_configuration_after_product_validation(self):
        configuration = {'.dart_tool/package_graph.json': 'prebuild'}
        probe = Mock(side_effect=[configuration]*3 + [{'.dart_tool/package_graph.json': 'changed'}])
        with self.assertRaisesRegex(ValueError, 'generated configuration before publication'):
            self.build_fixture(configuration=probe)
        self.assertEqual(b.read(self.out/'evidence/build-receipt.json')['status'], 'FAIL')

    def test_clean_build_rejects_untracked_source_added_during_product_validation(self):
        (self.root/'pubspec.lock').write_text('locked')
        subprocess.run(['git', 'add', 'pubspec.lock'], cwd=self.root, check=True)
        subprocess.run(['git', 'commit', '-qm', 'Track fixture lock'], cwd=self.root, check=True)
        with self.assertRaisesRegex(ValueError, 'repository source before publication'):
            self.build_fixture(allow_dirty=False, mutate='validate-products', mutate_path='late-untracked.txt')
        self.assertEqual(b.read(self.out/'evidence/build-receipt.json')['status'], 'FAIL')

    def test_clean_build_rejects_ignored_dart_file_reported_by_compiler(self):
        imported = self.root/'build/local values.dart'
        imported.parent.mkdir()
        imported.write_text('const value = 1;')
        with self.assertRaisesRegex(ValueError, 'Dart compiler input.*prebuild source snapshot: build/local values.dart'):
            self.build_fixture(allow_dirty=False, compiler_sources=(imported,))
        self.assertTrue((self.out/'evidence/compiler/cli.d').is_file())
        self.assertFalse(b.product_paths(self.out)[0].exists())
        self.assertEqual(b.read(self.out/'evidence/build-receipt.json')['status'], 'FAIL')

    def test_dirty_build_accepts_ignored_dart_bound_by_compilation_inventory(self):
        name = 'apps/meshctl/lib/local.dart'
        ignore = self.root/'.gitignore'
        ignore.write_text(ignore.read_text()+'/'+name+'\n')
        imported = self.root/name
        imported.parent.mkdir(parents=True)
        imported.write_text('const local = 1;')
        self.assertNotIn(name, b.repository_source_hashes(self.root, []))
        (self.root/'pubspec.lock').write_text('locked fixture')
        info, _ = self.build_fixture(compiler_sources=(imported,), inventoried_inputs=(name,))
        self.assertEqual(info['buildStatus'], 'PASS')
        evidence = self.out/'evidence'
        self.assertNotIn(name, b.read(evidence/'prebuild-identities.json')['source'])
        self.assertEqual(b.read(evidence/'compilation-input-hashes.json')[name], digest(imported))
        phases = b.read(evidence/'compiler-inputs.json')['firstParty']
        self.assertEqual({phase: files[name] for phase, files in phases.items()},
                         {'cli': digest(imported), 'app': digest(imported)})

    def test_compiler_report_records_hosted_dependencies_by_package_path_and_hash(self):
        local_cache = Path(self.enterContext(tempfile.TemporaryDirectory(prefix='fixture Pub package '))).resolve()
        package, alias = local_cache/'package', local_cache/'cache alias'
        name = 'lib/uses spaces.dart'
        source = package/name
        source.parent.mkdir(parents=True)
        source.write_text('const value = 1;')
        alias.symlink_to(package, target_is_directory=True)
        expected = {name: digest(source)}
        notice = {'path': 'NOTICES', 'sha256': b.sha(b'hosted notice')}
        snapshot = Mock(return_value={'fixture_package': {'path': str(package), 'configuredPath': str(alias), 'files': {
            name: {'sha256': expected[name]}}, 'hostedNotice': notice}})
        (self.root/'pubspec.lock').write_text('locked fixture')
        info, built = self.build_fixture(external_sources=snapshot, compiler_sources=(alias/name,))
        self.assertEqual(built, ['cli-build', 'app-build'])
        self.assertEqual(info['buildStatus'], 'PASS')
        report = self.out/'evidence/compiler-inputs.json'
        self.assertEqual(b.read(report)['hosted'], {
            'cli': {'fixture_package': expected}, 'app': {'fixture_package': expected}})
        self.assertEqual(b.read(report)['hostedNotices'], {'fixture_package': notice})
        self.assertEqual(b.read(self.out/'evidence/build-receipt.json')['compilerInputsSha256'], digest(report))
        self.assertNotIn(str(package), report.read_text())

    def test_app_report_binds_hosted_asset_and_shader_inputs_selected_by_asset_depfile(self):
        directory = Path(self.enterContext(tempfile.TemporaryDirectory(prefix='fixture Pub package '))).resolve()
        package = directory/'package'
        shader = package/'lib/shaders/paint.effect'
        header = shader.parent/'flutter/runtime_effect.glsl'
        header.parent.mkdir(parents=True)
        shader.write_text('#include <flutter/runtime_effect.glsl>\n')
        header.write_text('cache-only header')
        image = package/'assets/cache-only.png'
        image.parent.mkdir()
        image.write_bytes(b'fixture image')
        local_asset = self.root/'apps/meshchan_app/deferred/credits.txt'
        local_asset.parent.mkdir(parents=True)
        local_asset.write_bytes(b'local asset')
        notice = directory/'dev-package/LICENSE'
        notice.parent.mkdir()
        notice.write_bytes(b'hosted developer notice')
        sdk_header = self.root/'sdk'/b.SHADER_INCLUDE_DIR/'flutter/runtime_effect.glsl'
        sdk_header.parent.mkdir(parents=True)
        sdk_header.write_text('original SDK header')
        (self.root/'pubspec.lock').write_text('locked fixture')
        expected = {path.relative_to(package).as_posix(): digest(path) for path in (shader, header, image)}
        snapshot = Mock(return_value={'fixture_package': {'path': str(package), 'files': {
            path: {'sha256': value} for path, value in expected.items()}, 'hostedNotice': None},
            'fixture_dev_package': {'path': str(notice.parent), 'files': {'LICENSE': {'sha256': digest(notice)}},
                                    'hostedNotice': {'path': 'LICENSE', 'sha256': digest(notice)}}})
        info, _ = self.build_fixture(external_sources=snapshot, asset_sources=(shader, image, notice, local_asset),
                                     shader_plan=[{'path': str(shader), 'transformed': False},
                                                  {'path': str(shader.with_name('unused.effect')), 'transformed': True}])
        self.assertEqual(info['buildStatus'], 'PASS')
        evidence = self.out/'evidence'
        report = b.read(evidence/'compiler-inputs.json')
        self.assertEqual(report['firstParty']['app'][local_asset.relative_to(self.root).as_posix()], digest(local_asset))
        self.assertEqual(report['hosted'], {'cli': {}, 'app': {'fixture_package': expected}})
        assets = 'compiler/app-assets-0.d'
        self.assertEqual(report['depfileHashes'][assets], digest(evidence/assets))

    def test_frozen_app_rejects_ignored_asset_reported_only_in_asset_depfile(self):
        relative = 'apps/meshchan_app/deferred/local.txt'
        ignore = self.root/'.gitignore'
        ignore.write_text(ignore.read_text()+'/'+relative+'\n')
        subprocess.run(['git', 'add', '.gitignore'], cwd=self.root, check=True)
        subprocess.run(['git', 'commit', '-qm', 'Ignore synthetic asset'], cwd=self.root, check=True)
        asset = self.root/relative
        asset.parent.mkdir(parents=True)
        asset.write_text('Bundled by a deferred component')
        with self.assertRaisesRegex(ValueError, 'Flutter asset input.*prebuild source snapshot: '+relative):
            self.build_fixture(allow_dirty=False, asset_sources=(asset,))
        self.assertEqual(b.read(self.out/'evidence/build-receipt.json')['status'], 'FAIL')

    def test_app_rejects_selected_hosted_regular_asset_transformer(self):
        package = Path(self.enterContext(tempfile.TemporaryDirectory(prefix='hosted asset '))).resolve()
        image = package/'icons/2.0x/sample.png'
        image.parent.mkdir(parents=True)
        image.write_bytes(b'Bundled variant')
        declaration = package/'icons'
        with self.assertRaisesRegex(ValueError, 'cannot bind transformed Flutter asset.*sample.png'):
            # A directory declaration enumerates the base asset and its variants.
            (declaration/'sample.png').write_bytes(b'Base asset')
            self.build_fixture(asset_sources=(image,), transformed_assets=({'path': str(declaration)},))
        self.assertEqual(b.read(self.out/'evidence/build-receipt.json')['status'], 'FAIL')

    def test_app_asset_inputs_require_pinned_sdk_sources_or_explicit_artifact_evidence(self):
        directory = Path(self.enterContext(tempfile.TemporaryDirectory(prefix='sdk assets '))).resolve()
        sdk = directory/'sdk'
        pinned = sdk/'packages/flutter/lib/bundled.png'
        pinned.parent.mkdir(parents=True)
        pinned.write_bytes(b'tracked Flutter source')
        depfile = self.root/b.APP_FLUTTER_CACHE/'run'/b.APP_ASSET_DEPFILE
        sdk_notice = sdk/'bin/cache/pkg/sky_engine/LICENSE'
        notices = {'sky_engine': {'sdkNotice': {'path': str(sdk_notice)}}}
        known = {pinned, sdk_notice, sdk/b.MATERIAL_ICONS_FONT, depfile.with_name('native_assets.json')}
        accepted = b.app_asset_dependencies(self.root, known, [depfile], sdk, notices)
        self.assertEqual(accepted, {pinned})
        sdk_paths = {pinned.relative_to(sdk).as_posix()}
        self.assertEqual(b.bind_compiler_inputs(self.root, accepted, {}, {}, sdk, sdk_paths, {}, 'Flutter asset'),
                         ({}, {}))
        for extra, error in ((pinned.with_name('untracked.png'), 'outside pinned Flutter source'),
                             (directory/'unowned.png', 'no unique verified hosted source')):
            with self.subTest(extra=extra):
                extra.write_bytes(b'local file')
                actual = b.app_asset_dependencies(self.root, known | {extra}, [depfile], sdk, notices)
                with self.assertRaisesRegex(ValueError, error):
                    b.bind_compiler_inputs(self.root, actual, {}, {}, sdk, sdk_paths, {}, 'Flutter asset')

    def test_cli_build_uses_workspace_config_despite_nested_package_metadata(self):
        (self.root/'pubspec.lock').write_text('locked fixture')
        nested = self.root/'apps/meshctl/bin/.dart_tool'
        nested.mkdir(parents=True)
        shadow_files = [nested/name for name in ('package_config.json', 'package_graph.json')]
        for path in shadow_files:
            path.write_text('stale nested metadata')
        info, built = self.build_fixture()
        self.assertEqual(built, ['cli-build', 'app-build'])
        self.assertEqual(info['buildStatus'], 'PASS')
        self.assertTrue(all(path.read_text() == 'stale nested metadata' for path in shadow_files))

    def test_input_parser_uses_workspace_config_despite_nested_package_metadata(self):
        config = self.root/b.PACKAGE_CONFIG
        config.parent.mkdir()
        config.write_text('workspace package configuration')
        nested = self.root/'tool'/b.PACKAGE_CONFIG
        nested.parent.mkdir()
        nested.write_text('stale nested configuration')
        dart = self.root/'test-dart'
        command = Mock(return_value='{"members":{}}')
        with patch.object(b, 'compilation_inputs', return_value={'source.dart': 'hash'}):
            self.assertEqual(b.inputs(self.root, dart, command, 'snapshot-test'), {'source.dart': 'hash'})
        command.assert_called_once_with('snapshot-test', [
            dart, '--packages='+str(config), self.root/'tool/release_materials_inputs.dart', self.root])
        self.assertEqual(nested.read_text(), 'stale nested configuration')

    def test_generated_swift_and_package_graph_changes_block_app_compile(self):
        ephemeral = self.root/'apps/meshchan_app/macos/Flutter/ephemeral'
        packages = ephemeral/'Packages'
        for name in b.SWIFT_MANIFESTS:
            manifest = packages/name
            manifest.parent.mkdir(parents=True)
            manifest.write_text('package manifest')
        for name in b.GENERATED:
            (ephemeral/name).write_text('configuration')
        config = self.root/'.dart_tool/package_config.json'
        config.parent.mkdir()
        config.write_text('{}')
        graph = config.with_name('package_graph.json')
        graph.write_text('{"packages": []}')
        swift = packages/'.packages/FlutterFramework/Sources/FlutterFramework/FlutterFramework.swift'
        swift.parent.mkdir(parents=True)
        swift.write_text('original Swift source')
        before = b.configuration(self.root)
        self.assertTrue(all((packages/name).relative_to(self.root).as_posix() in before for name in b.SWIFT_MANIFESTS))
        (packages/'.packages/FlutterFramework/.swiftpm/xcode').mkdir(parents=True)
        self.assertEqual(b.configuration(self.root), before)
        for path, replacement in ((swift, 'different Swift source'), (graph, '{"packages": ["changed"]}')):
            with self.subTest(filename=path.name):
                original = path.read_bytes()
                path.write_text(replacement)
                after = b.configuration(self.root)
                self.assertEqual({key for key in after if before[key] != after[key]}, {path.relative_to(self.root).as_posix()})
                config.unlink()
                self.out = self.out.with_name(path.stem)
                with self.assertRaisesRegex(ValueError, 'generated configuration before App build'):
                    self.build_fixture(configuration=Mock(side_effect=[before, after]))
                app, cli = b.product_paths(self.out)
                self.assertTrue(cli.is_dir())
                self.assertFalse(app.exists())
                self.assertEqual(b.read(self.out/'build-info.json')['buildStatus'], 'FAIL')
                path.write_bytes(original)

    def test_locked_resolution_and_configuration_cannot_change_source(self):
        for phase in ('locked-resolution', 'configure-release'):
            with self.subTest(phase=phase):
                self.out = self.root/('build/phase-1e4/'+phase)
                (self.root/'.dart_tool/package_config.json').unlink(missing_ok=True)
                (self.root/'source.dart').write_text('original')
                with self.assertRaisesRegex(ValueError, 'Identity drift during'):
                    self.build_fixture(mutate=phase)
                self.assertEqual(b.read(self.out/'build-info.json')['buildStatus'], 'FAIL')
                self.assertFalse((self.out/'evidence/compilation-input-hashes.json').exists())

    def test_pub_package_metadata_aliases_fail_before_resolution(self):
        outside = Path(self.enterContext(tempfile.TemporaryDirectory(prefix='shared Pub metadata '))).resolve()
        protected = outside/'state.json'
        protected.write_text('other checkout state')
        (self.root/'.dart_tool').mkdir()
        for name in (*b.PACKAGE_METADATA, '.dart_tool/version'):
            path = self.root/name
            for mode in ('hardlink', 'symlink', 'dangling', 'directory'):
                with self.subTest(name=name, mode=mode):
                    if mode == 'hardlink':
                        os.link(protected, path)
                    elif mode == 'directory':
                        path.mkdir()
                    else:
                        path.symlink_to(protected if mode == 'symlink' else outside/'missing')
                    self.out = self.out.with_name(path.stem+'-'+mode)
                    with self.assertRaisesRegex(ValueError, 'Aliased.*Pub package metadata.*'+path.name):
                        self.build_fixture(allow_dirty=True)
                    self.assertFalse((self.root/'.dart_tool/package_config.json').exists() and
                                     path.name != 'package_config.json')
                    self.assertFalse((self.out/'evidence/inputs-before-configuration.json').exists())
                    self.assertEqual(protected.read_text(), 'other checkout state')
                    if mode == 'directory':
                        path.rmdir()
                    else:
                        path.unlink()
        self.out = self.out.with_name('alias-before-flutter-configuration')
        graph = self.root/b.PACKAGE_METADATA[1]
        with self.assertRaisesRegex(ValueError, 'Aliased.*Pub package metadata'):
            self.build_fixture(after_resolution=lambda: os.link(protected, graph))
        self.assertTrue((self.out/'evidence/inputs-before-configuration.json').exists())
        self.assertFalse((self.out/'evidence/compilation-input-hashes.json').exists())
        self.assertEqual(protected.read_text(), 'other checkout state')

    def test_workspace_pub_aliases_fail_before_locked_resolution(self):
        shared = Path(self.enterContext(tempfile.TemporaryDirectory(prefix='shared member Pub state '))).resolve()
        state = shared/'workspace_ref.json'
        state.write_text('shared workspace reference')
        for member in WORKSPACE_MEMBERS:
            metadata = self.root/member/'.dart_tool'
            metadata.mkdir(parents=True)
            (metadata/'pub').symlink_to(shared, target_is_directory=True)
            self.out = self.out.with_name('aliased-pub-'+Path(member).name)
            with self.subTest(member=member), self.assertRaisesRegex(ValueError, 'workspace Pub metadata directory'):
                self.build_fixture()
            self.assertFalse((self.root/'.dart_tool/package_config.json').exists())
            (metadata/'pub').unlink()

        metadata = self.root/'apps/meshctl/.dart_tool'
        metadata.rmdir()
        metadata.symlink_to(shared, target_is_directory=True)
        self.out = self.out.with_name('aliased-dart-tool')
        with self.assertRaisesRegex(ValueError, 'workspace Pub metadata directory'):
            self.build_fixture()
        metadata.unlink()
        pub = metadata/'pub'
        pub.mkdir(parents=True)
        target = pub/'workspace_ref.json'
        for kind, create in (('hardlink', lambda: os.link(state, target)),
                             ('symlink', lambda: target.symlink_to(shared/'missing.json'))):
            with self.subTest(kind=kind):
                create()
                self.out = self.out.with_name('aliased-workspace-ref-'+kind)
                with self.assertRaisesRegex(ValueError, 'workspace Pub metadata.*workspace_ref.json'):
                    self.build_fixture()
                self.assertFalse((self.root/'.dart_tool/package_config.json').exists())
                target.unlink()
        self.assertEqual(state.read_text(), 'shared workspace reference')
        self.assertEqual(list(shared.iterdir()), [state])

    def test_workspace_pub_preflight_checks_members_reported_by_dart(self):
        folder = self.root/'packages/nested/member with spaces'
        cache = folder/'.dart_tool/pub'
        cache.mkdir(parents=True)
        dart = self.root/'test-dart'
        command = Mock(return_value=json.dumps({'packages': [{'path': str(folder)}]}))
        b.validate_workspace_pub_metadata(self.root, dart, command)
        command.assert_called_once_with('list-pub-workspace', [dart, 'pub', 'workspace', 'list', '--json'])
        (cache/'workspace_ref.json').mkdir()
        with self.assertRaisesRegex(ValueError, 'workspace Pub metadata.*workspace_ref.json'):
            b.validate_workspace_pub_metadata(self.root, dart, command)
        command.return_value = json.dumps({'packages': [{'path': str(self.root.parent/'outside')}]})
        with self.assertRaisesRegex(ValueError, 'Pub workspace package is outside the checkout'):
            b.validate_workspace_pub_metadata(self.root, dart, command)

    def test_intermediate_pub_metadata_aliases_are_rejected_before_locked_resolution(self):
        shared = Path(self.enterContext(tempfile.TemporaryDirectory(prefix='other checkout Pub state '))).resolve()
        protected = shared/'package_config.json'
        protected.write_text('other checkout package configuration')
        for group in ('apps', 'packages'):
            with self.subTest(group=group):
                folder = self.root/group
                folder.mkdir(exist_ok=True)
                metadata = folder/'.dart_tool'
                metadata.symlink_to(shared, target_is_directory=True)
                self.out = self.out.with_name('aliased-intermediate-'+group)
                with self.assertRaisesRegex(ValueError, 'workspace Pub metadata directory.*'+group+r'/\.dart_tool'):
                    self.build_fixture()
                self.assertFalse((self.root/b.PACKAGE_CONFIG).exists())
                self.assertEqual(protected.read_text(), 'other checkout package configuration')
                metadata.unlink()

    def test_workspace_pub_checks_stray_configs_at_each_nested_level(self):
        intermediate = self.root/'packages/nested'
        member = intermediate/'member with spaces'
        member.mkdir(parents=True)
        dart = self.root/'test-dart'
        command = Mock(return_value=json.dumps({'packages': [{'path': str(member)}]}))
        for folder in (self.root/'packages', intermediate, member):
            with self.subTest(folder=folder):
                config = folder/b.PACKAGE_CONFIG
                config.parent.mkdir()
                config.write_text('local stale configuration')
                b.validate_workspace_pub_metadata(self.root, dart, command)
                config.unlink()
                config.symlink_to(self.root/'other package config')
                with self.assertRaisesRegex(ValueError, 'Aliased.*workspace Pub metadata.*package_config.json'):
                    b.validate_workspace_pub_metadata(self.root, dart, command)
                self.assertTrue(config.is_symlink())
                config.unlink()

    def test_flutter_app_cache_aliases_fail_before_pub_and_configuration(self):
        shared = Path(self.enterContext(tempfile.TemporaryDirectory(prefix='other App cache '))).resolve()
        sentinel = shared/'intermediate'
        sentinel.write_text('external cache contents')
        dart_tool = (self.root/b.APP_FLUTTER_CACHE).parent
        dart_tool.parent.mkdir(parents=True)
        with (self.root/'.gitignore').open('a') as stream:
            stream.write('apps/meshchan_app/.dart_tool\n')
        cache = self.root/b.APP_FLUTTER_CACHE
        for path in (dart_tool, cache):
            with self.subTest(path=path.name):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.symlink_to(shared, target_is_directory=True)
                self.out = self.out.with_name('cache-alias-'+path.name)
                with self.assertRaisesRegex(ValueError, 'Aliased.*Flutter App build cache directory'):
                    self.build_fixture()
                self.assertFalse((self.root/'.dart_tool/package_config.json').exists())
                self.assertEqual(list(shared.iterdir()), [sentinel])
                path.unlink()
        self.out = self.out.with_name('cache-alias-after-pub')
        with self.assertRaisesRegex(ValueError, 'Aliased.*Flutter App build cache directory'):
            self.build_fixture(after_resolution=lambda: cache.symlink_to(shared, target_is_directory=True))
        self.assertFalse((self.out/'evidence/compilation-input-hashes.json').exists())
        self.assertEqual(sentinel.read_text(), 'external cache contents')

    def test_native_hook_cache_is_checked_before_each_compiler(self):
        cache = self.root/b.HOOK_CACHE
        external = Path(self.enterContext(tempfile.TemporaryDirectory(prefix='external hook cache '))).resolve()
        sentinel = external/'expected'
        sentinel.write_text('external hook inputs')
        cache.parent.mkdir()
        cache.symlink_to(external, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'Aliased.*native hook cache directory'):
            self.build_fixture()
        self.assertFalse(b.product_paths(self.out)[1].exists())
        cache.unlink()
        cache.mkdir()
        (self.root/'.dart_tool/package_config.json').unlink()
        self.out = self.out.with_name('between-compilers')
        with self.assertRaisesRegex(ValueError, 'Aliased.*native hook cache output'):
            self.build_fixture(after_cli=lambda: (cache/'escape').symlink_to(external, target_is_directory=True))
        app, cli = b.product_paths(self.out)
        self.assertTrue((cli/'bin/meshctl').is_file())
        self.assertFalse(app.exists())
        self.assertEqual(sentinel.read_text(), 'external hook inputs')
        self.assertEqual(list(external.iterdir()), [sentinel])

    def test_release_build_isolates_old_hook_cache_and_binds_new_outputs(self):
        cache = self.root/b.HOOK_CACHE
        cache.mkdir(parents=True)
        stale = cache/'previous-toolchain-output'
        stale.write_text('old compiler and SDK')
        (self.root/'pubspec.lock').write_text('locked fixture')
        info, _ = self.build_fixture(after_cli=lambda: self.assertFalse(stale.exists()))
        self.assertEqual(info['buildStatus'], 'PASS')
        self.assertEqual(stale.read_text(), 'old compiler and SDK')
        self.assertEqual(list(cache.iterdir()), [stale])
        snapshot = self.out/b.NATIVE_HOOK_SNAPSHOT
        self.assertEqual((snapshot/'hook-output').read_text(), 'current hook bytes')
        receipt_path = self.out/'evidence/build-receipt.json'
        receipt = b.read(receipt_path)
        self.assertEqual(b.verify_native_hook_cache(receipt_path, receipt), snapshot)
        (snapshot/'hook-output').write_text('changed hook bytes')
        with self.assertRaisesRegex(ValueError, 'Saved native hook cache differs'):
            b.verify_native_hook_cache(receipt_path, receipt)

    def test_swiftpm_cache_aliases_stop_configuration(self):
        outside = Path(self.enterContext(tempfile.TemporaryDirectory(prefix='shared SwiftPM state '))).resolve()
        sentinel = outside/'workspace-state.json'
        sentinel.write_text('external state')
        app = self.root/'apps/meshchan_app'
        settings = outside/'.config/flutter/settings'
        with patch.dict(os.environ, {'HOME': str(outside)}):
            app.mkdir(parents=True)
            (app/'build').symlink_to(outside, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'Aliased.*Flutter SwiftPM cache'):
                self.build_fixture()
            self.assertFalse((self.root/'.dart_tool/package_config.json').exists())
            (app/'build').unlink()
            for build_dir, alias_relative in (
                (None, 'build'), (None, 'build/macos'), (None, 'build/macos/SourcePackages'),
                ('build/with spaces', 'build/with spaces/macos/SourcePackages/checkouts'),
            ):
                with self.subTest(alias=alias_relative):
                    if build_dir is not None:
                        settings.parent.mkdir(parents=True)
                        b.write(settings, {'build-dir': build_dir})
                    alias = app/alias_relative
                    alias.parent.mkdir(parents=True, exist_ok=True)
                    self.out = self.out.with_name(alias.name)
                    def setup_alias():
                        alias.symlink_to(outside, target_is_directory=True)
                    with self.assertRaisesRegex(ValueError, 'Aliased.*Flutter SwiftPM cache'):
                        self.build_fixture(after_resolution=setup_alias, mutate='configure-release')
                    self.assertTrue((self.out/'evidence/inputs-before-configuration.json').is_file())
                    self.assertFalse((self.out/'evidence/compilation-input-hashes.json').exists())
                    self.assertEqual((self.root/'source.dart').read_text(), 'source')
                    self.assertEqual(sentinel.read_text(), 'external state')
                    alias.unlink()
                    (self.root/'.dart_tool/package_config.json').unlink()
            legacy = outside/'.flutter_settings'
            b.write(legacy, {'build-dir': '../elsewhere'})
            with self.assertRaisesRegex(ValueError, 'Flutter build-dir must stay within'):
                b.validate_swift_package_cache(self.root, b.controlled_environment())
            legacy.unlink()
            b.validate_swift_package_cache(self.root, b.controlled_environment())

    def test_external_inputs_changed_by_cli_stop_app_compilation(self):
        with tempfile.TemporaryDirectory() as directory:
            hosted, notice = (Path(directory)/name for name in ('package.dart', 'LICENSE'))
            for source in (hosted, notice):
                source.write_text('recorded bytes')
            def snapshot(root, flutter, command=None):
                return {'hosted': digest(hosted), 'sdkNotice': digest(notice)}
            for source in (hosted, notice):
                with self.subTest(source=source.name):
                    self.out = self.out.with_name(source.name)
                    with self.assertRaisesRegex(ValueError, 'drift during external package sources before App build'):
                        self.build_fixture(external_sources=snapshot, after_cli=lambda: source.write_text('new bytes'))
                    app, cli = b.product_paths(self.out)
                    self.assertTrue((cli/'bin/meshctl').is_file())
                    self.assertFalse(app.exists())
                    self.assertEqual(b.read(self.out/'evidence/build-receipt.json')['status'], 'FAIL')
                    source.write_text('recorded bytes')
                    (self.root/'.dart_tool/package_config.json').unlink()

    def test_generated_flutter_paths_reject_aliases_before_flutter_can_write(self):
        with (self.root/'.gitignore').open('a') as ignore:
            ignore.write('apps/meshchan_app/macos/Flutter/ephemeral/\n')
        ephemeral = self.root/b.MACOS_EPHEMERAL
        ephemeral.mkdir(parents=True)
        script = ephemeral/'flutter_export_environment.sh'
        outside = self.enterContext(tempfile.TemporaryDirectory(prefix='owned outside fixture '))
        protected = Path(outside)/'protected-flutter-output'
        protected.write_text('original')
        protected.chmod(0o600)
        dangling = protected.with_name('missing-flutter-output')
        for kind, link in (('symlink', lambda: script.symlink_to(protected)),
                           ('hardlink', lambda: os.link(protected, script)),
                           ('dangling', lambda: script.symlink_to(dangling))):
            with self.subTest(alias=kind):
                link()
                self.out = self.out.with_name(kind)
                with self.assertRaisesRegex(ValueError, 'Aliased.*Flutter configuration output'):
                    self.build_fixture()
                self.assertFalse((self.root/'.dart_tool/package_config.json').exists())
                self.assertEqual(b.read(self.out/'build-info.json')['buildStatus'], 'FAIL')
                script.unlink()
        ephemeral.rmdir()
        external = protected.with_name('external-ephemeral')
        external.mkdir()
        ephemeral.symlink_to(external, target_is_directory=True)
        self.out = self.out.with_name('aliased-directory')
        with self.assertRaisesRegex(ValueError, 'Aliased.*Flutter configuration directory'):
            self.build_fixture()
        self.assertEqual(list(external.iterdir()), [])
        ephemeral.unlink()
        ephemeral.mkdir()

        self.out = self.out.with_name('added-after-resolution')
        with self.assertRaisesRegex(ValueError, 'Aliased.*Flutter configuration output'):
            self.build_fixture(after_resolution=lambda: script.symlink_to(protected))
        self.assertTrue((self.out/'evidence/inputs-before-configuration.json').exists())
        self.assertFalse((self.out/'evidence/compilation-input-hashes.json').exists())
        with self.assertRaisesRegex(ValueError, 'Aliased.*Flutter configuration output'):
            b.configuration(self.root)
        self.assertEqual(protected.read_text(), 'original')
        self.assertEqual(protected.stat().st_mode & 0o777, 0o600)
        self.assertFalse(dangling.exists())

    def test_plugin_registrant_aliases_fail_before_pub_and_configuration(self):
        registrant = self.root/b.MACOS_PLUGIN_REGISTRANT
        registrant.parent.mkdir(parents=True)
        outside = Path(self.enterContext(tempfile.TemporaryDirectory(prefix='external registrant '))).resolve()
        protected = outside/'existing.swift'
        protected.write_text('external Swift source')
        aliases = {
            'symlink': lambda: registrant.symlink_to(protected),
            'hardlink': lambda: os.link(protected, registrant),
            'dangling': lambda: registrant.symlink_to(outside/'missing.swift'),
        }
        for kind, alias in aliases.items():
            with self.subTest(kind=kind):
                alias()
                self.out = self.out.with_name(kind)
                with self.assertRaisesRegex(ValueError, 'Aliased or invalid Flutter plugin registrant'):
                    self.build_fixture(allow_dirty=True)
                self.assertFalse((self.root/'.dart_tool/package_config.json').exists())
                self.assertEqual(protected.read_text(), 'external Swift source')
                registrant.unlink()

        # Keep the bytes unchanged so the source hash comparison alone passes.
        registrant.write_bytes(protected.read_bytes())
        def replace_with_hardlink():
            registrant.unlink()
            os.link(protected, registrant)
        self.out = self.out.with_name('changed-after-pub')
        with self.assertRaisesRegex(ValueError, 'Aliased or invalid Flutter plugin registrant'):
            self.build_fixture(allow_dirty=True, after_resolution=replace_with_hardlink)
        self.assertTrue((self.out/'evidence/inputs-before-configuration.json').exists())
        self.assertFalse((self.out/'evidence/compilation-input-hashes.json').exists())
        self.assertEqual(protected.read_text(), 'external Swift source')
        self.assertFalse((outside/'missing.swift').exists())

    def test_input_change_stops_before_next_product_and_never_passes(self):
        for phase in ('cli-build', 'app-build'):
            with self.subTest(phase=phase):
                self.out = self.root/('build/phase-1e4/'+phase)
                (self.root/'.dart_tool/package_config.json').unlink(missing_ok=True)
                (self.root/'source.dart').write_text('original')
                original = digest(self.root/'source.dart')
                with self.assertRaisesRegex(ValueError, 'drift'):
                    self.build_fixture(mutate=phase)
                self.assertEqual(b.read(self.out/'evidence/compilation-input-hashes.json')['source.dart'], original)
                self.assertEqual(b.read(self.out/'build-info.json')['buildStatus'], 'FAIL')
                self.assertEqual(b.read(self.out/'evidence/build-receipt.json')['status'], 'FAIL')
                self.assertFalse((self.out/'evidence/candidate-checksums.txt').exists())
                if phase == 'cli-build':
                    self.assertFalse(b.product_paths(self.out)[0].exists())

    def test_each_compile_failure_and_missing_product_leave_failure(self):
        for fail, missing in (('cli-build', False), ('app-build', False), (None, True)):
            self.out = self.root/('build/phase-1e4/fail-'+str(fail))
            (self.root/'.dart_tool/package_config.json').unlink(missing_ok=True)
            with self.subTest(fail=fail, missing=missing), self.assertRaises((ValueError, subprocess.CalledProcessError)):
                self.build_fixture(fail=fail, missing=missing)
            self.assertEqual(b.read(self.out/'build-info.json')['buildStatus'], 'FAIL')
            self.assertEqual(b.read(self.out/'evidence/build-receipt.json')['status'], 'FAIL')

    def test_sdk_platform_python_and_source_expectations_fail_closed(self):
        with patch.object(b.platform, 'system', return_value='Linux'), self.assertRaisesRegex(ValueError, 'macOS arm64'):
            b.toolchain(self.root, Mock())
        with patch.object(b.platform, 'system', return_value='Darwin'), patch.object(b.platform, 'machine', return_value='x86_64'), self.assertRaises(ValueError):
            b.toolchain(self.root, Mock())
        with patch.object(b, 'config_values', return_value={'MESHCHAN_PRODUCT_VERSION': '0.1.0-rc.1', 'MESHCHAN_APP_BUILD': '7'}):
            for version, build in (('0.1.0', 7), ('0.1.0-rc.1', 8)):
                with self.assertRaisesRegex(ValueError, 'expectation'):
                    b.identity(self.root, version, build)
        with patch.object(b.platform, 'system', return_value='Darwin'), patch.object(b.platform, 'machine', return_value='arm64'), patch.object(b.sys, 'version_info', StablePython((3, 14, 0))), self.assertRaisesRegex(ValueError, 'stable Python'):
            b.toolchain(self.root, Mock())

    def test_sdk_checkout_and_cached_identity_gate_launcher(self):
        head = b.capture(['git', 'rev-parse', 'HEAD'], self.root)
        prepared_pins = {'frameworkRevision': head, 'engineRevision': 'engine'}
        make_flutter_tool_cache(self.root, prepared_pins)
        def git_probe(name, argv, cwd):
            self.assertEqual(argv[0], 'git')
            return b.capture(argv, cwd)

        launch = Mock(side_effect=git_probe)
        with (patch.object(b.platform, 'system', return_value='Darwin'),
              patch.object(b.platform, 'machine', return_value='arm64'),
              patch.object(b.sys, 'version_info', StablePython((3, 15, 2))),
              patch.object(b, 'read', return_value={'frameworkRevision': 'wrong pin'}) as pins,
              patch.object(b, 'source_identity', side_effect=ValueError('SDK source identity drift'))):
            with self.assertRaisesRegex(ValueError, 'pinned framework revision'):
                b.toolchain(self.root, launch)
            pins.return_value = prepared_pins
            with self.assertRaisesRegex(ValueError, 'SDK source identity drift'):
                b.toolchain(self.root, launch)
            (self.root/'source.dart').write_text('edited SDK file')
            with self.assertRaisesRegex(ValueError, 'tracked modifications'):
                b.toolchain(self.root, launch)
            self.assertTrue(all(call.args[1][0] == 'git' for call in launch.call_args_list))

    def test_toolchain_refuses_invalid_active_flutter_settings_before_probe(self):
        flutter = self.root/'sdk'
        home = self.root/'fixture home'
        modern = home/'.config/flutter/settings'
        legacy = home/'.flutter_settings'
        modern.parent.mkdir(parents=True)
        sdk = flutter/'bin/cache/dart-sdk'
        sdk.mkdir(parents=True)
        for field in ('version', 'revision'):
            (sdk/field).write_text('fixture')
        launch = Mock()
        with (patch.object(b.platform, 'system', return_value='Darwin'),
              patch.object(b.platform, 'machine', return_value='arm64'),
              patch.object(b.sys, 'version_info', StablePython((3, 15, 2))),
              patch.object(b, 'require_sdk_checkout'), patch.object(b, 'source_identity'),
              patch.object(b, 'require_ready_flutter_launcher', return_value=[])):
            for settings in (modern, legacy):
                for malformed in (b'{ invalid', b'{"build-dir": NaN}', b'{"setting": "\xff"}'):
                    with self.subTest(path=settings, contents=malformed):
                        settings.write_bytes(malformed)
                        with self.assertRaisesRegex(ValueError, 'Invalid Flutter settings file') as failure:
                            b.toolchain(flutter, launch, root=self.root, env={'HOME': home.name})
                        self.assertIn(str(settings), str(failure.exception))
                        self.assertEqual(settings.read_bytes(), malformed)
            legacy.write_text('{"build-dir": "legacy"}')
            self.assertEqual(b.read_flutter_settings(self.root, {'HOME': str(home)}), {'build-dir': 'legacy'})
            legacy.unlink()
            modern.unlink()
            for kind in ('FIFO', 'symlink to FIFO', 'directory'):
                with self.subTest(kind=kind):
                    if kind == 'FIFO':
                        os.mkfifo(modern)
                    elif kind == 'symlink to FIFO':
                        fifo = home/'external-fifo'
                        os.mkfifo(fifo)
                        modern.symlink_to(fifo)
                    else:
                        modern.mkdir()
                    with self.assertRaisesRegex(ValueError, 'Flutter settings path is not a regular file') as failure:
                        b.toolchain(flutter, launch, root=self.root, env={'HOME': home.name})
                    self.assertIn(str(modern), str(failure.exception))
                    if kind == 'directory':
                        modern.rmdir()
                    else:
                        modern.unlink()
        launch.assert_not_called()

    def test_toolchain_rejects_special_dart_metadata_before_launch(self):
        flutter = self.root/'sdk'
        pins = {'frameworkRevision': 'framework', 'engineRevision': 'engine', 'engineContentHash': 'content'}
        make_flutter_tool_cache(flutter, pins)
        launch = Mock()
        with (patch.object(b.platform, 'system', return_value='Darwin'),
              patch.object(b.platform, 'machine', return_value='arm64'),
              patch.object(b.sys, 'version_info', StablePython((3, 15, 2))),
              patch.object(b, 'require_sdk_checkout'), patch.object(b, 'read', return_value=pins),
              patch.object(b, 'source_identity')):
            for field in ('version', 'revision'):
                with self.subTest(field=field):
                    path = flutter/'bin/cache/dart-sdk'/field
                    original = path.read_bytes()
                    path.unlink()
                    os.mkfifo(path)
                    with self.assertRaisesRegex(ValueError, 'Dart SDK metadata must be a regular file: .*'+field):
                        b.toolchain(flutter, launch)
                    path.unlink()
                    path.write_bytes(original)
        launch.assert_not_called()

    def test_sdk_rejects_ignored_bootstrap_even_when_symlink_is_dangling(self):
        bootstrap = self.root/'bin/internal/bootstrap.sh'
        bootstrap.parent.mkdir(parents=True)
        (self.root/'.git/info/exclude').write_text('bin/internal/bootstrap.sh\n')
        launch = Mock()
        for dangling in (False, True):
            with self.subTest(dangling=dangling):
                if dangling:
                    bootstrap.symlink_to('missing.sh')
                else:
                    bootstrap.write_text('#!/bin/sh\nexit 1\n')
                self.assertEqual(b.capture(['git', 'status', '--porcelain'], self.root), '')
                with self.assertRaisesRegex(ValueError, 'Unexpected unpinned Flutter SDK bootstrap'):
                    b.require_sdk_checkout(self.root, {}, launch)
                bootstrap.unlink()
        launch.assert_not_called()

    def test_observed_flutter_identity_is_checked_after_launcher(self):
        observed = {'frameworkRevision': 'pin', 'engineRevision': 'wrong engine', 'engineContentHash': 'content'}
        pins = {**observed, 'engineRevision': 'pinned engine'}
        make_flutter_tool_cache(self.root, pins)
        launch = Mock(return_value=json.dumps(observed))
        with (patch.object(b.platform, 'system', return_value='Darwin'),
              patch.object(b.platform, 'machine', return_value='arm64'),
              patch.object(b.sys, 'version_info', StablePython((3, 15, 2))),
              patch.object(b, 'read', return_value=pins),
              patch.object(b, 'source_identity'),
              patch.object(b, 'require_sdk_checkout'),
              self.assertRaisesRegex(ValueError, 'Observed Flutter identity.*engineRevision')):
            b.toolchain(self.root, launch)
        launch.assert_called_once_with('flutter-version', [self.root/'bin/flutter', '--version', '--machine'])

    def test_stale_flutter_tool_caches_fail_before_running_the_launcher(self):
        flutter = self.root/'sdk'
        pins = {'frameworkRevision': 'framework', 'engineRevision': 'engine', 'engineContentHash': 'content'}
        launch = Mock()
        stamp, snapshot, pubspec, lock = (flutter/name for name in (
            b.FLUTTER_TOOL_STAMP, b.FLUTTER_TOOL_SNAPSHOT, b.FLUTTER_TOOL_PUBSPEC, b.FLUTTER_TOOL_LOCK))
        with (patch.object(b.platform, 'system', return_value='Darwin'),
              patch.object(b.platform, 'machine', return_value='arm64'),
              patch.object(b.sys, 'version_info', StablePython((3, 15, 2))),
              patch.object(b, 'read', return_value=pins), patch.object(b, 'source_identity'),
              patch.object(b, 'require_sdk_checkout')):
            for name, invalidate in (
                ('missing stamp', stamp.unlink), ('empty stamp', lambda: stamp.write_bytes(b'')),
                ('wrong revision', lambda: stamp.write_text('previous-framework:\n')),
                ('extra arguments', lambda: stamp.write_text('framework:--other-arg\n')),
                ('missing snapshot', snapshot.unlink), ('missing lock', lock.unlink),
                ('manifest newer than lock', lambda: os.utime(pubspec, ns=(0, lock.stat().st_mtime_ns+1))),
            ):
                with self.subTest(name=name):
                    make_flutter_tool_cache(flutter, pins)
                    b.require_ready_flutter_launcher(flutter)
                    invalidate()
                    with self.assertRaisesRegex(ValueError, 'Flutter tool cache is missing or stale'):
                        b.toolchain(flutter, launch)
                    launch.assert_not_called()

    def test_flutter_launcher_refuses_version_cache_that_flutter_would_replace(self):
        flutter = self.root/'sdk'
        pins = {'frameworkRevision': 'framework', 'engineRevision': 'engine', 'engineContentHash': 'content'}
        make_flutter_tool_cache(flutter, pins)
        path = flutter/b.FLUTTER_VERSION_CACHE
        version = json.loads(path.read_text())
        launch = Mock()
        b.require_ready_flutter_launcher(flutter, pins)
        incomplete = {key: value for key, value in version.items() if key != 'devToolsVersion'}
        with (patch.object(b.platform, 'system', return_value='Darwin'),
              patch.object(b.platform, 'machine', return_value='arm64'),
              patch.object(b.sys, 'version_info', StablePython((3, 15, 2))),
              patch.object(b, 'read', return_value=pins),
              patch.object(b, 'require_sdk_checkout'), patch.object(b, 'source_identity') as sdk_identity):
            for data, error in (
                (incomplete, 'field devToolsVersion'),
                ({**version, 'flutterVersion': None}, 'field flutterVersion'),
                ({**version, 'engineBuildDate': 123}, 'field engineBuildDate'),
                ({**version, 'frameworkVersion': '0.0.0-unknown'}, 'would require regeneration'),
                ({**version, 'repositoryUrl': 'https://example.invalid/flutter.git'}, 'would require regeneration'),
                ({**version, 'channel': 'main'}, 'would require regeneration'),
                ({**version, 'channel': 'master'}, 'would require regeneration'),
            ):
                with self.subTest(error=error):
                    original = encoded(data)
                    path.write_bytes(original)
                    with self.assertRaisesRegex(ValueError, 'Flutter version cache '+error):
                        b.toolchain(flutter, launch)
                    self.assertEqual(path.read_bytes(), original)
        sdk_identity.assert_not_called()
        launch.assert_not_called()

    def test_flutter_launcher_rejects_aliased_cache_writes_before_version_probe(self):
        flutter = self.root/'sdk'
        pins = {'frameworkRevision': 'framework', 'engineRevision': 'engine', 'engineContentHash': 'content'}
        make_flutter_tool_cache(flutter, pins)
        cache = flutter/'bin/cache'
        realm = cache/'engine.realm'
        external = self.root/'external-realm'
        external.write_text(pins['engineRevision']+'\n')
        launch = Mock()
        with (patch.object(b.platform, 'system', return_value='Darwin'),
              patch.object(b.platform, 'machine', return_value='arm64'),
              patch.object(b.sys, 'version_info', StablePython((3, 15, 2))),
              patch.object(b, 'read', return_value=pins), patch.object(b, 'source_identity') as sdk_identity,
              patch.object(b, 'require_sdk_checkout')):
            for path, label in ((realm, 'realm stamp'), (cache/'lockfile', 'cache lock'),
                                (cache/'engine.stamp', 'engine stamp'),
                                (flutter/'version', 'legacy version file'),
                                (flutter/b.FLUTTER_VERSION_CACHE, 'version cache'),
                                (flutter/ENGINE_STAMP, 'artifact stamp engine_stamp'),
                                (cache/'macos-sdk.stamp', 'artifact stamp macos-sdk'),
                                (cache/'flutter_sdk.stamp', 'artifact stamp flutter_sdk')):
                original = path.read_bytes() if path.is_file() else None
                if original is not None:
                    path.unlink()
                for kind, alias in (
                    ('symlink', lambda: path.symlink_to(external)),
                    ('hardlink', lambda: os.link(external, path)),
                    ('dangling', lambda: path.symlink_to(external.with_name('missing'))),
                    ('symlink-to-directory', lambda: path.symlink_to(external.parent, target_is_directory=True)),
                    ('directory', path.mkdir),
                ):
                    with self.subTest(path=path.name, kind=kind):
                        alias()
                        with self.assertRaisesRegex(ValueError, 'Aliased or invalid Flutter SDK '+label):
                            b.toolchain(flutter, launch)
                        if kind == 'directory':
                            path.rmdir()
                        else:
                            path.unlink()
                if original is not None:
                    path.write_bytes(original)
            b.require_ready_flutter_launcher(flutter)
            realm.write_bytes(b'\n')
            (cache/'lockfile').touch()
            b.require_ready_flutter_launcher(flutter)
            relocated_cache = self.root/'external-cache'
            cache.rename(relocated_cache)
            cache.symlink_to(relocated_cache, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'Aliased or invalid Flutter SDK cache directory'):
                b.toolchain(flutter, launch)
        launch.assert_not_called()
        sdk_identity.assert_not_called()
        self.assertEqual(external.read_text(), pins['engineRevision']+'\n')
        self.assertFalse(external.with_name('missing').exists())
        self.assertEqual((relocated_cache/'engine.realm').read_bytes(), b'\n')

    def test_flutter_launcher_rejects_missing_or_stale_artifact_stamps(self):
        flutter = self.root/'sdk'
        pins = {'frameworkRevision': 'framework', 'engineRevision': 'engine', 'engineContentHash': 'content'}
        make_flutter_tool_cache(flutter, pins)
        launch = Mock()
        with (patch.object(b.platform, 'system', return_value='Darwin'),
              patch.object(b.platform, 'machine', return_value='arm64'),
              patch.object(b.sys, 'version_info', StablePython((3, 15, 2))),
              patch.object(b, 'read', return_value=pins), patch.object(b, 'source_identity'),
              patch.object(b, 'require_sdk_checkout')):
            b.require_ready_flutter_launcher(flutter, pins)
            for name in ('engine_stamp', 'macos-sdk', 'flutter_sdk', 'material_fonts'):
                stamp = flutter/'bin/cache'/(name+'.stamp')
                original = stamp.read_bytes()
                stamp.unlink()
                for contents in (None, '', 'obsolete\n'):
                    with self.subTest(name=name, contents=contents):
                        if contents is not None:
                            stamp.write_text(contents)
                        with self.assertRaisesRegex(ValueError, f'Flutter artifact stamp {name} is missing or stale'):
                            b.toolchain(flutter, launch)
                stamp.write_bytes(original)
        launch.assert_not_called()

    def test_flutter_launcher_requires_artifact_directories_even_with_current_stamps(self):
        flutter = self.root/'sdk'
        pins = b.read(b.SPEC)
        make_flutter_tool_cache(flutter, pins)
        cache = flutter/'bin/cache'
        for relative in ('artifacts/engine/darwin-x64-profile', 'pkg/flutter_gpu', 'artifacts/material_fonts'):
            with self.subTest(relative=relative):
                directory = cache/relative
                directory.rmdir()
                with self.assertRaisesRegex(ValueError, 'Flutter artifact cache directory is missing'):
                    b.require_ready_flutter_launcher(flutter, pins)
                directory.mkdir()
        (cache/'artifacts/gradle_wrapper/gradlew').unlink()
        with self.assertRaisesRegex(ValueError, 'Flutter artifact cache file is missing: .*gradlew'):
            b.require_ready_flutter_launcher(flutter, pins)

    def test_flutter_tool_dependency_preflight_rejects_partial_cache_before_launch(self):
        flutter = self.root/'sdk'
        pins = b.read(b.SPEC)
        make_flutter_tool_cache(flutter, pins)
        config = flutter/b.FLUTTER_TOOL_PACKAGE_CONFIG
        hosted = flutter/'fixture pub cache/hosted_package/pubspec.yaml'
        launch = Mock()
        cache = b.require_ready_flutter_launcher(flutter, pins)
        self.assertIn(config, cache)
        self.assertIn(hosted, cache)
        self.assertIn(flutter/b.FLUTTER_TOOL_PUBSPEC, cache)
        original = config.read_bytes()
        with (patch.object(b.platform, 'system', return_value='Darwin'),
              patch.object(b.platform, 'machine', return_value='arm64'),
              patch.object(b.sys, 'version_info', StablePython((3, 15, 2))),
              patch.object(b, 'source_identity'), patch.object(b, 'require_sdk_checkout')):
            config.unlink()
            with self.assertRaisesRegex(ValueError, 'Flutter tool package config is missing'):
                b.toolchain(flutter, launch)
            b.write(config, {'configVersion': 2, 'packages': []})
            with self.assertRaisesRegex(ValueError, 'Invalid Flutter tool package config'):
                b.toolchain(flutter, launch)
            for constant in (b'NaN', b'Infinity', b'-Infinity'):
                with self.subTest(constant=constant):
                    malformed = original[:-1]+b', "extra": '+constant+b'}'
                    config.write_bytes(malformed)
                    with self.assertRaisesRegex(ValueError, 'Invalid Flutter tool package config'):
                        b.toolchain(flutter, launch)
                    self.assertEqual(config.read_bytes(), malformed)
            config.write_bytes(original)
            hosted.unlink()
            with self.assertRaisesRegex(ValueError, 'Missing Flutter tool dependency manifest for hosted_package'):
                b.toolchain(flutter, launch)
            # A FIFO is not a readable dependency manifest.
            os.mkfifo(hosted)
            with self.assertRaisesRegex(ValueError, 'Missing Flutter tool dependency manifest for hosted_package'):
                b.toolchain(flutter, launch)
        launch.assert_not_called()

    def test_toolchain_rejects_cache_bytes_replaced_during_version_probe(self):
        flutter = self.root/'sdk'
        pins = {'frameworkRevision': 'framework', 'engineRevision': 'engine', 'engineContentHash': 'content'}
        dart_version = flutter/'bin/cache/dart-sdk/version'
        dart_version.parent.mkdir(parents=True)
        dart_version.write_text('3.14.0\n')

        def launch(name, argv):
            path.write_bytes(replacement)
            return json.dumps({**pins, 'dartSdkVersion': '3.14.0'})

        with (patch.object(b.platform, 'system', return_value='Darwin'),
              patch.object(b.platform, 'machine', return_value='arm64'),
              patch.object(b.sys, 'version_info', StablePython((3, 15, 2))),
              patch.object(b, 'read', return_value=pins), patch.object(b, 'source_identity'),
              patch.object(b, 'require_sdk_checkout')):
            for name, replacement in ((b.FLUTTER_TOOL_SNAPSHOT, b'new snapshot'),
                                      (b.FLUTTER_VERSION_CACHE, None),
                                      (ENGINE_STAMP, b'engine'),
                                      ('bin/cache/macos-sdk.stamp', b'engine'),
                                      ('fixture pub cache/hosted_package/pubspec.yaml', b'changed manifest')):
                with self.subTest(name=name):
                    make_flutter_tool_cache(flutter, pins)
                    path = flutter/name
                    if replacement is None:
                        replacement = path.read_bytes()+b'\n'
                    with self.assertRaisesRegex(ValueError, 'Identity drift during Flutter launcher version probe'):
                        b.toolchain(flutter, launch)

    def test_sdk_preflight_rejects_hidden_changes_to_tracked_build_scripts(self):
        name = 'packages/flutter_tools/bin/macos_assemble.sh'
        script = self.root/name
        script.parent.mkdir(parents=True)
        script.write_text('#!/bin/sh\nexit 0\n')
        script.chmod(0o755)
        (script.parent/'alias').symlink_to('./macos_assemble.sh')
        (self.root/'.gitattributes').write_text('*.bat text eol=crlf\n')
        windows = script.parent/'fixture.bat'
        windows.write_bytes(b'@echo off\r\nexit /b 0\r\n')
        subprocess.run(['git', 'add', '.gitattributes', 'packages'], cwd=self.root, check=True)
        subprocess.run(['git', 'commit', '-qm', 'Track SDK script and link'], cwd=self.root, check=True)
        pins = {'frameworkRevision': b.capture(['git', 'rev-parse', 'HEAD'], self.root)}
        probe = Mock(side_effect=lambda name, argv, cwd: b.capture(argv, cwd))
        b.require_sdk_checkout(self.root, pins, probe)
        subprocess.run(['git', 'update-index', '--assume-unchanged', name], cwd=self.root, check=True)
        script.write_text('#!/bin/sh\nexit 1\n')
        self.assertEqual(b.capture(['git', 'status', '--porcelain', '--untracked-files=no'], self.root), '')
        with (patch.object(b.platform, 'system', return_value='Darwin'),
              patch.object(b.platform, 'machine', return_value='arm64'),
              patch.object(b.sys, 'version_info', StablePython((3, 15, 2))),
              patch.object(b, 'read', return_value=pins),
              self.assertRaisesRegex(ValueError, 'SDK tracked source.*macos_assemble.sh')):
            b.toolchain(self.root, probe)
        self.assertTrue(all(call.args[1][0] == 'git' for call in probe.call_args_list))

    def test_toolchain_hashes_release_cache_inputs(self):
        flutter = self.root/'sdk'
        dart = flutter/'bin/cache/dart-sdk'
        dart.mkdir(parents=True)
        (dart/'version').write_text('3.14.0\n')
        (dart/'revision').write_text('pinned dart revision\n')
        inputs = (dart/'bin/dartvm',
                  flutter/'bin/cache/artifacts/engine/common/flutter_patched_sdk_product/platform_strong.dill',
                  dart/'lib/_internal/vm_platform_product.dill',
                  flutter/'bin/cache/artifacts/engine/darwin-x64/font-subset',
                  flutter/'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
                  flutter/'bin/cache/artifacts/engine/darwin-x64/impellerc')
        for artifact in inputs:
            artifact.parent.mkdir(parents=True, exist_ok=True)
            artifact.write_bytes(b'original SDK release input')
        framework = flutter/b.RELEASE_FRAMEWORK
        version = framework/'Versions/A'
        framework_files = ('FlutterMacOS', 'Headers/FlutterMacOS.h', 'Headers/FlutterEngine.h', 'Modules/module.modulemap')
        for name in framework_files:
            artifact = version/name
            artifact.parent.mkdir(parents=True, exist_ok=True)
            artifact.write_text('original framework input')
        current = framework/'Versions/Current'
        current.symlink_to('A')
        for name in ('FlutterMacOS', 'Headers', 'Modules'):
            (framework/name).symlink_to('Versions/Current/'+name)
        shaders = flutter/'bin/cache/artifacts/engine/darwin-x64/shader_lib'
        shader_files = ('flutter/runtime_effect.glsl', 'impeller/texture.glsl')
        for name in shader_files:
            artifact = shaders/name
            artifact.parent.mkdir(parents=True)
            artifact.write_text('original shader header')
        shader_source = flutter/'engine/src/flutter/impeller/compiler/shader_lib'
        for name in shader_files:
            source = shader_source/name
            source.parent.mkdir(parents=True)
            source.write_bytes((shaders/name).read_bytes())
        subprocess.run(['git', 'init', '-q'], cwd=flutter, check=True)
        subprocess.run(['git', 'add', shader_source], cwd=flutter, check=True)
        subprocess.run(['git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test',
                        'commit', '-qm', 'Pinned shader sources'], cwd=flutter, check=True)
        pins = {'frameworkRevision': b.capture(['git', 'rev-parse', 'HEAD'], flutter),
                'engineRevision': 'engine', 'engineContentHash': 'content'}
        observed = {**pins, 'dartSdkVersion': '3.14.0'}
        make_flutter_tool_cache(flutter, pins)
        actual_is_file = Path.is_file

        def command(name, argv, cwd=None):
            if name == 'flutter-version-shader-source-tree':
                return subprocess.check_output(argv, cwd=cwd, text=True)
            return {'flutter-version': json.dumps(observed), 'flutter-version-clang-path': '/bin/sh',
                    'flutter-version-install-name-tool': '/bin/sh'}.get(name, 'tool version')

        with (patch.object(b.platform, 'system', return_value='Darwin'),
              patch.object(b.platform, 'machine', return_value='arm64'),
              patch.object(b.sys, 'version_info', StablePython((3, 15, 2))),
              patch.object(b, 'read', return_value=pins), patch.object(b, 'source_identity'),
              patch.object(b, 'require_sdk_checkout'),
              patch.object(b, 'read_flutter_settings', return_value={}),
              patch.object(Path, 'is_file', lambda path: actual_is_file(path)
                           if path in inputs or path.is_relative_to(framework) or path.is_relative_to(shaders) else True),
              patch.object(b, 'digest', side_effect=lambda path: digest(path) if path in inputs else 'constant')):
            original = b.toolchain(flutter, command)
            for artifact in inputs:
                with self.subTest(artifact=artifact.name):
                    self.assertEqual(original['toolHashes'][str(artifact)], digest(artifact))
                    before = artifact.read_bytes()
                    artifact.write_bytes(b'replaced SDK release input')
                    changed = b.toolchain(flutter, command)
                    self.assertEqual(changed['toolHashes'][str(artifact)], digest(artifact))
                    with self.assertRaisesRegex(ValueError, 'toolchain'):
                        b.require_equal(original, changed, 'toolchain')
                    artifact.unlink()
                    with self.assertRaisesRegex(ValueError, 'lacks required Release'):
                        b.toolchain(flutter, command)
                    artifact.write_bytes(before)
            for name in framework_files:
                with self.subTest(framework_input=name):
                    artifact = version/name
                    entry = f'Versions/A/{name}'
                    self.assertEqual(original['releaseFramework']['inventory'][entry]['sha256'], digest(artifact))
                    before = artifact.read_bytes()
                    artifact.write_text('changed framework input')
                    self.assertNotEqual(original, b.toolchain(flutter, command))
                    artifact.write_bytes(before)
            for name in shader_files:
                with self.subTest(shader_input=name):
                    artifact = shaders/name
                    self.assertEqual(original['shaderIncludes']['inventory'][name]['sha256'], digest(artifact))
                    before = artifact.read_bytes()
                    artifact.write_text('changed shader header')
                    with self.assertRaisesRegex(ValueError, 'Cached Impeller shader include differs from pinned source'):
                        b.toolchain(flutter, command)
                    artifact.write_bytes(before)
            extra_header = shaders/'impeller/local-override.glsl'
            extra_header.write_text('Cache-only header')
            with self.assertRaisesRegex(ValueError, 'include paths differ from pinned source: impeller/local-override.glsl'):
                b.toolchain(flutter, command)
            extra_header.unlink()
            (shaders/shader_files[0]).unlink()
            with self.assertRaisesRegex(ValueError, 'lacks required Release runtime effect shader header'):
                b.toolchain(flutter, command)
            (shaders/shader_files[0]).write_text('original shader header')
            module = version/'Modules/module.modulemap'
            module.unlink()
            with self.assertRaisesRegex(ValueError, 'framework input: Modules/module.modulemap'):
                b.toolchain(flutter, command)
            module.write_text('original framework input')
            self.assertEqual(original, b.toolchain(flutter, command))
            current.unlink()
            current.symlink_to('./A')
            self.assertNotEqual(original, b.toolchain(flutter, command))
            backup = framework.parent.with_name('macos-backup')
            backup.mkdir()
            with self.assertRaisesRegex(ValueError, 'ambiguous Release FlutterMacOS platform directories.*macos-backup'):
                b.toolchain(flutter, command)
            backup.rmdir()
            backup.symlink_to(framework.parent, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'ambiguous Release FlutterMacOS platform directories.*macos-backup'):
                b.toolchain(flutter, command)

    def test_build_rechecks_the_selected_framework_before_app_compilation(self):
        framework = Mock(side_effect=[{}, {'path': 'changed framework'}])
        with self.assertRaisesRegex(ValueError, 'Identity drift during Release FlutterMacOS framework before App build'):
            self.build_fixture(release_framework=framework)
        app, cli = b.product_paths(self.out)
        self.assertTrue((cli/'bin/meshctl').is_file())
        self.assertFalse(app.exists())
        self.assertEqual(b.read(self.out/'evidence/build-receipt.json')['status'], 'FAIL')

    def test_xcode_probe_obeys_deadline_and_drains_owned_processes(self):
        flutter = self.root/'sdk'
        dart = flutter/'bin/cache/dart-sdk'
        dart.mkdir(parents=True)
        (dart/'version').write_text('3.14.0\n')
        (dart/'revision').write_text('pinned dart revision\n')
        pins = {'frameworkRevision': 'framework', 'engineRevision': 'engine', 'engineContentHash': 'content'}
        observed = {**pins, 'dartSdkVersion': '3.14.0'}
        make_flutter_tool_cache(flutter, pins)
        runner = self.runner(timeout=0.7)
        marker = self.root/'xcode-probe-started'
        script = 'import sys,time; from pathlib import Path; Path(sys.argv[1]).touch(); time.sleep(30)'
        def command(name, argv, cwd=None):
            if name == 'flutter-version-xcode':
                self.assertEqual(argv, ['/usr/bin/xcodebuild', '-version'])
                return runner.command(name, [sys.executable, '-c', script, marker], cwd)
            return {'flutter-version': json.dumps(observed),
                    'flutter-version-clang-path': '/bin/sh', 'flutter-version-dart': 'Dart SDK'}[name]

        with (patch.object(b.platform, 'system', return_value='Darwin'),
              patch.object(b.platform, 'machine', return_value='arm64'),
              patch.object(b.sys, 'version_info', StablePython((3, 15, 2))),
              patch.object(b, 'read', return_value=pins), patch.object(b, 'source_identity'),
              patch.object(b, 'require_sdk_checkout'), patch.object(b, 'verified_shader_includes', return_value={}),
              patch.object(b, 'release_framework_identity', return_value={}),
              patch.object(b, 'read_flutter_settings', return_value={}),
              patch.object(Path, 'is_file', return_value=True),
              b.checkout_lock(self.root), self.assertRaisesRegex(TimeoutError, 'flutter-version-xcode')):
            b.toolchain(flutter, command)
        self.assertTrue(marker.is_file())
        step, = runner.receipt['steps']
        self.assertTrue(step['processTree']['exited'])
        self.assertIn('SIGTERM', step['processTree']['signalsSent'])

    def interrupt_build_during(self, phase):
        sdk = self.root/'fake-sdk'
        flutter_probe = phase == 'flutter-version'
        launcher = sdk/('bin/flutter' if flutter_probe else 'bin/cache/dart-sdk/bin/dart')
        launcher.parent.mkdir(parents=True)
        script = '#!/bin/sh\n'
        if phase == 'snapshot-before-configuration':
            workspace = json.dumps({'packages': [{'path': str(self.root)}]})
            script += 'if [ "$1" = pub ]; then\n  printf \'%s\\n\' '+shlex.quote(workspace)+'\n  exit 0\nfi\n'
        launcher.write_text(script+'echo probe-ready\nexec /bin/sleep 30\n')
        launcher.chmod(0o755)
        make_flutter_tool_cache(sdk, b.read(b.SPEC))
        if phase == 'checkout-status':
            monitor = self.root/'.git'/'slow-monitor'
            monitor.write_text('#!/bin/sh\necho probe-ready >&2\nexec /bin/sleep 30\n')
            monitor.chmod(0o755)
            subprocess.run(['git', 'config', 'core.fsmonitor', '.git/slow-monitor'], cwd=self.root, check=True)
        if not flutter_probe:
            flutter = sdk/'bin/flutter'
            flutter_script = '#!/bin/sh\n'
            if phase == 'snapshot-before-configuration':
                flutter_script += "printf '{}\\n' > .dart_tool/package_config.json\n"
            flutter.write_text(flutter_script+'exit 0\n')
            flutter.chmod(0o755)
            (self.root/'tool/check_product_version.py').write_text('pass\n')
        wrapper = self.root/'build-wrapper.py'
        wrapper.write_text(f"""import sys
sys.path.insert(0, {str(Path(b.__file__).parent)!r})
from pathlib import Path
from contextlib import nullcontext
from unittest.mock import patch
import build_release as b
class StablePython(tuple):
    releaselevel = 'final'
b.ROOT = Path({str(self.root)!r})
phase = {phase!r}
actual_command = b.Runner.command
def command(runner, name, argv, cwd=None, **kwargs):
    if name == phase and phase.startswith('source-'):
        assert 'ls-files' in argv
        argv = [{str(launcher)!r}]
    return actual_command(runner, name, argv, cwd, **kwargs)
with (patch.object(b, 'identity', return_value={{'productVersion': '0.1.0-rc.1', 'appBuild': '7'}}),
      patch.object(b, 'helpers', return_value={{}}),
      patch.object(b.Runner, 'command', command),
      nullcontext() if {flutter_probe!r} else patch.object(b, 'toolchain', return_value={{}}),
      patch.object(b.platform, 'system', return_value='Darwin'),
      patch.object(b.platform, 'machine', return_value='arm64'),
      patch.object(b.sys, 'version_info', StablePython((3, 15, 2))),
      patch.object(b, 'require_sdk_checkout'),
      patch.object(b, 'source_identity')):
    sys.exit(b.main())
""")
        proc = subprocess.Popen([sys.executable, str(wrapper), 'build', '--allow-dirty',
                                 '--flutter', str(sdk), '--output', str(self.out)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(lambda: (proc.kill(), proc.wait()) if proc.poll() is None else None)
        stderr_probe = phase == 'checkout-status'
        log = self.out/'evidence/logs'/(phase+('.stderr.log' if stderr_probe else '.log'))
        deadline = time.monotonic()+10
        while not (log.exists() and 'probe-ready' in log.read_text()):
            if proc.poll() is not None or time.monotonic() >= deadline:
                index = self.out/'build-info.json'
                error = b.read(index).get('error') if index.is_file() else None
                self.fail(f'Build step did not start: {phase} (status={proc.returncode}, error={error})')
            time.sleep(0.03)
        with self.assertRaisesRegex(ValueError, 'lock is held'):
            with b.checkout_lock(self.root):
                self.fail('Probe must run under the checkout lock')
        proc.send_signal(signal.SIGTERM)
        self.assertEqual(proc.wait(timeout=10), 1)
        receipt = b.read(self.out/'evidence/build-receipt.json')
        self.assertEqual(receipt['status'], 'FAIL')
        self.assertEqual(b.read(self.out/'build-info.json')['buildStatus'], 'FAIL')
        step = receipt['steps'][-1]
        self.assertEqual(step['name'], phase)
        self.assertTrue(step['processTree']['exited'])
        self.assertIn('SIGTERM', step['processTree']['signalsSent'])
        self.assertEqual(step['stderrLogSha256' if stderr_probe else 'logSha256'], digest(log))
        with b.checkout_lock(self.root):
            pass

    def test_sigterm_during_flutter_probe_seals_actual_build_failure(self):
        self.interrupt_build_during('flutter-version')

    def test_sigterm_during_dart_snapshot_seals_actual_build_failure(self):
        self.interrupt_build_during('snapshot-before-configuration')

    def test_sigterm_during_pub_workspace_listing_seals_actual_build_failure(self):
        self.interrupt_build_during('list-pub-workspace')

    def test_sigterm_during_source_enumeration_seals_actual_build_failure(self):
        self.interrupt_build_during('source-before-resolution-all')

    def test_sigterm_during_git_status_seals_actual_build_failure(self):
        self.interrupt_build_during('checkout-status')

    def test_sigterm_during_finalization_seals_both_failure_records(self):
        (self.root/'pubspec.lock').write_text('locked fixture')
        for phase in ('inventory', 'pass-publication'):
            with self.subTest(phase=phase):
                out = self.out.with_name(phase)
                ready, resume = self.root/(phase+'-ready'), self.root/(phase+'-resume')
                wrapper = self.root/(phase+'.py')
                wrapper.write_text(f"""import sys
import time
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, {str(Path(b.__file__).parent)!r})
import build_release as b
from build_release_test import ReleaseTests
fixture = ReleaseTests()
fixture.root = Path({str(self.root)!r})
fixture.out = Path({str(out)!r})
phase = {phase!r}
def pause():
    Path({str(ready)!r}).touch()
    deadline = time.monotonic() + 10
    while not Path({str(resume)!r}).exists():
        if time.monotonic() > deadline:
            raise TimeoutError('Fixture did not resume')
        time.sleep(0.02)
write, inventory = b.write, b.full_inventory
app_inventory_count = 0
def controlled_write(path, value):
    if phase == 'pass-publication' and path.name == 'build-info.json' and value.get('buildStatus') == 'PASS':
        pause()
    write(path, value)
def controlled_inventory(path):
    global app_inventory_count
    if phase == 'inventory' and path == b.product_paths(fixture.out)[0]:
        app_inventory_count += 1
        if app_inventory_count == 2:
            pause()
    return inventory(path)
with (patch.object(b, 'write', controlled_write),
      patch.object(b, 'full_inventory', controlled_inventory)):
    try:
        fixture.build_fixture()
    except b.GateInterrupted:
        sys.exit(1)
""")
                (self.root/'.dart_tool/package_config.json').unlink(missing_ok=True)
                proc = subprocess.Popen([sys.executable, str(wrapper)])
                self.addCleanup(lambda p=proc: (p.kill(), p.wait()) if p.poll() is None else None)
                for _ in range(150):
                    if ready.exists():
                        break
                    if proc.poll() is not None:
                        self.fail('Build fixture exited before '+phase)
                    time.sleep(0.02)
                else:
                    self.fail('Build did not reach '+phase)
                with self.assertRaisesRegex(ValueError, 'lock is held'):
                    with b.checkout_lock(self.root):
                        self.fail('Finalization must hold the checkout lock')
                proc.send_signal(signal.SIGTERM)
                resume.touch()
                self.assertEqual(proc.wait(timeout=10), 1)
                index = b.read(out/'build-info.json')
                receipt = b.read(out/'evidence/build-receipt.json')
                self.assertEqual(index['buildStatus'], 'FAIL')
                self.assertEqual(receipt['status'], 'FAIL')
                self.assertEqual(index['interruptSignal'], signal.SIGTERM)
                self.assertEqual(receipt['interruptSignal'], signal.SIGTERM)
                with b.checkout_lock(self.root):
                    pass

    def test_sigterm_between_verification_commands_seals_the_phase_ledger(self):
        (self.out/'evidence').mkdir(parents=True)
        code = """
import signal
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import build_release as b

root, run = map(Path, sys.argv[2:])
try:
    with b.checkout_lock(root), b.verification_runner(root, run, 'check-fixture', {}):
        signal.raise_signal(signal.SIGTERM)
except b.GateInterrupted:
    sys.exit(1)
"""
        result = subprocess.run([sys.executable, '-c', code, str(Path(b.__file__).parent), self.root, self.out],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1, result.stderr)
        ledger_path, = (self.out/'evidence').glob('check-fixture-*/build-receipt.json')
        ledger = b.read(ledger_path)
        self.assertEqual(ledger['status'], 'FAIL')
        self.assertEqual(ledger['interruptSignal'], signal.SIGTERM)
        with b.checkout_lock(self.root):
            pass

    def test_material_destination_rejects_dangling_symlink(self):
        self.out.mkdir(parents=True)
        external = self.root/'unowned target'
        (self.out/'materials').symlink_to(external, target_is_directory=True)
        self.assertFalse((self.out/'materials').exists())
        with self.assertRaisesRegex(ValueError, 'new dedicated directory'):
            b.material_destination(self.out, 'materials')
        self.assertFalse(external.exists())
        self.assertEqual(b.material_destination(self.out, 'new materials'), self.out/'new materials')
        for name in ('build-info.json.tmp', 'BUILD-INFO.JSON.TMP'):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'new dedicated directory'):
                b.material_destination(self.out, name)

    def test_path_audit_rejects_build_paths_in_executable_and_nested_library(self):
        bundle = self.root/'product'
        names = ('lib/native.dylib', 'bin/program')
        for name in names:
            binary = bundle/name
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b'package:meshctl/src/meshctl.dart\0/usr/lib/libSystem.B.dylib\0')
        self.assertEqual(b.audit_macho_paths(bundle, names, self.root), sorted(names))
        for name, leak in ((names[0], b'file:///Users/example/work/build/native.c'),
                           (names[1], os.fsencode(self.root/'source.dart')),
                           (names[1], b'file:///tmp/build/meshctl.dart'),
                           (names[1], b'/var/folders/token/T/session/snapshot.aot'),
                           (names[1], b'/tmp/session/snapshot.aot')):
            binary = bundle/name
            original = binary.read_bytes()
            binary.write_bytes(original+leak)
            with self.assertRaisesRegex(ValueError, 'Local build path') as error:
                b.audit_macho_paths(bundle, names, self.root)
            self.assertIn(name, str(error.exception))
            binary.write_bytes(original)

    def test_cli_sdk_rewrites_only_the_owned_snapshot_output(self):
        sdk = self.root/'pinned sdk'
        utils = sdk/'bin/utils'
        utils.mkdir(parents=True)
        (sdk/'version').write_text('pinned version')
        for launcher in ('dart', 'dartvm', 'dartaotruntime'):
            (sdk/'bin'/launcher).write_text(launcher)
        original = utils/'gen_snapshot'
        original.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > snapshot.aot\n')
        original.chmod(0o755)
        overlay = self.root/'private compiler'
        dart = b.cli_dart_sdk(sdk/'bin/dart', overlay)
        self.assertEqual(dart.read_bytes(), (sdk/'bin/dart').read_bytes())
        self.assertEqual((overlay/'version').resolve(), sdk/'version')
        scratch = self.root/'owned scratch'
        work = scratch/'dart-created directory'
        work.mkdir(parents=True)
        kernel = work/'kernel.dill'
        kernel.write_text('source kernel')
        snapshot = work/'snapshot.aot'
        compiler = overlay/'bin/utils/gen_snapshot'
        command = [compiler, '--snapshot-kind=app-aot-macho-dylib', '--macho='+str(snapshot), kernel]
        env = {**b.controlled_environment(), 'TMPDIR': str(scratch)}
        self.assertNotEqual(subprocess.run([*command, '--macho=other'], env=env, capture_output=True).returncode, 0)
        self.assertNotEqual(subprocess.run(command, env={**env, 'TMPDIR': str(work)},
                                           capture_output=True).returncode, 0)
        self.assertFalse(snapshot.exists())
        subprocess.run(command, env=env, check=True)
        self.assertEqual(snapshot.read_text().splitlines(), [command[1], '--macho=snapshot.aot', str(kernel)])

    def test_loader_checks_actual_loads_against_matching_macho_slices(self):
        bundle = self.root/'bundle'
        bundle.mkdir()
        exe, library, alias = (bundle/name for name in ('main', 'library', 'alias'))
        for path in (exe, library):
            path.write_bytes(b'\xcf\xfa\xed\xfe')
        alias.symlink_to(library.name)

        def inspect(argv, **kwargs):
            path = argv[-1]
            if argv[0].endswith('lipo'):
                return 'arm64 x86_64' if path == exe else library_architectures
            if path == exe:
                return macho_header(2)+'cmd LC_LOAD_WEAK_DYLIB\ncmdsize 64\nname @loader_path/alias (offset 24)'
            return (macho_header(library_types[argv[2]])+
                    'cmd LC_ID_DYLIB\ncmdsize 64\nname /irrelevant/install/id (offset 24)\n'
                    'cmd LC_REEXPORT_DYLIB\ncmdsize 64\nname /usr/lib/libSystem.B.dylib (offset 24)')

        with (patch.object(b, 'capture', side_effect=inspect),
              patch.object(b, 'system_library_location', return_value='dyld shared cache')):
            library_architectures = 'arm64'
            library_types = {'arm64': b.MH_DYLIB, 'x86_64': b.MH_DYLIB}
            with self.assertRaisesRegex(ValueError, 'loader target lacks x86_64'):
                b.loader_check(bundle, exe, {})
            library_architectures = 'arm64 x86_64'
            result = b.loader_check(bundle, exe, {})
            self.assertEqual(result['main']['slices']['x86_64']['dependencies'][0]['resolved'], ['library'])
            self.assertEqual(result['library']['slices']['arm64']['dependencies'],
                             [{'path': '/usr/lib/libSystem.B.dylib', 'scope': 'OS system',
                               'loadCommand': 'LC_REEXPORT_DYLIB', 'availability': 'dyld shared cache'}])
            self.assertEqual(result['library']['slices']['arm64']['fileType'], b.MH_DYLIB)
            for file_type in (1, 2):
                library_types['x86_64'] = file_type
                with self.subTest(file_type=file_type), self.assertRaisesRegex(ValueError, 'not a Mach-O dylib for x86_64'):
                    b.loader_check(bundle, exe, {})
            library.write_text('not Mach-O')
            with self.assertRaisesRegex(ValueError, 'loader target lacks arm64'):
                b.loader_check(bundle, exe, {})

    def test_loader_rejects_paths_leaving_and_reentering_bundle(self):
        bundle = self.root/'run/cli/bundle'
        executable = bundle/'bin/meshctl'
        library = bundle/'lib/library.dylib'
        for binary in (executable, library):
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b'\xcf\xfa\xed\xfe')
        (library.parent/'root').symlink_to('..')
        rpath = '@loader_path/../lib'
        dependency = '@rpath/library.dylib'

        def inspect(argv, **kwargs):
            if argv[0].endswith('lipo'):
                return 'arm64'
            if argv[-1] == executable:
                return (macho_header(2)+f'cmd LC_RPATH\ncmdsize 64\npath {rpath} (offset 12)\n'
                        f'cmd LC_LOAD_DYLIB\ncmdsize 64\nname {dependency} (offset 24)')
            return macho_header(b.MH_DYLIB)

        with patch.object(b, 'capture', side_effect=inspect):
            result = b.loader_check(bundle, executable, {})
            self.assertEqual(result['bin/meshctl']['slices']['arm64']['dependencies'][0]['resolved'],
                             ['lib/library.dylib'])
            escaping_runpath = '../../../cli/bundle/lib'
            self.assertEqual((executable.parent/escaping_runpath/library.name).resolve(strict=True), library)
            for rpath, dependency in (
                ('@loader_path/'+escaping_runpath, '@rpath/library.dylib'),
                ('@loader_path/../lib', '@loader_path/'+escaping_runpath+'/library.dylib'),
                ('@loader_path/../lib', '@rpath/../../bundle/lib/library.dylib'),
                ('@loader_path/../lib', '@loader_path/../lib/root/../bundle/lib/library.dylib'),
            ):
                with self.subTest(rpath=rpath, dependency=dependency), self.assertRaisesRegex(ValueError, 'External product loader path'):
                    b.loader_check(bundle, executable, {})

    def test_loader_rejects_host_runpaths_before_bundled_resolution(self):
        bundle = self.root/'bundle'
        executable = bundle/'bin/main'
        library = bundle/'lib/library.dylib'
        for binary in (executable, library):
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b'\xcf\xfa\xed\xfe')
        factory = '/usr/local/lib/.'
        bundled = '@loader_path/../lib'
        dependency = '@rpath/library.dylib'

        def inspect(argv, **kwargs):
            if argv[0].endswith('lipo'):
                return 'arm64'
            if argv[-1] == executable:
                loads = ''.join(f'cmd LC_RPATH\ncmdsize 64\npath {r} (offset 12)\n' for r in rpaths)
                return macho_header(2)+loads+f'cmd LC_LOAD_DYLIB\ncmdsize 64\nname {dependency} (offset 24)'
            return macho_header(b.MH_DYLIB)

        actual_is_file = Path.is_file

        def is_file(path):
            if path == Path(factory)/library.name:
                return installed_on_host
            return actual_is_file(path)

        with (patch.object(b, 'capture', side_effect=inspect), patch.object(Path, 'is_file', is_file),
              patch.object(b, 'system_library_location', return_value=None) as system_location):
            rpaths = (factory, bundled)
            for installed_on_host in (False, True):
                with self.subTest(installed=installed_on_host), self.assertRaisesRegex(ValueError, 'Host-dependent'):
                    b.loader_check(bundle, executable, {})
            rpaths = (bundled, factory)
            result = b.loader_check(bundle, executable, {})['bin/main']['slices']['arm64']
            self.assertEqual(result['rpaths'], list(rpaths))
            self.assertEqual(result['dependencies'][0]['resolved'], ['lib/library.dylib'])
            rpaths = ('/usr/lib/swift', bundled)
            self.assertEqual(b.loader_check(bundle, executable, {})['bin/main']['slices']['arm64']
                             ['dependencies'][0]['resolved'], ['lib/library.dylib'])
            system_location.assert_called_once_with('/usr/lib/swift/library.dylib')
            system_location.return_value = 'dyld shared cache'
            with self.assertRaisesRegex(ValueError, 'Host-dependent'):
                b.loader_check(bundle, executable, {})
            rpaths = (bundled, factory)
            library.unlink()
            with self.assertRaisesRegex(ValueError, 'Host-dependent'):
                b.loader_check(bundle, executable, {})

    def test_loader_searches_the_intermediate_runpath_before_main_fallback(self):
        bundle = self.root/'bundle'
        main = bundle/'bin/main'
        outer = bundle/'chain/libOuter.dylib'
        inner = bundle/'chain/children/libInner.dylib'
        selected = bundle/'chain/priority/libValue.dylib'
        fallback = bundle/'fallback/libValue.dylib'
        for binary in (main, outer, inner, selected, fallback):
            binary.parent.mkdir(parents=True, exist_ok=True)
            binary.write_bytes(b'\xcf\xfa\xed\xfe')

        def rpath(path):
            return f'cmd LC_RPATH\ncmdsize 64\npath {path} (offset 12)\n'

        def load(name):
            return f'cmd LC_LOAD_DYLIB\ncmdsize 64\nname {name} (offset 24)\n'

        commands = {
            main: macho_header(2)+rpath('@loader_path/../fallback')+load('@loader_path/../chain/libOuter.dylib'),
            outer: macho_header(b.MH_DYLIB)+rpath('@loader_path/priority')+load('@loader_path/children/libInner.dylib'),
            inner: macho_header(b.MH_DYLIB)+rpath('@loader_path/requester')+load('@rpath/libValue.dylib')
                +load('@loader_path/../libOuter.dylib'),
        }

        def inspect(argv, **kwargs):
            if argv[0].endswith('lipo'):
                return 'arm64'
            return commands.get(argv[-1], macho_header(b.MH_DYLIB))

        with patch.object(b, 'capture', side_effect=inspect):
            result = b.loader_check(bundle, main, {})['chain/children/libInner.dylib']['slices']['arm64']
            self.assertEqual(result['rpathChain'], [
                {'path': '@loader_path/requester', 'owner': 'chain/children/libInner.dylib'},
                {'path': '@loader_path/priority', 'owner': 'chain/libOuter.dylib'},
                {'path': '@loader_path/../fallback', 'owner': 'bin/main'},
            ])
            self.assertEqual(result['dependencies'][0]['resolved'], ['chain/priority/libValue.dylib'])
            fallback.unlink()
            result = b.loader_check(bundle, main, {})['chain/children/libInner.dylib']['slices']['arm64']
            self.assertEqual(result['dependencies'][0]['resolved'], ['chain/priority/libValue.dylib'])

    def test_loader_rejects_two_targets_for_the_same_dyld_install_name(self):
        bundle = self.root/'bundle'
        exe, left, right = (bundle/name for name in ('main', 'left/libStart.dylib', 'right/libStart.dylib'))
        first, second = (p.with_name('leaf.dylib') for p in (left, right))
        for path in (exe, left, right, first, second):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'\xcf\xfa\xed\xfe')

        def load(path, command='LC_LOAD_DYLIB'):
            return f'cmd {command}\ncmdsize 64\nname {path} (offset 24)\n'

        header = macho_header(b.MH_DYLIB)
        rpath = 'cmd LC_RPATH\ncmdsize 64\npath @loader_path/. (offset 12)\n'
        name = '@rpath/leaf.dylib'
        commands = {exe: macho_header(2)+load('@loader_path/left/libStart.dylib')+load('@loader_path/right/libStart.dylib'),
                    left: header+rpath+load(name), right: header+rpath+load(name),
                    first: header+load(name, 'LC_ID_DYLIB'), second: header+load(name, 'LC_ID_DYLIB')}

        def inspect(argv, **kwargs):
            return 'arm64' if argv[0].endswith('lipo') else commands[argv[-1]]

        with patch.object(b, 'capture', side_effect=inspect):
            for value in (name, '@loader_path/leaf.dylib'):
                commands[left] = header+rpath+load(value)
                with self.subTest(first_request=value), self.assertRaisesRegex(ValueError, 'Ambiguous dylib install name.*leaf'):
                    b.loader_check(bundle, exe, {})
            second.unlink()
            second.symlink_to('../left/leaf.dylib')
            result = b.loader_check(bundle, exe, {})
            self.assertEqual(result['right/libStart.dylib']['slices']['arm64']['dependencies'][0]['resolved'],
                             ['left/leaf.dylib'])

    def test_loader_resolves_raw_paths_without_dropping_terminal_directory_components(self):
        bundle = self.root/'bundle'
        executable = bundle/'bin/main'
        library = bundle/'lib/library.dylib'
        for binary in (executable, library):
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b'\xcf\xfa\xed\xfe')
        rpath = '@loader_path/../lib/.'
        dependency = '@rpath/library.dylib'

        def inspect(argv, **kwargs):
            if argv[0].endswith('lipo'):
                return 'arm64'
            if argv[-1] == executable:
                return (macho_header(2)+f'cmd LC_RPATH\ncmdsize 64\npath {rpath} (offset 12)\n'
                        f'cmd LC_LOAD_DYLIB\ncmdsize 64\nname {dependency} (offset 24)')
            return macho_header(b.MH_DYLIB)

        with patch.object(b, 'capture', side_effect=inspect):
            for value in ('@rpath/library.dylib', '@loader_path/../lib/./library.dylib',
                          '@executable_path/../lib/library.dylib'):
                dependency = value
                result = b.loader_check(bundle, executable, {})['bin/main']['slices']['arm64']
                self.assertEqual(result['dependencies'][0]['resolved'], ['lib/library.dylib'])
                for ending in ('/', '/.', '/./', '//'):
                    dependency = value+ending
                    with self.subTest(dependency=dependency), self.assertRaisesRegex(ValueError, 'Unresolved product loader path'):
                        b.loader_check(bundle, executable, {})

    def test_loader_rejects_thin_32_bit_macho_in_both_byte_orders(self):
        bundle = self.root/'bundle'
        bundle.mkdir()
        exe = bundle/'main'
        exe.write_bytes(b'\xcf\xfa\xed\xfe')
        for byte_order in ('<', '>'):
            with self.subTest(byte_order=byte_order):
                (bundle/'legacy-helper').write_bytes(struct.pack(byte_order+'IiiIIII', 0xfeedface, 7, 3, 2, 0, 0, 0))
                with patch.object(b, 'capture') as probe, self.assertRaisesRegex(ValueError, '32-bit Mach-O.*legacy-helper'):
                    b.loader_check(bundle, exe, {})
                probe.assert_not_called()

    def test_system_library_probe_checks_disk_and_dyld_shared_cache(self):
        cached = '/usr/lib/libFixtureOnlyInDyldCache.dylib'
        on_disk = self.root/'libFileFixture.dylib'
        on_disk.touch()
        with patch.object(b.ctypes, 'CDLL') as library:
            contains = library.return_value._dyld_shared_cache_contains_path
            contains.side_effect = lambda path: path == os.fsencode(cached)
            self.assertEqual(b.system_library_location(str(on_disk)), 'filesystem')
            library.assert_not_called()
            self.assertEqual(b.system_library_location(cached), 'dyld shared cache')
            self.assertIsNone(b.system_library_location('/usr/lib/libFixtureNotFound.dylib'))
            contains.assert_any_call(os.fsencode(cached))

    def test_loader_requires_system_dylibs_except_for_weak_loads(self):
        bundle = self.root/'bundle'
        bundle.mkdir()
        exe = bundle/'main'
        exe.write_bytes(b'\xcf\xfa\xed\xfe')
        dylib = '/usr/lib/libFixtureOnlyInDyldCache.dylib'
        missing = '/System/Library/libFixtureNotFound.dylib'
        command = 'LC_LOAD_DYLIB'
        def inspect(argv, **kwargs):
            return ('arm64' if argv[0].endswith('lipo') else
                    macho_header(2)+f'cmd {command}\ncmdsize 64\nname {dependency} (offset 24)')

        with (patch.object(b, 'capture', side_effect=inspect),
              patch.object(b, 'system_library_location', side_effect={dylib: 'dyld shared cache', missing: None}.__getitem__)):
            dependency = dylib
            result = b.loader_check(bundle, exe, {})
            self.assertEqual(result['main']['slices']['arm64']['dependencies'],
                             [{'path': dylib, 'scope': 'OS system', 'loadCommand': command,
                               'availability': 'dyld shared cache'}])
            dependency = missing
            for command in ('LC_LOAD_DYLIB', 'LC_LOAD_UPWARD_DYLIB', 'LC_REEXPORT_DYLIB', 'LC_LAZY_LOAD_DYLIB'):
                with self.subTest(command=command), self.assertRaisesRegex(ValueError, 'Missing required system dylib.*NotFound'):
                    b.loader_check(bundle, exe, {})
            command = 'LC_LOAD_WEAK_DYLIB'
            result = b.loader_check(bundle, exe, {})
            self.assertEqual(result['main']['slices']['arm64']['dependencies'],
                             [{'path': missing, 'scope': 'OS system', 'loadCommand': command,
                               'availability': 'missing weak load'}])
            for dependency in ('/usr/lib/../../tmp/library.dylib', '/System/Library/../../opt/library.dylib',
                               '/usr/lib/./library.dylib', '/usr/lib//library.dylib'):
                with self.subTest(dependency=dependency), self.assertRaisesRegex(ValueError, 'External loader path'):
                    b.loader_check(bundle, exe, {})

    def stub_material_command(self, output):
        original = b.Runner.command

        def command(runner, name, argv, cwd=None, **kwargs):
            if name in ('collect', 'check'):
                return output
            return original(runner, name, argv, cwd, **kwargs)

        return command

    def test_material_arguments_bind_current_inputs_and_review_required_fails(self):
        info = {'toolchain': {'flutterPath': '/selected sdk'},
                'sourceCommit': b.capture(['git', 'rev-parse', 'HEAD'], self.root)}
        opts = {'output': str(self.out/'materials'), 'downloads': '/downloads', 'probe': '/new probe.json', 'sdkSourceWorkspace': '/sdk sources'}
        argv = [str(v) for v in b.material_argv(self.root, self.out, info, opts, 'collect')]
        for flag, expected in (('--build-inputs', self.out/'evidence/compilation-input-hashes.json'),
                               ('--candidate-hashes', self.out/'evidence/candidate-checksums.txt'),
                               ('--build-receipt', self.out/'evidence/build-receipt.json'),
                               ('--probe', '/new probe.json')):
            self.assertEqual(argv[argv.index(flag)+1], str(expected))
        (self.out/'evidence').mkdir(parents=True)
        output = '{"status":"REVIEW_REQUIRED","openGates":["old candidate probe"]}'
        with (patch.object(b.Runner, 'command', self.stub_material_command(output)),
              self.assertRaisesRegex(ValueError, 'not PASS')):
            b.strict_materials(self.root, self.out, info, opts, 'collect', 'test')
        ledger = next((self.out/'evidence').glob('materials-*/build-receipt.json'))
        self.assertEqual(b.read(ledger)['status'], 'FAIL')

    def test_material_json_allows_sdk_progress_but_never_trailing_errors(self):
        output = 'Verifying SDK source archive: original.tar.gz\n{\n  "status": "PASS",\n  "failures": []\n}\n'
        self.assertEqual(b.material_result(output)['status'], 'PASS')
        self.assertEqual(b.material_result('{"status":"REVIEW_REQUIRED"}')['status'], 'REVIEW_REQUIRED')
        with self.assertRaises(json.JSONDecodeError):
            b.material_result(output+'ERROR: failed after report\n')

    def test_products_require_full_native_bundles_before_runtime(self):
        app, cli = b.product_paths(self.out)
        (cli/'bin').mkdir(parents=True);(cli/'bin/meshctl').write_bytes(b'executable only')
        with patch.object(b, 'check_app'), self.assertRaisesRegex(ValueError, 'Incomplete product'):
            b.products(self.root, app, cli, {'productVersion': '0.1.0-rc.1', 'appBuild': '7'}, {})

    def test_products_require_arm64_aot_exports_before_signature_and_runtime_checks(self):
        app, cli = self.product_fixture()
        ident = {'productVersion': '0.1.0-rc.1', 'appBuild': '7'}
        loads = {b.APP_AOT_BINARY: {'slices': {'arm64': {'fileType': b.MH_DYLIB}}}}
        argv = ['/usr/bin/xcrun', 'dyld_info', '-arch', 'arm64', '-exports', app/b.APP_AOT_BINARY]
        with (patch.object(b, 'check_app'), patch.object(b, 'loader_check'),
              patch.object(b, 'inspect_loaders', return_value=(loads, {})),
              patch.object(b, 'capture', return_value='    0x00004000  _kDartSnapshotText\n') as probe,
              patch.object(b.subprocess, 'run') as codesign):
            with self.assertRaisesRegex(ValueError, 'arm64 lacks Dart AOT exports: _kDartSnapshotData'):
                b.products(self.root, app, cli, ident, {})
            probe.assert_called_once_with(argv, env={})
            codesign.assert_not_called()
            probe.return_value += '    0x0038C000  _kDartSnapshotData\n'
            aot = b.verify_app_aot(app, loads, {})
            self.assertEqual(aot['exports'], ['_kDartSnapshotData', '_kDartSnapshotText'])
            self.assertEqual(aot['architecture'], 'arm64')
            loads[b.APP_AOT_BINARY]['slices']['arm64']['fileType'] = 2
            with self.assertRaisesRegex(ValueError, 'AOT snapshot is not an arm64 dylib'):
                b.verify_app_aot(app, loads, {})

    def test_app_native_manifest_maps_required_ids_to_each_loading_slice(self):
        app, _ = b.product_paths(self.out)
        manifest = app/'Contents/Frameworks/App.framework/Resources/flutter_assets/NativeAssetsManifest.json'
        manifest.parent.mkdir(parents=True)
        (app/b.APP_RUNNER).parent.mkdir()
        (app/b.APP_ENGINE_BINARY).parent.mkdir(parents=True)
        arches = ('arm64', 'x86_64')
        loaders = {b.APP_RUNNER: {'slices': {arch: {'rpaths': ['@executable_path/../Frameworks'],
                                                  'dependencies': [{'resolved': [b.APP_ENGINE_BINARY]}]}
                                           for arch in arches}},
                   b.APP_ENGINE_BINARY: {'slices': {arch: {'fileType': b.MH_DYLIB,
                                                         'rpaths': ['@loader_path/../../..']}
                                                  for arch in arches}}}
        ids = {}
        for asset, framework in b.APP_NATIVE_ASSETS.items():
            ids[asset] = ['absolute', '@rpath/'+framework]
            target = 'Contents/Frameworks/'+framework
            (app/target).parent.mkdir(parents=True)
            (app/target).write_bytes(b'framework fixture')
            loaders[target] = {'architectures': ['arm64', 'x86_64'],
                               'slices': {arch: {'fileType': b.MH_DYLIB} for arch in ('arm64', 'x86_64')}}
        with self.assertRaisesRegex(ValueError, 'Missing or external App native asset manifest'):
            b.app_native_assets(app, loaders)
        spec = {'format-version': [1, 0, 0], 'native-assets': {'macos_arm64': ids.copy(), 'macos_x64': ids.copy()}}
        b.write(manifest, spec)
        mappings = b.app_native_assets(app, loaders)['macos_arm64']
        self.assertEqual(len(mappings), 2)
        for entry in mappings.values():
            self.assertEqual(entry['caller'], b.APP_ENGINE_BINARY)
            self.assertEqual(entry['rpathChain'][0], {'owner': b.APP_ENGINE_BINARY, 'path': '@loader_path/../../..'})
        engine_arm = loaders[b.APP_ENGINE_BINARY]['slices']['arm64']
        engine_arm['rpaths'].insert(0, '/usr/local/lib/.')
        with self.assertRaisesRegex(ValueError, 'Host-dependent loader resolution.*via /usr/local/lib'):
            b.app_native_assets(app, loaders)
        engine_arm['rpaths'][0] = '@loader_path/.'
        shadow = (app/b.APP_ENGINE_BINARY).parent/next(iter(b.APP_NATIVE_ASSETS.values()))
        shadow.parent.mkdir()
        shadow.write_bytes(b'engine runpath wins')
        with self.assertRaisesRegex(ValueError, 'Unresolved App native asset'):
            b.app_native_assets(app, loaders)
        shadow.unlink()
        with patch.dict(loaders[b.APP_RUNNER]['slices']['arm64'], {'dependencies': []}):
            with self.assertRaisesRegex(ValueError, 'not a linked Flutter engine'):
                b.app_native_assets(app, loaders)
        unknown_id = 'package:unreviewed/native.dart'
        for unknown_path in (str(self.root/'external.dylib'), '@rpath/sqlite3.framework/sqlite3'):
            spec['native-assets']['macos_arm64'][unknown_id] = ['absolute', unknown_path]
            b.write(manifest, spec)
            with self.assertRaisesRegex(ValueError, 'Unreviewed App native asset IDs.*unreviewed'):
                b.app_native_assets(app, loaders)
        del spec['native-assets']['macos_arm64'][unknown_id]
        spec['native-assets']['unreviewed_target'] = ids.copy()
        b.write(manifest, spec)
        with self.assertRaisesRegex(ValueError, 'drift.*App native asset targets'):
            b.app_native_assets(app, loaders)
        del spec['native-assets']['unreviewed_target']
        sqlite, path = next((asset, value) for asset, value in ids.items() if asset.startswith('package:sqlite3/'))
        for wrong in (None, ['absolute', '@rpath/libserialport_plus.framework/libserialport_plus'],
                      ['absolute', str(self.root/'libsqlite3.dylib')]):
            with self.subTest(mapping=wrong):
                spec['native-assets']['macos_x64'][sqlite] = wrong
                b.write(manifest, spec)
                with self.assertRaisesRegex(ValueError, 'Invalid App native asset mapping for macos_x64.*sqlite3'):
                    b.app_native_assets(app, loaders)
        spec['native-assets']['macos_x64'][sqlite] = path
        b.write(manifest, spec)
        sqlite_target = loaders['Contents/Frameworks/sqlite3.framework/sqlite3']
        sqlite_target['slices']['x86_64']['fileType'] = 2
        with self.assertRaisesRegex(ValueError, 'App native asset target is not a Mach-O dylib for x86_64'):
            b.app_native_assets(app, loaders)
        sqlite_target['architectures'] = ['arm64']
        with self.assertRaisesRegex(ValueError, 'App native asset target lacks x86_64.*sqlite3'):
            b.app_native_assets(app, loaders)

    def test_app_engine_runpath_normalization_checks_existing_signature_before_writes(self):
        app, _ = b.product_paths(self.out)
        for path in (app/b.APP_ENGINE_BINARY, app/b.APP_RUNNER):
            path.parent.mkdir(parents=True)
            path.write_text('owned fixture')

        def receipt_command(name, argv, *, return_stderr=False):
            if name.endswith('-architectures'):
                return 'arm64 x86_64'
            if return_stderr:
                return 'Signature=adhoc\n'

        command = Mock(side_effect=receipt_command)
        b.normalize_app_engine_runpath(app, self.out, command)
        normalize, engine_seal, app_seal = [entry.args for entry in command.call_args_list[-3:]]
        self.assertEqual(normalize[1][-2:], ['/usr/local/lib/.', app/b.APP_ENGINE_BINARY])
        self.assertEqual((engine_seal[1][-1], app_seal[1][-1]), (app/b.APP_ENGINE, app))

        def certificate_signature(name, argv, **kwargs):
            if name == 'app-signature-before-normalization-x86_64':
                return 'Authority=Developer ID Application\n'
            return receipt_command(name, argv, **kwargs)

        command = Mock(side_effect=certificate_signature)
        with self.assertRaisesRegex(ValueError, 'requires existing local ad hoc signatures: app'):
            b.normalize_app_engine_runpath(app, self.out, command)
        self.assertFalse(any('normalize-runpath' in call.args[0] for call in command.call_args_list))

        os.link(app/b.APP_ENGINE_BINARY, self.root/'other-engine')
        command.reset_mock()
        with self.assertRaisesRegex(ValueError, 'requires an owned file:.*FlutterMacOS'):
            b.normalize_app_engine_runpath(app, self.out, command)
        command.assert_not_called()

    def test_manifest_asset_dependencies_inherit_the_flutter_caller_chain(self):
        app, _ = b.product_paths(self.out)
        runner, engine = app/b.APP_RUNNER, app/b.APP_ENGINE_BINARY
        frameworks = app/'Contents/Frameworks'
        sqlite = frameworks/'sqlite3.framework/sqlite3'
        outer = sqlite.with_name('libOuter.dylib')
        preferred = engine.parent/'priority/libValue.dylib'
        fallback = frameworks/'libValue.dylib'
        asset_files = [frameworks/name for name in b.APP_NATIVE_ASSETS.values()]
        for path in (runner, engine, outer, preferred, fallback, *asset_files):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'\xcf\xfa\xed\xfe fixture')
        manifest = frameworks/'App.framework/Resources/flutter_assets/NativeAssetsManifest.json'
        manifest.parent.mkdir(parents=True)
        assets = {name: ['absolute', '@rpath/'+file] for name, file in b.APP_NATIVE_ASSETS.items()}
        b.write(manifest, {'format-version': [1, 0, 0], 'native-assets': {'macos_arm64': assets}})

        def rpath(path):
            return f'cmd LC_RPATH\ncmdsize 64\npath {path} (offset 12)\n'

        def load(path):
            return f'cmd LC_LOAD_DYLIB\ncmdsize 64\nname {path} (offset 24)\n'

        commands = {
            runner: macho_header(2)+rpath('@executable_path/../Frameworks')+
                load('@rpath/FlutterMacOS.framework/Versions/A/FlutterMacOS'),
            engine: macho_header(b.MH_DYLIB)+rpath('@loader_path/priority'),
            sqlite: macho_header(b.MH_DYLIB)+load('@loader_path/libOuter.dylib'),
            outer: macho_header(b.MH_DYLIB)+load('@rpath/libValue.dylib'),
        }

        def inspect(argv, **kwargs):
            return 'arm64' if argv[0].endswith('lipo') else commands.get(argv[-1], macho_header(b.MH_DYLIB))

        with patch.object(b, 'capture', side_effect=inspect):
            loaders, reported_assets = b.inspect_loaders(app, runner, {}, app_assets=True)
            self.assertEqual(set(reported_assets['macos_arm64']), set(assets))
            slice_report = loaders[outer.relative_to(app).as_posix()]['slices']['arm64']
            self.assertEqual(slice_report['rpathChain'][0]['owner'], b.APP_ENGINE_BINARY)
            self.assertEqual(slice_report['dependencies'][0]['resolved'], [preferred.relative_to(app).as_posix()])
            fallback.unlink()
            b.inspect_loaders(app, runner, {}, app_assets=True)
            fallback.write_bytes(preferred.read_bytes())
            commands[preferred] = macho_header(2)
            with self.assertRaisesRegex(ValueError, 'not a Mach-O dylib.*libOuter.dylib.*libValue.dylib'):
                b.inspect_loaders(app, runner, {}, app_assets=True)

    def product_fixture(self):
        app, cli = b.product_paths(self.out)
        for name in ('bin/meshctl', *b.CLI_LIBRARIES):
            path = cli/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'fixture')
        for framework in ('App', 'FlutterMacOS', 'libserialport_plus', 'sqlite3'):
            path = app/f'Contents/Frameworks/{framework}.framework/{framework}'
            path.parent.mkdir(parents=True)
            path.write_bytes(b'fixture')
        return app, cli

    def test_products_reject_external_cli_link_before_any_probe(self):
        app, cli = self.product_fixture()
        external = self.root/'external-program'
        external.write_text('#!/bin/sh\nexit 0\n')
        external.chmod(0o755)
        executable = cli/'bin/meshctl'
        executable.unlink()
        executable.symlink_to(os.path.relpath(external, executable.parent))
        ident = {'productVersion': '0.1.0-rc.1', 'appBuild': '7'}
        with (patch.object(b, 'check_app'), patch.object(b, 'capture') as probe,
              self.assertRaisesRegex(ValueError, 'External product symlink')):
            b.products(self.root, app, cli, ident, {})
        probe.assert_not_called()

    def test_cli_sqlite_probe_requires_the_bundled_library_and_database(self):
        _, bundle = self.product_fixture()
        executable = bundle/'bin/meshctl'
        library = bundle/b.CLI_SQLITE_LIBRARY
        stdout = json.dumps({'schemaVersion': 1, 'operationSucceeded': True, 'exitCode': 0,
                             'storageClose': {'state': 'closed'}})
        touched = []

        def run(argv, *, cwd, env, text, capture_output, check):
            temp = Path(cwd)
            touched.append(temp)
            self.assertFalse(temp.is_relative_to(bundle))
            self.assertEqual(argv, [str(executable), '--data-dir', str(temp/'data'), 'settings', 'show', '--json'])
            self.assertEqual(env['DYLD_PRINT_LIBRARIES'], '1')
            self.assertTrue(text and capture_output and check)
            (temp/'data').mkdir()
            (temp/'data/meshchan.sqlite').write_bytes(database)
            return subprocess.CompletedProcess(argv, 0, stdout, trace)

        system = 'dyld[42]: <AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA> /usr/lib/libsqlite3.dylib\n'
        bundled = f'dyld[42]: <BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB> {library}\n'
        database = b'SQLite format 3\0'
        with patch.object(b.subprocess, 'run', side_effect=run):
            for trace in (system, system+bundled.rstrip('\n')+'.other\n'):
                with self.assertRaisesRegex(ValueError, 'did not load its bundled'):
                    b.verify_cli_sqlite(bundle, executable, {})
            trace = system+bundled
            proof = b.verify_cli_sqlite(bundle, executable, {})
            self.assertEqual(proof['loadedLibrary'], b.CLI_SQLITE_LIBRARY)
            database = b'invalid SQLite header'
            with self.assertRaisesRegex(ValueError, 'did not produce a SQLite database'):
                b.verify_cli_sqlite(bundle, executable, {})
        self.assertTrue(all(not folder.exists() for folder in touched))

    def test_cli_signature_gate_rejects_each_unverified_sibling_library(self):
        app, cli = self.product_fixture()
        ident = {'productVersion': '0.1.0-rc.1', 'appBuild': '7'}
        for name in b.CLI_LIBRARIES:
            def codesign(argv, **kwargs):
                if argv[1] == '--verify' and argv[-1] == str(cli/name):
                    raise subprocess.CalledProcessError(1, argv)
                return subprocess.CompletedProcess(argv, 0, '', '')

            with (self.subTest(name=name), patch.object(b, 'check_app'),
                  patch.object(b, 'loader_check'),
                  patch.object(b, 'inspect_loaders', return_value=({}, {})),
                  patch.object(b, 'verify_app_aot'),
                  patch.object(b, 'capture') as probe,
                  patch.object(b.subprocess, 'run', side_effect=codesign),
                  self.assertRaises(subprocess.CalledProcessError) as failure):
                b.products(self.root, app, cli, ident, {})
            self.assertEqual(failure.exception.cmd[-1], str(cli/name))
            probe.assert_not_called()

    def test_hung_product_cli_obeys_deadline_and_drains_descendants(self):
        _, cli = self.product_fixture()
        marker = self.root/'cli-started'
        marker.mkdir()
        exe = cli/'bin/meshctl'
        exe.write_text('#!/bin/sh\ntouch '+repr(str(marker/'ready'))+'\nexec /bin/sleep 30\n')
        exe.chmod(0o755)
        wrapper = self.root/'tool/build_release.py'
        wrapper.write_text(f"""import subprocess
import sys
sys.path.insert(0, {str(Path(b.__file__).parent)!r})
from pathlib import Path
from unittest.mock import patch
import build_release as b
b.ROOT = Path({str(self.root)!r})
actual_run = subprocess.run
def run(argv, **kwargs):
    if argv[0] == '/usr/bin/codesign':
        return subprocess.CompletedProcess(argv, 0, '', '')
    return actual_run(argv, **kwargs)
with (patch.object(b, 'check_app'),
      patch.object(b, 'loader_check'), patch.object(b, 'inspect_loaders', return_value=({{}}, {{}})),
      patch.object(b, 'verify_app_aot'),
      patch.object(subprocess, 'run', side_effect=run),
      patch.object(b, 'identity', return_value={{'productVersion': '0.1.0-rc.1', 'appBuild': '7'}})):
    sys.exit(b.main())
""")
        evidence = self.out/'evidence'
        evidence.mkdir()
        receipt = {'recipeVersion': FRESH_HOOK_RECIPE-1, 'steps': []}
        runner = b.Runner(self.root, evidence, receipt, b.controlled_environment(), timeout=3)
        with b.checkout_lock(self.root):
            try:
                with self.assertRaisesRegex(TimeoutError, 'validate-products'):
                    b.run_product_checks(self.root, self.out, runner.command)
            except subprocess.CalledProcessError:
                self.fail((evidence/'logs/validate-products.log').read_text())
        self.assertTrue((marker/'ready').exists())
        step, = runner.receipt['steps']
        self.assertEqual(step['name'], 'validate-products')
        self.assertTrue(step['processTree']['exited'])
        self.assertGreaterEqual(len(step['processTree']['members']), 2)
        self.assertTrue(all(member['exitObserved'] for member in step['processTree']['members']))

    def test_codesign_stderr_is_retained_in_build_failure_records(self):
        error = subprocess.CalledProcessError(
            1, ['/usr/bin/codesign', '--verify', 'fixture.dylib'],
            stderr=b'fixture.dylib: code object is not signed at all\n')
        self.assertNotIn('not signed', repr(error))
        with self.assertRaises(subprocess.CalledProcessError):
            self.build_fixture(product_error=error)
        for path in (self.out/'build-info.json', self.out/'evidence/build-receipt.json'):
            record = b.read(path)
            self.assertEqual(record.get('buildStatus', record.get('status')), 'FAIL')
            self.assertIn('code object is not signed at all', record['error'])

    def evidence_fixture(self):
        evidence = self.out/'evidence';evidence.mkdir(parents=True)
        logs = evidence/'logs';logs.mkdir()
        app, cli = b.product_paths(self.out)
        for bundle in (app, cli):
            bundle.mkdir(parents=True);(bundle/'payload').write_bytes(b'compiled product')
        (cli/'lib').mkdir(mode=0o755)
        lock = self.root/'pubspec.lock'
        lock.write_text('locked fixture')
        before = {'source.dart': digest(self.root/'source.dart'), 'pubspec.lock': digest(lock)}
        for name in ('compilation-input-hashes.json', 'inputs-after-cli.json', 'inputs-after-app.json'):
            b.write(evidence/name, before)
        (evidence/'run_build.py').write_bytes(b'original runner')
        prebuild = evidence/'prebuild-identities.json'
        b.write(prebuild, {'source': before, 'externalSources': {}, 'configuration': {},
                           'toolchain': {}, 'helpers': {}})
        graph = evidence/'resolved-graph.json'
        b.write(graph, {'packages': []})
        compiler = evidence/'compiler-inputs.json'
        depfile_hashes = {}
        for name in ('compiler/cli.d', 'compiler/app-0.d', 'compiler/app-assets-0.d'):
            path = evidence/name
            path.parent.mkdir(exist_ok=True)
            path.write_text('fixture depfile')
            depfile_hashes[name] = digest(path)
        b.write(compiler, {'depfileHashes': depfile_hashes, 'firstParty': {'cli': before, 'app': before},
                           'hosted': {'cli': {}, 'app': {}}, 'hostedNotices': {}})
        sums = evidence/'candidate-checksums.txt'
        sums.write_text('\n'.join(digest(p/'payload')+'  '+(p/'payload').relative_to(self.root).as_posix() for p in (app, cli))+'\n')
        steps = []
        report = {'status': 'PASS', 'signatures': {'app': {'entitlements': 'fixture entitlements'}}}
        checks = evidence/'product-checks.json'
        b.write(checks, report)
        for name in ('configure-release', 'cli-build', 'app-build', 'validate-products'):
            log = logs/(name+'.log');log.write_text('successful command')
            if name == 'validate-products':
                log.write_text(json.dumps(report))
            stderr = log.with_suffix('.stderr.log');stderr.write_text('diagnostic')
            steps.append({'name': name, 'exitCode': 0, 'log': log.relative_to(self.root).as_posix(), 'logSha256': digest(log),
                          'stderrLog': stderr.relative_to(self.root).as_posix(), 'stderrLogSha256': digest(stderr)})
        inventory = evidence/'candidate-inventories.json'
        b.write(inventory, {'app': b.full_inventory(app), 'cli': b.full_inventory(cli)})
        native_hooks = self.out/b.NATIVE_HOOK_SNAPSHOT
        native_hooks.mkdir()
        (native_hooks/'hook-output').write_bytes(b'current hook bytes')
        receipt = {'formatVersion': 1, 'status': 'PASS', 'inputsUnchangedAcrossBuilds': True,
                   'recipeVersion': b.RECIPE_VERSION, 'workingTree': ' M source.dart', 'engineeringDirtyMode': True,
                   'sourceCommit': b.capture(['git', 'rev-parse', 'HEAD'], self.root),
                   'app': app.relative_to(self.root).as_posix(), 'cli': cli.relative_to(self.root).as_posix(),
                   'compilationInputsSha256': digest(evidence/'compilation-input-hashes.json'),
                   'candidateChecksumsSha256': digest(sums), 'runnerSha256': digest(evidence/'run_build.py'),
                   'candidateInventoriesSha256': digest(inventory),
                   'nativeHookCacheSha256': b.sha(b.encoded(b.full_inventory(native_hooks))),
                   'compilerInputsSha256': digest(compiler),
                   'prebuildIdentitiesSha256': digest(prebuild), 'resolvedGraphSha256': digest(graph),
                   'productChecksSha256': digest(checks), 'steps': steps}
        b.write(evidence/'build-receipt.json', receipt)
        info = {'buildStatus': 'PASS', 'productChecksStatus': 'PASS', 'app': receipt['app'], 'cli': receipt['cli'],
                'sourceCommit': receipt['sourceCommit'], 'materials': {'status': 'NOT_RUN'},
                'recipeVersion': receipt['recipeVersion'], 'recipe': steps, 'signatures': report['signatures'],
                'workingTree': receipt['workingTree'], 'engineeringDirtyMode': receipt['engineeringDirtyMode'],
                'lockSha256': digest(lock), 'resolvedGraphSha256': digest(graph),
                'compilationInputIdentity': receipt['compilationInputsSha256'], 'sourceInputIdentity': b.sha(b.encoded(before)),
                'runIdentity': self.out.relative_to(self.root).as_posix(),
                'toolchain': {}, 'helperHashes': {}, 'controlledConfiguration': {'generated': {}},
                'evidence': {p.name: b.ref(self.root, p) for p in evidence.iterdir() if p.is_file()}}
        b.write(self.out/'build-info.json', info)
        return info

    def test_checkout_commit_timeouts_seal_verification_receipts_and_release_lock(self):
        info = self.evidence_fixture()
        evidence = self.out/'evidence'
        index = self.out/'build-info.json'
        build_receipt = evidence/'build-receipt.json'
        original_build = (index.read_bytes(), build_receipt.read_bytes())
        info['toolchain'] = {'flutterPath': '/selected sdk'}
        options = {'output': str(self.out/'materials'), 'downloads': str(self.root/'downloads'),
                   'probe': str(self.root/'probe'), 'sdkSourceWorkspace': str(self.root/'sdk-source')}
        original = self.stub_material_command('{"status":"PASS"}')
        for label, step_name in (
                ('check-inputs', 'checkout-commit-before-check'),
                ('materials-before', 'checkout-commit-before-materials'),
                ('materials-after', 'checkout-commit-after-materials')):
            with self.subTest(step=step_name):
                def command(runner, name, argv, cwd=None, **kwargs):
                    if name == step_name:
                        self.assertEqual(argv, ['git', 'rev-parse', 'HEAD'])
                        argv = ['/bin/sleep', '30']
                    return original(runner, name, argv, cwd, **kwargs)

                with (patch.object(b, 'ROOT', self.root), patch.object(b.Runner, 'command', command),
                      self.assertRaisesRegex(TimeoutError, 'Command deadline exceeded: '+step_name)):
                    if label == 'check-inputs':
                        b.check(argparse.Namespace(output=self.out, timeout=0.7))
                    else:
                        with b.checkout_lock(self.root):
                            b.strict_materials(self.root, self.out, info, options, 'collect',
                                               label.removeprefix('materials-'), timeout=0.7)
                ledger_path, = evidence.glob(f'{label}-*/build-receipt.json')
                ledger = b.read(ledger_path)
                self.assertEqual(ledger['status'], 'FAIL')
                step = ledger['steps'][-1]
                self.assertEqual(step['name'], step_name)
                self.assertTrue(step['processTree']['exited'])
                self.assertIn('SIGTERM', step['processTree']['signalsSent'])
                self.assertEqual((index.read_bytes(), build_receipt.read_bytes()), original_build)
                with b.checkout_lock(self.root):
                    pass

    def test_check_detects_product_log_receipt_and_inventory_tampering(self):
        info = self.evidence_fixture()
        evidence = self.out/'evidence'
        app, cli = b.product_paths(self.out)
        b.verify_evidence(self.root, self.out, info)
        for path in (app/'payload', cli/'payload', evidence/'build-receipt.json', evidence/'logs/app-build.log',
                     evidence/'logs/app-build.stderr.log', evidence/'candidate-inventories.json', evidence/'inputs-after-cli.json',
                     evidence/'compiler-inputs.json', evidence/'compiler/cli.d', evidence/'compiler/app-0.d',
                     evidence/'compiler/app-assets-0.d'):
            original = path.read_bytes();path.write_bytes(b'tampered')
            with self.subTest(path=path), self.assertRaises((ValueError, json.JSONDecodeError)):
                b.verify_evidence(self.root, self.out, info)
            path.write_bytes(original)
        (cli/'payload').chmod(0o755)
        with self.assertRaisesRegex(ValueError, 'inventory'):
            b.verify_evidence(self.root, self.out, info)

    def test_product_signatures_agree_with_validator_and_receipt(self):
        info = self.evidence_fixture()
        b.verify_evidence(self.root, self.out, info)
        with self.assertRaisesRegex(ValueError, 'indexed product signatures'):
            b.verify_evidence(self.root, self.out, {**info, 'signatures': {'app': {'entitlements': 'edited'}}})
        checks = self.out/'evidence/product-checks.json'
        info['evidence'].pop(checks.name)
        with self.assertRaisesRegex(ValueError, 'lacks required build evidence'):
            b.verify_evidence(self.root, self.out, info)
        b.write(checks, {'status': 'PASS', 'signatures': {'app': {'entitlements': 'substitute'}}})
        info['evidence'][checks.name] = b.ref(self.root, checks)
        with self.assertRaisesRegex(ValueError, 'product check report receipt'):
            b.verify_evidence(self.root, self.out, info)

    def test_prebuild_evidence_must_match_index_and_original_receipt(self):
        info = self.evidence_fixture()
        path = self.out/'evidence/prebuild-identities.json'
        reference = info['evidence'].pop(path.name)
        with self.assertRaisesRegex(ValueError, 'lacks required build evidence'):
            b.verify_evidence(self.root, self.out, info)
        b.write(path, {'source': {'source.dart': 'replacement'}, 'externalSources': {}})
        info['evidence'][path.name] = reference
        with self.assertRaisesRegex(ValueError, 'Evidence file changed'):
            b.verify_evidence(self.root, self.out, info)
        info['evidence'][path.name] = b.ref(self.root, path)
        with self.assertRaisesRegex(ValueError, 'prebuild identities receipt'):
            b.verify_evidence(self.root, self.out, info)

    def test_directory_mode_drift_is_rejected_without_changing_file_bytes(self):
        info = self.evidence_fixture()
        app, cli = b.product_paths(self.out)
        evidence = self.out/'evidence'
        b.verify_evidence(self.root, self.out, info)
        (cli/'lib').chmod(0o700)
        with self.assertRaisesRegex(ValueError, 'actual product inventory'):
            b.verify_evidence(self.root, self.out, info)
        inventory = evidence/'candidate-inventories.json'
        b.write(inventory, {'app': b.full_inventory(app), 'cli': b.full_inventory(cli)})
        info['evidence'][inventory.name] = b.ref(self.root, inventory)
        with self.assertRaisesRegex(ValueError, 'product inventory receipt'):
            b.verify_evidence(self.root, self.out, info)

    def test_check_rejects_fifo_added_to_bundle(self):
        info = self.evidence_fixture()
        _, cli = b.product_paths(self.out)
        pipe = cli/'unrecorded FIFO'
        os.mkfifo(pipe)
        with self.assertRaisesRegex(ValueError, 'Unsupported product entry type.*unrecorded FIFO'):
            b.verify_evidence(self.root, self.out, info)

    def test_check_and_materials_reject_fifo_index_and_step_logs_without_opening(self):
        self.evidence_fixture()
        args = self.material_args(timeout=5)
        path_open = Path.open
        for relative in ('build-info.json', 'evidence/logs/app-build.log', 'evidence/logs/app-build.stderr.log'):
            path = self.out/relative
            original = path.read_bytes()
            path.unlink()
            os.mkfifo(path)

            def open_regular(target, *args, **kwargs):
                if target == path:
                    self.fail('Verification tried to open a FIFO: '+relative)
                return path_open(target, *args, **kwargs)

            for command in (b.check, b.materials):
                with (self.subTest(path=relative, command=command.__name__),
                      patch.object(b, 'ROOT', self.root), patch.object(b, 'output_path', return_value=self.out),
                      patch.object(Path, 'open', open_regular),
                      self.assertRaisesRegex(ValueError, 'Expected a regular file: .*'+path.name)):
                    command(args)
                with b.checkout_lock(self.root):
                    pass
            path.unlink()
            path.write_bytes(original)

    def test_indexed_provenance_must_match_the_receipt_and_its_inputs(self):
        info = self.evidence_fixture()
        b.verify_evidence(self.root, self.out, info)
        for key, value in {'workingTree': '', 'engineeringDirtyMode': False, 'recipeVersion': b.RECIPE_VERSION+1,
                           'recipe': [], 'compilationInputIdentity': '0'*64,
                           'sourceInputIdentity': '0'*64, 'lockSha256': '0'*64,
                           'resolvedGraphSha256': '0'*64}.items():
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'indexed build provenance '+key):
                b.verify_evidence(self.root, self.out, {**info, key: value})
        graph = self.out/'evidence/resolved-graph.json'
        info['evidence'].pop(graph.name)
        with self.assertRaisesRegex(ValueError, 'lacks required build evidence'):
            b.verify_evidence(self.root, self.out, info)
        b.write(graph, {'packages': ['substitute']})
        info['evidence'][graph.name] = b.ref(self.root, graph)
        info['resolvedGraphSha256'] = digest(graph)
        with self.assertRaisesRegex(ValueError, 'resolved dependency graph receipt'):
            b.verify_evidence(self.root, self.out, info)

    def test_check_rejects_edited_index_before_using_current_configuration(self):
        info = self.evidence_fixture()
        info['controlledConfiguration']['generated'] = {'Flutter-Generated.xcconfig': 'new hash'}
        b.write(self.out/'build-info.json', info)
        with (patch.object(b, 'ROOT', self.root), patch.object(b, 'configuration') as live,
              self.assertRaisesRegex(ValueError, 'indexed generated configuration')):
            b.check(argparse.Namespace(output=self.out, timeout=5))
        live.assert_not_called()

    def test_check_rejects_workspace_config_drift_before_launching_input_parser(self):
        info = self.evidence_fixture()
        evidence = self.out/'evidence'
        config = self.root/b.PACKAGE_CONFIG
        config.parent.mkdir()
        config.write_text('recorded workspace configuration')
        prebuild_path = evidence/'prebuild-identities.json'
        prebuild = b.read(prebuild_path)
        prebuild['configuration'] = {b.PACKAGE_CONFIG: digest(config)}
        prebuild['toolchain'] = {'flutterPath': str(self.root/'sdk')}
        b.write(prebuild_path, prebuild)
        receipt_path = evidence/'build-receipt.json'
        receipt = b.read(receipt_path)
        receipt['prebuildIdentitiesSha256'] = digest(prebuild_path)
        b.write(receipt_path, receipt)
        info['toolchain'] = prebuild['toolchain']
        info['controlledConfiguration']['generated'] = prebuild['configuration']
        info['identity'] = {}
        for path in (prebuild_path, receipt_path):
            info['evidence'][path.name] = b.ref(self.root, path)
        b.write(self.out/'build-info.json', info)

        config.write_text('changed workspace configuration')
        with (patch.object(b, 'ROOT', self.root), patch.object(b, 'output_path', return_value=self.out),
              patch.object(b, 'identity', return_value={}), patch.object(b, 'helpers', return_value={}),
              patch.object(b, 'toolchain', return_value=prebuild['toolchain']),
              patch.object(b.Runner, 'command', return_value=info['sourceCommit']),
              patch.object(b, 'inputs') as parser,
              self.assertRaisesRegex(ValueError, 'Identity drift during current workspace package configuration')):
            b.check(argparse.Namespace(output=self.out))
        parser.assert_not_called()

    def test_check_rejects_drift_during_live_validation(self):
        info = self.evidence_fixture()
        evidence = self.out/'evidence'
        config = self.root/b.PACKAGE_CONFIG
        config.parent.mkdir()
        config.write_text('{}')
        generated = {b.PACKAGE_CONFIG: digest(config)}
        toolchain = {'flutterPath': str(self.root/'sdk')}
        info.update(identity={}, toolchain=toolchain, controlledConfiguration={'generated': generated})
        b.write(self.out/'build-info.json', info)
        prebuild_path = evidence/'prebuild-identities.json'
        prebuild = b.read(prebuild_path)
        source = b.repository_source_hashes(self.root, [self.out])
        prebuild.update(toolchain=toolchain, configuration=generated, source=source,
                        sourceMetadata=b.repository_source_metadata(self.root, source))
        b.write(prebuild_path, prebuild)
        _, cli = b.product_paths(self.out)
        ignored = self.root/'build/local.dart'
        ignored.write_text('ignored engineering input')
        input_path = evidence/'compilation-input-hashes.json'
        input_base = b.read(input_path)

        def input_snapshot(*_, **_options):
            return input_base | {'build/local.dart': digest(ignored)}

        b.write(input_path, input_snapshot())

        def command(_runner, _name, argv, cwd=None):
            return b.capture(argv, cwd or self.root, b.controlled_environment())

        for changed, error in (
                (cli/'payload', 'products during verification'),
                (self.root/'source.dart', 'source during verification'),
                (ignored, 'compilation inputs during verification'),
                (self.out/b.NATIVE_HOOK_SNAPSHOT/'hook-output', 'Saved native hook cache differs')):
            with self.subTest(path=changed):
                original = changed.read_bytes()

                def validate(*_):
                    changed.write_bytes(b'changed by product check')
                    return {'signatures': info['signatures']}

                try:
                    with (patch.object(b, 'ROOT', self.root), patch.object(b, 'output_path', return_value=self.out),
                          patch.object(b, 'verify_evidence', return_value=evidence),
                          patch.object(b, 'identity', return_value={}), patch.object(b, 'helpers', return_value={}),
                          patch.object(b, 'toolchain', return_value=toolchain),
                          patch.object(b, 'configuration', return_value=generated),
                          patch.object(b, 'inputs', side_effect=input_snapshot),
                          patch.object(b, 'external_sources', return_value={}),
                          patch.object(b.Runner, 'command', command),
                          patch.object(b, 'run_product_checks', side_effect=validate),
                          self.assertRaisesRegex(ValueError, error)):
                        b.check(argparse.Namespace(output=self.out))
                finally:
                    changed.write_bytes(original)

    def test_check_rejects_foreign_index_and_evidence_even_after_relabeling(self):
        info = self.evidence_fixture()
        other = self.out.with_name('second run')
        (other/'evidence').mkdir(parents=True)
        b.write(other/'build-info.json', info)
        args = argparse.Namespace(output=other)
        with patch.object(b, 'ROOT', self.root):
            with self.assertRaisesRegex(ValueError, 'selected run'):
                b.check(args)
            info['runIdentity'] = other.relative_to(self.root).as_posix()
            b.write(other/'build-info.json', info)
            with self.assertRaisesRegex(ValueError, 'selected run products'):
                b.check(args)
            info['app'], info['cli'] = [p.relative_to(self.root).as_posix() for p in b.product_paths(other)]
            b.write(other/'build-info.json', info)
            with self.assertRaisesRegex(ValueError, 'not owned by the selected run'):
                b.check(args)

    def test_commit_only_drift_blocks_collection_before_writing(self):
        self.evidence_fixture()
        subprocess.run(['git', 'commit', '--allow-empty', '-qm', 'Different commit, same tree'],
                       cwd=self.root, check=True)
        args = self.material_args()
        with patch.object(b, 'ROOT', self.root), self.assertRaisesRegex(ValueError, 'checkout commit'):
            b.materials(args)
        self.assertFalse((self.out/'materials').exists())
        self.assertEqual(b.read(self.out/'build-info.json')['materials']['status'], 'NOT_RUN')

    def test_handoff_check_rejects_engineering_build_even_at_same_commit(self):
        self.evidence_fixture()
        with (patch.object(b, 'ROOT', self.root),
              self.assertRaisesRegex(ValueError, 'Handoff requires a build from a frozen source commit')):
            b.check(argparse.Namespace(output=self.out, require_frozen=True))

    def material_args(self, **overrides):
        values = {'output': self.out, 'materials_name': 'materials',
                  'downloads': self.root/'downloads', 'probe': self.root/'probe',
                  'sdk_source_workspace': self.root/'sdk-source'}
        return argparse.Namespace(**(values | overrides))

    def test_materials_reject_product_cache_paths_without_writing(self):
        self.evidence_fixture()
        app, cli = b.product_paths(self.out)
        alias = self.root/'cli alias'
        alias.symlink_to(cli, target_is_directory=True)
        index = self.out/'build-info.json'
        original = digest(index)
        for fields in ({'downloads': app/'new-cache'}, {'downloads': alias/'new-cache'},
                       {'sdk_source_workspace': cli/'new-cache'}, {'downloads': self.out/'cli'}):
            with (self.subTest(fields=fields), patch.object(b, 'ROOT', self.root),
                  self.assertRaisesRegex(ValueError, 'overlaps a candidate product')):
                b.materials(self.material_args(**fields))
        self.assertEqual(digest(index), original)
        self.assertFalse((app/'new-cache').exists())
        self.assertFalse((cli/'new-cache').exists())

    def test_materials_reject_case_aliases_on_case_insensitive_volumes(self):
        self.evidence_fixture()
        app, cli = b.product_paths(self.out)
        app_alias = app.with_name('meshchan.app')
        if not app_alias.exists():
            self.skipTest('Fixture volume has case-sensitive names')
        cli_ancestor_alias = cli.parent.with_name('CLI')
        self.assertTrue(cli_ancestor_alias.samefile(cli.parent))
        self.assertTrue(app_alias.samefile(app))
        with patch.object(b, 'ROOT', self.root):
            for path in (app_alias/'not-created'/'cache', cli_ancestor_alias):
                with self.subTest(path=path), self.assertRaisesRegex(ValueError, 'overlaps a candidate product'):
                    b.materials(self.material_args(downloads=path))
        self.assertFalse((app/'not-created').exists())
        self.assertFalse((self.out/'materials').exists())

    def test_sdk_probe_rejects_aliased_writes_before_collect_or_recheck(self):
        info = self.evidence_fixture()
        _, cli = b.product_paths(self.out)
        original = b.full_inventory(cli)
        for leaf in ('evidence', 'evidence/app-arm64-gn.log', 'checkout/engine/src/out'):
            workspace = self.root/leaf.replace('/', '-')
            alias = workspace/leaf
            alias.parent.mkdir(parents=True)
            alias.symlink_to(cli if not leaf.endswith('.log') else cli/'uncreated-log')
            options = {'output': str(self.out/'materials'), 'downloads': str(self.root/'downloads'),
                       'sdkSourceWorkspace': str(workspace), 'probe': str(self.root/'probe')}
            with patch.object(b.Runner, 'command') as command:
                for action in ('collect', 'check'):
                    with self.subTest(leaf=leaf, action=action), self.assertRaisesRegex(
                            ValueError, 'SDK probe write path uses a symlink'):
                        b.strict_materials(self.root, self.out, info, options, action, 'fixture')
                command.assert_not_called()
        self.assertEqual(b.full_inventory(cli), original)

    def test_accepted_materials_index_survives_retry_request(self):
        info = self.evidence_fixture()
        info['materials'] = {'status': 'PASS', 'references': {'manifest': 'existing binding'}}
        index = self.out/'build-info.json'
        b.write(index, info)
        original = digest(index)
        with (patch.object(b, 'ROOT', self.root), patch.object(b, 'strict_materials') as collect,
              self.assertRaisesRegex(ValueError, 'already accepted')):
            b.materials(self.material_args(materials_name='retry'))
        collect.assert_not_called()
        self.assertEqual(digest(index), original)

    def test_materials_sigterm_during_finalization_records_failure_and_releases_lock(self):
        self.evidence_fixture()
        index = self.out/'build-info.json'
        receipt = self.out/'evidence/build-receipt.json'
        original_receipt = receipt.read_bytes()
        original_write = b.write

        def deliver_sigterm():
            self.assertTrue(callable(signal.getsignal(signal.SIGTERM)))
            signal.raise_signal(signal.SIGTERM)

        for phase in ('verify-evidence', 'publish-pass'):
            with self.subTest(phase=phase):
                args = self.material_args(materials_name=phase, timeout=5)
                destination = self.out/phase

                def strict_materials(root, out, info, options, action, label, timeout, *, interrupted):
                    self.assertIsInstance(interrupted, b.DeferredInterrupts)
                    self.assertEqual(b.read(index)['materials']['status'], 'RUNNING')
                    archive = destination/'source-materials/meshchan/meshchan-source.tar.gz'
                    archive.parent.mkdir(parents=True, exist_ok=True)
                    archive.write_bytes(source_archive(root, [])[0])
                    manifest = destination/'materials-manifest.json'
                    original_write(manifest, {'materials': {archive.relative_to(destination).as_posix(): b.ref(root, archive)}})
                    log = out/'evidence'/label/(action+'.log')
                    log.parent.mkdir(exist_ok=True)
                    log.write_text('fixture')
                    log.with_suffix('.stderr.log').write_text('')
                    return log, digest(manifest)

                def verify_evidence(*args):
                    if phase == 'verify-evidence':
                        deliver_sigterm()

                def write(path, value):
                    original_write(path, value)
                    if phase == 'publish-pass' and path == index and value['materials']['status'] == 'PASS':
                        deliver_sigterm()

                with (patch.object(b, 'ROOT', self.root), patch.object(b, 'output_path', return_value=self.out),
                      patch.object(b, 'check'), patch.object(b, 'strict_materials', side_effect=strict_materials),
                      patch.object(b, 'verify_evidence', side_effect=verify_evidence),
                      patch.object(b, 'RELEASE_ENTRY_SOURCE_FILES', ()), patch.object(b, 'write', side_effect=write),
                      self.assertRaisesRegex(b.GateInterrupted, 'SIGTERM')):
                    b.materials(args)
                result = b.read(index)
                self.assertEqual(result['buildStatus'], 'PASS')
                self.assertEqual(result['materials']['status'], 'FAIL')
                self.assertEqual(result['materials']['interruptSignal'], signal.SIGTERM)
                self.assertIn('SIGTERM', result['materials']['error'])
                self.assertNotIn('references', result['materials'])
                self.assertEqual(receipt.read_bytes(), original_receipt)
                with b.checkout_lock(self.root):
                    pass

    def test_handoff_rejects_unlisted_and_aliased_materials_even_with_bound_manifest(self):
        output = self.out/'materials'
        (output/'licenses').mkdir(parents=True)
        payload = output/'licenses/LICENSE'
        payload.write_bytes(b'license')
        manifest = output/'materials-manifest.json'
        b.write(manifest, {'materials': {'licenses/LICENSE': {'sha256': digest(payload)}}})
        logs = self.out/'evidence'
        logs.mkdir()
        refs = {manifest.name: b.ref(self.root, manifest)}
        for name in ('collect.log', 'collect.stderr.log', 'check.log', 'check.stderr.log'):
            path = logs/name
            path.write_text('retained log')
            refs[name] = b.ref(self.root, path)
        materials = {'arguments': {'output': str(output)}, 'references': refs}
        b.verify_material_binding(self.root, self.out, materials)
        extra = output/'licenses/local-only.txt'
        extra.write_text('not part of this handoff')
        with self.assertRaisesRegex(ValueError, 'Unlisted material: licenses/local-only.txt'):
            b.verify_material_binding(self.root, self.out, materials)
        extra.unlink()
        path_open = Path.open
        for path in (manifest, logs/'collect.log', logs/'check.stderr.log'):
            original = path.read_bytes()
            path.unlink()
            os.mkfifo(path)

            def open_regular(target, *args, **kwargs):
                if target == path:
                    self.fail('Material binding tried to open a FIFO: '+path.name)
                return path_open(target, *args, **kwargs)

            with (self.subTest(path=path.name), patch.object(Path, 'open', open_regular),
                  self.assertRaisesRegex(ValueError, 'Expected a regular file: .*'+path.name)):
                b.verify_material_binding(self.root, self.out, materials)
            path.unlink()
            path.write_bytes(original)
        external = self.root/'original-license'
        payload.rename(external)
        payload.symlink_to(external)
        with self.assertRaisesRegex(ValueError, 'Aliased.*material file'):
            b.verify_material_binding(self.root, self.out, materials)

    def test_materials_bind_manifest_and_original_receipt(self):
        info = self.evidence_fixture()
        out = self.out/'materials'
        out.mkdir()
        options = {'output': str(out), 'downloads': str(self.root/'downloads'),
                   'probe': str(self.root/'probe'), 'sdkSourceWorkspace': str(self.root/'sdk-source')}
        info['toolchain'] = {'flutterPath': '/selected sdk'}
        receipt_path = self.out/'evidence/build-receipt.json'
        receipt = b.read(receipt_path)
        original = {'sha256': digest(receipt_path), 'value': receipt}
        for error, commit, embedded, manifest_replaced in (
                ('material manifest commit', 'new', original, False),
                ('material build receipt contents', info['sourceCommit'],
                 {**original, 'value': {**receipt, 'startedAt': 'different build'}}, False),
                ('material build receipt digest', info['sourceCommit'], {**original, 'sha256': 'different'}, False),
                ('material manifest subprocess result', info['sourceCommit'], original, True)):
            with self.subTest(error=error):
                manifest = out/'materials-manifest.json'
                b.write(manifest, {'sourceCommit': commit, 'openGates': [], 'products': {'buildReceipt': embedded}})
                result = json.dumps({'status': 'PASS', 'manifestSha256': digest(manifest)})
                if manifest_replaced:
                    manifest.write_bytes(manifest.read_bytes()+b'\n')
                with (patch.object(b.Runner, 'command', self.stub_material_command(result)),
                      self.assertRaisesRegex(ValueError, error)):
                    b.strict_materials(self.root, self.out, info, options, 'collect', 'fixture')

    def test_materials_reject_source_changed_after_initial_build_check(self):
        info = self.evidence_fixture()
        evidence = self.out/'evidence'
        output = self.out/'materials'
        output.mkdir()
        options = {'output': str(output), 'downloads': str(self.root/'downloads'),
                   'probe': str(self.root/'probe'), 'sdkSourceWorkspace': str(self.root/'sdk-source')}
        info['toolchain'] = {'flutterPath': '/selected sdk'}
        source = self.root/'README.md'
        source.write_text('frozen project instructions')
        prebuild = b.read(evidence/'prebuild-identities.json')
        prebuild['source'][source.name] = digest(source)
        self.assertNotIn(source.name, b.read(evidence/'compilation-input-hashes.json'))
        b.write(evidence/'prebuild-identities.json', prebuild)
        receipt = b.read(evidence/'build-receipt.json')
        receipt['prebuildIdentitiesSha256'] = digest(evidence/'prebuild-identities.json')
        b.write(evidence/'build-receipt.json', receipt)
        receipt_sha = digest(evidence/'build-receipt.json')
        info['evidence']['build-receipt.json']['sha256'] = receipt_sha
        manifest = {'sourceCommit': info['sourceCommit'], 'openGates': [], 'sourceInputHashes': dict(prebuild['source']),
                    'products': {'buildReceipt': {'sha256': receipt_sha, 'value': receipt}}}
        b.write(output/'materials-manifest.json', manifest)

        def strict_result():
            return self.stub_material_command(json.dumps({'status': 'PASS',
                'manifestSha256': digest(output/'materials-manifest.json')}))

        with patch.object(b.Runner, 'command', strict_result()):
            b.strict_materials(self.root, self.out, info, options, 'check', 'original')
        source.write_text('instructions edited during material collection')
        manifest['sourceInputHashes'][source.name] = digest(source)
        b.write(output/'materials-manifest.json', manifest)
        with patch.object(b.Runner, 'command', strict_result()):
            for command in ('collect', 'check'):
                with self.subTest(command=command), self.assertRaisesRegex(ValueError, 'drift.*material source map'):
                    b.strict_materials(self.root, self.out, info, options, command, command)
        prebuild['source'] = manifest['sourceInputHashes']
        b.write(evidence/'prebuild-identities.json', prebuild)
        with (patch.object(b.Runner, 'command', strict_result()),
              self.assertRaisesRegex(ValueError, 'drift.*material source evidence')):
            b.strict_materials(self.root, self.out, info, options, 'check', 'altered-evidence')

    def test_only_fixed_result_reports_are_excluded_from_delivered_source(self):
        docs = self.root/'docs';(docs/'validation').mkdir(parents=True);(docs/'releases').mkdir()
        report = docs/'validation/phase-1e4-build.md';report.write_text('result 1')
        instructions = docs/'releases/phase-1e4-build.md';instructions.write_text('build instructions')
        arbitrary = docs/'validation/other.md';arbitrary.write_text('must remain')
        before = repository_source_hashes(self.root, [])
        report.write_text('result 2')
        self.assertEqual(before, repository_source_hashes(self.root, []))
        self.assertIn('docs/releases/phase-1e4-build.md', before)
        self.assertIn('docs/validation/other.md', before)
        instructions.write_text('changed instructions')
        self.assertNotEqual(before, repository_source_hashes(self.root, []))

    def test_external_sources_capture_native_hook_bytes_and_detect_drift(self):
        config = self.root/'.dart_tool/package_config.json';config.parent.mkdir()
        with tempfile.TemporaryDirectory() as other:
            cache = Path(other).resolve()
            packages = []
            for name in ('libserialport_plus', 'sqlite3', 'native_toolchain_c', 'hooks', 'code_assets'):
                folder = cache/name;folder.mkdir();(folder/'source').write_text(name)
                (folder/'pubspec.yaml').write_text('name: '+name+'\n')
                packages.append({'name': name, 'rootUri': folder.as_uri(), 'packageUri': 'lib/'})
            flutter = self.root/'sdk'
            sdk_package = flutter/'bin/cache/pkg/sky_engine'
            sdk_package.mkdir(parents=True)
            license_path = sdk_package/'LICENSE'
            license_path.write_text('original SDK license')
            framework = flutter/'packages/flutter'
            framework.mkdir(parents=True)
            flutter_license = framework/'LICENSE'
            flutter_license.write_text('pinned Flutter license')
            subprocess.run(['git', 'init', '-q'], cwd=flutter, check=True)
            subprocess.run(['git', 'add', 'packages/flutter/LICENSE'], cwd=flutter, check=True)
            subprocess.run(['git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test',
                            'commit', '-qm', 'Pinned SDK'], cwd=flutter, check=True)
            spec = self.root/'sdk-spec.json'
            b.write(spec, {'frameworkRevision': b.capture(['git', 'rev-parse', 'HEAD'], flutter),
                           'engineRevision': 'fixture'})
            b.write(self.root/'tool/release_materials_sources.json', {
                'sky_engine-fixture.zip': {'licenseMember': 'sky_engine/LICENSE', 'licenseSha256': digest(license_path)}})
            self.enterContext(patch.object(b, 'SPEC', spec))
            packages.append({'name': 'sky_engine', 'rootUri': sdk_package.as_uri(), 'packageUri': 'lib/'})
            packages.append({'name': 'flutter', 'rootUri': framework.as_uri(), 'packageUri': 'lib/'})
            b.write(config, {'packages': packages})
            before = b.external_sources(self.root, flutter)
            self.assertEqual(b.native_source_hashes(before)['libserialport_plus']['source'],
                             digest(cache/'libserialport_plus/source'))
            extra = cache/'libserialport_plus/local-header.h'
            extra.write_text('local extra header')
            self.assertNotIn(extra.name, b.native_source_hashes(before)['libserialport_plus'])
            self.assertEqual(b.native_source_hashes(b.external_sources(self.root, flutter))['libserialport_plus'][extra.name],
                             digest(extra))
            extra.unlink()
            self.assertEqual(before['sky_engine']['sdkNotice'], {'path': str(license_path), 'sha256': digest(license_path)})
            license_path.write_text('changed SDK license')
            with self.assertRaisesRegex(ValueError, 'SDK notice differs from pinned artifact member'):
                b.external_sources(self.root, flutter)
            license_path.write_text('original SDK license')
            for package in (sdk_package, framework):
                with self.subTest(package=package.name):
                    notice = package/'NOTICES'
                    notice.write_text('untracked override')
                    with self.assertRaisesRegex(ValueError, 'SDK notice differs from pinned Flutter source: .*NOTICES'):
                        b.external_sources(self.root, flutter)
                    notice.unlink()
            self.assertEqual(before, b.external_sources(self.root, flutter))
            (cache/'libserialport_plus/source').write_text('changed native source')
            with self.assertRaisesRegex(ValueError, 'drift'):
                b.require_equal(before['libserialport_plus'], b.external_sources(self.root, flutter)['libserialport_plus'],
                                'external sources')
            b.write(config, {'packages': packages[1:]})
            with self.assertRaisesRegex(ValueError, 'incomplete'):
                b.external_sources(self.root, flutter)


if __name__ == '__main__':
    unittest.main()
