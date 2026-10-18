#!/usr/bin/env python3
"""Prepare an isolated N -> N+1 fixture; never modifies /Applications/Draplet.app."""
import pathlib
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET
ET.register_namespace("sparkle", "http://www.andymatuschak.org/xml-namespaces/sparkle")

root = pathlib.Path(__file__).resolve().parents[1]
scenario = sys.argv[1] if len(sys.argv) > 1 else 'good'
assert scenario in ('good', 'bad-signature', 'network')
suffix = '' if scenario == 'good' else '.' + scenario.replace('-', '')
base = root / '.build' / ('update-test' + suffix)
base.mkdir(parents=True, exist_ok=True)
for kind, build in [('installed', '100'), ('release', '101')]:
    app = base / kind / 'Draplet Update Test.app'
    subprocess.run(['ditto', str(root / '.build/Draplet.app'), str(app)], check=True)
    info = app / 'Contents/Info.plist'
    data = plistlib.loads(info.read_bytes())
    data.update(CFBundleIdentifier='com.tyrell.Draplet.UpdateTest' + suffix, CFBundleName='Draplet Update Test',
                CFBundleDisplayName='Draplet Update Test', CFBundleVersion=build,
                CFBundleShortVersionString='0.5.0' if build == '100' else '0.5.1',
                DrapletUpdateTest=True, SUFeedURL='http://127.0.0.1:18734/' + scenario + '/appcast.xml',
                NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
    info.write_bytes(plistlib.dumps(data))
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
archive_dir = base / 'feed'
archive_dir.mkdir(exist_ok=True)
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent',
                str(base / 'release/Draplet Update Test.app'), str(archive_dir / 'Draplet-0.5.1.zip')], check=True)
(archive_dir / 'appcast.xml').unlink(missing_ok=True)
subprocess.run([str(root / '.build/dependencies/sparkle-2.10.0/bin/generate_appcast'),
                '--account', 'DrapletUpdates', '--download-url-prefix', 'http://127.0.0.1:18734/' + scenario + '/',
                '--maximum-deltas', '0', '--critical-update-version', '', str(archive_dir)], check=True)
if scenario == 'bad-signature':
    archive = archive_dir / 'Draplet-0.5.1.zip'
    with archive.open('ab') as output:
        output.write(b'corruption-for-EdDSA-test')
    feed = archive_dir / 'appcast.xml'
    tree = ET.parse(feed)
    tree.find('./channel/item/enclosure').set('length', str(archive.stat().st_size))
    tree.write(feed, encoding='utf-8', xml_declaration=True)
# The HTTP root is a directory of isolated scenario symlinks.
http_root = root / '.build/update-test-http'
http_root.mkdir(exist_ok=True)
link = http_root / scenario
if not link.exists():
    link.symlink_to(archive_dir)
if scenario == 'network':
    (archive_dir / 'appcast.xml').rename(archive_dir / 'offline-appcast.xml')
print(base)
