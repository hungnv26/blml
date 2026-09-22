Reply to App Review — submission a2af553f (1.1.0), guidelines 5.1.1(iv) and 1.5
==============================================================================

Paste into "Reply to App Review" on the submission page, then Resubmit
with build 101 attached.

---

Hello,

Thank you for the review. Both points are addressed in build 101, which is
attached to this submission.

Guideline 5.1.1(iv) – Contacts permission
The message shown before the Contacts permission request no longer lets the
user delay that request. It now has a single button, "Continue", which always
proceeds to the iOS permission dialog. There is no "Not now" button and no way
to dismiss the message, so the decision is always made in the system dialog.

The message is there because the data leaves the device: it states that the
phone numbers and email addresses in Contacts are uploaded to the user's own
BLML server, that they are used only to find people the user already knows,
and that they are never shown to other users. It ends by saying that iOS will
now ask for access and that declining is fine.

If the user denies access, nothing is uploaded, the app does not ask again,
and the Contacts tab continues to work for search by user name. The search
field then reads "Search by user name" — it no longer asks for the permission
that was refused.

Guideline 1.5 – Support URL
The Support URL is now https://hungngo.net/blml/support. It is a support page
with an email address for questions and a link for bug reports, plus answers
to the questions users actually ask: how to get an invite code, how to sign
in, what the contacts upload does, the passcode, notifications, and how to
delete an account.

Kind regards,
Hung Ngo
