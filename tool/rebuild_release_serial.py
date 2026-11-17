#!/usr/bin/env python3
"""Rebuild exact LGPL sources and test a modified library in isolated full copies.

The modified sp_list_ports returns an empty list before reaching any OS backend.
No real USB enumeration, port open, RF operation, or user database is used.
"""
import argparse
import ctypes
import hashlib
import json
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile


def digest(p):
    with Path(p).open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archive', type=Path, required=True)
    p.add_argument('--archive-sha256', required=True)
    p.add_argument('--cli', type=Path, required=True)
    p.add_argument('--app', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--attach-vm-evidence', type=Path,
                   help='Attach an existing normally closed, identity-checked product VM observation')
    p.add_argument('--vm-config', type=Path)
    a = p.parse_args()
    if a.attach_vm_evidence:
        if not a.vm_config:
            raise ValueError('--vm-config is required for VM evidence verification')
        attach_vm(a)
        return
    if digest(a.archive) != a.archive_sha256:
        raise ValueError('Source archive differs from locked archive')
    work = Path(tempfile.mkdtemp(prefix='meshchan-lgpl-', dir='/tmp'))
    src = work/'source'
    with tarfile.open(a.archive, 'r:gz') as tar:
        tar.extractall(src, filter='data')
    commands = []
    def run(argv):
        result = subprocess.run([str(v) for v in argv], text=True, capture_output=True)
        commands.append({'argv': [str(v) for v in argv], 'exitCode': result.returncode,
                         'stdout': result.stdout, 'stderr': result.stderr})
        result.check_returncode()
        return result
    compiler = run(['/usr/bin/xcrun', '--find', 'clang']).stdout.strip()
    version = run([compiler, '--version']).stdout
    sdk = run(['/usr/bin/xcrun', '--show-sdk-path']).stdout.strip()
    base = [compiler, '-dynamiclib', '-arch', 'arm64', '-isysroot', sdk,
            '-mmacosx-version-min=12.0', '-x', 'objective-c', '-std=c99',
            '-Wall', '-Wextra', '-pedantic', '-Wmissing-prototypes', '-Wshadow',
            '-DLIBSERIALPORT_ATBUILD', '-I', src/'src/include',
            '-framework', 'IOKit', '-framework', 'CoreFoundation',
            '-Wl,-headerpad_max_install_names']
    sources = [src/'src/libserialport'/s for s in ('serialport.c', 'timing.c', 'macosx.c')]
    original = work/'rebuilt-original.dylib'
    run(base+sources+['-o', original])
    lib = ctypes.CDLL(str(original))
    lib.sp_get_package_version_string.restype = ctypes.c_char_p
    package_version = lib.sp_get_package_version_string().decode()
    serial = sources[0]
    data = serial.read_bytes()
    marker = b'SP_API enum sp_return sp_list_ports(struct sp_port ***list_ptr)\r\n{'
    if data.count(marker) != 1:
        raise ValueError('Expected exact locked source function')
    patch = b'\r\n fprintf(stderr, "MESHCHAN_MODIFIED_SERIAL_EMPTY_LIST\\n");\r\n *list_ptr = calloc(1, sizeof(struct sp_port *));\r\n return *list_ptr ? SP_OK : SP_ERR_MEM;\r\n'
    serial.write_bytes(data.replace(marker, marker+patch))
    modified = work/'rebuilt-modified.dylib'
    run(base+sources+['-o', modified])
    if digest(original) == digest(modified):
        raise ValueError('Modified library must differ')
    run(['/usr/bin/ditto', a.cli.resolve(), work/'cli'])
    run(['/usr/bin/ditto', a.app.resolve(), work/'Meshchan.app'])
    cli_lib = work/'cli/lib/liblibserialport_plus.dylib'
    shutil.copyfile(modified, cli_lib)
    run(['/usr/bin/install_name_tool', '-id', '@rpath/liblibserialport_plus.dylib', cli_lib])
    run(['/usr/bin/codesign', '--force', '--sign', '-', cli_lib])
    # Complete CLI copy; no executable patch or environment injection.
    check = run([work/'cli/bin/meshctl', 'ports', '--json'])
    if 'MESHCHAN_MODIFIED_SERIAL_EMPTY_LIST' not in check.stderr or '"ports":[]' not in check.stdout.replace(' ', '').replace('\n', ''):
        raise ValueError('Product did not load/use modified library')
    app_lib = work/'Meshchan.app/Contents/Frameworks/libserialport_plus.framework/Versions/A/libserialport_plus'
    shutil.copyfile(modified, app_lib)
    run(['/usr/bin/install_name_tool', '-id', '@rpath/libserialport_plus.framework/libserialport_plus', app_lib])
    run(['/usr/bin/codesign', '--force', '--sign', '-', work/'Meshchan.app/Contents/Frameworks/libserialport_plus.framework'])
    run(['/usr/bin/codesign', '--force', '--sign', '-', work/'Meshchan.app'])
    run(['/usr/bin/codesign', '--verify', '--deep', '--strict', work/'Meshchan.app'])
    a.output.parent.mkdir(parents=True, exist_ok=True)
    report = {'formatVersion': 1, 'sourceArchiveSha256': digest(a.archive), 'workspace': str(work),
              'compiler': version, 'macosSdk': sdk, 'packageVersionReported': package_version,
              'originalRebuiltSha256': digest(original), 'modifiedSha256': digest(modified),
              'patchedSourceSha256': digest(serial), 'patch': patch.decode(),
              'cliOriginalSha256': digest(a.cli/'bin/meshctl'),
              'appOriginalSha256': digest(a.app/'Contents/MacOS/Meshchan'),
              'cliModifiedLibraryLoaded': True, 'appModifiedLibraryLoaded': False,
              'appPreparedCopy': str(work/'Meshchan.app'),
              'meaning': 'CLI product runtime marker and empty synthetic port list verified. App replacement copy signed ad hoc and structurally verified; no App runtime observation here. No Developer ID claim.',
              'commands': commands}
    a.output.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({k: report[k] for k in ('workspace', 'originalRebuiltSha256', 'modifiedSha256', 'cliModifiedLibraryLoaded', 'appModifiedLibraryLoaded')}, indent=2))


def attach_vm(a):
    import shlex
    from release_materials import serial_app_binding
    report = json.loads(a.output.read_text())
    # Never rebind an old observation to a new candidate, even at the same path.
    # Validate before creating a VM client or changing the report.
    serial_app_binding(report, a.app)
    spec = importlib.util.spec_from_file_location('product_host', Path(__file__).resolve().parents[1]/'apps/meshchan_app/tool/macos_vm/host.py')
    host = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(host)
    product = host.Product(str(a.vm_config), a.attach_vm_evidence)
    observed = product.state['products']['Release']
    if Path(observed['sourceApp']).resolve() != Path(report['appPreparedCopy']).resolve():
        raise ValueError('VM did not use the rebuilt replacement App')
    if observed.get('executableSha256') != digest(Path(report['appPreparedCopy'])/'Contents/MacOS/Meshchan'):
        raise ValueError('VM observation does not bind the prepared App executable')
    shutdown = observed['shutdown']
    if not all(shutdown[k] is True for k in ('resourcesReleased', 'workerExited')) or shutdown['owner'] != 'released':
        raise ValueError('VM App normal release not established')
    stderr = a.attach_vm_evidence/'Release/app.stderr'
    if 'MESHCHAN_MODIFIED_SERIAL_EMPTY_LIST' not in stderr.read_text():
        raise ValueError('VM product did not call the modified library')
    relative = 'Contents/Frameworks/libserialport_plus.framework/Versions/A/libserialport_plus'
    local = Path(report['appPreparedCopy'])/relative
    remote = observed['root']+'/Meshchan.app/'+relative
    result = product.vm.remote('/usr/bin/shasum -a 256 '+shlex.quote(remote), capture_output=True, text=True)
    if result.stdout.split()[0] != digest(local):
        raise ValueError('Guest replacement library differs from isolated copy')
    report['appModifiedLibraryLoaded'] = True
    report['appReplacedLibrarySha256'] = digest(local)
    report['appEvidence'] = {name: {'path': str(path.resolve()), 'sha256': digest(path)}
        for name, path in [('session.json', a.attach_vm_evidence/'session.json'),
                           ('stderr.log', stderr), ('stdout.log', a.attach_vm_evidence/'Release/app.stdout')]}
    report['meaning'] = 'Unmodified-source rebuild and CLI/App modified-library runtime calls verified without hardware; App ran in identity-checked VM and quit normally. Local ad hoc conditions only; repeat at 1E.6.'
    a.output.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({'appModifiedLibraryLoaded': True, 'guestLibrarySha256': digest(local), 'normalShutdown': shutdown}, indent=2))


if __name__ == '__main__':
    main()
