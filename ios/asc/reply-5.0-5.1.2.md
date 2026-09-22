Reply to App Review — submission a2af553f (1.1.0), guidelines 5.0 and 5.1.2
========================================================================

Paste into "Reply to App Review" on the submission page, then Resubmit
with build 99 attached.

---

Hello,

Thank you for the review. Both points are addressed in build 99, which is
attached to this submission.

Guideline 5.0 – CallKit in China
China has been removed from the app's availability in App Store Connect
(Pricing and Availability → China mainland: not available). The app is not
distributed in China, so CallKit is never active there.

Guideline 5.1.2 – Contacts
The app can upload the phone numbers and email addresses from the user's
Contacts to the user's own BLML server, solely to find which of their
contacts already have an account on that server. In build 99 nothing is
uploaded until the user explicitly agrees:

1. Opening the Contacts tab shows an in-app sheet, "Find people you know",
   which states what is uploaded (phone numbers and email addresses from
   Contacts), where to (the user's BLML server, named in the sheet), what
   it is used for (matching only), that the data is never shown to other
   users or shared with anyone, and how to stop it (Settings › Privacy &
   Security › Contacts).
2. Only after the user taps "Upload contacts" does the app request the
   system Contacts permission, and only then does it read the address
   book.
3. "Not now" leaves the Contacts tab fully usable for search by user name;
   contacts stay on the device.

The NSContactsUsageDescription string now states the upload as well, in
every localization. The same description has been added to the App Review
Information notes.

BLML is a self-hosted messenger: the server the data goes to belongs to the
user's own group, not to a third party.

Kind regards,
Hung Ngo
