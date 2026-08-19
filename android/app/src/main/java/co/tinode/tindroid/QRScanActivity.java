package co.tinode.tindroid;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.widget.Toast;

import com.google.mlkit.vision.barcode.BarcodeScannerOptions;
import com.google.mlkit.vision.barcode.BarcodeScanning;
import com.google.mlkit.vision.barcode.common.Barcode;
import com.google.mlkit.vision.common.InputImage;

import java.io.IOException;
import java.util.List;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.PickVisualMediaRequest;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;
import androidx.camera.view.PreviewView;
import androidx.core.content.ContextCompat;

import co.tinode.tindroid.widgets.QRCodeScanner;

/**
 * Full-screen QR scanner reachable straight from the chat list, the way Zalo
 * and WeChat surface theirs. Scans live with the camera, or decodes a code
 * from a picture already on the device — the case where the code arrived over
 * chat and there is no second device to point the camera at.
 */
public class QRScanActivity extends AppCompatActivity {
    private QRCodeScanner mQrScanner;
    private PreviewView mCameraPreview;

    private final ActivityResultLauncher<String> mRequestPermissionLauncher =
            registerForActivityResult(new ActivityResultContracts.RequestPermission(), isGranted -> {
                if (isGranted) {
                    mQrScanner.startCamera(this, mCameraPreview);
                }
                // Denied: the screen still works through "Scan from photo".
            });

    // The system photo picker runs out of process: no storage permission needed.
    private final ActivityResultLauncher<PickVisualMediaRequest> mPhotoPickerLauncher =
            registerForActivityResult(new ActivityResultContracts.PickVisualMedia(), uri -> {
                if (uri != null) {
                    decodeFromImage(uri);
                }
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_qr_scan);
        setTitle(R.string.scan_qr_code);

        mCameraPreview = findViewById(R.id.cameraPreviewView);
        mQrScanner = new QRCodeScanner(this, UiUtils.TOPIC_URI_PREFIX, this::goToTopic);

        findViewById(R.id.scanFromPhoto).setOnClickListener(v ->
                mPhotoPickerLauncher.launch(new PickVisualMediaRequest.Builder()
                        .setMediaType(ActivityResultContracts.PickVisualMedia.ImageOnly.INSTANCE)
                        .build()));

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED) {
            mQrScanner.startCamera(this, mCameraPreview);
        } else {
            mRequestPermissionLauncher.launch(Manifest.permission.CAMERA);
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (mQrScanner != null) {
            mQrScanner.stopCamera();
        }
    }

    private void decodeFromImage(Uri uri) {
        final InputImage image;
        try {
            image = InputImage.fromFilePath(this, uri);
        } catch (IOException ex) {
            Toast.makeText(this, R.string.image_read_failed, Toast.LENGTH_SHORT).show();
            return;
        }
        BarcodeScanning.getClient(new BarcodeScannerOptions.Builder()
                        .setBarcodeFormats(Barcode.FORMAT_QR_CODE).build())
                .process(image)
                .addOnSuccessListener(barcodes -> {
                    String id = firstTopicId(barcodes);
                    if (id != null) {
                        goToTopic(id);
                    } else {
                        Toast.makeText(this, R.string.qr_code_not_found, Toast.LENGTH_SHORT).show();
                    }
                })
                .addOnFailureListener(e ->
                        Toast.makeText(this, R.string.qr_code_not_found, Toast.LENGTH_SHORT).show());
    }

    private static String firstTopicId(List<Barcode> barcodes) {
        for (Barcode barcode : barcodes) {
            String id = UiUtils.topicFromQrCode(barcode.getRawValue());
            if (id != null) {
                return id;
            }
        }
        return null;
    }

    private void goToTopic(String id) {
        Intent it = new Intent(this, MessageActivity.class);
        it.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        it.putExtra(Const.INTENT_EXTRA_TOPIC, id);
        startActivity(it);
        finish();
    }
}
