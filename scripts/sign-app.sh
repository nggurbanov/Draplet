#!/bin/bash
# Use the same identity throughout Sparkle's helper graph, not just the host.
set -euo pipefail
app="$1"
identity="${2:-auto}"
if [ "$identity" = auto ]; then
  identity=$(security find-identity -v -p codesigning | awk '/"Apple Development:/{print $2; exit}')
  identity="${identity:--}"
fi
sign_options=()
if [ "$identity" != '-' ]; then sign_options=(--options runtime); fi
framework="$app/Contents/Frameworks/Sparkle.framework"
for helper in "$framework"/Versions/B/XPCServices/*.xpc "$framework"/Versions/B/Updater.app; do
  codesign --force --sign "$identity" "${sign_options[@]}" "$helper"
done
codesign --force --sign "$identity" "${sign_options[@]}" "$framework"/Versions/B/Autoupdate
codesign --force --sign "$identity" "${sign_options[@]}" "$framework"
codesign --force --sign "$identity" "${sign_options[@]}" "$app"
codesign --verify --deep --strict "$app"
