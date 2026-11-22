#!/usr/bin/env python3
"""Create and independently accept a local ad hoc Meshchan engineering DMG."""
import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import platform
import shutil
import stat
import subprocess
import sys
import uuid

import build_release as build
import package_dmg_image as disk
import package_release as package
from package_release_vm import checked_vm_configuration
from release_materials import controlled_environment, digest, encoded, product_inventory, require_material_file, safe, sha
from release_package_archive import check_payload, metadata_observations, new_extraction_root, open_archive, prefixed
import release_signed_runtime as runtime
import release_signing as signing
import sign_release

ROOT = build.ROOT
PROFILE = 'local-adhoc'
GUIDE = 'docs/releases/phase-1e7-dmg.md'
SOURCES = tuple(sorted(set(sign_release.SIGNING_SOURCES) | {
    GUIDE, 'tool/package_dmg.py', 'tool/package_dmg_image.py', 'tool/package_dmg_test.py',
}))
IMAGE_MANIFEST = 'image-payload.json'
SIGNED_MANIFEST = 'signed-product-info.json'
MATERIAL_MANIFEST = 'materials/materials-manifest.json'
PUBLIC_PAYLOAD = runtime.PUBLIC_PAYLOAD
PUBLIC_MATERIAL_DIRS = ('licenses', 'rebuild', 'source-materials')
PUBLIC_MATERIAL_FILES = ('THIRD_PARTY_NOTICES.md',)
PUBLIC_PRODUCT_DIRS = ('Meshchan.app', 'meshctl', 'signing-materials', 'signing-source', 'packaging-source')
PUBLIC_PRODUCT_README = b"""# Meshchan macOS engineering release

Keep Meshchan.app and the complete meshctl directory with these materials.
Both products use local ad hoc signatures. The public signed-product-info.json
binds the exact distributable files, license materials, and corresponding
source to the locally accepted product. See signing-materials for the user
library replacement instructions.
"""
SIGNATURE_POLICY = {
    'signingProfile': PROFILE,
    'productCodeSignature': 'AD_HOC',
    'containerCodeSignature': 'UNSIGNED',
    'developerId': 'NOT_APPLICABLE',
    'appleNotarization': 'NOT_APPLICABLE',
    'stapling': 'NOT_APPLICABLE',
}
README = b"""# Meshchan engineering disk image

The Meshchan product folder contains the complete Meshchan.app, meshctl,
licenses, corresponding source, and accepted build and signing records. Keep
meshctl/bin/meshctl with the rest of meshctl, including its native libraries.

The App and CLI use local ad hoc code signatures. This read-only disk image
container is unsigned. Apple has not notarized this engineering release.
Compare the image's SHA-256 with the checksum from a trusted release handoff.
A checksum and ad hoc code signatures do not establish an Apple publisher
identity or promise automatic Gatekeeper approval.

See dmg-source/docs/releases/phase-1e7-dmg.md for engineering packaging and
acceptance. Tested installation and upgrade instructions are a separate
release step. See signing-materials inside the product folder for the user
library replacement guide. The dmg-source folder contains the corresponding
container tooling and license. Product materials remain in the product folder.
"""
SOURCE_README = b"""# Meshchan engineering disk image tooling

The source paths below match their locations in the Meshchan checkout. See
docs/releases/phase-1e7-dmg.md for the Python 3.15, frozen product, signing
acceptance, Apple tooling, and macOS VM inputs. Use the original checkout and
receipts to reproduce acceptance. image-payload.json at the volume root
identifies the exact tooling inputs. LICENSE and COPYRIGHT apply to this source.
"""


@dataclass(frozen=True)
class Layout:
    manifest: dict
    outliers: dict[str, bytes]

    @property
    def inventory(self):
        return self.manifest['inventory'] | {IMAGE_MANIFEST: package.bytes_entry(encoded(self.manifest))}


@dataclass(frozen=True)
class PublicCandidate:
    info: dict
    generated: dict[str, bytes]

    @property
    def manifest(self):
        return self.generated[SIGNED_MANIFEST]

    @property
    def inventory(self):
        return sign_release.manifest_inventory(self.info, self.manifest)


def output_path(path):
    path = package.canonical(path)
    if path.parent != ROOT/'build/phase-1e7':
        raise ValueError('Use a new direct child of this checkout build/phase-1e7')
    name = path.relative_to(ROOT).as_posix()
    if (package.git(ROOT, '--literal-pathspecs', 'ls-files', '-z', '--', name)
            or not package.git(ROOT, 'check-ignore', '--', name)):
        raise ValueError('DMG output must be ignored and disjoint from tracked source')
    if os.path.lexists(path):
        raise ValueError('Preserve the existing DMG run and use a fresh output')
    return path


def volume_names(info):
    identity = info['identity']
    if (type(identity['appBuild']) is not str or not identity['appBuild'].isascii()
            or not identity['appBuild'].isdigit() or int(identity['appBuild']) <= 0
            or identity['target'] != 'macos-arm64'):
        raise ValueError('Invalid engineering DMG product identity')
    version, build_number = identity['productVersion'], identity['appBuild']
    top = 'Meshchan-'+version+'-macos-arm64'
    filename = 'Meshchan-'+version+'-build'+build_number+'-macos-arm64-local.dmg'
    for name in (top, filename):
        if '/' in package.safe(name):
            raise ValueError('Invalid engineering DMG asset name')
    return top, filename, 'Meshchan '+version+' build '+build_number


def tool_sources():
    entries = {}
    contents = {}
    for name in SOURCES:
        path = require_material_file(ROOT, name)
        with open_archive(package.canonical(path)) as stream:
            metadata = os.fstat(stream.fileno())
            data = stream.read()
        entry = {**package.bytes_entry(data), 'mode': stat.S_IMODE(metadata.st_mode)}
        package.equal((entry, (metadata.st_dev, metadata.st_ino)), package.file_stamp(path), 'DMG source '+name)
        if entry['mode'] & ~0o777:
            raise ValueError('Unexpected source mode for '+name)
        entries[name] = entry
        contents['dmg-source/'+name] = data
    return entries, contents


def tool_identity(inputs):
    return {'inputs': inputs, 'gitCommit': package.git(ROOT, 'rev-parse', 'HEAD').strip(),
            'workingTree': package.git(ROOT, 'status', '--porcelain=v1', '--untracked-files=all',
                                       '--', *SOURCES).splitlines()}


def public_candidate(info, full, materials_bytes, private_signed_pin):
    """Project a separately verified signed candidate without copying local receipts."""
    materials = json.loads(materials_bytes, object_pairs_hook=signing.policy_object)
    upstream = info['upstream']
    package.verify_report_fields(full[MATERIAL_MANIFEST], {
        'type': 'file', 'sha256': sha(materials_bytes), 'size': len(materials_bytes),
    }, 'Original signed material manifest bytes')
    package.equal(upstream['materialsManifestSha256'], sha(materials_bytes), 'Original material manifest pin')
    package.verify_report_fields(materials, {
        'sourceCommit': upstream['sourceCommit'], 'productVersion': info['identity']['productVersion'],
        'appBuild': info['identity']['appBuild'], 'openGates': [],
    }, 'Original accepted material identity')
    material_files = {}
    for name, entry in materials['materials'].items():
        member = Path(safe(name))
        if member.parts[0] not in PUBLIC_MATERIAL_DIRS and name not in PUBLIC_MATERIAL_FILES:
            if member.parts[0] != 'evidence':
                raise ValueError('Unclassified signed release material: '+name)
            continue
        pin = {key: entry[key] for key in ('size', 'sha256')}
        package.verify_report_fields(full['materials/'+name], {'type': 'file', **pin},
                                     'Public material inventory '+name)
        material_files[name] = pin
    materials_public = {
        'formatVersion': 1, 'payloadProfile': PUBLIC_PAYLOAD,
        'sourceCommit': upstream['sourceCommit'], 'productVersion': materials['productVersion'],
        'appBuild': materials['appBuild'], 'lockSha256': materials['lockSha256'],
        'privateMaterialManifestSha256': upstream['materialsManifestSha256'],
        'materials': material_files,
    }
    inventory = {name: entry for name, entry in full.items()
                 if name in ('.', 'materials') or Path(safe(name)).parts[0] in PUBLIC_PRODUCT_DIRS}
    for name in material_files:
        member = Path(safe('materials/'+name))
        inventory[member.as_posix()] = full[member.as_posix()]
        inventory.update({parent.as_posix(): full[parent.as_posix()] for parent in member.parents})
    generated = {MATERIAL_MANIFEST: encoded(materials_public), 'README.md': PUBLIC_PRODUCT_README}
    inventory.update({name: package.bytes_entry(data) for name, data in generated.items()})
    public_info = {
        **{key: info[key] for key in ('formatVersion', 'signingProfile', 'identity', 'policy',
                                     'signature', 'inventoryExclusions')},
        'payloadProfile': PUBLIC_PAYLOAD,
        'compiledSource': upstream['sourceCommit'],
        'privateSignedInfoSha256': private_signed_pin,
        'payloadInventory': inventory,
    }
    return PublicCandidate(public_info, {**generated, SIGNED_MANIFEST: encoded(public_info)})


def layout(candidate_inventory, info, args, sources, identity, *, public=None):
    top, filename, volume_name = volume_names(info)
    outliers = {**sources, 'README-engineering.md': README, 'dmg-source/README.md': SOURCE_README}
    image_candidate = candidate_inventory if public is None else public.inventory
    inventory = {'.': package.DIR, **prefixed(top, image_candidate)}
    for name, data in outliers.items():
        path = Path(name)
        for directory in path.parents:
            inventory.setdefault(directory.as_posix(), package.DIR)
        mode = identity['inputs'][name.removeprefix('dmg-source/')]['mode'] if name in sources else 0o644
        inventory[name] = {**package.bytes_entry(data), 'mode': mode}
    manifest = {
        'formatVersion': 1, **SIGNATURE_POLICY, 'identity': info['identity'],
        'upstream': info['upstream'], 'signingTool': info['signingTool'], 'dmgTool': identity,
        'signedInfoSha256': args.candidate_sha256, 'localAcceptanceSha256': args.acceptance_sha256,
        'image': {'filename': filename, 'volumeName': volume_name,
                  'format': disk.IMAGE_FORMAT, 'filesystem': disk.FILESYSTEM},
        'candidatePath': top, 'inventory': inventory, 'inventoryExclusions': [IMAGE_MANIFEST],
        'volumeMetadataPolicy': {
            'rootMode': package.DIR['mode'], 'ownerPresentation': 'Observed separately from payload modes',
            'systemManagedExtendedAttributes': ['com.apple.provenance'], 'extraVolumeEntries': [],
        },
    }
    if public is not None:
        manifest.update({
            'payloadProfile': PUBLIC_PAYLOAD,
            'upstream': {key: info['upstream'][key] for key in ('sourceCommit', 'buildRecipeVersion',
                                                               'buildInfoSha256', 'materialsManifestSha256')},
            'privateSignedInfoSha256': args.candidate_sha256,
            'signedInfoSha256': sha(public.manifest),
        })
    return Layout(manifest, outliers)


def stage(staging, candidate, expected, *, public=None):
    staging.mkdir(mode=0o755)
    staging.chmod(expected.inventory['.']['mode'])
    top = expected.manifest['candidatePath']
    generated = {}
    ignore = None
    if public is not None:
        selected = public.inventory.keys() - public.generated.keys()

        def ignore(directory, names):
            return [name for name in names if (Path(directory)/name).relative_to(candidate).as_posix() not in selected]

        generated = {f'{top}/{name}': data for name, data in public.generated.items()}
    shutil.copytree(candidate, staging/top, symlinks=True, copy_function=shutil.copy, ignore=ignore)
    files = {**expected.outliers, **generated, IMAGE_MANIFEST: encoded(expected.manifest)}
    for name, data in files.items():
        path = staging/name
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('xb') as output:
            output.write(data)
        path.chmod(expected.inventory[name]['mode'])
    for name, entry in expected.inventory.items():
        if entry['type'] == 'directory' and (name == 'dmg-source' or name.startswith('dmg-source/')):
            (staging/name).chmod(entry['mode'])
    return check_layout(staging, expected)


def check_layout(root, expected):
    check_payload(root, expected.inventory)
    return metadata_observations(root, expected.inventory)


def mounted_layout(root, full, info, args, entries, contents, *, public=None):
    # The manifest's commit is recorded at image creation. A later checkout
    # can verify the same exact source bytes even if those files were committed
    # after image creation. Other manifest fields are independently rebuilt.
    data = require_material_file(root, IMAGE_MANIFEST).read_bytes()
    declared = json.loads(data)
    tools = declared['dmgTool']
    if (type(tools) is not dict or type(tools.get('gitCommit')) is not str
            or len(tools['gitCommit']) != 40 or any(char not in '0123456789abcdef' for char in tools['gitCommit'])
            or type(tools.get('workingTree')) is not list or any(type(row) is not str for row in tools['workingTree'])):
        raise ValueError('Malformed DMG tool provenance')
    package.equal(encoded(entries), encoded(tools['inputs']), 'DMG source inputs used to create the image')
    expected = layout(full, info, args, contents,
                      {'inputs': entries, 'gitCommit': tools['gitCommit'], 'workingTree': tools['workingTree']},
                      public=public)
    package.equal(encoded(expected.manifest), data, 'Reconstructed image payload manifest')
    return expected


def static_products(root, original, full, info, signatures, runner):
    check_payload(root, full)
    metadata_observations(root, full)
    native = sign_release.native_report(original, root, runner)
    package.equal(encoded(info['native']), encoded(native), 'Native/AOT closure after image extraction')
    return {'status': 'PASS', 'signingProfile': PROFILE, 'productRoot': str(root),
            'inventorySha256': sha(encoded(full)), 'signatures': signatures, 'native': native}


def protect_inputs(output, args, upstream, candidate, receipt, local_workspace, image):
    config = package.canonical(args.vm_config)
    protected = (*upstream.protected, candidate.parent.parent, receipt, local_workspace, config,
                 *(ROOT/name for name in SOURCES), Path.home()/'Library/Application Support/meshchan')
    if image is not None:
        protected = (*protected, image)
    package.disjoint(output, protected)
    workspace_name = f'Meshchan DMG {args.command} {uuid.uuid4().hex}'
    workspace = package.canonical(args.workspace_parent/workspace_name)
    package.real_directory(workspace.parent)
    package.disjoint(workspace, (ROOT, *protected, output))
    vm = checked_vm_configuration(config, (ROOT, *protected, workspace, output), cwd=ROOT)
    return workspace, vm


def checked_reference(output, reference):
    return sign_release.evidence_json(output, reference)


def bind_runtime(output, evidence, candidate, info, manifest, vm, runner, record, *, workspace):
    cli_workspace = workspace/'cli workspace'
    package.disjoint(cli_workspace, [candidate.parent])
    cli_bundle = candidate/'meshctl'
    version = info['identity']['productVersion']
    record['cliStatus'] = 'RUNNING'
    cli = {**runtime.accept_cli(cli_bundle, cli_workspace, runner, version),
           'imageSha256': record['image']['sha256'], 'signedInfoSha256': sha(manifest), 'signingProfile': PROFILE}
    cli_path = evidence/'cli-runtime.json'
    record['cliReport'] = sign_release.publish_json(output, cli_path, cli)
    record['cliStatus'] = 'PASS'
    record['vmAppStatus'] = 'RUNNING'
    vm_evidence = evidence/'vm-app'
    with vm as config:
        vm_args = [sys.executable, '-B', ROOT/'tool/package_release_vm.py', '--config', config,
                   '--app', candidate/'Meshchan.app', '--signed-info', candidate/SIGNED_MANIFEST,
                   '--expected-signed-info-sha256', sha(manifest), '--evidence', vm_evidence]
        result = build.material_result(runner.command('dmg-vm-app-runtime', vm_args, cwd=ROOT))
    receipt_path = vm_evidence/'runtime.json'
    reference = sign_release.vm_report(output, receipt_path, result, candidate, info, manifest)
    vm_snapshot = product_inventory(vm_evidence)
    record['vmAppReport'] = reference
    record['vmAppStatus'] = 'PASS'
    context = {'imageSha256': record['image']['sha256'], 'signedInfoSha256': sha(manifest), 'signingProfile': PROFILE}
    vm_link = {'productRoot': str(candidate), **context, 'vmReceipt': reference, 'guestRun': result['guestRun']}
    record['vmImageBinding'] = sign_release.publish_json(output, evidence/'vm-image-binding.json', vm_link)

    def recheck():
        cli_again = checked_reference(output, record['cliReport'])
        package.verify_report_fields(cli_again, context, 'DMG CLI runtime identity')
        runtime.verify_cli_runtime_evidence(cli_again, cli_bundle, cli_workspace, version,
                                            ledger=runner.receipt, evidence_root=output)
        sign_release.vm_report(output, receipt_path, result, candidate, info, manifest)
        check_payload(vm_evidence, vm_snapshot)
        package.equal(vm_link, checked_reference(output, record['vmImageBinding']), 'VM image binding')

    return recheck


def accept_image(image, stamp, workspace, evidence, full, info, args, entries, contents, runner, record,
                 *, policy, expected=None, public=None):
    record['imageIntegrityStatus'] = 'RUNNING'
    record['imageVerification'] = disk.verify_image(runner, image, stamp)
    record['imageIntegrityStatus'] = 'PASS'
    mount = workspace/'readonly volume'
    extracted = workspace/'extracted payload'
    with disk.mounted_image(runner, image, stamp, mount, volume_names(info)[2], record):
        record['extractionStatus'] = 'RUNNING'
        mounted = mounted_layout(mount, full, info, args, entries, contents, public=public)
        if expected is not None:
            package.equal(expected, mounted, 'Mounted manifest and staged manifest')
        record['mountMetadata'] = check_layout(mount, mounted)
        shutil.copytree(mount, extracted, symlinks=True, copy_function=shutil.copy)
        extracted_stamp = extracted.lstat()
        record['extractedMetadata'] = check_layout(extracted, mounted)
        check_layout(mount, mounted)
        record['extractionStatus'] = 'PASS'
        record['signatureStatus'] = 'RUNNING'
        candidate = extracted/mounted.manifest['candidatePath']
        signatures = signing.verify_signatures(candidate, policy, info['signature']['identity'],
                                               runner.command, evidence)
        package.equal(encoded(info['signature']['items']), encoded(signatures),
                      'Ad hoc signatures after image extraction')
        record['signatureStatus'] = 'PASS'
    package.equal('PASS', record['detachStatus'], 'Detach before running extracted products')
    package.require_extraction_root(extracted, extracted_stamp)
    disk.require_image(image, stamp)
    record['extraction'] = {'root': str(extracted), 'candidateRoot': str(extracted/mounted.manifest['candidatePath']),
                            'inventorySha256': sha(encoded(mounted.inventory)),
                            'payloadManifestSha256': sha(encoded(mounted.manifest))}
    record['payloadManifest'] = sign_release.publish_json(evidence.parent, evidence/IMAGE_MANIFEST, mounted.manifest)
    return mounted, extracted, extracted_stamp, signatures


def verify_process_logs(output, ledger):
    seen = set()
    for step in ledger['steps']:
        for label in ('log', 'stderrLog'):
            if step[label] in seen or not isinstance(step[label+'Sha256'], str):
                raise ValueError('Missing or repeated process evidence '+step[label])
            seen.add(step[label])
            path = require_material_file(output, step[label])
            package.equal(step[label+'Sha256'], digest(path), 'Process evidence '+step[label])


def environment(runner):
    return {'macOS': runner.command('macos-version', ['/usr/bin/sw_vers']).strip(),
            'architecture': platform.machine(), 'pythonPath': sys.executable, 'pythonVersion': sys.version,
            'hdiutil': {'path': disk.HDIUTIL, 'sha256': digest(disk.HDIUTIL)},
            'diskutil': {'path': disk.DISKUTIL, 'sha256': digest(disk.DISKUTIL)}}


def run(args):
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise ValueError('Use a macOS arm64 engineering packaging host')
    create = args.command == 'create'
    output = output_path(args.output)
    root = package.real_directory(package.canonical(args.candidate))
    receipt = package.canonical(args.acceptance_receipt)
    image = None if create else package.canonical(args.image)
    info, manifest, local_report = sign_release.read_local_acceptance(
        root, args.candidate_sha256, receipt, args.acceptance_sha256)
    original = sign_release.accepted_upstream(info)
    full = sign_release.manifest_inventory(info, manifest)
    public = (public_candidate(info, full, require_material_file(root, MATERIAL_MANIFEST).read_bytes(),
                               args.candidate_sha256)
              if getattr(args, 'public_payload', False) else None)
    image_inventory = full if public is None else public.inventory
    local_workspace = package.real_directory(package.canonical(local_report['workspace']))
    workspace, vm = protect_inputs(output, args, original, root, receipt, local_workspace, image)
    output.parent.mkdir(parents=True, exist_ok=True)
    with new_extraction_root(output) as output_fd:
        output_stamp = os.fstat(output_fd)
    evidence = output/'evidence'
    evidence.mkdir(mode=0o700)
    evidence_stamp = evidence.lstat()

    receipt_path = output/('image-record.json' if create else 'dmg-acceptance.json')
    record = {
        'formatVersion': 1, 'command': args.command, 'status': 'RUNNING', 'startedAt': build.now(),
        **SIGNATURE_POLICY, 'identity': info['identity'], 'upstream': info['upstream'],
        'candidate': {'root': str(root), 'manifestSha256': args.candidate_sha256,
                      'localAcceptanceReceipt': str(receipt), 'localAcceptanceSha256': args.acceptance_sha256},
        'signingTool': info['signingTool'], 'workspace': str(workspace), 'localAcceptanceStatus': 'PASS',
        **dict.fromkeys(('workspaceStatus', 'stageStatus', 'imageIntegrityStatus', 'attachStatus', 'extractionStatus',
                         'signatureStatus', 'detachStatus', 'staticStatus', 'cliStatus', 'vmAppStatus',
                         'finalIntegrityStatus'), 'NOT_RUN'),
    }
    if not create:
        record['selectedImage'] = {'path': str(image), 'sha256': args.image_sha256}
    if public is not None:
        record['payloadProfile'] = PUBLIC_PAYLOAD
        record['publicSignedInfoSha256'] = sha(public.manifest)
    build.write(receipt_path, record)
    with build.DeferredInterrupts() as signals:
        runner = build.Runner(output, evidence, {'status': 'RUNNING', 'steps': []},
                              {**controlled_environment(), 'LC_ALL': 'C', 'TZ': 'UTC'}, args.timeout, signals)

        def publish(status):
            package.require_extraction_root(output, output_stamp)
            package.require_extraction_root(evidence, evidence_stamp)
            runner.receipt['status'] = status
            record['status'] = status
            record['finishedAt'] = build.now()
            record['processLedger'] = sign_release.publish_json(output, evidence/'build-receipt.json', runner.receipt)
            return sign_release.publish_json(output, receipt_path, record)

        try:
            record['workspaceStatus'] = 'RUNNING'
            with new_extraction_root(workspace) as workspace_fd:
                workspace_stamp = os.fstat(workspace_fd)
            # Host tooling, including the VM transfer's temporary archive,
            # must not inherit a TMPDIR that points into a protected input.
            runner.env['TMPDIR'] = str(workspace)
            record['workspaceStatus'] = 'PASS'
            record['environment'] = environment(runner)
            entries, contents = tool_sources()
            top, filename, volume = volume_names(info)
            policy = signing.load_policy(sign_release.POLICY)
            expected = staging = None
            if create:
                record['stageStatus'] = 'RUNNING'
                identity = tool_identity(entries)
                expected = layout(full, info, args, contents, identity, public=public)
                record['dmgTool'] = identity
                staging = output/'staging'
                record['stageMetadata'] = stage(staging, root, expected, public=public)
                record['stageStatus'] = 'PASS'
                image = output/filename
                stamp = disk.create_image(runner, staging, image, volume)
            else:
                stamp = package.file_stamp(image)
                package.equal(args.image_sha256, stamp[0]['sha256'], 'Externally selected DMG SHA-256')
            record['image'] = {'path': str(image), **stamp[0], 'format': disk.IMAGE_FORMAT,
                               'filesystem': disk.FILESYSTEM, 'volumeName': volume}
            mounted, extracted, extracted_stamp, signatures = accept_image(
                image, stamp, workspace, evidence, full, info, args, entries, contents, runner, record,
                policy=policy, expected=expected, public=public)
            record['dmgTool'] = mounted.manifest['dmgTool']
            extracted_candidate = extracted/top
            record['staticStatus'] = 'RUNNING'
            static = static_products(extracted_candidate, original, image_inventory, info, signatures, runner)
            record['staticReport'] = sign_release.publish_json(output, evidence/'static-products.json', static)
            record['staticStatus'] = 'PASS'
            if not create:
                package.require_extraction_root(extracted, extracted_stamp)
                check_layout(extracted, mounted)
                image_info = info if public is None else public.info
                image_manifest = manifest if public is None else public.manifest
                check_runtime = bind_runtime(output, evidence, extracted_candidate, image_info, image_manifest,
                                             vm, runner, record, workspace=workspace)
            else:
                sums = output/'SHA256SUMS'
                checksum = f'{stamp[0]["sha256"]}  {filename}\n'.encode()
                with sums.open('xb') as stream:
                    stream.write(checksum)
                record['checksumFile'] = sign_release.require_ref(output, sums, sha(checksum))
            record['finalIntegrityStatus'] = 'RUNNING'
            package.equal(original, sign_release.accepted_upstream(info), 'Original engineering package and frozen source')
            local = sign_release.read_local_acceptance(root, args.candidate_sha256, receipt, args.acceptance_sha256)
            package.equal((info, manifest, local_report), local, 'Accepted local candidate and evidence after disk image run')
            package.equal((entries, contents), tool_sources(), 'DMG tool inputs after run')
            checked_reference(output, record['payloadManifest'])
            checked_reference(output, record['staticReport'])
            if not create:
                check_runtime()
            else:
                check_layout(staging, expected)
                sign_release.require_ref(output, sums, sha(checksum))
            package.require_extraction_root(workspace, workspace_stamp)
            package.require_extraction_root(extracted, extracted_stamp)
            check_layout(extracted, mounted)
            verify_process_logs(output, runner.receipt)
            disk.require_image(image, stamp)
            record['finalIntegrityStatus'] = 'PASS'
            build.raise_if_interrupted(signals)
            final_ref = publish('CREATED' if create else 'PASS')
            while not signals.seal_if_unchanged(0):
                build.raise_if_interrupted(signals)
        except BaseException as error:
            for key, value in record.items():
                if key.endswith('Status') and value == 'RUNNING':
                    record[key] = 'FAIL'
            if signals:
                record['interruptSignal'] = int(signals[0])
            record['error'] = build.failure_message(error)
            publish('FAIL')
            raise
    return {'status': record['status'], 'image': record['image'], 'receipt': str(receipt_path),
            'receiptSha256': final_ref['sha256'], 'workspace': str(workspace),
            **({'checksumFile': str(output/'SHA256SUMS')} if create else {})}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for name in ('create', 'check'):
        command = commands.add_parser(name)
        command.add_argument('--candidate', type=Path, required=True)
        command.add_argument('--candidate-sha256', required=True)
        command.add_argument('--acceptance-receipt', type=Path, required=True)
        command.add_argument('--acceptance-sha256', required=True)
        command.add_argument('--output', type=Path, required=True)
        command.add_argument('--workspace-parent', type=Path, required=True)
        command.add_argument('--vm-config', type=Path, required=True)
        command.add_argument('--public-payload', action='store_true',
                             help='Use the independently reproducible public image layout without private receipts')
        command.add_argument('--timeout', type=build.command_timeout, default=900)
        if name == 'check':
            command.add_argument('--image', type=Path, required=True)
            command.add_argument('--image-sha256', required=True)
    args = parser.parse_args()
    if sys.version_info < (3, 15) or sys.version_info.releaselevel != 'final':
        parser.error('Use a stable Python 3.15 or newer')
    for name, value in vars(args).items():
        if name.endswith('_sha256') and not package.SHA256.fullmatch(value):
            parser.error('Use a lowercase SHA-256 for --'+name.replace('_', '-'))
    try:
        record = run(args)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError,
            KeyboardInterrupt, build.GateInterrupted) as error:
        print('ERROR: '+build.failure_message(error), file=sys.stderr)
        return 1
    print(json.dumps(record, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
