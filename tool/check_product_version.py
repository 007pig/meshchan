#!/usr/bin/env python3
"""Check explicit source identity and, when requested, actual App metadata."""
import argparse
import json
import os
import sys

from candidate_common import ROOT, versions
from product_identity import check_app, check_source_identity, check_xcode_environment, config_values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-version')
    parser.add_argument('--app-build', type=int)
    parser.add_argument('--app', help='Require a complete built App and check its actual Info.plist')
    parser.add_argument('--xcode-environment', action='store_true', help='Native build preflight; uses the tracked version decision')
    args = parser.parse_args()
    try:
        if args.xcode_environment:
            values = config_values(ROOT)
            version, build = values['MESHCHAN_PRODUCT_VERSION'], int(values['MESHCHAN_APP_BUILD'])
            if (args.expected_version is not None and args.expected_version != version
                    or args.app_build is not None and args.app_build != build):
                raise ValueError('Conflicting explicit/native version inputs')
            check_xcode_environment(os.environ, version, build)
        else:
            if args.expected_version is None or args.app_build is None:
                raise ValueError('--expected-version and --app-build are required')
            version, build = args.expected_version, args.app_build
        report = {'sourceMembers': versions(expected_version=version, app_build=build),
                  'sourceTemplate': check_source_identity(ROOT, version, build)}
        if args.app is not None:
            report['builtApp'] = check_app(args.app, version, build)
        print(json.dumps(report))
        return 0
    except (OSError, ValueError, KeyError) as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
