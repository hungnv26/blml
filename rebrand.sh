#!/usr/bin/env bash
#
# Applies every text-level rebranding change described in REBRANDING.md across the
# four Tinode repos. Logo/icon *files* are not touched — replace those by hand.
#
# Edit the CONFIG block below, then run:  ./rebrand.sh
#
# Everything is a git clone, so any run is fully revertible:
#     for d in server webapp android ios; do git -C "$d" checkout .; done
#
set -euo pipefail

# ─────────────────────────────── CONFIG ────────────────────────────────────────
# Display name of your app, e.g. "Acme Chat".
APP_NAME="BLML"
# Short name for the PWA home-screen label (12 chars or less is safest).
APP_NAME_SHORT="BLML"
# One-line description used in HTML meta tags and the PWA manifest.
APP_DESCRIPTION="BLML group chat"
# Your server, no scheme, no trailing slash. Used as the default host in all clients.
SERVER_HOST="chat.blml.app"
# Your website, used for legal/support links.
SITE_URL="https://blml.app"
# Support email.
SUPPORT_EMAIL="support@blml.app"
# Android application id — must be globally unique on Google Play.
ANDROID_APP_ID="app.blml.chat"
# iOS bundle identifier — must be globally unique on the App Store.
IOS_BUNDLE_ID="app.blml.chat"
# Copyright line shown in the Android about screen.
COPYRIGHT="© 2026 BLML"
# ───────────────────────────── END CONFIG ──────────────────────────────────────

cd "$(dirname "$0")"
ROOT="$PWD"

# BSD (macOS) and GNU sed disagree on -i. Normalise.
if sed --version >/dev/null 2>&1; then SEDI=(sed -i); else SEDI=(sed -i ''); fi
sedi() { "${SEDI[@]}" "$@"; }

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()  { printf '  ✓ %s\n' "$*"; }

for d in server webapp android ios; do
  [ -d "$ROOT/$d" ] || { echo "missing repo: $d — run the clone step first" >&2; exit 1; }
done

if [ "$APP_NAME" = "MyChat" ] || [ "$SERVER_HOST" = "chat.example.com" ]; then
  echo "Edit the CONFIG block at the top of this script first." >&2
  exit 1
fi

# ═══════════════════════════════ WEB APP ═══════════════════════════════════════
say "webapp/"
cd "$ROOT/webapp"

sedi "s|<title>Tinode</title>|<title>${APP_NAME}</title>|" index.html
sedi "s|content=\"Tinode Web\"|content=\"${APP_NAME}\"|g" index.html
sedi "s|Tinode instant messenger in a browser|${APP_DESCRIPTION}|g" index.html
sedi "s|https://web.tinode.co/|https://${SERVER_HOST}/|g" index.html
sedi "s|TinodeWeb does not work|${APP_NAME} does not work|" index.html
ok "index.html — title, meta, Open Graph, canonical URL"

python3 - "$APP_NAME" "$APP_NAME_SHORT" "$APP_DESCRIPTION" <<'PY'
import json, sys, collections
name, short, desc = sys.argv[1], sys.argv[2], sys.argv[3]
with open('manifest.json') as f:
    m = json.load(f, object_pairs_hook=collections.OrderedDict)
m['name'] = name
m['short_name'] = short
m['description'] = desc
# Stop browsers offering the *official* Tinode store apps instead of ours.
m.pop('related_applications', None)
m['prefer_related_applications'] = False
with open('manifest.json', 'w') as f:
    json.dump(m, f, indent=2, ensure_ascii=False)
    f.write('\n')
PY
ok "manifest.json — PWA name, description, dropped related_applications"

sedi "s|BASE_APP_NAME = 'TinodeWeb'|BASE_APP_NAME = '${APP_NAME// /}'|" src/config.js
sedi "s|{hosted: 'web.tinode.co', local: 'localhost:6060'}|{hosted: '${SERVER_HOST}', local: 'localhost:6060'}|" src/config.js
sedi "s|mailto:support@tinode.co|mailto:${SUPPORT_EMAIL}|" src/config.js
sedi "s|https://tinode.co/privacy.html|${SITE_URL}/privacy.html|" src/config.js
sedi "s|https://tinode.co/terms.html|${SITE_URL}/terms.html|" src/config.js
ok "src/config.js — app name, default host, legal + support links"

sedi "s|+ 'Tinode';|+ '${APP_NAME}';|" src/lib/utils.js
ok "src/lib/utils.js — document.title"

sedi "s|<h2>Tinode Web</h2>|<h2>${APP_NAME}</h2>|" src/views/logo-view.jsx
# The logo + heading are wrapped in a link to Tinode's GitHub — visible on the
# login screen. Point it at our site instead.
sedi "s|https://github.com/tinode/chat/|${SITE_URL}|" src/views/logo-view.jsx
ok "src/views/logo-view.jsx — splash screen heading + logo link"

# ═══════════════════════════════ ANDROID ═══════════════════════════════════════
say "android/"
cd "$ROOT/android"
S=app/src/main/res/values/strings.xml

sedi "s|\"app_name\" translatable=\"false\">Tinode<|\"app_name\" translatable=\"false\">${APP_NAME}<|" $S
sedi "s|\"app_name_full\" translatable=\"false\">Tinode Chat<|\"app_name_full\" translatable=\"false\">${APP_NAME}<|" $S
sedi "s|\"tinode\" translatable=\"false\">Tinode<|\"tinode\" translatable=\"false\">${APP_NAME}<|" $S
sedi "s|\"app_description\" translatable=\"false\">Tinode Chat<|\"app_description\" translatable=\"false\">${APP_DESCRIPTION}<|" $S
sedi "s|© 2014 – 2025 Tinode|${COPYRIGHT}|" $S
sedi "s|>Tinode Logo<|>${APP_NAME} Logo<|" $S
sedi "s|>Tinode profile<|>${APP_NAME} profile<|" $S
sedi "s|>Send Tinode message<|>Send ${APP_NAME} message<|" $S
sedi "s|>Tinode download<|>${APP_NAME} download<|" $S
sedi "s|>Tinode User %1\$s<|>${APP_NAME} User %1\$s<|" $S
sedi "s|>Tinode Video Call<|>${APP_NAME} Video Call<|" $S
sedi "s|>Check out Tinode Messenger<|>Check out ${APP_NAME}<|" $S
sedi "s|Check out Tinode Messenger. Download it from https://tinode.co|Check out ${APP_NAME}. Download it from ${SITE_URL}|" $S
sedi "s|\"tinode_url\" translatable=\"false\">https://tinode.co<|\"tinode_url\" translatable=\"false\">${SITE_URL}<|" $S
sedi "s|mailto:support@tinode.co|mailto:${SUPPORT_EMAIL}|" $S
sedi "s|https://tinode.co/terms.html|${SITE_URL}/terms.html|" $S
sedi "s|https://tinode.co/privacy.html|${SITE_URL}/privacy.html|" $S
sedi "s|https://web.tinode.co/.well-known/assetlinks.json|https://${SERVER_HOST}/.well-known/assetlinks.json|" $S
ok "strings.xml — app name, UI strings, legal links"

sedi "s|applicationId \"co.tinode.tindroidx\"|applicationId \"${ANDROID_APP_ID}\"|" app/build.gradle
sedi "s|resValue \"string\", \"default_host_name\", '\"sandbox.tinode.co\"'|resValue \"string\", \"default_host_name\", '\"${SERVER_HOST}\"'|" app/build.gradle
sedi "s|resValue \"string\", \"default_host_name\", '\"api.tinode.co\"'|resValue \"string\", \"default_host_name\", '\"${SERVER_HOST}\"'|" app/build.gradle
ok "app/build.gradle — applicationId, default server host (debug + release)"

sedi "s|android:host=\"web.tinode.co\"|android:host=\"${SERVER_HOST}\"|" app/src/main/AndroidManifest.xml
ok "AndroidManifest.xml — deep-link host"

# ═════════════════════════════════ iOS ═════════════════════════════════════════
say "ios/"
cd "$ROOT/ios"

sedi "s|^HOST_NAME = api.tinode.co|HOST_NAME = ${SERVER_HOST}|" prod.xcconfig
sedi "s|^APP_NAME = Tinode|APP_NAME = ${APP_NAME}|" prod.xcconfig
# devel.xcconfig carries its own name ("Tinode (test)") so debug installs sit beside
# the release build on the same device.
sedi "s|^APP_NAME = Tinode (test)|APP_NAME = ${APP_NAME} (dev)|" devel.xcconfig
ok "prod.xcconfig + devel.xcconfig — server host, APP_NAME"

python3 - "$APP_NAME" <<'PY'
import re, sys
name = sys.argv[1]
p = 'Tinodios/Info.plist'
s = open(p).read()
s = re.sub(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)',
           lambda m: m.group(1) + name + m.group(2), s, count=1)
open(p, 'w').write(s)
PY
ok "Info.plist — CFBundleDisplayName"

# The Debug target config hardcodes APP_NAME, shadowing devel.xcconfig entirely.
sedi "s|APP_NAME = Tinodios;|APP_NAME = \"${APP_NAME} (dev)\";|" Tinodios.xcodeproj/project.pbxproj
ok "project.pbxproj — Debug APP_NAME override"

# Covers both co.tinode.tinodios and co.tinode.tinodios.TinodiosNSExtension.
# Only touches the app project; the SDK/DB framework projects keep their ids.
sedi "s|PRODUCT_BUNDLE_IDENTIFIER = co.tinode.tinodios|PRODUCT_BUNDLE_IDENTIFIER = ${IOS_BUNDLE_ID}|g" \
  Tinodios.xcodeproj/project.pbxproj
ok "project.pbxproj — bundle identifiers (app + notification extension)"

# Hardcoded wordmarks on the login / signup / reset-password screens and a nav title.
# These are baked into the storyboard, not the string catalogs — grep for "Tinode" in
# .strings files finds nothing.
sedi "s|text=\"Tinode\"|text=\"${APP_NAME}\"|g; s|title=\"Tinode\"|title=\"${APP_NAME}\"|g" \
  Tinodios/Base.lproj/Main.storyboard
ok "Main.storyboard — in-app wordmarks"

sedi "s|applinks:\*.tinode.co|applinks:*.${SERVER_HOST#chat.}|" Tinodios/Tinodios.entitlements
sedi "s|iCloud.co.tinode.tinodios|iCloud.${IOS_BUNDLE_ID}|g" Tinodios/Tinodios.entitlements
ok "Tinodios.entitlements — associated domains, iCloud containers"

for f in */*.lproj/Localizable.strings *.lproj/Localizable.strings; do
  [ -f "$f" ] || continue
  sedi "s|Check out Tinode Messenger: https://tinode.co/|Check out ${APP_NAME}: ${SITE_URL}|g" "$f"
  sedi "s|Check out Tinode Messenger|Check out ${APP_NAME}|g" "$f"
done
ok "Localizable.strings — invite text (all locales)"

# ═══════════════════════════════ SERVER ════════════════════════════════════════
say "server/"
cd "$ROOT/server/server"

for f in templ/email-validation-*.templ templ/email-password-reset-*.templ templ/sms-universal-*.templ; do
  [ -f "$f" ] || continue
  sedi "s|https://tinode.co/|${SITE_URL}|g" "$f"
  sedi "s|Tinode Team|${APP_NAME} Team|g" "$f"
  sedi "s|Tinode|${APP_NAME}|g" "$f"
done
ok "templ/ — validation + password-reset emails and SMS, all languages"

sedi "s|\"sender\": \"\\\\\"Tinode\\\\\" <noreply@example.com>\"|\"sender\": \"\\\\\"${APP_NAME}\\\\\" <noreply@${SERVER_HOST}>\"|" tinode.conf
sedi "s|\"sender\": \"Tinode\"|\"sender\": \"${APP_NAME}\"|" tinode.conf
ok "tinode.conf — email/SMS sender name"

# ═══════════════════════════════ SUMMARY ═══════════════════════════════════════
say "Done — text rebranding applied."
cd "$ROOT"
for d in server webapp android ios; do
  n=$(git -C "$d" diff --name-only | wc -l | tr -d ' ')
  printf '  %-8s %s file(s) changed\n' "$d" "$n"
done
cat <<EOF

Review with:   git -C webapp diff        (and server / android / ios)
Revert all:    for d in server webapp android ios; do git -C "\$d" checkout .; done

Still to do by hand — see REBRANDING.md:
  • Replace logo/icon files (webapp/img/, android mipmap-*/, iOS AppIcon.appiconset)
  • Generate your own API key:  cd server/keygen && go run main.go
    then paste it into webapp/src/config.js (API_KEY)
EOF
