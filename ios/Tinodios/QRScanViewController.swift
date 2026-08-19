//
//  QRScanViewController.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import PhotosUI
import TinodeSDK
import TinodiosDB
import UIKit

/// Full-screen QR scanner reachable straight from the chat list, the way Zalo
/// and WeChat surface theirs. Scans live with the camera, or decodes a code
/// from a picture already in the photo library — the case where the code was
/// sent over chat and there is no second device to point the camera at.
class QRScanViewController: UIViewController {
    private var qrScanner: QRScanner?
    private let cameraPreviewView = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("Scan QR code", comment: "Screen title")
        view.backgroundColor = .black

        cameraPreviewView.frame = view.bounds
        cameraPreviewView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(cameraPreviewView)

        // "From photo" pill along the bottom, clear of the home indicator.
        var config = UIButton.Configuration.filled()
        config.title = NSLocalizedString("Scan from photo", comment: "Button: pick an image with a QR code from the photo library")
        config.image = UIImage(systemName: "photo.on.rectangle")
        config.imagePadding = 8
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        let photoButton = UIButton(configuration: config)
        photoButton.addTarget(self, action: #selector(pickPhoto), for: .touchUpInside)
        photoButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(photoButton)
        NSLayoutConstraint.activate([
            photoButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            photoButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if qrScanner == nil {
            // No prefix filter here: handleScanned() accepts both the canonical
            // prefix and the legacy Android "tinode:id/" form.
            qrScanner = QRScanner(embedIn: cameraPreviewView, expectedCodePrefix: nil, delegate: self)
        }
        qrScanner?.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        qrScanner?.stop()
    }

    // MARK: - Scan from a saved image

    @objc private func pickPhoto() {
        // PHPicker runs out of process, so no photo-library permission prompt.
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    /// Finds a QR code in a still image. CIDetector rather than Vision: it is
    /// available everywhere the app runs and one QR code in a photo is well
    /// within its ability.
    private static func qrCode(in image: UIImage) -> String? {
        guard let ciImage = CIImage(image: image),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else {
            return nil
        }
        let features = detector.features(in: ciImage)
        for case let feature as CIQRCodeFeature in features {
            if let message = feature.messageString {
                return message
            }
        }
        return nil
    }

    // MARK: - Handling a code from either source

    private func handleScanned(raw: String?) {
        // Accepts "tinode:topic/<id>" (canonical, shared with web) and
        // "tinode:id/<id>" (codes from older Android builds).
        guard let id = Utils.topicFromQrCode(raw) else {
            UiUtils.showToast(message: NSLocalizedString("Not a valid BLML QR code", comment: "Toast error"))
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
                self?.qrScanner?.start()
            }
            return
        }
        openTopic(id: id)
    }

    private func openTopic(id: String) {
        // This screen is one tap from a cold start, so the login handshake may
        // still be in flight; getMeta then 401s. When already authenticated go
        // straight to the lookup — connectAndLoginSync reports failure on an
        // open socket ("already connected"), so it is only the cold-start path.
        if Cache.tinode.isConnectionAuthenticated {
            fetchAndOpenTopic(id: id)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loggedIn = SharedUtils.connectAndLoginSync(using: Cache.tinode, inBackground: false)
                || Cache.tinode.isConnectionAuthenticated
            DispatchQueue.main.async {
                guard loggedIn else {
                    UiUtils.showToast(message: NSLocalizedString("Not connected to server", comment: "Toast error"))
                    self?.qrScanner?.start()
                    return
                }
                self?.fetchAndOpenTopic(id: id)
            }
        }
    }

    private func fetchAndOpenTopic(id: String) {
        let getMeta = MsgGetMeta(desc: MetaGetDesc(), sub: nil, data: nil, del: nil, tags: false, cred: false)
        Cache.tinode.getMeta(topic: id, query: getMeta).then(
            onSuccess: { [weak self] msg in
                if let desc = msg?.meta?.desc as? Description<TheCard, PrivateType> {
                    ContactsManager.default.processDescription(uid: id, desc: desc)
                }
                self?.presentChatReplacingCurrentVC(with: id)
                return nil
            },
            onFailure: { [weak self] err in
                DispatchQueue.main.async {
                    UiUtils.showToast(message: NSLocalizedString("Could not find that user or group", comment: "Toast error"))
                    self?.qrScanner?.start()
                }
                Cache.log.info("QR scan: topic lookup failed: %@", err.localizedDescription)
                return nil
            })
    }
}

extension QRScanViewController: QRScannerDelegate {
    func qrScanner(didScanCode codeValue: String?) {
        // The scanner has no prefix filter, so the raw payload arrives here and
        // goes through the same validation as photo-library scans.
        handleScanned(raw: codeValue)
    }
}

extension QRScanViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else {
            return
        }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            DispatchQueue.main.async {
                guard let image = object as? UIImage else {
                    UiUtils.showToast(message: NSLocalizedString("Could not read that image", comment: "Toast error"))
                    return
                }
                self?.handleScanned(raw: QRScanViewController.qrCode(in: image))
            }
        }
    }
}
