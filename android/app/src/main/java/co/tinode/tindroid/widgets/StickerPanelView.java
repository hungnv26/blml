package co.tinode.tindroid.widgets;

import android.content.Context;
import android.graphics.Color;
import android.util.AttributeSet;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AbsListView;
import android.widget.BaseAdapter;
import android.widget.GridView;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * A keyboard-sized panel of stickers, shown in place of the soft keyboard.
 * Mirrors ios/Tinodios/widgets/EmojiPickerView.swift — keep the two in step.
 * <p>
 * Deliberately plain emoji rather than downloaded image packs: no server
 * storage, no asset pipeline, and they travel as ordinary text so every client
 * already displays them.
 */
public class StickerPanelView extends LinearLayout {
    public interface Listener {
        void onSticker(String emoji);

        void onBackspace();
    }

    private static class Category {
        final String label;
        final String[] emoji;
        final int perRow;

        Category(String label, int perRow, String[] emoji) {
            this.label = label;
            this.perRow = perRow;
            this.emoji = emoji;
        }
    }

    private static final Category[] CATEGORIES = new Category[]{
            // The page the picker opens on: the handful of things people
            // actually send. Pairs where one emoji alone reads ambiguously
            // (a lone cake says "cake"; cake+popper says "happy birthday").
            new Category("⭐", 5, new String[]{
                    "👍", "❤️", "🎉", "🎂🎉", "🙏", "👌",
                    "😂", "😍", "👏", "🔥", "💯", "✅",
                    "👋", "🤝", "🥰", "😮", "😢", "🤔",
                    "💪", "🙌", "🎁", "💐", "🍀", "⭐",
                    "😅", "🤷", "😴", "☕", "🌹", "🎊"}),
            new Category("😀", 6, new String[]{
                    "😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "🙃",
                    "😉", "😊", "😇", "🥰", "😍", "🤩", "😘", "😗", "😚", "😙",
                    "😋", "😛", "😜", "🤪", "😝", "🤑", "🤗", "🤭", "🤫", "🤔",
                    "🤐", "🤨", "😐", "😑", "😶", "😏", "😒", "🙄", "😬", "😌",
                    "😔", "😪", "🤤", "😴", "😷", "🤒", "🤕", "🥵", "🥶", "🥴",
                    "😵", "🤯", "🤠", "🥳", "😎", "🤓", "🧐", "😕", "😟", "🙁",
                    "😮", "😯", "😲", "😳", "🥺", "😦", "😧", "😨", "😰", "😥",
                    "😢", "😭", "😱", "😖", "😣", "😞", "😓", "😩", "😫", "🥱",
                    "😤", "😡", "😠", "🤬", "😈", "👿", "💀", "💩", "🤡", "👻"}),
            new Category("👍", 6, new String[]{
                    "👍", "👎", "👌", "🤌", "✌️", "🤞", "🤟", "🤘", "🤙", "👈",
                    "👉", "👆", "👇", "☝️", "✋", "🤚", "🖐️", "🖖", "👋", "🤝",
                    "🙏", "✊", "👊", "🤛", "🤜", "👏", "🙌", "👐", "🤲", "💪",
                    "🦾", "👀", "👁️", "👂", "👃", "👄", "🧠", "🦴", "🫀", "🤳"}),
            new Category("❤️", 6, new String[]{
                    "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔",
                    "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💟", "♥️",
                    "💯", "💢", "💥", "💫", "💦", "💨", "🔥", "✨", "🌟", "⭐"}),
            new Category("🐶", 6, new String[]{
                    "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯",
                    "🦁", "🐮", "🐷", "🐸", "🐵", "🙈", "🙉", "🙊", "🐔", "🐧",
                    "🐦", "🐤", "🦆", "🦅", "🦉", "🦇", "🐺", "🐗", "🐴", "🦄",
                    "🐝", "🐛", "🦋", "🐌", "🐞", "🐢", "🐍", "🐙", "🦑", "🦀",
                    "🐬", "🐳", "🐟", "🐊", "🐆", "🦓", "🦍", "🐘", "🐫", "🦒"}),
            new Category("🍔", 6, new String[]{
                    "🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐",
                    "🍈", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🥑", "🍆",
                    "🥕", "🌽", "🌶️", "🥒", "🥬", "🥦", "🧄", "🧅", "🍄", "🥜",
                    "🍞", "🥐", "🥖", "🧀", "🥚", "🍳", "🥞", "🥓", "🍔", "🍟",
                    "🍕", "🌭", "🥪", "🌮", "🌯", "🍜", "🍲", "🍣", "🍱", "🍚",
                    "🍦", "🍰", "🎂", "🍫", "🍬", "🍭", "🍩", "🍪", "☕", "🍺"}),
            new Category("⚽", 6, new String[]{
                    "⚽", "🏀", "🏈", "⚾", "🎾", "🏐", "🏉", "🎱", "🏓", "🏸",
                    "🥅", "🏒", "🏑", "🏏", "⛳", "🏹", "🎣", "🥊", "🥋", "⛸️",
                    "🎿", "🛷", "🏂", "🏋️", "🤸", "🤼", "🤽", "🤾", "🚴", "🚵",
                    "🏆", "🥇", "🥈", "🥉", "🎖️", "🎯", "🎲", "🎮", "🎰", "🎳",
                    "🎤", "🎧", "🎼", "🎹", "🥁", "🎷", "🎺", "🎸", "🎻", "🎬"}),
            new Category("🚗", 6, new String[]{
                    "🚗", "🚕", "🚙", "🚌", "🚎", "🏎️", "🚓", "🚑", "🚒", "🚐",
                    "🚚", "🚛", "🚜", "🛴", "🚲", "🛵", "🏍️", "✈️", "🚀", "🛸",
                    "🚁", "⛵", "🚤", "🛳️", "⚓", "🚦", "🗺️", "🗿", "🗽", "🗼",
                    "🏰", "🏠", "🏢", "🏥", "🏦", "🏫", "⛰️", "🏖️", "🏝️", "🌋",
                    "🌅", "🌄", "🌈", "☀️", "🌤️", "⛅", "🌧️", "⛈️", "❄️", "🌙"}),
            new Category("💡", 6, new String[]{
                    "⌚", "📱", "💻", "⌨️", "🖥️", "🖨️", "📷", "📹", "🎥", "📺",
                    "📻", "☎️", "📞", "📟", "🔋", "🔌", "💡", "🔦", "🕯️", "🧯",
                    "💰", "💳", "💎", "⚖️", "🔧", "🔨", "🛠️", "🔑", "🔒", "🔓",
                    "📦", "📫", "📮", "📝", "📚", "📖", "🔍", "🔎", "🎁", "🎈",
                    "🎉", "🎊", "🎀", "🎄", "🧨", "🔔", "⏰", "⏳", "🧭", "🩺"}),
            new Category("✅", 6, new String[]{
                    "✅", "❌", "⭕", "❗", "❓", "‼️", "⁉️", "💤", "🚫", "⚠️",
                    "♻️", "🔱", "⚜️", "🔰", "✳️", "❇️", "©️", "®️", "™️", "🆗",
                    "🆒", "🆕", "🆓", "🔝", "🔙", "🔜", "🔛", "🔃", "🔄", "▶️",
                    "⏸️", "⏹️", "⏺️", "⏭️", "⏮️", "🔀", "🔁", "🔂", "➕", "➖",
                    "0️⃣", "1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣", "6️⃣", "7️⃣", "8️⃣", "9️⃣"})
    };

    private Listener mListener;
    private GridView mGrid;
    private LinearLayout mTabs;
    private int mCurrent = 0;

    public StickerPanelView(Context context) {
        super(context);
        init();
    }

    public StickerPanelView(Context context, AttributeSet attrs) {
        super(context, attrs);
        init();
    }

    public void setListener(Listener l) {
        mListener = l;
    }

    private void init() {
        setOrientation(VERTICAL);

        // Follows the app theme rather than hard-coding: the Android client
        // still themes the composer with attributes, unlike the iOS one.
        TypedValue tv = new TypedValue();
        getContext().getTheme().resolveAttribute(android.R.attr.colorBackground, tv, true);
        setBackgroundColor(tv.data);

        mTabs = new LinearLayout(getContext());
        mTabs.setOrientation(HORIZONTAL);
        addView(mTabs, new LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(40)));

        for (int i = 0; i < CATEGORIES.length; i++) {
            final int index = i;
            TextView tab = makeKey(CATEGORIES[i].label, 17);
            tab.setOnClickListener(v -> selectCategory(index));
            mTabs.addView(tab, new LinearLayout.LayoutParams(0, LayoutParams.MATCH_PARENT, 1f));
        }
        TextView backspace = makeKey("⌫", 20);
        backspace.setOnClickListener(v -> {
            if (mListener != null) {
                mListener.onBackspace();
            }
        });
        mTabs.addView(backspace, new LinearLayout.LayoutParams(0, LayoutParams.MATCH_PARENT, 1f));

        mGrid = new GridView(getContext());
        mGrid.setVerticalScrollBarEnabled(false);
        mGrid.setSelector(android.R.color.transparent);
        addView(mGrid, new LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        mGrid.setOnItemClickListener((parent, view, position, id) -> {
            if (mListener != null) {
                mListener.onSticker(CATEGORIES[mCurrent].emoji[position]);
            }
        });

        selectCategory(0);
    }

    private TextView makeKey(String label, int sizeSp) {
        TextView t = new TextView(getContext());
        t.setText(label);
        t.setGravity(Gravity.CENTER);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp);
        t.setBackgroundResource(androidx.appcompat.R.drawable.abc_item_background_holo_light);
        return t;
    }

    private void selectCategory(int index) {
        mCurrent = index;
        for (int i = 0; i < CATEGORIES.length; i++) {
            // Emoji ignore text tint, so selection is shown by dimming the rest.
            mTabs.getChildAt(i).setAlpha(i == index ? 1f : 0.45f);
        }
        Category cat = CATEGORIES[index];
        mGrid.setNumColumns(cat.perRow);
        mGrid.setAdapter(new EmojiAdapter(cat));
    }

    private int dp(int v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v,
                getResources().getDisplayMetrics());
    }

    private class EmojiAdapter extends BaseAdapter {
        private final Category mCat;

        EmojiAdapter(Category cat) {
            mCat = cat;
        }

        @Override
        public int getCount() {
            return mCat.emoji.length;
        }

        @Override
        public Object getItem(int position) {
            return mCat.emoji[position];
        }

        @Override
        public long getItemId(int position) {
            return position;
        }

        @Override
        public View getView(int position, View convertView, ViewGroup parent) {
            TextView t = convertView instanceof TextView ? (TextView) convertView
                    : new TextView(getContext());
            t.setLayoutParams(new AbsListView.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, dp(mCat.perRow <= 5 ? 64 : 52)));
            t.setGravity(Gravity.CENTER);
            // Bigger cells on the common page deserve a bigger glyph. Pairs
            // ("🎂🎉") are wider than one glyph; auto-size shrinks, not clips.
            t.setTextSize(TypedValue.COMPLEX_UNIT_SP, mCat.perRow <= 5 ? 30 : 24);
            t.setTextColor(Color.BLACK);
            t.setText(mCat.emoji[position]);
            return t;
        }
    }
}
