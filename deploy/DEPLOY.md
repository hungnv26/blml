# Deploying BLML to Vultr Singapore

Everything here is prepared and tested except the three steps that need your
account and your card. Those are marked **you**.

Target: Vultr Singapore (`sgp`), plan `vc2-2c-4gb` — 2 vCPU, 4 GB, 80 GB NVMe,
3 TB transfer, US$20/month. Measured 44 ms from Hanoi, ~100 ms from Sydney.

The `vc2-1c-2gb` plan at US$10 also works — the whole stack idles at 110 MB —
and Vultr resizes upward in place, so starting small costs nothing but a
reboot later.

---

## 1. Create the server — **you**

In the Vultr console:

- **Deploy New Server** → Cloud Compute → Regular (or High Performance)
- **Location:** Singapore
- **Image:** Ubuntu 24.04 LTS
- **Plan:** `vc2-2c-4gb`
- **SSH Key:** add your public key (`~/.ssh/id_ed25519.pub`). Do this now —
  the provisioning script only disables password login if a key is present.
- **Hostname:** `blml`
- Enable **Auto Backups** if you want Vultr's own snapshots (~US$4/month). This
  is separate from `backup.sh` and worth having: it survives losing the server.

Note the IP address.

## 2. Point the domain — **you**

Add an A record at your DNS provider:

```
chat.blml.app.   A   <vps-ip>
```

Do this before step 4. Caddy requests the certificate on first start, and
Let's Encrypt has to resolve the name to this server.

Check it has propagated:

```bash
dig +short chat.blml.app
```

## 3. Provision the box

```bash
ssh root@<vps-ip> 'bash -s' < deploy/provision-vps.sh
```

Installs Docker, opens 22/80/443 and the TURN ports, turns on unattended
security updates, disables SSH password login, and adds 2 GB of swap.
Re-runnable.

## 4. Fill in the production settings

In `deploy/secrets.env` (gitignored, never committed):

```
BLML_DOMAIN=chat.blml.app
ACME_EMAIL=<your email>          # Let's Encrypt expiry notices only
TURN_URL=turn:chat.blml.app:3478
TURN_USER=blmlturn
TURN_PASSWORD=<openssl rand -hex 16>
```

`API_KEY_SALT` and `UID_ENCRYPTION_KEY` stay exactly as they are. They derive
every user ID and the API key baked into the apps, so keeping them means the
existing accounts, the message history, and the builds already on everyone's
phones all keep working.

## 5. Deploy

With the local stack running (the data is read out of it):

```bash
./deploy/migrate-to-vps.sh root@<vps-ip>
```

This ships the code, the secrets, the database and the uploaded media, renders
`blml.conf` and `turnserver.conf` on the server, builds, and starts everything
behind TLS. It refuses to overwrite an existing populated database without
asking first.

Expect the first run to take a few minutes — it builds the Go server on the
VPS. Caddy may take another 30 seconds after that to obtain the certificate.

## 6. Turn on backups

```bash
ssh root@<vps-ip> 'cd /opt/blml/deploy && ./backup.sh --install'
```

Nightly at 03:15, keeping 14 days, verified after writing. These land on the
same disk as the data, so they cover "someone deleted the group" but not
"the server is gone" — that is what Vultr's snapshots are for. To add an
off-box copy, uncomment the `rclone` line at the bottom of `backup.sh`.

---

## Verifying

```bash
curl -sI https://chat.blml.app | head -1          # expect 200
python3 deploy/qa_suite.py                        # point HTTP/WS at the domain first
```

Admin dashboard — deliberately not exposed to the internet:

```bash
ssh -L 6061:localhost:6061 root@<vps-ip>
# then open http://localhost:6061/?token=<ADMIN_TOKEN>
```

Calls: place one between two phones on **different** networks (one on mobile
data). That is the case that only works once TURN is running, and the thing
worth checking after the first deploy.

## Day-to-day

```bash
ssh root@<vps-ip>
cd /opt/blml/deploy
C="docker compose -f docker-compose.yml -f docker-compose.prod.yml"

$C ps                    # what is running
$C logs -f blml          # server log
$C logs caddy | tail -30 # certificate problems show up here
$C restart blml          # after editing secrets.env + ./gen-config.sh
```

To ship a code change: commit, then re-run `migrate-to-vps.sh`. It rsyncs and
rebuilds. It will ask before replacing the database — answer no if you only
meant to update the code, or better, take a backup first.

## Still outstanding before the app stores

These are unrelated to the VPS and need you:

- **Firebase** — both configs still say `blml-placeholder`, so push
  notifications do not work. A real project is needed for iOS and Android.
- **Android release keystore** — the current one is dev-only and labelled
  "NOT for Play Store use".
- **Privacy policy URL** — both stores require one that is publicly hosted.
  Now that you have a domain, `https://chat.blml.app/privacy` is the obvious
  home for it.
- **`PrivacyInfo.xcprivacy`** — a legal declaration; read it before submitting.
