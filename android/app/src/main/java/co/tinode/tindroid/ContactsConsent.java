package co.tinode.tindroid;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;

import androidx.appcompat.app.AlertDialog;
import androidx.preference.PreferenceManager;

import co.tinode.tindroid.account.Utils;

/**
 * The user's answer to "may BLML upload your address book to the server?"
 *
 * <p>The system READ_CONTACTS permission is not that answer: its prompt is a
 * single sentence and cannot say what the server does with the data. Store
 * policy (Apple 5.1.2, and Play asks the same) requires that the app explain
 * the upload and get a yes <em>before</em> asking the system, so this dialog
 * runs first and {@code ContactsSyncAdapter} refuses to upload until it has
 * been accepted. Declining keeps the Contacts tab usable for search by
 * username; the offer is made again only when the user starts something that
 * needs contacts.
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

    /** True once the user has answered either way. */
    public static boolean isDecided(Context context) {
        return prefs(context).getString(KEY, null) != null;
    }

    public static void revoke(Context context) {
        prefs(context).edit().putString(KEY, DECLINED).apply();
    }

    public interface Callback {
        void onDecided(boolean accepted);
    }

    /**
     * Shows the consent dialog. {@code callback.onDecided(true)} fires only if
     * the user accepted; the caller then requests the system permission.
     */
    public static void offer(Activity activity, Callback callback) {
        String host = PreferenceManager.getDefaultSharedPreferences(activity)
                .getString(Utils.PREFS_HOST_NAME, TindroidApp.getDefaultHostName());
        new AlertDialog.Builder(activity)
                .setTitle(R.string.contacts_consent_title)
                .setMessage(activity.getString(R.string.contacts_consent_message, host))
                .setNegativeButton(R.string.contacts_consent_decline, (dialog, which) -> {
                    prefs(activity).edit().putString(KEY, DECLINED).apply();
                    callback.onDecided(false);
                })
                .setPositiveButton(R.string.contacts_consent_accept, (dialog, which) -> {
                    prefs(activity).edit().putString(KEY, GRANTED).apply();
                    callback.onDecided(true);
                })
                .setCancelable(false)
                .show();
    }
}
