#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash scripts/fetch-sparkle.sh
mkdir -p .build
xcrun clang -fobjc-arc -fblocks -DHIDDENBAR_NATIVE_VISIBILITY=1 \
  -c Vendor/HiddenBar/Engine/Native/HBNativeVisibilityShim.m -o .build/TestNativeVisibility.o
xcrun clang -fobjc-arc -fblocks -mmacosx-version-min=14.2 -c Sources/WindowServerBridge.m -o .build/TestWindowServerBridge.o
xcrun swiftc -swift-version 5 -D HIDDENBAR_NATIVE_VISIBILITY \
  -module-cache-path "${TMPDIR:-/tmp}/codex-swift-module-cache" \
  -import-objc-header Sources/WindowServerBridge.h \
  -F .build/dependencies/sparkle-2.10.0 -framework Sparkle \
  -Xlinker -rpath -Xlinker "$PWD/.build/dependencies/sparkle-2.10.0" \
  Tests/main.swift Sources/AppUpdater.swift Sources/UpdateReminderPolicy.swift Sources/CaptureRetryPolicy.swift Sources/PermissionMonitor.swift Sources/WindowServerSnapshot.swift Sources/ForegroundApplication.swift Sources/FrameDeliveryGate.swift Sources/Settings.swift Sources/Preferences.swift Sources/IndicatorIcons.swift Sources/LeftCurtain.swift Sources/MenuAnimation.swift Sources/MenuBarBackdrop.swift Sources/SystemPresentation.swift Sources/ForegroundFullscreen.swift Vendor/HiddenBar/Engine/*.swift Vendor/HiddenBar/Engine/Native/*.swift \
  Vendor/HiddenBar/Layout/*.swift .build/TestNativeVisibility.o .build/TestWindowServerBridge.o -o .build/DrapletTests
.build/DrapletTests
