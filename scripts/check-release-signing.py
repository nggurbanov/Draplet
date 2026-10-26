#!/usr/bin/env python3
"""Require a compatible update identity or an explicitly gated legacy migration."""
import argparse
import json
from pathlib import Path
import plistlib
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


def release_policy(app):
    try:
        with (Path(app) / 'Contents/Info.plist').open('rb') as source:
            info = plistlib.load(source)
        build = int(info['CFBundleVersion'])
        floor = int(info.get('DrapletMinimumAutoupdateVersion', 0))
    except (OSError, KeyError, TypeError, ValueError, plistlib.InvalidFileException):
        raise SystemExit('Could not read integer release-policy values from the application.')
    if build <= 0 or floor < 0 or floor > build:
        raise SystemExit('Invalid minimum automatic-update build.')
    return build, floor


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app')
    parser.add_argument('--previous-app', action='append', required=True)
    parser.add_argument('--minimum-autoupdate-version', type=int)
    parser.add_argument('--migration-notes', type=Path)
    parser.add_argument('--report-json', type=Path)
    args = parser.parse_args()
    metadata, current = requirement(args.app)
    if 'Signature=adhoc' in metadata or 'cdhash ' in current:
        raise SystemExit('Ad-hoc update rejected: its code identity changes with the binary, invalidating macOS privacy permissions.')
    if 'TeamIdentifier=not set' in metadata and '(runtime)' in metadata:
        raise SystemExit('Hardened runtime without an Apple Team ID cannot load the bundled Sparkle framework. Use the explicit alpha signing profile.')
    if run('codesign', '--verify', '--deep', '--strict', args.app).returncode:
        raise SystemExit('Application signature verification failed.')
    candidate_build, floor = release_policy(args.app)
    if not floor:
        raise SystemExit('The candidate must embed DrapletMinimumAutoupdateVersion; legacy builds must remain gated in future releases.')
    if args.minimum_autoupdate_version is not None and args.minimum_autoupdate_version != floor:
        raise SystemExit('Appcast policy does not match the signed application policy.')
    previous_apps = []
    migration = False
    for previous_app in args.previous_app:
        if run('codesign', '--verify', '--deep', '--strict', previous_app).returncode:
            raise SystemExit('Previous application signature verification failed.')
        previous_build, previous_floor = release_policy(previous_app)
        if floor < previous_floor:
            raise SystemExit('The minimum automatic-update build cannot be lowered; legacy installations still need migration.')
        if candidate_build <= previous_build:
            raise SystemExit('The candidate build must be newer than every previous release.')
        _, previous = requirement(previous_app)
        compatible = all(run('codesign', '--verify', '--strict', '-R', '=' + expected, app).returncode == 0
                         for app, expected in [(args.app, previous), (previous_app, current)])
        previous_apps.append({'build': previous_build, 'minimumAutoupdateVersion': previous_floor,
                              'compatible': compatible})
        if not compatible:
            if previous_build >= floor:
                raise SystemExit('Update identity differs from the previous app. Automatic updates for that build must remain blocked.')
            migration = True
    # A legacy client can skip the first migration release and update directly
    # to any later one. Keep the recovery notice in every gated release.
    if floor > 1:
        notes = args.migration_notes.read_text() if args.migration_notes and args.migration_notes.is_file() else ''
        if not all(text in notes for text in ['data-permission-migration', 'Accessibility', 'Screen Recording']):
            raise SystemExit('A legacy migration requires release notes explaining macOS permission recovery, including in later releases.')
    report = {'candidateBuild': candidate_build, 'minimumAutoupdateVersion': floor,
              'previousApps': previous_apps, 'requiresPermissionMigration': migration}
    if args.report_json:
        args.report_json.write_text(json.dumps(report, indent=2) + '\n')
    print('Stable signature verified; manual migration is required for legacy builds.' if migration
          else 'Stable application signature verified; previous identities are compatible.')


if __name__ == '__main__':
    main()
