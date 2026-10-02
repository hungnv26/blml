package co.tinode.tindroid;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.TextUtils;
import android.util.Log;
import android.view.View;
import android.view.ViewParent;
import android.webkit.MimeTypeMap;
import android.widget.Toast;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.net.MalformedURLException;
import java.net.URL;
import java.util.concurrent.Executors;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.content.FileProvider;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;

import co.tinode.tinodesdk.LargeFileHelper;
import co.tinode.tinodesdk.Tinode;

/**
 * Shared chrome for the full-screen image and video viewers: no app bar, no system bars,
 * black background, a small overlay with Back / Share / Save. File name, type and size are
 * never shown.
 */
final class MediaViewer {
    private static final String TAG = "MediaViewer";
    private static final String FILE_PROVIDER = "co.tinode.tindroid.provider";
    // Subfolder of the cache dir exposed through FileProvider for sharing (provider_paths.xml).
    private static final String SHARE_DIR = "shared";

    private MediaViewer() {}

    /** Hide the activity's app bar and the system bars. */
    static void enter(@NonNull Activity activity) {
        View appBar = appBar(activity);
        if (appBar != null) {
            appBar.setVisibility(View.GONE);
        }
        WindowInsetsControllerCompat ctrl = WindowCompat.getInsetsController(activity.getWindow(),
                activity.getWindow().getDecorView());
        ctrl.setSystemBarsBehavior(WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
        ctrl.hide(WindowInsetsCompat.Type.systemBars());
    }

    /** Undo {@link #enter(Activity)}. */
    static void exit(@NonNull Activity activity) {
        View appBar = appBar(activity);
        if (appBar != null) {
            appBar.setVisibility(View.VISIBLE);
        }
        WindowCompat.getInsetsController(activity.getWindow(), activity.getWindow().getDecorView())
                .show(WindowInsetsCompat.Type.systemBars());
    }

    @Nullable
    private static View appBar(@NonNull Activity activity) {
        View toolbar = activity.findViewById(R.id.toolbar);
        if (toolbar == null) {
            return null;
        }
        ViewParent parent = toolbar.getParent();
        // toolbar.xml wraps the Toolbar into an AppBarLayout together with the offline indicator.
        return parent instanceof com.google.android.material.appbar.AppBarLayout ? (View) parent : toolbar;
    }

    /** Keep the overlay bar clear of a camera cut-out once the status bar is hidden. */
    static void avoidCutout(@NonNull View bar) {
        bar.post(() -> {
            WindowInsetsCompat wi = ViewCompat.getRootWindowInsets(bar);
            int top = 0;
            if (wi != null) {
                Insets cut = wi.getInsets(WindowInsetsCompat.Type.displayCutout());
                top = cut.top;
            }
            bar.setPadding(bar.getPaddingLeft(), top, bar.getPaddingRight(), bar.getPaddingBottom());
        });
    }

    /** Share a bitmap shown in the viewer. */
    static void shareBitmap(@NonNull Activity activity, @Nullable Bitmap bmp, @Nullable String mime,
                            @Nullable String fileName) {
        if (bmp == null) {
            Toast.makeText(activity, R.string.action_failed, Toast.LENGTH_SHORT).show();
            return;
        }
        boolean png = "image/png".equals(mime);
        File file = shareFile(activity, fileName, png ? ".png" : ".jpg");
        try (OutputStream out = new FileOutputStream(file)) {
            bmp.compress(png ? Bitmap.CompressFormat.PNG : Bitmap.CompressFormat.JPEG, 95, out);
        } catch (IOException ex) {
            Log.w(TAG, "Failed to write image for sharing", ex);
            Toast.makeText(activity, R.string.action_failed, Toast.LENGTH_SHORT).show();
            return;
        }
        startShare(activity, file, png ? "image/png" : "image/jpeg");
    }

    /**
     * Share a received attachment: inline bytes are written out, an out-of-band file is fetched
     * from the server first (with auth headers only for the BLML host).
     */
    static void shareAttachment(@NonNull Activity activity, @NonNull Bundle args, @NonNull String defaultMime) {
        String mime = args.getString(AttachmentHandler.ARG_MIME_TYPE);
        if (TextUtils.isEmpty(mime)) {
            mime = defaultMime;
        }
        String ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime);
        final File file = shareFile(activity, args.getString(AttachmentHandler.ARG_FILE_NAME),
                TextUtils.isEmpty(ext) ? "" : "." + ext);
        final String finalMime = mime;

        Bundle cached = Cache.getDataBundle(args.getString("cache_id"), false);
        Bundle source = cached != null ? cached : args;
        final byte[] bits = source.getByteArray(AttachmentHandler.ARG_SRC_BYTES);
        if (bits != null) {
            try (OutputStream out = new FileOutputStream(file)) {
                out.write(bits);
            } catch (IOException ex) {
                Log.w(TAG, "Failed to write attachment for sharing", ex);
                Toast.makeText(activity, R.string.action_failed, Toast.LENGTH_SHORT).show();
                return;
            }
            startShare(activity, file, finalMime);
            return;
        }

        Uri ref = args.getParcelable(AttachmentHandler.ARG_REMOTE_URI);
        if (ref == null) {
            Toast.makeText(activity, R.string.action_failed, Toast.LENGTH_SHORT).show();
            return;
        }
        final Tinode tinode = Cache.getTinode();
        final String url;
        try {
            url = new URL(tinode.getBaseUrl(), ref.toString()).toString();
        } catch (MalformedURLException ex) {
            Toast.makeText(activity, R.string.action_failed, Toast.LENGTH_SHORT).show();
            return;
        }
        Toast.makeText(activity, R.string.preparing_to_share, Toast.LENGTH_SHORT).show();
        final LargeFileHelper lfh = tinode.getLargeFileHelper();
        final Handler main = new Handler(Looper.getMainLooper());
        Executors.newSingleThreadExecutor().execute(() -> {
            boolean ok;
            try (OutputStream out = new FileOutputStream(file)) {
                ok = lfh.download(url, out, null) > 0;
            } catch (Exception ex) {
                Log.w(TAG, "Failed to fetch attachment for sharing", ex);
                ok = false;
            }
            final boolean success = ok;
            main.post(() -> {
                if (activity.isFinishing() || activity.isDestroyed()) {
                    return;
                }
                if (success) {
                    startShare(activity, file, finalMime);
                } else {
                    Toast.makeText(activity, R.string.action_failed, Toast.LENGTH_SHORT).show();
                }
            });
        });
    }

    private static File shareFile(Context context, @Nullable String fileName, String ext) {
        File dir = new File(context.getCacheDir(), SHARE_DIR);
        if (!dir.exists() && !dir.mkdirs()) {
            Log.w(TAG, "Failed to create " + dir);
        }
        String name = fileName != null ? fileName.trim().replaceAll("[\\\\/:*?\"<>|]", "_") : "";
        if (TextUtils.isEmpty(name)) {
            name = "BLML_" + System.currentTimeMillis();
        }
        if (!TextUtils.isEmpty(ext) && !name.toLowerCase().endsWith(ext.toLowerCase())) {
            name += ext;
        }
        return new File(dir, name);
    }

    private static void startShare(Activity activity, File file, String mime) {
        Uri uri = FileProvider.getUriForFile(activity, FILE_PROVIDER, file);
        Intent send = new Intent(Intent.ACTION_SEND);
        send.setType(mime);
        send.putExtra(Intent.EXTRA_STREAM, uri);
        send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        try {
            activity.startActivity(Intent.createChooser(send, activity.getString(R.string.action_share)));
        } catch (ActivityNotFoundException ex) {
            Toast.makeText(activity, R.string.action_failed, Toast.LENGTH_SHORT).show();
        }
    }
}
