#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/Draplet.app/Contents/{MacOS,Resources}
xcrun clang -fobjc-arc -fblocks -DHIDDENBAR_NATIVE_VISIBILITY=1 \
  -mmacosx-version-min=14.0 -c Vendor/HiddenBar/Engine/Native/HBNativeVisibilityShim.m -o .build/NativeVisibility.o
swift_sources=(Sources/*.swift Vendor/HiddenBar/Engine/*.swift Vendor/HiddenBar/Engine/Native/*.swift Vendor/HiddenBar/Layout/*.swift)
xcrun swiftc -O -swift-version 5 -D HIDDENBAR_NATIVE_VISIBILITY \
  -module-cache-path "${TMPDIR:-/tmp}/codex-swift-module-cache" \
  -import-objc-header Vendor/HiddenBar/Engine/Native/HBNativeVisibilityShim.h \
  "${swift_sources[@]}" .build/NativeVisibility.o -o .build/Draplet.app/Contents/MacOS/Draplet
cp Resources/Info.plist .build/Draplet.app/Contents/Info.plist
cp LICENSE ThirdPartyNotices.md .build/Draplet.app/Contents/Resources/
cp Vendor/HiddenBar/LICENSE .build/Draplet.app/Contents/Resources/HiddenBar-LICENSE
mkdir -p .build/Draplet.app/Contents/Resources/HiddenBar
cp Resources/HiddenBar/*.png .build/Draplet.app/Contents/Resources/HiddenBar/
if [ -f Resources/Draplet.icns ]; then cp Resources/Draplet.icns .build/Draplet.app/Contents/Resources/; fi
identity="${DRAPLET_SIGNING_IDENTITY:--}"
if [ "$identity" = "-" ]; then
  identity=$(security find-identity -v -p codesigning | awk '/"Apple Development:/{print $2; exit}')
  identity="${identity:--}"
fi
codesign --force --sign "$identity" --options runtime .build/Draplet.app
codesign --verify --strict .build/Draplet.app
echo "Built: $PWD/.build/Draplet.app"
