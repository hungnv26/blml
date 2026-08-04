package co.tinode.tindroid;

import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;

import com.google.android.material.tabs.TabLayout;
import com.google.android.material.tabs.TabLayoutMediator;

import androidx.annotation.NonNull;
import androidx.fragment.app.Fragment;
import androidx.fragment.app.FragmentActivity;
import androidx.viewpager2.adapter.FragmentStateAdapter;
import androidx.viewpager2.widget.ViewPager2;

public class StartChatFragment extends Fragment {
    /** Intent extra naming the tab to open on, e.g. from Settings > My QR code. */
    public static final String EXTRA_TAB = "co.tinode.tindroid.START_CHAT_TAB";

    private static final int COUNT_OF_TABS = 3;
    private static final int TAB_SEARCH = 0;
    private static final int TAB_NEW_GROUP = 1;
    public static final int TAB_BY_ID = 2;

    private static final int[] TAB_NAMES = new int[] {R.string.find, R.string.group, R.string.by_id};

    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, ViewGroup container,
                             Bundle savedInstanceState) {
        return inflater.inflate(R.layout.fragment_create, container, false);
    }

    @Override
    public void onViewCreated(@NonNull View view, Bundle savedInstance) {
        final FragmentActivity activity = requireActivity();

        int initialTab = 0;
        if (savedInstance != null) {
            initialTab = savedInstance.getInt("activeTab");
        } else if (activity.getIntent() != null) {
            initialTab = activity.getIntent().getIntExtra(EXTRA_TAB, 0);
        }

        final TabLayout tabLayout = view.findViewById(R.id.tabsCreationOptions);
        final ViewPager2 viewPager = view.findViewById(R.id.tabPager);
        viewPager.setAdapter(new PagerAdapter(activity));
        new TabLayoutMediator(tabLayout, viewPager, (tab, position) -> tab.setText(TAB_NAMES[position])).attach();
        // Must come after attach(): the mediator resets the pager to page 0 when
        // it wires itself up, which is why the previous call here did nothing
        // (it was marked "no effect ... an Android bug").
        if (initialTab != 0) {
            viewPager.setCurrentItem(initialTab, false);
        }
    }

    @Override
    public void onSaveInstanceState(@NonNull Bundle outState) {
        super.onSaveInstanceState(outState);

        final FragmentActivity activity = requireActivity();

        final TabLayout tabLayout = activity.findViewById(R.id.tabsCreationOptions);
        if (tabLayout != null) {
            outState.putInt("activeTab", tabLayout.getSelectedTabPosition());
        }
    }

    private static class PagerAdapter extends FragmentStateAdapter {
        PagerAdapter(FragmentActivity fa) {
            super(fa);
        }

        @NonNull
        @Override
        public Fragment createFragment(int position) {
            return switch (position) {
                case TAB_SEARCH -> new FindFragment();
                case TAB_NEW_GROUP -> new CreateGroupFragment();
                case TAB_BY_ID -> new AddByIDFragment();
                default -> throw new IllegalArgumentException("Invalid TAB position " + position);
            };
        }

        @Override
        public int getItemCount() {
            return COUNT_OF_TABS;
        }
    }
}
