package co.tinode.tindroid;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;

/**
 * The four-digit passcode screen, used both to set a code and to unlock the app.
 *
 * <p>It draws its own keypad rather than raising the soft keyboard. A lock
 * screen has to be unmissable and undismissable, and a keyboard can be
 * dismissed, resized, or replaced by a third-party one — none of which is
 * acceptable on the screen standing between someone and a stranger's chats.
 *
 * <p>Kept in step with the iOS PasscodeViewController.
 */
public class PasscodeActivity extends AppCompatActivity {
    public static final String EXTRA_MODE = "passcode_mode";

    /** Blocks the app until the correct code is entered. */
    public static final String MODE_UNLOCK = "unlock";
    /** First-time setup: enter, then confirm. */
    public static final String MODE_SETUP = "setup";
    /** Confirm the current code, then set a new one. */
    public static final String MODE_CHANGE = "change";
    /** Confirm the current code, then delete it. */
    public static final String MODE_REMOVE = "remove";

    private static final int STAGE_VERIFY = 0;
    private static final int STAGE_ENTER_NEW = 1;
    private static final int STAGE_CONFIRM_NEW = 2;

    private static final int ACCENT = 0xFF00A884;
    private static final int DOT_SIZE_DP = 16;
    private static final int KEY_SIZE_DP = 76;

    private String mMode;
    private String mUid;
    private int mStage;
    private String mFirstEntry;
    private final StringBuilder mEntry = new StringBuilder();

    private TextView mTitle;
    private TextView mHint;
    private TextView mError;
    private LinearLayout mDotsRow;
    private final View[] mDots = new View[Passcode.LENGTH];

    /** Opens the screen in one of the four modes. */
    public static Intent intent(Context context, String mode) {
        Intent i = new Intent(context, PasscodeActivity.class);
        i.putExtra(EXTRA_MODE, mode);
        return i;
    }

    private float dp(float value) {
        return TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value,
                getResources().getDisplayMetrics());
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        mMode = getIntent().getStringExtra(EXTRA_MODE);
        if (TextUtils.isEmpty(mMode)) {
            mMode = MODE_UNLOCK;
        }
        mUid = Cache.getTinode() != null ? Cache.getTinode().getMyId() : null;
        // Setup has no current code to confirm; every other mode starts there.
        mStage = MODE_SETUP.equals(mMode) ? STAGE_ENTER_NEW : STAGE_VERIFY;

        setContentView(buildLayout());
        refreshPrompt();
        refreshDots();
        Passcode.setShowing(true);
    }

    @Override
    protected void onDestroy() {
        Passcode.setShowing(false);
        super.onDestroy();
    }

    @Override
    public void onBackPressed() {
        if (MODE_UNLOCK.equals(mMode)) {
            // The lock screen must not be dismissed with Back. Drop to the
            // home screen instead, leaving the app locked.
            moveTaskToBack(true);
            return;
        }
        super.onBackPressed();
    }

    // ── Layout ──────────────────────────────────────────────────────────────

    private View buildLayout() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setBackgroundColor(themeColor(android.R.attr.colorBackground));
        root.setPadding((int) dp(24), (int) dp(24), (int) dp(24), (int) dp(24));

        mTitle = new TextView(this);
        mTitle.setTextSize(24);
        mTitle.setGravity(Gravity.CENTER);
        mTitle.setTextColor(themeColor(android.R.attr.textColorPrimary));
        root.addView(mTitle);

        mHint = new TextView(this);
        mHint.setTextSize(15);
        mHint.setGravity(Gravity.CENTER);
        mHint.setTextColor(themeColor(android.R.attr.textColorSecondary));
        LinearLayout.LayoutParams hintLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        hintLp.topMargin = (int) dp(8);
        root.addView(mHint, hintLp);

        mDotsRow = new LinearLayout(this);
        mDotsRow.setOrientation(LinearLayout.HORIZONTAL);
        mDotsRow.setGravity(Gravity.CENTER);
        for (int i = 0; i < Passcode.LENGTH; i++) {
            View dot = new View(this);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    (int) dp(DOT_SIZE_DP), (int) dp(DOT_SIZE_DP));
            lp.setMarginStart((int) dp(11));
            lp.setMarginEnd((int) dp(11));
            dot.setLayoutParams(lp);
            mDots[i] = dot;
            mDotsRow.addView(dot);
        }
        LinearLayout.LayoutParams dotsLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        dotsLp.topMargin = (int) dp(28);
        root.addView(mDotsRow, dotsLp);

        mError = new TextView(this);
        mError.setTextSize(14);
        mError.setGravity(Gravity.CENTER);
        mError.setTextColor(ContextCompat.getColor(this, R.color.colorDanger));
        // Reserve the line so the layout does not jump when an error appears.
        mError.setText(" ");
        LinearLayout.LayoutParams errLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        errLp.topMargin = (int) dp(16);
        root.addView(mError, errLp);

        LinearLayout.LayoutParams padLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        padLp.topMargin = (int) dp(28);
        root.addView(buildKeypad(), padLp);

        if (MODE_UNLOCK.equals(mMode)) {
            // Without a way out, forgetting the code would leave the app
            // permanently unusable and reinstalling the only remedy.
            Button forgot = new Button(this, null, android.R.attr.borderlessButtonStyle);
            forgot.setText(R.string.passcode_forgot);
            forgot.setAllCaps(false);
            forgot.setTextSize(15);
            forgot.setOnClickListener(v -> confirmLogout());
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.topMargin = (int) dp(24);
            root.addView(forgot, lp);
        } else {
            Button cancel = new Button(this, null, android.R.attr.borderlessButtonStyle);
            cancel.setText(android.R.string.cancel);
            cancel.setAllCaps(false);
            cancel.setTextSize(15);
            cancel.setOnClickListener(v -> {
                setResult(Activity.RESULT_CANCELED);
                finish();
            });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.topMargin = (int) dp(24);
            root.addView(cancel, lp);
        }

        return root;
    }

    /** Resolves a theme attribute to a colour, so the screen follows the
     * app's light and dark themes instead of hard-coding one of them. */
    private int themeColor(int attr) {
        TypedValue tv = new TypedValue();
        if (getTheme().resolveAttribute(attr, tv, true)) {
            return tv.resourceId != 0 ? ContextCompat.getColor(this, tv.resourceId) : tv.data;
        }
        return Color.GRAY;
    }

    private View buildKeypad() {
        LinearLayout grid = new LinearLayout(this);
        grid.setOrientation(LinearLayout.VERTICAL);
        grid.setGravity(Gravity.CENTER);

        String[][] rows = {{"1", "2", "3"}, {"4", "5", "6"}, {"7", "8", "9"}, {"", "0", "⌫"}};
        for (String[] row : rows) {
            LinearLayout line = new LinearLayout(this);
            line.setOrientation(LinearLayout.HORIZONTAL);
            line.setGravity(Gravity.CENTER);
            for (String label : row) {
                line.addView(makeKey(label));
            }
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.topMargin = (int) dp(8);
            grid.addView(line, lp);
        }
        return grid;
    }

    private View makeKey(final String label) {
        int size = (int) dp(KEY_SIZE_DP);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(size, size);
        lp.setMarginStart((int) dp(12));
        lp.setMarginEnd((int) dp(12));

        if (label.isEmpty()) {
            // A spacer, so "0" stays centred under "8".
            View filler = new View(this);
            filler.setLayoutParams(lp);
            return filler;
        }

        TextView key = new TextView(this);
        key.setLayoutParams(lp);
        key.setText(label);
        key.setGravity(Gravity.CENTER);
        key.setTextColor(themeColor(android.R.attr.textColorPrimary));
        key.setClickable(true);
        key.setFocusable(true);

        if ("⌫".equals(label)) {
            key.setTextSize(24);
            key.setOnClickListener(v -> {
                if (mEntry.length() > 0) {
                    mEntry.deleteCharAt(mEntry.length() - 1);
                    refreshDots();
                }
            });
        } else {
            key.setTextSize(30);
            GradientDrawable bg = new GradientDrawable();
            bg.setShape(GradientDrawable.OVAL);
            bg.setColor(themeColor(android.R.attr.colorButtonNormal));
            key.setBackground(bg);
            key.setOnClickListener(v -> onDigit(label));
        }
        return key;
    }

    // ── Prompt and dots ─────────────────────────────────────────────────────

    private void refreshPrompt() {
        if (MODE_UNLOCK.equals(mMode)) {
            mTitle.setText(R.string.passcode_enter);
            mHint.setText(R.string.passcode_app_locked);
            return;
        }
        switch (mStage) {
            case STAGE_VERIFY:
                mTitle.setText(R.string.passcode_enter_current);
                mHint.setText("");
                break;
            case STAGE_ENTER_NEW:
                mTitle.setText(R.string.passcode_choose);
                mHint.setText(R.string.passcode_choose_explained);
                break;
            default:
                mTitle.setText(R.string.passcode_confirm);
                mHint.setText(R.string.passcode_confirm_explained);
                break;
        }
    }

    private void refreshDots() {
        for (int i = 0; i < mDots.length; i++) {
            boolean filled = i < mEntry.length();
            GradientDrawable d = new GradientDrawable();
            d.setShape(GradientDrawable.OVAL);
            d.setColor(filled ? ACCENT : Color.TRANSPARENT);
            d.setStroke((int) dp(1.5f), filled ? ACCENT
                    : ContextCompat.getColor(this, R.color.colorGray));
            mDots[i].setBackground(d);
        }
    }

    private void showError(int messageId) {
        mError.setText(messageId);
        mEntry.setLength(0);
        refreshDots();
        mDotsRow.animate().translationX(dp(10)).setDuration(60)
                .withEndAction(() -> mDotsRow.animate().translationX(-dp(10)).setDuration(60)
                        .withEndAction(() -> mDotsRow.animate().translationX(0).setDuration(60)));
        mDotsRow.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
    }

    // ── Flow ────────────────────────────────────────────────────────────────

    private void onDigit(String digit) {
        if (mEntry.length() >= Passcode.LENGTH) {
            return;
        }
        mError.setText(" ");
        mEntry.append(digit);
        refreshDots();
        if (mEntry.length() == Passcode.LENGTH) {
            final String complete = mEntry.toString();
            // Let the last dot paint before the screen changes under it.
            mDotsRow.postDelayed(() -> process(complete), 120);
        }
    }

    private void process(String code) {
        switch (mStage) {
            case STAGE_VERIFY:
                if (!Passcode.verify(this, mUid, code)) {
                    showError(R.string.passcode_wrong);
                    return;
                }
                if (MODE_UNLOCK.equals(mMode)) {
                    Passcode.unlock();
                    setResult(Activity.RESULT_OK);
                    finish();
                } else if (MODE_REMOVE.equals(mMode)) {
                    Passcode.clear(this, mUid);
                    setResult(Activity.RESULT_OK);
                    finish();
                } else {
                    mEntry.setLength(0);
                    refreshDots();
                    mStage = STAGE_ENTER_NEW;
                    refreshPrompt();
                }
                break;

            case STAGE_ENTER_NEW:
                mFirstEntry = code;
                mEntry.setLength(0);
                refreshDots();
                mStage = STAGE_CONFIRM_NEW;
                refreshPrompt();
                break;

            default:
                if (!code.equals(mFirstEntry)) {
                    // Back to the first entry: re-confirming against a code
                    // they may have mistyped would lock in the typo.
                    mFirstEntry = null;
                    mStage = STAGE_ENTER_NEW;
                    refreshPrompt();
                    showError(R.string.passcode_mismatch);
                    return;
                }
                if (!Passcode.set(this, mUid, code)) {
                    showError(R.string.passcode_save_failed);
                    return;
                }
                Passcode.unlock();
                setResult(Activity.RESULT_OK);
                finish();
                break;
        }
    }

    private void confirmLogout() {
        new AlertDialog.Builder(this)
                .setMessage(R.string.passcode_logout_warning)
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton(R.string.logout, (dialog, which) -> {
                    Passcode.clear(this, mUid);
                    Passcode.unlock();
                    UiUtils.doLogout(this);
                    finish();
                })
                .show();
    }
}
