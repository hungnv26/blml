# BLML → WhatsApp-style interface: redesign plan, all clients

Goal: make BLML feel like WhatsApp on **iOS, Android, and web** — familiar to the
50-person group on day one. We match WhatsApp's visual language (colors, layout,
hierarchy); we never copy Meta's assets (doodle wallpaper, icons, fonts-as-shipped).

## Design language (shared tokens)

One palette, applied identically in all three clients:

| Token | Light | Dark | Used for |
|---|---|---|---|
| `accent` | `#00A884` | `#00A884` | buttons, links, active states, FAB |
| `bubble.outgoing` | `#DCF8C6` | `#005C4B` | **my** messages (green = mine, always) |
| `bubble.incoming` | `#FFFFFF` | `#202C33` | others' messages |
| `bubble.text` | `#111B21` | `#E9EDEF` | message text |
| `chat.canvas` | `#ECE5DD` | `#0B141A` | conversation background |
| `list.title` | large bold "Chats" | same | chat list header |
| `unread.badge` | `#25D366` pill | same | unread counts |

Typography: system fonts (SF on iOS, Roboto on Android, system stack on web) —
matches WhatsApp, zero licensing risk.

## Status: what's already shipped (iOS phase 1)

- ✅ Bubble inversion fixed (upstream had incoming=green): `ios/Tinodios/MessageViewController.swift` Constants
- ✅ Chat canvas beige/near-black; transparent collection view + cells (`MessageCell.swift`)
- ✅ "Chats" large title (`ChatListViewController.swift` — note: `navigationItem.title`, storyboard overrides `self.title`)
- ✅ Green send/voice control (`widgets/SendMessageBar.swift`)
- ✅ Login: "Welcome to BLML", green capsule Sign In, soft fields (`LoginViewController.swift` + storyboard outlet `blm-Si-gnB`)
- ✅ App-wide green tint (`AppDelegate.swift` window.tintColor)

Rollout: iPad has everything; both iPhones pending `ios/install-devices.sh` when reachable.

---

## Phase 1 — Parity: bring Android and web up to the iOS look ✅ DONE 2026-08-03
*Web verified live (bubble swap + green accents, dark mode). Android: colors.xml /
values-night swaps + accent `#00A884` + "Chats" title (`chats_title` string,
ChatsFragment), APK built — not visually verified (no Android device on hand;
changes are exact-value swaps in centralized resources).*

**Android** (`android/app/src/main/res/`):
- `values/colors.xml:51-56` — same inversion as iOS: `colorMessageBubbleMine` (mine,
  currently `#FAFAFA`) → `#DCF8C6`; `colorMessageBubbleOther` (currently green
  `#C5E1A5`) → white. Add night variants in `values-night/colors.xml`
  (`#005C4B` / `#202C33`), canvas colors, and swap the accent (`colorAccent`/
  `colorPrimary` family) to `#00A884`.
- Chat canvas: `layout/fragment_messages.xml` background + night variant.
- "Chats" toolbar title: `ChatsFragment`/`activity_chats` label (currently app name).
- Flashing/selected variants (`*Flashing`, `*FlashingLight`) need matching hues, not
  just the base colors — they're the long-press highlight.

**Web** (`webapp/css/base.css` — token system already exists, use it):
- `--clr-bubble-left-bg` (incoming, currently green) ↔ `--clr-bubble-right-bg`
  (outgoing, currently off-white): swap roles with the WhatsApp values via
  `light-dark()`.
- Accent: audit the `--clr-primary*` family → green.
- Wallpaper: engine already built (`--wallpaper-url`, `img/bkg/`) — pick or draw a
  neutral doodle tile (see Phase 4), or plain `#ECE5DD` to start.
- Rebuild + `docker compose up -d --build`; remember stale-chunk + 11 h cache
  gotchas (SETUP.md).

Definition of done: side-by-side screenshots of the same conversation on all three
clients look like siblings.

## Phase 2 — Chat list rows ✅ DONE 2026-08-03 (iOS + web; Android partial)
*iOS: WhatsApp timestamp (green when unread) + green badge pill — verified. Web:
row timestamp via `touched` prop + green badge — verified live. Android: badge
greened (`colorPillCounter`); row timestamp deferred until an Android device
exists to verify against.*

All three: avatar + **name (semibold)** + last-message preview (grey, one line,
sender prefix in groups) + right-aligned time + green unread badge pill.
- iOS: `widgets/ChatListViewCell.{swift,xib}` — add preview + time + badge labels.
- Android: chat list adapter row layout (`contact.xml` / `ChatsAdapter`).
- Web: `src/widgets/contact-badges` / chat-list CSS — mostly styling, data present.
- Swipe actions (archive/delete) already exist on iOS; verify parity on the others.

## Phase 3 — Navigation chrome ✅ DONE 2026-08-04 (iOS; Android deferred)
*iOS: UITabBarController root — **Chats / Contacts / Settings**, green tint; all
three tabs verified, and opening a conversation verified working with the tab
root in place. All five rootViewController-cast sites resolve via
`UiUtils.mainNavVC()` (the push-notification route would otherwise crash).*

*History worth keeping: on 2026-08-03 this was reverted after chat rows stopped
opening. That diagnosis was WRONG — the real cause was an empty `placeholderText`
crashing `PlaceholderTextView`. Re-enabled 2026-08-04 once that was fixed.*

*No Calls tab: the app has an active-call UI (CallViewController) but no
call-history screen. Building one means a new view over the webrtc call events
stored in-band with messages — real work, not wiring. Android bottom nav still
deferred (no device to verify structural changes). Web two-pane kept by design.*

- iOS: bottom `UITabBarController` — **Chats / Calls / Settings** (only tabs with
  real backends; no Updates/Communities). Reroute Profile button into Settings tab.
- Android: `BottomNavigationView` with the same three tabs.
- Web: keep the two-pane layout (WhatsApp Web does too) — polish: rounded search
  field, green compose FAB, header cleanup.
- Calls tab = call history from message events; Tinode records call events in-band,
  so this is a filtered view, not new infrastructure.

## Phase 4 — Chat polish ✅ PARTIAL 2026-08-03
*Self-made doodle wallpaper tiles (brand/chat-wallpaper-{light,dark}.png,
generated, deterministic) wired into iOS chat canvas with dark variant —
verified both modes. Dark-mode audit found+fixed stale bubble colors on
appearance switch (traitCollectionDidChange reload). Web keeps its built-in
wallpaper engine. Remaining: attachment sheet grid, Android wallpaper.*

- Self-made doodle wallpaper tile (commission or generate — **not** Meta's), wired
  to iOS canvas, Android background, web `--wallpaper-url`.
- Input bar: rounded pill field + circular green send button on all clients (iOS done).
- Attachment sheet: grid of colored circles (photos/camera/document) — iOS
  `SendMessageBar` plus Android equivalent; web has a simpler menu.
- Dark-mode audit pass on every screen (settings, profile, dialogs).

## Phase 5 — Rollout & upkeep

- iOS: `ios/install-devices.sh` (exists) — also the weekly re-signing pass.
- Android: `./gradlew :app:assembleDebug` + APK to the kid's/family phones.
- Web: rebuild + redeploy; server cache means returning browsers lag ≤ 11 h.
- Screenshot set per release in `brand/screenshots/` for before/after.

## Explicitly out of scope (no backend to power them)

Status/Updates, Communities, Channels-as-tab, Meta-AI search, stickers/reactions
(Tinode 0.25 has no reaction API). Revisit only if Tinode upstream grows the
features.

## Suggested order & rough effort

| Step | Effort | Value |
|---|---|---|
| Phase 1 Android + web parity | ~half a day | family sees one product everywhere |
| Phase 2 chat list rows | ~a day | biggest daily-use win after bubbles |
| Phase 4 polish (can precede 3) | ~half a day | cheap delight |
| Phase 3 tab bars | 1–2 days | full WhatsApp feel |

Every phase ships independently — stop anywhere and the app is still coherent.
