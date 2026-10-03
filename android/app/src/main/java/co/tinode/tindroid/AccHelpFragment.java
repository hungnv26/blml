package co.tinode.tindroid;

import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.res.Resources;
import android.net.Uri;
import android.os.Bundle;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.TextUtils;
import android.text.style.ForegroundColorSpan;
import android.text.style.UnderlineSpan;
import android.util.Log;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import com.google.android.gms.oss.licenses.v2.OssLicensesMenuActivity;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;

import androidx.annotation.NonNull;
import androidx.annotation.StringRes;
import androidx.appcompat.app.ActionBar;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.Toolbar;
import androidx.fragment.app.Fragment;

/**
 * Fragment for editing current user details.
 */
public class AccHelpFragment extends Fragment {
    private static final String TAG = "AccHelpFragment";

    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, ViewGroup container,
                             Bundle savedInstanceState) {
        final AppCompatActivity activity = (AppCompatActivity) requireActivity();

        // Inflate the fragment layout
        View fragment = inflater.inflate(R.layout.fragment_acc_help, container, false);
        final ActionBar bar = activity.getSupportActionBar();
        if (bar != null) {
            bar.setDisplayHomeAsUpEnabled(true);
        }

        Toolbar toolbar = activity.findViewById(R.id.toolbar);
        toolbar.setTitle(R.string.help);
        toolbar.setNavigationOnClickListener(v -> activity.getSupportFragmentManager().popBackStack());

        BrandingConfig config = BrandingConfig.getConfig(activity);

        // Make policy links clickable.
        makeViewClickable(activity, fragment.findViewById(R.id.contactUs), R.string.contact_us,
                config != null && !TextUtils.isEmpty(config.contact_us_uri) ?
                        config.contact_us_uri : getString(R.string.contact_us_uri));
        // BLML's own legal pages always: a branding config fetched from upstream's
        // hosts.tinode.co must not redirect Terms/Privacy to someone else's documents.
        makeViewClickable(activity, fragment.findViewById(R.id.termsOfUse), R.string.terms_of_use,
                getString(R.string.terms_of_use_uri));
        makeViewClickable(activity, fragment.findViewById(R.id.privacyPolicy), R.string.privacy_policy,
                getString(R.string.privacy_policy_uri));

        fragment.findViewById(R.id.aboutTheApp).setOnClickListener(v ->
                ((ChatsActivity) activity).showFragment(ChatsActivity.FRAGMENT_ACC_ABOUT, null));

        // BLML's own licence first (the generated screen lists only the libraries),
        // with the library list one tap further.
        fragment.findViewById(R.id.ossLicenses).setOnClickListener(v ->
                new AlertDialog.Builder(activity)
                        .setTitle(R.string.licenses)
                        .setMessage(getString(R.string.license_notice) + "\n\n" + readApacheLicense())
                        .setPositiveButton(R.string.third_party_libraries, (dialog, which) -> {
                            OssLicensesMenuActivity.setActivityTitle(getString(R.string.third_party_libraries));
                            activity.startActivity(new Intent(activity, OssLicensesMenuActivity.class));
                        })
                        .setNegativeButton(android.R.string.cancel, null)
                        .show());

        return fragment;
    }

    private String readApacheLicense() {
        try (InputStream in = getResources().openRawResource(R.raw.apache_license);
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) > 0) {
                out.write(buf, 0, n);
            }
            return out.toString("UTF-8");
        } catch (IOException ex) {
            Log.w(TAG, "Failed to read the license text", ex);
            return "https://www.apache.org/licenses/LICENSE-2.0";
        }
    }

    private void makeViewClickable(AppCompatActivity activity, TextView link,
                                   @StringRes int string_id, String uriString) {
        final Uri uri = Uri.parse(uriString);
        if (uri == null) {
            return;
        }

        Resources res = getResources();
        SpannableStringBuilder text = new SpannableStringBuilder(res.getString(string_id));
        text.setSpan(new ForegroundColorSpan(res.getColor(R.color.colorAccent, activity.getTheme())),
                0, text.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        text.setSpan(new UnderlineSpan(), 0, text.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        link.setText(text);
        link.setOnClickListener(v -> {
            try {
                startActivity(new Intent(Intent.ACTION_VIEW, uri));
            } catch (ActivityNotFoundException ignored) {
                Log.w(TAG, "No application can open the URL");
            }
        });
    }
}
