#!/usr/bin/env bash
#
# Validates the two Firebase client config files before we spend a build on
# them. The failure this catches is quiet and expensive: a config for the wrong
# project, or the placeholder still in place, produces an app that builds, runs,
# and silently never receives a notification.
#
#   ./deploy/check-firebase-config.sh
set -uo pipefail
cd "$(dirname "$0")/.."

ANDROID=android/app/google-services.json
IOS=ios/GoogleService-Info.plist
PKG=app.blml.chat
fail=0

note() { printf '  %-22s %s\n' "$1" "$2"; }
bad()  { printf '  %-22s \033[1;31m%s\033[0m\n' "$1" "$2"; fail=1; }
good() { printf '  %-22s \033[1;32m%s\033[0m\n' "$1" "$2"; }

echo "Android — $ANDROID"
if [ ! -f "$ANDROID" ]; then
  bad "file" "missing"
else
  proj=$(python3 -c "import json;print(json.load(open('$ANDROID'))['project_info'].get('project_id',''))" 2>/dev/null)
  num=$(python3 -c "import json;print(json.load(open('$ANDROID'))['project_info'].get('project_number',''))" 2>/dev/null)
  pkgs=$(python3 -c "
import json
d=json.load(open('$ANDROID'))
print(','.join(c['client_info']['android_client_info']['package_name'] for c in d.get('client',[])))" 2>/dev/null)
  case "$proj" in
    ""|blml-placeholder) bad "project_id" "$proj (still the placeholder)" ;;
    *) good "project_id" "$proj" ;;
  esac
  case "$num" in
    ""|000000000000) bad "project_number" "$num (still the placeholder)" ;;
    *) good "project_number" "$num" ;;
  esac
  case ",$pkgs," in
    *",$PKG,"*) good "package_name" "$pkgs" ;;
    *) bad "package_name" "$pkgs (expected $PKG)" ;;
  esac
fi

echo
echo "iOS — $IOS"
if [ ! -f "$IOS" ]; then
  bad "file" "missing"
else
  val() { plutil -extract "$1" raw -o - "$IOS" 2>/dev/null; }
  proj=$(val PROJECT_ID); bundle=$(val BUNDLE_ID); sender=$(val GCM_SENDER_ID)
  case "$proj" in
    ""|blml-placeholder) bad "PROJECT_ID" "$proj (still the placeholder)" ;;
    *) good "PROJECT_ID" "$proj" ;;
  esac
  case "$sender" in
    ""|000000000000) bad "GCM_SENDER_ID" "$sender (still the placeholder)" ;;
    *) good "GCM_SENDER_ID" "$sender" ;;
  esac
  [ "$bundle" = "$PKG" ] && good "BUNDLE_ID" "$bundle" || bad "BUNDLE_ID" "$bundle (expected $PKG)"
  # Push must be enabled on the Firebase app itself. Current plists use
  # IS_GCM_ENABLED; IS_GCM_MESSAGING_ENABLED is the legacy spelling, so accept
  # either rather than reporting a working config as suspect.
  gcm=$(val IS_GCM_ENABLED); [ -n "$gcm" ] || gcm=$(val IS_GCM_MESSAGING_ENABLED)
  [ "$gcm" = "true" ] && good "push enabled" "yes" || bad "push enabled" "${gcm:-unset}"
  # Analytics off is deliberate here and disclosed in the privacy policy.
  an=$(val IS_ANALYTICS_ENABLED)
  [ "$an" = "false" ] && good "analytics" "off (as intended)" || note "analytics" "${an:-unset}"
fi

echo
# Both files must describe the SAME Firebase project, or one platform silently
# talks to a project the server does not push to.
if [ -f "$ANDROID" ] && [ -f "$IOS" ]; then
  a=$(python3 -c "import json;print(json.load(open('$ANDROID'))['project_info'].get('project_id',''))" 2>/dev/null)
  i=$(plutil -extract PROJECT_ID raw -o - "$IOS" 2>/dev/null)
  if [ -n "$a" ] && [ "$a" = "$i" ]; then good "same project" "$a"; else bad "same project" "android=$a ios=$i"; fi
fi

echo
if [ "$fail" = "0" ]; then
  echo "  READY — configs look real and consistent."
else
  echo "  NOT READY — fix the red items above before building."
fi
exit $fail
