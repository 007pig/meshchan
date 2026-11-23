"""Targeted acceptance failures and offline evidence resolution for Phase 1E.8."""
from contextlib import closing
import json
from pathlib import Path
import plistlib
import sqlite3
import tempfile
import unittest

import package_dmg as dmg
import release_retention_inputs as retention
import release_signed_runtime as runtime
from release_materials import encoded, product_inventory, sha
from release_retention_archive import scanned_input


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='Retained evidence ')
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.original = Path('/previous owned workspace')
        self.lookups = []

    def locate(self, original):
        self.lookups.append(original)
        return self.root/original.relative_to(self.original)

    def write(self, original, raw):
        target = self.locate(original)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
        return sha(raw)

    def test_pinned_bytes_are_checked_before_parsing(self):
        reader = retention.RetainedRead(self.locate, live=False)
        receipt = self.original/'acceptance.json'
        correct = self.write(receipt, b'{"status":"PASS"}')
        self.write(receipt, b'{"status":"PASS","status":"FAIL"}')
        ref = {'path': 'acceptance.json', 'sha256': correct}
        with self.assertRaisesRegex(ValueError, 'SHA-256'):
            reader.report(self.original, ref, receipt)
        ref['sha256'] = sha(b'{"status":"PASS","status":"FAIL"}')
        with self.assertRaisesRegex(ValueError, '[Dd]uplicate'):
            reader.report(self.original, ref, receipt)

    def test_create_or_sign_is_not_independent_acceptance(self):
        info = {'identity': {'appBuild': '8', 'productVersion': '0.1.0-rc.1', 'target': 'macos-arm64'}}
        _, filename, _ = dmg.volume_names(info)
        asset = self.original/'create'/filename
        acceptance = self.original/'check/dmg-acceptance.json'
        for command, status in (('create', 'CREATED'), ('sign', 'SIGNED'), ('check', 'RUNNING')):
            with self.subTest(command=command, status=status):
                digest = self.write(acceptance, encoded({'formatVersion': 1, 'command': command, 'status': status}))
                reader = retention.RetainedRead(self.locate, live=False)
                with self.assertRaisesRegex(ValueError, 'independent DMG acceptance'):
                    retention.accepted_image(reader, {'dmg': (asset, '0'*64), 'dmg_acceptance': (acceptance, digest)},
                                             info, {})
                self.assertNotIn(asset, self.lookups)

    def test_historical_image_structure_binds_the_image_and_checksum_logs(self):
        image = str(self.original/'release image.dmg')
        info = {'Format': retention.disk.IMAGE_FORMAT, 'Format Description': retention.disk.IMAGE_TYPE,
                'Class Name': 'CUDIFDiskImage', 'Properties': {'Checksummed': True, 'Compressed': True,
                                                             'Encrypted': False},
                'partitions': {'partitions': [{'partition-filesystems': {retention.disk.FILESYSTEM: ''}}]}}
        crc = {'Checksum Type': 'CRC32', 'Checksum Value': '$0012ABCD'}
        verification = {'expected': crc, 'calculated': crc}
        logs = {'image-info': {'log': plistlib.dumps(info)}, 'verify-image': {'log': plistlib.dumps(verification)},
                'inspect-container-signature': {'stderrLog': f'{image}: code object is not signed at all\n'.encode()}}
        ledger = {'steps': [
            {'name': 'image-info', 'argv': [retention.disk.HDIUTIL, 'imageinfo', '-plist', image]},
            {'name': 'verify-image', 'argv': [retention.disk.HDIUTIL, 'verify', '-plist', image]},
            {'name': 'inspect-container-signature', 'argv': ['/usr/bin/codesign', '--display', image]},
        ]}
        receipt = {'checksum': crc}
        retention.verify_image_structure(ledger, logs, image, receipt)
        other_crc = crc | {'Checksum Value': '$DEADBEEF'}
        with self.assertRaisesRegex(ValueError, 'receipt checksum differs'):
            retention.verify_image_structure(ledger, logs, image, {'checksum': other_crc})
        changes = (
            ('image-info', {'log': plistlib.dumps(info | {'Format': 'UDRW'})}),
            ('verify-image', {'log': plistlib.dumps(verification | {'calculated': other_crc})}),
            ('inspect-container-signature', {'stderrLog': b'/other.dmg: code object is not signed at all\n'}),
        )
        for name, output in changes:
            with self.subTest(step=name), self.assertRaises(ValueError):
                retention.verify_image_structure(ledger, logs | {name: output}, image, receipt)
        ledger['steps'][1]['argv'][-1] = '/other.dmg'
        with self.assertRaisesRegex(ValueError, 'structure process verify-image argv differs'):
            retention.verify_image_structure(ledger, logs, image, receipt)

    def test_historical_image_volume_requires_read_only_flags_and_matching_identity(self):
        mount = {'mountPoint': str(self.original/'readonly volume'), 'name': 'Release image',
                 'wholeDevice': '/dev/disk20', 'volumeDevice': '/dev/disk20s1',
                 'volumeUuid': '485590BA-3872-403A-BFF7-13D2FACCFBAC',
                 'volumeRoot': {'globalPermissionsEnabled': False}}
        receipt = {'BusProtocol': 'Disk Image', 'DeviceNode': mount['volumeDevice'], 'ParentWholeDisk': 'disk20',
                   'MountPoint': mount['mountPoint'], 'FilesystemType': 'hfs',
                   'FilesystemName': retention.disk.FILESYSTEM, 'VolumeName': mount['name'],
                   'VolumeUUID': mount['volumeUuid'], 'Writable': False, 'WritableVolume': False,
                   'WritableMedia': False, 'GlobalPermissionsEnabled': False}
        ledger = {'steps': [{'name': 'volume-info',
                             'argv': [retention.disk.DISKUTIL, 'info', '-plist', mount['mountPoint']]}]}

        def logs(observation):
            return {'volume-info': {'log': plistlib.dumps(observation)}}

        retention.verify_image_volume(ledger, logs(receipt), mount)
        for field, value in (('Writable', True), ('WritableVolume', True), ('WritableMedia', True),
                             ('DeviceNode', '/dev/disk30s1'), ('GlobalPermissionsEnabled', 0),
                             ('VolumeUUID', 'ED0A090B-69C6-4DC8-BD88-051B65E0D1A0')):
            with self.subTest(field=field), self.assertRaises(ValueError):
                retention.verify_image_volume(ledger, logs(receipt | {field: value}), mount)

    def test_historical_image_codesign_binds_the_commands_and_signature_outputs(self):
        candidate = self.original/'extracted product'
        policy = retention.release_signing
        framework = 'Meshchan.app/Contents/Frameworks/App.framework'
        binary = framework+'/Versions/A/App'
        item = policy.CodeItem(framework, binary, 'framework', 'org.meshchan.app', False, 'A', dmg.PROFILE)
        target = str(candidate/framework)
        name = 'verify-01-framework-arm64'
        codesign = '/usr/bin/codesign'
        verify = [codesign, '--verify', '--strict', '--all-architectures', '--verbose=2']
        display = [codesign, '--display', '--architecture', 'arm64', '--bundle-version', 'A']
        ledger = {'steps': [
            {'name': 'verify-app-nested', 'argv': [*verify, '--deep', str(candidate/'Meshchan.app')]},
            {'name': 'verify-01-framework-requirement', 'argv': [*verify, '--bundle-version', 'A', target]},
            {'name': name+'-display', 'argv': [*display, '--verbose=4', target]},
            {'name': name+'-entitlements', 'argv': [*display, '--entitlements', '-', '--xml', target]},
        ]}
        cdhash = '1'*40
        fields = (
            f'Executable={candidate/binary}', 'Total signatures=1', 'Chosen signature=1', 'Signature=adhoc',
            'CodeDirectory v=20400 flags=0x2(adhoc) location=embedded', f'CDHash={cdhash}',
            f'Identifier={item.identifier}', 'TeamIdentifier=not set',
        )
        stderr = ('\n'.join(fields)+'\n').encode()
        logs = {name+'-display': {'stderrLog': stderr}, name+'-entitlements': {'log': b''}}
        signature = {
            'identity': policy.local_identity(),
            'order': [{**item.record(), 'architectures': ['arm64']}],
            'items': [{**item.record(), 'slices': {
                'arm64': {'identifier': item.identifier, 'team': None, 'authorityChain': [], 'timestamp': None,
                          'signatureSlots': 1, 'flags': 2, 'runtime': False, 'adhoc': True,
                          'cdhash': cdhash, 'entitlements': {}},
            }}],
        }
        retention.verify_image_signatures(ledger, logs, candidate, signature, (item,))

        for original, replacement in ((str(candidate/binary).encode(), b'/other/executable'),
                                      (cdhash.encode(), b'2'*40),
                                      (b'flags=0x2', b'flags=0x10002')):
            bad_logs = logs | {name+'-display': {'stderrLog': stderr.replace(original, replacement)}}
            with self.subTest(replacement=replacement), self.assertRaises(ValueError):
                retention.verify_image_signatures(ledger, bad_logs, candidate, signature, (item,))
        entitlements = {'log': plistlib.dumps({'com.apple.security.get-task-allow': True})}
        with self.assertRaisesRegex(ValueError, 'Embedded runtime or entitlements'):
            retention.verify_image_signatures(ledger, logs | {name+'-entitlements': entitlements},
                                              candidate, signature, (item,))
        ledger['steps'][2]['argv'][3] = 'x86_64'
        with self.assertRaisesRegex(ValueError, 'Historical codesign invocation .* argv differs'):
            retention.verify_image_signatures(ledger, logs, candidate, signature, (item,))

    def test_evidence_references_reject_aliases_and_scope_escape(self):
        reader = retention.RetainedRead(self.locate, live=False)
        target = self.original/'owned/evidence.json'
        for alias in ('../evidence.json', './owned/evidence.json', 'owned//evidence.json',
                      str(self.original/'other/evidence.json')):
            with self.subTest(alias=alias):
                with self.assertRaises(ValueError):
                    reader.reference(self.original, {'path': alias, 'sha256': '0'*64}, target,
                                     scope=self.original/'owned')
        self.assertEqual(self.lookups, [])

    def test_locator_cannot_follow_aliased_evidence_ancestor(self):
        original = self.original/'alias/local.json'
        (self.root/'alias').symlink_to('/unavailable original checkout')
        reader = retention.RetainedRead(self.locate, live=False)
        with self.assertRaisesRegex(ValueError, 'Aliased evidence ancestor'):
            reader.bytes(original, '0'*64)

    def test_historical_tool_identity_checks_presence_bytes_and_mode(self):
        name = 'tool/old_snapshot.py'
        origin = self.original/'source'
        path = origin/name
        pin = self.write(path, b'historical data')
        target = self.locate(path)
        target.chmod(0o600)
        tool = {
            'gitCommit': 'a'*40, 'workingTree': [],
            'inputs': {name: {'type': 'file', 'size': len(b'historical data'), 'mode': 0o600, 'sha256': pin}},
        }
        reader = retention.RetainedRead(self.locate, live=False)
        retention.verify_tool_snapshot(reader, origin, tool, [name])
        entry = tool['inputs'][name]
        for field in entry:
            with self.subTest(missing=field):
                tool['inputs'][name] = {key: value for key, value in entry.items() if key != field}
                with self.assertRaisesRegex(ValueError, 'Incomplete engineering tool file identity'):
                    retention.verify_tool_snapshot(reader, origin, tool, [name])
        tool['inputs'][name] = entry
        target.chmod(0o644)
        with self.assertRaisesRegex(ValueError, 'mode differs'):
            retention.verify_tool_snapshot(reader, origin, tool, [name])
        target.chmod(0o600)
        target.write_bytes(b'changed snapshot')
        with self.assertRaisesRegex(ValueError, 'size differs|sha256 differs'):
            retention.verify_tool_snapshot(reader, origin, tool, [name])
        target.unlink()
        with self.assertRaises(FileNotFoundError):
            retention.verify_tool_snapshot(reader, origin, tool, [name])

    def fixture_replacement(self):
        signed_root = self.original/'signed'
        workspace = self.original/'user modified products'
        evidence = workspace/'evidence'
        guest = evidence/'app-vm'
        receipt_path = evidence/'replacement-receipt.json'
        modified = workspace/'user products'
        source = 'materials/source-materials/archives/serial.tar.gz'
        source_pin = self.write(signed_root/source, b'archive')
        self.write(evidence/'libserialport-source.tar.gz', b'archive')
        source_root = evidence/'libserialport-source'
        patched = source_root/retention.SOURCE_FILES[0]
        patched_pin = self.write(patched, b'patched source')
        app_library = source_root/'app-library.dylib'
        cli_library = source_root/'cli-library.dylib'
        app_pin = self.write(app_library, b'rebuilt App library')
        cli_pin = self.write(cli_library, b'rebuilt CLI library')
        self.write(modified/'replacement.dylib', b'rebuilt library')
        for path in ('user-app.entitlements', 'user-cli.entitlements', 'app-vm/Release/fixture/meshchan.sqlite',
                     'app-vm/Release/fixture/.meshchan.owner.lock', 'app-vm/Release/app-supervisor.log'):
            self.write(evidence/path, b'replacement evidence')
        required = ('session.json', 'refresh-state.json', 'Release/app.stdout', 'Release/app.stderr',
                    'Release/app.pid', 'Release/app.exit', 'Release/synthetic-ports.png')
        app_refs = {name: self.write(guest/name, b'evidence') for name in required}
        self.locate(guest/'Release/app-launch.claim').symlink_to('ephemeral-executor:claim')
        cli = {'status': 'PASS', 'exitCode': 0}
        for key, name in (('log', 'evidence/logs/modified.log'), ('stderrLog', 'evidence/logs/modified.stderr.log'),
                          ('pidReceipt', 'cli working directory/child.pid')):
            cli[key] = name
            cli[key+'Sha256'] = self.write(workspace/name, b'process')
        inventory, _ = scanned_input(self.locate(modified))
        report = {
            'formatVersion': 2, 'signingProfile': dmg.PROFILE, 'status': 'PASS', 'signedInfoSha256': 'a'*64,
            'signedRoot': str(signed_root), 'identity': {}, 'finalIntegrity': 'PASS', 'cli': cli,
            'app': {'status': 'PASS', 'exitCode': 0, 'guestExecutorExit': 0, 'guestLockReleased': True,
                    'pidAbsent': True, 'evidence': app_refs},
            'modifiedInventorySha256': sha(encoded(inventory)),
            'sourceArchive': {'materialsManifestSha256': 'b'*64, 'sha256': source_pin, 'path': source, 'size': 7},
            'replacement': {'patch': {'patchedSourceSha256': patched_pin}, 'libraries': {
                retention.APP_LIBRARY: {'path': retention.APP_LIBRARY, 'rebuiltSha256': app_pin},
                retention.CLI_LIBRARY: {'path': retention.CLI_LIBRARY, 'rebuiltSha256': cli_pin},
            }},
            'steps': [{'name': 'modified', 'exitCode': 0, 'processTree': {'exited': True, 'childReaped': True},
                       **{key: cli[key] for key in ('log', 'logSha256', 'stderrLog', 'stderrLogSha256')}}],
        }
        pin = self.write(receipt_path, encoded(report))
        receipt = {'modifiedLibraryReport': {'path': 'evidence/replacement-receipt.json', 'sha256': pin}}
        result = {'status': 'PASS', 'signingProfile': dmg.PROFILE, 'receipt': str(receipt_path), 'receiptSha256': pin}
        info = {'identity': {}, 'upstream': {'materialsManifestSha256': 'b'*64}}
        self.lookups.clear()
        return (signed_root, workspace, receipt, result, info, 'a'*64)

    def test_replacement_archive_selects_evidence_without_executor_claim(self):
        fixture = self.fixture_replacement()
        guest = fixture[1]/'evidence/app-vm'
        reader = retention.RetainedRead(self.locate, live=False)
        retention.verify_replacement(reader, *fixture)
        for path in reader.roots():
            scanned_input(self.locate(path))
        self.assertNotIn(guest/'Release/app-launch.claim', self.lookups)

    def test_replacement_archive_requires_the_database_and_bound_build_outputs(self):
        fixture = self.fixture_replacement()
        evidence = fixture[1]/'evidence'
        self.locate(evidence/'app-vm/Release/fixture/meshchan.sqlite').unlink()
        with self.assertRaises(FileNotFoundError):
            retention.verify_replacement(retention.RetainedRead(self.locate, live=False), *fixture)
        self.write(evidence/'app-vm/Release/fixture/meshchan.sqlite', b'replacement evidence')
        source = evidence/'libserialport-source'
        for name in (retention.SOURCE_FILES[0], 'app-library.dylib', 'cli-library.dylib'):
            target = self.locate(source/name)
            original = target.read_bytes()
            with self.subTest(path=name):
                target.write_bytes(b'changed build output')
                with self.assertRaisesRegex(ValueError, 'sha256 differs'):
                    retention.verify_replacement(retention.RetainedRead(self.locate, live=False), *fixture)
            target.write_bytes(original)

    def test_frozen_build_rejects_dirty_source_before_reading_products(self):
        source = self.original/'checkout'
        build_run = 'build/phase-1e4/run'
        upstream = {'sourceCheckout': str(source), 'buildRun': build_run,
                    'sourceCommit': 'a'*40, 'buildRecipeVersion': 55}
        info = {'formatVersion': 1, 'sourceCommit': upstream['sourceCommit'], 'recipeVersion': 55,
                'runIdentity': build_run, 'identity': {}, 'buildStatus': 'PASS', 'productChecksStatus': 'PASS',
                'engineeringDirtyMode': False, 'workingTree': ''}
        path = source/build_run/'build-info.json'
        for field, value in (('engineeringDirtyMode', True), ('workingTree', ' M tool/build_release.py')):
            with self.subTest(field=field):
                upstream['buildInfoSha256'] = self.write(path, encoded(info | {field: value}))
                reader = retention.RetainedRead(self.locate, live=False)
                with self.assertRaisesRegex(ValueError, f'Frozen build information {field} differs'):
                    retention.frozen_build(reader, upstream, {})

    def test_frozen_build_accepts_a_pinned_materials_retry_directory(self):
        source = self.original/'checkout'
        build_run = 'build/phase-1e4/run'
        run = source/build_run
        evidence = run/'evidence'
        commit = 'a'*40
        identity = {'target': 'macos-arm64', 'appBuild': '10', 'productVersion': '0.1.0-rc.1'}
        app, cli = retention.build.product_paths(run)
        self.write(app/'Contents/MacOS/Meshchan', b'app')
        self.write(cli/'bin/meshctl', b'cli')
        self.write(run/'native-hooks/receipt.json', b'{}')

        def ref(path, raw):
            return {'path': path.relative_to(source).as_posix(), 'sha256': self.write(path, raw)}

        inputs = encoded({'apps/meshctl/lib/src/meshctl.dart': 'b'*64})
        validation = encoded({'status': 'PASS', 'pathAudit': {
            'app': ['Contents/MacOS/Meshchan'], 'cli': ['bin/meshctl'],
        }})
        records = {
            'run_build.py': b'# frozen build driver\n',
            'candidate-inventories.json': encoded({
                'app': product_inventory(self.locate(app)), 'cli': product_inventory(self.locate(cli)),
            }),
            'candidate-checksums.txt': b'fixture checksums\n',
            'prebuild-identities.json': encoded({'source': {}, 'sourceMetadata': {}, 'configuration': {}}),
            'resolved-graph.json': encoded({'packages': []}),
            'compiler-inputs.json': encoded({'depfileHashes': {}}),
            'product-checks.json': validation,
            **dict.fromkeys(('compilation-input-hashes.json', 'inputs-before-configuration.json',
                            'inputs-after-cli.json', 'inputs-after-app.json'), inputs),
        }
        proof = {name: ref(evidence/name, raw) for name, raw in records.items()}
        stdout = ref(evidence/'logs/validate-products.log', validation)
        stderr = ref(evidence/'logs/validate-products.stderr.log', b'')
        step = {'name': 'validate-products', 'exitCode': 0,
                'log': stdout['path'], 'logSha256': stdout['sha256'],
                'stderrLog': stderr['path'], 'stderrLogSha256': stderr['sha256'],
                'processTree': {'exited': True, 'childReaped': True}}
        products = {'app': app.relative_to(source).as_posix(), 'cli': cli.relative_to(source).as_posix()}
        context = {'formatVersion': 1, 'sourceCommit': commit, 'recipeVersion': 57,
                   'engineeringDirtyMode': False, 'workingTree': '', **products}
        receipt = {
            **context, 'status': 'PASS', 'inputsUnchangedAcrossBuilds': True, 'steps': [step],
            'nativeHookCacheSha256': sha(encoded(product_inventory(self.locate(run/'native-hooks')))),
            **{field: proof[name]['sha256'] for field, name in (
                ('runnerSha256', 'run_build.py'), ('candidateInventoriesSha256', 'candidate-inventories.json'),
                ('candidateChecksumsSha256', 'candidate-checksums.txt'),
                ('prebuildIdentitiesSha256', 'prebuild-identities.json'), ('resolvedGraphSha256', 'resolved-graph.json'),
                ('compilationInputsSha256', 'compilation-input-hashes.json'),
                ('compilerInputsSha256', 'compiler-inputs.json'), ('productChecksSha256', 'product-checks.json'),
            )},
        }
        proof['build-receipt.json'] = ref(evidence/'build-receipt.json', encoded(receipt))
        info = {**context, 'runIdentity': build_run, 'identity': identity,
                'buildStatus': 'PASS', 'productChecksStatus': 'PASS', 'recipe': [step], 'evidence': proof,
                'sourceInputIdentity': sha(encoded({})), 'helperHashes': {}, 'controlledConfiguration': {'generated': {}}}
        upstream = {'sourceCheckout': str(source), 'buildRun': build_run,
                    'sourceCommit': commit, 'buildRecipeVersion': 57}
        material = b'fixture license\n'
        manifest = encoded({
            'sourceCommit': commit, 'products': {'buildReceipt': proof['build-receipt.json']}, 'openGates': [],
            'materials': {'LICENSE': {'size': len(material), 'sha256': sha(material)}},
        })
        for name in ('materials', 'materials-retry'):
            directory = retention.build.material_destination(self.locate(run), name)
            self.assertEqual(directory.parent, self.locate(run))
            self.write(run/name/'LICENSE', material)
            ref(run/name/'materials-manifest.json', manifest)
        upstream['materialsManifestSha256'] = sha(manifest)

        def verify(output, manifest_dir):
            info['materials'] = {
                'status': 'PASS', 'arguments': {'output': str(output)},
                'references': {'materials-manifest.json': {
                    'path': (manifest_dir/'materials-manifest.json').relative_to(source).as_posix(),
                    'sha256': upstream['materialsManifestSha256'],
                }},
            }
            upstream['buildInfoSha256'] = self.write(run/'build-info.json', encoded(info))
            reader = retention.RetainedRead(self.locate, live=False)
            return retention.frozen_build(reader, upstream, identity)[3]['materials']

        for name in ('materials', 'materials-retry'):
            destination = run/name
            with self.subTest(name=name):
                self.assertEqual(verify(destination, destination),
                                 (destination, product_inventory(self.locate(destination))))
        with self.assertRaisesRegex(ValueError, 'direct child'):
            verify(run/'nested/materials-retry', run/'materials-retry')
        with self.assertRaisesRegex(ValueError, 'material manifest location'):
            verify(run/'materials-retry', run/'materials')

    def test_frozen_recheck_requires_versioned_build_ledgers(self):
        source = self.original/'checkout'
        build_run = 'build/phase-1e4/run'
        run = source/build_run
        ledgers = {}
        for name in retention.CHECKS:
            path = run/'evidence'/(name+'-1')/'build-receipt.json'
            ledgers[name] = {'path': path.relative_to(source).as_posix(),
                             'sha256': self.write(path, encoded({'status': 'PASS', 'formatVersion': 2}))}
        receipt = {'buildRun': build_run, 'frozenVerification': {
            'result': {'status': 'PASS', 'buildStatus': 'PASS', 'materialsStatus': 'PASS', 'run': build_run},
            'ledgers': ledgers,
        }}
        with self.assertRaisesRegex(ValueError, 'Frozen verification ledger check-inputs formatVersion differs'):
            retention.verify_frozen_recheck(retention.RetainedRead(self.locate, live=False), source, run, receipt)

    def test_historical_vm_command_binds_the_app_manifest_and_evidence(self):
        checkout = self.original/'checkout'
        python = '/unavailable toolchain/bin/python3'
        candidate = self.original/'relocated product'
        evidence = checkout/'build/phase-1e7/check/evidence/vm-app'
        config = '/previous temporary/private-vm.json'
        pin = 'f'*64
        step = {'cwd': str(checkout), 'argv': [python, '-B', str(checkout/'tool/package_release_vm.py'),
                '--config', config, '--app', str(candidate/'Meshchan.app'), '--signed-info',
                str(candidate/'signed-product-info.json'), '--expected-signed-info-sha256', pin,
                '--evidence', str(evidence)]}
        args = checkout, python, candidate, pin, evidence
        self.assertEqual(retention.verify_vm_invocation(step, *args), Path(config))
        for index, value in ((0, '/different toolchain/bin/python3'), (2, '/other checkout/tool/package_release_vm.py'),
                             (6, '/different candidate/Meshchan.app'), (10, 'e'*64), (12, '/other run/evidence')):
            with self.subTest(index=index):
                argv = step['argv'].copy()
                argv[index] = value
                with self.assertRaisesRegex(ValueError, 'Historical VM invocation argv differs'):
                    retention.verify_vm_invocation(step | {'argv': argv}, *args)
        with self.assertRaisesRegex(ValueError, 'Historical VM invocation cwd differs'):
            retention.verify_vm_invocation(step | {'cwd': '/other checkout'}, *args)

    def test_historical_replacement_command_uses_the_same_config_and_valid_timeout(self):
        checkout = self.original/'checkout'
        python = '/unavailable toolchain/bin/python3'
        candidate = self.original/'signed product'
        workspace = self.original/'replacement workspace'
        config = Path('/previous temporary/private-vm.json')
        pin = 'f'*64
        step = {'cwd': str(checkout), 'argv': [python, '-B', str(checkout/'tool/release_signed_replacement.py'),
                '--signed-root', str(candidate), '--signed-info-sha256', pin, '--output', str(workspace),
                '--vm-config', str(config), '--timeout', '900']}
        args = checkout, python, candidate, pin, workspace, config
        retention.verify_replacement_invocation(step, *args)
        argv = step['argv'].copy()
        argv[10] = '/different temporary/private-vm.json'
        with self.assertRaisesRegex(ValueError, 'Historical replacement invocation argv differs'):
            retention.verify_replacement_invocation(step | {'argv': argv}, *args)
        with self.assertRaisesRegex(ValueError, 'Invalid historical replacement timeout'):
            retention.verify_replacement_invocation(step | {'argv': [*step['argv'][:-1], '0']}, *args)

    def fixture_cli(self):
        bundle = self.original/'relocated products/meshctl'
        workspace = self.original/'cli workspace'
        executable, library = bundle/'bin/meshctl', bundle/'lib/libsqlite3.dylib'
        observer = workspace/'release-image-probe'
        data = workspace/'owned signed CLI data'
        version = 'meshctl 0.1.0-rc.1'
        ex_pin = self.write(executable, b'signed executable')
        lib_pin = self.write(library, b'signed library')
        obs_pin = self.write(observer, b'observer')
        row = ('a'*32, runtime.CLI_TITLE, runtime.CLI_BODY, 1)
        with closing(sqlite3.connect(':memory:')) as database:
            database.execute('create table stored_drafts (id, title, body, revision)')
            database.execute('insert into stored_drafts values (?, ?, ?, ?)', row)
            database.commit()
            database_pin = self.write(data/'meshchan.sqlite', database.serialize())
        cli = {'status': 'PASS', 'bundle': str(bundle), 'database': str(data/'meshchan.sqlite'),
               'databaseSha256': database_pin, 'observerSha256': obs_pin, 'versionOutput': version,
               'storedDrafts': [row], 'processes': []}
        ledger = {'steps': [{'name': 'signed-cli-version', 'cwd': str(workspace),
                             'argv': [str(executable), '--version']}]}
        logs = {'signed-cli-version': {'log': version.encode()}}
        draft = {'id': row[0], 'title': row[1], 'body': row[2], 'revision': 1,
                 'bodyUtf8ByteLength': len(row[2].encode())}
        for offset, action in enumerate(('create', 'show')):
            image = workspace/(action+'-image.json')
            pid = 101 + offset*10
            observer_pid = pid+1
            observation = encoded({'pid': pid, 'observerPid': observer_pid, 'exitCode': 0,
                                   'mapping': {'address': '0xdeadbeef', 'device': 1, 'inode': 2}})
            self.write(image, observation)
            options = ['--title', row[1], '--body', row[2]] if action == 'create' else ['--id', row[0]]
            command = list(map(str, [executable, '--data-dir', data, 'draft', action, *options, '--json']))
            result = {'exitCode': 0, 'operationSucceeded': True, 'schemaVersion': 1,
                      'command': 'draft', 'action': action, 'hostCleanup': 'succeeded', 'draft': draft,
                      'storageClose': {'state': 'closed', 'error': None}}
            mapping = runtime.image_report(observation, executable, library, ex_pin, lib_pin, 0,
                                           observer_pid=observer_pid)
            cli['processes'].append({'report': result, 'name': action, 'pid': pid, 'cwd': str(workspace),
                                     'argv': command, 'pidAbsentAfterNormalExit': True, 'sqliteMapping': mapping})
            ledger['steps'].append({
                'name': 'signed-cli-'+action, 'cwd': str(workspace),
                'argv': [str(observer), str(image), str(library), *command],
                'processTree': {'exited': True, 'childReaped': True,
                                'members': [{'pid': observer_pid, 'pgid': observer_pid,
                                             'ppid': 2, 'exitObserved': True}]},
            })
            logs['signed-cli-'+action] = {'log': json.dumps(result).encode()}
        self.lookups.clear()
        return cli, bundle, workspace, {'productVersion': '0.1.0-rc.1'}, ledger, logs

    def test_recovered_cli_validates_historical_vnode_without_requiring_current_inode(self):
        fixture = self.fixture_cli()
        retention.verify_cli(retention.RetainedRead(self.locate, live=False), *fixture)
        with self.assertRaisesRegex(ValueError, 'Original SQLite vnode'):
            retention.verify_cli(retention.RetainedRead(self.locate, live=True), *fixture)
        self.assertTrue(all(path.is_relative_to(self.original) for path in self.lookups))

    def test_recovered_cli_requires_database_and_both_observer_reports(self):
        fixture = self.fixture_cli()
        for original in (self.original/'cli workspace/show-image.json',
                         self.original/'cli workspace/owned signed CLI data/meshchan.sqlite'):
            with self.subTest(original=original):
                target = self.locate(original)
                raw = target.read_bytes()
                target.unlink()
                with self.assertRaises(FileNotFoundError):
                    retention.verify_cli(retention.RetainedRead(self.locate, live=False), *fixture)
                target.write_bytes(raw)


if __name__ == '__main__':
    unittest.main()
