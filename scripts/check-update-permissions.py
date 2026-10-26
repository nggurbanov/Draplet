#!/usr/bin/env python3
"""Check privacy evidence written by a normally launched disposable app.

Launch and quit through the macOS UI, and authorize the fixture explicitly.
Never launch the test host as a shell child: it can inherit the parent's TCC
grants, invalidating the test. This collector reads evidence and never grants
permissions, launches applications or captures the screen.
"""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixture', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--phase', choices=['baseline', 'before', 'after'], required=True)
    args = parser.parse_args()
    app = (args.fixture / 'installed/Draplet Update Test.app').resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    bundle = info['CFBundleIdentifier']
    assert info.get('DrapletUpdateTest') is True and bundle.startswith('com.tyrell.Draplet.UpdateTest.'), \
        'Only disposable update fixtures are allowed.'
    source = Path(info['DrapletPrivacyTestReport'])
    assert time.time() - source.stat().st_mtime < 3, 'The native report is stale; launch the fixture normally.'
    state = json.loads(source.read_text())
    assert state['parentPID'] == 1, 'A shell-child launch cannot establish independent privacy authorization.'
    command = subprocess.check_output(['ps', '-p', str(state['pid']), '-o', 'comm='], text=True).strip()
    assert command == str(app / 'Contents/MacOS/Draplet'), 'The report does not belong to the live fixture.'
    args.report.mkdir(parents=True, exist_ok=True)
    if args.phase == 'baseline':
        assert state['build'] == '100' and not state['accessibility'] and not state['screenRecording'], \
            'The fresh fixture already sees privacy grants; this is not an independent baseline.'
    else:
        baseline = json.loads((args.report / 'baseline.json').read_text())
        assert not baseline['accessibility'] and not baseline['screenRecording'], 'A denied baseline is mandatory.'
        assert state['accessibility'] and state['screenRecording'], 'The fixture lost privacy authorization: ' + repr(state)
        assert state['automaticDownloads'] is True, 'Automatic downloads must remain enabled.'
        if args.phase == 'before':
            assert state['build'] == '100' and state['ready'] == '0.5.1', 'The real update must be staged first.'
        else:
            before = json.loads((args.report / 'before.json').read_text())
            assert state['build'] == '101' and state['pid'] != before['pid'], 'The successor did not launch.'
            prefs = plistlib.loads(subprocess.check_output(['defaults', 'export', bundle, '-']))
            assert prefs['permissionUpdateSentinel'] == 'preserved', 'Fixture preferences changed.'
            result = {'passed': True, 'before': before, 'after': state,
                      'independentDeniedBaseline': True, 'preferencesPreserved': True,
                      'scope': 'LaunchServices app identity on this Mac; isolated bundle ID'}
            (args.report / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    (args.report / (args.phase + '.json')).write_text(json.dumps(state, indent=2) + '\n')
    print(json.dumps({'phase': args.phase, 'passed': True, 'accessibility': state['accessibility'],
                      'screenRecording': state['screenRecording'], 'build': state['build']}), flush=True)


if __name__ == '__main__':
    main()
