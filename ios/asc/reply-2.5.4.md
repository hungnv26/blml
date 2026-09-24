Reply to App Review — submission a2af553f (1.1.0), guideline 2.5.4
================================================================

Paste into "Reply to App Review" on the submission page, then Resubmit
with build 102 attached.

---

Hello,

Thank you for the review. Addressed in build 102, which is attached to this
submission.

Guideline 2.5.4 – VoIP background mode
The "voip" value has been removed from UIBackgroundModes, and the PushKit
registration code has been removed with it.

For context: BLML does have voice and video calls (in any one-to-one chat,
the phone and camera buttons in the top bar; incoming calls are presented
with CallKit). They are signalled to the callee with a standard push
notification rather than a VoIP push, so the VoIP background mode was never
required for them and it is now gone. The remaining background modes are
fetch, processing and remote-notification.

Kind regards,
Hung Ngo
