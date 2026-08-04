package co.tinode.tindroid;

import android.Manifest;
import android.accounts.Account;
import android.accounts.AccountManager;
import android.content.Intent;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.text.TextUtils;
import android.view.Menu;

import java.util.List;

import com.google.android.material.bottomnavigation.BottomNavigationView;

import androidx.fragment.app.Fragment;
import androidx.fragment.app.FragmentActivity;
import androidx.fragment.app.FragmentManager;
import androidx.fragment.app.FragmentTransaction;
import co.tinode.tindroid.account.ContactsManager;
import co.tinode.tindroid.account.Utils;
import co.tinode.tindroid.media.VxCard;
import co.tinode.tinodesdk.MeTopic;
import co.tinode.tinodesdk.Tinode;
import co.tinode.tinodesdk.Topic;
import co.tinode.tinodesdk.model.Credential;
import co.tinode.tinodesdk.model.Description;
import co.tinode.tinodesdk.model.MsgServerInfo;
import co.tinode.tinodesdk.model.MsgServerPres;
import co.tinode.tinodesdk.model.PrivateType;
import co.tinode.tinodesdk.model.Subscription;

/**
 * This activity owns 'me' topic.
 */
public class ChatsActivity extends BaseActivity
        implements UiUtils.ProgressIndicator, UtilsMedia.MediaPreviewer,
        FindFragment.ReadContactsPermissionChecker,
        ImageViewFragment.AvatarCompletionHandler {
    static final String TAG_FRAGMENT_NAME = "fragment";
    static final String FRAGMENT_CHATLIST = "contacts";
    static final String FRAGMENT_ACCOUNT_INFO = "account_info";
    static final String FRAGMENT_AVATAR_PREVIEW = "avatar_preview";
    static final String FRAGMENT_ACC_CREDENTIALS = "acc_credentials";
    static final String FRAGMENT_ACC_HELP = "acc_help";
    static final String FRAGMENT_ACC_GENERAL = "acc_general";
    static final String FRAGMENT_ACC_NOTIFICATIONS = "acc_notifications";
    static final String FRAGMENT_ACC_PERSONAL = "acc_personal";
    static final String FRAGMENT_ACC_SECURITY = "acc_security";
    static final String FRAGMENT_ACC_ABOUT = "acc_about";
    static final String FRAGMENT_ARCHIVE = "archive";
    static final String FRAGMENT_BANNED = "banned";
    static final String FRAGMENT_WALLPAPERS = "wallpapers";
    static final String FRAGMENT_FIND = "find";

    private BottomNavigationView mBottomNav = null;
    // Set while the bar is being selected programmatically, so the tab listener
    // ignores that selection instead of navigating again (which recursed until
    // the stack overflowed).
    private boolean mSuppressNavListener = false;
    private ContactsEventListener mTinodeListener = null;
    private MeListener mMeTopicListener = null;
    private MeTopic<VxCard> mMeTopic = null;

    private Account mAccount;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        UiUtils.setupSystemToolbar(this);

        setContentView(R.layout.activity_contacts);
        applyEdgeToEdgeInsets(findViewById(android.R.id.content));

        setSupportActionBar(findViewById(R.id.toolbar));

        FragmentManager fm = getSupportFragmentManager();

        if (fm.findFragmentByTag(FRAGMENT_CHATLIST) == null) {
            Fragment fragment = new ChatsFragment();
            fm.beginTransaction()
                    .replace(R.id.contentFragment, fragment, FRAGMENT_CHATLIST)
                    .setPrimaryNavigationFragment(fragment)
                    .commit();
        }

        mBottomNav = findViewById(R.id.bottomNav);
        mBottomNav.setOnItemSelectedListener(item -> {
            if (mSuppressNavListener) {
                // Selection came from syncBottomNav, not from the user.
                return true;
            }
            final int id = item.getItemId();
            if (id == R.id.nav_chats) {
                showFragment(FRAGMENT_CHATLIST, null);
            } else if (id == R.id.nav_contacts) {
                showFragment(FRAGMENT_FIND, null);
            } else if (id == R.id.nav_settings) {
                showFragment(FRAGMENT_ACCOUNT_INFO, null);
            } else {
                return false;
            }
            return true;
        });
        // Re-tapping the already-selected tab should do nothing, not rebuild the
        // fragment and lose its scroll position.
        mBottomNav.setOnItemReselectedListener(item -> {});

        // Pressing Back pops a fragment without going through showFragment, so
        // the bar has to follow the back stack too.
        fm.addOnBackStackChangedListener(() -> {
            Fragment current = UiUtils.getVisibleFragment(fm);
            if (current != null && current.getTag() != null) {
                resetTopLevelToolbar(current.getTag());
                syncBottomNav(current.getTag());
            }
        });

        mMeTopic = Cache.getTinode().getOrCreateMeTopic();
        mMeTopicListener = new MeListener();
    }

    /**
     * Reset the toolbar when landing on a top-level tab. Sub-screens (account
     * pages) set their own title and back arrow, and nothing used to undo that,
     * so switching tabs left the previous screen's "Account settings" title and
     * up-arrow in place. Fragments that configure their own toolbar do so in
     * onResume, which runs after this, so they still win.
     */
    private void resetTopLevelToolbar(String tag) {
        final int titleRes;
        if (FRAGMENT_CHATLIST.equals(tag)) {
            titleRes = R.string.app_name;
        } else if (FRAGMENT_FIND.equals(tag)) {
            titleRes = R.string.contacts;
        } else {
            return;
        }

        androidx.appcompat.widget.Toolbar toolbar = findViewById(R.id.toolbar);
        if (toolbar != null) {
            toolbar.setTitle(titleRes);
            toolbar.setSubtitle(null);
            toolbar.setLogo(null);
        }
        androidx.appcompat.app.ActionBar bar = getSupportActionBar();
        if (bar != null) {
            bar.setDisplayHomeAsUpEnabled(false);
        }
    }

    // FindFragment (the Contacts tab) casts its host to this interface, so any
    // activity hosting it must implement it. Limits the permission prompt to
    // once per session, same as StartChatActivity does.
    private boolean mReadContactsPermissionsAlreadyRequested = false;

    @Override
    public boolean shouldRequestReadContactsPermission() {
        return !mReadContactsPermissionsAlreadyRequested;
    }

    @Override
    public void setReadContactsPermissionRequested() {
        mReadContactsPermissionsAlreadyRequested = true;
    }

    /**
     * Keep the bottom bar in sync with whatever fragment is actually showing.
     * Navigation also happens via intents, back-stack pops and in-app links, so
     * the bar cannot rely on its own taps alone. Sub-screens reached from a tab
     * (account sub-pages, archive) keep that tab highlighted; screens belonging
     * to no tab leave the selection untouched.
     */
    private void syncBottomNav(String tag) {
        if (mBottomNav == null) {
            return;
        }
        final int target;
        switch (tag) {
            case FRAGMENT_CHATLIST:
            case FRAGMENT_ARCHIVE:
            case FRAGMENT_BANNED:
                target = R.id.nav_chats;
                break;
            case FRAGMENT_FIND:
                target = R.id.nav_contacts;
                break;
            case FRAGMENT_ACCOUNT_INFO:
            case FRAGMENT_ACC_CREDENTIALS:
            case FRAGMENT_ACC_HELP:
            case FRAGMENT_ACC_GENERAL:
            case FRAGMENT_ACC_NOTIFICATIONS:
            case FRAGMENT_ACC_PERSONAL:
            case FRAGMENT_ACC_SECURITY:
            case FRAGMENT_ACC_ABOUT:
            case FRAGMENT_WALLPAPERS:
                target = R.id.nav_settings;
                break;
            default:
                return;
        }
        if (mBottomNav.getSelectedItemId() != target) {
            // Assigning selectedItemId fires the tab listener. Comparing ids is
            // not enough of a guard: the menu dispatches the click before it
            // marks the item checked, so during a user tap this still reads the
            // previous id. Suppress the listener outright for the duration.
            mSuppressNavListener = true;
            try {
                mBottomNav.setSelectedItemId(target);
            } finally {
                mSuppressNavListener = false;
            }
        }
    }

    /**
     * onResume restores subscription to 'me' topic and sets listener.
     */
    @Override
    public void onResume() {
        super.onResume();

        final Tinode tinode = Cache.getTinode();
        mTinodeListener = new ContactsEventListener(tinode.isConnected());
        tinode.addListener(mTinodeListener);

        Cache.setSelectedTopicName(null);

        UiUtils.setupToolbar(this, null, null, false,
                null, false, 0);

        if (!mMeTopic.isAttached()) {
            toggleProgressIndicator(true);
        }

        // This will issue a subscription request.
        if (!UiUtils.attachMeTopic(this, mMeTopicListener)) {
            toggleProgressIndicator(false);
        }

        final Intent intent = getIntent();
        String tag = intent.getStringExtra(TAG_FRAGMENT_NAME);
        if (!TextUtils.isEmpty(tag)) {
            showFragment(tag, null);
        }
    }

    private void datasetChanged() {
        Fragment fragment = UiUtils.getVisibleFragment(getSupportFragmentManager());
        if (fragment instanceof ChatsFragment) {
            ((ChatsFragment) fragment).datasetChanged();
        }
    }

    @Override
    public void onPause() {
        super.onPause();

        Cache.getTinode().removeListener(mTinodeListener);
    }

    @Override
    public void onStop() {
        super.onStop();
        if (mMeTopic != null) {
            mMeTopic.remListener(mMeTopicListener);
        }
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        // Enable options menu by returning true
        return true;
    }

    @Override
    public void handleMedia(Bundle args) {
        showFragment(FRAGMENT_AVATAR_PREVIEW, args);
    }

    void showFragment(String tag, Bundle args) {
        if (isFinishing() || isDestroyed()) {
            return;
        }

        final FragmentManager fm = getSupportFragmentManager();

        // Already on screen: nothing to do. Without this, syncBottomNav's
        // programmatic selection would bounce back through the tab listener and
        // re-create the fragment.
        Fragment visible = UiUtils.getVisibleFragment(fm);
        if (visible != null && tag.equals(visible.getTag()) && args == null) {
            resetTopLevelToolbar(tag);
            syncBottomNav(tag);
            return;
        }

        Fragment fragment = fm.findFragmentByTag(tag);
        if (fragment == null) {
            switch (tag) {
                case FRAGMENT_FIND:
                    fragment = new FindFragment();
                    break;
                case FRAGMENT_ACCOUNT_INFO:
                    fragment = new AccountInfoFragment();
                    break;
                case FRAGMENT_ACC_CREDENTIALS:
                    fragment = new AccCredFragment();
                    break;
                case FRAGMENT_ACC_HELP:
                    fragment = new AccHelpFragment();
                    break;
                case FRAGMENT_ACC_GENERAL:
                    fragment = new AccGeneralFragment();
                    break;
                case FRAGMENT_ACC_NOTIFICATIONS:
                    fragment = new AccNotificationsFragment();
                    break;
                case FRAGMENT_ACC_PERSONAL:
                    fragment = new AccPersonalFragment();
                    break;
                case FRAGMENT_AVATAR_PREVIEW:
                    fragment = new ImageViewFragment();
                    if (args == null) {
                        args = new Bundle();
                    }
                    args.putBoolean(AttachmentHandler.ARG_AVATAR, true);
                    break;
                case FRAGMENT_ACC_SECURITY:
                    fragment = new AccSecurityFragment();
                    break;
                case FRAGMENT_ACC_ABOUT:
                    fragment = new AccAboutFragment();
                    break;
                case FRAGMENT_ARCHIVE:
                case FRAGMENT_BANNED:
                    fragment = new ChatsFragment();
                    if (args == null) {
                        args = new Bundle();
                    }
                    args.putBoolean(tag, true);
                    break;
                case FRAGMENT_CHATLIST:
                    fragment = new ChatsFragment();
                    break;
                case FRAGMENT_WALLPAPERS:
                    fragment = new WallpaperFragment();
                    break;
                default:
                    throw new IllegalArgumentException("Failed to create fragment: unknown tag " + tag);
            }
        } else if (args == null) {
            // Retain old arguments.
            args = fragment.getArguments();
        }

        if (args != null) {
            if (fragment.getArguments() != null) {
                fragment.getArguments().putAll(args);
            } else {
                fragment.setArguments(args);
            }
        }

        FragmentTransaction trx = fm.beginTransaction();
        trx.replace(R.id.contentFragment, fragment, tag)
                .addToBackStack(tag)
                .setTransition(FragmentTransaction.TRANSIT_FRAGMENT_OPEN)
                .commit();

        resetTopLevelToolbar(tag);
        syncBottomNav(tag);
    }

    @Override
    public void toggleProgressIndicator(boolean on) {
        List<Fragment> fragments = getSupportFragmentManager().getFragments();
        for (Fragment f : fragments) {
            if (f instanceof UiUtils.ProgressIndicator && (f.isVisible() || !on)) {
                ((UiUtils.ProgressIndicator) f).toggleProgressIndicator(on);
            }
        }
    }

    @Override
    public void onAcceptAvatar(String topicName, Bitmap avatar) {
        if (isDestroyed() || isFinishing()) {
            return;
        }

        UiUtils.updateAvatar(Cache.getTinode().getMeTopic(), avatar);
    }

    interface FormUpdatable {
        void updateFormValues(final FragmentActivity activity, final MeTopic<VxCard> me);
    }

    // This is called on Websocket thread.
    private class MeListener extends UiUtils.MeEventListener {
        private void updateVisibleInfoFragment() {
            runOnUiThread(() -> {
                List<Fragment> fragments = getSupportFragmentManager().getFragments();
                for (Fragment f : fragments) {
                    if (f != null && f.isVisible() && f instanceof FormUpdatable) {
                        ((FormUpdatable) f).updateFormValues(ChatsActivity.this, mMeTopic);
                    }
                }
            });
        }

        @Override
        public void onInfo(MsgServerInfo info) {
            datasetChanged();
        }

        @Override
        public void onPres(MsgServerPres pres) {
            if ("msg".equals(pres.what)) {
                datasetChanged();
            } else if ("off".equals(pres.what) || "on".equals(pres.what)) {
                datasetChanged();
            }
        }

        @Override
        public void onMetaSub(final Subscription<VxCard, PrivateType> sub) {
            if (sub.deleted == null) {
                if (sub.pub != null) {
                    sub.pub.constructBitmap();
                }

                if (!UiUtils.isPermissionGranted(ChatsActivity.this, Manifest.permission.WRITE_CONTACTS)) {
                    // We can't save contact if we don't have appropriate permission.
                    return;
                }

                Tinode tinode = Cache.getTinode();
                if (mAccount == null) {
                    mAccount = Utils.getSavedAccount(AccountManager.get(ChatsActivity.this), tinode.getMyId());
                }
                if (Topic.isP2PType(sub.topic)) {
                    ContactsManager.processContact(ChatsActivity.this,
                            ChatsActivity.this.getContentResolver(), mAccount, tinode,
                            sub.pub, null, sub.getUnique(), sub.deleted != null,
                            null, false);
                }
            }
        }

        @Override
        public void onMetaDesc(final Description<VxCard, PrivateType> desc) {
            if (desc.pub != null) {
                desc.pub.constructBitmap();
            }

            updateVisibleInfoFragment();
        }

        @Override
        public void onSubsUpdated() {
            datasetChanged();
        }

        @Override
        public void onSubscriptionError(Exception ex) {
            runOnUiThread(() -> {
                Fragment fragment = UiUtils.getVisibleFragment(getSupportFragmentManager());
                if (fragment instanceof UiUtils.ProgressIndicator) {
                    ((UiUtils.ProgressIndicator) fragment).toggleProgressIndicator(false);
                }
            });
        }

        @Override
        public void onContUpdated(final String contact) {
            datasetChanged();
        }

        @Override
        public void onMetaTags(String[] tags) {
            updateVisibleInfoFragment();
        }

        @Override
        public void onCredUpdated(Credential[] cred) {
            updateVisibleInfoFragment();
        }
    }

    private class ContactsEventListener extends UiUtils.EventListener {
        ContactsEventListener(boolean online) {
            super(ChatsActivity.this, online);
        }

        @Override
        public void onLogin(int code, String txt) {
            super.onLogin(code, txt);
            UiUtils.attachMeTopic(ChatsActivity.this, mMeTopicListener);
        }

        @Override
        public void onDisconnect(boolean byServer, int code, String reason) {
            super.onDisconnect(byServer, code, reason);

            // Update online status of contacts.
            datasetChanged();
        }
    }
}