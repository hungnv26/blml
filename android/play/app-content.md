# App content declarations

**Policy → App content.** One section per form, in the order the console shows
them.

## Privacy policy

`https://chat.blml.app/privacy`

## App access

Choose **All or some functionality is restricted** and add one set of
instructions:

- **Name:** Reviewer account
- **Username / password:** a dedicated review account on chat.blml.app. Do not
  reuse the Apple review account; create a second one (for example
  `googlereview`) so the two reviews cannot interfere. Keep the password out of
  this repository.
- **Any other information:**

```
Please sign in with the account above on the first screen (Login / Password,
then SIGN IN). Sign-up is open too (it asks for an email address and sends a
confirmation code), but the account above already has sample conversations.

The account already has a contact and a group chat so that messaging, photos,
voice notes, polls, blocking and reporting can be tried. Voice and video calls
need a second device signed in to another account.

Account deletion: Settings > Security > Delete account.
```

## Ads

**No**, the app does not contain ads.

## Content rating

Start the questionnaire with email `support@blml.app` and category
**All other app types** (if **Communication** or **Social** is offered, choose
that).

| Question | Answer |
|---|---|
| Violence, blood, fear | No |
| Sexuality, nudity | No |
| Profanity or crude humour | No |
| Controlled substances (drugs, alcohol, tobacco) | No |
| Gambling, simulated gambling | No |
| Do users interact or exchange content with each other? | **Yes** (text, photos, video, audio, calls) |
| Can users block other users, and report users and content? | **Yes** |
| Is user-to-user chat moderated? | Reports go to the server operator and are reviewed within 24 hours |
| Does the app share the user's precise location with other users? | No |
| Does the app allow purchases of digital goods? | No |
| Is the app a web browser or search engine? | No |
| Is the app mainly a news or educational product? | No |

Expect a rating around Teen / PEGI 12 with a "Users interact" notice. That is
normal for a chat app.

## Target audience and content

- **Target age:** tick **13–15, 16–17 and 18 and over**. Do not tick any group
  under 13: that brings in Google's Families policy, which a general chat app
  with user-generated content does not meet.
- **Could your store listing unintentionally appeal to children?** **Yes.**
  The icon is bright and cartoon-like. Answering Yes adds a "Not designed for
  children" label to the listing and avoids an argument with review.

The privacy policy currently says children may be members of a family group.
Before submitting, either reword that sentence to "members aged 13 and over", or
accept that it sits awkwardly next to this answer.

## Data safety

See [data-safety.md](data-safety.md).

## Advertising ID

**No.**

## Government apps, financial features, health

- Government app: **No**
- Financial features: **My app doesn't provide any financial features**
- Health: **My app does not have any health features**

## News app

**No.**

## Permission declarations

The console only asks about these if it finds them in the bundle.

**Full-screen intent (`USE_FULL_SCREEN_INTENT`)**

- Does your app need this permission as a core function? **Yes**
- Use case: **Making and receiving calls**
- Explanation:

```
BLML has voice and video calling. The full-screen intent is used only to show
the incoming call screen when someone calls the user and the phone is locked or
the app is in the background.
```

**Photo and video permissions:** not requested. The app uses the system photo
picker, so this form should not appear.

**Contacts (`READ_CONTACTS`, `WRITE_CONTACTS`):** no declaration form. The app
explains what it does with contacts before the system prompt, and works without
the permission.

**Foreground services:** the app declares no foreground service types, so no
declaration is needed.

## User-generated content

Play's policy for apps with user content asks for four things, all in place:

1. Users accept the Terms of Use before creating an account
   (`https://hungngo.net/blml/terms`).
2. The terms define objectionable content and forbid it.
3. Users can report users and groups, and block users, from inside the app.
4. Reports are acted on: content is removed and abusive accounts are deleted.
