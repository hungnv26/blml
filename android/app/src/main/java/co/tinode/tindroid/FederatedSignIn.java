package co.tinode.tindroid;

import android.annotation.SuppressLint;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.CancellationSignal;
import android.text.InputType;
import android.text.TextUtils;
import android.util.Log;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AlertDialog;
import androidx.core.content.ContextCompat;
import androidx.credentials.ClearCredentialStateRequest;
import androidx.credentials.CredentialManager;
import androidx.credentials.CredentialManagerCallback;
import androidx.credentials.CustomCredential;
import androidx.credentials.GetCredentialRequest;
import androidx.credentials.GetCredentialResponse;
import androidx.credentials.exceptions.ClearCredentialException;
import androidx.credentials.exceptions.GetCredentialCancellationException;
import androidx.credentials.exceptions.GetCredentialException;
import androidx.preference.PreferenceManager;

import com.google.android.libraries.identity.googleid.GetGoogleIdOption;
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseUser;
import com.google.firebase.auth.GoogleAuthProvider;
import com.google.i18n.phonenumbers.NumberParseException;
import com.google.i18n.phonenumbers.PhoneNumberUtil;
import com.google.i18n.phonenumbers.Phonenumber;

import java.util.Locale;

import co.tinode.tindroid.account.Utils;
import co.tinode.tindroid.media.VxCard;
import co.tinode.tinodesdk.PromisedReply;
import co.tinode.tinodesdk.ServerResponseException;
import co.tinode.tinodesdk.Tinode;
import co.tinode.tinodesdk.model.AuthScheme;
import co.tinode.tinodesdk.model.Credential;
import co.tinode.tinodesdk.model.MetaSetDesc;
import co.tinode.tinodesdk.model.ServerMessage;

/**
 * Sign in with Google.
 *
 * <p>Credential Manager signs the person in to Google, Firebase Auth turns that
 * into a Firebase ID token, and the token is the secret for the server's
 * "firebase" auth scheme. The server verifies it and either signs the person in
 * or answers 404 — no account yet — in which case we ask for a display name and
 * an optional phone number, show the Terms, and create one.
 *
 * <p>Sign in with Apple is iOS-only: Apple's rule requiring it (4.8) applies to
 * iOS apps. Kept in step with the iOS FederatedSignIn class.
 */
class FederatedSignIn {
    private static final String TAG = "FederatedSignIn";
    static final Uri TERMS_URL = Uri.parse("https://hungngo.net/blml/terms");

    private final LoginActivity mActivity;
    private final Button mButton;

    FederatedSignIn(LoginActivity activity, Button button) {
        mActivity = activity;
        mButton = button;
    }

    /**
     * The Web OAuth client ID that google-services.json provides once Google
     * sign-in is enabled in the Firebase console; 0/empty until then, and the
     * Google button stays hidden.
     */
    @SuppressLint("DiscouragedApi")
    static String webClientId(Context context) {
        int id = context.getResources().getIdentifier("default_web_client_id", "string", context.getPackageName());
        return id == 0 ? null : context.getString(id);
    }

    static boolean isGoogleAvailable(Context context) {
        return !TextUtils.isEmpty(webClientId(context));
    }

    void signInWithGoogle() {
        String clientId = webClientId(mActivity);
        if (TextUtils.isEmpty(clientId)) {
            return;
        }
        mButton.setEnabled(false);
        GetGoogleIdOption option = new GetGoogleIdOption.Builder()
                .setFilterByAuthorizedAccounts(false)
                .setServerClientId(clientId)
                .build();
        GetCredentialRequest request = new GetCredentialRequest.Builder().addCredentialOption(option).build();
        CredentialManager.create(mActivity).getCredentialAsync(mActivity, request, new CancellationSignal(),
                ContextCompat.getMainExecutor(mActivity),
                new CredentialManagerCallback<>() {
                    @Override
                    public void onResult(GetCredentialResponse response) {
                        androidx.credentials.Credential cred = response.getCredential();
                        if (cred instanceof CustomCredential &&
                                GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL.equals(cred.getType())) {
                            GoogleIdTokenCredential google = GoogleIdTokenCredential.createFrom(cred.getData());
                            firebaseSignIn(google.getIdToken(), google.getDisplayName());
                        } else {
                            fail(null);
                        }
                    }

                    @Override
                    public void onError(@NonNull GetCredentialException e) {
                        if (e instanceof GetCredentialCancellationException) {
                            // Closing the Google sheet is not an error worth a toast.
                            mButton.setEnabled(true);
                        } else {
                            fail(e);
                        }
                    }
                });
    }

    private void firebaseSignIn(String googleIdToken, String suggestedName) {
        FirebaseAuth.getInstance()
                .signInWithCredential(GoogleAuthProvider.getCredential(googleIdToken, null))
                .addOnSuccessListener(result -> {
                    FirebaseUser user = result.getUser();
                    if (user == null) {
                        fail(null);
                        return;
                    }
                    user.getIdToken(false)
                            .addOnSuccessListener(t -> serverLogin(t.getToken(),
                                    suggestedName != null ? suggestedName : user.getDisplayName()))
                            .addOnFailureListener(this::fail);
                })
                .addOnFailureListener(this::fail);
    }

    private void serverLogin(final String idToken, final String suggestedName) {
        final SharedPreferences pref = PreferenceManager.getDefaultSharedPreferences(mActivity);
        @SuppressLint("UnsafeOptInUsageError")
        final String hostName = pref.getString(Utils.PREFS_HOST_NAME, TindroidApp.getDefaultHostName());
        @SuppressLint("UnsafeOptInUsageError")
        final boolean tls = pref.getBoolean(Utils.PREFS_USE_TLS, TindroidApp.getDefaultTLS());
        final Tinode tinode = Cache.getTinode();
        tinode.connect(hostName, tls, false)
                .thenApply(new PromisedReply.SuccessListener<>() {
                    @Override
                    public PromisedReply<ServerMessage> onSuccess(ServerMessage ignored) {
                        return tinode.loginFirebase(idToken);
                    }
                })
                .thenApply(new PromisedReply.SuccessListener<>() {
                    @Override
                    public PromisedReply<ServerMessage> onSuccess(ServerMessage msg) {
                        signedIn(idToken);
                        return null;
                    }
                })
                .thenCatch(new PromisedReply.FailureListener<>() {
                    @Override
                    public PromisedReply<ServerMessage> onFailure(Exception err) {
                        if (err instanceof ServerResponseException &&
                                ((ServerResponseException) err).getCode() == 404) {
                            // Verified identity, no account yet: offer to create one.
                            mActivity.runOnUiThread(() -> completeSignUp(idToken, suggestedName, null));
                        } else {
                            fail(err);
                        }
                        return null;
                    }
                });
    }

    private void signedIn(String idToken) {
        final Tinode tinode = Cache.getTinode();
        UiUtils.updateAndroidAccount(mActivity, tinode.getMyId(),
                new AuthScheme(AuthScheme.LOGIN_FIREBASE, AuthScheme.encodeFirebaseToken(idToken)).toString(),
                tinode.getAuthToken(), tinode.getAuthTokenExpiration());
        tinode.setAutoLoginToken(tinode.getAuthToken());
        UiUtils.onLoginSuccess(mActivity, mButton, tinode.getMyId());
    }

    /**
     * Name (prefilled from Google), optional phone number, and the Terms, which
     * must be accepted before an account is created (Apple guideline 1.2; sign-up
     * through Google is open, with no invite code).
     */
    private void completeSignUp(final String idToken, final String suggestedName, final String phone) {
        if (mActivity.isFinishing() || mActivity.isDestroyed()) {
            return;
        }
        mButton.setEnabled(true);

        final LinearLayout form = new LinearLayout(mActivity);
        form.setOrientation(LinearLayout.VERTICAL);
        int pad = (int) (20 * mActivity.getResources().getDisplayMetrics().density);
        form.setPadding(pad, pad / 2, pad, 0);
        final EditText nameInput = new EditText(mActivity);
        nameInput.setHint(R.string.federated_name_hint);
        nameInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PERSON_NAME |
                InputType.TYPE_TEXT_FLAG_CAP_WORDS);
        nameInput.setText(suggestedName);
        final EditText phoneInput = new EditText(mActivity);
        phoneInput.setHint(R.string.federated_phone_hint);
        phoneInput.setInputType(InputType.TYPE_CLASS_PHONE);
        phoneInput.setText(phone);
        form.addView(nameInput);
        form.addView(phoneInput);

        final AlertDialog dialog = new AlertDialog.Builder(mActivity)
                .setTitle(R.string.federated_create_title)
                .setMessage(R.string.federated_create_message)
                .setView(form)
                .setNeutralButton(R.string.read_terms, null)
                .setNegativeButton(android.R.string.cancel, (d, w) -> signOut(mActivity))
                .setPositiveButton(R.string.agree_and_create, null)
                .setCancelable(false)
                .create();
        dialog.setOnShowListener(d -> {
            // Neutral opens the Terms without closing the form.
            dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener(v ->
                    mActivity.startActivity(new Intent(Intent.ACTION_VIEW, TERMS_URL)));
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
                String name = nameInput.getText().toString().trim();
                if (name.isEmpty()) {
                    nameInput.setError(mActivity.getString(R.string.full_name_required));
                    return;
                }
                Credential[] creds = null;
                String rawPhone = phoneInput.getText().toString().trim();
                if (!rawPhone.isEmpty()) {
                    String e164 = toE164(rawPhone);
                    if (e164 == null) {
                        phoneInput.setError(mActivity.getString(R.string.phone_number_required));
                        return;
                    }
                    creds = new Credential[]{new Credential("tel", e164)};
                }
                dialog.dismiss();
                createAccount(idToken, name, creds);
            });
        });
        dialog.show();
    }

    private void createAccount(final String idToken, final String name, final Credential[] creds) {
        mButton.setEnabled(false);
        MetaSetDesc<VxCard, String> desc = new MetaSetDesc<>(new VxCard(name), null);
        Cache.getTinode().createAccountFirebase(idToken, true, desc, creds)
                .thenApply(new PromisedReply.SuccessListener<>() {
                    @Override
                    public PromisedReply<ServerMessage> onSuccess(ServerMessage msg) {
                        signedIn(idToken);
                        return null;
                    }
                })
                .thenCatch(new PromisedReply.FailureListener<>() {
                    @Override
                    public PromisedReply<ServerMessage> onFailure(Exception err) {
                        if (err instanceof ServerResponseException &&
                                ((ServerResponseException) err).getCode() == 409) {
                            mActivity.runOnUiThread(() -> {
                                mButton.setEnabled(true);
                                Toast.makeText(mActivity, R.string.phone_number_taken, Toast.LENGTH_LONG).show();
                            });
                        } else {
                            fail(err);
                        }
                        return null;
                    }
                });
    }

    /** Numbers typed without a country code are read in the device's region. */
    static String toE164(String raw) {
        PhoneNumberUtil util = PhoneNumberUtil.getInstance();
        try {
            Phonenumber.PhoneNumber number = util.parse(raw, Locale.getDefault().getCountry());
            if (!util.isValidNumber(number)) {
                return null;
            }
            return util.format(number, PhoneNumberUtil.PhoneNumberFormat.E164);
        } catch (NumberParseException e) {
            return null;
        }
    }

    /** Signs out of Firebase and forgets the Google choice on this device. */
    static void signOut(Context context) {
        FirebaseAuth.getInstance().signOut();
        CredentialManager.create(context).clearCredentialStateAsync(new ClearCredentialStateRequest(),
                new CancellationSignal(), ContextCompat.getMainExecutor(context),
                new CredentialManagerCallback<>() {
                    @Override
                    public void onResult(Void unused) {
                    }

                    @Override
                    public void onError(@NonNull ClearCredentialException e) {
                        Log.w(TAG, "Failed to clear credential state", e);
                    }
                });
    }

    /** Removes the Firebase user when the BLML account is deleted. */
    static void deleteFirebaseUser() {
        FirebaseUser user = FirebaseAuth.getInstance().getCurrentUser();
        if (user != null) {
            user.delete().addOnFailureListener(e -> Log.w(TAG, "Failed to delete Firebase user", e));
        }
    }

    private void fail(Exception err) {
        Log.w(TAG, "Sign-in failed", err);
        signOut(mActivity);
        mActivity.runOnUiThread(() -> {
            mButton.setEnabled(true);
            Toast.makeText(mActivity, R.string.federated_sign_in_failed, Toast.LENGTH_SHORT).show();
        });
    }
}
