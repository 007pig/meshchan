#!/usr/bin/env python3
"""Package and independently check a frozen macOS arm64 Release handoff."""
import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import platform
import re
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urljoin, urlparse

import build_release as build
from release_materials import (controlled_environment, digest, encoded, product_inventory,
                               require_material_file, require_product_disjoint, safe, sha,
                               unlisted_material_files)
from release_package_archive import (archive_stamp, check_payload, compare, create_archive,
                                     extract_archive, metadata_observations, new_extraction_root,
                                     open_archive, prefixed)

ROOT = build.ROOT
DIR = {'type': 'directory', 'mode': 0o755}
INDEXES = ('build-info.json', 'evidence/build-receipt.json', 'evidence/candidate-inventories.json')
VM_DIR = 'apps/meshchan_app/tool/macos_vm/'
SKILL = '.agents/skills/macos-vm-gui-testing/'
SOURCES = (
    'LICENSE', 'COPYRIGHT', 'CLA.md', 'CONTRIBUTING.md',
    'docs/releases/phase-1e5-package.md', 'docs/releases/phase-1e4-build.md',
    'docs/macos-vm-gui-testing.md', 'docs/releases/project-license-decision.json',
    'tool/package_release.py', 'tool/package_release_vm.py', 'tool/release_package_archive.py',
    'tool/package_release_test.py', *('tool/'+name for name in build.HELPERS),
    VM_DIR+'host.py', VM_DIR+'product.sh', VM_DIR+'MeshchanUI.swift',
    'apps/meshchan_app/tool/check_macos_runtime.py', SKILL+'SKILL.md',
    *(SKILL+'scripts/'+name for name in ('vm.py', 'guest.sh', 'stop-guest.sh', 'askpass.sh')),
)
GIT = ['/usr/bin/git', '-c', 'core.fsmonitor=false']
SHA256 = re.compile(r'[a-f0-9]{64}')
README = b"""# Meshchan engineering package

Open Meshchan.app for the macOS App. From this directory, run
`./meshctl/bin/meshctl --version` or `./meshctl/bin/meshctl --help`.
Keep the complete meshctl directory together, including its lib directory.

The materials directory contains the accepted licenses, notices and corresponding
source. The provenance directory carries the upstream build indexes.
The packaging-source directory carries the separate engineering packaging inputs.
See package-info.json for the file inventory and original locations.

This is a macOS arm64 engineering candidate with local build signatures.
Public distribution, installation, upgrades and other runtime environments have
separate acceptance gates.
"""
VALIDATOR = """
import json, sys
from pathlib import Path
sys.path.insert(0, 'tool')
import build_release as b
receipt, app, cli = map(Path, sys.argv[2:])
data = receipt.read_bytes()
if b.sha(data) != sys.argv[1]:
    raise ValueError('Native validator build receipt differs from the accepted SHA-256')
hooks = b.verify_native_hook_cache(receipt, json.loads(data))
print(json.dumps(b.products(b.ROOT, app, cli, b.identity(b.ROOT),
                            b.controlled_environment(), hook_cache=hooks)))
"""


def equal(expected, actual, label):
    if expected != actual:
        raise ValueError(label+' differs from its bound expectation')


def verify_report_fields(report, expected, label):
    for key, value in expected.items():
        actual = report.get(key)
        if type(actual) is not type(value) or actual != value:
            raise ValueError(f'{label} {key} differs from its bound expectation')


def canonical(value):
    raw = Path(value).expanduser().absolute()
    if raw.resolve() != raw or raw.is_symlink():
        raise ValueError('Use a canonical path with no symlink aliases: '+str(raw))
    return raw


def disjoint(path, protected):
    require_product_disjoint({'Output': path}, protected, protected='a protected path')


def real_directory(path):
    if not stat.S_ISDIR(path.lstat().st_mode):
        raise ValueError('Expected a real directory: '+str(path))
    return path


def git(cwd, *args):
    return subprocess.check_output([*GIT, *args], cwd=cwd, env=controlled_environment(),
                                   timeout=20, text=True)


def output_path(value, new):
    path = canonical(value)
    if path.parent != ROOT/'build/phase-1e5':
        raise ValueError('Use a direct child of the development checkout build/phase-1e5 directory')
    tracked = git(ROOT, '--literal-pathspecs', 'ls-files', '--cached', '-z', '--',
                  path.relative_to(ROOT).as_posix())
    if tracked or not git(ROOT, 'check-ignore', '--', path.relative_to(ROOT).as_posix()):
        raise ValueError('Package output must be ignored and disjoint from tracked source')
    if new and os.path.lexists(path):
        raise ValueError('Preserve the existing package run; choose a fresh directory')
    if not new:
        real_directory(path)
    return path


def selected_info(source, relative, pin):
    path = Path(relative)
    if (path.is_absolute() or path.parts[:2] != ('build', 'phase-1e4') or len(path.parts) < 3
            or path.as_posix() != relative or '..' in path.parts):
        raise ValueError('Use the selected run path relative to the frozen checkout')
    run = real_directory(canonical(source/path))
    data = require_material_file(run, INDEXES[0]).read_bytes()
    equal(pin, sha(data), 'Accepted build-info SHA-256')
    info = json.loads(data)
    equal(relative, info['runIdentity'], 'Selected build run')
    if info['engineeringDirtyMode'] is not False or info['workingTree']:
        raise ValueError('The selected build must have frozen source')
    if info['materials']['status'] != 'PASS':
        raise ValueError('The selected build requires accepted strict materials')
    return run, info


def protected_caches(source, info):
    options = info['materials']['arguments']
    tools = info['toolchain']
    config = require_material_file(source, '.dart_tool/package_config.json')
    package_roots = [Path(unquote(urlparse(urljoin(config.as_uri(), item['rootUri'])).path))
                     for item in build.read(config)['packages']]
    return [Path(options['downloads']), Path(options['sdkSourceWorkspace']),
            Path(tools['flutterPath']), Path(tools['macosSdk']['path']),
            Path.home()/'.pub-cache', *package_roots]


def git_metadata(root):
    return [Path(git(root, 'rev-parse', '--path-format=absolute', option).strip())
            for option in ('--git-dir', '--git-common-dir')]


def file_entry(path):
    st = path.lstat()
    if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1:
        raise ValueError('Expected a single-link regular file: '+str(path))
    return {'type': 'file', 'mode': stat.S_IMODE(st.st_mode), 'size': st.st_size, 'sha256': digest(path)}


def bytes_entry(data):
    return {'type': 'file', 'mode': 0o644, 'size': len(data), 'sha256': sha(data)}


def material_inventory(path, reference, receipt_sha, commit):
    manifest_file = require_material_file(path, 'materials-manifest.json')
    data = manifest_file.read_bytes()
    equal(reference, sha(data), 'Accepted material manifest')
    manifest = json.loads(data)
    equal(commit, manifest['sourceCommit'], 'Material source commit')
    equal(receipt_sha, manifest['products']['buildReceipt']['sha256'], 'Material build receipt')
    if manifest['openGates'] or not manifest['materials']:
        raise ValueError('The material manifest has open gates or lacks its inventory')
    for name in manifest['materials']:
        require_material_file(path, name)
    if extras := unlisted_material_files(path, manifest['materials']):
        raise ValueError('Unlisted material: '+extras[0])
    inventory = product_inventory(path)
    listed = manifest['materials'] | {'materials-manifest.json': {'size': len(data), 'sha256': reference}}
    compare(listed, {name: {**listed[name], 'size': entry['size'], 'sha256': entry['sha256']}
                     for name, entry in inventory.items() if entry['type'] == 'file'},
            'Accepted material file bytes')
    return inventory


def verify_frozen_helpers(source, info):
    equal(info['sourceCommit'], git(source, 'rev-parse', 'HEAD').strip(), 'Frozen checkout commit')
    helpers = info['helperHashes']
    if not {'tool/'+name for name in build.HELPERS} <= helpers.keys():
        raise ValueError('Frozen build lacks its recorded checker and helper hashes')
    for name, expected in helpers.items():
        equal(expected, digest(require_material_file(source, name)), 'Frozen helper '+name)


def read_bound_index(run, name, entry):
    data = require_material_file(run, name).read_bytes()
    equal(entry['sha256'], sha(data), 'Parsed build index '+name)
    return json.loads(data)


def snapshot(source, run, info, pin):
    # The externally supplied handoff digest anchors all original index and
    # binding references. The frozen checker verifies their full semantics.
    bound = {INDEXES[0]: pin}
    bound.update({ref['path']: ref['sha256'] for ref in info['evidence'].values()})
    bound.update({ref['path']: ref['sha256'] for ref in info['materials']['references'].values()})
    def read_bound(name, expected):
        path = run/INDEXES[0] if name == INDEXES[0] else source/safe(name)
        if not path.is_relative_to(run):
            raise ValueError('Evidence lies outside the selected build: '+name)
        relative = path.relative_to(run).as_posix()
        entry = file_entry(require_material_file(run, relative))
        equal(expected, entry['sha256'], 'Bound file '+name)
        return relative, entry

    inputs = dict(read_bound(name, expected) for name, expected in bound.items())
    receipt = read_bound_index(run, INDEXES[1], inputs[INDEXES[1]])
    equal(info['sourceCommit'], receipt['sourceCommit'], 'Receipt source commit')
    equal(inputs[INDEXES[2]]['sha256'], receipt['candidateInventoriesSha256'], 'Receipt product inventory')
    inputs.update(read_bound(step[name], step[name+'Sha256']) for step in receipt['steps']
                  for name in ('log', 'stderrLog') if name in step)
    products = read_bound_index(run, INDEXES[2], inputs[INDEXES[2]])
    app, cli = build.product_paths(run)
    material_path = Path(info['materials']['arguments']['output'])
    if material_path.parent != run:
        raise ValueError('Accepted materials are outside the selected build')
    reference = info['materials']['references']['materials-manifest.json']
    equal(material_path/'materials-manifest.json', source/safe(reference['path']), 'Material location')
    trees = {'Meshchan.app': (app, products['app']), 'meshctl': (cli, products['cli']),
             'materials': (material_path, material_inventory(material_path, reference['sha256'],
                                                             inputs[INDEXES[1]]['sha256'], info['sourceCommit']))}
    metadata = {}
    for label, (path, expected) in trees.items():
        if canonical(path) != path:
            raise ValueError('Invalid product path: '+str(path))
        if label != 'materials':
            check_payload(path, expected)
        metadata[label] = metadata_observations(path, expected)
    return trees, inputs, metadata


def tool_identity():
    files = {name: file_entry(require_material_file(ROOT, name)) for name in SOURCES}
    return {'gitCommit': git(ROOT, 'rev-parse', 'HEAD').strip(),
            'workingTree': git(ROOT, 'status', '--porcelain=v1', '--untracked-files=all',
                               '--', *SOURCES).splitlines(), 'inputs': files}


def original_package(output, pin, source, run, info):
    path = require_material_file(output, 'evidence/package-receipt.json')
    data = path.read_bytes()
    if pin is not None:
        equal(pin, sha(data), 'Original package receipt SHA-256')
    result = json.loads(data)
    verify_report_fields(result, {'formatVersion': 1, 'command': 'package'}, 'Original package receipt')
    equal((str(source), run.relative_to(source).as_posix(), info['sourceCommit'], info['identity']),
          (result['sourceCheckout'], result['buildRun'], result['sourceCommit'], result['identity']),
          'Original package source')
    return result


def layout(source, run, info, trees, inputs, tools, top):
    payload = {'.': DIR}
    locations = {}
    for name, (path, expected) in trees.items():
        payload.update(prefixed(name, expected))
        locations[name] = {'sourceRelativeToRun': path.relative_to(run).as_posix(),
                           'stageRelativeToPackageRun': 'stage/'+top+'/'+name,
                           'archiveMemberAndExtractionRelativePath': top+'/'+name}
    copies = {'provenance/'+Path(name).name: (run/name, inputs[name]) for name in INDEXES}
    for name, entry in tools['inputs'].items():
        if safe(name) == '.':
            raise ValueError('Invalid packaging input path')
        copies['packaging-source/'+name] = ROOT/name, entry
    for name, (_, entry) in copies.items():
        payload[name] = entry
        for parent in Path(name).parents:
            payload.setdefault(parent.as_posix(), DIR)
    payload['README.md'] = bytes_entry(README)
    package_info = encoded({
        'formatVersion': 1, 'identity': info['identity'], 'sourceCommit': info['sourceCommit'],
        'buildRecipeVersion': info['recipeVersion'], 'sourceCheckout': str(source),
        'buildRun': info['runIdentity'], 'toolInputs': tools['inputs'], 'locations': locations,
        'upstreamSha256': {name: inputs[name]['sha256'] for name in INDEXES} |
        {'materials-manifest.json': trees['materials'][1]['materials-manifest.json']['sha256']},
        'payloadInventory': payload, 'inventoryExclusions': ['package-info.json'],
    })
    return copies, package_info, payload | {'package-info.json': bytes_entry(package_info)}


def create_stage(stage, copies, package_info, inventory, trees):
    stage.mkdir(mode=0o755)
    stage.chmod(DIR['mode'])
    for name, (source, _) in trees.items():
        shutil.copytree(source, stage/name, symlinks=True, copy_function=shutil.copy)
    for name, (source, _) in copies.items():
        target = stage/name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(source, target)
    for name in inventory:
        if name.startswith('packaging-source') or name == 'provenance':
            if inventory[name]['type'] == 'directory':
                (stage/name).chmod(DIR['mode'])
    for name, data in {'README.md': README, 'package-info.json': package_info}.items():
        path = stage/name
        with path.open('xb') as stream:
            stream.write(data)
        path.chmod(0o644)


def file_stamp(path):
    with open_archive(canonical(path)) as stream:
        return archive_stamp(stream)


def require_extraction_root(path, original):
    if not os.path.samestat(original, canonical(path).lstat()):
        raise ValueError('Extraction directory differs from the owned root')


def persist_report(path, value):
    build.write(path, value)
    return {'path': str(path), 'sha256': digest(path)}


def vm_report_reference(output, path, result, expected):
    equal('PASS', result['status'], 'VM App acceptance')
    run = result['guestRun']
    if not isinstance(run, str) or not run.strip():
        raise ValueError('VM App verifier did not identify a guest run')
    name = path.relative_to(output).as_posix()
    data = require_material_file(output, name).read_bytes()
    report = json.loads(data)
    fields = {
        **expected, 'status': 'PASS', 'guestRun': run,
        'guestInventoryBefore': 'PASS', 'guestInventoryAfter': 'PASS',
        'guestSignature': 'PASS', 'guestExecutorExit': 0, 'guestLockReleased': True,
    }
    verify_report_fields(report, fields, 'VM App receipt')
    return {'path': name, 'sha256': sha(data)}


def validate_cli(bundle, cwd, runner, version):
    exe = bundle/'bin/meshctl'
    runner.env = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LANG': 'en_US.UTF-8',
                  'LC_ALL': 'en_US.UTF-8', 'HOME': str(cwd), 'TMPDIR': str(cwd),
                  'DYLD_PRINT_LIBRARIES': '1'}
    equal('meshctl '+version, runner.command('cli-version', [exe, '--version'], cwd).strip(),
          'Compiled CLI version')
    data = cwd/'owned CLI data'
    start = [exe, '--data-dir', data, 'draft']
    title, body = 'Packaging smoke', 'Offline sample 中文\r\nsecond line\n'
    calls = [('cli-write', ['create', '--title', title, '--body', body, '--json']),
             ('cli-read', None)]
    rows = []
    for name, args in calls:
        if args is None:
            args = ['show', '--id', rows[0]['report']['draft']['id'], '--json']
        result = json.loads(runner.command(name, [*start, *args], cwd))
        draft = result['draft']
        verify_report_fields(result, {'exitCode': 0, 'operationSucceeded': True, 'schemaVersion': 1}, name)
        verify_report_fields(result['storageClose'], {'state': 'closed'}, name+' storage close')
        verify_report_fields(draft, {'title': title, 'body': body, 'revision': 1,
                                     'bodyUtf8ByteLength': len(body.encode())}, name+' draft')
        trace = (runner.evidence/'logs'/(name+'.stderr.log')).read_text()
        local = str((bundle/build.CLI_SQLITE_LIBRARY).resolve())
        loaded = {path.removeprefix('/System/Volumes/Data') for path in
                  re.findall(r'^dyld\[\d+\]: <[0-9A-Fa-f-]+> (/.+)$', trace, re.MULTILINE)}
        if local not in loaded:
            raise ValueError('CLI operation did not load its own extracted SQLite: '+name)
        rows.append({'name': name, 'sqliteLoadedFrom': local, 'report': result})
    equal(rows[0]['report']['draft'], rows[1]['report']['draft'], 'Draft after process reopen')
    db = require_material_file(data, 'meshchan.sqlite')
    with closing(sqlite3.connect(db.as_uri()+'?mode=ro&immutable=1', uri=True)) as connection:
        equal([('ok',)], connection.execute('pragma quick_check').fetchall(), 'SQLite integrity')
        drafts = connection.execute('select id, title, body, revision from stored_drafts').fetchall()
    equal([(rows[0]['report']['draft']['id'], title, body, 1)], drafts, 'Persisted SQLite draft')
    return {'status': 'PASS', 'processes': rows, 'database': str(db),
            'databaseSha256': digest(db), 'storedDrafts': drafts}


def upstream_ledgers(source, run, before):
    phases = ('check-inputs-', 'check-products-', 'materials-recheck-', 'check-commit-')
    result = {}
    for prefix in phases:
        matches = [path for path in (run/'evidence').glob(prefix+'*') if path not in before]
        if len(matches) != 1:
            raise ValueError('Expected one new frozen verification ledger for '+prefix)
        name = (matches[0]/'build-receipt.json').relative_to(source).as_posix()
        data = require_material_file(source, name).read_bytes()
        equal('PASS', json.loads(data)['status'], 'Frozen verification '+prefix)
        result[prefix.rstrip('-')] = {'path': name, 'sha256': sha(data)}
    return result


def run_package(args):
    new = args.command == 'package'
    root = real_directory(canonical(args.source_checkout))
    output = output_path(args.output if new else args.package_run, new)
    extract = canonical(args.extract_root)
    real_directory(extract.parent)
    if os.path.lexists(extract):
        raise ValueError('Use a fresh external extraction directory')
    run, info = selected_info(root, args.build_run, args.expected_build_info_sha256)
    caches = [*protected_caches(root, info), *git_metadata(ROOT), *git_metadata(root)]
    disjoint(output, [root, run, *caches] if root != ROOT else [run, *caches])
    disjoint(extract, [ROOT, root, *caches])
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise ValueError('Real engineering verification requires macOS arm64')
    if new:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.mkdir(mode=0o700)
        evidence = output/'evidence'
        evidence.mkdir(mode=0o700)
    else:
        parent = real_directory(canonical(output/'evidence'))
        evidence = Path(tempfile.mkdtemp(prefix='check-', dir=parent))

    started = build.now()
    receipt_path = evidence/'package-receipt.json'
    record = {'formatVersion': 1, 'status': 'RUNNING', 'startedAt': started,
              'command': args.command, 'sourceCheckout': str(root), 'buildRun': args.build_run,
              'identity': info['identity'], 'sourceCommit': info['sourceCommit'],
              'python': {'path': sys.executable, 'resolvedPath': str(Path(sys.executable).resolve()),
                         'version': sys.version, 'sha256': digest(Path(sys.executable))},
              'host': info['toolchain']['host'], 'extractRoot': str(extract),
              'frozenStatus': 'NOT_RUN', 'integrityStatus': 'NOT_RUN',
              'postRuntimeIntegrityStatus': 'NOT_RUN', 'cliStatus': 'NOT_RUN',
              'vmAppStatus': 'NOT_RUN'}
    build.write(receipt_path, record)
    pin = args.expected_build_info_sha256
    with build.DeferredInterrupts() as interrupted:
        runner = build.Runner(output, evidence, {'status': 'RUNNING', 'steps': []},
                              controlled_environment(), args.timeout, interrupted)

        def finish(status):
            record.update(status=status, finishedAt=build.now())
            if runner.receipt['steps']:
                runner.receipt['status'] = status
                runner.save()
                record['processLedger'] = build.ref(output, evidence/'build-receipt.json')
            build.write(receipt_path, record)

        try:
            tools = tool_identity()
            record['packagingTool'] = tools
            with build.checkout_lock(root):
                verify_frozen_helpers(root, info)
                initial = snapshot(root, run, info, pin)
                previous = set((run/'evidence').iterdir())
            # This exact public entry owns the same checkout lock while checking.
            # Reacquire it before consuming anything and compare the original cut.
            record['frozenStatus'] = 'RUNNING'
            build.write(receipt_path, record)
            upstream = build.material_result(runner.command(
                'frozen-check', [sys.executable, '-B', root/'tool/build_release.py', 'check',
                                 '--output', args.build_run, '--require-frozen',
                                 '--timeout', str(args.timeout)], cwd=root))
            with build.checkout_lock(root):
                verify_frozen_helpers(root, info)
                equal({'status': 'PASS', 'buildStatus': 'PASS', 'materialsStatus': 'PASS',
                       'run': args.build_run}, upstream, 'Frozen verification outcome')
                record['frozenVerification'] = {'result': upstream, 'ledgers': upstream_ledgers(root, run, previous)}
                equal(initial, snapshot(root, run, info, pin), 'Original candidate after frozen check')
                record['frozenStatus'] = 'PASS'
                verify_package(args, output, extract, evidence, runner, record, initial, tools, root, run, info)
                verify_frozen_helpers(root, info)
                equal(initial, snapshot(root, run, info, pin), 'Original candidate after runtime acceptance')
                equal(tools, tool_identity(), 'Packaging inputs during acceptance')
                record['postRuntimeIntegrityStatus'] = 'PASS'
                status = 'PASS' if args.vm_config else 'INCOMPLETE'
                build.raise_if_interrupted(interrupted)
                finish(status)
                while not interrupted.seal_if_unchanged(0):
                    build.raise_if_interrupted(interrupted)
                return record
        except BaseException as error:
            for key in ('frozenStatus', 'integrityStatus', 'postRuntimeIntegrityStatus', 'cliStatus', 'vmAppStatus'):
                if record[key] == 'RUNNING':
                    record[key] = 'FAIL'
            record['error'] = build.failure_message(error)
            if interrupted:
                record['interruptSignal'] = int(interrupted[0])
            finish('FAIL')
            raise


def verify_package(args, output, extract, evidence, runner, record, initial, tools, root, run, info):
    trees, inputs, source_metadata = initial
    identity = info['identity']
    top = safe('Meshchan-'+identity['productVersion']+'-'+identity['target'])
    stage = output/'stage'/top
    archive = output/'archives'/(top+'.tar')
    record['integrityStatus'] = 'RUNNING'
    new = args.command == 'package'
    original = None
    if not new:
        pin = args.expected_package_receipt_sha256
        original = original_package(output, pin, root, run, info)
        if pin is not None:
            tools = original['packagingTool']
            record['originalPackageReceiptSha256'] = pin
    copies, package_info, inventory = layout(root, run, info, trees, inputs, tools, top)
    expected = prefixed(top, inventory)
    link_roots = (top+'/Meshchan.app', top+'/meshctl')
    if new:
        stage.parent.mkdir()
        archive.parent.mkdir()
        create_stage(stage, copies, package_info, inventory, trees)
    real_directory(canonical(stage))
    canonical(archive)
    check_payload(stage, inventory)
    stage_metadata = metadata_observations(stage, inventory)
    equal(initial, snapshot(root, run, info, args.expected_build_info_sha256),
          'Original candidate after staging')
    build.raise_if_interrupted(runner.interrupted)
    stamp = create_archive(archive, stage, expected) if new else file_stamp(archive)
    archive_entry = {'path': archive.relative_to(output).as_posix(), **stamp[0]}
    package_entry = {'path': (stage/'package-info.json').relative_to(output).as_posix(),
                     **inventory['package-info.json']}
    if original is not None:
        equal(archive_entry, original['archive'], 'Original engineering archive')
        equal(package_entry, original['packageInfo'], 'Original package manifest')
    equal(initial, snapshot(root, run, info, args.expected_build_info_sha256),
          'Original candidate after archiving')
    check_payload(canonical(stage), inventory)
    unpacked = extract/top
    cwd = extract/'runtime workspace'
    with new_extraction_root(canonical(extract)) as target, open_archive(canonical(archive)) as stream:
        extraction_root = os.fstat(target)
        equal(stamp, archive_stamp(stream), 'Archive opened for extraction')
        extract_archive(stream, target, expected, link_roots)
        require_extraction_root(extract, extraction_root)
        os.mkdir(cwd.name, mode=0o700, dir_fd=target)
    equal(stamp, file_stamp(archive), 'Archive after extraction')
    check_payload(canonical(unpacked), inventory)
    extracted_metadata = metadata_observations(unpacked, inventory)
    record.update(archive=archive_entry, packageInfo=package_entry, stage=str(stage), extracted=str(unpacked),
                  metadata={'source': source_metadata, 'stage': stage_metadata, 'extracted': extracted_metadata,
                            'policy': 'Preserve all data and modes; omit system-managed com.apple.provenance.'})

    runner.env = {**controlled_environment(), 'TMPDIR': str(cwd)}
    products = json.loads(runner.command(
        'relocated-products', [sys.executable, '-B', '-c', VALIDATOR,
                               inputs[INDEXES[1]]['sha256'], run/INDEXES[1],
                               unpacked/'Meshchan.app', unpacked/'meshctl'], cwd=root))
    equal('PASS', products['status'], 'Relocated native and signature checks')
    record['staticReport'] = persist_report(evidence/'relocated-products.json', products)
    record['integrityStatus'] = 'PASS'
    record['cliStatus'] = 'RUNNING'
    cli = validate_cli(unpacked/'meshctl', cwd, runner, identity['productVersion'])
    record['cliReport'] = persist_report(evidence/'cli-runtime.json', cli)
    record['cliStatus'] = 'PASS'
    if args.vm_config:
        record['vmAppStatus'] = 'RUNNING'
        runner.env = controlled_environment()
        app = unpacked/'Meshchan.app'
        result = runner.command('vm-app-runtime', [sys.executable, '-B', ROOT/'tool/package_release_vm.py',
                                '--config='+str(args.vm_config.expanduser().absolute()), '--app', app,
                                '--package-info', unpacked/'package-info.json',
                                '--evidence', evidence/'vm-app'], cwd=ROOT)
        vm_result = build.material_result(result)
        record['vmAppReport'] = vm_report_reference(output, evidence/'vm-app/runtime.json', vm_result, {
            'app': str(app), 'identity': identity, 'packageInfoSha256': package_entry['sha256'],
            'appInventorySha256': sha(encoded(trees['Meshchan.app'][1])),
        })
        record['vmAppStatus'] = 'PASS'
    record['postRuntimeIntegrityStatus'] = 'RUNNING'
    equal(stamp, file_stamp(archive), 'Archive after runtime acceptance')
    require_extraction_root(extract, extraction_root)
    check_payload(canonical(stage), inventory)
    check_payload(canonical(unpacked), inventory)
    metadata_observations(stage, inventory)
    metadata_observations(unpacked, inventory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for name in ('package', 'check'):
        cmd = commands.add_parser(name)
        cmd.add_argument('--source-checkout', type=Path, required=True)
        cmd.add_argument('--build-run', required=True)
        cmd.add_argument('--expected-build-info-sha256', required=True)
        if name == 'package':
            cmd.add_argument('--output', type=Path, default=Path('build/phase-1e5/run-001'))
        else:
            cmd.add_argument('--package-run', type=Path, required=True)
            cmd.add_argument('--expected-package-receipt-sha256',
                             help='Recorded receipt hash for checking a package made with older tooling')
        cmd.add_argument('--extract-root', type=Path, required=True)
        cmd.add_argument('--vm-config', type=Path, help='Existing private macOS VM configuration')
        cmd.add_argument('--timeout', type=build.command_timeout, default=3600, help='Per-command seconds')
    args = parser.parse_args()
    if sys.version_info < (3, 15) or sys.version_info.releaselevel != 'final':
        parser.error('Use a stable Python 3.15 or newer')
    if not SHA256.fullmatch(args.expected_build_info_sha256):
        parser.error('Use the accepted lowercase SHA-256 of build-info.json')
    if (args.command == 'check' and args.expected_package_receipt_sha256 is not None
            and not SHA256.fullmatch(args.expected_package_receipt_sha256)):
        parser.error('Use the recorded lowercase SHA-256 of the original package receipt')
    try:
        record = run_package(args)
    except (Exception, KeyboardInterrupt) as error:
        print('ERROR: '+build.failure_message(error), file=sys.stderr)
        return 1
    print(json.dumps({name: record[name] for name in ('status', 'packageInfo', 'archive', 'stage',
                                                     'vmAppStatus')}, indent=2))
    return 0 if record['status'] == 'PASS' else 2


if __name__ == '__main__':
    sys.exit(main())
