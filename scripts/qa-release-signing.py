#!/usr/bin/env python3
"""Exercise release policy against real signed bundles; never launches an app.

Use a test certificate matching --compatible-previous. Only temporary copies
are changed and signed; none of the input bundles or installed apps are changed.
"""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--compatible-previous', required=True)
    parser.add_argument('--incompatible-previous', required=True)
    parser.add_argument('--adhoc', required=True)
    parser.add_argument('--signing-identity', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    checker = root / 'scripts/check-release-signing.py'
    builds = [int(plistlib.loads((Path(app) / 'Contents/Info.plist').read_bytes())['CFBundleVersion'])
              for app in [args.candidate, args.compatible_previous, args.incompatible_previous, args.adhoc]]
    build = max(builds) + 1
    legacy_build = builds[2]
    (root / '.build').mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='release-signing-', dir=root / '.build') as directory:
        work = Path(directory)

        def signed_copy(name, version, floor, profile=None):
            app = work / name / 'Draplet.app'
            result = subprocess.run(['ditto', str(args.candidate), str(app)], capture_output=True)
            if result.returncode:
                raise SystemExit('Could not copy the signing fixture.')
            path = app / 'Contents/Info.plist'
            info = plistlib.loads(path.read_bytes())
            info['CFBundleVersion'] = str(version)
            if floor is None:
                info.pop('DrapletMinimumAutoupdateVersion', None)
            else:
                info['DrapletMinimumAutoupdateVersion'] = floor
            path.write_bytes(plistlib.dumps(info))
            result = subprocess.run(['bash', str(root / 'scripts/sign-app.sh'), str(app), args.signing_identity],
                                    capture_output=True,
                                    env={**os.environ, 'DRAPLET_SIGNING_PROFILE': profile} if profile else None)
            if result.returncode:
                raise SystemExit('Could not sign the temporary fixture with the supplied test identity.')
            return str(app)

        candidate = signed_copy('candidate', build, build)
        unsafe = signed_copy('unsafe', build, legacy_build)
        lowered = signed_copy('lowered', build + 1, legacy_build)
        missing = signed_copy('missing', build + 1, None)
        invalid = signed_copy('invalid', build, build + 1)
        notes = work / 'migration.html'
        notes.write_text('<p data-permission-migration>One-time migration: approve Accessibility '
                         'and Screen Recording again. Preferences and pins are retained.</p>')
        previous = ['--previous-app', args.compatible_previous]
        legacy = ['--previous-app', args.incompatible_previous]
        cases = [
            ('previous release is mandatory', [candidate], False, 'required'),
            ('compatible previous release', [candidate, *previous, '--migration-notes', str(notes)], True, 'compatible'),
            ('incompatible automatic update', [unsafe, *legacy], False, 'identity differs'),
            ('explicit permission migration', [candidate, *legacy, '--migration-notes', str(notes)], True, 'manual migration'),
            ('migration notes are mandatory', [candidate, *legacy], False, 'requires release notes'),
            ('later releases retain the recovery notice', [candidate, *previous], False, 'requires release notes'),
            ('missing notes file is rejected', [candidate, *legacy, '--migration-notes', str(work / 'absent.html')], False, 'requires release notes'),
            ('every previous release is checked', [unsafe, *previous, *legacy], False, 'identity differs'),
            ('ad-hoc migration is rejected', [args.adhoc, *previous, '--migration-notes', str(notes)], False, 'Ad-hoc update rejected'),
            ('migration boundary survives later releases', [lowered, '--previous-app', candidate], False, 'cannot be lowered'),
            ('signed migration policy is mandatory', [missing, *previous], False, 'must embed'),
            ('appcast must use the signed policy', [candidate, *previous, '--minimum-autoupdate-version', str(legacy_build)], False, 'does not match'),
            ('build must increase', [candidate, '--previous-app', candidate], False, 'must be newer'),
            ('future migration boundary is rejected', [invalid, *previous], False, 'Invalid minimum'),
        ]
        signature = subprocess.run(['codesign', '-d', '-vv', candidate], capture_output=True, text=True)
        if 'TeamIdentifier=not set' in signature.stdout + signature.stderr:
            runtime = signed_copy('runtime', build, build, profile='apple')
            cases.append(('unlaunchable self-signed runtime is rejected', [runtime, *previous], False,
                          'Hardened runtime without an Apple Team ID'))
        for name, arguments, accepted, message in cases:
            result = subprocess.run([sys.executable, str(checker), *arguments], capture_output=True, text=True)
            output = result.stdout + result.stderr
            assert (result.returncode == 0) == accepted and message in output, name + ': ' + output
            print('PASS', name, flush=True)


if __name__ == '__main__':
    main()
