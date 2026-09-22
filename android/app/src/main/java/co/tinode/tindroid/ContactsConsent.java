package co.tinode.tindroid;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;

import androidx.appcompat.app.AlertDialog;
import androidx.preference.PreferenceManager;

import co.tinode.tindroid.account.Utils;

/**
 * Explains the contacts upload, immediately before the system prompt.
 *
 * <p>Two review rules meet here and only one shape satisfies both. Apple
 * 5.1.2 (and Play asks the same) wants the upload explained and agreed to
 * before it happens — the system prompt is a single sentence and cannot say
 * what the server does with the data. Apple 5.1.1(iv) forbids letting that
 * explanation <em>delay</em> the system prompt: a pre-prompt with a "Not now"
 * button was rejected, because the decision belongs to the system dialog.
 * So this dialog has one button, which always continues to the system
 * prompt; denying there leaves the Contacts tab usable for search by user
 * name.
 *
 * <p>Kept in step with the iOS ContactsConsent enum.
 */
public class ContactsConsent {
    private static final String KEY = "contacts_upload_consent";
    private static final String GRANTED = "granted";
    private static final String DECLINED = "declined";

    private static SharedPreferences prefs(Context context) {
        return context.getApplicationContext().getSharedPreferences("contacts_consent", Context.MODE_PRIVATE);
    }

    public static boolean isGranted(Context context) {
        return GRANTED.equals(prefs(context).getString(KEY, null));
    }

    public static void revoke(Context context) {
        prefs(context).edit().putString(KEY, DECLINED).apply();
    }

    public interface Callback {
        void onDecided(boolean accepted);
    }

    /** Shows the explanation, then continues to the system permission request. */
    public static void offer(Activity activity, Callback callback) {
        String host = PreferenceManager.getDefaultSharedPreferences(activity)
                .getString(Utils.PREFS_HOST_NAME, TindroidApp.getDefaultHostName());
        new AlertDialog.Builder(activity)
                .setTitle(R.string.contacts_consent_title)
                .setMessage(activity.getString(R.string.contacts_consent_message, host))
                // One button, and it always continues to the system prompt:
                // see the note above. The place to say no is the OS dialog.
                .setPositiveButton(R.string.contacts_consent_continue, (dialog, which) -> {
                    prefs(activity).edit().putString(KEY, GRANTED).apply();
                    callback.onDecided(true);
                })
                .setCancelable(false)
                .show();
    }
}
