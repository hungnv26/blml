#!/usr/bin/env bash
#
# Build the BLML iOS app (free-team signed) and install it on every reachable
# paired device. Run this to push app updates — and weekly, because free-team
# signatures expire after 7 days.
#
# A device is "reachable" when it's on this Mac via USB or same-network Wi-Fi,
# unlocked at least once recently. Unreachable devices are skipped — rerun
# later; already-installed apps keep working until their signature expires.
#
set -euo pipefail
cd "$(dirname "$0")"

echo "── building ──"
xcodebuild -workspace Tinodios.xcworkspace -scheme Tinodios -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build-device ARCHS=arm64 \
  DEVELOPMENT_TEAM=Y9T5MPV87F CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_ENTITLEMENTS="$PWD/Tinodios/Tinodios-dev.entitlements" \
  -allowProvisioningUpdates build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"

APP="build-device/Build/Products/Debug-iphoneos/Tinodios.app"

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
