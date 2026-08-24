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

# ── Distribute ───────────────────────────────────────────────────────────────
# Uploading is not shipping. A build that lands in App Store Connect belonging
# to no beta group is invisible to every tester, and TestFlight then offers
# them the newest build their groups DO carry — so the new version looks like
# it silently failed to install, or worse, downgrades them. That is exactly
# what happened to build 96, which sat undistributed while the script printed
# "Uploaded" and stopped.
#
# GROUP=... picks a different one. External groups additionally need the build
# submitted for Beta App Review; group membership alone does not distribute to
# them either.
GROUP=${GROUP:-Family (internal)}

log "Waiting for processing, then adding it to '$GROUP'"
python3 - "$BUNDLE" "$BUILD_NO" "$GROUP" <<'PYEOF'
import sys, time
# cd to the script's directory happened in the shell above, so asc/ is here.
sys.path.insert(0, "asc")
import asc

bundle, target, group_name = sys.argv[1], sys.argv[2], sys.argv[3]

app = asc.call("GET", f"/v1/apps?filter[bundleId]={bundle}")["data"][0]["id"]

groups = asc.call("GET", f"/v1/apps/{app}/betaGroups?limit=50")["data"]
match = [g for g in groups if g["attributes"].get("name") == group_name]
if not match:
    sys.exit("no beta group named %r (have: %s)"
             % (group_name, ", ".join(g["attributes"].get("name") for g in groups)))
group = match[0]
gid = group["id"]
external = not group["attributes"].get("isInternalGroup")

# Ingestion runs well past the point where the upload reports success, and the
# build is not addressable until it does.
build = None
deadline = time.time() + 1800
while time.time() < deadline:
    for b in asc.call("GET", f"/v1/builds?filter[app]={app}&limit=5&sort=-version")["data"]:
        if b["attributes"].get("version") == target:
            if b["attributes"].get("processingState") == "VALID":
                build = b
            break
    if build:
        break
    print("  still processing...")
    time.sleep(60)
if not build:
    sys.exit("build %s never became VALID; assign it by hand in App Store Connect" % target)

asc.call("POST", f"/v1/builds/{build['id']}/relationships/betaGroups",
         {"data": [{"type": "betaGroups", "id": gid}]})

# External testers cannot install until Apple has reviewed the build, and
# adding it to a group does not submit it.
if external:
    try:
        asc.call("POST", "/v1/betaAppReviewSubmissions", {"data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}})
    except Exception as err:
        print("  beta review submission failed:", str(err)[:200])

# Verify from the group's side. The POST returning cleanly is not evidence
# that a tester can see the build.
carried = sorted((int(b["attributes"]["version"])
                  for b in asc.call("GET", f"/v1/betaGroups/{gid}/builds?limit=200")["data"]),
                 reverse=True)
state = asc.call("GET", f"/v1/builds/{build['id']}/buildBetaDetail")["data"]["attributes"]
print("  '%s' now carries: %s" % (group_name, carried[:5]))
print("  internal: %s   external: %s"
      % (state.get("internalBuildState"), state.get("externalBuildState")))
if target not in (str(v) for v in carried):
    sys.exit("build %s is still not in the group" % target)
PYEOF

cat <<EOF

Done. Build $BUILD_NO is uploaded and assigned to '$GROUP'.

Internal testers (people on your App Store Connect team, up to 100) get it
straight away, with no review. External groups go through Beta App Review;
after the first build of a version has passed, later ones usually clear
immediately.
EOF
