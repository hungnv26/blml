# BLML — self-hosted chat

Working copy of the Tinode chat platform, cloned 2026-08-03, rebranded to **BLML** and
set up for self-hosting for a ~50 person group.

## Status

Rebranding is applied and both mobile apps compile.

| | Status |
|---|---|
| Name | `BLML` across web, Android, iOS, and server emails |
| Logo | `brand/source-artwork.png` → 31 icon files across the three clients |
| Brand colour | `#0e1b52` (sampled from the artwork) |
| Bundle id | `app.blml.chat` on both platforms |
| Android APK | ✅ `android/app/build/outputs/apk/debug/app-debug.apk` (102 MB) |
| iOS simulator build | ✅ `ios/build/Build/Products/Debug-iphonesimulator/Tinodios.app` (81 MB) |
| Verified | installed on an iPhone 17 Pro simulator — see `brand/verification-ios-home.png` |

See [BUILDING.md](BUILDING.md) for the toolchain, the local config files, and the
upstream bugs that had to be patched. [REDESIGN-PLAN.md](REDESIGN-PLAN.md) is the
WhatsApp-style interface plan for all three clients (iOS phase 1 shipped).

**Not yet done:** push notifications (placeholder Firebase config), a real Android
signing key, and an actual server at `chat.blml.app`.

## Layout

| Folder | Upstream | Version | License |
|---|---|---|---|
| `server/` | [tinode/chat](https://github.com/tinode/chat) | v0.25.3 | GPL 3.0 |
| `webapp/` | [tinode/webapp](https://github.com/tinode/webapp) | v0.25.3 | Apache 2.0 |
| `android/` | [tinode/tindroid](https://github.com/tinode/tindroid) | v0.25.5 | Apache 2.0 |
| `ios/` | [tinode/ios](https://github.com/tinode/ios) | v1.24.4 | Apache 2.0 |

Each is an untouched git clone with `origin` pointing at upstream, so `git pull` still
works and `git diff` always shows exactly what you changed.

Licensing for this use case: the three clients are Apache 2.0, so renaming, re-logoing,
and redistributing them is fine (keep the license files). The server is GPL 3.0, but
running a modified server for your own group is not distribution and triggers no
obligations.

## Rebranding

- **`REBRANDING.md`** — every file and line where the name or logo appears, per repo.
- **`rebrand.sh`** — applies all the text changes. The CONFIG block at the top holds the
  current BLML values; edit and re-run to change them (revert first, see below).
- **`brand/`** — source artwork plus `generate-icons.sh`, which produces and installs
  every icon size the three clients need from `icon.png`.

Because everything is git, any run is undoable:

```bash
for d in server webapp android ios; do git -C "$d" checkout .; done
```

## Suggested order

1. Edit CONFIG in `rebrand.sh`, run it, review with `git -C webapp diff`.
2. Put artwork in `brand/`, run `brand/generate-icons.sh`.
3. Generate your own API key (`server/keygen`) and put it in `webapp/src/config.js` —
   don't ship the demo key that's checked in.
4. Build and check the web app: `cd webapp && npm install && npm run build`.
5. Stand the server up with Docker (Postgres + `tinode/tinode-postgres`), serve your
   built web app from it, verify branding end to end.
6. Android and iOS last — those need store accounts, signing keys, and Firebase config
   for push.

## Things to remember when deploying

- Set a real database password; the upstream Docker examples use empty/default ones.
- Disable the sample/test data the server seeds on first run.
- TLS via the server's built-in Let's Encrypt (`TLS_DOMAIN_NAME`) or a reverse proxy.
- Push notifications need your own Firebase project, wired into both `tinode.conf` and
  the rebuilt mobile apps.
- Back up the database plus the media upload directory.
