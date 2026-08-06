package co.tinode.tindroid;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.preference.PreferenceManager;
import android.text.Editable;
import android.text.TextUtils;
import android.util.Log;
import android.util.Patterns;
import android.widget.EditText;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AlertDialog;

import org.json.JSONObject;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.regex.Matcher;

import co.tinode.tindroid.account.Utils;
import co.tinode.tindroid.media.VxCard;
import co.tinode.tinodesdk.ComTopic;
import co.tinode.tinodesdk.model.Drafty;
import co.tinode.tinodesdk.model.Subscription;

/**
 * Compose-time extras shared by the message composer: @mentions, polls and
 * link titles. Mirrors the iOS implementations in
 * MessageViewController+SendMessageBarDelegate.swift — keep the two in step.
 */
public class ComposeExtras {
    private static final String TAG = "ComposeExtras";
    private static final int LINK_TITLE_TIMEOUT_MS = 3000;
    private static final int MAX_TITLE_LEN = 120;

    // ── @mentions ───────────────────────────────────────────────────────────

    /** Display name -> uid for mentions picked while composing the current message. */
    private final Map<String, String> mPendingMentions = new HashMap<>();

    public void clearMentions() {
        mPendingMentions.clear();
    }

    public boolean hasMentions() {
        return !mPendingMentions.isEmpty();
    }

    /**
     * Shows the member picker when "@" begins a word in a group chat.
     * Returns true if a picker was shown.
     */
    public boolean maybeShowMentionPicker(@NonNull Activity activity, @NonNull EditText input,
                                          @Nullable ComTopic<VxCard> topic) {
        if (topic == null || !topic.isGrpType()) {
            return false;
        }
        Editable text = input.getText();
        int caret = input.getSelectionStart();
        if (caret <= 0 || caret > text.length() || text.charAt(caret - 1) != '@') {
            return false;
        }
        // Mid-word "@" (an email address) must not trigger the picker.
        if (caret >= 2) {
            char prev = text.charAt(caret - 2);
            if (prev != ' ' && prev != '\n') {
                return false;
            }
        }

        Collection<Subscription<VxCard, co.tinode.tinodesdk.model.PrivateType>> subsRaw = topic.getSubscriptions();
        if (subsRaw == null || subsRaw.isEmpty()) {
            return false;
        }
        final String me = Cache.getTinode().getMyId();
        final List<String> names = new ArrayList<>();
        final List<String> uids = new ArrayList<>();
        for (Subscription<VxCard, co.tinode.tinodesdk.model.PrivateType> sub : subsRaw) {
            if (sub.user == null || sub.user.equals(me) || sub.pub == null
                    || TextUtils.isEmpty(sub.pub.fn)) {
                continue;
            }
            names.add(sub.pub.fn);
            uids.add(sub.user);
        }
        if (names.isEmpty()) {
            return false;
        }

        new AlertDialog.Builder(activity)
                .setTitle(R.string.mention_title)
                .setItems(names.toArray(new String[0]), (dialog, which) -> {
                    mPendingMentions.put(names.get(which), uids.get(which));
                    // The field already holds the "@"; complete the token.
                    input.getText().insert(input.getSelectionStart(), names.get(which) + " ");
                })
                .setNegativeButton(android.R.string.cancel, null)
                .show();
        return true;
    }

    /**
     * Converts "@Name" tokens for picked members into Drafty MN spans.
     * Operates on the parsed document's text, since Drafty.parse may shift
     * offsets while extracting markdown.
     */
    public Drafty attachMentions(Drafty d) {
        if (mPendingMentions.isEmpty() || d == null) {
            return d;
        }
        String txt = d.txt != null ? d.txt : "";
        for (Map.Entry<String, String> e : mPendingMentions.entrySet()) {
            String token = "@" + e.getKey();
            int from = 0;
            while (true) {
                int at = txt.indexOf(token, from);
                if (at < 0) {
                    break;
                }
                int after = at + token.length();
                boolean boundaryBefore = at == 0 || txt.charAt(at - 1) == ' ' || txt.charAt(at - 1) == '\n';
                boolean boundaryAfter = after == txt.length()
                        || !Character.isLetterOrDigit(txt.charAt(after));
                if (boundaryBefore && boundaryAfter) {
                    // Drafty.parse already turns "@Name" into an MN entity, but
                    // fills it with the literal text instead of a user id.
                    // Appending a second entity left two overlapping mentions on
                    // the same span, the first pointing at nobody — so replace
                    // the existing value when there is one.
                    if (!replaceMentionValue(d, at, token.length(), e.getValue())) {
                        d = appendEntity(d, "MN", singleton("val", e.getValue()), at, token.length());
                    }
                }
                from = after;
            }
        }
        return d;
    }

    // ── Polls ───────────────────────────────────────────────────────────────

    public interface PollListener {
        void onPoll(Drafty content);
    }

    /** Question + up to four options, sent as a form of pub buttons. */
    public static void showPollComposer(@NonNull Activity activity, @NonNull PollListener listener) {
        android.widget.LinearLayout box = new android.widget.LinearLayout(activity);
        box.setOrientation(android.widget.LinearLayout.VERTICAL);
        int pad = (int) (16 * activity.getResources().getDisplayMetrics().density);
        box.setPadding(pad, pad / 2, pad, 0);

        final EditText question = new EditText(activity);
        question.setHint(R.string.poll_question_hint);
        box.addView(question);
        final List<EditText> options = new ArrayList<>();
        for (int i = 1; i <= 4; i++) {
            EditText opt = new EditText(activity);
            opt.setHint(activity.getString(R.string.poll_option_hint, i));
            box.addView(opt);
            options.add(opt);
        }

        new AlertDialog.Builder(activity)
                .setTitle(R.string.poll_title)
                .setMessage(R.string.poll_explained)
                .setView(box)
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton(R.string.poll_send, (dialog, which) -> {
                    String q = question.getText().toString().trim();
                    List<String> opts = new ArrayList<>();
                    for (EditText opt : options) {
                        String v = opt.getText().toString().trim();
                        if (!v.isEmpty()) {
                            opts.add(v);
                        }
                    }
                    if (q.isEmpty() || opts.size() < 2) {
                        android.widget.Toast.makeText(activity, R.string.poll_needs_more,
                                android.widget.Toast.LENGTH_SHORT).show();
                        return;
                    }
                    listener.onPoll(makePoll(q, opts));
                })
                .show();
    }

    /** Bold question, then one pub button per option, wrapped in a form. */
    public static Drafty makePoll(String question, List<String> options) {
        StringBuilder sb = new StringBuilder("📊 ").append(question);
        List<int[]> spans = new ArrayList<>();
        for (String option : options) {
            // Drafty offsets count code POINTS, while String.length() counts
            // UTF-16 units — the chart emoji is two units but one point, so a
            // length-based offset lands one character late and slices the first
            // option into "C" + a button reading "o".
            int at = cp(sb) + 1;
            sb.append("\n").append(option);
            spans.add(new int[]{at, cpOf(option)});
        }
        Drafty d = Drafty.fromPlainText(sb.toString());
        // Bold the question, past the emoji + space (2 code points).
        d = appendStyle(d, "ST", 2, cpOf(question));
        for (int i = 0; i < spans.size(); i++) {
            Map<String, Object> data = new HashMap<>();
            data.put("act", "pub");
            data.put("name", "poll");
            data.put("val", options.get(i));
            d = appendEntity(d, "BN", data, spans.get(i)[0], spans.get(i)[1]);
        }
        return appendStyle(d, "FM", 0, cp(sb));
    }

    private static int cp(CharSequence s) {
        return Character.codePointCount(s, 0, s.length());
    }

    private static int cpOf(String s) {
        return s.codePointCount(0, s.length());
    }

    // ── Link titles ─────────────────────────────────────────────────────────

    public interface TitleListener {
        /** Called on a background thread with the title, or null. */
        void onTitle(@Nullable String title);
    }

    /** First http(s) URL in the text, or null. */
    @Nullable
    public static String firstLink(String text) {
        Matcher m = Patterns.WEB_URL.matcher(text);
        while (m.find()) {
            String candidate = m.group();
            String lower = candidate.toLowerCase();
            // Lowercased: soft keyboards autocapitalize a leading URL, and a
            // case-sensitive check would silently skip the lookup.
            if (lower.startsWith("http://") || lower.startsWith("https://")) {
                return candidate;
            }
        }
        return null;
    }

    /** Asks our own server for the page title. Never blocks longer than 3s. */
    public static void fetchLinkTitle(Context ctx, String link, TitleListener listener) {
        Executors.newSingleThreadExecutor().execute(() -> {
            HttpURLConnection conn = null;
            try {
                SharedPreferences pref = PreferenceManager.getDefaultSharedPreferences(ctx);
                String host = pref.getString(Utils.PREFS_HOST_NAME, TindroidApp.getDefaultHostName());
                boolean tls = pref.getBoolean(Utils.PREFS_USE_TLS, TindroidApp.getDefaultTLS());
                URL url = new URL((tls ? "https://" : "http://") + host
                        + "/v0/urlpreview?url=" + URLEncoder.encode(link, "UTF-8"));
                conn = (HttpURLConnection) url.openConnection();
                conn.setConnectTimeout(LINK_TITLE_TIMEOUT_MS);
                conn.setReadTimeout(LINK_TITLE_TIMEOUT_MS);
                conn.setRequestProperty("X-Tinode-APIKey", Cache.getApiKey());
                if (conn.getResponseCode() != 200) {
                    listener.onTitle(null);
                    return;
                }
                StringBuilder sb = new StringBuilder();
                try (InputStream is = conn.getInputStream()) {
                    byte[] buf = new byte[4096];
                    int n;
                    while ((n = is.read(buf)) > 0) {
                        sb.append(new String(buf, 0, n, "UTF-8"));
                    }
                }
                String title = new JSONObject(sb.toString()).optString("title", "");
                if (title.length() > MAX_TITLE_LEN) {
                    title = title.substring(0, MAX_TITLE_LEN);
                }
                listener.onTitle(title.isEmpty() ? null : title);
            } catch (Exception ex) {
                Log.i(TAG, "link title lookup failed: " + ex.getMessage());
                listener.onTitle(null);
            } finally {
                if (conn != null) {
                    conn.disconnect();
                }
            }
        });
    }

    // ── Drafty helpers ──────────────────────────────────────────────────────
    // Drafty's public API has no "add entity at offset"; the SDK's insertButton
    // is package-private and rejects pub buttons outright (it demands a URL for
    // every action type), so styles and entities are appended directly.

    /** Points an already-parsed MN entity at the real uid. */
    private static boolean replaceMentionValue(Drafty d, int at, int len, String uid) {
        if (d.fmt == null || d.ent == null) {
            return false;
        }
        for (Drafty.Style st : d.fmt) {
            if (st.at == at && st.len == len && st.key != null
                    && st.key >= 0 && st.key < d.ent.length
                    && "MN".equals(d.ent[st.key].tp)) {
                Map<String, Object> data = d.ent[st.key].data;
                if (data == null) {
                    data = new HashMap<>();
                    d.ent[st.key].data = data;
                }
                data.put("val", uid);
                return true;
            }
        }
        return false;
    }

    private static Map<String, Object> singleton(String k, Object v) {
        Map<String, Object> m = new HashMap<>();
        m.put(k, v);
        return m;
    }

    private static Drafty appendStyle(Drafty d, String tp, int at, int len) {
        Drafty.Style style = new Drafty.Style(tp, at, len);
        d.fmt = append(d.fmt, style);
        return d;
    }

    private static Drafty appendEntity(Drafty d, String tp, Map<String, Object> data, int at, int len) {
        Drafty.Entity ent = new Drafty.Entity(tp, data);
        int key = d.ent == null ? 0 : d.ent.length;
        d.ent = append(d.ent, ent);
        d.fmt = append(d.fmt, new Drafty.Style(at, len, key));
        return d;
    }

    private static Drafty.Style[] append(Drafty.Style[] arr, Drafty.Style s) {
        if (arr == null) {
            return new Drafty.Style[]{s};
        }
        Drafty.Style[] out = new Drafty.Style[arr.length + 1];
        System.arraycopy(arr, 0, out, 0, arr.length);
        out[arr.length] = s;
        return out;
    }

    private static Drafty.Entity[] append(Drafty.Entity[] arr, Drafty.Entity e) {
        if (arr == null) {
            return new Drafty.Entity[]{e};
        }
        Drafty.Entity[] out = new Drafty.Entity[arr.length + 1];
        System.arraycopy(arr, 0, out, 0, arr.length);
        out[arr.length] = e;
        return out;
    }
}
