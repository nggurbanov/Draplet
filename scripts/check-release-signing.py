#!/usr/bin/env python3
"""Reject unstable update identities and optionally compare a previous release."""
import argparse
import subprocess


def run(*args):
    return subprocess.run(args, capture_output=True, text=True)


def requirement(app):
    result = run('codesign', '-d', '-vv', '-r-', str(app))
    if result.returncode:
        raise SystemExit('Could not inspect the application signature.')
    metadata = result.stdout + '\n' + result.stderr
    lines = [line.removeprefix('# ') for line in metadata.splitlines()]
    expression = next((line.removeprefix('designated => ') for line in lines
                       if line.startswith('designated => ')), None)
    if not expression:
        raise SystemExit('Application has no designated requirement.')
    return metadata, expression


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app')
    parser.add_argument('--previous-app')
    args = parser.parse_args()
    metadata, current = requirement(args.app)
    if 'Signature=adhoc' in metadata or 'cdhash ' in current:
        raise SystemExit('Ad-hoc update rejected: its code identity changes with the binary, invalidating macOS privacy permissions.')
    if run('codesign', '--verify', '--deep', '--strict', args.app).returncode:
        raise SystemExit('Application signature verification failed.')
    if args.previous_app:
        _, previous = requirement(args.previous_app)
        for app, expected in [(args.app, previous), (args.previous_app, current)]:
            if run('codesign', '--verify', '--strict', '-R', '=' + expected, app).returncode:
                raise SystemExit('Update identity differs from the previous app. Plan and test a permission migration before publishing.')
    print('Stable application signature verified' + ('; previous identity is compatible.' if args.previous_app else '.'))


if __name__ == '__main__':
    main()
