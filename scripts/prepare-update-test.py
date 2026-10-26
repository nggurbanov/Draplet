#!/usr/bin/env python3
"""Prepare an isolated N -> N+1 fixture; never modifies /Applications/Draplet.app."""
import pathlib
import plistlib
import subprocess
import os
import sys
import xml.etree.ElementTree as ET
ET.register_namespace("sparkle", "http://www.andymatuschak.org/xml-namespaces/sparkle")

root = pathlib.Path(__file__).resolve().parents[1]
scenario = sys.argv[1] if len(sys.argv) > 1 else 'good'
assert scenario in ('good', 'bad-signature', 'network', 'scheduled', 'migration')
suffix = '' if scenario == 'good' else '.' + scenario.replace('-', '')
run_id = os.environ.get('DRAPLET_TEST_RUN_ID', '')
if run_id:
    assert run_id.isalnum(), 'Use an alphanumeric test run ID'
    suffix += '.' + run_id
base = root / '.build' / ('update-test' + suffix)
base.mkdir(parents=True, exist_ok=True)
commands = [line.strip().split(None, 1)[-1] for line in subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True).splitlines()]
for kind in ('installed', 'release'):
    executable = base / kind / 'Draplet Update Test.app/Contents/MacOS/Draplet'
    names = [str(executable), str(executable.relative_to(root))]
    if any(command == name or command.startswith(name + ' ') for command in commands for name in names):
        raise SystemExit('Quit the existing update fixture before preparing another run.')
for kind, build in [('installed', '100'), ('release', '101')]:
    app = base / kind / 'Draplet Update Test.app'
    source_app = pathlib.Path(os.environ.get('DRAPLET_TEST_BASE_APP', str(root / '.build/Draplet.app')))
    subprocess.run(['ditto', str(source_app), str(app)], check=True)
    info = app / 'Contents/Info.plist'
    data = plistlib.loads(info.read_bytes())
    data.update(CFBundleIdentifier='com.tyrell.Draplet.UpdateTest' + suffix, CFBundleName='Draplet Update Test',
                CFBundleDisplayName='Draplet Update Test', CFBundleVersion=build,
                CFBundleShortVersionString='0.5.0' if build == '100' else '0.5.1',
                DrapletUpdateTest=True, SUFeedURL='http://127.0.0.1:18734/' + scenario + '/appcast.xml',
                NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
    if scenario == 'scheduled':
        data['SUAutomaticallyUpdate'] = False
    if report := os.environ.get('DRAPLET_TEST_PRIVACY_REPORT'):
        data['DrapletPrivacyTestReport'] = str(pathlib.Path(report).resolve())
    info.write_bytes(plistlib.dumps(data))
    subprocess.run(['bash', str(root / 'scripts/sign-app.sh'), str(app), os.environ.get('DRAPLET_TEST_SIGNING_IDENTITY', '-')], check=True)
archive_dir = base / 'feed'
archive_dir.mkdir(exist_ok=True)
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent',
                str(base / 'release/Draplet Update Test.app'), str(archive_dir / 'Draplet-0.5.1.zip')], check=True)
(archive_dir / 'appcast.xml').unlink(missing_ok=True)
appcast_args = [str(root / '.build/dependencies/sparkle-2.10.0/bin/generate_appcast'),
                '--account', 'DrapletUpdates', '--download-url-prefix', 'http://127.0.0.1:18734/' + scenario + '/',
                '--maximum-deltas', '0']
appcast_args += ['--major-version', '101'] if scenario == 'migration' else ['--critical-update-version', '']
subprocess.run([*appcast_args, str(archive_dir)], check=True)
if scenario == 'bad-signature':
    archive = archive_dir / 'Draplet-0.5.1.zip'
    with archive.open('ab') as output:
        output.write(b'corruption-for-EdDSA-test')
    feed = archive_dir / 'appcast.xml'
    tree = ET.parse(feed)
    enclosure = tree.find('./channel/item/enclosure')
    if enclosure is None:
        raise SystemExit('Generated update feed has no enclosure')
    enclosure.set('length', str(archive.stat().st_size))
    tree.write(feed, encoding='utf-8', xml_declaration=True)
# The HTTP root is a directory of isolated scenario symlinks.
http_root = root / '.build/update-test-http'
http_root.mkdir(exist_ok=True)
link = http_root / scenario
if link.is_symlink():
    link.unlink()
elif link.exists():
    raise SystemExit('The test HTTP path is not a symlink; refusing to replace it.')
link.symlink_to(archive_dir)
if scenario == 'network':
    (archive_dir / 'appcast.xml').rename(archive_dir / 'offline-appcast.xml')
print(base)
print('Bundle ID: com.tyrell.Draplet.UpdateTest' + suffix)
