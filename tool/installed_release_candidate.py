"""Admit a later engineering image for candidate-specific install verification."""

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import sys

import installed_release_files as files
import package_dmg
import package_dmg_image as disk
from package_release import verify_report_fields
from release_materials import encoded, sha
from release_retention_inputs import verify_chain
import release_signing as signing
from release_signed_runtime import local_app_code_hashes, signed_info
from retain_release import CANDIDATE_FIELDS, COMMIT, bound_json, canonical, live_locator

RUNTIME_FILES = (
    'Meshchan.app/Contents/MacOS/Meshchan',
    'Meshchan.app/Contents/Frameworks/libserialport_plus.framework/Versions/A/libserialport_plus',
    'Meshchan.app/Contents/Frameworks/sqlite3.framework/Versions/A/sqlite3',
    'meshctl/bin/meshctl',
    'meshctl/lib/liblibserialport_plus.dylib',
    'meshctl/lib/libsqlite3.dylib',
)
POLICY_PATH = 'dmg-source/tool/release_signing_policy.json'


@dataclass(frozen=True)
class InstallCandidate:
    image_payload: bytes
    signed_info: dict
    policy: tuple
    report: dict

    @property
    def download_asset(self):
        image = self.report['engineeringDmg']
        return {'filename': Path(image['path']).name, 'size': image['size'], 'sha256': image['sha256']}

    @property
    def mount_pins(self):
        return {'volume_uuid': self.report['volumeUuid'],
                'manifest_sha256': self.report['candidatePins']['image_payload']}

    def verify_download(self, reader, path, *, url, started_at, finished_at, user_home):
        return files.verify_safari_download(reader, path, expected_asset=self.download_asset, url=url,
                                            started_at=started_at, finished_at=finished_at, user_home=user_home)

    def check_download(self, download):
        files.verify_safari_download_receipt(download)
        asset = self.download_asset
        verify_report_fields(download, {'sha256': asset['sha256']}, 'Admitted download')
        verify_report_fields(download['file'], {'size': asset['size']}, 'Admitted download file')
        if Path(download['file']['path']).name != asset['filename']:
            raise ValueError('Admitted download has the wrong asset filename')

    def observe_mount(self, vm, before, download):
        self.check_download(download)
        return files.observe_download_mount(vm, before, download, self.report['volumeName'], **self.mount_pins)

    def detach_mount(self, vm, before, download, mount):
        self.check_download(download)
        verify_report_fields(mount, {'volumeName': self.report['volumeName']}, 'Admitted volume name')
        return files.detach_download_mount(vm, before, download, mount, **self.mount_pins)

    def verify_installation(self, vm, app, materials_root, *, scratch, include_volume_materials=True):
        return files.verify_installation(
            vm, self.image_payload, self.mount_pins['manifest_sha256'], app, materials_root,
            scratch=scratch, policy=self.policy, signed_info=self.signed_info,
            include_volume_materials=include_volume_materials,
        )


def admit(selection_file, selection_sha256, *, expected_source, expected_build):
    """Verify the engineering chain and pin the actual image used by Safari and Finder."""
    if type(expected_source) is not str or COMMIT.fullmatch(expected_source) is None:
        raise ValueError('Expected the full compiled source commit')
    if type(expected_build) is not int or expected_build <= 8:
        raise ValueError('Use the historical sealed-archive entry point for Build 8')
    selection_file = canonical(selection_file)
    selection, _ = bound_json(selection_file, selection_sha256)
    if (set(selection) != {'formatVersion', 'inputRoots', 'candidate'}
            or type(selection['formatVersion']) is not int or selection['formatVersion'] != 1
            or type(selection['inputRoots']) is not list or not selection['inputRoots']
            or type(selection['candidate']) is not dict or set(selection['candidate']) != CANDIDATE_FIELDS):
        raise ValueError('Expected a complete pinned live engineering candidate selection')
    roots = [canonical(path) for path in selection['inputRoots']]
    if Path('/') in roots or len(set(roots)) != len(roots):
        raise ValueError('Expected distinct explicit candidate evidence roots')

    def locate(path):
        return live_locator(roots, path)

    refs = selection['candidate']
    pins = {name: value['sha256'] for name, value in refs.items() if name != 'upstream_tool_snapshot'}
    chain = verify_chain(refs, locate, live=True)['identities']
    verify_report_fields(chain, {'sourceCommit': expected_source}, 'Admitted compiled source')
    identity = chain['product']
    verify_report_fields(identity, {'appBuild': str(expected_build)}, 'Admitted App build')

    def read(name):
        return bound_json(locate(refs[name]['path']), pins[name])

    private = signed_info(locate(refs['signed_manifest']['path']), pins['signed_manifest'])
    verify_report_fields(private, {'identity': identity, 'signingProfile': signing.LOCAL_PROFILE},
                         'Admitted signed products')
    folder, filename, volume = package_dmg.volume_names(private)
    image = chain['image']
    verify_report_fields(image, {'path': refs['dmg']['path'], 'sha256': pins['dmg'], 'volumeName': volume,
                                 'format': disk.IMAGE_FORMAT, 'filesystem': disk.FILESYSTEM}, 'Admitted image')
    if Path(image['path']).name != filename:
        raise ValueError('Admitted image filename disagrees with the signed identity')

    accepted, _ = read('dmg_acceptance')
    created, _ = read('image_record')
    mount_uuid = accepted['mount']['volumeUuid']
    if (type(mount_uuid) is not str or files.GUID.fullmatch(mount_uuid) is None
            or created['mount']['volumeUuid'] != mount_uuid):
        raise ValueError('Admitted image creation and acceptance need a matching volume UUID')
    manifest, raw = read('image_payload')
    verify_report_fields(manifest, {
        **package_dmg.SIGNATURE_POLICY, 'candidatePath': folder, 'identity': identity,
        'localAcceptanceSha256': pins['local_acceptance'],
        'image': {'filename': filename, 'volumeName': volume, 'format': disk.IMAGE_FORMAT,
                  'filesystem': disk.FILESYSTEM},
    }, 'Admitted image payload')
    verify_report_fields(manifest['upstream'], {'sourceCommit': expected_source}, 'Image compiled source')
    files.mount_manifest(raw, pins['image_payload'])
    extract = Path(accepted['extraction']['root'])
    if manifest.get('payloadProfile') == package_dmg.PUBLIC_PAYLOAD:
        verify_report_fields(manifest, {'privateSignedInfoSha256': pins['signed_manifest']},
                             'Private signed evidence')
        verify_report_fields(accepted, {'payloadProfile': package_dmg.PUBLIC_PAYLOAD,
                                         'publicSignedInfoSha256': manifest['signedInfoSha256']},
                             'Extracted signed evidence')
        public_path = locate(extract/folder/package_dmg.SIGNED_MANIFEST)
        installed = signed_info(public_path, manifest['signedInfoSha256'])
        verify_report_fields(installed, {
            'payloadProfile': package_dmg.PUBLIC_PAYLOAD, 'compiledSource': expected_source,
            'privateSignedInfoSha256': pins['signed_manifest'],
            'identity': identity, 'signature': private['signature'],
        }, 'Public signed evidence')
    else:
        verify_report_fields(manifest, {'signedInfoSha256': pins['signed_manifest']}, 'Admitted signed evidence')
        installed = private

    policy = locate(extract/POLICY_PATH).read_bytes()
    inventory = manifest['inventory']
    verify_report_fields(inventory[POLICY_PATH], {'type': 'file', 'size': len(policy), 'sha256': sha(policy)},
                         'Admitted signing policy')
    verify_report_fields(manifest, {'signedInfoSha256': sha(encoded(installed))}, 'Installed signing bytes')
    parsed_policy = signing.parse_policy(policy)
    _, app, materials = files.installation_layout(raw, pins['image_payload'])
    record = {
        'status': 'PASS', 'scope': 'ENGINEERING_INPUT_ADMISSION', 'newProductRuntime': 'NOT_RUN',
        'candidateSelectionSha256': selection_sha256, 'candidatePins': pins,
        'sourceCommit': expected_source, 'product': identity, 'engineeringDmg': image,
        'originalChecksums': {'path': refs['checksums']['path'], 'sha256': pins['checksums']},
        'volumeUuid': mount_uuid, 'volumeName': volume, 'candidateFolder': folder,
        'payloadProfile': manifest.get('payloadProfile'),
        'appInventorySha256': sha(encoded(app)), 'materialsInventorySha256': sha(encoded(materials)),
        'appCodeDirectoryHashes': local_app_code_hashes(installed),
        'runtimeImageSha256': {name: inventory[f'{folder}/{name}']['sha256'] for name in RUNTIME_FILES},
    }
    bound_json(selection_file, selection_sha256)
    return InstallCandidate(raw, installed, parsed_policy, record)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate-selection', required=True, type=Path)
    parser.add_argument('--selection-sha256', required=True)
    parser.add_argument('--expected-source', required=True)
    parser.add_argument('--expected-build', required=True, type=int)
    args = parser.parse_args(argv)
    try:
        candidate = admit(args.candidate_selection, args.selection_sha256,
                          expected_source=args.expected_source, expected_build=args.expected_build)
        print(json.dumps(candidate.report, indent=2, sort_keys=True))
    except (KeyError, OSError, TypeError, ValueError) as error:
        print(f'Engineering install input admission: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
