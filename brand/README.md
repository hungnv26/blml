# Brand assets

Drop your source artwork in this folder, then run `./generate-icons.sh` to produce every
size the three clients need and copy them into place.

## What to provide

| File | Requirement |
|---|---|
| `icon.png` | **Required.** 1024×1024, square, no transparency at the edges if you want a clean iOS icon (iOS masks the corners itself — do not pre-round them). |
| `icon.svg` | Optional but recommended. Square viewBox, 512×512 nominal. Used directly as the web app splash logo, which stays crisp at any size. |
| `icon-foreground.png` | Optional, for the Android adaptive icon. 1024×1024 with the artwork confined to the middle ~66% (the "safe zone") — Android crops the outer edge into circles, squircles, and other shapes depending on the launcher. If missing, `icon.png` is used and may get cropped. |
| `badge.png` | Optional. Flat single-colour silhouette on transparent background, used for the web push notification badge. Falls back to a desaturated `icon.png`. |

## Generated outputs

**Web app** → `webapp/img/`

| File | Size |
|---|---|
| `logo.svg` | vector (copied from `icon.svg` if present) |
| `logo192.png` | 192×192 |
| `logo96.png` | 96×96 |
| `logo32x32.png` | 32×32 |
| `logo32x32a.png` | 32×32 (unread-state favicon) |
| `badge96.png` | 96×96 |
| `og-logo.jpeg` | 1200×630 social preview — **make this one by hand**, it's a wide banner not a square icon |

**Android** → `android/app/src/main/res/mipmap-*/`

| Density | `ic_launcher.png` | `ic_launcher_foreground.png` |
|---|---|---|
| mdpi | 48×48 | 108×108 |
| hdpi | 72×72 | 162×162 |
| xhdpi | 96×96 | 216×216 |
| xxhdpi | 144×144 | 324×324 |
| xxxhdpi | 192×192 | 432×432 |

Also set the adaptive-icon background colour: `launcherBackground` in
`android/app/src/main/res/values/colors.xml`.

**iOS** → `ios/Tinodios/Supporting Files/Assets.xcassets/AppIcon.appiconset/`

16 PNGs from 20×20 through 1024×1024. Xcode 14+ also accepts a single 1024×1024 icon —
if you go that route, open the asset catalog in Xcode, set the AppIcon's "Single Size"
option, drag `icon.png` in, and skip the generated set entirely.

## Notes

- Keep the artwork legible at 32×32. Most of where users see it is a browser tab.
- The web app's theme colour is `#3949AB` (`webapp/manifest.json`) and the Android
  adaptive-icon background is in `colors.xml` — update both to match your palette.
