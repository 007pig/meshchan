#!/usr/bin/env python3
"""Bounded production-entry persistence/normal-quit and whole-app relocation."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--evidence', type=Path)
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
    root = (args.evidence or Path(tempfile.mkdtemp(prefix='meshchan-1d3-app-'))).resolve()
    root.mkdir(parents=True, exist_ok=True)
    fixture = root / 'meshchan-1d3-sqlite'
    runs = []
    for product, mode in [(app, 'write'), (app, 'read'), (root / 'Meshchan.app', 'read')]:
        if product != app and not product.exists():
            shutil.copytree(app, product, symlinks=True)
        argv = [str(product / 'Contents/MacOS/Meshchan'), '--meshchan-runtime=' + mode,
                '--data-dir=' + str(fixture), '--runtime-exit']
        result = subprocess.run(argv, cwd=root, capture_output=True, text=True, timeout=120)
        output = [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')]
        reports = [r for r in output if r.get('verification') == 'meshchan.runtime.1d3']
        shutdown = [r for r in output if r.get('runtime') == 'meshchan.shutdown.1d3']
        entry = {'argv': argv, 'cwd': str(root), 'exitCode': result.returncode,
                 'stdout': result.stdout, 'stderr': result.stderr, 'reports': reports,
                 'shutdown': shutdown}
        runs.append(entry)
        (root / 'runtime-processes.json').write_text(json.dumps(runs, indent=2))
        if result.returncode != 0 or len(reports) != 1 or reports[0].get('passed') is not True:
            raise RuntimeError('Runtime acceptance failed; see ' + str(root))
        if reports[0]['receivePorts'] or reports[0]['pendingRequests']:
            raise RuntimeError('Client resources were not drained')
        phases = reports[0]['phases']
        if not all(phase in phases for phase in ('opening', 'ready', 'closing', 'closed')) or (
                phases.index('opening') >= phases.index('ready')):
            raise RuntimeError('Production bridge did not observe Opening before Ready and final close')
        if len(shutdown) != 1 or not shutdown[0]['resourcesReleased'] or not shutdown[0]['workerExited']:
            raise RuntimeError('Normal quit did not confirm the shared shutdown barrier')
    signature = subprocess.run(['codesign', '--verify', '--deep', '--strict', '--all-architectures',
                                str(root / 'Meshchan.app')], capture_output=True, text=True)
    (root / 'signature.json').write_text(json.dumps({'exitCode': signature.returncode,
        'stdout': signature.stdout, 'stderr': signature.stderr}, indent=2))
    signature.check_returncode()
    for mode, fixture_name, phases in [('quit-starting', 'startup', ('starting', 'opening')),
                                      ('quit-ready', 'ready', ('ready',))]:
        quit_run = subprocess.run([str(app / 'Contents/MacOS/Meshchan'),
            '--meshchan-runtime=' + mode,
            '--data-dir=' + str(root / ('meshchan-1d3-' + fixture_name))],
            cwd=root, capture_output=True, text=True, timeout=120)
        quit_reports = [json.loads(line) for line in quit_run.stdout.splitlines() if line.startswith('{')]
        (root / (fixture_name + '-quit.json')).write_text(json.dumps({'exitCode': quit_run.returncode,
            'stdout': quit_run.stdout, 'stderr': quit_run.stderr, 'reports': quit_reports}, indent=2))
        if quit_run.returncode or len(quit_reports) != 1 or not quit_reports[0]['resourcesReleased']:
            raise RuntimeError(mode + ' did not pass its actual release/exit barrier')
        report = quit_reports[0]
        if report['workerWasSpawned'] and not report['workerExited']:
            raise RuntimeError('A spawned worker must actually exit before quit')
        if report['quitPhase'] not in phases:
            raise RuntimeError(mode + ' arrived in an unexpected phase')
        if report['pendingRequests'] or report['receivePorts']:
            raise RuntimeError(mode + ' did not dispose its client resources')
        if mode == 'quit-ready' and not report['workerWasSpawned']:
            raise RuntimeError('Ready quit must close an actual live owner')
    print(json.dumps({'passed': True, 'evidence': str(root), 'runs': len(runs)}))


if __name__ == '__main__':
    main()
