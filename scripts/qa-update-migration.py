#!/usr/bin/env python3
"""Verify that an isolated legacy client cannot silently install a migration.

Prepare a fresh migration fixture, then serve .build/update-test-http on port
18734. This checks Sparkle and the production updater controller, not TCC grants.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixture', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    app = args.fixture / 'installed/Draplet Update Test.app'
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    bundle = info['CFBundleIdentifier']
    assert info.get('DrapletUpdateTest') is True and bundle.startswith('com.tyrell.Draplet.UpdateTest.migration'), \
        'Only disposable migration fixtures are allowed.'
    assert info['CFBundleVersion'] == '100', 'Prepare a fresh fixture first.'
    assert info['SUAutomaticallyUpdate'] is True, 'This check needs automatic downloads enabled.'
    args.report.mkdir(parents=True, exist_ok=True)
    # Delay the reminder in this disposable domain so unattended QA cannot
    # interrupt the user's desktop. The pending review itself is still asserted.
    for key, kind, value in [('migrationSentinel', '-string', 'preserved'),
                             ('updateReminderVersion', '-string', '101'),
                             ('updateReminderDeferredUntil', '-date', '2035-01-01T00:00:00Z')]:
        subprocess.run(['defaults', 'write', bundle, key, kind, value], check=True)
    spec = importlib.util.spec_from_file_location('native_qa', Path(__file__).with_name('qa-native.py'))
    assert spec is not None and spec.loader is not None
    qa = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(qa)
    control = qa.Controls(app / 'Contents/MacOS/Draplet', args.report / 'runtime.log',
                          '--test-controls', '--qa-no-reopen')
    try:
        deadline = time.monotonic() + 30
        while True:
            state = control.request('update-status')
            assert not state['ready'], 'Legacy client silently staged the migration: ' + repr(state)
            if state['pending'] == '0.5.1':
                break
            if time.monotonic() > deadline:
                raise AssertionError('Migration review was not offered: ' + repr(state))
            time.sleep(.25)
        assert state['automaticDownloads'] is True, state
        control.send('quit')
        control.process.wait(timeout=10)
        time.sleep(2)
        installed = plistlib.loads(info_path.read_bytes())['CFBundleVersion']
        assert installed == '100', 'Ordinary exit installed the migration without consent.'
        prefs = plistlib.loads(subprocess.check_output(['defaults', 'export', bundle, '-']))
        assert prefs['migrationSentinel'] == 'preserved', 'Fixture preferences changed.'
        result = {'passed': True, 'automaticDownloadsEnabled': True, 'pendingReview': state['pending'],
                  'stagedForInstallation': False, 'installedAfterQuit': installed, 'preferencesPreserved': True,
                  'privacyPermissionPreservationTested': False}
        (args.report / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result), flush=True)
    finally:
        control.close()


if __name__ == '__main__':
    main()
