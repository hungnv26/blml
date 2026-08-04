# BLML system setup

How the whole BLML stack fits together and how to run it — locally today, on a
VPS when you're ready. The local stack in `deploy/` is the same one you'll run
in production; only TLS and DNS are added on top.

## Architecture

```
                    ┌────────────────────────────────────────┐
   browsers ──────► │  blml server (Go, port 6060)           │
   Android app ───► │  • WebSocket + long-polling API        │      ┌──────────┐
   iOS app ───────► │  • serves the web app at /             │ ───► │ Postgres │
                    │  • serves uploads at /v0/file/s/       │      │ (pgdata) │
                    │  • email templates (rebranded)         │      └──────────┘
                    └───────────────┬────────────────────────┘
                                    │
                              uploads volume
                          (attachments > ~95 KB)
```

One Go binary does everything: API, static web app, file uploads. Postgres
holds accounts, messages, and file metadata; attachment bytes live in the
uploads volume. Nothing else is required for core chat.

## Local stack (running now)

```bash
cd deploy
set -a; source secrets.env; set +a
docker compose up -d --build
open http://localhost:6060
```

| Piece | What it is |
|---|---|
| `deploy/Dockerfile` | Two-stage build: compiles the **rebranded** server from `server/` source (upstream's image downloads a stock amd64 release binary — wrong branding, wrong arch for Apple Silicon), then packages it with the built web app and BLML email templates. |
| `deploy/docker-compose.yml` | `db` (postgres:16) → `blml-init` (one-shot schema create/upgrade) → `blml` (the server). |
| `deploy/secrets.env` | The four secrets. Gitignored. Generated with `openssl rand`. |
| `deploy/gen-config.sh` | Produces `blml.conf` from the rebranded `tinode.conf` template + secrets. Rerun after changing either. |
| `deploy/blml.conf` | The actual server config the container mounts. Gitignored (contains secrets). |

No sample data is loaded — the alice/bob/carol demo accounts with published
passwords are upstream's, and the image deliberately doesn't ship `data.json`.
Create accounts through the app's Sign Up screen.

### Secrets — what each one does

| Secret | Purpose | Rotation consequence |
|---|---|---|
| `API_KEY_SALT` | Validates the API key clients present | Must regenerate client API key + rebuild clients |
| `AUTH_TOKEN_KEY` | Signs session tokens | All users logged out (harmless) |
| `UID_ENCRYPTION_KEY` | Obfuscates user IDs | **NEVER rotate after go-live — corrupts all IDs** |
| `POSTGRES_PASSWORD` | Database password | Update secrets.env + rerun gen-config.sh + restart |

### The API key chain (easy to get wrong)

Server validates the client's API key against `api_key_salt`. We replaced the
default salt, so the default Tinode API key **stopped working**. The new key
was generated with the in-image keygen and baked into:

- `webapp/src/config.js` → `API_KEY` (webapp rebuilt with it)
- `android/.../co/tinode/tindroid/Cache.java` → `API_KEY`
- `ios/TinodiosDB/SharedUtils.swift` → `kApiKey`

All three must hold the *same* key. Android was missed for a while and kept the
stock Tinode key, so the Android app could not connect to BLML at all — the
WebSocket was rejected with `403 Forbidden` and the client surfaced it as the
misleading "disconnected (503)". If Android ever fails to log in while iOS and
web are fine, compare these three constants first.

If you ever regenerate the salt: `docker compose run --rm --entrypoint
/opt/blml/keygen blml -salt "$API_KEY_SALT"`, paste the new key into those
three files, rebuild all clients.

## Day-2 operations

**Backup — two things, not one** (DB has the references, volume has the bytes):

```bash
docker compose exec db pg_dump -U postgres tinode | gzip > backup-$(date +%F).sql.gz
docker run --rm -v blml_uploads:/u -v "$PWD":/out alpine tar czf /out/uploads-$(date +%F).tar.gz -C /u .
```

**Logs / status:**

```bash
docker compose logs -f blml
docker compose ps
```

**Update after changing server code, webapp, or email templates:**

```bash
cd webapp && rm -f umd/* && npm run build   # rm first: webpack leaves stale chunks behind
cd ../deploy && docker compose up -d --build
```

Two caching gotchas when shipping webapp updates, learned the hard way:
- Webpack does **not** delete old chunk files from `umd/` — a removed feature can
  survive in a stale chunk that still gets copied into the image. Always clear
  `umd/` before a rebuild.
- The server sends `Cache-Control: max-age=39600` (11 h) for static files
  (`"cache_control"` in blml.conf), and the webapp registers a service worker.
  Returning browsers can run the previous build for up to ~11 hours after a
  deploy. New visitors always get the fresh build. Lower `cache_control` if
  that window bothers you.

**Admin CLI** (create/manage users, topics): `server/tn-cli/` — Python,
`pip install tinode-grpc`, connects to gRPC port 16060.

## Going to production (when you have a VPS + domain)

1. VPS: 2 vCPU / 4 GB / 40 GB (Hetzner/DO, ~$10-20/mo). Install Docker.
2. Point `chat.blml.app` A-record at it.
3. Copy the repo (or just `deploy/` + built images) to the VPS. Copy
   `secrets.env` separately — it is not in git.
4. TLS: easiest is a Caddy container in front:
   `caddy reverse-proxy --from chat.blml.app --to blml:6060`
   (automatic Let's Encrypt; WebSockets proxied automatically). Alternatively
   enable the server's built-in ACME in blml.conf (`"tls"` section).
5. `docker compose up -d --build` — same stack, unchanged.
6. Mobile apps: rebuild release configs (already pointing at `chat.blml.app`),
   distribute via TestFlight / Play closed testing.
7. Push notifications: create a Firebase project for `app.blml.chat`, replace
   both placeholder config files (see BUILDING.md), and enable FCM in
   blml.conf's `"push"` section. Web push works via the same project
   (`webapp/firebase-init.js`).

### Not set up yet (deliberately)

- **Email verification** — needs SMTP credentials; `"email"` validator in
  blml.conf. For a 50-person group you can skip it entirely.
- **Voice/video calls** — needs `"webrtc"` enabled + ICE servers (coturn or
  Twilio's). The rebranded apps hide nothing; it just won't connect calls
  until ICE is configured.
- **Monitoring** — upstream ships an exporter (`server/monitoring/`) for
  Prometheus/InfluxDB if you ever want it.


## Email verification

Enabled: signing up now requires confirming an email before the account works.
The server replies `300 validate credentials`, sends a code, and the client shows
a "Confirm credentials" screen.

Settings live in `deploy/secrets.env` (gitignored) and are injected into
`blml.conf` by `gen-config.sh`:

```
EMAIL_VERIFICATION=true
SMTP_SERVER=mailpit     # local catcher; a real host in production
SMTP_PORT=1025
SMTP_LOGIN=
SMTP_PASSWORD=
SMTP_SENDER='"BLML" <noreply@blml.app>'
```

**Local development** uses the `mailpit` container in `docker-compose.yml` — a
fake SMTP server that captures every message. Open <http://localhost:8025> to
read verification emails without any real mail account.

**Production** — swap in a real provider and drop the mailpit service. Gmail
needs an App Password (not your login password):

```
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
SMTP_LOGIN=you@gmail.com
SMTP_PASSWORD=<16-char app password>
```

Then `./gen-config.sh && docker compose up -d --build`.

**To disable:** set `EMAIL_VERIFICATION=false` and regenerate.

### Why this matters beyond signup

Before this, the `credentials` table was completely empty, so **email search and
address-book contact sync silently returned nothing**. A verified account now
gets an `email:<address>` tag, which is what those features look up. Verified
end-to-end: signup gated → BLML-branded mail sent from `noreply@blml.app` (no
Tinode references) → code accepted → credential stored with `done = true`.

Existing accounts are unaffected; the check applies at signup.


## Finding people by username

Searching a bare username works: typing `alice` in Contacts finds the user whose
login is `alice`.

Upstream only matched the fully-namespaced tag (`basic:alice`), which nobody
would think to type, so username search silently returned nothing. `rewriteTag`
in `server/server/utils.go` now expands a bare token into an OR group
`["alice", "basic:alice"]` — the same shape it already used to let a bare email
match an `email:` tag. It widens the search; it never narrows it.

Verified A/B against the live server: with the change `thao` finds "Tho" and
`hungnv` finds "hung viet ngo"; without it both return nothing.

Note you never appear in your own search results — that is Tinode behaviour, not
a bug.

If you enable another auth scheme with `add_to_tags`, add its namespace beside
`basic:` in that function.

## Invite-only registration

The server is invite-only: creating an account requires a registration code.
Without one the server returns `403 permission denied` with
`params: {"what": "registration-code"}`.

- The code lives in `deploy/secrets.env` as `REGISTRATION_CODE` (gitignored).
- `gen-config.sh` injects it into `blml.conf` as `"registration_codes"`.
- Clients present it as a `code:<value>` tag at signup. Tags are carried by every
  Tinode SDK, so this needed no protocol or SDK change. The server strips the tag
  before saving, so codes never land on accounts or in discovery.
- On iOS the signup screen's **Invite code** field carries it (this reuses the
  old "Description" row — a per-user bio is useless for a family chat).

**To change the code:** edit `REGISTRATION_CODE` in `secrets.env`, then

```bash
cd deploy && ./gen-config.sh && set -a && source secrets.env && set +a && docker compose up -d --build
```

Existing accounts are unaffected — the code is only checked at signup.

**To reopen registration:** blank out `REGISTRATION_CODE` and regenerate. The
server logs which mode it is in at startup ("Registration is invite-only" vs
"Registration is OPEN").

**All three clients are wired.** Each signup form has an **Invite code** field
(reusing the old "Description" row, which a family chat has no use for):

| Client | File |
|---|---|
| iOS | `Tinodios/SignupViewController.swift` + storyboard placeholder |
| Web | `src/views/create-account-view.jsx` (passes tags as the 5th arg to `onCreateAccount`) |
| Android | `SignUpFragment.java` + `description_optional` string |

Verified against the running server: wrong code → `permission denied (403)`,
correct code → account created.

