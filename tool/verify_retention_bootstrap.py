"""Authenticate a retained verifier before running it from a private copy.

Run this standalone program from a trusted location outside the retained object.
"""

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile


RECEIPT = 'retention-receipt.json'
MANIFEST = 'retention-manifest.json'
ENTRY_POINT = Path('tool/retain_release.py')
RUN_VERIFIER = """
import os
import runpy
import sys

sys.argv = sys.argv[1:]
sys.path.insert(0, os.path.dirname(sys.argv[0]))
runpy.run_path(sys.argv[0], run_name='__main__')
"""


def enclosing_checkout(path):
    # A home-level dotfiles repository does not make the user's other
    # project and archive directories part of an engineering checkout.
    home = Path.home()
    return next((parent for parent in path.parents if parent != home and os.path.lexists(parent/'.git')), None)


def require_checkout_boundaries(work, outputs):
    checkout = enclosing_checkout(work)
    if checkout is not None and work.parent != checkout/'build/phase-1e8':
        raise ValueError('Checkout work directory must be a fresh child of build/phase-1e8')
    for label, path in outputs.items():
        if enclosing_checkout(path) is not None:
            raise ValueError(f'{label} must be outside a Git checkout: {path}')


@contextmanager
def opened_directory(name, parent=None):
    fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
    try:
        yield fd
    finally:
        os.close(fd)


def read_regular(parent, name, *, expected_size=None, expected_sha256=None):
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
    with os.fdopen(os.open(name, flags, dir_fd=parent), 'rb') as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise ValueError(f'Expected a single-link regular input: {name}')
        if expected_size is not None and before.st_size != expected_size:
            raise ValueError(f'Input differs from its pinned size: {name}')
        if expected_sha256 is not None:
            # Authenticate large or damaged JSON inputs before allocating their data.
            if hashlib.file_digest(stream, 'sha256').hexdigest() != expected_sha256:
                raise ValueError(f'Input differs from its SHA-256 pin: {name}')
            stream.seek(0)
        data = stream.read(before.st_size + 1)
        after = os.fstat(stream.fileno())
        if (len(data) != before.st_size or before.st_mode != after.st_mode
                or before.st_mtime_ns != after.st_mtime_ns or before.st_ctime_ns != after.st_ctime_ns):
            raise ValueError(f'Input changed while being read: {name}')
        if expected_sha256 is not None and hashlib.sha256(data).hexdigest() != expected_sha256:
            raise ValueError(f'Input differs from its SHA-256 pin: {name}')
        return data, stat.S_IMODE(before.st_mode)


def pinned_object(parent, name, expected_sha256):
    if type(expected_sha256) is not str or not re.fullmatch(r'[0-9a-f]{64}', expected_sha256):
        raise ValueError(f'Expected a lowercase SHA-256 pin for {name}')
    data, _ = read_regular(parent, name, expected_sha256=expected_sha256)

    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f'Duplicate JSON key in {name}: {key}')
            result[key] = value
        return result

    value = json.loads(data, object_pairs_hook=unique)
    if type(value) is not dict or type(value.get('formatVersion')) is not int or value['formatVersion'] != 1:
        raise ValueError(f'Unsupported bootstrap input: {name}')
    return value


def stage_verifier(retention, receipt_pin, destination):
    """Copy only byte-verified verifier inputs to an existing private directory."""
    if not retention.is_absolute() or retention.resolve(strict=True) != retention:
        raise ValueError('Use a canonical absolute retention path')
    seen = set()
    with opened_directory(retention) as retained:
        receipt = pinned_object(retained, RECEIPT, receipt_pin)
        if receipt.get('status') != 'SEALED':
            raise ValueError('Expected a sealed retention receipt')
        expected = pinned_object(retained, MANIFEST, receipt['manifestSha256'])['verifier']

        def stage(source, relative):
            key = relative.as_posix()
            mode = stat.S_IMODE(os.fstat(source).st_mode)
            if expected.get(key) != {'type': 'directory', 'mode': mode}:
                raise ValueError(f'Verifier directory differs from the pinned manifest: {key}')
            seen.add(key)
            for name in sorted(os.listdir(source)):
                member = relative/name
                key = member.as_posix()
                entry = expected.get(key, {})
                if entry.get('type') == 'directory':
                    (destination/member).mkdir(mode=0o700)
                    with opened_directory(name, source) as directory:
                        stage(directory, member)
                elif entry.get('type') == 'file':
                    data, mode = read_regular(source, name, expected_size=entry['size'])
                    actual = {'type': 'file', 'mode': mode, 'size': len(data),
                              'sha256': hashlib.sha256(data).hexdigest()}
                    if actual != entry:
                        raise ValueError(f'Verifier file differs from the pinned manifest: {key}')
                    with (destination/member).open('xb') as output:
                        output.write(data)
                    seen.add(key)
                else:
                    raise ValueError(f'Unexpected verifier member: {key}')

        with opened_directory('verifier', retained) as source:
            stage(source, Path('.'))
    if seen != expected.keys() or expected.get(ENTRY_POINT.as_posix(), {}).get('type') != 'file':
        raise ValueError('The pinned verifier inventory or entry point is missing')
    return destination/ENTRY_POINT


def main(argv=None):
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('command', choices=('check', 'restore'))
    cli.add_argument('--retention', required=True, type=Path)
    cli.add_argument('--receipt-sha256', required=True)
    cli.add_argument('--work', required=True, type=Path)
    cli.add_argument('--destination', type=Path)
    args = cli.parse_args(argv)
    if (args.command == 'restore') != (args.destination is not None):
        cli.error('--destination is required for restore and unavailable for check')
    command = [args.command, '--retention', str(args.retention), '--receipt-sha256', args.receipt_sha256,
               '--work', str(args.work)]
    if args.destination is not None:
        command += ['--destination', str(args.destination)]
    try:
        outputs = {'Restore directory': args.destination.resolve()} if args.destination is not None else {}
        require_checkout_boundaries(args.work.resolve(), outputs)
        with tempfile.TemporaryDirectory(prefix='meshchan-verified-retention-') as private:
            script = stage_verifier(args.retention, args.receipt_sha256, Path(private))
            return subprocess.run([sys.executable, '-I', '-S', '-B', '-c', RUN_VERIFIER, str(script), *command],
                                  check=False).returncode
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        print(f'Retention bootstrap failed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
