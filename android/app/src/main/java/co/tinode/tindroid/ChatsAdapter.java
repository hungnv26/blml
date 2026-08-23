package co.tinode.tindroid;

import android.app.Activity;
import android.content.Context;
import android.content.res.TypedArray;
import android.graphics.Typeface;
import android.text.TextUtils;

import java.util.Calendar;
import java.util.Date;

import androidx.core.content.ContextCompat;
import android.view.LayoutInflater;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.widget.AppCompatImageView;
import androidx.core.content.res.ResourcesCompat;
import androidx.recyclerview.selection.ItemDetailsLookup;
import androidx.recyclerview.selection.ItemKeyProvider;
import androidx.recyclerview.selection.SelectionTracker;
import androidx.recyclerview.widget.RecyclerView;
import co.tinode.tindroid.db.StoredTopic;
import co.tinode.tindroid.format.PreviewFormatter;
import co.tinode.tindroid.media.VxCard;
import co.tinode.tinodesdk.ComTopic;
import co.tinode.tinodesdk.Storage;
import co.tinode.tinodesdk.Tinode;
import co.tinode.tinodesdk.Topic;
import co.tinode.tinodesdk.model.Drafty;
import co.tinode.tinodesdk.model.TheCard;

/**
 * Handling active chats, i.e. 'me' topic.
 */
public class ChatsAdapter extends RecyclerView.Adapter<ChatsAdapter.ViewHolder> {
    private static final int MAX_MESSAGE_PREVIEW_LENGTH = 60;

    private static int sColorOffline;
    private static int sColorOnline;
    // The slf topic has no public name, so a search has to match its
    // displayed title instead or Saved messages becomes unfindable while the
    // pinned row is hidden.
    private static String sSelfTitle;
    private final ClickListener mClickListener;
    private List<ComTopic<VxCard>> mTopics;
    private HashMap<String, Integer> mTopicIndex;
    private SelectionTracker<String> mSelectionTracker;
    private final Filter mTopicFilter;
    // Optional filter to find topics by name.
    private Filter mTextFilter = null;
    // Saved messages is pinned above everything else, in row 0. It used to
    // live on the Contacts tab, which read as a person rather than a
    // conversation. Hidden while a search is running: a pinned row that
    // ignores the query looks like a result that does not match.
    private boolean mPinSaved = true;

    ChatsAdapter(Context context, ClickListener clickListener, @Nullable Filter filter) {
        super();

        mClickListener = clickListener;
        mTopicFilter = filter != null ? filter : topic -> true;

        setHasStableIds(true);
        setTextFilter(null);

        sColorOffline = ResourcesCompat.getColor(context.getResources(),
                R.color.offline, context.getTheme());
        sColorOnline = ResourcesCompat.getColor(context.getResources(),
                R.color.online, context.getTheme());
        sSelfTitle = context.getString(R.string.self_topic_title);
    }

    void resetContent(Activity activity) {
        if (activity == null || activity.isFinishing() || activity.isDestroyed()) {
            return;
        }

        final boolean pinSaved = mPinSaved;
        final Collection<ComTopic<VxCard>> newTopics = Cache.getTinode().getFilteredTopics(t ->
                t.getTopicType().match(ComTopic.TopicType.USER) &&
                        !(pinSaved && t.isSlfType()) &&
                        mTopicFilter.filter((ComTopic) t) &&
                        mTextFilter.filter((ComTopic) t));

        final HashMap<String, Integer> newTopicIndex = new HashMap<>(newTopics.size());
        for (ComTopic t : newTopics) {
            newTopicIndex.put(t.getName(), newTopicIndex.size());
        }

        final List<ComTopic<VxCard>> newTopicList = new ArrayList<>(newTopics);

        activity.runOnUiThread(() -> {
            mTopics = newTopicList;
            mTopicIndex = newTopicIndex;
            notifyDataSetChanged();
        });
    }

    @NonNull
    @Override
    public ViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        final LayoutInflater inflater = LayoutInflater.from(parent.getContext());
        return new ViewHolder(
                inflater.inflate(viewType, parent, false), mClickListener, viewType);
    }

    /** 1 while the pinned Saved messages row occupies position 0. */
    private int pinnedCount() {
        return mPinSaved ? 1 : 0;
    }

    /** The real slf topic, or null when it has not been created yet: the
     * server makes it on the first subscribe, so a fresh account has none. */
    @SuppressWarnings("unchecked")
    private ComTopic<VxCard> savedTopic() {
        if (Cache.getTinode() == null) {
            return null;
        }
        Topic t = Cache.getTinode().getTopic(Tinode.TOPIC_SLF);
        return t instanceof ComTopic ? (ComTopic<VxCard>) t : null;
    }

    @Override
    public void onBindViewHolder(@NonNull ViewHolder holder, int position) {
        if (holder.viewType == R.layout.contact && position < pinnedCount()) {
            holder.bindSaved(savedTopic());
            return;
        }
        position -= pinnedCount();
        if (holder.viewType == R.layout.contact) {
            if (mTopics.size() <= position) {
                // Looks like there is a race condition here.
                return;
            }
            ComTopic<VxCard> topic = mTopics.get(position);
            if (topic == null) {
                // This should not happen.
                return;
            }
            Storage.Message msg = Cache.getTinode().getLastMessage(topic.getName());
            holder.bind(position, topic, msg, mSelectionTracker != null &&
                    mSelectionTracker.isSelected(topic.getName()));
        }
    }

    @Override
    public long getItemId(int position) {
        if (position < pinnedCount()) {
            return Tinode.TOPIC_SLF.hashCode();
        }
        position -= pinnedCount();
        if (getActualItemCount() == 0) {
            return -2;
        }
        return StoredTopic.getId(mTopics.get(position));
    }

    private String getItemKey(int position) {
        if (position < pinnedCount()) {
            return Tinode.TOPIC_SLF;
        }
        position -= pinnedCount();
        if (mTopics == null || position < 0 || position >= mTopics.size()) {
            return null;
        }
        return mTopics.get(position).getName();
    }

    public int getItemPosition(String key) {
        if (mTopicIndex == null) {
            return -1;
        }
        Integer pos = mTopicIndex.get(key);
        return pos == null ? -1 : pos + pinnedCount();
    }

    private int getActualItemCount() {
        return mTopics == null ? 0 : mTopics.size();
    }

    @Override
    public int getItemCount() {
        // If there are no contacts, the RV will show a single 'empty' item.
        int count = getActualItemCount();
        return pinnedCount() + (count == 0 ? 1 : count);
    }

    @Override
    public int getItemViewType(int position) {
        if (position < pinnedCount()) {
            return R.layout.contact;
        }
        if (getActualItemCount() == 0) {
            return R.layout.contact_empty;
        }
        return R.layout.contact;
    }

    void setSelectionTracker(SelectionTracker<String> selectionTracker) {
        mSelectionTracker = selectionTracker;
    }

    void setTextFilter(@Nullable String text) {
        // The pinned row steps aside for a search, and the slf topic rejoins
        // the ordinary filtered list so it can still be found.
        mPinSaved = TextUtils.isEmpty(text);
        mTextFilter = new Filter() {
            private final String mQuery = text;
            @Override
            public boolean filter(ComTopic topic) {
                if (TextUtils.isEmpty(mQuery)) {
                    return true;
                }

                if (topic.isSlfType()) {
                    return sSelfTitle != null &&
                            sSelfTitle.toLowerCase(Locale.getDefault()).contains(mQuery);
                }

                ArrayList<String> hayStack = new ArrayList<>();
                TheCard pub = (TheCard) topic.getPub();
                if (pub != null) {
                    hayStack.add(pub.fn);
                    hayStack.add(pub.note);
                }
                hayStack.add(topic.getComment());
                return hayStack.stream()
                        .filter(token -> token != null && token.toLowerCase(Locale.getDefault()).contains(mQuery))
                        .findAny()
                        .orElse(null) != null;
            }
        };
    }

    interface ClickListener {
        void onClick(String topicName);
    }

    interface Filter {
        // Returns true to keep topic, false to ignore.
        boolean filter(ComTopic topic);
    }

    static class ContactDetailsLookup extends ItemDetailsLookup<String> {
        final RecyclerView mRecyclerView;

        ContactDetailsLookup(RecyclerView rv) {
            mRecyclerView = rv;
        }

        @Nullable
        @Override
        public ItemDetails<String> getItemDetails(@NonNull MotionEvent e) {
            View view = mRecyclerView.findChildViewUnder(e.getX(), e.getY());
            if (view != null) {
                ViewHolder holder = (ViewHolder) mRecyclerView.getChildViewHolder(view);
                return holder.getItemDetails();
            }
            return null;
        }
    }

    static class ContactDetails extends ItemDetailsLookup.ItemDetails<String> {
        int pos;
        String id;

        @Override
        public int getPosition() {
            return pos;
        }

        @Nullable
        @Override
        public String getSelectionKey() {
            return id;
        }
    }

    static class ContactKeyProvider extends ItemKeyProvider<String> {
        final ChatsAdapter mAdapter;

        ContactKeyProvider(ChatsAdapter adapter) {
            super(SCOPE_MAPPED);
            mAdapter = adapter;
        }

        @Nullable
        @Override
        public String getKey(int position) {
            return mAdapter.getItemKey(position);
        }

        @Override
        public int getPosition(@NonNull String key) {
            return mAdapter.getItemPosition(key);
        }
    }

    /** Time for today, otherwise a short date — matches the iOS/web row format. */
    private static String shortTime(Context ctx, Date when) {
        Calendar then = Calendar.getInstance();
        then.setTime(when);
        Calendar now = Calendar.getInstance();
        boolean sameDay = then.get(Calendar.YEAR) == now.get(Calendar.YEAR)
                && then.get(Calendar.DAY_OF_YEAR) == now.get(Calendar.DAY_OF_YEAR);
        return sameDay
                ? android.text.format.DateFormat.getTimeFormat(ctx).format(when)
                : android.text.format.DateFormat.getDateFormat(ctx).format(when);
    }

    public static class ViewHolder extends RecyclerView.ViewHolder {
        final int viewType;
        TextView name;
        TextView unreadCount;
        TextView time;
        TextView priv;
        ImageView messageStatus;
        AppCompatImageView avatarView;
        ImageView online;
        ImageView deleted;
        ImageView channel;
        ImageView group;
        ImageView verified;
        ImageView staff;
        ImageView danger;
        ImageView muted;
        ImageView blocked;
        ImageView archived;
        View pinned;

        final ContactDetails details;
        ClickListener clickListener;

        ViewHolder(@NonNull View item, ClickListener cl, int viewType) {
            super(item);
            this.viewType = viewType;

            if (viewType == R.layout.contact) {
                name = item.findViewById(R.id.contactName);
                unreadCount = item.findViewById(R.id.unreadCount);
                time = item.findViewById(R.id.contactTime);
                priv = item.findViewById(R.id.contactPriv);
                messageStatus = item.findViewById(R.id.messageStatus);
                avatarView = item.findViewById(R.id.avatar);
                online = item.findViewById(R.id.online);
                deleted = item.findViewById(R.id.deleted);
                channel = item.findViewById(R.id.icon_channel);
                group = item.findViewById(R.id.icon_group);
                verified = item.findViewById(R.id.icon_verified);
                staff = item.findViewById(R.id.icon_staff);
                danger = item.findViewById(R.id.icon_danger);
                muted = item.findViewById(R.id.icon_muted);
                blocked = item.findViewById(R.id.icon_blocked);
                archived = item.findViewById(R.id.icon_archived);
                pinned = item.findViewById(R.id.pinnedChatIndicator);

                details = new ContactDetails();
                clickListener = cl;
            } else {
                details = null;
            }
        }

        ItemDetailsLookup.ItemDetails<String> getItemDetails() {
            // The pinned Saved messages row is not selectable: multi-select
            // exists to delete and archive chats, and neither applies to a row
            // that is drawn whether or not the topic exists.
            return isPinnedSaved ? null : details;
        }

        /** True while this holder is showing the pinned Saved messages row. */
        boolean isPinnedSaved = false;

        /** Draws the pinned Saved messages row.
         *
         * The slf topic is created server-side on the first subscribe, so for
         * anyone who has never opened it there is nothing to bind — and the
         * row still has to be there, or Saved messages is unreachable now that
         * the Contacts tab no longer lists it. When the topic does exist the
         * ordinary bind runs, keeping the preview, unread badge and time. */
        void bindSaved(@Nullable ComTopic<VxCard> topic) {
            isPinnedSaved = true;
            if (topic != null) {
                bind(0, topic, Cache.getTinode().getLastMessage(topic.getName()), false);
                // bind() clears the flag on the way through; this row is still
                // the pinned one.
                isPinnedSaved = true;
                return;
            }

            name.setText(R.string.self_topic_title);
            name.setTypeface(null, Typeface.NORMAL);
            priv.setText(R.string.self_topic_description);
            messageStatus.setVisibility(View.GONE);
            unreadCount.setVisibility(View.GONE);
            if (time != null) {
                time.setVisibility(View.GONE);
            }
            UiUtils.setAvatar(avatarView, null, Tinode.TOPIC_SLF, false);
            online.setVisibility(View.INVISIBLE);
            channel.setVisibility(View.GONE);
            group.setVisibility(View.GONE);
            deleted.setVisibility(View.GONE);
            verified.setVisibility(View.GONE);
            staff.setVisibility(View.GONE);
            danger.setVisibility(View.GONE);
            muted.setVisibility(View.GONE);
            archived.setVisibility(View.GONE);
            blocked.setVisibility(View.GONE);
            pinned.setVisibility(View.GONE);
            itemView.setAlpha(1.0f);
            itemView.setActivated(false);

            final Context context = itemView.getContext();
            TypedArray typedArray = context.obtainStyledAttributes(
                    new int[]{android.R.attr.selectableItemBackgroundBorderless});
            itemView.setBackgroundResource(typedArray.getResourceId(0, 0));
            typedArray.recycle();
            itemView.setOnClickListener(view -> clickListener.onClick(Tinode.TOPIC_SLF));
            itemView.setOnLongClickListener(null);
        }

        void bind(int position, final ComTopic<VxCard> topic, Storage.Message msg, boolean selected) {
            // View holders are recycled; a row that was the pinned one last
            // time must go back to being selectable.
            isPinnedSaved = false;
            final Context context = itemView.getContext();
            final String topicName = topic.getName();

            details.pos = position;
            details.id = topicName;

            VxCard pub = topic.getPub();
            if (pub != null && pub.fn != null) {
                name.setText(pub.fn);
                name.setTypeface(null, Typeface.NORMAL);
            } else if (topic.isSlfType()) {
                name.setText(R.string.self_topic_title);
                name.setTypeface(null, Typeface.NORMAL);
            } else {
                name.setText(R.string.placeholder_contact_title);
                name.setTypeface(null, Typeface.ITALIC);
            }
            Drafty content = (msg != null && !msg.isDeleted()) ? msg.getContent() : null;
            if (content != null) {
                if (msg.isMine()) {
                    messageStatus.setVisibility(View.VISIBLE);
                    UiUtils.setMessageStatusIcon(messageStatus, msg.getStatus(),
                            topic.msgReadCount(msg.getSeqId()), topic.msgRecvCount(msg.getSeqId()));
                } else {
                    messageStatus.setVisibility(View.GONE);
                }
                priv.setText(content.preview(MAX_MESSAGE_PREVIEW_LENGTH)
                        .format(new PreviewFormatter(priv.getContext(), priv.getTextSize())));
            } else {
                messageStatus.setVisibility(View.GONE);
                priv.setText(topic.getComment());
            }

            int unread = topic.getUnreadCount();
            if (unread > 0) {
                unreadCount.setText(unread > 9 ? "9+" : String.valueOf(unread));
                unreadCount.setVisibility(View.VISIBLE);
            } else {
                unreadCount.setVisibility(View.GONE);
            }

            // WhatsApp-style row timestamp: time today, date otherwise; green
            // while there are unread messages, same as iOS and web.
            if (time != null) {
                Date touched = topic.getTouched();
                if (touched != null) {
                    time.setText(shortTime(time.getContext(), touched));
                    time.setTextColor(unread > 0
                            ? 0xFF25D366
                            : ContextCompat.getColor(time.getContext(), R.color.colorGray));
                    time.setVisibility(View.VISIBLE);
                } else {
                    time.setVisibility(View.GONE);
                }
            }

            UiUtils.setAvatar(avatarView, pub, topicName, topic.isDeleted());

            if (topic.isChannel()) {
                online.setVisibility(View.INVISIBLE);
                channel.setVisibility(View.VISIBLE);
            } else if (topic.isSlfType()) {
                online.setVisibility(View.INVISIBLE);
                channel.setVisibility(View.GONE);
            } else {
                channel.setVisibility(View.GONE);
                if (topic.isGrpType()) {
                   group.setVisibility(View.VISIBLE);
                } else {
                    group.setVisibility(View.GONE);
                }
                if (topic.isDeleted()) {
                    online.setVisibility(View.GONE);
                } else {
                    online.setVisibility(View.VISIBLE);
                    online.setColorFilter(topic.getOnline() ? sColorOnline : sColorOffline);
                }
            }

            if (topic.isDeleted()) {
                itemView.setAlpha(0.8f);
                deleted.setVisibility(View.VISIBLE);
            } else {
                deleted.setVisibility(View.GONE);
                itemView.setAlpha(1.0f);
            }

            verified.setVisibility(topic.isTrustedVerified() ? View.VISIBLE : View.GONE);
            staff.setVisibility(topic.isTrustedStaff() ? View.VISIBLE : View.GONE);
            danger.setVisibility(topic.isTrustedDanger() ? View.VISIBLE : View.GONE);

            if (topic.isSlfType()) {
                muted.setVisibility(View.GONE);
            } else {
                muted.setVisibility(topic.isMuted() ? View.VISIBLE : View.GONE);
            }
            archived.setVisibility(topic.isArchived() ? View.VISIBLE : View.GONE);
            blocked.setVisibility(!topic.isJoiner() ? View.VISIBLE : View.GONE);

            pinned.setVisibility(topic.getPinnedRank() > 0 ? View.VISIBLE : View.GONE);

            if (selected) {
                itemView.setBackgroundResource(R.drawable.contact_background);
                itemView.setOnClickListener(null);

                itemView.setActivated(true);
            } else {
                if (topic.getPinnedRank() > 0) {
                    itemView.setBackgroundResource(R.drawable.contact_background_pinned);
                } else {
                    TypedArray typedArray = context.obtainStyledAttributes(new int[]{android.R.attr.selectableItemBackgroundBorderless});
                    itemView.setBackgroundResource(typedArray.getResourceId(0, 0));
                    typedArray.recycle();
                }
                itemView.setOnClickListener(view -> clickListener.onClick(topicName));

                itemView.setActivated(false);
            }

            // Field lengths may have changed.
            itemView.invalidate();
        }
    }
}
