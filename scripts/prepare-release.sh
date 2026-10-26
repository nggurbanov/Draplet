#!/bin/bash
# Build local artifacts and a signed candidate appcast. Does not publish anything.
set -euo pipefail
cd "$(dirname "$0")/.."
export DRAPLET_SIGNING_IDENTITY="${DRAPLET_SIGNING_IDENTITY:--}"
bash scripts/build-dmg.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
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
  --embed-release-notes \
  --link https://github.com/nggurbanov/Draplet \
  --download-url-prefix "https://github.com/nggurbanov/Draplet/releases/download/v$version/" "$staging"
cp "$staging/appcast.xml" "dist/appcast-$version.xml"
python3 scripts/prepare-source.py
(cd dist && shasum -a 256 "Draplet-$version.dmg" "$archive" "Draplet-$version-source.tar.gz" > "Draplet-$version.sha256")
echo "Prepared $version. Publish release assets before replacing updates/appcast.xml with dist/appcast-$version.xml."
