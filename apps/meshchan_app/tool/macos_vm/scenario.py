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
        self.field(0,'0'); self.expect('invalid-request','Use decimal integers')
        self.field(0,'5'); self.field(2,'15000'); self.expect('invalid-startup','Use decimal integers')
        self.field(2,'0'); self.act('nav','Drafts'); self.act('nav','Device')
        self.expect('navigation-return','Selected port: None')

    def preedit(self, target):
        if target == 'diagnostic':
            self.act('nav','Diagnostics'); self.act('click','notProvided'); self.act('click','Text (UTF-8)'); self.field(0,'')
        elif target == 'device':
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
        if target == 'diagnostic' and action == 'operation': self.act('pointer','ping')
        elif target == 'diagnostic' and action == 'content': self.act('pointer','text')
        elif target == 'diagnostic' and action == 'start': self.act('pointer','Start and record')
        elif action == 'navigation': self.act('nav','Drafts' if target in ['device','diagnostic'] else 'Device')
        elif action == 'quit': self.act('key','q','command')
        elif target == 'draft' and action == 'save': self.act('pointer','Save')
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
        elif target == 'diagnostic':
            self.act('nav','Device'); self.act('nav','Diagnostics'); self.act('field','0')
            assert self.focus('diagnostic-navigation-retained')['value'] == '中文'
            self.expect('diagnostic-no-port','Selected session port: None')
            self.act('click','Preview parameters'); self.expect('diagnostic-preview-rejected','invalid_input')
        else:
            self.act('key','s','command'); self.expect('draft-saved','Saved')

    def diagnostic_quit(self, choice):
        if choice not in ['Save','Discard']:
            raise ValueError('Choose Save or Discard')
        self.act('click','ping'); self.act('click','Finite Responder')
        self.expect('respond-choice','respond')
        self.act('click','respond'); self.act('click','PING'); self.act('field','0')
        assert self.focus('ping-return')['value'] == '中文'
        self.act('nav','Drafts'); self.act('click','New')
        self.field(0,'diagnosticgui'); self.field(1,'abc')
        self.act('key','q','command'); self.expect('dirty-continue','Leave this draft?')
        self.capture('dirty-continue'); self.act('click','Continue editing')
        self.expect('continued-offline','Storage ready')
        assert self.focus('continued-content')['value'] == 'abc'
        self.act('key','q','command'); self.expect('dirty-' + choice,'Leave this draft?')
        self.capture('dirty-' + choice); self.act('click',choice)
        for _ in range(50):
            try:
                self.product.settled(self.mode)
                return
            except (ValueError,subprocess.CalledProcessError) as error:
                last = error; time.sleep(0.1)
        raise ValueError('Diagnostic navigation quit did not settle: ' + str(last))

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


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config',required=True); p.add_argument('--evidence',required=True)
    p.add_argument('mode',choices=MODES)
    p.add_argument('stage',choices=['initial','preedit','defer','commit','quit','discard','diagnostic-quit'])
    p.add_argument('value',nargs='?'); p.add_argument('action',nargs='?')
    p.add_argument('--visual-confirmed',action='store_true')
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
    elif args.stage == 'diagnostic-quit': scenario.diagnostic_quit(args.value)


if __name__ == '__main__': main()
