package co.tinode.tindroid;

import android.content.Intent;
import android.os.Bundle;
import android.text.TextUtils;
import android.view.View;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import java.util.Collection;
import java.util.HashSet;
import java.util.Set;

import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.AppCompatImageView;

import co.tinode.tindroid.media.VxCard;
import co.tinode.tinodesdk.ComTopic;
import co.tinode.tinodesdk.FndTopic;
import co.tinode.tinodesdk.PromisedReply;
import co.tinode.tinodesdk.Tinode;
import co.tinode.tinodesdk.Topic;
import co.tinode.tinodesdk.model.MetaSetDesc;
import co.tinode.tinodesdk.model.MsgGetMeta;
import co.tinode.tinodesdk.model.MsgSetMeta;
import co.tinode.tinodesdk.model.PrivateType;
import co.tinode.tinodesdk.model.ServerMessage;
import co.tinode.tinodesdk.model.Subscription;

/**
 * Zalo-style "Add friend" screen, mirroring iOS: your own QR card, add by
 * phone number, add by email, scan a QR code, and people you may know —
 * members of your group chats you have no direct chat with yet.
 */
public class AddFriendActivity extends AppCompatActivity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_add_friend);
        setTitle(R.string.action_add_friend);

        final Tinode tinode = Cache.getTinode();

        TextView name = findViewById(R.id.myName);
        VxCard me = tinode.getMeTopic() != null ? (VxCard) tinode.getMeTopic().getPub() : null;
        name.setText(me != null && me.fn != null ? me.fn : "");
        ImageView qr = findViewById(R.id.myQrCode);
        if (tinode.getMyId() != null) {
            UiUtils.generateQRCode(qr, UiUtils.TOPIC_URI_PREFIX + tinode.getMyId());
        }

        EditText phone = findViewById(R.id.phoneInput);
        EditText email = findViewById(R.id.emailInput);
        findViewById(R.id.phoneGo).setOnClickListener(v -> {
            String tel = UtilsString.asPhone(phone.getText().toString().trim());
            if (tel == null) {
                Toast.makeText(this, R.string.enter_full_phone, Toast.LENGTH_SHORT).show();
                return;
            }
            search(Tinode.TAG_PHONE + tel);
        });
        findViewById(R.id.emailGo).setOnClickListener(v -> {
            String addr = UtilsString.asEmail(email.getText().toString().trim());
            if (addr == null) {
                Toast.makeText(this, R.string.invalid_email, Toast.LENGTH_SHORT).show();
                return;
            }
            search(Tinode.TAG_EMAIL + addr);
        });

        findViewById(R.id.scanQrRow).setOnClickListener(v ->
                startActivity(new Intent(this, QRScanActivity.class)));

        buildSuggestions();
    }

    // Directory lookup by a single exact tag; opens the chat when one matches.
    private void search(String query) {
        final FndTopic<VxCard> fnd = Cache.getTinode().getOrCreateFndTopic();
        Cache.attachFndTopic(new FndTopic.FndListener<>())
                .thenApply(new PromisedReply.SuccessListener<>() {
                    @Override
                    public PromisedReply<ServerMessage> onSuccess(ServerMessage unused) {
                        fnd.setMeta(new MsgSetMeta.Builder<String, String>()
                                .with(new MetaSetDesc<>(query, null)).build());
                        return fnd.getMeta(MsgGetMeta.sub());
                    }
                })
                .thenApply(new PromisedReply.SuccessListener<>() {
                    @Override
                    public PromisedReply<ServerMessage> onSuccess(ServerMessage unused) {
                        runOnUiThread(() -> showSearchResult(fnd));
                        return null;
                    }
                })
                .thenCatch(new PromisedReply.FailureListener<>() {
                    @Override
                    public PromisedReply<ServerMessage> onFailure(Exception err) {
                        runOnUiThread(() -> Toast.makeText(AddFriendActivity.this,
                                R.string.no_connection, Toast.LENGTH_SHORT).show());
                        return null;
                    }
                });
    }

    private void showSearchResult(FndTopic<VxCard> fnd) {
        Collection<Subscription<VxCard, String[]>> subs = fnd.getSubscriptions();
        if (subs != null) {
            for (Subscription<VxCard, String[]> s : subs) {
                String id = s.user != null ? s.user : s.topic;
                if (!TextUtils.isEmpty(id)) {
                    goToTopic(id);
                    return;
                }
            }
        }
        Toast.makeText(this, R.string.no_member_found, Toast.LENGTH_SHORT).show();
    }

    /** Members of my group chats without a direct chat yet, from the local
     * store — the useful meaning of "people you may know" on a family server. */
    private void buildSuggestions() {
        final Tinode tinode = Cache.getTinode();
        final String myId = tinode.getMyId();
        final LinearLayout list = findViewById(R.id.suggestionsList);
        final Set<String> seen = new HashSet<>();

        for (Topic<?, ?, ?, ?> t : tinode.getFilteredTopics(t ->
                t.getTopicType() == Topic.TopicType.GRP)) {
            @SuppressWarnings("unchecked")
            ComTopic<VxCard> grp = (ComTopic<VxCard>) t;
            Collection<Subscription<VxCard, PrivateType>> subs = grp.getSubscriptions();
            if (subs == null) {
                continue;
            }
            for (Subscription<VxCard, PrivateType> sub : subs) {
                final String uid = sub.user;
                if (TextUtils.isEmpty(uid) || uid.equals(myId) || !seen.add(uid)
                        || tinode.getTopic(uid) != null) {
                    continue;
                }
                list.addView(suggestionRow(sub.pub, uid));
            }
        }
        if (list.getChildCount() > 0) {
            findViewById(R.id.suggestionsHeader).setVisibility(View.VISIBLE);
        }
    }

    /** Avatar + name + "In a group with you", built in code: the existing
     * contact row layouts are welded to cursor adapters. */
    private View suggestionRow(VxCard pub, String uid) {
        final float dp = getResources().getDisplayMetrics().density;
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(android.view.Gravity.CENTER_VERTICAL);
        row.setPadding(0, (int) (8 * dp), 0, (int) (8 * dp));
        android.util.TypedValue tv = new android.util.TypedValue();
        getTheme().resolveAttribute(android.R.attr.selectableItemBackground, tv, true);
        row.setBackgroundResource(tv.resourceId);

        AppCompatImageView avatar = new AppCompatImageView(this);
        avatar.setImageDrawable(UiUtils.avatarDrawable(this,
                pub != null ? pub.getBitmap() : null,
                pub != null ? pub.fn : null, uid, false));
        row.addView(avatar, new LinearLayout.LayoutParams((int) (48 * dp), (int) (48 * dp)));

        LinearLayout texts = new LinearLayout(this);
        texts.setOrientation(LinearLayout.VERTICAL);
        texts.setPadding((int) (16 * dp), 0, 0, 0);
        TextView title = new TextView(this);
        title.setTextSize(16);
        title.setTextAppearance(android.R.style.TextAppearance_Material_Body1);
        title.setText(pub != null && pub.fn != null ? pub.fn : uid);
        TextView subtitle = new TextView(this);
        subtitle.setTextSize(13);
        subtitle.setTextAppearance(android.R.style.TextAppearance_Material_Small);
        subtitle.setText(R.string.in_group_with_you);
        texts.addView(title);
        texts.addView(subtitle);
        row.addView(texts);

        row.setOnClickListener(v -> goToTopic(uid));
        return row;
    }

    private void goToTopic(String id) {
        Intent it = new Intent(this, MessageActivity.class);
        it.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        it.putExtra(Const.INTENT_EXTRA_TOPIC, id);
        startActivity(it);
    }
}
