#!/usr/bin/env python3
"""Hardware-free History/Save panel stages with separately reviewed preedit."""
import argparse
import json
import sys
from host import Product, MODES
from scenario import Scenario


class HistoryScenario(Scenario):
    def initial(self):
        self.act('size', '1200', '950')
        self.act('nav', 'Diagnostics')
        self.act('pointer', 'History')
        self.expect('history-initial', 'Rows on this page:')
        self.capture('history-initial')

    def preedit(self, target):
        if target == 'filter':
            self.field(0, '')
        elif target != 'filename':
            raise ValueError('Unknown History preedit target')
        original = self.focus(target + '-before')
        if original['sourceID'] not in ['com.apple.keylayout.US', 'com.apple.keylayout.ABC']:
            raise ValueError('Expected Latin source before this preedit')
        self.product.state['products'][self.mode][target + 'OriginalSource'] = original['sourceID']
        self.product.save()
        self.act('key', 'a', 'command')
        self.act('key', 'space', 'control')
        self.act('type', 'zhongwen')
        self.focus(target + '-preedit')
        self.state(target + '-preedit')
        self.capture(target + '-preedit')
        print('REVIEW_REQUIRED: inspect this original image and focused-field JSON before defer/commit')

    def defer_filter(self, action):
        if action == 'run': self.act('pointer', 'Run')
        elif action == 'apply': self.act('pointer', 'Apply')
        elif action == 'menu': self.act('pointer', 'Operation: All')
        elif action == 'quit': self.act('key', 'q', 'command')
        else: raise ValueError('Unsupported History composing action')
        facts = self.focus('filter-deferred-' + action)
        if 'zhong' not in facts['value']:
            raise ValueError('Composition was lost')
        self.state('filter-deferred-' + action)
        self.capture('filter-deferred-' + action)

    def commit(self, target):
        before = self.focus(target + '-before-commit')
        if before['sourceID'] != 'com.apple.inputmethod.SCIM.ITABC':
            raise ValueError('Expected actual Pinyin preedit')
        self.act('key', 'space')
        facts = self.focus(target + '-committed')
        if facts['value'] != '中文':
            raise ValueError('Natural commit mismatch: ' + str(facts))
        with (self.out / 'visual-reviews.jsonl').open('a') as stream:
            import time
            stream.write(json.dumps({'target':target, 'reviewedBeforeSpace':True, 'focusPID':facts['focusOwnerPID'], 'timeUtc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}) + '\n')
        self.capture(target + '-committed')
        self.act('key', 'space', 'control')
        restored = self.focus(target + '-restored')
        if restored['sourceID'] != self.product.state['products'][self.mode][target + 'OriginalSource']:
            raise ValueError('Input source not restored')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True)
    parser.add_argument('--evidence', required=True)
    parser.add_argument('mode', choices=MODES)
    sub = parser.add_subparsers(dest='stage', required=True)
    sub.add_parser('initial')
    preedit = sub.add_parser('preedit'); preedit.add_argument('target', choices=['filter', 'filename'])
    defer = sub.add_parser('defer'); defer.add_argument('action', choices=['run', 'apply', 'menu', 'quit'])
    commit = sub.add_parser('commit'); commit.add_argument('target', choices=['filter', 'filename']); commit.add_argument('--visual-confirmed', action='store_true', required=True)
    args = parser.parse_args()
    scenario = HistoryScenario(Product(args.config, args.evidence), args.mode)
    if args.stage == 'initial': scenario.initial()
    elif args.stage == 'preedit': scenario.preedit(args.target)
    elif args.stage == 'defer': scenario.defer_filter(args.action)
    else: scenario.commit(args.target)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
