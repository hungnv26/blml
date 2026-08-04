# Rebranding map

Every place the name "Tinode" and its logo appear, per repo. Verified against the
checked-out versions (server v0.25.3, webapp v0.25.3, android v0.25.5, ios v1.24.4).

Run `./rebrand.sh` to apply all the *text* changes automatically. Logo/icon files must
be replaced by hand — see "Logo assets" at the bottom.

---

## 1. Web app (`webapp/`) — Apache 2.0

The web app is a React SPA served as static files by the Tinode server. This is the
lowest-effort client to rebrand and the one most of your 50 users will actually use.

### Name

| File | Line | Current value |
|---|---|---|
| `index.html` | 4 | `<title>Tinode</title>` |
| `index.html` | 7 | `<meta name="application-name" content="Tinode Web" />` |
| `index.html` | 8 | `<meta name="description" content="Tinode instant messenger in a browser" />` |
| `index.html` | 9, 13, 22 | `web.tinode.co` URLs (`application-url`, `og:url`, `canonical`) |
| `index.html` | 14, 16 | Open Graph title and description |
| `index.html` | 35 | Noscript text: "TinodeWeb does not work without JavaScript" |
| `manifest.json` | 2–4 | `name`, `short_name`, `description` (PWA install name) |
| `manifest.json` | 33–41 | `related_applications` — points at the *official* Play/App Store apps. **Delete this block and set `prefer_related_applications` to `false`**, otherwise browsers prompt your users to install the official Tinode app instead of yours. |
| `src/config.js` | 5 | `BASE_APP_NAME = 'TinodeWeb'` — used in the User-Agent and Firebase app name |
| `src/lib/utils.js` | 20 | `document.title = ... + 'Tinode'` — hardcoded, overrides `<title>` on unread count |
| `src/views/logo-view.jsx` | 17 | `<h2>Tinode Web</h2>` — the splash/login screen heading |

The i18n JSON files (`src/i18n/*.json`) contain **no** brand strings — nothing to change there.

### Server address

| File | Line | Current value |
|---|---|---|
| `src/config.js` | 12 | `KNOWN_HOSTS = {hosted: 'web.tinode.co', local: 'localhost:6060'}` |
| `src/config.js` | 15 | `DEFAULT_HOST = KNOWN_HOSTS.hosted` |
| `src/config.js` | 9 | `API_KEY` — **generate your own** with `server/keygen`, don't ship the demo key |

### Support / legal links (they point at tinode.co)

`src/config.js` lines 117, 120, 123: `LINK_CONTACT_US`, `LINK_PRIVACY_POLICY`,
`LINK_TERMS_OF_SERVICE`.

### Logo files (`webapp/img/`)

| File | Size | Referenced from |
|---|---|---|
| `logo.svg` | 512×512 | `src/views/logo-view.jsx:16` (splash screen), `manifest.json` |
| `logo192.png` | 192×192 | `index.html:21` (apple-touch-icon), `manifest.json` |
| `logo96.png` | 96×96 | `manifest.json`, `service-worker.js:107` (push notification icon) |
| `logo32x32.png` | 32×32 | `index.html:20` (favicon) |
| `logo32x32a.png` | 32×32 | alternate favicon (unread state) |
| `badge96.png` | 96×96 | notification badge (monochrome silhouette) |
| `og-logo.jpeg` | — | Open Graph social preview image |

---

## 2. Android (`android/`) — Apache 2.0

### Name

| File | Line | Current value | Note |
|---|---|---|---|
| `app/src/main/res/values/strings.xml` | 9 | `app_name` = `Tinode` | launcher label |
| " | 10 | `app_name_full` = `Tinode Chat` | |
| " | 12 | `tinode` = `Tinode` | used in UI chrome |
| " | 24 | `app_description` = `Tinode Chat` | |
| " | 11 | `copyright` = `© 2014 – 2025 Tinode` | |
| " | 30 | `tinode_logo` = `Tinode Logo` | accessibility label |
| " | 77, 78 | invite subject/body — mention Tinode + tinode.co | |
| " | 80, 82 | `profile_action`, `tinode_message` | contacts integration |
| " | 162, 231, 329 | download title, default contact name, video call title | |
| " | 4, 6, 7, 8 | `tinode_url`, `contact_us_uri`, `terms_of_use_uri`, `privacy_policy_uri` | |
| " | 3 | `asset_statements` → `web.tinode.co` assetlinks | change if you use app links |

Translated copies live in `values-de/`, `values-es/`, `values-fr/`, `values-hi/`,
`values-it/`, `values-ko/`, `values-pt/`, `values-ro/`, `values-ru/`. The
`translatable="false"` strings (including `app_name`) only exist in the default
`values/` file, so one edit covers all locales for the name itself.

### Identity and server

| File | Line | Current | Change to |
|---|---|---|---|
| `app/build.gradle` | 24 | `applicationId "co.tinode.tindroidx"` | your own reverse-domain id — **required**, this is what Play uses for uniqueness |
| `app/build.gradle` | 43 | debug `default_host_name` = `sandbox.tinode.co` | your server |
| `app/build.gradle` | 46 | release `default_host_name` = `api.tinode.co` | your server |
| `app/build.gradle` | 12 | `namespace 'co.tinode.tindroid'` | **leave alone** — this is the Java package; renaming means moving every source dir. `applicationId` is what matters for distribution. |
| `app/src/main/AndroidManifest.xml` | 125 | deep link host `web.tinode.co` | your domain |

Emulator host is `10.0.2.2:6060` (`strings.xml:5`) — that's the host loopback from an
Android emulator, leave it.

### Icons (`app/src/main/res/`)

Adaptive icon: `mipmap-anydpi/ic_launcher.xml` = background color
(`@color/launcherBackground` in `values/colors.xml`) + foreground
(`mipmap/ic_launcher_foreground`).

Replace `ic_launcher.png` and `ic_launcher_foreground.png` at each density:

| Directory | ic_launcher.png |
|---|---|
| `mipmap-mdpi/` | 48×48 |
| `mipmap-hdpi/` | 72×72 |
| `mipmap-xhdpi/` | 96×96 |
| `mipmap-xxhdpi/` | 144×144 |
| `mipmap-xxxhdpi/` | 192×192 |

The `_foreground` variants should be 108×108 dp at each density with the artwork inside
the middle 72×72 dp safe zone. Easiest path: Android Studio → right-click `res` →
*New → Image Asset*, which generates every density from one source SVG/PNG.

### Build note

If you build from a downloaded archive rather than a git clone, the gradle
`gitVersionCode()` / `gitVersionName()` helpers fail — replace them with static values.
We cloned via git, so this does not apply here.

---

## 3. iOS (`ios/`) — Apache 2.0

iOS is the tidiest of the three: name and server live in xcconfig files.

| File | Line | Current | Note |
|---|---|---|---|
| `prod.xcconfig` | 9 | `HOST_NAME = api.tinode.co` | your server |
| `prod.xcconfig` | 11 | `USE_TLS = YES` | keep YES for production |
| `prod.xcconfig` | 14 | `APP_NAME = Tinode` | feeds `CFBundleName` via `$(APP_NAME)` |
| `devel.xcconfig` | 14 | `APP_NAME = Tinode (test)` | **easy to miss** — Debug builds use this file, not `prod.xcconfig`. Leaving it means debug installs still say "Tinode". |
| `devel.xcconfig` | 9, 11 | `HOST_NAME = 127.0.0.1:6060`, `USE_TLS = NO` | local dev, fine as-is |
| `Tinodios/Info.plist` | — | `CFBundleDisplayName` = `Tinode` | the name under the home-screen icon |
| `Tinodios.xcodeproj/project.pbxproj` | 1349 | `APP_NAME = Tinodios;` in the **Debug** config | **shadows `devel.xcconfig` entirely** — a target-level build setting beats the xcconfig it inherits from, so debug builds ignore the xcconfig value and `CFBundleName` comes out as "Tinodios" |
| `Tinodios.xcodeproj/project.pbxproj` | 1379, 1405 | `PRODUCT_BUNDLE_IDENTIFIER = co.tinode.tinodios` | your own — **required** for App Store |
| " | 1433, 1460 | `co.tinode.tinodios.TinodiosNSExtension` | notification extension |
| `en.lproj/Localizable.strings` | 60, 63 | "Check out Tinode Messenger" invite text | plus `es/ru/uk/zh-Hans/zh-Hant.lproj` |
| `Tinodios/Base.lproj/Main.storyboard` | 1049, 1861, 1899, 2213, 2332 | `text="Tinode"` / `title="Tinode"` | **the wordmark users actually see** — login, signup, reset-password screens and a nav title. Hardcoded in the storyboard, so grepping the `.strings` catalogs finds nothing. |
| `Tinodios/Tinodios.entitlements` | 9 | `applinks:*.tinode.co` | universal-link domain |
| `Tinodios/Tinodios.entitlements` | 13, 21 | `iCloud.co.tinode.tinodios` | must match an iCloud container you create in the Apple Developer portal |

Leave `TinodeSDK.xcodeproj` and `TinodiosDB.xcodeproj` bundle ids alone — they are
internal frameworks, not distributed products.

### Icons

`Tinodios/Supporting Files/Assets.xcassets/AppIcon.appiconset/` — 16 PNGs from 20×20 up
to 1024×1024. Replace the whole set; the simplest route is dragging a single 1024×1024
PNG into the AppIcon slot in Xcode 14+ (single-size app icons are supported) and deleting
the rest.

`Tinodios/Supporting Files/Assets.xcassets/logo-ios.imageset/` — **a second, separate
logo** at 288/576/864 px (1x/2x/3x). This is the one shown on the login, signup and
reset-password screens and on the launch screen. Replacing only AppIcon leaves the old
Tinode logo staring at every user the moment they open the app — the home-screen icon
looks right and the first screen inside does not.

---

## 4. Server (`server/`) — GPL 3.0

Running a modified server for your own group triggers no GPL distribution obligations.
The server has almost no user-visible branding, with one exception that matters:

### Email and SMS templates — `server/server/templ/`

`email-validation-*.templ`, `email-password-reset-*.templ`, `sms-universal-*.templ`
(one set per language: en, es, fr, pt, ru, uk, vi, zh, zh-TW …).

The English validation email says "someone used your email to register at **Tinode**",
signs off "**Tinode Team**", and links to `https://tinode.co/`. **If you enable email
verification, your users will see this** — rebrand at minimum
`email-validation-en.templ` and `email-password-reset-en.templ`.

### Config — `server/server/tinode.conf`

| Line | Setting |
|---|---|
| 411 | `"sender": "\"Tinode\" <noreply@example.com>"` — the From: on outgoing email |
| 475 | SMS `"sender": "Tinode"` |
| 400, 466 | host URL used to build links inside emails |
| 269 / 297 / 330 / 349 | database name `tinode` (cosmetic, safe to leave) |

Database name, table names, and Go package paths are internal — do not rename them.

---

## 5. What you cannot rename

- The `tinode` **wire protocol** identifiers and the SDK class names (`Tinode.…` in JS,
  `TinodeSDK` in Swift, `co.tinode.tinodesdk` in Java). These are library internals;
  users never see them and renaming breaks compilation.
- The Android `namespace` / Java package tree (see above) — technically possible, not
  worth it.

---

## Logo assets

Put your source artwork in `brand/` (see `brand/README.md` for the full size list).
You need, at minimum, one **square SVG or 1024×1024 PNG** of the icon; everything else
can be generated from it:

- Web: `sips` / ImageMagick, or any favicon generator
- Android: Android Studio *Image Asset* wizard
- iOS: drop the 1024×1024 into Xcode's AppIcon slot

---

## Order of work

1. `./rebrand.sh` — applies every text change above.
2. Drop new icons into `brand/`, generate per-platform sizes, replace the files listed.
3. Build and run the web app first (fastest feedback loop):
   `cd webapp && npm install && npm run build`
4. Point the server at your built web app, verify the browser tab, favicon, splash
   screen, and PWA install name.
5. Android and iOS only when you're happy with the branding — those require store
   accounts and Firebase config.
