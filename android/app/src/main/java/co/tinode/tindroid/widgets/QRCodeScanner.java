package co.tinode.tindroid.widgets;

import android.app.Activity;
import android.media.Image;
import android.text.TextUtils;
import android.util.Log;

import com.google.common.util.concurrent.ListenableFuture;
import com.google.mlkit.vision.barcode.BarcodeScanner;
import com.google.mlkit.vision.barcode.BarcodeScannerOptions;
import com.google.mlkit.vision.barcode.BarcodeScanning;
import com.google.mlkit.vision.barcode.common.Barcode;
import com.google.mlkit.vision.common.InputImage;

import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import androidx.annotation.NonNull;
import androidx.annotation.OptIn;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ExperimentalGetImage;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.Preview;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.content.ContextCompat;
import androidx.lifecycle.LifecycleOwner;

public class QRCodeScanner {
    private final static String TAG = "QRCodeScanner";
    private final Activity mParent;
    private final SuccessListener mSuccessListener;

    private final ExecutorService mQRCodeAnalysisExecutor = Executors.newSingleThreadExecutor();
    private final BarcodeScannerOptions mBarcodeScannerOptions =
            new BarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build();
    private boolean mIsCameraActive = false;
    private boolean mIsScanning = false;
    private volatile BarcodeScanner mScanner = null;
    ProcessCameraProvider mCameraProvider = null;

    public QRCodeScanner(@NonNull Activity context, @NonNull SuccessListener listener) {
        mParent = context;
        mSuccessListener = listener;
    }

    public void startCamera(final LifecycleOwner lifecycleOwner, PreviewView previewView) {
        if (mIsCameraActive) {
            return;
        }

        mIsCameraActive = true;
        mScanner = BarcodeScanning.getClient(mBarcodeScannerOptions);

        final ListenableFuture<ProcessCameraProvider> cameraProviderFuture =
                ProcessCameraProvider.getInstance(mParent);
        cameraProviderFuture.addListener(
                () -> {
                    try {
                        mCameraProvider = cameraProviderFuture.get();
                        Preview.Builder builder = new Preview.Builder();
                        Preview previewUseCase = builder.build();
                        previewUseCase.setSurfaceProvider(previewView.getSurfaceProvider());
                        mCameraProvider.unbindAll();
                        ImageAnalysis analysisUseCase = new ImageAnalysis.Builder().build();
                        analysisUseCase.setAnalyzer(mQRCodeAnalysisExecutor, this::scanBarcodes);
                        mCameraProvider.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA,
                                previewUseCase, analysisUseCase);
                    } catch (ExecutionException | IllegalArgumentException | InterruptedException e) {
                        Log.e(TAG, "Unable to initialize camera", e);
                    }
                },
                ContextCompat.getMainExecutor(mParent));
    }

    public void stopCamera() {
        if (!mIsCameraActive) {
            return;
        }

        mIsCameraActive = false;
        if (mCameraProvider != null) {
            mCameraProvider.unbindAll();
        }
        BarcodeScanner scanner = mScanner;
        mScanner = null;
        if (scanner != null) {
            scanner.close();
        }
    }

    @OptIn(markerClass = ExperimentalGetImage.class)
    private void scanBarcodes(final ImageProxy imageProxy) {
        Image mediaImage = imageProxy.getImage();
        if (mediaImage == null || mIsScanning || !mIsCameraActive) {
            imageProxy.close();
            return;
        }

        InputImage image = InputImage.fromMediaImage(mediaImage,
                imageProxy.getImageInfo().getRotationDegrees());
        BarcodeScanner scanner = mScanner;
        if (scanner == null) {
            imageProxy.close();
            return;
        }
        mIsScanning = true;
        scanner.process(image)
                .addOnSuccessListener(barcodes -> {
                    imageProxy.close();
                    mIsScanning = false;
                    for (Barcode barcode: barcodes) {
                        String rawValue = barcode.getRawValue();
                        if (rawValue == null) {
                            continue;
                        }
                        // Codes from iOS carry "tinode:topic/", ones from older
                        // Android builds "tinode:id/".
                        String id = co.tinode.tindroid.UiUtils.topicFromQrCode(rawValue);
                        if (!TextUtils.isEmpty(id)) {
                            mSuccessListener.onScanSuccessful(id);
                            break;
                        }
                    }
                })
                .addOnFailureListener(e -> {
                    imageProxy.close();
                    mIsScanning = false;
                    Log.w(TAG, "Scanner error", e);
                });
    }

    public interface SuccessListener {
        void onScanSuccessful(String id);
    }
}
