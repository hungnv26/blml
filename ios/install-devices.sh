#!/usr/bin/env bash
#
# Build the BLML iOS app and install it on every reachable paired device.
# Run this to push app updates.
#
# Signed with the paid developer team, so profiles last a year rather than the
# seven days a free personal team gave. The weekly re-signing agent installed by
# install-resign-agent.sh is no longer needed to keep apps alive; it is only
# useful now as a way to push updates on a schedule.
#
# A device is "reachable" when it's on this Mac via USB or same-network Wi-Fi,
# unlocked at least once recently. Unreachable devices are skipped — rerun
# later; already-installed apps keep working until their signature expires.
#
set -euo pipefail
cd "$(dirname "$0")"

echo "── building ──"
# Release, not Debug: Release reads prod.xcconfig, so the app points at
# chat.blml.app over TLS. The entitlements override is gone too — a free team
# could not sign push or associated domains, so the build had to be stripped to
# an empty entitlements file. The paid team signs them properly.
xcodebuild -workspace Tinodios.xcworkspace -scheme Tinodios -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build-device ARCHS=arm64 \
  DEVELOPMENT_TEAM=Y9T5MPV87F CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"

APP="build-device/Build/Products/Release-iphoneos/Tinodios.app"

echo "── installing ──"
# name:identifier pairs of the family devices
DEVICES=(
  "your iPhone 17 Pro Max:BCCF9AEE-3AFE-5108-9731-1F6D24FE4008"
  "kid's iPhone 11:CD656C0A-B624-50F3-B7E9-798C823DF9DC"
  "iPad:07B7855D-8EA8-5644-9047-1999AE53C373"
)
for entry in "${DEVICES[@]}"; do
  NAME="${entry%%:*}"; ID="${entry##*:}"
  if xcrun devicectl device install app --device "$ID" "$APP" >/dev/null 2>&1; then
    echo "  ✓ $NAME"
  else
    echo "  ✗ $NAME (offline or locked — rerun when connected)"
  fi
done
