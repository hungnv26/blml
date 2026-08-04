package co.tinode.tindroid;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.text.InputType;
import android.text.TextUtils;
import android.widget.EditText;

import androidx.appcompat.app.AlertDialog;
import androidx.preference.PreferenceManager;

import co.tinode.tindroid.account.Utils;

/**
 * Builds and shares the "Invite a friend" message.
 * <p>
 * BLML is invite-only, so an invitation is useless without three things: the
 * app, the server address, and the registration code. A bare "install BLML"
 * leaves the recipient stuck at a 403 on the signup screen.
 * <p>
 * Mirrors ios/Tinodios/InviteHelper.swift — keep the two in step.
 */
public class InviteHelper {
    // The invite code this account signed up with. Nobody remembers a code they
    // typed once at signup, so the app remembers it for them.
    private static final String PREF_INVITE_CODE = "pref_invite_code";

    private static SharedPreferences prefs(Context context) {
        return PreferenceManager.getDefaultSharedPreferences(context);
    }

    public static String getInviteCode(Context context) {
        String code = prefs(context).getString(PREF_INVITE_CODE, null);
        return TextUtils.isEmpty(code) ? null : code;
    }

    public static void setInviteCode(Context context, String code) {
        if (TextUtils.isEmpty(code)) {
            return;
        }
        prefs(context).edit().putString(PREF_INVITE_CODE, code.trim()).apply();
    }

    public static boolean hasInviteCode(Context context) {
        return getInviteCode(context) != null;
    }

    /** The invite text. The code line is omitted when unknown rather than left blank. */
    public static String inviteText(Context context) {
        SharedPreferences pref = prefs(context);
        String host = pref.getString(Utils.PREFS_HOST_NAME, TindroidApp.getDefaultHostName());
        boolean tls = pref.getBoolean(Utils.PREFS_USE_TLS, TindroidApp.getDefaultTLS());

        StringBuilder sb = new StringBuilder();
        sb.append(context.getString(R.string.invite_message_intro)).append("\n\n");
        sb.append("1. ").append(context.getString(R.string.invite_message_install)).append("\n");
        sb.append("2. ").append(context.getString(R.string.invite_message_server,
                (tls ? "https://" : "http://") + host)).append("\n");

        String code = getInviteCode(context);
        if (code != null) {
            sb.append("3. ").append(context.getString(R.string.invite_message_code, code));
        } else {
            // Better to say a code is needed than to let them hit a 403 and
            // assume the server is broken.
            sb.append("3. ").append(context.getString(R.string.invite_message_no_code));
        }
        return sb.toString();
    }

    public static void share(Context context) {
        Intent intent = new Intent(Intent.ACTION_SEND);
        intent.setType("text/plain");
        intent.putExtra(Intent.EXTRA_TEXT, inviteText(context));
        context.startActivity(Intent.createChooser(intent, context.getString(R.string.invite_share_via)));
    }

    /**
     * Collects the invite code when the app never saw it — an account created on
     * another device, or before the code was stored.
     */
    public static void promptForCode(Context context, Runnable onSaved) {
        final EditText input = new EditText(context);
        input.setInputType(InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS);
        input.setHint(R.string.invite_code_title);
        input.setText(getInviteCode(context));

        new AlertDialog.Builder(context)
                .setTitle(R.string.invite_code_title)
                .setMessage(R.string.invite_code_explained)
                .setView(input)
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton(R.string.action_save, (dialog, which) -> {
                    setInviteCode(context, input.getText().toString());
                    if (onSaved != null) {
                        onSaved.run();
                    }
                })
                .show();
    }
}
