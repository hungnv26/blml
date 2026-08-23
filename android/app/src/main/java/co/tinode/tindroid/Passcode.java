package co.tinode.tindroid;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.text.TextUtils;
import android.util.Log;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;

/**
 * A four-digit passcode that locks the app, stored per account.
 *
 * <p>Keyed by uid, which is what makes it per-user: two people sharing a device
 * each get their own code, and neither can open the other's account with it.
 * The record survives logout, so signing out and back in does not silently drop
 * the passcode.
 *
 * <p>Kept in step with the iOS Passcode enum.
 */
public class Passcode {
    private static final String TAG = "Passcode";

    /** Four digits, matching what people expect from a phone lock screen. */
    public static final int LENGTH = 4;

    private static final String PREFS = "passcode";

    /**
     * True while the app must be unlocked before it can be used: set when the
     * app goes to the background, and true at process start so a cold launch
     * is gated too. Cleared by a correct code, or by {@link #enforce} when the
     * account has no passcode to enforce.
     */
    private static boolean sLocked = true;

    /** True while the lock screen is on top, so the gate does not relaunch it. */
    private static boolean sShowing = false;

    private static SharedPreferences prefs(Context context) {
        return context.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static String key(String uid) {
        return "passcode." + uid;
    }

    /**
     * Stored as {@code <salt-hex>:<sha256-hex>}.
     *
     * <p>Hashing four digits is not much of a barrier on its own — the whole
     * space is ten thousand entries — but the alternative is writing the code
     * down in plain text, and the salt at least means a preferences dump cannot
     * be compared against precomputed digests, or against another account's
     * entry to see that two users picked the same code.
     */
    private static String digest(String code, byte[] salt) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            md.update(salt);
            md.update(code.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            for (byte b : md.digest()) {
                sb.append(String.format("%02x", b));
            }
            return sb.toString();
        } catch (Exception ex) {
            // SHA-256 is mandatory on every Android release; if it is somehow
            // missing, refusing to store anything beats storing plain digits.
            Log.e(TAG, "SHA-256 unavailable", ex);
            return null;
        }
    }

    private static String toHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }

    private static byte[] fromHex(String hex) {
        if (hex == null || hex.length() % 2 != 0) {
            return null;
        }
        byte[] out = new byte[hex.length() / 2];
        try {
            for (int i = 0; i < out.length; i++) {
                out[i] = (byte) Integer.parseInt(hex.substring(i * 2, i * 2 + 2), 16);
            }
        } catch (NumberFormatException ex) {
            return null;
        }
        return out;
    }

    /** True when this account has a passcode configured. */
    public static boolean isSet(Context context, String uid) {
        return !TextUtils.isEmpty(uid) && prefs(context).contains(key(uid));
    }

    /**
     * Saves a new passcode, replacing any existing one. Returns false when the
     * code is the wrong shape or hashing failed — callers must not report
     * success on a passcode that was never stored.
     */
    public static boolean set(Context context, String uid, String code) {
        if (TextUtils.isEmpty(uid) || !isWellFormed(code)) {
            return false;
        }
        byte[] salt = new byte[16];
        new SecureRandom().nextBytes(salt);
        String hash = digest(code, salt);
        if (hash == null) {
            return false;
        }
        return prefs(context).edit().putString(key(uid), toHex(salt) + ":" + hash).commit();
    }

    /**
     * Checks a code against the stored one. False when nothing is stored: an
     * account with no passcode cannot be unlocked by guessing.
     */
    public static boolean verify(Context context, String uid, String code) {
        if (TextUtils.isEmpty(uid)) {
            return false;
        }
        String record = prefs(context).getString(key(uid), null);
        if (record == null) {
            return false;
        }
        int sep = record.indexOf(':');
        if (sep <= 0) {
            return false;
        }
        byte[] salt = fromHex(record.substring(0, sep));
        if (salt == null) {
            return false;
        }
        String expected = record.substring(sep + 1);
        String actual = digest(code, salt);
        return actual != null && actual.equals(expected);
    }

    /** Removes the passcode for this account. */
    public static void clear(Context context, String uid) {
        if (TextUtils.isEmpty(uid)) {
            return;
        }
        prefs(context).edit().remove(key(uid)).apply();
        sLocked = false;
    }

    /** Exactly {@link #LENGTH} ASCII digits. */
    public static boolean isWellFormed(String code) {
        if (code == null || code.length() != LENGTH) {
            return false;
        }
        for (int i = 0; i < code.length(); i++) {
            if (!Character.isDigit(code.charAt(i))) {
                return false;
            }
        }
        return true;
    }

    /** Called when the app goes to the background. */
    public static void lock() {
        sLocked = true;
    }

    public static void unlock() {
        sLocked = false;
    }

    public static boolean isLocked() {
        return sLocked;
    }

    static void setShowing(boolean showing) {
        sShowing = showing;
    }

    /**
     * Puts the lock screen up when the signed-in account has a passcode and the
     * app is locked. The single entry point for the gate, called both when the
     * app returns to the foreground and once the chat list is up — on a cold
     * start the uid is not known yet when the process first starts, so the
     * foreground check alone would find nothing to lock.
     *
     * <p>Safe to call repeatedly: it clears the lock and returns when there is
     * no passcode to enforce.
     */
    public static void enforce(Context context) {
        if (!sLocked || sShowing) {
            return;
        }
        String uid = Cache.getTinode() != null ? Cache.getTinode().getMyId() : null;
        if (TextUtils.isEmpty(uid)) {
            // Not signed in yet. Stay locked: the check runs again once the
            // chat list appears.
            return;
        }
        if (!isSet(context, uid)) {
            sLocked = false;
            return;
        }
        Intent lock = PasscodeActivity.intent(context, PasscodeActivity.MODE_UNLOCK);
        lock.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        context.startActivity(lock);
    }
}
