#!/usr/bin/env python3
"""Validate all four current members against an explicit release decision."""
import argparse
import json

from candidate_common import versions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-version', required=True)
    parser.add_argument('--app-build', required=True, type=int)
    args = parser.parse_args()
    print(json.dumps(versions(expected_version=args.expected_version, app_build=args.app_build)))


if __name__ == '__main__':
    main()
