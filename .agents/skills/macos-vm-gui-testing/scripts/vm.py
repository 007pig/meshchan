#!/usr/bin/env python3
"""Host-side SSH orchestration. This program never emits local GUI events."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request

HERE = Path(__file__).resolve().parent
CLICLICK_URL = 'https://github.com/BlueM/cliclick/releases/download/5.1/cliclick.zip'
CLICLICK_SHA256 = '710910fd2dade6a3b5889594bfc019e7d4c2beee09fd777503e71ea82acc91bc'
RUN = re.compile(r'\d{8}T\d{6}Z-(baseline|background|minimized|pinyin|product)-\d+')

def call(args, **kwargs):
    try:
        return subprocess.run(args, check=True, **kwargs)
    except subprocess.CalledProcessError as error:
        if args[0] in ('ssh', 'scp') and error.returncode == 255:
            raise ValueError('SSH connection unavailable. Check the diagnostic above. '
                             'For Permission denied or an expired control connection, run '
                             'vm.py --config /absolute/path/config.json connect in your own '
                             'terminal and authenticate there; never put a password in chat '
                             'or configuration.') from None
        raise

def build(out):
    out = Path(out).expanduser().resolve()
    out.mkdir(parents=True, exist_ok=True)
    app = out / 'UTMUIProbe.app/Contents'
    (app / 'MacOS').mkdir(parents=True, exist_ok=True)
    shutil.copy2(HERE / 'native/Info.plist', app / 'Info.plist')
    for source, dest, frameworks in [
        ('Probe', app / 'MacOS/UTMUIProbe', ['Cocoa', 'ApplicationServices']),
        ('KeyInput', out / 'bin/key-input', ['Foundation', 'ApplicationServices']),
        ('PlaceWindow', out / 'bin/place-window', ['Cocoa', 'ApplicationServices']),
        ('IMEInspect', out / 'pinyin-bin/ime-inspect', ['Cocoa', 'Carbon', 'ApplicationServices']),
    ]:
        dest.parent.mkdir(parents=True, exist_ok=True)
        args = ['xcrun', 'clang', '-fobjc-arc', '-arch', 'arm64', str(HERE / f'native/{source}.m'), '-o', str(dest)]
        for framework in frameworks:
            args.extend(['-framework', framework])
        call(args)
        call(['codesign', '--force', '--sign', '-', str(dest)])
    shutil.copy2(out / 'bin/key-input', out / 'pinyin-bin/key-input')
    archive = out / 'cliclick-5.1.zip'
    if not archive.exists():
        with urllib.request.urlopen(CLICLICK_URL, timeout=30) as response:
            archive.write_bytes(response.read())
    if hashlib.sha256(archive.read_bytes()).hexdigest() != CLICLICK_SHA256:
        raise ValueError('cliclick archive checksum mismatch')
    with tempfile.TemporaryDirectory() as tmp:
        call(['ditto', '-x', '-k', str(archive), tmp])
        binary, = [p for p in Path(tmp).rglob('cliclick') if p.is_file()]
        shutil.copy2(binary, out / 'bin/cliclick')
    (out / 'bin/cliclick').chmod(0o755)
    call(['codesign', '--force', '--sign', '-', str(out / 'bin/cliclick')])
    call(['codesign', '--force', '--sign', '-', str(out / 'UTMUIProbe.app')])
    for name in ['guest.sh', 'pinyin.sh', 'stop-guest.sh']:
        shutil.copy2(HERE / name, out / name)
    print(out)

class VM:
    def __init__(self, path):
        self.c = json.loads(Path(path).expanduser().read_text())
        for key in ['host', 'user', 'uuid', 'known_hosts', 'runtime_dir', 'evidence_dir', 'guest_root']:
            if not isinstance(self.c.get(key), str) or not self.c[key]:
                raise ValueError(f'Missing configuration: {key}')
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.:-]*', self.c['host']):
            raise ValueError('Invalid host')
        if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_-]*', self.c['user']):
            raise ValueError('Invalid user')
        if not re.fullmatch(r'[A-Fa-f0-9-]{36}', self.c['uuid']):
            raise ValueError('Invalid UUID')
        if not re.fullmatch(r'/Users/[A-Za-z0-9_-]+/[A-Za-z0-9_/-]+', self.c['guest_root']) or '..' in self.c['guest_root'].split('/'):
            raise ValueError('guest_root must be an absolute dedicated path under /Users/account')
        self.root = self.c['guest_root']
        known = Path(self.c['known_hosts']).expanduser().resolve()
        if not known.is_file():
            raise ValueError('Provide independently verified known_hosts before connecting')
        runtime_path = Path(self.c['runtime_dir']).expanduser()
        if runtime_path.is_symlink():
            raise ValueError('runtime_dir must not be a symlink')
        self.runtime = runtime_path.resolve()
        self.runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
        if self.runtime.stat().st_uid != os.getuid():
            raise ValueError('runtime_dir must be owned by current user')
        self.runtime.chmod(0o700)
        self.target = self.c['user'] + '@' + self.c['host']
        self.opts = ['-o', 'UserKnownHostsFile=' + str(known), '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=5', '-o', 'ControlPath=' + str(self.runtime / 'ssh-control')]
        self.guard = ' && '.join([
            'case "$(/usr/sbin/sysctl -n hw.model)" in VirtualMac*) true;; *) false;; esac',
            'test "$(/usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice | /usr/bin/awk -F \'"\' \'/IOPlatformUUID/ {print $(NF-1)}\')" = ' + shlex.quote(self.c['uuid']),
            'test "$(/usr/bin/stat -f %Su /dev/console)" = ' + shlex.quote(self.c['user']),
        ])

    def remote(self, command, **kwargs):
        if self.c.get('credentials_file'):
            control = subprocess.run(['ssh', *self.opts, '-O', 'check', self.target], capture_output=True)
            if control.returncode:
                self.connect()
        return call(['ssh', *self.opts, '-o', 'BatchMode=yes', self.target,
                     self.guard + ' && {\n' + command + '\n}'], **kwargs)

    def connect(self):
        env = dict(os.environ)
        options = {}
        if self.c.get('credentials_file'):
            credential_path = Path(self.c['credentials_file']).expanduser()
            if credential_path.is_symlink() or not credential_path.is_file():
                raise ValueError('credentials_file must be a regular private file')
            info = credential_path.stat()
            if info.st_uid != os.getuid() or info.st_mode & 0o077:
                raise ValueError('credentials_file must be owned by current user with mode 0600')
            credentials = json.loads(credential_path.read_text())
            if any(credentials.get(k) != self.c[k] for k in ['user', 'host', 'uuid']) or not isinstance(credentials.get('password'), str) or not credentials['password']:
                raise ValueError('Private credentials must match configured user, host and UUID')
            env.update(SSH_ASKPASS=str(HERE / 'askpass.sh'), SSH_ASKPASS_REQUIRE='force',
                       DISPLAY='meshchan-vm-auth', MESHCHAN_VM_CREDENTIALS=str(credential_path.resolve()),
                       MESHCHAN_VM_PYTHON=sys.executable)
            options['stdin'] = subprocess.DEVNULL
        call(['ssh', *self.opts, '-M', '-o', 'ControlPersist=30m', '-o', 'ServerAliveInterval=30', '-o', 'ServerAliveCountMax=3', '-fNT', self.target], env=env, **options)

    def runpath(self, run):
        if not RUN.fullmatch(run):
            raise ValueError('Invalid run ID')
        return self.root + '/runs/' + run

    def check(self):
        self.remote("sw_vers; /usr/sbin/sysctl -n hw.model; /usr/bin/csrutil status; /usr/bin/stat -f %Su /dev/console; /usr/bin/defaults read com.apple.HIToolbox; /usr/bin/defaults read com.apple.symbolichotkeys", timeout=20)

    def deploy(self, output):
        output = Path(output).expanduser().resolve()
        q = shlex.quote
        # Existing signed app is deliberately preserved. Fresh locations receive the new app.
        command = f'''set -e
root={q(self.root)}
test ! -d "$root/active.lock"
mkdir -p "$root"
stage=$(mktemp -d "$root/.deploy.XXXXXX")
trap 'rm -rf "$stage"' EXIT
/usr/bin/tar -xf - -C "$stage"
if test ! -d "$root/UTMUIProbe.app"; then
    cp -R "$stage/UTMUIProbe.app" "$root/UTMUIProbe.app"
elif test "$root" != "$HOME/utm-ui-isolation"; then
    echo 'Existing custom-root app: confirm it supports the fourth root argument before reuse' >&2; exit 78
fi
for item in bin pinyin-bin guest.sh pinyin.sh stop-guest.sh; do cp -R "$stage/$item" "$root/"; done
mkdir -p "$root/runs"
echo DEPLOYED_APP_PRESERVED_IF_PRESENT'''
        with tempfile.TemporaryFile() as stream:
            with tarfile.open(fileobj=stream, mode='w') as archive:
                for name in ['UTMUIProbe.app', 'bin', 'pinyin-bin', 'guest.sh', 'pinyin.sh', 'stop-guest.sh']:
                    archive.add(output / name, arcname=name)
            stream.seek(0)
            self.remote(command, stdin=stream, timeout=60)

    def start(self, stage):
        q = shlex.quote
        script = f'''set -e
root={q(self.root)}
test "$(/usr/sbin/ioreg -a -n Root -d1 | /usr/bin/plutil -extract IOConsoleLocked raw -o - -)" = false || {{ echo 'BLOCKED: unlock the guest desktop' >&2; exit 66; }}
test ! -d "$root/active.lock"
if test {q(stage)} = product; then test -f "$root/product.sh" || {{ echo 'Deploy the product-owned runner first' >&2; exit 69; }}; fi
for item in UTMUIProbe.app/Contents/MacOS/UTMUIProbe bin/key-input bin/place-window bin/cliclick pinyin-bin/ime-inspect pinyin-bin/key-input; do test -x "$root/$item"; done
before=$(cat "$root/latest-run" 2>/dev/null || true)
open -n "$root/UTMUIProbe.app" --args {q(self.c['uuid'])} {q(stage)} "$root"
for attempt in {{1..100}}; do
    now=$(cat "$root/latest-run" 2>/dev/null || true)
    if test -n "$now" && test "$now" != "$before"; then basename "$now"; exit 0; fi
    sleep 0.1
done
tail -n 8 "$root/executor.log" >&2
exit 77'''
        result = self.remote(script, capture_output=True, text=True, timeout=20)
        run = result.stdout.strip()
        if not RUN.fullmatch(run) or RUN.fullmatch(run).group(1) != stage:
            raise ValueError('Executor did not return the requested run ID: ' + run)
        print(run)

    def review(self, run, gate, approve=False):
        path = shlex.quote(self.runpath(run))
        if '-pinyin-' not in run:
            raise ValueError('Review is only valid for a Pinyin run')
        if approve:
            self.remote(f'''set -e
r={path}
test ! -f "$r/exit-code"
test -f "$r/ready-{gate}"
test ! -f "$r/commit-{gate}"
test -f "$r/{gate}-preedit.png"
printf '%s visual review confirmed for {gate}\\n' "$(date -u +%FT%TZ)" >> "$r/review.txt"
touch "$r/commit-{gate}"''', timeout=10)
        else:
            self.collect(run)
            self.remote(f'cat {path}/{gate}-preedit.json', timeout=10)

    def collect(self, run):
        remote = self.runpath(run)
        dest = Path(self.c['evidence_dir']).expanduser().resolve()
        dest.mkdir(parents=True, exist_ok=True)
        self.remote('test -d ' + shlex.quote(remote), timeout=10)
        call(['scp', *self.opts, '-o', 'BatchMode=yes', '-r', self.target + ':' + remote, str(dest)], timeout=60)
        print(dest / run)

def verify(path):
    path = Path(path).expanduser().resolve()
    match = RUN.fullmatch(path.name)
    if not match:
        raise ValueError('Evidence directory name must be a run ID')
    stage = match.group(1)
    if stage == 'product':
        raise ValueError('Use the product runner\'s independent verifier; TextEdit checks do not validate product results')
    if (path / 'exit-code').read_text().strip() != '0':
        raise ValueError('Run failed or was interrupted')
    expected = b'ABC\n\xe4\xb8\xad\xe6\x96\x87\nABC\n\xe4\xbd\xa0\xe5\xa5\xbd\nABC\n' if stage == 'pinyin' else ''.join(f'VM-{stage}-{i:03d}\n' for i in range(1, 4 if stage == 'baseline' else 31)).encode()
    actual = (path / 'actual.txt').read_bytes().replace(b'\r', b'\n')
    if actual != expected:
        raise ValueError('Actual saved text does not match independently generated expectation')
    if stage == 'pinyin':
        checkpoints = ['initial', 'latin-before-switch', 'pinyin-first-switch', 'zhongwen-preedit', 'zhongwen-before-commit', 'zhongwen-committed', 'latin-return-switch', 'latin-return-typed', 'pinyin-second-switch', 'nihao-preedit', 'nihao-before-commit', 'nihao-committed', 'restored-source', 'final-text']
        sources = {name: json.loads((path / (name + '.json')).read_text()) for name in checkpoints}
        for name, value in sources.items():
            if value.get('focusVerified') is not True or not (value['foregroundPID'] == value['focusOwnerPID'] == value['textEditPID']) or value['fieldRole'] != 'AXTextArea':
                raise ValueError('Focus verification failed: ' + name)
        original = sources['initial']['sourceID']
        if original not in ['com.apple.keylayout.US', 'com.apple.keylayout.ABC'] or sources['restored-source']['sourceID'] != original:
            raise ValueError('Original Latin input source was not restored')
        for name in ['pinyin-first-switch', 'pinyin-second-switch', 'zhongwen-preedit', 'nihao-preedit']:
            if sources[name]['sourceID'] != 'com.apple.inputmethod.SCIM.ITABC':
                raise ValueError('Unexpected Pinyin input source')
        for gate, preedit in [('zhongwen', 'ABC\nzhong wen'), ('nihao', 'ABC\n中文\nABC\nni hao')]:
            for suffix in ['-preedit', '-before-commit']:
                if sources[gate + suffix]['text'] != preedit:
                    raise ValueError('Preedit changed or was not recorded')
        for gate, text in [('zhongwen', 'ABC\n中文'), ('nihao', 'ABC\n中文\nABC\n你好')]:
            if sources[gate + '-committed']['text'] != text:
                raise ValueError('Natural commit text mismatch')
            if not (path / ('commit-' + gate)).exists() or ('visual review confirmed for ' + gate) not in (path / 'review.txt').read_text():
                raise ValueError('Missing explicit preedit review')
        images = ['zhongwen-preedit', 'zhongwen-committed', 'nihao-preedit', 'nihao-committed', 'final']
    else:
        images = ['start', 'middle', 'end']
        for i in range(1, 4 if stage == 'baseline' else 31):
            if json.loads((path / f'focus-{i}.json').read_text()).get('focusVerified') is not True:
                raise ValueError('ASCII input focus was not verified')
    for name in images:
        if not (path / (name + '.png')).is_file() or not (path / (name + '.png')).read_bytes().startswith(b'\x89PNG\r\n\x1a\n'):
            raise ValueError('Missing screenshot: ' + name)
    result = {'guest_result': 'PASS', 'stage': stage, 'run': path.name, 'actual_sha256': hashlib.sha256(actual).hexdigest(), 'host_input_isolation': 'requires separate user observation', 'visual_preedit': 'requires recorded visual review' if stage == 'pinyin' else 'not applicable'}
    (path / 'verified-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', help='Private JSON configuration (no stored password)')
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('build'); p.add_argument('--output', required=True)
    for name in ['connect', 'disconnect', 'check', 'stop']:
        sub.add_parser(name)
    p = sub.add_parser('deploy'); p.add_argument('--build-dir', required=True)
    p = sub.add_parser('run'); p.add_argument('stage', choices=['baseline', 'background', 'minimized', 'pinyin', 'product'])
    for name in ['status', 'collect']:
        p = sub.add_parser(name); p.add_argument('run_id')
    for name in ['review', 'approve']:
        p = sub.add_parser(name); p.add_argument('run_id'); p.add_argument('gate', choices=['zhongwen', 'nihao'])
        if name == 'approve':
            p.add_argument('--visual-confirmed', action='store_true', required=True, help='Assert that the correct focus, underlined composition and candidate were visually inspected')
    p = sub.add_parser('verify'); p.add_argument('evidence')
    args = parser.parse_args()
    if args.command == 'build': return build(args.output)
    if args.command == 'verify': return verify(args.evidence)
    if not args.config: parser.error('--config is required for VM operations')
    vm = VM(args.config)
    if args.command == 'connect':
        vm.connect()
        vm.check()
    elif args.command == 'disconnect':
        call(['ssh', *vm.opts, '-O', 'exit', vm.target])
    elif args.command == 'check': vm.check()
    elif args.command == 'deploy': vm.deploy(args.build_dir)
    elif args.command == 'run': vm.start(args.stage)
    elif args.command == 'status':
        p = shlex.quote(vm.runpath(args.run_id))
        vm.remote(f'test -d {p} && tail -n 12 {p}/run.log && if test -f {p}/exit-code; then cat {p}/exit-code; else echo RUNNING; fi', timeout=10)
    elif args.command == 'stop':
        vm.remote('bash ' + shlex.quote(vm.root + '/stop-guest.sh') + ' ' + shlex.quote(vm.c['uuid']) + ' ' + shlex.quote(vm.root), timeout=15)
    elif args.command == 'collect': vm.collect(args.run_id)
    elif args.command in ['review', 'approve']: vm.review(args.run_id, args.gate, args.command == 'approve')

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        sys.exit(1)
