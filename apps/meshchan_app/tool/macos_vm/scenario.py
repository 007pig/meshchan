#!/usr/bin/env python3
"""Reviewable UI stages. Chinese input comes only from guest virtual keycodes."""
import argparse
import json
import subprocess
import time
from host import MODES, Product


class Scenario:
    def __init__(self, product, mode):
        self.product, self.mode = product, mode
        self.root = product.state['products'][mode]['root']
        self.out = product.out / mode
        self.out.mkdir(exist_ok=True)

    def act(self, *args):
        return self.product.act(self.mode,list(args))

    def state(self, name):
        rows = json.loads(self.act('snapshot'))
        (self.out / (name + '.json')).write_text(json.dumps(rows,ensure_ascii=False,indent=2) + '\n')
        return rows

    def expect(self, name, value):
        rows = self.state(name)
        if not any(value in row.get(k,'') for row in rows for k in ['value','title','description']):
            raise ValueError('Missing expectation: ' + name + ' / ' + value)
        return rows

    def capture(self, name):
        self.act('screenshot',self.root + '/' + name + '.png')
        self.product.collect(self.mode)

    def field(self, index, value):
        self.act('field',str(index)); self.act('key','a','command')
        if value:
            self.act('type',value)
        else:
            self.act('key','delete')

    def focus(self, name):
        facts = json.loads(self.act('focus'))
        (self.out / (name + '-focus.json')).write_text(json.dumps(facts,ensure_ascii=False,indent=2) + '\n')
        return facts

    def initial(self):
        self.act('size','1200','850'); self.act('nav','Device')
        rows = self.expect('device-initial','No ports have been listed or opened')
        # Flutter's unfocused semantics proxies may have empty AXValue. Read the
        # actual focused native text input instead of treating the proxy as text.
        for index, value in enumerate(['5','15','0']):
            self.act('field',str(index))
            assert self.focus('default-' + str(index))['value'] == value
        self.expect('device-no-selection','Selected port: None')
        self.capture('device-initial')
        self.act('click','Refresh')
        self.expect('device-explicit-refresh','Selected port: None')
        self.capture('device-refresh')
        self.field(0,'0'); self.expect('invalid-request','Use decimal integers')
        self.field(0,'5'); self.field(2,'15000'); self.expect('invalid-startup','Use decimal integers')
        self.field(2,'0'); self.act('nav','Drafts'); self.act('nav','Device')
        self.expect('navigation-return','Selected port: None')

    def preedit(self, target):
        if target == 'device':
            self.act('nav','Device'); self.field(0,'5')
        else:
            self.act('nav','Drafts'); self.act('click','New')
            self.field(0,'vm' + self.mode.lower()); self.field(1,'')
        original = self.focus(target + '-before')
        assert original['sourceID'] in ['com.apple.keylayout.US','com.apple.keylayout.ABC']
        self.product.state['products'][self.mode][target + 'OriginalSource'] = original['sourceID']
        self.product.save()
        self.act('key','space','control')
        self.act('type','zhongwen')
        self.focus(target + '-preedit'); self.state(target + '-preedit')
        self.capture(target + '-preedit')
        print('REVIEW_REQUIRED: inspect original screenshot and focused-field JSON before continuing')

    def defer(self, target, action):
        if action == 'navigation': self.act('nav','Drafts' if target == 'device' else 'Device')
        elif action == 'quit': self.act('key','q','command')
        elif target == 'draft' and action == 'save': self.act('pointer','Save')
        elif target == 'device' and action == 'menu': self.act('pointer','Select a port')
        else: raise ValueError('Unsupported composing action')
        rows = self.state(target + '-deferred-' + action)
        assert not any(r.get('title','').startswith('Leave this') or r.get('value','').startswith('Leave this') for r in rows)
        assert not any('Dismiss menu' in r.get(k,'') for r in rows for k in ['title','value','description'])
        assert any('zhong' in r['value'] for r in rows if r['role'] in ['AXTextField','AXTextArea'])
        self.focus(target + '-deferred-' + action)
        self.capture(target + '-deferred-' + action)

    def commit(self, target):
        before = self.focus(target + '-before-commit')
        assert before['sourceID'] == 'com.apple.inputmethod.SCIM.ITABC'
        self.act('key','space')
        expected = '5中文' if target == 'device' else '中文'
        facts = self.focus(target + '-committed')
        assert facts['value'] == expected, facts
        with (self.out / 'visual-reviews.jsonl').open('a') as stream:
            stream.write(json.dumps({'target':target,'preeditImage':target + '-preedit.png','reviewedBeforeSpace':True,'focusPID':facts['focusOwnerPID'],'timeUtc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}) + '\n')
        self.state(target + '-committed'); self.capture(target + '-committed')
        self.act('key','space','control')
        restored = self.focus(target + '-restored')
        assert restored['sourceID'] == self.product.state['products'][self.mode][target + 'OriginalSource']
        if target == 'device':
            self.expect('device-committed-invalid','Use decimal integers'); self.field(0,'5')
        else:
            self.act('key','s','command'); self.expect('draft-saved','Saved')

    def quit_decision(self, choice):
        # Actual Latin input after source restoration proves the source is usable.
        self.act('field','1'); self.act('key','right','command'); self.act('type','abc')
        assert self.focus('dirty-' + choice)['value'] == '中文abc'
        self.act('key','q','command'); self.expect('quit-' + choice,'Leave this draft?')
        self.capture('quit-' + choice)
        self.act('click',choice)
        if choice == 'Continue editing':
            self.expect('quit-continued','Storage ready')
            self.undo_suffix()
        else:
            for _ in range(50):
                try:
                    self.product.settled(self.mode)
                    return
                except (ValueError, subprocess.CalledProcessError) as error:
                    # No extra UI input or shutdown retry while actual close settles.
                    last = error; time.sleep(0.1)
            raise ValueError('Quit did not settle: ' + str(last))

    def undo_suffix(self):
        # Key delivery crosses Flutter's Undo grouping interval. Preserve and
        # inspect each real group instead of assuming three letters form one.
        for index in range(4):
            value = self.focus('undo-after-continue-' + str(index))['value']
            if value == '中文': return
            assert value in ['中文a','中文ab','中文abc'], value
            if index < 3: self.act('key','z','command')
        raise ValueError('Undo did not reach the saved Chinese body')

    def discard(self):
        self.act('nav','Drafts'); self.act('click','New')
        self.field(0,'vmdiscard'); self.field(1,'abc')
        assert self.focus('discard-dirty')['value'] == 'abc'
        self.act('key','q','command'); self.expect('quit-Discard','Leave this draft?')
        self.capture('quit-Discard'); self.act('click','Discard')
        for _ in range(50):
            try:
                self.product.settled(self.mode); return
            except (ValueError,subprocess.CalledProcessError) as error:
                last = error; time.sleep(0.1)
        raise ValueError('Discard quit did not settle: ' + str(last))

    def check(self, port):
        if not port or not port.strip(): raise ValueError('An explicitly authorized exact guest port is required')
        self.act('nav','Device'); self.act('click','Refresh')
        self.expect('hardware-before-selection','Selected port: None')
        self.act('click','Select a port'); self.act('click',port)
        rows = self.expect('hardware-selected','Selected port: ' + port)
        assert not any('Active / last attempt' in r['value'] for r in rows)
        self.capture('hardware-selected')
        self.act('click','Check device'); self.state('hardware-check-start')
        self.capture('hardware-check-start')
        deadline = time.monotonic() + 25
        sample = 0
        while True:
            sample += 1
            rows = self.state('hardware-check-' + str(sample))
            texts = [r[k] for r in rows for k in ['title','value','description']]
            if 'Not connected' in texts and any('Active / last attempt' in t for t in texts): break
            if time.monotonic() > deadline:
                self.capture('hardware-cleanup-unconfirmed')
                raise ValueError('Actual check/cleanup not settled; do not retry or force owner exit')
            time.sleep(0.2)
        assert any('Session cleanup: succeeded' in t and 'Host observer cleanup: succeeded' in t for t in texts)
        sources = [t for t in texts if t.startswith('Source port:')]
        failure = [t for t in texts if t.startswith('Initialization:')]
        result = {'port':port,'informationObtained':bool(sources),'sourceAndTime':sources,'initialization':failure,'sessionCleanup':'succeeded','observerCleanup':'succeeded','notConnected':True}
        (self.out / 'hardware-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
        self.capture('hardware-settled')
        self.act('nav','Diagnostics'); self.act('nav','Device')
        after = self.state('hardware-navigation-retained')
        assert [r['value'] for r in after if r['value'].startswith('Source port:')] == sources
        print(self.mode + ': explicitly selected finite check settled; information=' + str(bool(sources)))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config',required=True); p.add_argument('--evidence',required=True)
    p.add_argument('mode',choices=MODES)
    p.add_argument('stage',choices=['initial','preedit','defer','commit','quit','discard','check'])
    p.add_argument('value',nargs='?'); p.add_argument('action',nargs='?')
    p.add_argument('--visual-confirmed',action='store_true')
    p.add_argument('--port',help='Exact guest port explicitly selected by the user; required only for check')
    args = p.parse_args()
    scenario = Scenario(Product(args.config,args.evidence),args.mode)
    if args.stage == 'initial': scenario.initial()
    elif args.stage == 'preedit': scenario.preedit(args.value)
    elif args.stage == 'defer': scenario.defer(args.value,args.action)
    elif args.stage == 'commit':
        if not args.visual_confirmed: p.error('View original preedit image and focus JSON first; then pass --visual-confirmed')
        scenario.commit(args.value)
    elif args.stage == 'quit': scenario.quit_decision(args.value)
    elif args.stage == 'discard': scenario.discard()
    elif args.stage == 'check':
        if args.port is None: p.error('check requires --port with the explicitly authorized exact guest path')
        scenario.check(args.port)


if __name__ == '__main__': main()
