"""Test the case and process boundaries without a guest or candidate."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import accept_installed_release as install

PROTECTION_INVENTORY = 'SIP\tSystem Integrity Protection status: enabled.\nGatekeeper\tassessments enabled\n'
PREFLIGHT_INVENTORY = 'OS\t27.2.1\t26B131\tarm64\n'+PROTECTION_INVENTORY


def verified_download_fixture(layout):
    time = '2026-11-21T17:42:00Z'
    when = install.files.parse_time(time)
    guid = 'A654CB03-F3CE-4123-88E1-CC38CB2988DF'
    url = 'http://192.168.64.1/'+install.DMG_NAME
    quarantine = f'0083;{int(when.timestamp()):x};Safari;{guid}'
    attributes = {install.files.QUARANTINE: quarantine.encode(),
                  install.files.WHERE_FROM: plistlib.dumps([url])}
    stamp = {'path': layout['download'], 'size': install.DMG_SIZE, 'birthTime': int(when.timestamp())}
    return {'browser': 'Safari', 'sha256': install.DMG_SHA, 'file': stamp, 'url': url,
            'startedAt': time, 'finishedAt': time, 'quarantine': quarantine, 'whereFrom': [url],
            'event': {'id': guid, 'agent': 'com.apple.Safari', 'url': None,
                      'appleTime': (when-install.files.APPLE_EPOCH).total_seconds()},
            'metadata': {'extendedAttributes': {'.': {
                key: {'scope': install.files.SYSTEM_ATTRIBUTES[key], 'hex': value.hex()}
                for key, value in attributes.items()}},
                'ownershipAclAndFlags': '-rw-r--r--@ 1 guest staff - 675911154 file'}}


def record_bound_mount(evidence, layout):
    baseline = plistlib.dumps({'images': [], 'framework': 'one', 'revision': '1'})
    (evidence/install.BASELINE).write_bytes(baseline)
    before_pin = hashlib.sha256(baseline).hexdigest()
    install.write_new(evidence/'preflight.json', {'createdAt': '2026-11-21T17:40:00Z'})
    install.write_new(evidence/'mount-baseline.json', {'sha256': before_pin,
                                                      'capturedAt': '2026-11-21T17:41:00Z'})
    download = verified_download_fixture(layout)
    stamp = download['file']
    install.write_new(evidence/'download.json', download)
    mounted = {'volumeName': install.VOLUME, 'readOnly': True, 'download': stamp,
               'volumeUuid': install.inputs.DMG_VOLUME_UUID,
               'attachment': {'path': layout['download'], 'imageProcessPid': 34}}
    record = evidence/'mount.json'
    install.write_new(record, {**mounted, 'beforeSha256': before_pin})
    return mounted, before_pin, install.digest(record)


class InstallCaseTest(unittest.TestCase):
    def test_layout_is_account_default_and_keeps_complete_cli(self):
        paths = install.path_layout('guest', 'install-01')
        self.assertEqual(paths['app'], '/Users/guest/Applications/Meshchan.app')
        self.assertEqual(paths['data'], '/Users/guest/Library/Application Support/meshchan')
        self.assertTrue(paths['cli'].endswith('/'+install.CANDIDATE+'/meshctl/bin/meshctl'))
        for user, token in [('../guest', 'ok'), ('guest', '../ok'), ('guest', 'bad\ncase')]:
            with self.subTest(user=user, token=token), self.assertRaises(ValueError):
                install.path_layout(user, token)

    def test_preflight_target_and_identity_are_required(self):
        vm = SimpleNamespace(c={'user': 'guest', 'uuid': 'specific-guest'})
        run = 'upgrade-01'
        paths = install.path_layout('guest', run)
        targets = {paths[key]: 'absent' for key in ('app', 'data', 'product', 'download')}
        targets['/Applications/Meshchan.app'] = 'absent'
        partial = paths['download']+'.download'
        targets[partial] = 'absent'
        base = {'formatVersion': 1, 'run': run, 'modelVerifiedBySsh': True,
                'consoleUser': 'guest', 'guestUuid': 'specific-guest', 'paths': paths, 'targets': targets,
                'inventory': PREFLIGHT_INVENTORY}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            record = root/'preflight.json'
            record.write_text(json.dumps(base))
            self.assertEqual(install.checked_case(vm, run, root), paths)
            for mutation in ({'formatVersion': True}, {'consoleUser': 'other'},
                             {'guestUuid': 'other'}, {'targets': {**targets, paths['data']: 'present'}},
                             {'targets': {**targets, partial: 'present'}},
                             {'inventory': PREFLIGHT_INVENTORY.replace('arm64', 'x86_64')},
                             {'inventory': PREFLIGHT_INVENTORY.replace('assessments enabled', 'assessments disabled')}):
                with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                    record.write_text(json.dumps({**base, **mutation}))
                    install.checked_case(vm, run, root)

    def test_preflight_refuses_disabled_or_ambiguous_system_protection(self):
        layout = install.path_layout('guest', 'run')
        targets = [layout[key] for key in ('app', 'data', 'product', 'download')]
        targets += ['/Applications/Meshchan.app', layout['download']+'.download']
        inventory = PREFLIGHT_INVENTORY+''.join(f'target\tabsent\t{path}\n' for path in targets)
        vm = SimpleNamespace(c={'user': 'guest', 'uuid': 'specific-guest'}, runpath=lambda run: '/guest/runs/'+run)
        with patch.object(install, 'output', return_value=inventory) as remote:
            self.assertEqual(install.preflight(vm, 'run')['inventory'], inventory)
            self.assertIn('assessment=$(/usr/sbin/spctl --status)', remote.call_args.args[1])
            for wrong, name in (
                (inventory.replace('status: enabled.', 'status: disabled.'), 'SIP'),
                (inventory+'Gatekeeper\tassessments disabled\n', 'Gatekeeper'),
            ):
                remote.return_value = wrong
                with self.assertRaisesRegex(ValueError, 'enabled '+name):
                    install.preflight(vm, 'run')

    def test_lan_binding_requires_private_ipv4(self):
        self.assertEqual(install.lan_address('192.168.64.1'), '192.168.64.1')
        for address in ('0.0.0.0', '127.0.0.1', '1.1.1.1', '::1'):
            with self.subTest(address=address), self.assertRaises(ValueError):
                install.lan_address(address)

    def test_network_probe_retains_failure_and_exits_nonzero(self):
        layout = install.path_layout('guest', 'install-01')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            argv = ['accept', 'network', '--label', 'before', '--vm-config', 'private.json',
                    '--run', 'install-01', '--evidence', str(root)]
            reachable = {'status': 'REACHABLE', 'probes': {}}
            vm = object()
            with (patch.object(sys, 'argv', argv),
                  patch.object(install.guest, 'load', return_value=SimpleNamespace(VM=lambda _: vm)),
                  patch.object(install, 'checked_case', return_value=layout),
                  patch.object(install.checks, 'observe_network', return_value=reachable),
                  patch.object(install.checks, 'require_offline', side_effect=ValueError('reachability'))):
                with self.assertRaisesRegex(ValueError, 'reachability'):
                    install.main()
            receipt = install.read_record(root/'network-before.json')
            self.assertEqual((receipt['status'], receipt['label']), ('REACHABLE', 'before'))

    def test_network_retry_retains_inconclusive_evidence_and_refuses_known_reachability(self):
        layout = install.path_layout('guest', 'install-01')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            receipt = root/'network-before.json'
            original = {'status': 'UNVERIFIED', 'probes': {}, 'label': 'before'}
            install.write_new(receipt, original)
            argv = ['accept', 'network', '--label', 'before', '--vm-config', 'private.json',
                    '--run', 'install-01', '--evidence', str(root)]
            vm = object()
            with (patch.object(sys, 'argv', argv),
                  patch.object(install.guest, 'load', return_value=SimpleNamespace(VM=lambda _: vm)),
                  patch.object(install, 'checked_case', return_value=layout),
                  patch.object(install.checks, 'observe_network', return_value={'status': 'REACHABLE'}) as observe,
                  patch.object(install.checks, 'require_offline', side_effect=ValueError('reachability'))):
                with self.assertRaisesRegex(ValueError, 'reachability'):
                    install.main()
                with self.assertRaises(FileExistsError):
                    install.main()
                observe.assert_called_once_with(vm)
            self.assertEqual(install.read_record(root/'network-before-attempt-1.json'), original)
            self.assertEqual(install.read_record(receipt), {'status': 'REACHABLE', 'label': 'before'})

    def test_network_interrupt_after_a_public_response_prevents_case_retry(self):
        layout = install.path_layout('guest', 'install-01')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            argv = ['accept', 'network', '--label', 'before', '--vm-config', 'private.json',
                    '--run', 'install-01', '--evidence', str(root)]
            vm = SimpleNamespace()
            reachable = subprocess.CompletedProcess([], 0, '1.1.1.1\n0.015000\n200\n', '')
            with (patch.object(sys, 'argv', argv),
                  patch.object(install.guest, 'load', return_value=SimpleNamespace(VM=lambda _: vm)),
                  patch.object(install, 'checked_case', return_value=layout),
                  patch.object(vm, 'remote', create=True, side_effect=[reachable, KeyboardInterrupt]) as remote):
                with self.assertRaises(KeyboardInterrupt):
                    install.main()
                receipt = install.read_record(root/'network-before.json')
                self.assertIs(receipt['interrupted'], True)
                self.assertEqual(receipt['status'], 'REACHABLE')
                with self.assertRaises(FileExistsError):
                    install.main()
                self.assertEqual(remote.call_count, 2)

    def test_incomplete_receipt_serialization_leaves_no_canonical_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            receipt = root/'result.json'
            with self.assertRaises(TypeError):
                install.write_new(receipt, {'first': 'serialized', 'second': object()})
            self.assertEqual(list(root.iterdir()), [])
            install.write_new(receipt, {'status': 'PASS'})
            with self.assertRaises(FileExistsError):
                install.write_new(receipt, {'status': 'other'})
            self.assertEqual(install.read_record(receipt), {'status': 'PASS'})

    def test_failed_case_actions_preserve_separate_numbered_receipts_and_allow_retry(self):
        layout = install.path_layout('guest', 'install-01')
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            argv = ['accept', 'install', '--label', 'before', '--vm-config', 'private.json',
                    '--run', 'install-01', '--evidence', str(evidence)]
            vm = object()
            failed = ValueError('unexpected installed file at a private path')
            with (patch.object(sys, 'argv', argv),
                  patch.object(install.guest, 'load', return_value=SimpleNamespace(VM=lambda _: vm)),
                  patch.object(install, 'checked_case', return_value=layout),
                  patch.object(install, 'collect_case', side_effect=[failed, KeyboardInterrupt,
                                                                     {'inventory': 'verified'}])):
                with self.assertRaises(ValueError) as error:
                    install.main()
                self.assertIs(error.exception, failed)
                with self.assertRaises(KeyboardInterrupt):
                    install.main()
                self.assertFalse((evidence/'install-before.json').exists())
                install.main()
            errors = [install.read_record(evidence/f'install-before-failure-{n}.json') for n in (1, 2)]
            self.assertEqual([item['status'] for item in errors], ['FAIL', 'INTERRUPTED'])
            self.assertEqual([item['errorType'] for item in errors], ['ValueError', 'KeyboardInterrupt'])
            self.assertTrue(all(item['action'] == 'install-before' and item['run'] == 'install-01'
                                for item in errors))
            self.assertNotIn('private path', json.dumps(errors))
            self.assertEqual(install.read_record(evidence/'install-before.json'), {'inventory': 'verified'})

    def test_launch_transport_failure_preserves_both_the_request_and_failed_attempt(self):
        layout = install.path_layout('guest', 'install-01')
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            argv = ['accept', 'open-request', '--label', 'initial', '--vm-config', 'private.json',
                    '--run', 'install-01', '--evidence', str(evidence)]
            vm = object()

            def interrupted_request(*_):
                install.write_new(evidence/'launch-initial.json', {'status': 'REQUESTED'})
                raise subprocess.TimeoutExpired('ssh', 10)

            with (patch.object(sys, 'argv', argv),
                  patch.object(install.guest, 'load', return_value=SimpleNamespace(VM=lambda _: vm)),
                  patch.object(install, 'checked_case', return_value=layout),
                  patch.object(install, 'request_open', side_effect=interrupted_request)):
                with self.assertRaises(subprocess.TimeoutExpired):
                    install.main()
            pending = install.read_record(evidence/'launch-initial.json')
            attempt = install.read_record(evidence/'launch-initial-failure-1.json')
            self.assertEqual(pending['status'], 'REQUESTED')
            self.assertEqual((attempt['status'], attempt['errorType']), ('BLOCKED', 'TimeoutExpired'))

    def test_cli_busy_checks_the_same_live_launch_and_uses_default_storage(self):
        layout = install.path_layout('guest', 'install-01')
        result = SimpleNamespace(returncode=69, stdout='busy', stderr='')
        vm = SimpleNamespace(remote=lambda *_a, **_k: result)
        owner = {'pid': 83, 'ownerMarker': {'pid': 83, 'openedAt': '2026-11-21T17:45:00Z'}}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            install.write_new(root/'runtime-initial.json', owner)
            install.write_new(root/'network-before.json',
                              {'status': 'PASS', 'label': 'before', 'time': '2026-11-21T17:42:00Z'})
            with (patch.object(install.checks, 'require_offline'),
                  patch.object(install, 'observe_launched_runtime', return_value=owner) as observe,
                  patch.object(install, 'verify_cli_files') as verify,
                  patch.object(install, 'invoke_cli', wraps=install.invoke_cli) as invoke,
                  patch.object(install.beta, 'verify_busy') as busy):
                report = install.collect_cli(vm, root, layout, 'busy')
                later_owner = {**owner, 'ownerMarker': {'pid': 83, 'openedAt': '2026-11-21T17:46:00Z'}}
                observe.side_effect = (owner, later_owner)
                with self.assertRaisesRegex(ValueError, 'App owner after CLI contention'):
                    install.collect_cli(vm, root, layout, 'busy')
            self.assertEqual([call.args for call in observe.call_args_list], [(vm, layout, root, 'initial', 83)] * 4)
            self.assertEqual(verify.call_args.args[2], install.CLI_FILE_PINS)
            executable = invoke.call_args.args[2]
            self.assertEqual(str(executable), layout['cli'])
            self.assertEqual(invoke.call_args.args[3:], ('draft', 'list', '--json'))
            self.assertEqual([call.args for call in busy.call_args_list], [(result,), (result,)])
            self.assertEqual(report, {'exitCode': 69, 'stdout': 'busy', 'stderr': '',
                                      'appPid': 83, 'ownerMarker': owner['ownerMarker']})

    def test_served_asset_is_an_independent_verified_copy(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            asset = root/'asset'
            asset.write_bytes(b'expected')
            checksum = hashlib.sha256(b'expected').hexdigest()
            with install.checked_asset(asset, checksum, 8) as admitted:
                asset.write_bytes(b'modified')
                self.assertEqual(admitted.read(), b'expected')
            with self.assertRaisesRegex(ValueError, 'pinned'):
                with install.checked_asset(asset, checksum, 8):
                    self.fail('Accepted an asset with the wrong digest')
            fifo = root/'fifo'
            os.mkfifo(fifo)
            with self.assertRaisesRegex(ValueError, 'size or type'):
                with install.checked_asset(fifo, checksum, 8):
                    self.fail('Accepted a FIFO as a release asset')

    def test_download_window_binds_to_case_preflight(self):
        preflight = '2026-11-21T17:42:26Z'
        baseline = '2026-11-21T17:42:52Z'
        start = '2026-11-21T17:42:53Z'
        end = '2026-11-21T17:43:26Z'
        collection = '2026-11-21T17:44:06Z'
        install.require_case_download_window(preflight, baseline, start, end, collection)
        with self.assertRaises(ValueError):
            install.require_case_download_window('2026-11-22T17:42:26Z', baseline, start, end, collection)
        with self.assertRaises(ValueError):
            install.require_case_download_window(preflight, baseline, end, start, collection)

    def test_mount_rejects_a_verified_safari_download_older_than_the_case_baseline(self):
        layout = install.path_layout('guest', 'install-01')
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            record_bound_mount(evidence, layout)
            receipt_path = evidence/'mount-baseline.json'
            receipt = install.read_record(receipt_path)
            receipt_path.write_text(json.dumps({**receipt, 'capturedAt': '2026-11-21T17:42:01Z'}))
            args = SimpleNamespace(action='mount', before=None)
            with patch.object(install.files, 'observe_download_mount') as mount:
                with self.assertRaisesRegex(ValueError, 'preflight and mount baseline'):
                    install.collect_case(args, None, layout, evidence)
                mount.assert_not_called()

    def test_detach_uses_the_mount_receipt_with_the_same_baseline(self):
        layout = install.path_layout('guest', 'install-01')
        download = verified_download_fixture(layout)
        mounted = {'volumeName': install.VOLUME, 'readOnly': True, 'volumeUuid': install.inputs.DMG_VOLUME_UUID}
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            inventory = plistlib.dumps({'images': [], 'framework': 'one', 'revision': '1'})
            install.write_new(evidence/'preflight.json', {'createdAt': '2026-11-21T17:40:00Z'})
            install.write_new(evidence/'network-before.json',
                              {'label': 'before', 'time': '2026-11-21T17:41:00Z'})
            common = ['--vm-config', str(evidence/'vm.json'), '--run', 'install-01',
                      '--evidence', str(evidence)]
            vm = SimpleNamespace(remote=lambda *args, **kwargs: SimpleNamespace(stdout=inventory.decode()))
            with (patch.object(install.guest, 'load', return_value=SimpleNamespace(VM=lambda _: vm)),
                  patch.object(install, 'checked_case', return_value=layout),
                  patch.object(install.checks, 'require_offline'),
                  patch.object(install.files, 'observe_download_mount', return_value=mounted.copy()),
                  patch.object(install.files, 'detach_download_mount', return_value={'status': 'PASS'}) as detach):
                with (patch.object(sys, 'argv', ['accept', 'mount-baseline', *common]),
                      patch.object(install, 'now', return_value='2026-11-21T17:41:30Z')):
                    install.main()
                install.write_new(evidence/'download.json', download)
                with patch.object(sys, 'argv', ['accept', 'mount', *common]):
                    install.main()
                baseline = install.files.parse_mount_snapshot(inventory.decode())
                with patch.object(sys, 'argv', ['accept', 'detach', *common]):
                    with self.assertRaisesRegex(ValueError, 'Run install --label before'):
                        install.main()
                detach.assert_not_called()
                self.assertFalse((evidence/'detach.json').exists())
                install.write_new(evidence/'install-before.json', {
                    'imageManifestSha256': install.inputs.CANDIDATE_PINS['image_payload'],
                    'mountSha256': install.digest(evidence/'mount.json'),
                    'systemProtection': install.SYSTEM_PROTECTION,
                    'layout': {'app': layout['app'], 'cli': layout['cli'], 'volumeMaterials': layout['product']},
                })
                different = evidence/'different.plist'
                different.write_bytes(plistlib.dumps({'images': [], 'framework': 'two', 'revision': '1'}))
                with patch.object(sys, 'argv', ['accept', 'detach', *common, '--before', str(different)]):
                    with self.assertRaisesRegex(ValueError, 'captured case baseline'):
                        install.main()
                detach.assert_not_called()
                with patch.object(sys, 'argv', ['accept', 'detach', *common]):
                    install.main()
                detach.assert_called_once_with(vm, baseline, download, mounted)
                self.assertEqual(install.read_record(evidence/'detach.json')['beforeSha256'],
                                 hashlib.sha256(inventory).hexdigest())
                with patch.object(sys, 'argv', ['accept', 'detach', *common]):
                    with self.assertRaises(FileExistsError):
                        install.main()
                detach.assert_called_once()

    def test_mount_baseline_refuses_to_begin_before_recorded_offline_probe(self):
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            with patch.object(install, 'record_baseline') as capture:
                with self.assertRaises(FileNotFoundError):
                    install.collect_case(SimpleNamespace(action='mount-baseline'), None, None, evidence)
                capture.assert_not_called()

    def test_mount_baseline_can_retry_when_receipt_was_not_published(self):
        layout = install.path_layout('guest', 'install-01')
        inventory = plistlib.dumps({'images': [], 'framework': 'one', 'revision': '1'}).decode()
        vm = SimpleNamespace(remote=lambda *args, **kwargs: SimpleNamespace(stdout=inventory))
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            common = ['mount-baseline', '--vm-config', 'unused', '--run', 'install-01',
                      '--evidence', str(evidence)]
            receipt = evidence/'mount-baseline.json'
            with (patch.object(sys, 'argv', ['accept', *common]),
                  patch.object(install.guest, 'load', return_value=SimpleNamespace(VM=lambda _: vm)),
                  patch.object(install, 'checked_case', return_value=layout),
                  patch.object(install, 'read_case_network')):
                with patch.object(install, 'write_new', side_effect=OSError('publication interrupted')):
                    with self.assertRaisesRegex(OSError, 'publication interrupted') as failure:
                        install.main()
                    self.assertIn('Could not retain the mount-baseline failure receipt: OSError',
                                  failure.exception.__notes__)
                self.assertFalse(receipt.exists())
                install.main()
            parsed, record = install.read_baseline(evidence)
            self.assertEqual(parsed, install.files.parse_mount_snapshot(inventory))
            self.assertEqual(record['sha256'], hashlib.sha256(inventory.encode()).hexdigest())

    def test_mount_refuses_to_advance_a_staged_beta_without_its_closed_data(self):
        layout = install.path_layout('guest', 'upgrade')
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            record_bound_mount(evidence, layout)
            install.write_new(evidence/'beta-stage.json', {'status': 'PASS'})
            with patch.object(install.files, 'observe_download_mount') as mount:
                with self.assertRaisesRegex(FileNotFoundError, 'beta-observe'):
                    install.collect_case(SimpleNamespace(action='mount', before=None), None, layout, evidence)
                mount.assert_not_called()

    def test_mount_requires_the_matching_download_executor_to_finish_normally(self):
        layout = install.path_layout('guest', 'first')
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            recorded, _, _ = record_bound_mount(evidence, layout)
            runner = '20261121T193040Z-product-1902'
            download = verified_download_fixture(layout)
            download['observationSession'] = {'runner': runner,
                                              'access': 'Guest GUI executor with native Downloads permission'}
            (evidence/'download.json').write_text(json.dumps(download))
            install.write_new(evidence/'executor-start.json', {'run': runner, 'status': 'RUNNING'})
            args = SimpleNamespace(action='mount', before=None)
            vm = object()
            with patch.object(install.files, 'observe_download_mount', return_value=recorded) as observe:
                with self.assertRaisesRegex(ValueError, 'Run executor-finish'):
                    install.collect_case(args, vm, layout, evidence)
                finish = evidence/'executor-finish.json'
                finish.write_text(json.dumps({'run': '20261121T193040Z-product-1903', 'status': 'PASS', 'exitCode': 0}))
                with self.assertRaisesRegex(ValueError, 'Download executor finish run'):
                    install.collect_case(args, vm, layout, evidence)
                finish.write_text(json.dumps({'run': runner, 'status': 'PASS', 'exitCode': 1}))
                with self.assertRaisesRegex(ValueError, 'Download executor finish exitCode'):
                    install.collect_case(args, vm, layout, evidence)
                observe.assert_not_called()
                finish.write_text(json.dumps({'run': runner, 'status': 'PASS', 'exitCode': 0}))
                install.collect_case(args, vm, layout, evidence)
                observe.assert_called_once()
                (evidence/'executor-start.json').unlink()
                install.require_finished_download_executor(evidence, download)

    def test_executor_start_cannot_be_backfilled_after_download(self):
        layout = install.path_layout('guest', 'first')
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            record_bound_mount(evidence, layout)
            args = SimpleNamespace(action='executor-start', vm_config=None, run='first')
            with patch.object(install, 'product_executor') as prepare:
                with self.assertRaisesRegex(FileExistsError, 'download.json'):
                    install.collect_case(args, None, layout, evidence)
                prepare.assert_not_called()

    def test_executor_finish_requires_download_or_explicit_case_abandonment(self):
        layout = install.path_layout('guest', 'install-01')
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            common = ['--vm-config', 'unused', '--evidence', str(evidence), '--run', 'install-01']
            vm = object()
            executor = SimpleNamespace(vm=vm)
            with (patch.object(install.guest, 'load', return_value=SimpleNamespace(VM=lambda _: vm)),
                  patch.object(install, 'checked_case', return_value=layout),
                  patch.object(install, 'product_executor', return_value=executor),
                  patch.object(install, 'finish_executor', return_value={'status': 'PASS'}) as finish):
                with patch.object(sys, 'argv', ['accept', 'executor-finish', *common]):
                    with self.assertRaisesRegex(FileNotFoundError, 'download.json'):
                        install.main()
                    finish.assert_not_called()
                with patch.object(sys, 'argv', ['accept', 'executor-finish', *common, '--abort']):
                    install.main()
                    self.assertEqual(install.read_record(evidence/'executor-finish.json')['status'], 'ABORTED')
                with patch.object(sys, 'argv', ['accept', 'mount-baseline', *common]):
                    with self.assertRaisesRegex(ValueError, 'case was abandoned'):
                        install.main()
                finish.assert_called_once_with(executor, expected_run=None)

    def test_beta_close_can_be_rechecked_after_a_later_cli_error_without_recapture(self):
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            vm = object()
            session = '/Users/guest/utm-ui-isolation/package.ABCDEF01'
            active = {'pid': 40}
            binding = {'guestSession': session, 'runtimeSha256': 'bound runtime'}
            report = {'status': 'PASS', 'pid': 40, **binding, 'snapshot': {}, 'shutdown': {}}
            with (patch.object(install, 'capture_shutdown', return_value=report) as capture,
                  patch.object(install.beta, 'verify_shutdown') as verify_shutdown,
                  patch.object(install.beta, 'verify_archived_snapshot', return_value={}) as verify_snapshot):
                recorded = install.capture_beta_close(vm, evidence, active, session, 'bound runtime')
                self.assertEqual(install.read_record(evidence/'beta-close.json'), recorded)
                self.assertEqual(install.capture_beta_close(vm, evidence, active, session, 'bound runtime'), recorded)
                with self.assertRaisesRegex(ValueError, 'Measured Beta shutdown runtimeSha256'):
                    install.capture_beta_close(vm, evidence, active, session, 'different runtime')
                capture.assert_called_once_with(vm, active, binding, evidence/'closed-beta')
                verify_shutdown.assert_called_once_with(report['shutdown'])
                verify_snapshot.assert_called_once_with(evidence/'closed-beta', report['snapshot'])

    def test_install_before_requires_the_same_live_mount_through_verification(self):
        layout = install.path_layout('guest', 'install-01')
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            mounted, _, mount_pin = record_bound_mount(evidence, layout)
            with (patch.object(install, 'measure_system_protection', return_value=install.SYSTEM_PROTECTION),
                  patch.object(install.files, 'observe_download_mount', return_value=mounted) as observe,
                  patch.object(install, 'checked_install', return_value={'inventory': 'matched'}) as verify):
                self.assertEqual(install.verify_case_install(None, layout, evidence, 'archive', 'before'),
                                 {'inventory': 'matched', 'mountSha256': mount_pin,
                                  'systemProtection': install.SYSTEM_PROTECTION})
                self.assertEqual(observe.call_count, 2)
                observe.side_effect = (mounted, {**mounted, 'attachment': {'imageProcessPid': 35}})
                with self.assertRaisesRegex(ValueError, 'changed during installed-file verification'):
                    install.verify_case_install(None, layout, evidence, 'archive', 'before')
                self.assertEqual(verify.call_count, 2)

    def test_install_after_rechecks_the_actual_comparison_before_file_verification(self):
        layout = install.path_layout('guest', 'install-01')
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            result = evidence/'compare.json'
            result.write_text(json.dumps({'status': 'PASS'}))
            with (patch.object(install, 'measure_system_protection', return_value=install.SYSTEM_PROTECTION),
                  patch.object(install, 'require_final_guest_state'),
                  patch.object(install, 'compare_evidence') as replay,
                  patch.object(install, 'checked_install', return_value={'inventory': 'matched'}) as verify):
                with self.assertRaisesRegex(ValueError, 'complete closed App and CLI comparison'):
                    install.verify_case_install(None, layout, evidence, 'archive', 'after')
                replay.assert_not_called()
                verify.assert_not_called()
                actual = {'status': 'PASS', 'baseline': 'empty', 'historyLimitAfter': 1002,
                          'newDraft': {'title': 'title', 'body': 'body'}, 'draftsAfter': 1}
                replay.return_value = actual
                result.write_text(json.dumps({**actual, 'draftsAfter': 2}))
                with self.assertRaisesRegex(ValueError, 'Closed App and CLI comparison'):
                    install.verify_case_install(None, layout, evidence, 'archive', 'after')
                verify.assert_not_called()
                result.write_text(json.dumps(actual))
                self.assertEqual(install.verify_case_install(None, layout, evidence, 'archive', 'after'),
                                 {'inventory': 'matched', 'compareSha256': install.digest(result),
                                  'systemProtection': install.SYSTEM_PROTECTION,
                                  'finalGuestState': {'caseImageAttached': False, 'appRunning': False,
                                                      'defaultDirectoryOwned': False}})
                replay.assert_called_with(None, layout, evidence, title='title', body='body',
                                          history_limit=1002, beta_case=False)
                verify.assert_called_once()

    def test_final_beta_install_reauthenticates_the_original_admitted_inputs(self):
        layout = install.path_layout('guest', 'upgrade')
        comparison = {'status': 'PASS', 'baseline': 'beta', 'historyLimitAfter': 1002,
                      'newDraft': {'title': 'title', 'body': 'body'}}
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            root = evidence/'original-beta'
            admitted = {'closedFixture': str(root/'hardware/run-09-rf-restart/vm-source-closed-fixture'),
                        'closedDatabaseSha256': install.beta.DATABASE_PIN,
                        'source': {'baseCommit': 'accepted', 'nonbuildHandoffChanges': ['docs/guide.md']}}
            install.write_new(evidence/'compare.json', comparison)
            with (patch.object(install.beta, 'verify_beta', return_value=admitted),
                  patch.object(install.workflow, 'stage_beta', return_value={'status': 'PASS'})):
                args = SimpleNamespace(action='beta-stage', beta_evidence=root)
                install.write_new(evidence/'beta-stage.json', install.collect_beta(args, None, layout, evidence))
            with (patch.object(install, 'measure_system_protection', return_value=install.SYSTEM_PROTECTION),
                  patch.object(install, 'require_final_guest_state'),
                  patch.object(install, 'compare_evidence', return_value=comparison),
                  patch.object(install, 'checked_install', return_value={'inventory': 'matched'}) as verify,
                  patch.object(install.beta, 'verify_beta', return_value={**admitted,
                               'closedDatabaseSha256': 'changed'}) as authenticate):
                with self.assertRaisesRegex(ValueError, 'Beta inputs before and after'):
                    install.verify_case_install(None, layout, evidence, 'archive', 'after')
                authenticate.assert_called_once_with(root)
                verify.assert_not_called()
                reauthenticated = {**admitted, 'source': {**admitted['source'], 'nonbuildHandoffChanges': [
                    'docs/guide.md', 'docs/another-guide.md']}}
                authenticate.return_value = reauthenticated
                result = install.verify_case_install(None, layout, evidence, 'archive', 'after')
                self.assertEqual(result['betaInputs'], reauthenticated)
                verify.assert_called_once()

                (evidence/'beta-stage.json').write_text(json.dumps({'status': 'PASS'}))
                install.write_new(evidence/'beta-inputs.json', admitted)
                result = install.verify_case_install(None, layout, evidence, 'archive', 'after')
                self.assertEqual(result['betaInputs'], reauthenticated)
                authenticate.assert_called_with(root)

    def test_install_after_rechecks_live_app_mount_and_storage_after_file_verification(self):
        layout = install.path_layout('guest', 'first')
        comparison = {'status': 'PASS', 'baseline': 'empty', 'historyLimitAfter': 1002,
                      'newDraft': {'title': 'title', 'body': 'body'}}
        vm = SimpleNamespace(c={'user': 'guest'}, remote=object())
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            install.write_new(evidence/'compare.json', comparison)
            with (patch.object(install, 'measure_system_protection',
                               return_value=install.SYSTEM_PROTECTION) as protection,
                  patch.object(install, 'require_unmounted') as unmounted,
                  patch.object(install, 'require_no_app') as app,
                  patch.object(install.beta, 'require_guest_storage_released') as storage,
                  patch.object(install, 'compare_evidence', return_value=comparison),
                  patch.object(install, 'checked_install', return_value={}) as verify):
                for check in (app, unmounted, storage, protection):
                    with self.subTest(check=check):
                        check.side_effect = [None, ValueError('guest state changed')]
                        with self.assertRaisesRegex(ValueError, 'guest state changed'):
                            install.verify_case_install(vm, layout, evidence, 'archive', 'after')
                        self.assertEqual(check.call_count, 2)
                        verify.assert_called_once()
                        for mock in (app, unmounted, storage, protection, verify):
                            mock.reset_mock(side_effect=True)
                install.verify_case_install(vm, layout, evidence, 'archive', 'after')
                storage.assert_called_with(vm.remote, 'guest')

    def test_download_through_owned_executor_and_with_the_captured_baseline(self):
        layout = install.path_layout('guest', 'install-01')
        now = '2026-11-21T17:44:00Z'
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            inv = plistlib.dumps({'images': [], 'framework': 'one', 'revision': '1'})
            vm = SimpleNamespace(remote=lambda *a, **k: SimpleNamespace(stdout=inv.decode()))
            product = SimpleNamespace(vm=vm, state={'run': 'verified-product-run'},
                                      job=lambda command, *, timeout: f'{timeout}s over the console: {command}')
            install.write_new(evidence/'preflight.json', {'createdAt': '2026-11-21T17:41:00Z'})
            with patch.object(install, 'now', return_value='2026-11-21T17:42:00Z'):
                baseline = install.record_baseline(vm, layout, evidence)
            install.write_new(evidence/'mount-baseline.json', baseline)
            args = SimpleNamespace(action='download', vm_config='config', run='install-01', gui=True,
                                   url='http://192.168.64.1/file.dmg', started_at='2026-11-21T17:43:00Z',
                                   finished_at='2026-11-21T17:43:50Z')

            def verify(reader, path, **kwargs):
                self.assertEqual(path, layout['download'])
                self.assertEqual(install.output(reader, 'shasum', timeout=120), '120s over the console: shasum')
                self.assertEqual(kwargs['expected_asset']['sha256'], install.DMG_SHA)
                return {'browser': 'Safari'}

            with (patch.object(install, 'now', return_value=now),
                  patch.object(install, 'product_executor', return_value=product),
                  patch.object(install, 'checked_case', return_value=layout),
                  patch.object(install, 'executor_session') as owned,
                  patch.object(install.files, 'verify_safari_download', side_effect=verify)):
                report = install.collect_case(args, vm, layout, evidence)
                owned.assert_called_once_with(product)
                self.assertEqual(report['observationSession']['runner'], product.state['run'])
                args.started_at = '2026-11-21T17:41:50Z'
                with self.assertRaisesRegex(ValueError, 'timestamps'):
                    install.collect_case(args, vm, layout, evidence)
                owned.assert_called_once()

    def test_case_lock_rejects_concurrent_actions(self):
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary).resolve()
            with install.case_lock(evidence), self.assertRaisesRegex(ValueError, 'using this'):
                with install.case_lock(evidence):
                    self.fail('The case lock was re-acquired')

    def test_download_executor_requires_the_matching_live_run_and_lock(self):
        with tempfile.TemporaryDirectory() as temporary:
            vm = SimpleNamespace(root='/Users/guest/utm-ui-isolation')
            expected = {'run': 'verified-product-run', 'lockIdentity': '17:4'}
            executor = SimpleNamespace(out=Path(temporary), vm=vm, state=expected)
            session = vm.root+'/package.ABCDEF01'
            install.write_new(executor.out/'launch.json', {'guestSession': session})
            with patch.object(install.guest, 'owned_guest_run', return_value=expected) as observe:
                self.assertEqual(install.executor_session(executor), session)
                observe.assert_called_once_with(vm, session)
                observe.return_value = {**expected, 'lockIdentity': '17:5'}
                with self.assertRaisesRegex(ValueError, 'owned case run'):
                    install.executor_session(executor)

            executor.state = {}

            def recover(product, launch_session, *, timeout):
                self.assertEqual((launch_session, timeout), (session, 2))
                product.state.update(expected)
                return True

            with (patch.object(install.guest, 'record_guest_run', side_effect=recover),
                  patch.object(install.guest, 'owned_guest_run', return_value=expected)):
                self.assertEqual(install.executor_session(executor), session)

    def test_product_runner_passes_the_download_reply_budget_to_ssh(self):
        product_class = install.guest.load(
            'installed_release_test_executor', 'apps/meshchan_app/tool/macos_vm/host.py').Product
        product = product_class.__new__(product_class)
        product.state = {'run': 'case'}
        sent = []

        def remote(script, **kwargs):
            sent.append((script, kwargs))
            return SimpleNamespace(stdout='observed\n')

        product.vm = SimpleNamespace(runpath=lambda run: '/guest/runs/'+run, remote=remote)
        self.assertEqual(product.job('/usr/bin/true'), 'observed\n')
        self.assertIn('{1..200}', sent[-1][0])
        self.assertEqual(sent[-1][1]['timeout'], 25)
        self.assertEqual(product.job('/usr/bin/true', timeout=120), 'observed\n')
        self.assertIn('{1..1200}', sent[-1][0])
        self.assertEqual(sent[-1][1]['timeout'], 125)

    def test_interrupted_executor_state_update_preserves_last_complete_state(self):
        product_class = install.guest.load(
            'installed_release_state_test_executor', 'apps/meshchan_app/tool/macos_vm/host.py').Product
        product = product_class.__new__(product_class)
        with tempfile.TemporaryDirectory() as temporary:
            product.out = Path(temporary)
            product.state_path = product.out/'session.json'
            product.state = {'run': 'original'}
            product.save()
            product.state = {'run': 'replacement'}
            with patch.object(Path, 'replace', side_effect=OSError('interrupted publication')):
                with self.assertRaises(OSError):
                    product.save()
            self.assertEqual(install.read_record(product.state_path), {'run': 'original'})
            self.assertEqual(list(product.out.iterdir()), [product.state_path])

    def test_executor_start_recovers_the_recorded_live_session_without_relaunch(self):
        with tempfile.TemporaryDirectory() as temporary:
            vm = SimpleNamespace(root='/Users/guest/utm-ui-isolation')
            expected = {'run': 'verified-product-run', 'lockIdentity': '17:4'}
            executor = SimpleNamespace(out=Path(temporary), vm=vm, state=expected)
            session = vm.root+'/package.ABCDEF01'
            install.write_new(executor.out/'launch.json', {'guestSession': session})
            with (patch.object(install.guest, 'owned_guest_run', return_value=expected) as owner,
                  patch.object(install.guest, 'start_guest') as start):
                report = install.launch_executor(executor)
            owner.assert_called_once_with(vm, session)
            start.assert_not_called()
            self.assertEqual(report, {'run': expected['run'], 'status': 'RUNNING'})

    def test_executor_finish_after_lost_response_confirms_original_exit_without_resending(self):
        with tempfile.TemporaryDirectory() as temporary:
            vm = SimpleNamespace(root='/Users/guest/utm-ui-isolation')
            expected = {'run': 'verified-product-run', 'lockIdentity': '17:4'}
            executor = SimpleNamespace(out=Path(temporary), vm=vm, state=expected)
            session = vm.root+'/package.ABCDEF01'
            install.write_new(executor.out/'launch.json', {'guestSession': session})
            with (patch.object(install.guest, 'owned_guest_run', side_effect=[expected, None]) as owner,
                  patch.object(install.guest, 'finish_guest',
                               side_effect=subprocess.TimeoutExpired('ssh', 10)) as finish,
                  patch.object(install.guest, 'confirm_guest_exit', return_value=0) as confirm):
                with self.assertRaisesRegex(ValueError, 'Download executor ownership run'):
                    install.finish_executor(executor, expected_run='another-product-run')
                owner.assert_not_called()
                with self.assertRaises(subprocess.TimeoutExpired):
                    install.finish_executor(executor)
                self.assertEqual(install.finish_executor(executor),
                                 {'run': expected['run'], 'status': 'PASS', 'exitCode': 0})
            self.assertEqual(owner.call_count, 2)
            finish.assert_called_once_with(executor, session)
            confirm.assert_called_once_with(executor)


class RuntimeTest(unittest.TestCase):
    def test_runtime_and_close_require_the_same_launch_streams(self):
        layout = install.path_layout('guest', 'first')
        vm = SimpleNamespace(root='/Users/guest/utm-ui-isolation', c={'user': 'guest'})
        session = vm.root+'/package.ABCDEF01'
        launch = {'status': 'REQUESTED', 'method': 'LaunchServices', 'arguments': [],
                  'app': layout['app'], 'guestSession': session,
                  'systemProtection': install.SYSTEM_PROTECTION}
        file = {'device': 7, 'inode': 91}
        open_files = (
            f'p93\nf1\ntREG\nD0x7\ni91\nn{session}/app.stdout\n'
            f'f2\ntREG\nD0x7\ni91\nn{session}/app.stderr\n'
        )
        live = {'pid': 93, 'app': layout['app'], 'openFiles': open_files}
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            with self.assertRaises(FileNotFoundError):
                install.observe_launched_runtime(vm, layout, evidence, 'reopen', 93)
            install.write_new(evidence/'launch-reopen.json', launch)
            with (patch.object(install, 'output', return_value='0\n'),
                  patch.object(install, 'runtime_observation', return_value=live) as runtime,
                  patch.object(install.files, 'guest_file_stamp', return_value=file)):
                observed = install.observe_launched_runtime(vm, layout, evidence, 'reopen', 93)
                self.assertEqual(observed['launchSha256'], install.digest(evidence/'launch-reopen.json'))
                runtime.return_value = {**live, 'openFiles': open_files.replace(session, vm.root+'/package.BAD00000')}
                with self.assertRaisesRegex(ValueError, 'outside the measured'):
                    install.observe_launched_runtime(vm, layout, evidence, 'reopen', 93)
            install.write_new(evidence/'runtime-reopen.json', observed)
            with (patch.object(install.guest, 'require_absent_pid'),
                  patch.object(install.files, 'guest_file_stamp', return_value={**file, 'inode': 92}),
                  patch.object(install, 'output') as read):
                with self.assertRaisesRegex(ValueError, 'vnode'):
                    install.capture_installed_close(vm, evidence, 'reopen')
                read.assert_not_called()
            (evidence/'launch-reopen.json').write_text(json.dumps({**launch, 'guestSession': vm.root+'/package.BAD00000'}))
            with self.assertRaisesRegex(ValueError, 'Runtime launch binding'):
                install.capture_installed_close(vm, evidence, 'reopen')

    def test_application_file_must_match_frozen_bytes_and_same_vnode(self):
        stamp = {'inode': 12345, 'device': 17}
        pin = 'a'*64
        with (patch.object(install.files, 'remote_text', return_value=pin+'  /app\n') as read,
              patch.object(install.files, 'guest_file_stamp', return_value=stamp) as observe):
            self.assertEqual(install.verify_installed_file(None, '/app', pin, stamp=stamp),
                             {**stamp, 'sha256': pin})
            with self.assertRaisesRegex(ValueError, 'frozen candidate'):
                install.verify_installed_file(None, '/app', 'b'*64, stamp=stamp)
            observe.return_value = {**stamp, 'inode': 12346}
            with self.assertRaisesRegex(ValueError, 'frozen candidate'):
                install.verify_installed_file(None, '/app', pin, stamp=stamp)
            read.assert_called_with(None, ['/usr/bin/shasum', '-a', '256', '/app'])

    def test_launch_checks_both_code_directories_and_runtime_files(self):
        app = '/Users/guest/Applications/Meshchan.app'
        with (patch.object(install.files, 'remote_text') as run,
              patch.object(install, 'verify_installed_file') as verify):
            install.verify_launch_app(None, app)
            self.assertIn('--all-architectures', run.call_args_list[0].args[1])
            for call, (arch, pin) in zip(run.call_args_list[1:], install.APP_CODE_PINS.items(), strict=True):
                self.assertIn(arch, call.args[1])
                self.assertIn(f'-R=identifier "{install.APP_IDENTIFIER}" and cdhash H"{pin}"', call.args[1])
            self.assertEqual([call.args[1:] for call in verify.call_args_list],
                             [(f'{app}/{name}', pin) for name, pin in install.APP_FILE_PINS.items()])

    def test_ordinary_argv_refuses_wrong_owner_copy_and_probes(self):
        app = '/Users/guest/Applications/Meshchan.app/Contents/MacOS/Meshchan'
        install.verify_runtime_argv(93, app, app, 501, 501)
        install.verify_runtime_argv(93, app, app+' -psn_0_123', 501, 501)
        for pid, argv, uid in [
            (True, app, 501),
            (93, app, 502),
            (93, app+' --data-dir=/private/tmp/copy', 501),
            (93, app+' --meshchan-runtime=write', 501),
            (93, '/owned/fixture/Meshchan.app/Contents/MacOS/Meshchan', 501),
        ]:
            with self.subTest(argv=argv), self.assertRaises(ValueError):
                install.verify_runtime_argv(pid, app, argv, uid, 501)

    def test_live_mappings_require_the_bound_pid_and_vnode(self):
        raw = 'p93\ncMeshchan\nftxt\ntREG\nD0x1000011\ni393861\nn/path/to/image\n\n'
        image, = install.live_vnodes(raw, 93)
        stamp = {'device': 16777233, 'inode': 393861}
        self.assertEqual(image['descriptor'], 'txt')
        self.assertEqual(image['n'], '/path/to/image')
        install.file_vnode(image, stamp)
        with self.assertRaises(ValueError):
            install.file_vnode(image, {**stamp, 'inode': 393862})
        with self.assertRaises(ValueError):
            install.live_vnodes(raw, 94)
        with self.assertRaises(ValueError):
            install.live_vnodes(raw+'p94\n', 93)

    def test_only_recognized_system_data_paths_can_accompany_text_mappings(self):
        metal = '/private/var/folders/x1/guest/C/org.meshchan.meshchan/com.apple.metal/32023/'
        self.assertIsNotNone(install.SYSTEM_MAPPED_DATA.fullmatch(metal+'libraries.data'))
        self.assertIsNone(install.SYSTEM_MAPPED_DATA.fullmatch(metal+'libsqlite3.dylib'))
        self.assertIsNone(install.SYSTEM_MAPPED_DATA.fullmatch('/opt/homebrew/lib/libsqlite3.dylib'))

    def test_launch_uses_only_the_exact_bundle_and_standard_streams(self):
        app = '/Users/guest/Applications/Meshchan.app'
        session = '/Users/guest/utm-ui-isolation/package.ABCDEF01'
        request = install.ordinary_open_command(app, session)
        self.assertIn('/usr/bin/open --stdout ', request)
        self.assertIn(f'--stderr {session}/app.stderr {app}', request)
        self.assertNotIn('--args', request)
        self.assertNotIn('/Contents/MacOS/', request)

    def test_launch_rechecks_protection_after_install_before_requesting_open(self):
        layout = install.path_layout('guest', 'measure')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with (patch.object(install, 'require_detached_case'),
                  patch.object(install, 'require_unmounted'),
                  patch.object(install, 'require_launch_milestones'),
                  patch.object(install, 'verify_launch_app'),
                  patch.object(install, 'output', side_effect=[
                      '', PROTECTION_INVENTORY.replace('assessments enabled', 'assessments disabled')]),
                  patch.object(install.guest, 'guest_session') as session):
                with self.assertRaisesRegex(ValueError, 'enabled Gatekeeper'):
                    install.request_open(None, layout, root, 'initial')
                session.assert_not_called()
                self.assertFalse((root/'launch-initial.json').exists())

    def test_measured_open_refuses_to_launch_until_cli_artifacts_are_present(self):
        layout = install.path_layout('guest', 'measure')
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            with (patch.object(install, 'require_detached_case'),
                  patch.object(install, 'require_unmounted'),
                  patch.object(install, 'read_case_network'),
                  patch.object(install, 'verify_case_close', return_value=({}, {}, {})),
                  patch.object(install, 'verify_case_cli_contention'),
                  patch.object(install.guest, 'guest_session') as session):
                with self.assertRaisesRegex(FileNotFoundError, 'cli-before.json'):
                    install.request_open(None, layout, evidence, 'initial')
                install.write_new(evidence/'cli-before.json', install.workflow.EMPTY_PUBLIC)
                with self.assertRaisesRegex(FileNotFoundError, 'cli-mapping.json'):
                    install.request_open(None, layout, evidence, 'initial')
                with self.assertRaisesRegex(FileNotFoundError, 'cli-after.json'):
                    install.request_open(None, layout, evidence, 'reopen')
                session.assert_not_called()
                self.assertFalse(any(evidence.glob('launch-*.json')))

    def test_cli_reads_cannot_be_backfilled_after_the_corresponding_launch(self):
        layout = install.path_layout('guest', 'measure')
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            for phase in ('initial', 'reopen'):
                install.write_new(evidence/f'launch-{phase}.json', {'status': 'REQUESTED'})
            with (patch.object(install, 'read_case_network'),
                  patch.object(install, 'require_no_app') as check_app):
                for label in ('before', 'mapping', 'after'):
                    with self.subTest(label=label), self.assertRaisesRegex(ValueError, 'before requesting'):
                        install.collect_cli(None, evidence, layout, label)
                check_app.assert_not_called()

    def test_initial_close_cannot_be_collected_without_its_live_cli_contention(self):
        vm = SimpleNamespace(root='/Users/guest/utm-ui-isolation', c={'user': 'guest'})
        session = vm.root+'/package.ABCDEF01'
        layout = install.path_layout('guest', 'measure')
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            launch = evidence/'launch-initial.json'
            install.write_new(launch, {'status': 'REQUESTED', 'method': 'LaunchServices', 'arguments': [],
                                       'guestSession': session, 'app': layout['app'],
                                       'systemProtection': install.SYSTEM_PROTECTION})
            install.write_new(evidence/'runtime-initial.json',
                              {'pid': 40, 'app': layout['app'], 'guestSession': session,
                               'launchSha256': install.digest(launch)})
            with patch.object(install, 'capture_shutdown') as capture:
                with self.assertRaisesRegex(FileNotFoundError, 'cli-busy.json'):
                    install.capture_installed_close(vm, evidence, 'initial')
                capture.assert_not_called()

    def test_launch_requires_exact_detached_case_and_inventory(self):
        paths = install.path_layout('guest', 'upgrade-01')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            mounted, before_pin, mount_pin = record_bound_mount(root, paths)
            install.write_new(root/'install-before.json', {
                'imageManifestSha256': install.inputs.CANDIDATE_PINS['image_payload'],
                'mountSha256': mount_pin,
                'systemProtection': install.SYSTEM_PROTECTION,
                'layout': {'app': paths['app'], 'cli': paths['cli'], 'volumeMaterials': paths['product']},
            })
            detached = root/'detach.json'
            valid = {'status': 'PASS', 'attachment': mounted['attachment'],
                     'beforeSha256': before_pin, 'mountSha256': mount_pin}
            for wrong in ({'status': 'FAIL'}, {'attachment': {'path': paths['download'], 'imageProcessPid': 35}},
                          {'mountSha256': 'wrong'}):
                with self.subTest(wrong=wrong), self.assertRaises(ValueError):
                    detached.write_text(json.dumps({**valid, **wrong}))
                    install.require_detached_case(root, paths)
            detached.write_text(json.dumps(valid))
            install.require_detached_case(root, paths)


class CompareCaseTest(unittest.TestCase):
    def test_network_evidence_cannot_be_used_under_the_other_label(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            install.write_new(root/'network-after.json', {'label': 'before', 'status': 'PASS'})
            with patch.object(install.checks, 'require_offline') as offline:
                with self.assertRaisesRegex(ValueError, 'Case network observation label'):
                    install.read_case_network(root, 'after')
                offline.assert_not_called()

    def test_close_evidence_binds_to_its_launch_and_reopens_the_archived_snapshot(self):
        layout = install.path_layout('guest', 'measure')
        vm = SimpleNamespace(root='/Users/guest/utm-ui-isolation')
        session = vm.root+'/package.ABCDEF01'
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            launch = root/'launch-initial.json'
            install.write_new(launch, {'status': 'REQUESTED', 'method': 'LaunchServices', 'arguments': [],
                                       'guestSession': session, 'app': layout['app'],
                                       'systemProtection': install.SYSTEM_PROTECTION})
            binding = {'guestSession': session, 'launchSha256': install.digest(launch)}
            runtime = {'app': layout['app'], 'dataDirectory': layout['data'], 'pid': 40, **binding}
            install.write_new(root/'runtime-initial.json', runtime)
            closed = {'status': 'PASS', 'pid': 40, 'shutdown': {}, 'snapshot': {'files': {}}, **binding}
            receipt = root/'closed-initial.json'
            receipt.write_text(json.dumps(closed))
            with (patch.object(install.beta, 'verify_shutdown'),
                  patch.object(install.beta, 'verify_archived_snapshot', return_value={'database': {}}) as verify):
                self.assertEqual(install.verify_case_close(vm, layout, root, 'initial'), (runtime, closed, {}))
                verify.assert_called_once_with(root/'closed-initial', closed['snapshot'])
                receipt.write_text(json.dumps({**closed, 'pid': 41}))
                with self.assertRaisesRegex(ValueError, 'Case App shutdown pid'):
                    install.verify_case_close(vm, layout, root, 'initial')
                verify.assert_called_once()

    def test_compare_refuses_reused_or_misordered_observations(self):
        layout = install.path_layout('guest', 'measure')
        before = install.files.parse_time('2026-11-21T17:40:00Z')
        after = install.files.parse_time('2026-11-21T17:45:00Z')
        initial = ({'time': '2026-11-21T17:41:00Z'},
                   {'guestSession': '/first', 'capturedAt': '2026-11-21T17:42:00Z'}, {})
        reopened = ({'time': '2026-11-21T17:43:00Z'},
                    {'guestSession': '/second', 'capturedAt': '2026-11-21T17:44:00Z'}, {})
        with (patch.object(install, 'require_detached_case', return_value={'capturedAt': before.isoformat()}),
              patch.object(install, 'read_case_network', side_effect=[before, after, before, after]),
              patch.object(install, 'verify_case_close', side_effect=[
                  initial, (reopened[0], {**reopened[1], 'guestSession': '/first'}, {}),
                  initial, ({'time': '2026-11-21T17:41:30Z'}, *reopened[1:]),
              ])):
            with self.assertRaisesRegex(ValueError, 'two ordinary launches'):
                install.compare_evidence(None, layout, None, title='', body='', history_limit=1002,
                                         beta_case=False)
            with self.assertRaisesRegex(ValueError, 'two ordinary launches'):
                install.compare_evidence(None, layout, None, title='', body='', history_limit=1002,
                                         beta_case=False)


if __name__ == '__main__':
    unittest.main()
