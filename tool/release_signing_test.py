import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import tempfile
import unittest
from unittest import mock

import release_signing as signing


TEAM = 'M3SHCH4N01'
FINGERPRINT = 'A'*40


def mach_o(kind, *, payload=b'unchanged loader payload', signature=b'new-signature',
           cpu=0x0100000c, subtype=0):
    """An inspectable shape fixture. It does not have a valid code signature."""
    signature_blob = struct.pack('>III', 0xfade0cc0, 12+len(signature), 0)+signature
    file_offset = 128
    signature_offset = file_offset+len(payload)
    file_size = len(payload)+len(signature_blob)
    header = struct.pack('<IiiIIIII', 0xfeedfacf, cpu, subtype, kind, 2, 88, 0, 0)
    linkedit = struct.pack('<II16sQQQQiiII', 0x19, 72, b'__LINKEDIT', 0, 0x4000,
                           file_offset, file_size, 1, 1, 0, 0)
    sig = struct.pack('<IIII', 0x1d, 16, signature_offset, len(signature_blob))
    return (header+linkedit+sig).ljust(file_offset, b'\0')+payload+signature_blob


def universal_library():
    x64 = mach_o(signing.MH_DYLIB, cpu=0x01000007, subtype=3)
    arm64 = mach_o(signing.MH_DYLIB)
    entries = struct.pack('>iiIII', 0x01000007, 3, 0x4000, len(x64), 14)
    entries += struct.pack('>iiIII', 0x0100000c, 0, 0x8000, len(arm64), 14)
    header = struct.pack('>II', 0xcafebabe, 2)+entries
    return (header.ljust(0x4000, b'\0')+x64).ljust(0x8000, b'\0')+arm64


class SigningPolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.policy = signing.load_policy(signing.DEFAULT_POLICY)

    def product(self, name='source'):
        root = self.root/name
        for item in self.policy:
            binary = root/item.binary
            binary.parent.mkdir(parents=True, exist_ok=True)
            binary.write_bytes(mach_o(signing.MH_EXECUTE if item.runtime else signing.MH_DYLIB))
            binary.chmod(0o755)
            if item.seal:
                seal = root/item.seal
                seal.parent.mkdir(parents=True)
                seal.write_bytes(b'test seal')
                manifest = (root/item.path/'Contents/Info.plist' if item.role == 'app'
                            else binary.parent/'Resources/Info.plist')
                manifest.parent.mkdir(parents=True, exist_ok=True)
                manifest.write_bytes(plistlib.dumps({
                    'CFBundleIdentifier': item.identifier,
                    'CFBundleExecutable': binary.name,
                }))
            if item.role == 'framework':
                (root/item.path/'Versions/Current').symlink_to(item.version)
        (root/'Meshchan.app/Contents/ordinary-resource.txt').write_text('baseline')
        return root

    def test_orders_strict_known_graph_and_main_flags(self):
        root = self.product()

        def check_entitlements(name, argv):
            if '--entitlements' in argv:
                plist = argv[argv.index('--entitlements')+1]
                self.assertEqual(plistlib.loads(plist.read_bytes()), {signing.CLI_UNSIGNED_MEMORY: True})

        command = mock.MagicMock(side_effect=check_entitlements)
        signing.sign_products(root, self.policy, {'sha1': FINGERPRINT, 'team': TEAM}, command)
        graph = signing.discover_code(root, self.policy)
        self.assertEqual(len(graph), 8)
        self.assertEqual([item['role'] for item in graph],
                         ['framework']*4+['app', 'cliLibrary', 'cliLibrary', 'cli'])
        self.assertEqual(command.call_count, len(graph))
        for item, recorded in zip(graph, command.call_args_list, strict=True):
            _, argv = recorded.args
            self.assertEqual(argv[-1], root/item['path'])
            self.assertIn('--timestamp', argv)
            self.assertNotIn('--deep', argv)
            self.assertEqual('--options' in argv, item['runtime'])
            self.assertEqual('--entitlements' in argv, item['role'] == 'cli')

    def test_unclassified_mach_o_and_executable_are_rejected(self):
        root = self.product()
        resource = root/'Meshchan.app/Contents/unclassified'
        resource.write_bytes(mach_o(signing.MH_DYLIB))
        with self.assertRaisesRegex(ValueError, 'Unexpected code binaries'):
            signing.discover_code(root, self.policy)
        resource.write_bytes(b'#!/bin/sh\n')
        resource.chmod(0o755)
        with self.assertRaisesRegex(ValueError, 'Unclassified executable'):
            signing.discover_code(root, self.policy)

    def test_main_executable_requires_execute_permission(self):
        root = self.product()
        (root/self.policy[-1].binary).chmod(0o644)
        with self.assertRaisesRegex(ValueError, 'lack.*execute permission'):
            signing.discover_code(root, self.policy)

    def test_policy_cannot_permit_debug_entitlements_or_outer_first(self):
        policy = json.loads(signing.DEFAULT_POLICY.read_bytes())
        path = self.root/'policy.json'
        policy['codeItems'][-1]['entitlements']['com.apple.security.get-task-allow'] = True
        path.write_text(json.dumps(policy))
        with self.assertRaisesRegex(ValueError, 'exact entitlements'):
            signing.load_policy(path)
        policy['codeItems'][-1]['entitlements'] = {signing.CLI_UNSIGNED_MEMORY: 1}
        path.write_text(json.dumps(policy))
        with self.assertRaisesRegex(ValueError, 'exact entitlements'):
            signing.load_policy(path)
        policy['codeItems'][-1]['entitlements'] = {signing.CLI_UNSIGNED_MEMORY: True}
        policy['codeItems'].insert(0, policy['codeItems'].pop(4))
        path.write_text(json.dumps(policy))
        with self.assertRaisesRegex(ValueError, 'order nested frameworks'):
            signing.load_policy(path)

    def test_owned_copy_and_bounded_transformation(self):
        original = self.product()
        candidate = self.root/'owned relocated candidate'
        shutil.copytree(original, candidate, symlinks=True)
        main = next(item for item in self.policy if item.role == 'app')
        (candidate/main.binary).write_bytes(mach_o(signing.MH_EXECUTE, signature=b'timestamped-signature'))
        (candidate/main.seal).write_bytes(b'updated seal')
        report = signing.verify_transform(original, candidate, self.policy)
        self.assertEqual({change['path'] for change in report['changedFiles']}, {main.binary, main.seal})
        (candidate/main.binary).write_bytes(mach_o(signing.MH_EXECUTE, payload=b'different loader payload'))
        with self.assertRaisesRegex(ValueError, 'Non-signature Mach-O'):
            signing.verify_transform(original, candidate, self.policy)

    def test_library_replacement_requires_payload_change_not_just_signature_change(self):
        original = self.product()
        candidate = self.root/'replacement'
        shutil.copytree(original, candidate, symlinks=True)
        library = self.policy[0].binary
        (candidate/library).write_bytes(mach_o(signing.MH_DYLIB, signature=b'only a new signature'))
        with self.assertRaisesRegex(ValueError, 'replacement library payload did not change'):
            signing.verify_transform(original, candidate, self.policy, replacements=[library])
        (candidate/library).write_bytes(mach_o(signing.MH_DYLIB, payload=b'modified library'))
        report = signing.verify_transform(original, candidate, self.policy, replacements=[library])
        self.assertEqual(report['replacementLibraries'], [library])

    def test_library_replacement_requires_the_original_architecture_set(self):
        original = self.product()
        library = self.policy[0].binary
        (original/library).write_bytes(universal_library())
        candidate = self.root/'replacement'
        shutil.copytree(original, candidate, symlinks=True)
        (candidate/library).write_bytes(mach_o(signing.MH_DYLIB, payload=b'modified library'))
        with self.assertRaisesRegex(ValueError, 'Replacement library architecture set changed'):
            signing.verify_transform(original, candidate, self.policy, replacements=[library])

    def test_non_signature_resource_mode_link_and_metadata_changes_are_rejected(self):
        original = self.product()
        for mode in ('resource', 'mode', 'link'):
            with self.subTest(mode=mode):
                candidate = self.root/('candidate-'+mode)
                shutil.copytree(original, candidate, symlinks=True)
                resource = candidate/'Meshchan.app/Contents/ordinary-resource.txt'
                if mode == 'resource':
                    resource.write_bytes(b'changed')
                elif mode == 'mode':
                    resource.chmod(0o600)
                else:
                    link = candidate/self.policy[0].path/'Versions/Current'
                    link.unlink()
                    link.symlink_to('./A')
                with self.assertRaisesRegex(ValueError, 'Non-signature product inventory'):
                    signing.verify_transform(original, candidate, self.policy)

    def test_signing_failure_stops_at_current_child_and_shared_files_are_rejected(self):
        root = self.product()
        command = mock.MagicMock(side_effect=[None, subprocess.CalledProcessError(1, ['codesign'])])
        with self.assertRaises(subprocess.CalledProcessError):
            signing.sign_products(root, self.policy, {'sha1': FINGERPRINT, 'team': TEAM}, command)
        self.assertEqual(command.call_count, 2)
        (self.root/'external-shared-file').hardlink_to(root/self.policy[0].binary)
        command.reset_mock()
        with self.assertRaisesRegex(ValueError, 'shared hard links'):
            signing.sign_products(root, self.policy, {'sha1': FINGERPRINT, 'team': TEAM}, command)
        command.assert_not_called()

    def test_identity_must_be_exact_valid_developer_id(self):
        command = mock.MagicMock(return_value='     0 valid identities found\n')
        with self.assertRaises(signing.IdentityUnavailable):
            signing.select_identity(FINGERPRINT, TEAM, command)
        command.reset_mock()
        with self.assertRaisesRegex(ValueError, 'exact 40-character'):
            signing.select_identity('Developer ID Application', TEAM, command)
        command.assert_not_called()
        command.return_value = f'  1) {FINGERPRINT} "Apple Development: example ({TEAM})"\n'
        with self.assertRaisesRegex(ValueError, 'not a Developer ID'):
            signing.select_identity(FINGERPRINT, TEAM, command)

    def test_signature_validation_rejects_privileges_runtime_team_and_unsigned_time(self):
        item = next(item for item in self.policy if item.role == 'app')
        authority = f'Developer ID Application: Test Person ({TEAM})'
        baseline = {'identifier': item.identifier, 'team': TEAM, 'adhoc': False,
                    'authorityChain': [authority], 'timestamp': '20 Nov 2026 at 20:00:00',
                    'runtime': True, 'entitlements': {}}
        signing.verify_signature_values(item, {'team': TEAM}, baseline)
        variants = ({'team': 'WRONGTEAM1'}, {'adhoc': True}, {'runtime': False}, {'timestamp': None},
                    {'entitlements': {'com.apple.security.get-task-allow': True}},
                    {'entitlements': {'com.apple.security.cs.disable-library-validation': True}},
                    {'entitlements': {signing.CLI_UNSIGNED_MEMORY: True}})
        for changed in variants:
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                signing.verify_signature_values(item, {'team': TEAM}, {**baseline, **changed})
        with self.assertRaisesRegex(ValueError, 'runtime or entitlements'):
            signing.verify_signature_values(self.policy[0], {'team': TEAM}, {
                **baseline, 'identifier': self.policy[0].identifier, 'runtime': False,
                'entitlements': {'com.apple.security.cs.allow-jit': True},
            })
        cli = self.policy[-1]
        hardened_cli = {**baseline, 'identifier': cli.identifier, 'entitlements': cli.entitlements}
        signing.verify_signature_values(cli, {'team': TEAM}, hardened_cli)
        with self.assertRaisesRegex(ValueError, 'runtime or entitlements'):
            signing.verify_signature_values(cli, {'team': TEAM}, {**hardened_cli, 'entitlements': {}})

    def test_signature_display_rejects_other_or_unobservable_slots(self):
        root = self.product()
        item = self.policy[-1]
        header = f'Executable={root/item.binary}\n'
        for slot, total, message in ((1, 2, 'one embedded signature'), (2, 1, 'one embedded signature'),
                                     (None, None, 'Total signatures')):
            with self.subTest(slot=slot, total=total):
                output = header
                if total is not None:
                    output += f'Total signatures={total}\nChosen signature={slot}\n'
                command = mock.MagicMock(return_value=output)
                with self.assertRaisesRegex(ValueError, message):
                    signing.display_signature(root, item, 'arm64', command, 'display')
                command.assert_called_once()

    def test_verify_checks_each_actual_item_against_apple_requirement_and_leaf_pin(self):
        root = self.product()
        leaf = b'test public certificate bytes'
        fingerprint = hashlib.sha1(leaf).hexdigest().upper()
        seen = []

        def command(name, argv, cwd=None, *, return_stderr=False):
            seen.append((name, argv))
            certificate_prefix = next((value.partition('=')[2] for value in argv
                                       if str(value).startswith('--extract-certificates=')), None)
            if certificate_prefix:
                Path(certificate_prefix+'0').write_bytes(leaf)
            if name.endswith('-certificate-details'):
                return f'subject=\n    OU={TEAM}\nissuer=\nnotBefore=earlier\nnotAfter=later\n {signing.LEAF_OID}:'
            if name.endswith('-display') or name.endswith('-entitlements'):
                item = next(item for item in self.policy if argv[-1] == root/item.path)
                if name.endswith('-entitlements'):
                    return plistlib.dumps(item.entitlements).decode() if item.entitlements else ''
                flags = '0x10000(runtime)' if item.runtime else '0x0(none)'
                return '\n'.join((f'Executable={root/item.binary}', f'Identifier={item.identifier}',
                                  f'CodeDirectory v=20500 size=567 flags={flags} location=embedded',
                                  f'TeamIdentifier={TEAM}', f'CDHash={"b"*40}',
                                  f'Authority=Developer ID Application: Test ({TEAM})',
                                  'Total signatures=1', 'Chosen signature=1',
                                  'Timestamp=20 Nov 2026 at 22:00:00'))
            return ''

        report = signing.verify_signatures(root, self.policy, {'sha1': fingerprint, 'team': TEAM},
                                           command, self.root)
        self.assertEqual(len(report), len(self.policy))
        requirements = [argv for name, argv in seen if name.endswith('-requirement')]
        self.assertEqual(len(requirements), len(self.policy))
        self.assertTrue(all('--all-architectures' in argv and signing.ISSUER_OID in argv[-2]
                            and signing.LEAF_OID in argv[-2] and argv[-2].startswith('=anchor apple generic')
                            and f'certificate leaf = H"{fingerprint}"' in argv[-2]
                            for argv in requirements))
        self.assertEqual(report[0]['slices']['arm64']['leafCertificate']['sha1'], fingerprint)
        self.assertEqual(report[0]['slices']['arm64']['signatureSlots'], 1)
        with self.assertRaisesRegex(ValueError, 'leaf certificate does not match'):
            signing.verify_signatures(root, self.policy, {'sha1': FINGERPRINT, 'team': TEAM},
                                      command, self.root)


if __name__ == '__main__':
    unittest.main()
