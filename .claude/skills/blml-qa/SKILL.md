---
name: blml-qa
description: End-to-end QA of BLML (the Tinode fork in this repo) on a fresh LOCAL server — iOS simulator, Android emulator, the web app and the server protocol — finding bugs, illogical flows, and gaps against what WhatsApp/Telegram/Signal users expect. Report-only; the user decides what gets fixed. Use when asked to "test BLML", "QA the chat app", "test all functions", or before an App Store / APK release.
---

# BLML QA

Tests every user-facing function of BLML on all three clients plus the server,
against a **fresh local instance**, and reports findings. It never fixes app code
on its own (build-breakers that stop testing are the one exception: fix the
minimum, say so in the report).

## Ground rules

- **Local server only.** All testing runs against `localhost:6060` (Android
  emulator: `10.0.2.2:6060`, which is the Mac's loopback). Never sign in to or
  create accounts on chat.blml.app. `qa/blml_qa.py` refuses non-local hosts.
- **Test accounts only.** Logins/passwords are in `qa/test-accounts.env`
  (gitignored, generated). Read them from there; never print passwords in chat,
  reports, or commit messages.
- **Google / Apple sign-in are out of scope** for the local run (they need the
  Firebase project and real identities). Only check that the buttons behave
  sensibly when sign-in is not configured.
- **Report-only.** Findings go to `qa/runs/<date>/REPORT.md` (gitignored).

## 1. Fresh instance

```bash
cd deploy
docker compose --env-file secrets.env stop blml 2>/dev/null   # frees :6060
docker compose -p blml-qa --env-file secrets.env down -v       # wipe the previous QA run
docker compose -p blml-qa --env-file secrets.env up -d --build db blml-init blml
cd .. && python3 qa/blml_qa.py seed
```

`blml-qa` is a separate compose project: its own Postgres volume, so the main
local stack's data is untouched. The image bundles `webapp/umd`, so run
`npm run build` in `webapp/` first if web sources changed. If Colima is wedged
(`vz driver is running but host agent is not`): `colima stop -f && colima start`.

Accounts created by `seed`: `qa_ios`, `qa_android`, `qa_web` (one per client)
and `qa_peer`, `qa_peer2` (scripted counterparts). Phones are ACMA fiction
numbers +61 491 570 101…105, in that order.

## 2. Builds

| Client | Build | Install / open |
|---|---|---|
| iOS | `cd ios && LANG=en_US.UTF-8 xcodebuild -workspace Tinodios.xcworkspace -scheme Tinodios -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/qa-dd HOST_NAME=localhost:6060 USE_TLS=NO build` | iOS Simulator tool `launch` with `ios/build/qa-dd/Build/Products/Debug-iphonesimulator/Tinodios.app` (uninstall `app.blml.chat` first so the host re-seeds) |
| Android | `cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug` | AVD `blml-test`; `adb install -r app/build/outputs/apk/debug/app-debug.apk`. On an emulator the app defaults to `10.0.2.2:6060`, no TLS |
| Web | `cd webapp && npm run build`, then rebuild the image | built-in browser at `http://localhost:6060` |
| Server | `docker run --rm -v "$PWD/server":/src -w /src -v blml-gomod:/go/pkg/mod -v blml-gocache:/root/.cache/go-build golang:1.26-alpine go test ./server/...` | — |

SDK paths: `adb` and `emulator` live under `/opt/homebrew/share/android-commandlinetools/`.
Start the emulator with `emulator -avd blml-test -no-audio -no-snapshot-save &`.
Drive Android with `adb shell input tap|text|swipe|keyevent`, read screens with
`adb exec-out screencap -p > shot.png` and `adb shell uiautomator dump /sdcard/ui.xml && adb shell cat /sdcard/ui.xml`
(the XML gives exact bounds — prefer it over guessing coordinates).
`adb logcat -d | grep -iE 'AndroidRuntime|FATAL|tindroid'` after anything odd.

Build failures count as findings (they block a release).

Lessons from the 2026-10-02 run:
- **Uninstall before installing** on both simulator and emulator. An APK installed
  over an old copy kept `chat.blml.app` as its host (and a prefilled login) — testing
  from there would hit production.
- Start the emulator with `-gpu host -cores 4`; without GPU on a busy Mac it throws
  "not responding" dialogs that aren't app bugs.
- Claude Code's auto-mode safety check may refuse subagents reading
  `qa/test-accounts.env` / the invite code. If it does, don't work around it: ask the
  user to sign each client in once (or allow the read), then continue.
- The local config still uses the production FCM project and TURN host; pushes go
  only to the test devices, but say so in the report.
- Run all builds right after any automated fix pass — the OCR pass broke the iOS
  build twice.

## 3. The other person: `qa/blml_qa.py`

Chat bugs only show up between two people. The scripted peer plays the other side:

```bash
python3 qa/blml_qa.py send    qa_peer qa_ios "hi"            # p2p message
python3 qa/blml_qa.py reply   qa_peer qa_ios 3 "re: 3"
python3 qa/blml_qa.py edit    qa_peer qa_ios 4 "edited"
python3 qa/blml_qa.py delete  qa_peer qa_ios 4
python3 qa/blml_qa.py typing  qa_peer qa_ios
python3 qa/blml_qa.py read    qa_peer qa_ios                  # sends a read receipt
python3 qa/blml_qa.py history qa_peer qa_ios 20               # what the server actually holds
python3 qa/blml_qa.py listen  qa_peer 60                      # watch what arrives
python3 qa/blml_qa.py group   qa_peer "Group" qa_ios qa_android
python3 qa/blml_qa.py find    qa_peer "+61491570101"
python3 qa/blml_qa.py topics  qa_peer
```

Always verify a UI action against `history`/`topics` — "it looked sent" is not
"the server has it".

## 4. What to test (every client)

Mark each line PASS / FAIL / MISSING / N-A. Compare against what a WhatsApp,
Telegram or Signal user would expect; an expectation BLML does not meet is a
MISSING finding, not silently skipped.

**Account**: sign up (with and without invite code; wrong code), sign in, wrong
password message, sign out, sign back in, change name/avatar, add/change phone
(+duplicate number → clear error), change password, delete account (and what the
peer then sees), Google/Apple buttons when unconfigured.

**Finding people**: search by name, by phone (+ local format), by login; phonebook
match (iOS: add a contact with a peer's number via Contacts; Android: `adb` insert
or the Contacts app); invite link/QR; add by ID.

**1:1 chat**: send/receive text, emoji, long text, links; delivery + read
indicators both ways; typing indicator; reply/quote; edit (own message only,
indicator shown); delete for me / for everyone; forward; copy; message order under
fast sends; offline send then reconnect (kill server or network) — queued
messages, retry, no duplicates; unread badge counts and clearing; scroll-back
history; draft kept when leaving a chat.

**Media**: photo, video, file, voice note, location/contact if offered — send,
receive, preview, download, cancel upload, large file limit message.

**Groups**: create, name/avatar, add/remove member, roles/permissions, leave,
delete, member list, messages from several members, what a removed member can
still see.

**Safety (App Review 1.2)**: block a user (they can no longer message you; what
they see), unblock, report user/message/group → appears in the operator's `sys`
topic (`history qa_peer sys` won't work; check with the admin console or DB),
mute/archive chats, Terms link reachable.

**Calls** (if the client offers them): start/cancel/decline audio+video call to
another client; simulator/emulator limits are N-A, not FAIL.

**Settings & misc**: notifications toggles, passcode/app lock, theme/wallpaper,
language switch, About/Support/Privacy links (must not mention Tinode),
empty states, rotation/iPad width, dark mode, VoiceOver/TalkBack labels on main
buttons, app background → foreground keeps the session.

**Cross-client**: same account on two clients at once (sync of read state,
edits, deletes); messages between iOS ↔ Android ↔ web directly.

## 5. Server (protocol level)

Using `qa/blml_qa.py` and raw websocket frames: auth (invite code gating, firebase
scheme returns 401/404 sensibly when unconfigured), tel auto-confirm + duplicate
409, permissions (non-member can't read/post group; blocked user can't post p2p;
removed member loses access), edit/delete authorization (can't edit/delete
others' messages unless admin), uploads (size limit, auth required for download),
fnd search doesn't leak hidden fields, account deletion cleans up, rate/size
limits on huge messages, malformed frames don't crash the server (check
`docker compose -p blml-qa logs blml` for panics afterward).

## 6. Report

`qa/runs/<YYYY-MM-DD>/REPORT.md`, findings ranked most severe first:

```
### [SEV] Title            (SEV = Blocker | High | Medium | Low)
Platform: iOS | Android | Web | Server | All     Type: Bug | Illogical flow | Missing vs other apps | Build
Steps: 1… 2… 3…
Expected: …        Actual: …
Evidence: screenshot path / log lines / blml_qa.py output
Code pointer (if found): path:line
```

Then a coverage table (area × platform → PASS/FAIL/MISSING/N-A) so it's clear
what was and wasn't exercised. End with the top 5 to fix before the next release.
