"""Admit the frozen Phase 1E.9 engineering download from its durable handoff."""

from dataclasses import dataclass
from pathlib import Path
import stat

import package_dmg
from package_release import verify_report_fields
from release_package_archive import check_payload
from release_retention_archive import regular_entry
from release_retention_inputs import original_path, verify_chain
from release_signed_runtime import signed_info
from retain_release import MANIFEST, METADATA, RECEIPT, Mapping, bound_json, canonical


DEFAULT_ARCHIVE = Path('/Volumes/WD_BLACK_4T_1/BuildArtifacts/Meshchan Engineering Archive')
DMG_FILENAME = 'Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg'
DMG_SIZE = 675_911_154
DMG_SHA256 = 'b42021e054e65e47893d84437100a6b9e51a2ea93eb7a060c12e70fdb4a6ca28'
# From the pinned 1E.7 dmg-acceptance.json mount observation.
DMG_VOLUME_UUID = 'AD0C541A-7555-3814-8EDF-E12A92E548CA'
CHECKSUM_SHA256 = '8f26a0821bb39bd1c93d48e57622164fd4b4eaf87d59d9ac80ae503d1023da53'
SEAL_SHA256 = '76221dc94d40c7f32aaa5933c849fd17b4eadf3aceda907f9475f971dc38fc8c'
RESTORE_SHA256 = '12c3ca8e302865182bfcd9f0a49f62c9c7e213ada9a2f6c0dce4439c02639fcf'
TRANSFER_SHA256 = '2d80a32ea0e46165259012e8968531bc72481bf31116e247e2be87660a7cab37'
PRODUCT_COMMIT = 'a29430b608658a8b56d619f641dc8600346b6d27'
CANDIDATE_PINS = {
    'dmg': DMG_SHA256,
    'checksums': CHECKSUM_SHA256,
    'image_record': '8c108e73e60b9d29a879b489cc6312d65f4cfc6440f5046d891a101006a41245',
    'image_payload': '5abc9abee4004a9b9a1d3a8bfdb62e2d52893207308478d95f55b795ca8cdf62',
    'dmg_acceptance': 'b88f3f1647fe65e1f549e32d00de555b59dba09da366001c530f67626124b71f',
    'signed_manifest': '58565d17e1c8659f6a73d6164ea37afabee1b75a03c1b20a01615ade467c18d9',
    'local_acceptance': '17b203af6191d574d7d77fed472fb04050690aaf87e0b312ef1e02fa6eb474f0',
}


@dataclass(frozen=True)
class RCInputs:
    dmg: Path
    checksums: Path
    image_manifest: dict
    signed_info: dict
    report: dict


def verify_dmg_bytes(path: Path) -> dict:
    path = canonical(path)
    file = path.lstat()
    if (path.name != DMG_FILENAME or not stat.S_ISREG(file.st_mode)
            or file.st_size != DMG_SIZE):
        raise ValueError('Expected the exact Build 8 DMG filename and size')
    entry, _ = regular_entry(path)
    verify_report_fields(entry, {'sha256': DMG_SHA256, 'size': DMG_SIZE}, 'Build 8 engineering DMG')
    return entry


def verify_rc_inputs(archive_root: Path = DEFAULT_ARCHIVE) -> RCInputs:
    """Check the durable seal, its verified restore, and the published asset bytes.

    Use the checkout's semantic verifier on the retained inputs. This function
    reads the archived verifier inventory without executing archived code.
    """
    archive_root = canonical(archive_root)
    seal = canonical(archive_root/'RC1 Build 8 - 1E.8')
    if {child.name for child in seal.iterdir()} != {RECEIPT, MANIFEST, 'retained.tar', 'verifier'}:
        raise ValueError('Unexpected durable seal contents')
    receipt, _ = bound_json(canonical(seal/RECEIPT), SEAL_SHA256)
    verify_report_fields(receipt, {'formatVersion': 1, 'status': 'SEALED'}, 'Durable seal receipt')
    manifest, _ = bound_json(canonical(seal/MANIFEST), receipt['manifestSha256'])
    verify_report_fields(manifest, {'formatVersion': 1, 'metadata': METADATA}, 'Durable seal manifest')
    check_payload(canonical(seal/'verifier'), manifest['verifier'])
    actual_archive, _ = regular_entry(canonical(seal/'retained.tar'))
    verify_report_fields(receipt, {'archive': actual_archive}, 'Durable seal archive')

    evidence_dir = canonical(archive_root/'RC1 Build 8 - restore evidence')
    restore, _ = bound_json(canonical(evidence_dir/'verification.json'), RESTORE_SHA256)
    verify_report_fields(restore, {
        'status': 'PASS', 'operation': 'restore', 'receiptSha256': SEAL_SHA256,
        'archive': actual_archive, 'historicalAcceptance': 'MATCHED', 'newProductRuntime': 'NOT_RUN',
    }, 'Independent restore')
    verify_report_fields(restore['imageStructure'], {
        'status': 'PASS', 'format': 'UDZO', 'filesystem': 'HFS+', 'containerSignature': 'UNSIGNED',
    }, 'Restored image structure')
    historical_dmg = original_path(restore['restoredDmg'])
    if len(historical_dmg.parts) < 5 or historical_dmg.parent.name != 'inputs':
        raise ValueError('Unexpected historical restored image location')
    historical_archive = historical_dmg.parents[2]
    # The pinned receipt records the original archive location. Read only
    # the corresponding member under the operator-selected archive root.
    restored_dmg = canonical(archive_root/historical_dmg.relative_to(historical_archive))
    restored_root = restored_dmg.parents[1]
    locate = Mapping(manifest['mapping'], restored_root)
    selection, _ = bound_json(locate(manifest['selectionPath']), manifest['selectionSha256'])
    refs = selection['candidate']
    for key, pin in CANDIDATE_PINS.items():
        verify_report_fields(refs[key], {'sha256': pin}, f'Selected {key} pin')
    if locate(refs['dmg']['path']) != restored_dmg:
        raise ValueError('Restored image does not match the selected DMG member')
    chain = verify_chain(refs, locate)['identities']
    verify_report_fields(manifest['identities'], {'acceptance': chain}, 'Retained acceptance chain')
    verify_report_fields(chain, {'sourceCommit': PRODUCT_COMMIT, 'buildRecipeVersion': 55}, 'Frozen build')
    verify_report_fields(chain['image'], {'size': DMG_SIZE, 'sha256': DMG_SHA256}, 'Accepted image')

    assets = canonical(archive_root/'RC1 Build 8 - engineering assets')
    dmg = canonical(assets/DMG_FILENAME)
    checksums = canonical(assets/'SHA256SUMS')
    transfer, _ = bound_json(canonical(evidence_dir/'handoff-assets.json'), TRANSFER_SHA256)
    verify_report_fields(transfer, {
        'status': 'PASS', 'path': str(historical_archive/dmg.relative_to(archive_root)),
        'size': DMG_SIZE, 'sha256': DMG_SHA256, 'originalChecksumsSha256': CHECKSUM_SHA256,
        'verifiedRestoreMember': str(historical_dmg),
    }, 'Engineering asset transfer')
    image = verify_dmg_bytes(dmg)
    sums, _ = regular_entry(checksums)
    verify_report_fields(sums, {'sha256': CHECKSUM_SHA256}, 'Original SHA256SUMS')
    image_manifest, _ = bound_json(locate(refs['image_payload']['path']), CANDIDATE_PINS['image_payload'])
    verify_report_fields(image_manifest, package_dmg.SIGNATURE_POLICY, 'Engineering image signature policy')
    info = signed_info(locate(refs['signed_manifest']['path']), CANDIDATE_PINS['signed_manifest'])
    report = {
        'status': 'PASS', 'historicalAcceptance': 'MATCHED', 'newProductRuntime': 'NOT_RUN',
        'selectionSha256': manifest['selectionSha256'], 'candidatePins': CANDIDATE_PINS.copy(),
        'seal': str(seal), 'sealReceiptSha256': SEAL_SHA256,
        'sealManifestSha256': receipt['manifestSha256'], 'archive': actual_archive,
        'restoreReport': str(evidence_dir/'verification.json'), 'restoreReportSha256': RESTORE_SHA256,
        'restoredDmg': str(restored_dmg), 'assetTransferSha256': TRANSFER_SHA256,
        'engineeringDmg': {'path': str(dmg), **image},
        'originalChecksums': {'path': str(checksums), **sums}, 'identities': chain,
    }
    return RCInputs(dmg, checksums, image_manifest, info, report)
