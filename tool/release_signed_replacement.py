#!/usr/bin/env python3
"""Rebuild and exercise a synthetic libserialport replacement in local copies."""

import argparse
from contextlib import nullcontext
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tarfile
import time
import uuid

import build_release as build
import package_release_vm as vm_steps
from release_materials import (ancestor_identities, controlled_environment, digest, directory_identity, encoded,
                               product_inventory, require_material_file, require_product_disjoint, safe, sections, sha)
from release_package_archive import check_payload, compare, metadata_observations
import release_signing as signing
from release_signed_runtime import manifest_profile, parse_signed_info


APP = 'Meshchan.app'
CLI = 'meshctl'
APP_FRAMEWORK = APP + '/Contents/Frameworks/libserialport_plus.framework'
APP_LIBRARY = APP_FRAMEWORK + '/Versions/A/libserialport_plus'
CLI_LIBRARY = CLI + '/lib/liblibserialport_plus.dylib'
CLI_BINARY = CLI + '/bin/meshctl'
APP_BINARY = APP + '/Contents/MacOS/Meshchan'
APP_NOT_REFRESHED = 'No ports have been listed or opened.'
APP_EMPTY = 'No available ports were reported.'
MANIFEST = 'signed-product-info.json'
UPSTREAM_CHECK = 'upstream-provenance/package-check-receipt.json'
SOURCE_FILES = tuple('src/libserialport/' + name for name in ('serialport.c', 'timing.c', 'macosx.c'))
LIST_FUNCTION = b'SP_API enum sp_return sp_list_ports(struct sp_port ***list_ptr)\r\n{'
SOURCE_MEMBER = re.compile(r'source-materials/archives/libserialport_plus-[0-9.]+\.tar\.gz')
MARKER_START = 'MESHCHAN_MODIFIED_SERIAL_EMPTY_LIST:'


def checked_absolute(path):
    path = Path(path).expanduser().absolute()
    if path != path.resolve() or path.is_symlink():
        raise ValueError('Use a canonical path with no symlink components: ' + str(path))
    return path


def inspectable_upstream_path(path):
    # Shipped manifests name the publisher's local inputs. If another account
    # cannot inspect one of those paths, protect its nearest visible parent.
    for candidate in (path, *path.parents):
        try:
            resolved = candidate.resolve()
            ancestor_identities(resolved)
        except PermissionError:
            continue
        return resolved
    raise ValueError('Cannot inspect an ancestor of upstream release input: '+str(path))


def product_inventory_from_payload(inventory):
    return {name: item for name, item in inventory.items()
            if PurePosixPath(name).parts[:1] in ((APP,), (CLI,))}


def original_payload(root, expected):
    actual = product_inventory(root)
    compare(expected, actual, 'Pinned signed original inventory')
    for name, item in expected.items():
        if item['type'] == 'file':
            require_material_file(root, name)
    return metadata_observations(root, actual)


def serial_archive(root, inventory):
    materials = root/'materials'
    manifest = require_material_file(materials, 'materials-manifest.json')
    index_bytes = manifest.read_bytes()
    if inventory['materials/materials-manifest.json']['sha256'] != sha(index_bytes):
        raise ValueError('Original materials manifest changed')
    entries = json.loads(index_bytes)['materials']
    matches = [name for name in entries if SOURCE_MEMBER.fullmatch(name)]
    if len(matches) != 1:
        raise ValueError('Expected one archived libserialport source in the material manifest')
    relative = matches[0]
    archive = require_material_file(materials, relative)
    entry = entries[relative]
    pin = inventory['materials/' + relative]
    actual = {'size': archive.stat().st_size, 'sha256': digest(archive)}
    if any(type(entry[key]) is not type(value) or entry[key] != value
           or type(pin[key]) is not type(value) or pin[key] != value
           for key, value in actual.items()):
        raise ValueError('Archived libserialport source differs from pinned release materials')
    return archive, {'path': 'materials/' + relative, **actual,
                     'materialsManifestSha256': sha(index_bytes)}


def patch_source(source, marker):
    if not re.fullmatch(re.escape(MARKER_START) + r'[0-9a-f]{32}', marker):
        raise ValueError('Invalid synthetic libserialport marker')
    data = source.read_bytes()
    includes = b'#include "libserialport_internal.h"\r\n'
    if (data.count(LIST_FUNCTION) != 1 or data.count(includes) != 1
            or MARKER_START.encode() in data):
        raise ValueError('Expected the shipped libserialport include and port-list function')
    patch = (f'\r\n fprintf(stderr, "{marker}:%d\\n", (int)getpid());\r\n'
             ' fflush(stderr);\r\n'
             ' *list_ptr = calloc(1, sizeof(struct sp_port *));\r\n'
             ' return *list_ptr ? SP_OK : SP_ERR_MEM;\r\n').encode()
    source.write_bytes(data.replace(includes, includes + b'#include <unistd.h>\r\n')
                       .replace(LIST_FUNCTION, LIST_FUNCTION + patch))
    return {'sourceSha256': sha(data), 'patchedSourceSha256': digest(source), 'patch': patch.decode()}


def split_identifier(output, label):
    values = [line.strip() for line in output.splitlines() if line.strip() and not line.endswith(':')]
    if len(values) != 1:
        raise ValueError('Unexpected install name for ' + label)
    return values[0]


def check_install_name(path, architectures, expected, command, label):
    for arch in architectures:
        output = command(label+'-'+arch, ['/usr/bin/otool', '-arch', arch, '-D', path])
        actual = split_identifier(output, f'{path} ({arch})')
        if actual != expected:
            raise ValueError(f'Unexpected libserialport install name for {arch}: {actual}')


def replace_library(original, copies, path, source, compiler, sdk, command, label):
    old, new = original/path, copies/path
    arches = command(label+'-source-architectures', ['/usr/bin/lipo', '-archs', old]).split()
    if 'arm64' not in arches or set(arches) - {'arm64', 'x86_64'} or len(arches) != len(set(arches)):
        raise ValueError('Unsupported released libserialport architecture list')
    install_name = ('@rpath/libserialport_plus.framework/libserialport_plus' if path == APP_LIBRARY
                    else '@rpath/lib/liblibserialport_plus.dylib')
    check_install_name(old, arches, install_name, command, label+'-source-id')
    # Preserve the release paths and all supported slices. Xcode supplies the
    # system frameworks and SDK; no Flutter or Dart is used here.
    arch_flags = [item for arch in arches for item in ('-arch', arch)]
    fresh = source/(label+'.dylib')
    command(label+'-compile', [compiler, '-dynamiclib', *arch_flags, '-isysroot', sdk,
                             '-mmacosx-version-min=12.0', '-x', 'objective-c', '-std=c99',
                             '-DLIBSERIALPORT_ATBUILD', '-I', source/'src/include',
                             '-framework', 'IOKit', '-framework', 'CoreFoundation',
                             '-Wl,-headerpad_max_install_names', '-Xlinker', '-install_name',
                             '-Xlinker', install_name, *[source/name for name in SOURCE_FILES],
                             '-o', fresh])
    rebuilt = command(label+'-target-architectures', ['/usr/bin/lipo', '-archs', fresh]).split()
    if len(rebuilt) != len(arches) or set(rebuilt) != set(arches):
        raise ValueError('Modified libserialport architecture set changed')
    check_install_name(fresh, arches, install_name, command, label+'-rebuilt-id')
    for arch in arches:
        args = ['/usr/bin/nm', '-arch', arch, '-gUj']
        before = set(command(label+'-source-exports-'+arch, [*args, old]).splitlines())
        after = set(command(label+'-target-exports-'+arch, [*args, fresh]).splitlines())
        if '_sp_list_ports' not in before or before != after:
            raise ValueError('Modified libserialport exported symbols changed for ' + arch)
    shutil.copyfile(fresh, new)
    if digest(new) == digest(old):
        raise ValueError('Modified libserialport bytes did not change')
    return {'path': path, 'architectures': arches, 'installName': install_name,
            'originalSha256': digest(old), 'rebuiltSha256': digest(new)}


def local_signing_items(policy):
    if signing.policy_profile(policy) != signing.LOCAL_PROFILE:
        raise ValueError('The replacement test requires the local-adhoc signing profile')
    selected = {APP, CLI_BINARY, APP_FRAMEWORK, CLI_LIBRARY}
    items = [item for item in policy if item.path in selected]
    if {item.path for item in items} != selected:
        raise ValueError('Required local signing items missing from distribution policy')
    return items


def re_sign_local(copies, policy, command, evidence):
    # Preserve the selected local runtime and entitlements on affected code.
    items = local_signing_items(policy)
    for index, item in enumerate(items):
        args = ['/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none',
                '--identifier', item.identifier, *item.bundle_args()]
        if item.runtime:
            entitlements = evidence/('user-'+item.role+'.entitlements')
            with entitlements.open('xb') as stream:
                plistlib.dump(item.entitlements, stream)
            args += ['--options', 'runtime', '--entitlements', entitlements]
        command('local-sign-'+str(index), [*args, copies/item.path])


def verify_local_signatures(copies, policy, command, *, prefix='local'):
    """Read back the local ad hoc policy on every affected architecture."""
    items = local_signing_items(policy)
    actual = {entry['path']: entry['architectures'] for entry in signing.discover_code(copies, policy)}
    for index, item in enumerate(items):
        args = ['/usr/bin/codesign', '--verify', '--strict', '--all-architectures', *item.bundle_args()]
        if item.path == APP:
            args.append('--deep')
        command(f'{prefix}-verify-{index}', [*args, copies/item.path])
    observed = {}
    for index, item in enumerate(items):
        signatures = {}
        for arch in actual[item.path]:
            facts = signing.display_signature(copies, item, arch, command,
                                              f'{prefix}-display-{index}-{arch}')
            signing.verify_signature_values(item, signing.local_identity(), facts)
            signatures[arch] = facts
        observed[item.path] = signatures
    return observed


def prepare_copies(original, original_inventory, copies, evidence, archive, archive_sha,
                   policy, marker, command):
    copies.mkdir()
    stage_inventory = product_inventory_from_payload(original_inventory)
    for name in (APP, CLI):
        shutil.copytree(original/name, copies/name, symlinks=True, copy_function=shutil.copy2)
    copied = product_inventory(copies)
    compare(stage_inventory, {name: copied[name] for name in copied if name != '.'},
            'Unmodified user copies')
    check_payload(copies, copied)
    archive_copy = evidence/'libserialport-source.tar.gz'
    shutil.copyfile(archive, archive_copy)
    if digest(archive_copy) != archive_sha:
        raise ValueError('Source archive changed during copy')
    source = evidence/'libserialport-source'
    with tarfile.open(archive_copy, 'r:gz') as stream:
        stream.extractall(source, filter='data')
    for name in (*SOURCE_FILES, 'src/include/config.h'):
        require_material_file(source, name)
    patch = patch_source(source/SOURCE_FILES[0], marker)
    compiler = command('xcode-clang', ['/usr/bin/xcrun', '--find', 'clang']).strip()
    sdk = command('xcode-sdk', ['/usr/bin/xcrun', '--show-sdk-path']).strip()
    version = command('clang-version', [compiler, '--version'])
    libraries = {path: replace_library(original, copies, path, source, compiler, sdk, command, label)
                 for path, label in ((CLI_LIBRARY, 'cli-library'), (APP_LIBRARY, 'app-library'))}
    re_sign_local(copies, policy, command, evidence)
    transform = signing.verify_transform(original, copies, policy, replacements=(CLI_LIBRARY, APP_LIBRARY))
    allowed = {CLI_LIBRARY, APP_LIBRARY, CLI_BINARY, APP_BINARY}
    allowed.update(item.seal for item in policy if item.path in (APP, APP_FRAMEWORK))
    changed = {entry['path'] for entry in transform['changedFiles']}
    if changed - allowed or not {CLI_LIBRARY, APP_LIBRARY} <= changed:
        raise ValueError('Local re-signing changed an unrelated product file')
    verified_inventory = copied.copy()
    for entry in transform['changedFiles']:
        path = entry['path']
        compare({path: copied[path]}, {path: entry['before']}, 'Unmodified product at transformation')
        verified_inventory[path] = entry['after']
    check_payload(copies, verified_inventory)
    for path, label in ((CLI_LIBRARY, 'cli-library'), (APP_LIBRARY, 'app-library')):
        details = libraries[path]
        check_install_name(copies/path, details['architectures'], details['installName'],
                           command, label+'-local-signature-id')
        details['signedReplacementSha256'] = verified_inventory[path]['sha256']
    signatures = verify_local_signatures(copies, policy, command)
    check_payload(copies, verified_inventory)
    env = controlled_environment()
    cli_loaders = build.loader_check(copies/CLI, copies/CLI_BINARY, env)
    # The CLI embeds its dynamic asset table in the AOT image. Use the
    # accepted native hook binding and preserved install name before the
    # fresh process confirms the actual call using the unique marker.
    index = json.loads((original/'materials/materials-manifest.json').read_bytes())
    mapping = index['native'][CLI]['libserialport_plus']
    if (CLI_LIBRARY.removeprefix(CLI+'/') not in cli_loaders
            or not mapping['loader'][0].lstrip().startswith(libraries[CLI_LIBRARY]['installName']+' (')
            or mapping['sections'] != sections(original/CLI_LIBRARY)):
        raise ValueError('CLI does not reference its bundled serial native asset')
    _, assets = build.inspect_loaders(copies/APP, copies/APP_BINARY, env, app_assets=True)
    arm_assets = assets['macos_arm64']
    if APP_LIBRARY.removeprefix(APP+'/') not in {entry['target'] for entry in arm_assets.values()}:
        raise ValueError('App does not resolve its bundled serial native asset')
    return {'patch': patch, 'compiler': version, 'macosSDK': sdk, 'localSignatures': signatures,
            'libraries': libraries, 'payloadTransform': transform, 'appNativeAssets': assets,
            'verifiedInventory': verified_inventory}


def require_marker(log, marker, pid=None):
    candidates = [line for line in log.splitlines() if line.startswith(MARKER_START)]
    match = re.fullmatch(re.escape(marker)+r':([1-9][0-9]*)', candidates[0]) if len(candidates) == 1 else None
    if match is None or (pid is not None and int(match[1]) != pid):
        raise ValueError('Missing exact current-run libserialport invocation marker')
    return int(match[1])


def verify_cli_output(stdout, stderr, marker, *, pid=None):
    value = json.loads(stdout)
    if (value != {'schemaVersion': 1, 'command': 'ports', 'ports': []}
            or type(value['schemaVersion']) is not int):
        raise ValueError('Expected the exact synthetic CLI port-list result')
    return {'result': value, 'markerPid': require_marker(stderr, marker, pid)}


def read_owned_pid(raw):
    if not re.fullmatch(r'[1-9][0-9]*\n', raw) or int(raw) <= 1:
        raise ValueError('Invalid owned process PID receipt')
    return int(raw)


def read_owned_exit(raw):
    if not re.fullmatch(r'(0|[1-9][0-9]{0,2})\n', raw) or int(raw) > 255:
        raise ValueError('Invalid owned process exit receipt')
    return int(raw)


def run_cli(copies, work, runner, marker, library_sha):
    work.mkdir(mode=0o700)
    pid_receipt = work/'child.pid'
    if digest(require_material_file(copies, CLI_LIBRARY)) != library_sha:
        raise ValueError('Prepared CLI replacement hash changed')
    # The shell records the direct child PID and execs the selected binary
    # in the same process. The marker must name that PID.
    launcher = 'printf "%s\\n" "$$" > "$1" || exit\nshift\nexec "$@"'
    runner.command('modified-cli-ports',
                   ['/bin/sh', '-c', launcher, 'meshchan-replacement', pid_receipt,
                    copies/CLI_BINARY, 'ports', '--json'], work)
    step = runner.receipt['steps'][-1]
    raw_pid = require_material_file(work, pid_receipt.name).read_bytes()
    logs = {key: require_material_file(runner.root, step[key]).read_bytes()
            for key in ('log', 'stderrLog')}
    if any(sha(raw) != step[key+'Sha256'] for key, raw in logs.items()):
        raise ValueError('Current CLI logs differ from the owned process receipts')
    return {'exitCode': step['exitCode'], **verify_cli_output(logs['log'].decode(),
                                                        logs['stderrLog'].decode(), marker,
                                                        pid=read_owned_pid(raw_pid.decode())),
            'pidReceipt': pid_receipt.relative_to(runner.root).as_posix(), 'pidReceiptSha256': sha(raw_pid),
            'log': step['log'], 'logSha256': step['logSha256'],
            'stderrLog': step['stderrLog'], 'stderrLogSha256': step['stderrLogSha256']}


def verify_shutdown(stdout):
    records = [json.loads(line) for line in stdout.splitlines() if line.startswith('{')]
    matches = [entry for entry in records if entry.get('runtime') == 'meshchan.shutdown.1d3']
    if len(matches) != 1:
        raise ValueError('Expected one current App shutdown receipt')
    record = matches[0]
    if (not all(record.get(key) is True for key in ('resourcesReleased', 'workerExited', 'workerWasSpawned'))
            or not all(type(record.get(key)) is int and record[key] == 0
                       for key in ('pendingRequests', 'receivePorts', 'maintenanceFailureCount'))
            or 'error' not in record or record['error'] is not None
            or record.get('owner') != 'released' or record.get('quitPhase') != 'ready'):
        raise ValueError('App did not confirm normal storage, owner and worker release')
    return record


APP_LAUNCH_CLAIM = 'app-launch.claim'
GUEST_WATCHER = 'guest-watcher'
HOST_CANCELLED = 'host-cancelled'


def cancel_app_launch(vm, root):
    """Prevent a queued watcher from starting unless it already owns launch."""
    claim = shlex.quote(root+'/'+APP_LAUNCH_CLAIM)
    # The symlink records its owner in the atomic creation itself. A retry
    # after a lost SSH result can recover the same decision without replacing it.
    command = f'''claim={claim}
if test ! -L "$claim"; then
    test ! -e "$claim" || exit 75
    /bin/ln -sn {HOST_CANCELLED} "$claim" 2>/dev/null || true
fi
/usr/bin/readlink "$claim"
'''

    def read_owner():
        return vm.remote(command, capture_output=True, text=True, timeout=10).stdout

    try:
        owner = read_owner()
    except (ValueError, subprocess.TimeoutExpired):
        owner = read_owner()
    if owner == HOST_CANCELLED+'\n':
        return True
    if re.fullmatch(rf'{GUEST_WATCHER}:[0-9a-f]{{32}}:[1-9][0-9]*\n', owner):
        return False
    raise ValueError('Could not identify the owned App launch claim')


def watch_app(root, finish=None):
    q = shlex.quote
    argv = [root+'/Meshchan.app/Contents/MacOS/Meshchan', '--data-dir='+root+'/fixture']
    request_finish = ('\n  /usr/bin/touch '+q(finish)) if finish is not None else ''
    claim = q(root+'/'+APP_LAUNCH_CLAIM)
    token = GUEST_WATCHER+':'+uuid.uuid4().hex
    # This monitor owns one child. Queue execution stays available for UI
    # actions while it watches the child without borrowing the host desktop.
    return f"""child=
owner={token}:$$
finish_app() {{
  local code=$?
  trap - EXIT
  trap '' HUP INT TERM
  # The traps are ready before the atomic claim. Only its exact owner can
  # publish receipts, including an interruption immediately after claiming.
  [[ $(/usr/bin/readlink {claim} 2>/dev/null) == "$owner" ]] || return 0
  if [[ -n "$child" ]]; then
    if [[ $(jobs -pr) == "$child" ]]; then
      kill -TERM "$child" 2>/dev/null || true
      sleep 1
      if [[ $(jobs -pr) == "$child" ]]; then kill -KILL "$child" 2>/dev/null || true; fi
    fi
    wait "$child" || true
  fi
  if ! {{ printf '%s\\n' "$code" > {q(root+'/app.exit.tmp')} &&
       /bin/mv {q(root+'/app.exit.tmp')} {q(root+'/app.exit')}; }}; then
    echo 'Owned App exit receipt could not be published' >&2
  fi{request_finish}
}}
trap finish_app EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
if ! /bin/ln -sn "$owner" {claim} 2>/dev/null ||
   [[ $(/usr/bin/readlink {claim}) != "$owner" ]]; then
  exit 75
fi
cd {q(root+'/cwd')}
# Latch an interrupt through the fork and registration of the owned child.
pending=
trap 'pending=${{pending:-129}}' HUP
trap 'pending=${{pending:-130}}' INT
trap 'pending=${{pending:-143}}' TERM
/usr/bin/env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin LANG=en_US.UTF-8 TMPDIR={q(root+'/cwd')} \\
  {shlex.join(argv)} > {q(root+'/app.stdout')} 2> {q(root+'/app.stderr')} < /dev/null &
child=$!
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
[[ -z "$pending" ]] || exit "$pending"
printf '%s\\n' "$child" > {q(root+'/app.pid.tmp')}
/bin/mv {q(root+'/app.pid.tmp')} {q(root+'/app.pid')}
deadline=$((SECONDS + 90))
while [[ $(jobs -pr) == "$child" ]]; do
  if (( SECONDS >= deadline )); then exit 124; fi
  sleep 0.1
done
code=0
wait "$child" || code=$?
child=
exit "$code"
"""


def snapshot_has(rows, expected):
    return any(expected == row.get(key) for row in rows for key in ('title', 'value', 'description'))


def wait_for(probe, timeout, message):
    deadline = time.monotonic()+timeout
    while True:
        if result := probe():
            return result
        if time.monotonic() >= deadline:
            raise ValueError(message)
        time.sleep(0.15)


def guest_read(vm, path, *, wait=False):
    quoted = shlex.quote(path)
    command = ('if test -f '+quoted+'; then /bin/cat '+quoted+'; fi'
               if wait else '/bin/cat '+quoted)
    return vm.remote(command, capture_output=True, text=True, timeout=10).stdout


def run_app(copies, evidence, vm_config, marker, app_library_hash, *,
            app_inventory, on_failure=None, configuration=None):
    app = copies/APP
    check_payload(app, app_inventory)
    relative = APP_LIBRARY.removeprefix(APP+'/')
    if app_inventory[relative]['sha256'] != app_library_hash:
        raise ValueError('Prepared App replacement hash changed')
    host = vm_steps.load('signed_replacement_vm_host', 'apps/meshchan_app/tool/macos_vm/host.py')
    if configuration is None:
        configuration = nullcontext(vm_config)
    with configuration as config:
        product = host.Product(str(config), evidence)
    vm, q = product.vm, shlex.quote
    vm_steps.require_ready_connection(vm)
    session = vm_steps.guest_session(vm)
    launch_attempted = False
    app_reaped = False
    pid = None
    app_error = None
    try:
        vm_steps.start_guest(vm, session)
        if not vm_steps.record_guest_run(product, session, timeout=10):
            raise ValueError('Timed out waiting for owned user-library guest executor')
        products = vm.root+'/products'
        root = products+'/'+product.state['run']+'-Release'
        vm.remote('set -e\numask 077\n/bin/mkdir -p '+q(products)
                  +'\ntest ! -L '+q(products)+'\n/bin/mkdir '+q(root)
                  +'\n/bin/mkdir '+shlex.join([root+'/fixture', root+'/cwd']), timeout=10)
        product.upload([(app, APP)], root)
        vm_steps.guest_inventory(vm, root, app_inventory, scratch=evidence)
        remote_app = root+'/'+APP
        vm.remote('/usr/bin/codesign --verify --deep --strict --all-architectures '+q(remote_app),
                  timeout=30)
        finish = vm.runpath(product.state['run'])+'/finish'
        launch_attempted = True
        product.job('(\n'+watch_app(root, finish)+'\n) > '+q(root+'/app-supervisor.log')
                    +' 2>&1 < /dev/null &')
        raw_pid = wait_for(lambda: guest_read(vm, root+'/app.pid', wait=True), 10,
                           'Owned App did not report a PID')
        pid = read_owned_pid(raw_pid)
        product.state['products']['Release'] = {
            'root': root, 'pid': pid, 'sourceApp': str(app),
            'executableSha256': app_inventory['Contents/MacOS/Meshchan']['sha256'],
        }
        product.save()

        def activate():
            try:
                product.act('Release', ['activate'])
                return True
            except ValueError:
                return False

        wait_for(activate, 20, 'Owned replacement App did not display its Meshchan window')
        product.act('Release', ['size', '1200', '850'])
        product.act('Release', ['nav', 'Device'])
        before = json.loads(product.act('Release', ['snapshot']))
        if (not snapshot_has(before, APP_NOT_REFRESHED) or snapshot_has(before, APP_EMPTY)
                or MARKER_START in guest_read(vm, root+'/app.stderr')):
            raise ValueError('Unexpected call to serial library before the controlled refresh')
        # Confirm the exact mapped library bytes in this instance's bundle
        # immediately before taking the only action that enumerates metadata.
        remote = vm.remote('/usr/bin/shasum -a 256 < '+q(remote_app+'/'+relative),
                           capture_output=True, text=True, timeout=10).stdout
        if remote != app_library_hash+'  -\n':
            raise ValueError('Guest refresh target differs from the synthetic replacement library')
        product.act('Release', ['click', 'Refresh'])

        def read_app_result():
            rows = json.loads(product.act('Release', ['snapshot']))
            return rows if snapshot_has(rows, APP_EMPTY) and not snapshot_has(rows, APP_NOT_REFRESHED) else None

        rows = wait_for(read_app_result, 10, 'App did not display the synthetic empty list')
        snapshots = evidence/'refresh-state.json'
        refresh_evidence = {'before': before, 'after': rows}
        build.write(snapshots, refresh_evidence)
        product.act('Release', ['screenshot', root+'/synthetic-ports.png'])
        product.act('Release', ['key', 'q', 'command'])
        code = wait_for(lambda: guest_read(vm, root+'/app.exit', wait=True), 20,
                        'Owned replacement App did not finish Quit')
        exit_code = read_owned_exit(code)
        vm_steps.require_absent_pid(vm, pid)
        app_reaped = True
        product.collect('Release')
        if exit_code:
            raise ValueError('Replacement App did not exit zero')
        names = ('refresh-state.json', 'Release/app.stdout', 'Release/app.stderr',
                 'Release/app.pid', 'Release/app.exit', 'Release/synthetic-ports.png')
        collected = {name: require_material_file(evidence, name).read_bytes() for name in names}
        if (collected['refresh-state.json'] != encoded(refresh_evidence)
                or collected['Release/app.pid'] != raw_pid.encode()
                or collected['Release/app.exit'] != code.encode()
                or not collected['Release/synthetic-ports.png'].startswith(b'\x89PNG\r\n\x1a\n')):
            raise ValueError('Collected App receipts differ from current-run observations')
        shutdown = verify_shutdown(collected['Release/app.stdout'].decode())
        require_marker(collected['Release/app.stderr'].decode(), marker, pid)
        vm_steps.guest_inventory(vm, root, app_inventory, scratch=evidence)
        check_payload(app, app_inventory)
        product.state['products']['Release']['shutdown'] = shutdown
        product.save()
        collected['session.json'] = require_material_file(evidence, 'session.json').read_bytes()
        if json.loads(collected['session.json']) != product.state:
            raise ValueError('App session receipt differs from current guest ownership')
        result = {'guestRun': product.state['run'], 'pid': pid, 'exitCode': 0,
                  'shutdown': shutdown, 'pidAbsent': True, 'guestLibrarySha256': app_library_hash,
                  'appInventorySha256': sha(encoded(app_inventory)), 'inventoryBefore': 'PASS',
                  'inventoryAfter': 'PASS', 'result': APP_EMPTY}
    except (Exception, KeyboardInterrupt) as error:
        app_error = error
        # Guest cleanup can outlast the supervising host process's signal
        # grace period. Publish the primary failure while the host can write.
        if on_failure is not None:
            try:
                on_failure(error)
            except (Exception, KeyboardInterrupt) as publish_error:
                app_error = ValueError(build.failure_message(error)+'\nFailure receipt could not be written: '
                                       +build.failure_message(publish_error))
                raise app_error from None
        raise
    finally:
        try:
            # A queued job can outlive an interrupted SSH command. Where no
            # PID was observed, resolve whether it is still safe to cancel.
            if launch_attempted and pid is None and cancel_app_launch(vm, root):
                launch_attempted = False
            if launch_attempted and not app_reaped:
                read_owned_exit(wait_for(lambda: guest_read(vm, root+'/app.exit', wait=True), 95,
                                         'Owned guest monitor did not settle after interruption'))
                raw_pid = guest_read(vm, root+'/app.pid', wait=True)
                if raw_pid and pid is None:
                    pid = read_owned_pid(raw_pid)
                if pid is not None:
                    vm_steps.require_absent_pid(vm, pid)
            try:
                if launch_attempted and not app_reaped and 'Release' in product.state['products']:
                    product.collect('Release')
            finally:
                # Once the monitor owns launch, it finishes its exact executor
                # after App exit even if the host orchestrator was interrupted.
                if launch_attempted:
                    executor_exit = vm_steps.confirm_guest_exit(product)
                else:
                    executor_exit = vm_steps.finish_guest(product, session, check_product_shutdown=False)
        except (Exception, KeyboardInterrupt) as cleanup_error:
            if app_error is None:
                raise
            raise ValueError(build.failure_message(app_error)+'\nGuest cleanup failed: '
                             +build.failure_message(cleanup_error)) from None
    if type(executor_exit) is not int or executor_exit != 0:
        raise ValueError('Replacement App executor did not finish normally')
    result.update(guestExecutorExit=executor_exit, guestLockReleased=True,
                  evidence={name: sha(raw) for name, raw in collected.items()})
    return result


def run(signed_root, output, *, inventory=None, signed_info_sha256, vm_config=None, timeout=900):
    root = checked_absolute(signed_root)
    output = checked_absolute(output)
    config = checked_absolute(vm_config) if vm_config is not None else None
    protected = (root, build.ROOT/'.git', build.ROOT/'.dart_tool', build.ROOT/'apps',
                 Path.home()/vm_steps.DEFAULT_DATA_SUBDIR)
    require_product_disjoint({'Replacement output': output},
                             (*protected, config) if config is not None else protected)
    # pathlib comparisons alone miss case aliases on case-insensitive volumes.
    in_checkout = directory_identity(build.ROOT) in ancestor_identities(output)
    if in_checkout and not output.is_relative_to(build.ROOT/'build'):
        raise ValueError('Use an external output or a canonical ignored build subdirectory')
    if not re.fullmatch(r'[0-9a-f]{64}', signed_info_sha256):
        raise ValueError('Expected an independently selected signed-product-info SHA-256')
    manifest = require_material_file(root, MANIFEST).read_bytes()
    if sha(manifest) != signed_info_sha256:
        raise ValueError('Signed product manifest differs from its selected SHA-256')
    info = parse_signed_info(manifest)
    if manifest_profile(info) != signing.LOCAL_PROFILE:
        raise ValueError('The replacement test requires a local-adhoc candidate manifest')
    upstream = info['upstream']
    source = Path(upstream['sourceCheckout'])
    package_run = Path(upstream['packageRun'])
    check_bytes = require_material_file(root, UPSTREAM_CHECK).read_bytes()
    if sha(check_bytes) != upstream['upstreamCheckReceiptSha256']:
        raise ValueError('Archived upstream check receipt differs from the selected candidate')
    upstream_check = json.loads(check_bytes, object_pairs_hook=signing.policy_object)
    extract_root = Path(upstream_check['extractRoot'])
    if not all(path.is_absolute() for path in (source, package_run, extract_root)):
        raise ValueError('Replacement input has malformed upstream product paths')
    upstream_paths = [inspectable_upstream_path(path)
                      for path in (source/safe(upstream['buildRun']), package_run, extract_root)]
    source_guard = inspectable_upstream_path(source)
    if directory_identity(source_guard) != directory_identity(build.ROOT):
        upstream_paths.append(source_guard)
    require_product_disjoint({'Replacement output': output}, upstream_paths,
                             protected='an upstream release input')
    expected = info['payloadInventory']
    if type(expected) is not dict or MANIFEST in expected:
        raise ValueError('Signed product payload inventory must exclude its own manifest')
    if inventory is not None:
        compare(inventory, expected, 'Selected signed product manifest')
    full_expected = expected | {MANIFEST: {'type': 'file', 'mode': 0o600, 'size': len(manifest),
                                         'sha256': signed_info_sha256}}
    configuration = (vm_steps.checked_vm_configuration(config, (*protected, *upstream_paths, output, build.ROOT))
                     if config is not None else None)
    return _run_replacement(root, output, info, full_expected, config, timeout, configuration=configuration)


def _run_replacement(root, output, info, full_expected, config, timeout, *, configuration):
    original_metadata = original_payload(root, full_expected)
    signed_info_sha256 = full_expected[MANIFEST]['sha256']
    expected = info['payloadInventory']

    output.mkdir(mode=0o700)
    evidence = output/'evidence'
    evidence.mkdir(mode=0o700)
    copies = output/'user products'
    scratch = evidence/'certificate-observations'
    scratch.mkdir(mode=0o700)
    marker = MARKER_START+uuid.uuid4().hex
    report = {'formatVersion': 2, 'signingProfile': info['signingProfile'],
              'status': 'RUNNING', 'steps': [], 'marker': marker,
              'signedInfoSha256': signed_info_sha256, 'identity': info['identity'],
              'filesystemMetadata': {'originalBefore': original_metadata},
              'signedRoot': str(root), 'cli': {'status': 'NOT_RUN'}, 'app': {'status': 'NOT_RUN'}}
    receipt = evidence/'replacement-receipt.json'
    env = {**controlled_environment(), 'TMPDIR': str(scratch)}
    runner = build.Runner(output, evidence, report, env, timeout=timeout)
    build.write(receipt, report)
    try:
        index = info['policy']
        relative = 'tool/release_signing_policy.json'
        policy_bytes = require_material_file(root, 'signing-source/'+relative).read_bytes()
        if index != {'path': relative, 'sha256': sha(policy_bytes)}:
            raise ValueError('Candidate signing policy differs from its manifest')
        policy = signing.parse_policy(policy_bytes)
        if signing.policy_profile(policy) != info['signingProfile']:
            raise ValueError('Candidate signing policy profile conflict')
        actual_signatures = signing.verify_signatures(root, policy, info['signature']['identity'],
                                                      runner.command, scratch)
        if encoded(info['signature']['items']) != encoded(actual_signatures):
            raise ValueError('Candidate signatures differ from their manifest')
        archive, report['sourceArchive'] = serial_archive(root, expected)
        report['replacement'] = prepare_copies(root, expected, copies, evidence, archive,
                                                report['sourceArchive']['sha256'], policy,
                                                marker, runner.command)
        modified = report['replacement']['verifiedInventory']
        check_payload(copies, modified)
        report['filesystemMetadata']['modifiedBefore'] = metadata_observations(copies, modified)
        library_hashes = report['replacement']['libraries']
        if any(digest(copies/path) != row['signedReplacementSha256']
               for path, row in library_hashes.items()):
            raise ValueError('Synthetic replacement library changed before execution')
        report['modifiedInventorySha256'] = sha(encoded(modified))
        report['cli'] = {'status': 'FAIL'}
        report['cli'] = {'status': 'PASS', **run_cli(copies, output/'cli working directory', runner, marker,
                                        library_hashes[CLI_LIBRARY]['signedReplacementSha256'])}
        build.write(receipt, report)
        if config is not None:
            app_inventory = {'.' if name == APP else name.removeprefix(APP+'/'): entry
                             for name, entry in modified.items()
                             if name == APP or name.startswith(APP+'/')}
            report['app'] = {'status': 'FAIL', 'evidenceRoot': 'evidence/app-vm'}

            def publish_app_failure(error):
                report.update(status='FAIL', error=build.failure_message(error))
                build.write(receipt, report)

            report['app'] = {'status': 'PASS', **run_app(copies, evidence/'app-vm', config, marker,
                                    library_hashes[APP_LIBRARY]['signedReplacementSha256'],
                                    app_inventory=app_inventory, on_failure=publish_app_failure,
                                    configuration=configuration)}
        else:
            report['app']['reason'] = 'The independent guest App acceptance requires --vm-config'
        check_payload(copies, modified)
        report['filesystemMetadata']['modifiedAfter'] = metadata_observations(copies, modified)
        report['filesystemMetadata']['originalAfter'] = original_payload(root, full_expected)
        report['finalIntegrity'] = 'PASS'
        report['status'] = 'PASS' if report['app']['status'] == 'PASS' else 'INCOMPLETE'
    except (Exception, KeyboardInterrupt) as error:
        report.update(status='FAIL', error=build.failure_message(error))
        raise
    finally:
        build.write(receipt, report)
    return {**report, 'receipt': str(receipt), 'receiptSha256': sha(encoded(report))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--signed-root', type=Path, required=True)
    parser.add_argument('--signed-info-sha256', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--vm-config', type=Path)
    parser.add_argument('--timeout', type=build.command_timeout, default=900)
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, vm_steps.interrupted)
    try:
        result = run(args.signed_root, args.output, signed_info_sha256=args.signed_info_sha256,
                     vm_config=args.vm_config, timeout=args.timeout)
    except (Exception, KeyboardInterrupt) as error:
        print('ERROR: '+build.failure_message(error), file=sys.stderr)
        return 1
    print(json.dumps({key: result[key] for key in ('status', 'signingProfile', 'receipt', 'receiptSha256')}, indent=2))
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
