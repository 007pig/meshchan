#!/usr/bin/env python3
"""Prepare an external four-member copy; never generate runners in the product."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

from regression_1d10 import ROOT, digest, source_manifest, write_json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--flutter', type=Path, required=True)
    args = parser.parse_args()
    target = args.destination.resolve()
    if target == ROOT or ROOT in target.parents or target in ROOT.parents:
        parser.error('Probe must be external to the product checkout')
    target.mkdir(parents=True, exist_ok=False)
    manifest = source_manifest()
    for name in manifest:
        path = target / name
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, path)
    app = target / 'apps/meshchan_app'
    original = (app / 'pubspec.yaml').read_text()
    argv = [str(args.flutter), 'create', '--platforms=android,ios', '--no-pub',
            '--project-name=meshchan_app', '--org=org.meshchan.probe', str(app)]
    # Generate hosts in the copy, then restore every original input create might touch.
    subprocess.run(argv, cwd=target, check=True)
    removed = []
    for path in sorted(app.rglob('*'), reverse=True):
        relative = path.relative_to(app)
        if relative.parts[0] in ('android', 'ios') or relative.as_posix() == '.metadata':
            continue
        if path.is_file() or path.is_symlink():
            name = str(path.relative_to(target))
            if name not in manifest:
                path.unlink()  # Only new template scaffolding in this owned copy.
                removed.append(name)
        elif path.is_dir() and not any(path.iterdir()):
            path.rmdir()
    for name in manifest:
        shutil.copy2(ROOT / name, target / name)
    (app / 'pubspec.yaml').write_text(original.replace(
        '\ndependencies:\n', '\ndependencies:\n  sqlite3: 3.9.1\n', 1))
    shutil.copy2(ROOT / 'tool/mobile_probe.dart.txt', app / 'lib/mobile_probe.dart')
    write_json(target / 'probe-source.json', {
        'fourMemberSource': manifest, 'rootLockSha256': digest(ROOT / 'pubspec.lock'),
        'createArgv': argv, 'entrypoint': 'apps/meshchan_app/lib/mobile_probe.dart',
        'removedTemplateScaffolding': sorted(removed),
        'probeOnlyDifferences': ['generated Android/iOS hosts and metadata',
            'direct sqlite3 3.9.1 dependency in copied app', 'lib/mobile_probe.dart'],
        'productMainUnchanged': digest(app / 'lib/main.dart') == manifest['apps/meshchan_app/lib/main.dart']})
    print(json.dumps({'prepared': str(target)}))


if __name__ == '__main__':
    main()
