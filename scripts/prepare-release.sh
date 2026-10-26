#!/bin/bash
# Build local artifacts and a signed candidate appcast. Does not publish anything.
set -euo pipefail
cd "$(dirname "$0")/.."
case "${DRAPLET_SIGNING_IDENTITY:-}" in
  ''|'-'|'auto')
    echo 'Set DRAPLET_SIGNING_IDENTITY to an explicit stable certificate. Ad-hoc updates invalidate macOS privacy permissions.' >&2
    exit 1
    ;;
esac
export DRAPLET_SIGNING_IDENTITY
if [ -z "${DRAPLET_PREVIOUS_RELEASE_APP:-}" ] || [ ! -d "$DRAPLET_PREVIOUS_RELEASE_APP" ]; then
  echo 'Set DRAPLET_PREVIOUS_RELEASE_APP to the previous public application bundle.' >&2
  exit 1
fi
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)
minimum_auto=$(/usr/libexec/PlistBuddy -c 'Print :DrapletMinimumAutoupdateVersion' Resources/Info.plist)
if ! [[ "$minimum_auto" =~ ^[1-9][0-9]*$ && "$build" =~ ^[1-9][0-9]*$ ]] || (( build < minimum_auto )); then
  echo 'The release build must meet the permanent minimum automatic-update version.' >&2
  exit 1
fi
bash scripts/build-dmg.sh
signing_check=(.build/Draplet.app --previous-app "$DRAPLET_PREVIOUS_RELEASE_APP"
  --minimum-autoupdate-version "$minimum_auto" --migration-notes "updates/$version.html"
  --report-json .build/release-signing.json)
python3 scripts/check-release-signing.py "${signing_check[@]}"
public_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)
sparkle="$PWD/.build/dependencies/sparkle-2.10.0"
[ "$("$sparkle/bin/generate_keys" --account DrapletUpdates -p)" = "$public_key" ] || {
  echo 'The DrapletUpdates Keychain key does not match the app public key.' >&2; exit 1;
}
archive="Draplet-$version.zip"
ditto -c -k --sequesterRsrc --keepParent .build/Draplet.app "dist/$archive"
staging=$(mktemp -d "$PWD/.build/appcast.XXXXXX")
trap 'rm -rf "$staging"' EXIT
cp "dist/$archive" "$staging/"
if [ -f "updates/$version.html" ]; then cp "updates/$version.html" "$staging/Draplet-$version.html"; fi
"$sparkle/bin/generate_appcast" --account DrapletUpdates --maximum-deltas 0 \
  --embed-release-notes --major-version "$minimum_auto" \
  --link https://github.com/nggurbanov/Draplet \
  --download-url-prefix "https://github.com/nggurbanov/Draplet/releases/download/v$version/" "$staging"
python3 - "$staging/appcast.xml" "$minimum_auto" "$build" <<'PY'
import sys
import xml.etree.ElementTree as ET
namespace = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
items = ET.parse(sys.argv[1]).findall('./channel/item')
if len(items) != 1 or items[0].findtext('sparkle:version', namespaces=namespace) != sys.argv[3]:
    raise SystemExit('Generated feed does not contain exactly the candidate build.')
if items[0].findtext('sparkle:minimumAutoupdateVersion', namespaces=namespace) != sys.argv[2]:
    raise SystemExit('Generated feed omitted the permanent automatic-update migration boundary.')
PY
cp "$staging/appcast.xml" "dist/appcast-$version.xml"
python3 scripts/prepare-source.py
(cd dist && shasum -a 256 "Draplet-$version.dmg" "$archive" "Draplet-$version-source.tar.gz" > "Draplet-$version.sha256")
echo "Prepared $version. Publish release assets before replacing updates/appcast.xml with dist/appcast-$version.xml."
