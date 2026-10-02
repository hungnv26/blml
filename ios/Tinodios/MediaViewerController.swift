//
//  MediaViewerController.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import AVKit
import Kingfisher
import TinodeSDK
import UIKit

/// Full-screen viewer for a received picture, the way Photos / WhatsApp show
/// one: black background, the picture fills the screen, pinch or double-tap to
/// zoom, swipe down to close. The only chrome is a close and a share button,
/// and a single tap hides even those. No title, no file details.
class ImageViewerController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let bits: Data?
    private let ref: String?
    private let placeholder: UIImage?

    /// Called once the viewer is gone (closed with the button or swiped away).
    var onDismiss: (() -> Void)?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let closeButton = ImageViewerController.makeOverlayButton(
        systemName: "xmark", label: NSLocalizedString("Close", comment: "Accessibility: close the image viewer"))
    private let shareButton = ImageViewerController.makeOverlayButton(
        systemName: "square.and.arrow.up", label: NSLocalizedString("Share", comment: "Accessibility: share the picture"))
    private var overlayHidden = false
    private var loadedFullImage = false

    init(bits: Data?, ref: String?, placeholder: UIImage?) {
        self.bits = bits
        self.ref = ref
        self.placeholder = placeholder
        super.init(nibName: nil, bundle: nil)
        // Over full screen so the chat shows through while swiping the picture away.
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        modalPresentationCapturesStatusBarAppearance = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var prefersStatusBarHidden: Bool { return overlayHidden }
    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }
    override var prefersHomeIndicatorAutoHidden: Bool { return overlayHidden }
    // Taking first responder keeps the chat's composer (the presenting screen's
    // input accessory view, drawn above everything) off the picture.
    override var canBecomeFirstResponder: Bool { return true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = NSLocalizedString("Picture", comment: "Accessibility: the picture in the viewer")
        scrollView.addSubview(imageView)

        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        shareButton.isEnabled = false
        view.addSubview(closeButton)
        view.addSubview(shareButton)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            closeButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            shareButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            shareButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16)
        ])

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)

        loadImage()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            onDismiss?()
            onDismiss = nil
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if scrollView.zoomScale <= scrollView.minimumZoomScale {
            layoutImage()
        }
    }

    // MARK: - Image

    private func loadImage() {
        if let bits = bits, let image = UIImage(data: bits) {
            show(image, final: true)
            return
        }
        if let placeholder = placeholder {
            show(placeholder, final: false)
        }
        guard let ref = ref, let url = URL(string: ref, relativeTo: Cache.tinode.baseURL(useWebsocketProtocol: false)) else {
            if placeholder == nil {
                show(UiUtils.placeholderImage(named: "image-broken", withBackground: nil, width: 96, height: 96), final: false)
            }
            return
        }
        spinner.startAnimating()
        let modifier = AnyModifier { request in
            var request = request
            LargeFileHelper.addCommonHeaders(to: &request, using: Cache.tinode)
            return request
        }
        KingfisherManager.shared.retrieveImage(with: url.downloadURL, options: [.requestModifier(modifier)]) { [weak self] result in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            switch result {
            case .success(let value):
                self.show(value.image, final: true)
            case .failure(let error):
                Cache.log.info("ImageViewer - failed to download '%@': %d", url.absoluteString, error.errorCode)
                if self.placeholder == nil {
                    self.show(UiUtils.placeholderImage(named: "image-broken", withBackground: nil, width: 96, height: 96), final: false)
                }
                UiUtils.showToast(message: NSLocalizedString("Couldn't load the picture.", comment: "Toast: image download failed"))
            }
        }
    }

    private func show(_ image: UIImage, final: Bool) {
        imageView.image = image
        loadedFullImage = final
        shareButton.isEnabled = final
        scrollView.zoomScale = scrollView.minimumZoomScale
        layoutImage()
    }

    /// Fits the picture to the screen and centers it.
    private func layoutImage() {
        guard let size = imageView.image?.size, size.width > 0, size.height > 0 else { return }
        let bounds = scrollView.bounds.size
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        imageView.frame = CGRect(origin: .zero, size: fitted)
        scrollView.contentSize = fitted
        centerImage()
    }

    private func centerImage() {
        let bounds = scrollView.bounds.size
        let content = imageView.frame.size
        let dx = max(0, (bounds.width - content.width) / 2)
        let dy = max(0, (bounds.height - content.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    // MARK: - Gestures

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }
        let point = gesture.location(in: imageView)
        let scale = min(scrollView.maximumZoomScale, 2.5)
        let width = scrollView.bounds.width / scale
        let height = scrollView.bounds.height / scale
        scrollView.zoom(to: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height), animated: true)
    }

    @objc private func handleSingleTap() {
        setOverlay(hidden: !overlayHidden)
    }

    private func setOverlay(hidden: Bool) {
        overlayHidden = hidden
        UIView.animate(withDuration: 0.2) {
            self.closeButton.alpha = hidden ? 0 : 1
            self.shareButton.alpha = hidden ? 0 : 1
            self.setNeedsStatusBarAppearanceUpdate()
        }
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Swipe-to-close only for a mostly vertical drag on an unzoomed picture;
        // a zoomed picture pans instead.
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        guard scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 else { return false }
        let velocity = pan.velocity(in: view)
        return abs(velocity.y) > abs(velocity.x)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // The scroll view's own pan sees the same drag; at 1x it has nothing to scroll.
        return other === scrollView.panGestureRecognizer
    }

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let progress = min(1, abs(translation.y) / 400)
        switch gesture.state {
        case .changed:
            imageView.transform = CGAffineTransform(translationX: translation.x * 0.3, y: translation.y)
            view.backgroundColor = UIColor.black.withAlphaComponent(1 - progress * 0.8)
            closeButton.alpha = overlayHidden ? 0 : 1 - progress * 2
            shareButton.alpha = closeButton.alpha
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: view).y
            if gesture.state == .ended && (abs(translation.y) > 120 || abs(velocity) > 900) {
                let direction: CGFloat = (translation.y == 0 ? velocity : translation.y) < 0 ? -1 : 1
                UIView.animate(withDuration: 0.2, animations: {
                    self.imageView.transform = CGAffineTransform(translationX: 0, y: direction * self.view.bounds.height)
                    self.view.backgroundColor = .clear
                    self.closeButton.alpha = 0
                    self.shareButton.alpha = 0
                }, completion: { _ in
                    self.dismiss(animated: false)
                })
            } else {
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [], animations: {
                    self.imageView.transform = .identity
                    self.view.backgroundColor = .black
                    self.closeButton.alpha = self.overlayHidden ? 0 : 1
                    self.shareButton.alpha = self.closeButton.alpha
                })
            }
        default:
            break
        }
    }

    // MARK: - Buttons

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func shareTapped() {
        guard loadedFullImage, let image = imageView.image else { return }
        let share = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = shareButton
        share.popoverPresentationController?.sourceRect = shareButton.bounds
        present(share, animated: true)
    }

    /// Round translucent button that reads on any picture, light or dark.
    static func makeOverlayButton(systemName: String, label: String) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        button.layer.cornerRadius = 22
        button.accessibilityLabel = label
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44)
        ])
        return button
    }
}

/// Where a video message's bytes come from: a server reference (streamed with
/// the session's credentials) or data carried inside the message.
enum VideoSourceResolver {
    static func playableURL(bits: Data?, ref: String?, mime: String?) -> URL? {
        if let ref = ref, let url = URL(string: ref, relativeTo: Cache.tinode.baseURL(useWebsocketProtocol: false)) {
            return Cache.tinode.addAuthQueryParams(url)
        }
        guard let bits = bits, !bits.isEmpty else { return nil }
        // AVPlayer needs a file with a known extension for in-message data.
        let ext: String
        switch mime?.lowercased() {
        case "video/quicktime": ext = "mov"
        case "video/webm": ext = "webm"
        case "video/3gpp": ext = "3gp"
        default: ext = "mp4"
        }
        let name = "inline-video-\(bits.hashValue).\(ext)"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: file.path) {
            do {
                try bits.write(to: file)
            } catch {
                Cache.log.error("Video - failed to stage inline video: %@", error.localizedDescription)
                return nil
            }
        }
        return file
    }
}

/// Full-screen video: the system player (AVPlayerViewController) with its own
/// close button, scrubber, AirPlay and swipe-down to close. No titles or file
/// details. (Not subclassed: Apple doesn't support subclassing it, and a
/// subclass lost the close button's dismissal.)
enum FullScreenVideo {
    static func present(url: URL, from presenter: UIViewController, startAt time: CMTime = .zero) {
        let player = AVPlayer(url: url)
        player.isMuted = false
        let vc = AVPlayerViewController()
        vc.player = player
        vc.modalPresentationStyle = .fullScreen
        vc.overrideUserInterfaceStyle = .dark
        // Play with sound even with the silent switch on, as the system players do.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        presenter.present(vc, animated: true) {
            if time.isValid && time.seconds > 0 {
                player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            player.play()
        }
    }
}
