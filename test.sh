#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build
xcrun clang -fobjc-arc -fblocks -DHIDDENBAR_NATIVE_VISIBILITY=1 \
  -c Vendor/HiddenBar/Engine/Native/HBNativeVisibilityShim.m -o .build/TestNativeVisibility.o
xcrun swiftc -swift-version 5 -D HIDDENBAR_NATIVE_VISIBILITY \
  -module-cache-path "${TMPDIR:-/tmp}/codex-swift-module-cache" \
  -import-objc-header Vendor/HiddenBar/Engine/Native/HBNativeVisibilityShim.h \
  Tests/main.swift Sources/Settings.swift Sources/Preferences.swift Sources/IndicatorIcons.swift Sources/LeftCurtain.swift Sources/MenuAnimation.swift Sources/MenuBarBackdrop.swift Sources/SystemOverview.swift Vendor/HiddenBar/Engine/*.swift Vendor/HiddenBar/Engine/Native/*.swift \
  Vendor/HiddenBar/Layout/*.swift .build/TestNativeVisibility.o -o .build/DrapletTests
.build/DrapletTests
