#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash scripts/fetch-sparkle.sh
sparkle="$PWD/.build/dependencies/sparkle-2.10.0"
mkdir -p .build/Draplet.app/Contents/{MacOS,Resources,Frameworks}
xcrun clang -fobjc-arc -fblocks -DHIDDENBAR_NATIVE_VISIBILITY=1 \
  -mmacosx-version-min=14.2 -c Vendor/HiddenBar/Engine/Native/HBNativeVisibilityShim.m -o .build/NativeVisibility.o
swift_sources=(Sources/*.swift Vendor/HiddenBar/Engine/*.swift Vendor/HiddenBar/Engine/Native/*.swift Vendor/HiddenBar/Layout/*.swift)
xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos14.2" -D HIDDENBAR_NATIVE_VISIBILITY \
  -module-cache-path "${TMPDIR:-/tmp}/codex-swift-module-cache" \
  -import-objc-header Vendor/HiddenBar/Engine/Native/HBNativeVisibilityShim.h \
  -F "$sparkle" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  "${swift_sources[@]}" .build/NativeVisibility.o -o .build/Draplet.app/Contents/MacOS/Draplet
cp Resources/Info.plist .build/Draplet.app/Contents/Info.plist
ditto "$sparkle/Sparkle.framework" .build/Draplet.app/Contents/Frameworks/Sparkle.framework
cp "$sparkle/LICENSE" .build/Draplet.app/Contents/Resources/Sparkle-LICENSE
cp LICENSE ThirdPartyNotices.md .build/Draplet.app/Contents/Resources/
cp Vendor/HiddenBar/LICENSE .build/Draplet.app/Contents/Resources/HiddenBar-LICENSE
mkdir -p .build/Draplet.app/Contents/Resources/HiddenBar
cp Resources/HiddenBar/*.png .build/Draplet.app/Contents/Resources/HiddenBar/
if [ -f Resources/Draplet.icns ]; then cp Resources/Draplet.icns .build/Draplet.app/Contents/Resources/; fi
# Ad-hoc alpha artifacts omit hardened runtime. Development/distribution
# identities enable it after re-signing every nested helper with the same identity.
bash scripts/sign-app.sh .build/Draplet.app "${DRAPLET_SIGNING_IDENTITY:-auto}"
echo "Built: $PWD/.build/Draplet.app"
