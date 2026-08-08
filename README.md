# BLML

A self-hosted, invite-only chat app for a private group — family, friends, a small
team. You run the server; the messages, photos and files stay on your own
machine. No third-party accounts, no ads, no analytics.

Native apps for iOS and Android, plus a web client, all talking to a single Go
server backed by PostgreSQL.

**Live instance: [chat.blml.app](https://chat.blml.app)** — invite-only, so
sign-up needs a code from the operator.

<p align="center">
  <img src="brand/screenshots/01-chats.png" width="230" alt="Chat list with search">
  <img src="brand/screenshots/02-chat.png" width="230" alt="Conversation">
  <img src="brand/screenshots/03-attachments.png" width="230" alt="Attachment sheet">
</p>
<p align="center">
  <img src="brand/screenshots/04-appearance.png" width="230" alt="Appearance settings">
  <img src="brand/screenshots/05-wallpapers.png" width="230" alt="Chat wallpapers">
</p>

## What it does

**Messaging** — one-to-one and group chats, delivery and read receipts, typing
indicators, replies, message editing and voice messages. Attachments up to
100 MB: photos, video, documents, audio.

**Invite-only by design.** Creating an account requires a registration code that
you control. Without it the server refuses signup outright, so a public address
does not mean a public server. *Invite a friend* shares the app, the server
address and the code in one message.

**Finding people** — search by username, scan a QR code in person, or match
against your phone's address book once members add a phone number.

**Group extras** — @mentions, pinned messages, polls (tap-to-vote), broadcast
channels where only admins post, and link titles resolved by your own server.

**Voice and video calls** over WebRTC, direct between devices.

**Appearance** — light/dark/system theme and a chat wallpaper gallery served
from your own server, so nothing external is needed to render it.

## Architecture

```
   iOS ─┐
Android ─┼──►  BLML server (Go, :6060)  ──►  PostgreSQL
    Web ─┘         ├── WebSocket + long-polling API
                   ├── serves the web client
                   └── serves uploads
                                │
                          uploads volume
```

One binary does the API, the web client and file uploads. Postgres holds
accounts, messages and file metadata; attachment bytes live on disk.

## Quick start

Requires Docker.

```bash
cd deploy
cp secrets.env.example secrets.env
```

Generate the four secrets and put them in `secrets.env`:

```bash
openssl rand -base64 32   # API_KEY_SALT
openssl rand -base64 32   # AUTH_TOKEN_KEY
openssl rand -base64 16   # UID_ENCRYPTION_KEY
openssl rand -base64 24   # POSTGRES_PASSWORD
```

Set `REGISTRATION_CODE` to whatever you will hand out, then:

```bash
./gen-config.sh
set -a; source secrets.env; set +a
docker compose up -d --build
```

Open <http://localhost:6060>. The first run creates the database schema. No
sample accounts are loaded — create yours through Sign Up.

> **The API key chain.** Changing `API_KEY_SALT` invalidates the key baked into
> the clients. Regenerate it with the in-image keygen and paste the result into
> `webapp/src/config.js`, `android/.../Cache.java` and
> `ios/TinodiosDB/SharedUtils.swift` — all three must match, or that client gets
> `403` on connect.

## Building the clients

| Client | Command |
|---|---|
| Web | `cd webapp && rm -f umd/* && npm install && npm run build` |
| Android | `cd android && ./gradlew :app:assembleDebug` |
| iOS | `cd ios && pod install && open Tinodios.xcworkspace` |

Point the apps at your server: iOS via `dev.xcconfig` / `prod.xcconfig`, Android
via `TindroidApp.getDefaultHostName()`, web via `webapp/src/config.js`.

`ios/install-devices.sh` builds and installs on every paired device at once.
With a free Apple developer account the signature expires after 7 days;
`ios/install-resign-agent.sh` installs a launchd job that reruns it every
Monday and Thursday, skipping devices that are offline.

## Going to production

Deployment is scripted end to end. On a fresh Ubuntu VPS:

```bash
ssh root@<vps-ip> 'bash -s' < deploy/provision-vps.sh   # Docker, firewall, SSH hardening
./deploy/migrate-to-vps.sh root@<vps-ip>                # code, secrets, database, media
ssh root@<vps-ip> 'cd /opt/blml/deploy && ./backup.sh --install'
```

That brings up the server behind Caddy, which obtains and renews its TLS
certificate automatically, plus coturn for the call relay. `secrets.env` is
never in git and is copied across explicitly.

Sizing is smaller than it looks: the whole stack idles around 110 MB of RAM, so
1 vCPU / 2 GB is comfortable for ~100 users. Disk is what grows, from shared
photos and video. Note that the Go build needs roughly 1.5 GB — it will be
OOM-killed on a 1 GB instance unless you build the image elsewhere.

The full runbook, including the DNS record, TURN, and what to verify
afterwards, is in [deploy/DEPLOY.md](deploy/DEPLOY.md). Phone and email
verification and push notifications are covered in [SETUP.md](SETUP.md).

## Repository layout

```
server/    Go server and database adapters
ios/       iOS client (Swift)
android/   Android client (Java)
webapp/    Web client (React) and static assets
deploy/    Docker Compose stack, provisioning and deploy scripts, backups,
           config generator, admin dashboard
brand/     Icons, logo, wallpapers and their generator scripts
```

Design notes are in [REDESIGN-PLAN.md](REDESIGN-PLAN.md), operational detail in
[SETUP.md](SETUP.md), build instructions in [BUILDING.md](BUILDING.md).

## Security notes

- `deploy/secrets.env`, the generated `blml.conf` and `turnserver.conf`, and
  signing keystores are gitignored. Keep them that way — the TURN config holds
  the relay password.
- `UID_ENCRYPTION_KEY` derives every user ID and `API_KEY_SALT` derives the key
  compiled into the clients. Never rotate either on a server with live users:
  it invalidates the accounts and every installed app.
- Phone verification ships in a no-SMS debug mode: the server accepts a fixed
  code, so a member could claim a number that is not theirs. Fine for a closed
  group, not for a public one — configure Twilio credentials for real
  verification.
- Registration is invite-only, but the code is a shared secret. Rotate it in
  `secrets.env` when someone should no longer be able to invite.

## License

The server is licensed under the **GNU GPL v3.0**; the iOS, Android and web
clients under the **Apache License 2.0**. Both licenses and the upstream
copyright notices are preserved in `server/LICENSE`, `ios/LICENSE`,
`android/LICENSE` and `webapp/LICENSE`.

The BLML name, logo and artwork under `brand/` are not covered by those
licenses.
