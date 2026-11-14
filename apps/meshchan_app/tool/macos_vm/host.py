#!/usr/bin/env python3
"""Meshchan VM UI harness; host orchestration emits no GUI input events."""
import argparse
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shlex
import subprocess
import sys
import tarfile
import tempfile
import time

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
SKILL = REPO / '.agents/skills/macos-vm-gui-testing/scripts'
spec = importlib.util.spec_from_file_location('meshchan_vm', SKILL / 'vm.py')
vm_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vm_module)
q = shlex.quote
MODES = ['Debug','Release','DebugDiscard','ReleaseDiscard','DebugDevice','ReleaseDevice']


class Product:
    def __init__(self, config, evidence):
        self.vm = vm_module.VM(config)
        if self.vm.root != '/Users/' + self.vm.c['user'] + '/utm-ui-isolation':
            raise ValueError('Meshchan product runner requires the default dedicated guest_root before launching an owner')
        self.out = Path(evidence).resolve()
        self.out.mkdir(parents=True, exist_ok=True)
        self.state_path = self.out / 'session.json'
        self.state = json.loads(self.state_path.read_text()) if self.state_path.exists() else {'products': {}}

    def save(self):
        self.state_path.write_text(json.dumps(self.state, indent=2) + '\n')

    def upload(self, entries, destination):
        with tempfile.TemporaryFile() as stream:
            with tarfile.open(fileobj=stream, mode='w') as archive:
                for source, name in entries:
                    archive.add(source, arcname=name)
            stream.seek(0)
            self.vm.remote('set -e\nmkdir -p ' + q(destination) + '\n/usr/bin/tar -xf - -C ' + q(destination), stdin=stream, timeout=180)

    def prepare(self):
        if 'run' in self.state:
            raise ValueError('This evidence directory already has a run; reuse it or choose a new directory')
        driver = self.out / 'meshchan-ui'
        subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(self.out / 'module-cache'), str(HERE / 'MeshchanUI.swift'), '-o', str(driver)], check=True)
        subprocess.run(['codesign', '--force', '--sign', '-', str(driver)], check=True)
        self.vm.remote('test ! -d ' + q(self.vm.root + '/active.lock'), timeout=10)
        self.upload([(SKILL / 'guest.sh','guest.sh'), (SKILL / 'stop-guest.sh','stop-guest.sh'), (HERE / 'product.sh','product.sh'), (driver,'product-bin/meshchan-ui')], self.vm.root)
        capture = io.StringIO()
        with contextlib.redirect_stdout(capture):
            self.vm.start('product')
        self.state['run'] = capture.getvalue().strip()
        self.save()
        print(self.state['run'])

    def job(self, script):
        run = self.vm.runpath(self.state['run'])
        job = str(time.time_ns())
        # The queue is private to this explicit GUI-session executor run.
        self.vm.remote('set -e\ntest ! -f ' + q(run + '/exit-code') + '\ncat > ' + q(run + '/queue/' + job + '.tmp') + '\nmv ' + q(run + '/queue/' + job + '.tmp') + ' ' + q(run + '/queue/' + job + '.sh'), input='set -euo pipefail\n' + script + '\n', text=True, timeout=10)
        reply = run + '/replies/' + job
        try:
            result = self.vm.remote('for attempt in {1..200}; do\n if test -f ' + q(reply + '.exit') + '; then cat ' + q(reply + '.stdout') + '; cat ' + q(reply + '.stderr') + ' >&2; exit "$(cat ' + q(reply + '.exit') + ')"; fi\n sleep 0.1\ndone\necho "Job response pending; do not resend input" >&2\nexit 75', capture_output=True, text=True, timeout=25)
        except subprocess.CalledProcessError as error:
            raise ValueError('Guest command failed: ' + error.stderr.strip()) from None
        return result.stdout

    def launch(self, mode, app):
        if mode in self.state['products']:
            raise ValueError('Mode already launched; use a new run for another fixture')
        product = self.vm.root + '/products/' + self.state['run'] + '-' + mode
        app = Path(app).resolve()
        subprocess.run(['codesign','--verify','--deep','--strict','--all-architectures',str(app)], check=True)
        binary_hash = hashlib.sha256((app / 'Contents/MacOS/Meshchan').read_bytes()).hexdigest()
        self.vm.remote('test ! -e ' + q(product), timeout=10)
        self.upload([(app,'Meshchan.app')], product)
        # The full app, cwd, owner directory, output and drivers are outside Documents.
        script = f'''mkdir -p {q(product + '/fixture')} {q(product + '/cwd')}
cd {q(product + '/cwd')}
/usr/bin/codesign --verify --deep --strict --all-architectures {q(product + '/Meshchan.app')}
{q(product + '/Meshchan.app/Contents/MacOS/Meshchan')} {q('--data-dir=' + product + '/fixture')} > {q(product + '/app.stdout')} 2> {q(product + '/app.stderr')} < /dev/null &
echo $!'''
        pid = int(self.job(script).strip())
        self.state['products'][mode] = {'root':product,'pid':pid,'sourceApp':str(app),'executableSha256':binary_hash}
        self.save()
        for _ in range(50):
            try:
                self.act(mode, ['activate'])
                break
            except (ValueError, subprocess.CalledProcessError):
                time.sleep(0.2)
        else:
            raise ValueError('Fixture did not become available; inspect its existing logs before retrying')
        print(json.dumps(self.state['products'][mode]))

    def act(self, mode, args):
        product = self.state['products'][mode]
        root = product['root']
        argv = [self.vm.root + '/product-bin/meshchan-ui', str(product['pid']), *args]
        return self.job('export MESHCHAN_VM_PRODUCT_ROOT=' + q(root) + '\nexport MESHCHAN_GUI_FIXTURE=' + q(root + '/fixture') + '\n' + shlex.join(argv))

    def collect(self, mode):
        root = self.state['products'][mode]['root']
        target = self.out / mode
        target.mkdir(exist_ok=True)
        with tempfile.TemporaryFile() as stream:
            self.vm.remote('/usr/bin/tar -cf - -C ' + q(root) + ' --exclude=Meshchan.app .', stdout=stream, timeout=60)
            stream.seek(0)
            with tarfile.open(fileobj=stream) as archive:
                archive.extractall(target, filter='data')
        print(target)

    def settled(self, mode):
        product = self.state['products'][mode]
        # Never query closed application UI, and never kill an owner to produce PASS.
        self.vm.remote('test -z "$(/bin/ps -p ' + str(product['pid']) + ' -o pid=)"', timeout=10)
        self.collect(mode)
        reports = [json.loads(s) for s in (self.out / mode / 'app.stdout').read_text().splitlines() if s.startswith('{')]
        if not reports or not all(reports[-1].get(k) is True for k in ['resourcesReleased','workerExited']) or any(reports[-1].get(k) != 0 for k in ['pendingRequests','receivePorts']):
            raise ValueError('Normal resource/worker shutdown receipt missing')
        product['shutdown'] = reports[-1]
        self.save()
        print(json.dumps(reports[-1]))

    def finish(self):
        for mode in self.state['products']:
            self.settled(mode)
        self.vm.remote('touch ' + q(self.vm.runpath(self.state['run']) + '/finish'), timeout=10)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config', required=True)
    p.add_argument('--evidence', required=True)
    sub = p.add_subparsers(dest='command', required=True)
    sub.add_parser('prepare')
    launch = sub.add_parser('launch'); launch.add_argument('mode', choices=MODES); launch.add_argument('app')
    action = sub.add_parser('action'); action.add_argument('mode', choices=MODES); action.add_argument('args', nargs='+')
    for command in ['collect','settled']:
        mode = sub.add_parser(command); mode.add_argument('mode',choices=MODES)
    sub.add_parser('finish')
    args = p.parse_args()
    product = Product(args.config,args.evidence)
    if args.command == 'prepare': product.prepare()
    elif args.command == 'launch': product.launch(args.mode,args.app)
    elif args.command == 'action': print(product.act(args.mode,args.args),end='')
    elif args.command == 'collect': product.collect(args.mode)
    elif args.command == 'settled': product.settled(args.mode)
    elif args.command == 'finish': product.finish()


if __name__ == '__main__':
    try:
        main()
    except (ValueError,OSError,subprocess.SubprocessError) as error:
        print('ERROR: ' + str(error),file=sys.stderr)
        sys.exit(1)
