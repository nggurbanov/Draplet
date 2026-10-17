#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -x .build/packaging-venv/bin/dmgbuild ]; then
  python3 -m venv .build/packaging-venv
  .build/packaging-venv/bin/pip install 'dmgbuild==1.6.7'
fi
bash build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
mkdir -p dist
.build/packaging-venv/bin/dmgbuild -s scripts/dmg-settings.py 'Draplet' "dist/Draplet-${version}.dmg"
hdiutil verify "dist/Draplet-${version}.dmg"

# Verify the app after packaging: Finder metadata can invalidate a signed bundle.
verify_mount=$(mktemp -d "$PWD/.build/dmg-check.XXXXXX")
cleanup() {
  hdiutil detach "$verify_mount" >/dev/null 2>&1 || true
  rmdir "$verify_mount" 2>/dev/null || true
}
trap cleanup EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$verify_mount" "dist/Draplet-${version}.dmg" >/dev/null
codesign --verify --strict "$verify_mount/Draplet.app"
[ "$(readlink "$verify_mount/Applications")" = '/Applications' ]
cmp .build/Draplet.app/Contents/MacOS/Draplet "$verify_mount/Draplet.app/Contents/MacOS/Draplet"
echo "Verified mounted app signature, executable and Applications shortcut."
