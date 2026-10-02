package co.tinode.tindroid;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.text.InputType;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.Toast;

import androidx.appcompat.app.AlertDialog;

import co.tinode.tindroid.media.VxCard;
import co.tinode.tinodesdk.MeTopic;
import co.tinode.tinodesdk.PromisedReply;
import co.tinode.tinodesdk.ServerResponseException;
import co.tinode.tinodesdk.model.Credential;
import co.tinode.tinodesdk.model.MsgSetMeta;
import co.tinode.tinodesdk.model.ServerMessage;

/**
 * Asks once, after sign-in, for a phone number on accounts that have none.
 *
 * <p>Phonebook search only finds accounts carrying a confirmed "tel:" tag, so
 * without numbers on accounts it finds no one. Recorded when shown, not when
 * answered: "Not now" means not now, and Settings stays available. Kept in step
 * with the iOS PhoneNumberPrompt.
 */
class PhoneNumberOffer {
    private static final String PREFS = "phone_number_offer";

    static void offerOnceIfMissing(final Activity activity) {
        if (Passcode.isLocked() || activity.isFinishing() || activity.isDestroyed()) {
            return;
        }
        final String uid = Cache.getTinode().getMyId();
        final MeTopic<VxCard> me = Cache.getTinode().getMeTopic();
        if (uid == null || me == null) {
            return;
        }
        Credential[] creds = me.getCreds();
        if (creds == null) {
            // Not loaded yet; the next resume will check again.
            return;
        }
        for (Credential c : creds) {
            if ("tel".equals(c.meth)) {
                return;
            }
        }
        SharedPreferences prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (prefs.getBoolean(uid, false)) {
            return;
        }
        prefs.edit().putBoolean(uid, true).apply();

        final EditText input = new EditText(activity);
        input.setInputType(InputType.TYPE_CLASS_PHONE);
        input.setHint(R.string.federated_phone_hint);
        FrameLayout box = new FrameLayout(activity);
        int pad = (int) (20 * activity.getResources().getDisplayMetrics().density);
        box.setPadding(pad, 0, pad, 0);
        box.addView(input);

        final AlertDialog dialog = new AlertDialog.Builder(activity)
                .setTitle(R.string.add_phone_title)
                .setMessage(R.string.add_phone_message)
                .setView(box)
                .setNegativeButton(R.string.not_now, null)
                .setPositiveButton(R.string.save, null)
                .show();
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            String e164 = FederatedSignIn.toE164(activity, input.getText().toString().trim());
            if (e164 == null) {
                // Shown on the field, so the dialog stays open and the input can be fixed.
                input.setError(activity.getString(R.string.phone_number_invalid));
                return;
            }
            dialog.dismiss();
            // noinspection unchecked
            me.setMeta(new MsgSetMeta.Builder().with(new Credential("tel", e164)).build())
                    .thenApply(new PromisedReply.SuccessListener() {
                        @Override
                        public PromisedReply onSuccess(Object result) {
                            activity.runOnUiThread(() -> Toast.makeText(activity,
                                    R.string.credential_saved, Toast.LENGTH_SHORT).show());
                            return null;
                        }
                    })
                    .thenCatch(new PromisedReply.FailureListener() {
                        @Override
                        public PromisedReply onFailure(Exception err) {
                            boolean taken = err instanceof ServerResponseException &&
                                    ((ServerResponseException) err).getCode() == 409;
                            activity.runOnUiThread(() -> Toast.makeText(activity,
                                    taken ? R.string.phone_number_taken : R.string.action_failed,
                                    Toast.LENGTH_SHORT).show());
                            return null;
                        }
                    });
        });
    }
}
