"""Apply and verify the explicit macOS product signing policy."""
from dataclasses import dataclass
import hashlib
import json
import mmap
from pathlib import Path, PurePosixPath
import plistlib
import re
import ssl
import struct
import subprocess
import tempfile

from release_materials import product_inventory
from release_package_archive import compare, metadata_observations, prefixed


DEFAULT_POLICY = Path(__file__).with_name('release_signing_policy.json')
CERTIFICATE_TYPE = 'Developer ID Application'
LOCAL_PROFILE = 'local-adhoc'
DEVELOPER_PROFILE = 'developer-id'
CLI_UNSIGNED_MEMORY = 'com.apple.security.cs.allow-unsigned-executable-memory'
DISABLE_LIBRARY_VALIDATION = 'com.apple.security.cs.disable-library-validation'
LEAF_OID = '1.2.840.113635.100.6.1.13'
ISSUER_OID = '1.2.840.113635.100.6.2.6'
THIN_64 = b'\xcf\xfa\xed\xfe'
FAT_HEADERS = {b'\xca\xfe\xba\xbe': struct.Struct('>iiIII'),
               b'\xca\xfe\xba\xbf': struct.Struct('>iiQQII')}
OTHER_MACHO = {b'\xfe\xed\xfa\xcf', b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe',
               b'\xbe\xba\xfe\xca', b'\xbf\xba\xfe\xca'}
ARCH_NAMES = {0x01000007: 'x86_64', 0x0100000c: 'arm64'}
MH_EXECUTE, MH_DYLIB = 2, 6
LC_SEGMENT_64, LC_CODE_SIGNATURE = 0x19, 0x1d
CS_ADHOC, CS_RUNTIME = 0x2, 0x10000
BUNDLE_SUFFIXES = {'.app', '.framework', '.xpc', '.appex', '.plugin', '.bundle', '.kext'}


class IdentityUnavailable(ValueError):
    """The requested certificate and private key are unavailable."""


@dataclass(frozen=True)
class CodeItem:
    path: str
    binary: str
    role: str
    identifier: str
    runtime: bool
    version: str | None = None
    signing_profile: str = DEVELOPER_PROFILE

    @property
    def entitlements(self):
        values = {CLI_UNSIGNED_MEMORY: True} if self.role == 'cli' else {}
        if self.signing_profile == LOCAL_PROFILE and self.runtime:
            values[DISABLE_LIBRARY_VALIDATION] = True
        return values

    @property
    def seal(self):
        if self.role == 'app':
            return self.path+'/'+'Contents/_CodeSignature/CodeResources'
        if self.role == 'framework':
            return PurePosixPath(self.binary).parent.as_posix()+'/_CodeSignature/CodeResources'
        return None

    def bundle_args(self):
        return ['--bundle-version', self.version] if self.version else []

    def record(self):
        return {'path': self.path, 'binary': self.binary, 'role': self.role,
                'identifier': self.identifier, 'bundleVersion': self.version,
                'signingProfile': self.signing_profile, 'runtime': self.runtime,
                'entitlements': self.entitlements, 'secureTimestamp': self.signing_profile == DEVELOPER_PROFILE}


def local_identity():
    return {'adhoc': True, 'certificateType': None, 'authority': None, 'team': None, 'secureTimestamp': False}


def require_local_identity(identity):
    expected = local_identity()
    if (type(identity) is not dict or identity != expected
            or any(type(identity[key]) is not type(value) for key, value in expected.items())):
        raise ValueError('Expected an explicit ad hoc identity without a certificate, Team, or secure timestamp')


def policy_profile(policy):
    profiles = {item.signing_profile for item in policy}
    if profiles == {LOCAL_PROFILE}:
        return LOCAL_PROFILE
    if profiles == {DEVELOPER_PROFILE}:
        return DEVELOPER_PROFILE
    raise ValueError('Missing, unknown, or conflicting code signing profiles')


def exact_entitlements(actual, expected):
    return (type(actual) is dict and actual == expected
            and all(type(value) is bool for value in actual.values()))


def relative_product_path(value):
    if not isinstance(value, str):
        raise ValueError('Signing policy paths must be strings')
    path = PurePosixPath(value)
    if (len(path.parts) < 1 or path.parts[0] not in {'Meshchan.app', 'meshctl'}
            or '..' in path.parts or path.as_posix() != value):
        raise ValueError('Unsafe signing policy path: '+value)
    return path


def policy_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError('Duplicate JSON key: '+key)
        value[key] = item
    return value


def load_policy(path):
    return parse_policy(Path(path).read_bytes())


def parse_policy(raw):
    data = json.loads(raw, object_pairs_hook=policy_object)
    if type(data) is not dict or type(data.get('formatVersion')) is not int:
        raise ValueError('Unsupported signing policy format')
    keys = {'formatVersion', 'certificateType', 'secureTimestamp', 'codeItems'}
    if (data['formatVersion'] == 1 and set(data) == keys
            and data['certificateType'] == CERTIFICATE_TYPE and data['secureTimestamp'] is True):
        profile = DEVELOPER_PROFILE
    elif (data['formatVersion'] == 2 and set(data) == keys | {'signingProfile'}
          and data['signingProfile'] == LOCAL_PROFILE and data['certificateType'] is None
          and data['secureTimestamp'] is False):
        profile = LOCAL_PROFILE
    else:
        raise ValueError('Unsupported signing policy format, profile, or certificate policy')
    if type(data['codeItems']) is not list:
        raise ValueError('Signing policy code items must be a list')

    items = []
    for entry in data['codeItems']:
        if not isinstance(entry, dict):
            raise ValueError('Signing policy code items must be objects')
        role = entry.get('role')
        keys = {'path', 'binary', 'role', 'identifier', 'runtime', 'entitlements'}
        if role == 'framework':
            keys.add('version')
        if keys != set(entry) or role not in ('app', 'cli', 'framework', 'cliLibrary'):
            raise ValueError('Unsupported signing policy code item: '+repr(entry))
        target = relative_product_path(entry['path'])
        binary = relative_product_path(entry['binary'])
        identifier = entry['identifier']
        version = entry.get('version')
        runtime = role in ('app', 'cli')
        item = CodeItem(target.as_posix(), binary.as_posix(), role, identifier, runtime, version, profile)
        if (not isinstance(identifier, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.-]*', identifier)
                or entry['runtime'] is not runtime
                or not exact_entitlements(entry['entitlements'], item.entitlements)):
            raise ValueError('Signing profile requires role-specific runtime and exact entitlements: '+str(target))
        if role == 'app':
            valid = target == PurePosixPath('Meshchan.app') and binary == target/'Contents/MacOS/Meshchan'
        elif role == 'framework':
            valid = (isinstance(version, str) and re.fullmatch(r'[A-Za-z0-9]+', version)
                     and version != 'Current' and target.suffix == '.framework'
                     and target.parent == PurePosixPath('Meshchan.app/Contents/Frameworks')
                     and binary == target/'Versions'/version/target.stem)
        else:
            valid = binary == target and (target == PurePosixPath('meshctl/bin/meshctl') if role == 'cli'
                                          else target.parent == PurePosixPath('meshctl/lib'))
        if not valid:
            raise ValueError('Unexpected signing location for '+role+': '+str(target))
        items.append(item)

    for field in ('path', 'binary', 'identifier'):
        if len({getattr(item, field) for item in items}) != len(items):
            raise ValueError('Duplicate signing policy '+field)
    roles = [item.role for item in items]
    if (roles.count('app') != 1 or roles.count('cli') != 1
            or roles != sorted(roles, key=('framework', 'app', 'cliLibrary', 'cli').index)):
        raise ValueError('Signing policy must order nested frameworks and CLI libraries before their owners')
    return tuple(items)


def product_inventory_pair(root):
    return {name: entry for product in ('Meshchan.app', 'meshctl')
            for name, entry in prefixed(product, product_inventory(root/product)).items()}


def examine_slice(contents, start, size, declared, label):
    end = start+size
    if size < 32 or start < 0 or end > len(contents) or contents[start:start+4] != THIN_64:
        raise ValueError('Expected a supported 64-bit Mach-O slice: '+label)
    cpu, sub, kind, ncmds, command_size = struct.unpack_from('<iiIII', contents, start+4)
    architecture = ARCH_NAMES.get(cpu)
    if not architecture or (declared is not None and (cpu, sub) != declared):
        raise ValueError('Unexpected Mach-O slice architecture: '+label)

    command_start = start+32
    command_end = command_start+command_size
    if command_end > end or ncmds > command_size//8:
        raise ValueError('Invalid Mach-O load command table: '+label)
    commands = bytearray(contents[command_start:command_end])
    offset = 0
    linkedit = signature = None
    for _ in range(ncmds):
        if offset+8 > command_size:
            raise ValueError('Truncated Mach-O load command: '+label)
        command, length = struct.unpack_from('<II', commands, offset)
        if length < 8 or length % 8 or offset+length > command_size:
            raise ValueError('Invalid Mach-O load command size: '+label)
        if command == LC_SEGMENT_64:
            if length < 72:
                raise ValueError('Truncated Mach-O segment command: '+label)
            if commands[offset+8:offset+24].rstrip(b'\0') == b'__LINKEDIT':
                if linkedit is not None or length != 72:
                    raise ValueError('Unexpected Mach-O __LINKEDIT shape: '+label)
                linkedit = struct.unpack_from('<QQQ', commands, offset+32)
                # Only the terminal segment's file/VM extents change with the signature.
                struct.pack_into('<Q', commands, offset+32, 0)
                struct.pack_into('<Q', commands, offset+48, 0)
        elif command == LC_CODE_SIGNATURE:
            if signature is not None or length != 16:
                raise ValueError('Unexpected Mach-O code signature command: '+label)
            signature = struct.unpack_from('<II', commands, offset+8)
            struct.pack_into('<I', commands, offset+12, 0)
        offset += length
    if offset != command_size or signature is None or linkedit is None:
        raise ValueError('Incomplete signed Mach-O load commands: '+label)

    signature_offset, signature_size = signature
    vm_size, file_offset, file_size = linkedit
    aligned_vm_sizes = {(file_size+page-1)//page*page for page in (0x1000, 0x4000)}
    if (not command_size+32 <= file_offset <= signature_offset or signature_size < 12
            or signature_offset+signature_size != size or file_offset+file_size != size
            or vm_size not in aligned_vm_sizes):
        raise ValueError('Signature is not the bounded terminal region of the Mach-O: '+label)
    magic, blob_size = struct.unpack_from('>II', contents, start+signature_offset)
    if magic != 0xfade0cc0 or not 12 <= blob_size <= signature_size:
        raise ValueError('Invalid embedded code signature blob: '+label)
    # codesign reserves space for the CMS. Some input signatures retain a
    # short nonzero fragment after the superblob from an earlier signing pass.
    padding = contents[start+signature_offset+blob_size:end]
    if any(padding[64:]):
        raise ValueError('Unexpected data in embedded signature padding: '+label)

    payload = hashlib.sha256(contents[start:command_start])
    payload.update(commands)
    with memoryview(contents) as view:
        payload.update(view[command_end:start+signature_offset])
    return architecture, {
        'cpuSubtype': sub, 'fileType': kind, 'nonSignatureSha256': payload.hexdigest(),
        'signatureOffset': signature_offset, 'signatureSize': signature_size,
        'signatureSha256': hashlib.sha256(contents[start+signature_offset:end]).hexdigest(),
        'linkeditFileSize': file_size, 'linkeditVmSize': vm_size,
    }


def macho_layout(path):
    with Path(path).open('rb') as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as contents:
        if contents[:4] == THIN_64:
            architecture, layout = examine_slice(contents, 0, len(contents), None, str(path))
            return {'format': 'thin', 'slices': {architecture: layout}}

        header = FAT_HEADERS.get(contents[:4])
        if header is None or len(contents) < 8:
            raise ValueError('Unsupported Mach-O format: '+str(path))
        count, = struct.unpack_from('>I', contents, 4)
        table_end = 8+count*header.size
        if count < 2 or count > len(ARCH_NAMES) or table_end > len(contents):
            raise ValueError('Invalid universal Mach-O table: '+str(path))
        slices = {}
        previous_end = table_end
        for index in range(count):
            cpu, sub, start, size, alignment, *reserved = header.unpack_from(contents, 8+index*header.size)
            if (not previous_end <= start <= len(contents) or not 0 <= alignment <= 16
                    or start % (1 << alignment) or start-previous_end >= (1 << alignment)
                    or any(reserved) or any(contents[previous_end:start])):
                raise ValueError('Invalid universal Mach-O slice placement: '+str(path))
            architecture, layout = examine_slice(contents, start, size, (cpu, sub), str(path))
            if architecture in slices:
                raise ValueError('Repeated Mach-O architecture: '+str(path))
            slices[architecture] = {**layout, 'alignment': alignment, 'sliceOrder': index}
            previous_end = start+size
        if previous_end != len(contents):
            raise ValueError('Unrecognized data after final Mach-O slice: '+str(path))
        return {'format': 'fat64' if header.size == 32 else 'fat32', 'slices': slices}


def payload_identity(layout):
    signing_fields = {'signatureSize', 'signatureSha256', 'linkeditFileSize', 'linkeditVmSize'}
    return {'format': layout['format'],
            'slices': {arch: {key: value for key, value in details.items() if key not in signing_fields}
                       for arch, details in layout['slices'].items()}}


def macho_payload(path):
    """Return a position-independent digest of every non-signature slice byte."""
    return payload_identity(macho_layout(path))


def inspect_code(root, policy, inventory):
    root = root.resolve(strict=True)
    machos = {}
    bundles = {path for path, entry in inventory.items()
               if entry['type'] == 'directory' and PurePosixPath(path).suffix in BUNDLE_SUFFIXES}
    expected_bundles = {item.path for item in policy if item.seal}
    if bundles != expected_bundles:
        raise ValueError(f'Unexpected code bundles: missing {sorted(expected_bundles-bundles)}, '
                         f'unclassified {sorted(bundles-expected_bundles)}')
    for path, entry in inventory.items():
        if entry['type'] != 'file':
            continue
        with (root/path).open('rb') as stream:
            magic = stream.read(4)
        if magic in OTHER_MACHO:
            raise ValueError('Unsupported Mach-O code item: '+path)
        if magic == THIN_64 or magic in FAT_HEADERS:
            machos[path] = macho_layout(root/path)
        elif entry['mode'] & 0o111:
            raise ValueError('Unclassified executable product file: '+path)
    expected_machos = {item.binary for item in policy}
    if set(machos) != expected_machos:
        raise ValueError(f'Unexpected code binaries: missing {sorted(expected_machos-machos.keys())}, '
                         f'unclassified {sorted(machos.keys()-expected_machos)}')

    seals = {item.seal for item in policy if item.seal}
    declared_seals = seals | {PurePosixPath(seal).parent.as_posix() for seal in seals}
    actual_seals = {path for path in inventory if '_CodeSignature' in PurePosixPath(path).parts}
    if actual_seals != declared_seals or any(inventory[seal]['type'] != 'file' for seal in seals):
        raise ValueError('Unexpected bundle seal layout')

    records = []
    for item in policy:
        layout = machos[item.binary]
        slices = layout['slices']
        expected_kind = MH_EXECUTE if item.runtime else MH_DYLIB
        if 'arm64' not in slices or any(details['fileType'] != expected_kind for details in slices.values()):
            raise ValueError('Signing policy role/architectures disagree with Mach-O type: '+item.binary)
        if item.runtime and not inventory[item.binary]['mode'] & 0o111:
            raise ValueError('Product executable lacks execute permission: '+item.binary)
        if item.role == 'framework' and (root/item.path/'Versions/Current').resolve() != (root/item.binary).parent:
            raise ValueError('Framework default version disagrees with signing policy: '+item.path)
        if item.seal:
            manifest = (root/item.path/'Contents/Info.plist' if item.role == 'app'
                        else (root/item.binary).parent/'Resources/Info.plist')
            if (inventory.get(manifest.relative_to(root).as_posix(), {}).get('type') != 'file'
                    or not isinstance(metadata := plistlib.loads(manifest.read_bytes()), dict)
                    or metadata.get('CFBundleIdentifier') != item.identifier
                    or metadata.get('CFBundleExecutable') != Path(item.binary).name):
                raise ValueError('Bundle code metadata disagrees with signing policy: '+item.path)
        records.append({**item.record(), 'architectures': list(slices), 'machO': layout})
    return records


def discover_code(root, policy):
    """Discover the actual code graph and map it to the ordered, explicit policy."""
    return inspect_code(root, policy, product_inventory_pair(root))


def inspect_products(root, policy):
    inventory = product_inventory_pair(root)
    return {'inventory': inventory, 'codeItems': inspect_code(root, policy, inventory),
            'filesystemMetadata': metadata_observations(root, inventory)}


def verify_transform(original_root, signed_root, policy, *, replacements=()):
    """Compare the whole product trees, allowing only known signature changes."""
    before = inspect_products(original_root, policy)
    after = inspect_products(signed_root, policy)
    files_before, files_after = before['inventory'], after['inventory']
    replacements = set(replacements)
    libraries = {item.binary for item in policy if not item.runtime}
    if not replacements <= libraries:
        raise ValueError('Only explicitly identified Mach-O libraries may be replaced')
    allowed = {item.binary for item in policy} | {item.seal for item in policy if item.seal}

    def file_shape(inventory):
        return {path: ({key: value for key, value in entry.items() if key not in {'size', 'sha256'}}
                       if path in allowed else entry) for path, entry in inventory.items()}

    compare(file_shape(files_before), file_shape(files_after), 'Non-signature product inventory')
    for path, entry in files_after.items():
        candidate, original = (signed_root/path).lstat(), (original_root/path).lstat()
        if entry['type'] == 'file' and candidate.st_nlink != 1:
            raise ValueError('Signed product file has shared hard links: '+path)
        if (candidate.st_dev, candidate.st_ino) == (original.st_dev, original.st_ino):
            raise ValueError('Signed product shares an inode with its source: '+path)
    original_code = {record['binary']: record for record in before['codeItems']}
    for item in after['codeItems']:
        path = item['binary']
        original = original_code[path]['machO']
        signed = item['machO']
        same_payload = payload_identity(original) == payload_identity(signed)
        if path in replacements:
            if signed['slices'].keys() != original['slices'].keys():
                raise ValueError('Replacement library architecture set changed: '+path)
            if same_payload:
                raise ValueError('Expected replacement library payload did not change: '+path)
            continue
        if not same_payload:
            raise ValueError('Non-signature Mach-O content changed: '+path)
        for arch, actual in signed['slices'].items():
            expected = original['slices'][arch]
            if (expected['linkeditVmSize'] != actual['linkeditVmSize']
                    and expected['signatureSize'] == actual['signatureSize']):
                raise ValueError('Unexpected Mach-O __LINKEDIT virtual-size change: '+path)
    changes = [{'path': path, 'before': files_before[path], 'after': files_after[path]}
               for path in sorted(allowed) if files_before[path] != files_after[path]]
    return {'changedFiles': changes, 'replacementLibraries': sorted(replacements),
            'originalCodeItems': before['codeItems'], 'signedCodeItems': after['codeItems'],
            'filesystemMetadata': {'original': before['filesystemMetadata'],
                                   'signed': after['filesystemMetadata']}}


def identity_values(selector, team):
    if not isinstance(selector, str) or not re.fullmatch(r'[0-9A-Fa-f]{40}', selector):
        raise ValueError('Use the exact 40-character certificate SHA-1 as the identity selector')
    if not isinstance(team, str) or not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise ValueError('Expected a ten-character Developer ID Team ID')
    return selector.upper(), team


def public_certificate(path, command, name):
    details = command(name, ['/usr/bin/openssl', 'x509', '-inform', 'DER', '-in', path,
                             '-noout', '-subject', '-issuer', '-nameopt', 'sep_multiline,sname,utf8',
                             '-startdate', '-enddate', '-text'])
    der = path.read_bytes()
    return details, {'sha1': hashlib.sha1(der).hexdigest().upper(),
                     'sha256': hashlib.sha256(der).hexdigest(),
                     'notBefore': required_value(details, 'notBefore'),
                     'notAfter': required_value(details, 'notAfter')}


def required_value(output, label):
    values = re.findall(r'^'+re.escape(label)+r'=(.+)$', output, re.MULTILINE)
    if len(values) != 1 or not values[0].strip():
        raise ValueError('Missing or repeated signature field: '+label)
    return values[0].strip()


def check_public_leaf(details, team):
    subject = details.partition('subject=')[2].partition('\nissuer=')[0]
    if (re.findall(r'^\s*OU\s*=\s*(.+)$', subject, re.MULTILINE) != [team]
            or not re.search(r'^\s*'+re.escape(LEAF_OID)+r':', details, re.MULTILINE)):
        raise ValueError('Leaf certificate is not a Developer ID Application certificate for Team '+team)


def select_identity(selector, team, command):
    """Resolve a unique valid code-signing identity, using only public certificate bytes."""
    fingerprint, team = identity_values(selector, team)
    output = command('signer-available-identities', ['/usr/bin/security', 'find-identity', '-p', 'codesigning', '-v'])
    matches = re.findall(r'^\s*\d+\)\s+'+fingerprint+r'\s+"([^\r\n]+)"\s*$', output, re.MULTILINE)
    if len(matches) != 1:
        raise IdentityUnavailable('Expected one valid signing identity matching certificate '+fingerprint)
    authority = matches[0]
    if not authority.startswith(CERTIFICATE_TYPE+': '):
        raise ValueError('Selected identity is not a Developer ID Application identity')
    search = command('signer-public-certificate', ['/usr/bin/security', 'find-certificate', '-a', '-p', '-c', authority])
    matching_certificates = set()
    for pem in re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', search, re.DOTALL):
        der = ssl.PEM_cert_to_DER_cert(pem)
        if hashlib.sha1(der).hexdigest().upper() == fingerprint:
            matching_certificates.add(der)
    if len(matching_certificates) != 1:
        raise IdentityUnavailable('Cannot locate the selected identity’s public certificate')
    with tempfile.TemporaryDirectory(prefix='meshchan-signing-certificate-') as scratch:
        certificate = Path(scratch)/'leaf.der'
        certificate.write_bytes(matching_certificates.pop())
        try:
            command('signer-trust', ['/usr/bin/security', 'verify-cert', '-L', '-p', 'codeSign', '-c', certificate])
        except subprocess.CalledProcessError as error:
            raise IdentityUnavailable('Selected certificate failed local code-signing trust evaluation') from error
        details, evidence = public_certificate(certificate, command, 'signer-certificate-details')
        check_public_leaf(details, team)
    return {**evidence, 'team': team, 'authority': authority, 'certificateType': CERTIFICATE_TYPE}


def sign_products(root, policy, identity, command, *, scratch=None):
    if policy_profile(policy) == LOCAL_PROFILE:
        require_local_identity(identity)
        selector, timestamp = '-', '--timestamp=none'
    else:
        selector, _ = identity_values(identity['sha1'], identity['team'])
        timestamp = '--timestamp'
    inventory = product_inventory_pair(root)
    inspect_code(root, policy, inventory)
    for path, entry in inventory.items():
        if entry['type'] == 'file' and (root/path).lstat().st_nlink != 1:
            raise ValueError('Refusing to sign a product with shared hard links: '+path)
    with tempfile.TemporaryDirectory(prefix='signing-entitlements-', dir=scratch) as directory:
        for index, item in enumerate(policy, 1):
            argv = ['/usr/bin/codesign', '--force', '--sign', selector, timestamp,
                    '--identifier', item.identifier, *item.bundle_args()]
            if item.runtime:
                argv.extend(['--options', 'runtime'])
            if item.entitlements:
                entitlements = Path(directory)/f'{item.role}.plist'
                entitlements.write_bytes(plistlib.dumps(item.entitlements))
                argv.extend(['--entitlements', entitlements])
            command(f'sign-{index:02d}-{item.role}', [*argv, root/item.path])


def display_signature(root, item, arch, command, name):
    base = ['/usr/bin/codesign', '--display', '--architecture', arch, *item.bundle_args()]
    properties = command(name+'-display', [*base, '--verbose=4', root/item.path], return_stderr=True)
    if Path(required_value(properties, 'Executable')).resolve(strict=True) != root.resolve(strict=True)/item.binary:
        raise ValueError('Signature display returned a different executable: '+item.binary)
    # Verification and display normally select the slot preferred by macOS.
    # The release policy covers the only signature on each architecture.
    if (required_value(properties, 'Total signatures') != '1'
            or required_value(properties, 'Chosen signature') != '1'):
        raise ValueError('Expected one embedded signature in the first slot: '+item.path)
    matches = re.findall(r'^CodeDirectory [^\n]*?\bflags=0x([a-fA-F0-9]+)\([^\n]*\)[^\n]*'
                         r'\blocation=embedded$', properties, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError('Expected one selected embedded CodeDirectory: '+item.path)
    flags = int(matches[0], 16)
    if item.signing_profile == LOCAL_PROFILE and required_value(properties, 'Signature') != 'adhoc':
        raise ValueError('Signature display did not report an ad hoc signature: '+item.path)
    raw = command(name+'-entitlements', [*base, '--entitlements', '-', '--xml', root/item.path])
    entitlements = plistlib.loads(raw.encode()) if raw.strip() else {}
    if type(entitlements) is not dict:
        raise ValueError('Embedded entitlements are not a dictionary: '+item.path)
    cdhash = required_value(properties, 'CDHash')
    if not re.fullmatch(r'[0-9a-f]{40}', cdhash):
        raise ValueError('Malformed CodeDirectory hash: '+item.path)
    timestamps = re.findall(r'^Timestamp=(.*)$', properties, re.MULTILINE)
    if len(timestamps) > 1 or (timestamps and not timestamps[0].strip()):
        raise ValueError('Malformed secure timestamp: '+item.path)
    team = required_value(properties, 'TeamIdentifier')
    authorities = re.findall(r'^Authority=(.*)$', properties, re.MULTILINE)
    if any(not authority.strip() for authority in authorities):
        raise ValueError('Malformed signing authority: '+item.path)
    return {'identifier': required_value(properties, 'Identifier'), 'team': None if team == 'not set' else team,
            'authorityChain': authorities,
            'timestamp': timestamps[0] if len(timestamps) == 1 else None,
            'signatureSlots': 1, 'flags': flags,
            'runtime': bool(flags & CS_RUNTIME), 'adhoc': bool(flags & CS_ADHOC),
            'cdhash': cdhash, 'entitlements': entitlements}


def verify_signature_values(item, identity, displayed):
    if item.signing_profile == LOCAL_PROFILE:
        require_local_identity(identity)
        if (displayed['adhoc'] is not True or displayed['team'] is not None
                or displayed['authorityChain'] != [] or displayed['timestamp'] is not None
                or displayed['identifier'] != item.identifier):
            raise ValueError('Embedded ad hoc signature state differs from policy: '+item.path)
    elif item.signing_profile == DEVELOPER_PROFILE:
        verify_developer_signature(item, identity, displayed)
    else:
        raise ValueError('Unknown code signing profile: '+item.signing_profile)
    if (displayed['runtime'] is not item.runtime
            or not exact_entitlements(displayed['entitlements'], item.entitlements)):
        raise ValueError('Embedded runtime or entitlements differ from policy: '+item.path)


def verify_developer_signature(item, identity, displayed):
    chain = displayed['authorityChain']
    if (displayed['adhoc'] is not False or displayed['identifier'] != item.identifier
            or displayed['team'] != identity['team']
            or not chain or not chain[0].startswith(CERTIFICATE_TYPE+': ')
            or (identity.get('authority') is not None and chain[0] != identity['authority'])):
        raise ValueError('Embedded signing identity/Team/identifier differs from policy: '+item.path)
    if not displayed['timestamp'] or displayed['timestamp'].strip().lower() in {'none', 'not set'}:
        raise ValueError('Missing secure Timestamp in signature: '+item.path)


def verify_signatures(root, policy, identity, command, scratch):
    """Verify every discovered code item and architecture against the selected profile."""
    local = policy_profile(policy) == LOCAL_PROFILE
    if local:
        require_local_identity(identity)
    else:
        fingerprint, team = identity_values(identity['sha1'], identity['team'])
    graph = discover_code(root, policy)
    verify = ['/usr/bin/codesign', '--verify', '--strict', '--all-architectures', '--verbose=2']
    command('verify-app-nested', [*verify, '--deep', root/'Meshchan.app'])
    report = []
    with tempfile.TemporaryDirectory(prefix='certificates-', dir=scratch) as directory:
        for index, (item, discovered) in enumerate(zip(policy, graph, strict=True), 1):
            prefix = f'verify-{index:02d}-{item.role}'
            args = [*verify, *item.bundle_args()]
            if not local:
                requirement = (f'=anchor apple generic and identifier "{item.identifier}" '
                               f'and certificate 1[field.{ISSUER_OID}] exists '
                               f'and certificate leaf[field.{LEAF_OID}] exists '
                               f'and certificate leaf = H"{fingerprint}" '
                               f'and certificate leaf[subject.OU] = "{team}"')
                args.extend(['--test-requirement', requirement])
            command(prefix+'-requirement', [*args, root/item.path])
            slices = {}
            for arch in discovered['architectures']:
                name = prefix+'-'+arch
                displayed = display_signature(root, item, arch, command, name)
                verify_signature_values(item, identity, displayed)
                if local:
                    slices[arch] = displayed
                    continue
                extracted = Path(directory)/name
                command(name+'-certificate-chain', ['/usr/bin/codesign', '--display', '--architecture', arch,
                                                    *item.bundle_args(), f'--extract-certificates={extracted}',
                                                    root/item.path])
                leaf = extracted.with_name(extracted.name+'0')
                details, evidence = public_certificate(leaf, command, name+'-certificate-details')
                check_public_leaf(details, team)
                if evidence['sha1'] != fingerprint:
                    raise ValueError('Embedded leaf certificate does not match the selected fingerprint: '+item.path)
                slices[arch] = {**displayed, 'leafCertificate': evidence}
            report.append({**item.record(), 'slices': slices})
    return report
