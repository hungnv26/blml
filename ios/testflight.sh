#!/usr/bin/env bash
#
# Build BLML and upload it to TestFlight.
#
#   ./testflight.sh
#
# Needs an App Store Connect API key, once:
#
#   App Store Connect -> Users and Access -> Integrations -> App Store Connect API
#   -> generate a key with the "App Manager" role, download the .p8, and put it in
#      ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8
#
#   Then export the two identifiers shown next to the key, or drop them in
#   ios/.testflight.env (gitignored):
#     ASC_KEY_ID=ABCD123456
#     ASC_ISSUER_ID=69a6de70-....
#
# The .p8 is downloadable exactly once and cannot be recovered — keep a copy
# somewhere safe. Anyone holding it can publish builds as you.
#
# The app record itself has to exist in App Store Connect first. Apple has no
# API for creating one, so that step is a visit to the website; everything
# after it is this script.
set -euo pipefail
cd "$(dirname "$0")"

TEAM=Y9T5MPV87F
BUNDLE=app.blml.chat
BUILD_DIR=${TMPDIR:-/tmp}/blml-testflight

log() { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# shellcheck disable=SC1091
[ -f .testflight.env ] && { set -a; source .testflight.env; set +a; }

: "${ASC_KEY_ID:?set ASC_KEY_ID (in ios/.testflight.env or the environment)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (in ios/.testflight.env or the environment)}"

KEY_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
[ -f "$KEY_FILE" ] || die "API key not found at $KEY_FILE"

# Every upload needs a build number App Store Connect has not seen before, and
# it will reject a duplicate after the whole upload has transferred. Derive it
# from the commit count, which only ever goes up.
BUILD_NO=$(git rev-list --count HEAD)
VERSION=$(grep -oE '^GIT_TAG = .*' prod.xcconfig | awk '{print $3}')
log "Building $VERSION ($BUILD_NO)"

rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"
xcodebuild -workspace Tinodios.xcworkspace -scheme Tinodios -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$BUILD_DIR/BLML.xcarchive" \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
  CURRENT_PROJECT_VERSION="$BUILD_NO" \
  -allowProvisioningUpdates archive 2>&1 | grep -E "ARCHIVE (SUCCEEDED|FAILED)" \
  || die "archive failed"

cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
    <key>uploadSymbols</key><true/>
    <key>destination</key><string>export</string>
</dict>
</plist>
PLIST

log "Exporting a distribution build"
xcodebuild -exportArchive -archivePath "$BUILD_DIR/BLML.xcarchive" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$BUILD_DIR/export" -allowProvisioningUpdates 2>&1 \
  | grep -E "EXPORT (SUCCEEDED|FAILED)" || die "export failed"

IPA=$(find "$BUILD_DIR/export" -name '*.ipa' | head -1)
[ -n "$IPA" ] || die "no .ipa produced"

# Catch the common signing mistakes here rather than after a 95 MB upload and a
# rejection email.
ENT=$(codesign -d --entitlements :- "$BUILD_DIR/export"/*.ipa 2>/dev/null || true)
log "Validating before upload"
xcrun altool --validate-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tail -5

log "Uploading $(du -h "$IPA" | cut -f1) to App Store Connect"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tail -8

cat <<EOF

Uploaded. App Store Connect processes the build for 5-15 minutes before it
appears in TestFlight.

Internal testers (people on your App Store Connect team, up to 100) get it as
soon as processing finishes, with no review. External testers need the first
build of each version to pass Beta App Review, usually within a day.
EOF
