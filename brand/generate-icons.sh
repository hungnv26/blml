#!/usr/bin/env bash
#
# Generates every icon size the three Tinode clients need from brand/icon.png
# (and optionally icon.svg / icon-foreground.png / badge.png) and copies them
# into the right places.
#
# Uses macOS's built-in `sips`. On Linux, install ImageMagick and the script
# falls back to `convert`.
#
# Usage:  ./generate-icons.sh          apply
#         ./generate-icons.sh --check  just report what's missing
#
set -euo pipefail
cd "$(dirname "$0")"
BRAND="$PWD"
ROOT="$(dirname "$PWD")"

CHECK_ONLY=false
[ "${1:-}" = "--check" ] && CHECK_ONLY=true

# ── resize backend ─────────────────────────────────────────────────────────────
if command -v sips >/dev/null 2>&1; then
  resize() { sips -z "$2" "$2" "$1" --out "$3" >/dev/null; }
elif command -v magick >/dev/null 2>&1; then
  resize() { magick "$1" -resize "$2x$2" "$3"; }
elif command -v convert >/dev/null 2>&1; then
  resize() { convert "$1" -resize "$2x$2" "$3"; }
else
  echo "Need sips (macOS) or ImageMagick. Install with: brew install imagemagick" >&2
  exit 1
fi

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()  { printf '  ✓ %s\n' "$*"; }
warn(){ printf '  ! %s\n' "$*"; }

# ── inputs ─────────────────────────────────────────────────────────────────────
SRC="$BRAND/icon.png"
SVG="$BRAND/icon.svg"
FG="$BRAND/icon-foreground.png"
BADGE="$BRAND/badge.png"

if [ ! -f "$SRC" ]; then
  echo "Missing $SRC — see brand/README.md for what to provide." >&2
  exit 1
fi
[ -f "$SVG" ]   || warn "no icon.svg — web splash logo will keep the Tinode vector"
[ -f "$FG" ]    && FG_SRC="$FG" || { FG_SRC="$SRC"; warn "no icon-foreground.png — using icon.png (may be cropped by Android launchers)"; }
[ -f "$BADGE" ] && BADGE_SRC="$BADGE" || { BADGE_SRC="$SRC"; warn "no badge.png — using icon.png for the push badge"; }

if $CHECK_ONLY; then
  say "Check only — nothing written."
  exit 0
fi

# ── web app ────────────────────────────────────────────────────────────────────
say "webapp/img/"
W="$ROOT/webapp/img"
resize "$SRC" 192 "$W/logo192.png";   ok "logo192.png"
resize "$SRC"  96 "$W/logo96.png";    ok "logo96.png"
resize "$SRC"  32 "$W/logo32x32.png"; ok "logo32x32.png"
resize "$SRC"  32 "$W/logo32x32a.png";ok "logo32x32a.png"
resize "$BADGE_SRC" 96 "$W/badge96.png"; ok "badge96.png"
if [ -f "$SVG" ]; then cp "$SVG" "$W/logo.svg"; ok "logo.svg"; fi
warn "og-logo.jpeg (1200×630 social banner) still needs to be made by hand"

# ── android ────────────────────────────────────────────────────────────────────
say "android/app/src/main/res/mipmap-*/"
A="$ROOT/android/app/src/main/res"
set -- "mdpi 48 108" "hdpi 72 162" "xhdpi 96 216" "xxhdpi 144 324" "xxxhdpi 192 432"
for entry in "$@"; do
  read -r d launcher foreground <<<"$entry"
  resize "$SRC"    "$launcher"   "$A/mipmap-$d/ic_launcher.png"
  resize "$FG_SRC" "$foreground" "$A/mipmap-$d/ic_launcher_foreground.png"
  ok "mipmap-$d — ${launcher}px launcher, ${foreground}px foreground"
done

# ── ios ────────────────────────────────────────────────────────────────────────
say "ios/…/AppIcon.appiconset/"
I="$ROOT/ios/Tinodios/Supporting Files/Assets.xcassets/AppIcon.appiconset"
gen() { resize "$SRC" "$1" "$I/$2"; }
gen 1024 ios-logo-1024-1024.png
gen   20 ios-logo-1024-20.png
gen   40 ios-logo-1024-20@2x.png
gen   60 ios-logo-1024-20@3x.png
gen   29 ios-logo-1024-29.png
gen   58 ios-logo-1024-29@2x.png
gen   87 ios-logo-1024-29@3x.png
gen   40 ios-logo-1024-40.png
gen   80 ios-logo-1024-40@2x.png
gen  120 ios-logo-1024-40@3x.png
gen  120 ios-logo-1024-60@2x.png
gen  180 ios-logo-1024-60@3x.png
gen   76 ios-logo-1024-76.png
gen  152 ios-logo-1024-76@2x.png
gen  167 ios-logo-1024-83.5@2x.png
ok "16 app icon sizes"

# The in-app logo on the login, signup, reset-password and launch screens. Separate
# asset from AppIcon — miss it and the app still shows the Tinode logo at runtime.
# Prefer the background-free mark here: on the dark welcome screen the full
# icon card reads as a pasted square. Falls back to icon.png if absent.
LOGO_SRC="$BRAND/logo-transparent.png"; [ -f "$LOGO_SRC" ] || LOGO_SRC="$SRC"
L="$ROOT/ios/Tinodios/Supporting Files/Assets.xcassets/logo-ios.imageset"
resize "$LOGO_SRC" 288 "$L/logo-ios.png"
resize "$LOGO_SRC" 576 "$L/logo-ios@2x.png"
resize "$LOGO_SRC" 864 "$L/logo-ios@3x.png"
ok "logo-ios.imageset — in-app + launch screen logo (transparent)"

say "Done."
cat <<EOF

Review with:   git -C webapp status && git -C android status && git -C ios status
Revert icons:  for d in webapp android ios; do git -C "\$d" checkout .; done

Don't forget the colours that sit behind the icons:
  • webapp/manifest.json      → "theme_color" (currently #3949AB)
  • android .../values/colors.xml → launcherBackground
EOF
