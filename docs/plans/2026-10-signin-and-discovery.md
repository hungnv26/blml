# Sign in with Google/Apple + phonebook discovery

Decided with the owner, 2026-09-30.

## Why phonebook search finds almost nobody

- Address-book upload (`fnd` topic) matches only against **confirmed** `tel:` /
  `email:` tags. Of 17 active accounts, 2 have a confirmed phone and 0 an email:
  sign-up never asks for a phone, and email verification is off (no SMTP).
- iOS uploads numbers as stored (`0912 345 678` → `0912345678`), so local-format
  numbers never match `tel:+84…`. Android already normalises via the SIM country.

## Decisions

| Question | Answer |
|---|---|
| Invite code for Google/Apple/phone sign-in | **Not required** (basic sign-up keeps it) |
| Phone numbers | **Collected without SMS**, confirmed on entry; one account per number |
| Order | Server, iOS and Android together |
| Apple | Sign in with Apple is mandatory on iOS once Google is offered (4.8); not built on Android |

## Consequences we accept

- Open sign-up via Google/Apple ⇒ strangers can join. Guideline 1.2 then requires
  report + block (both exist), Terms of Use accepted at sign-up (new), and someone
  reading reports (admin console view, new).
- Unverified phones ⇒ anyone can claim a number first. Mitigation: a confirmed
  number belongs to one account (store already returns ErrDuplicate); admin can
  release a wrongly claimed number.
- The fixed validator test code `123456` (`debug_response`) is removed — it let
  anyone confirm any phone/email today.

## Work packages

Server (Go, `server/server`)
1. `auth/firebase`: verify Firebase ID tokens (firebase.google.com/go v3, same
   service-account file as FCM). Unique key = Firebase uid. No account → ErrNotFound
   (404) so clients create one. On create, verified email → `email:` tag.
2. `registration_code_exempt_schemes` config: skip the invite gate for `firebase`.
3. `acc_validation.tel.auto_confirm`: confirm phone credentials on entry, no SMS,
   tag `tel:+E164`; applies at sign-up and when added from Settings.
4. gen-config.sh: enable the above, drop `debug_response`.
5. Admin console: reports list (from the `sys` topic / report messages).

iOS (`ios/`)
6. FirebaseAuth + GoogleSignIn pods; Sign in with Apple (AuthenticationServices).
7. Login screen: Google + Apple buttons → Firebase ID token → `{login scheme:"firebase"}`;
   on 404 → name + optional phone + Terms → `{acc new scheme:"firebase"}`.
8. Phone field at sign-up and "Add phone number" in Settings without a code step.
9. ContactsSynchronizer: normalise numbers with PhoneNumberKit + device region.
10. Terms of Use checkbox at sign-up (both paths).

Android (`android/`)
11. Firebase Auth + Credential Manager (Sign in with Google) → same server flow.
12. Phone field at sign-up / Settings without a code step; Terms checkbox.

Web
13. hungngo.net/blml/terms — Terms of Use with the zero-tolerance clause.

## Owner prerequisites (one-time)

- Firebase console → Authentication → enable **Google** and **Apple** providers.
- Firebase → Android app → add release + debug **SHA-1/SHA-256** fingerprints.
- Re-download `GoogleService-Info.plist` and `google-services.json` afterwards
  (they gain the OAuth client IDs Google Sign-In needs).
- Blaze plan not needed (no SMS).
