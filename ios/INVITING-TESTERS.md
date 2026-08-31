# Inviting a TestFlight tester

You have someone's email and want them on the beta.

```sh
cd ios
./invite-tester.py someone@example.com
```

Apple emails the invitation. Then send them the invite code and the install
guide yourself — Apple's email mentions neither, and without the code they
cannot finish signing up.

## Check the group first

```sh
./invite-tester.py --list
```

**A tester only ever sees builds their group carries** — not the newest build,
their group's. Add someone to a group holding an old build and that is what
they install, with nothing on screen suggesting a newer one exists. This is
how a tester ends up *downgraded* after an upload. Groups behind the newest
build are flagged in the output.

`--group "Name"` picks another group; the default is `Family & Friends`.
Re-running for someone already in the group does nothing, so it is safe to
repeat.

## What to send them

Registration is invite-only, so the sign-up screen rejects them without a
code. Read the current one from the VPS:

```sh
ssh root@45.32.107.71 "grep '^REGISTRATION_CODE=' /opt/blml/deploy/secrets.env"
```

> Hi — I'd like you to try BLML, a private chat app I've built for family and
> friends.
>
> You'll get an email from **TestFlight** (Apple) inviting you to the beta.
> Accept that and it installs the app.
>
> Then open BLML and tap **Sign Up**. The non-obvious bit: creating an account
> needs an invite code.
>
> **Invite code:** `<code>`
>
> Step-by-step guide: `<link>`
>
> Two things that trip people up: leave the **phone number** blank, and **no
> confirmation email is sent** — the account works straight away.

## Confirming it worked

`--list` again. Their state moves `INVITED` → `ACCEPTED` → `INSTALLED`. Stuck
on `INVITED` for a day means the invitation email is what to chase, not the app.

## When it goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| No email from Apple | Spam, or a typo | `--list` shows the address actually added; Apple can resend |
| They installed an old version | Their group is behind | Add the newest build to that group |
| "Sign-up needs a valid invite code" | Code rotated | Re-read `REGISTRATION_CODE` |
| App stops opening after ~90 days | TestFlight builds expire | Expected — upload a new build |
| Stuck on Beta App Review | First build of a version, external group | Usually under a day |

## Limits

100 internal testers (App Store Connect users, no review). 10,000 external,
with the first build of each version passing Beta App Review. The public link
is capped separately — currently 100.

## Doing it by hand

App Store Connect → BLML → TestFlight → pick the group → **Testers +** → *Add
New Testers*. Same result; the script exists because it also compares the
group's build against the newest upload, which the web UI does not show.
