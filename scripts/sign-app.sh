#!/bin/bash
# Use the same identity throughout Sparkle's helper graph, not just the host.
set -euo pipefail
app="$1"
identity="${2:-auto}"
if [ "$identity" = auto ]; then
  identity=$(security find-identity -v -p codesigning | awk '/"Apple Development:/{print $2; exit}')
  identity="${identity:--}"
fi
sign_options=(--options 0)
case "${DRAPLET_SIGNING_PROFILE:-apple}" in
  apple)
    if [ "$identity" != '-' ]; then sign_options=(--options runtime); fi
    ;;
  alpha)
    # Unnotarized alpha keeps the same runtime policy as the ad-hoc releases.
    # A self-signed identity has no Apple Team ID, so hardened runtime would
    # refuse to load Sparkle even when both use the same certificate.
    ;;
  *) echo 'Unknown DRAPLET_SIGNING_PROFILE; use apple or alpha.' >&2; exit 1 ;;
esac
framework="$app/Contents/Frameworks/Sparkle.framework"
for helper in "$framework"/Versions/B/XPCServices/*.xpc "$framework"/Versions/B/Updater.app; do
  codesign --force --sign "$identity" "${sign_options[@]}" "$helper"
done
codesign --force --sign "$identity" "${sign_options[@]}" "$framework"/Versions/B/Autoupdate
codesign --force --sign "$identity" "${sign_options[@]}" "$framework"
codesign --force --sign "$identity" "${sign_options[@]}" "$app"
codesign --verify --deep --strict "$app"
