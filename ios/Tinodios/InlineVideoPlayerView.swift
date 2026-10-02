//
//  InlineVideoPlayerView.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import AVFoundation
import UIKit

protocol InlineVideoPlayerViewDelegate: AnyObject {
    /// The full-screen button was tapped; `time` is where playback was.
    func inlineVideoWantsFullScreen(_ view: InlineVideoPlayerView, url: URL, at time: CMTime)
    /// Playback reached the end or was stopped: the view should go away.
    func inlineVideoDidFinish(_ view: InlineVideoPlayerView)
    /// AVPlayer can't play this file (e.g. a WebM sent from a browser).
    func inlineVideoFailed(_ view: InlineVideoPlayerView)
}

/// Plays a video message in place, on top of its poster in the bubble — the
/// Telegram / Instagram feed behaviour: starts muted, a speaker button turns
/// sound on, a button goes full screen, tapping the video pauses / resumes.
/// When the clip ends the poster comes back.
class InlineVideoPlayerView: UIView {
    let url: URL
    /// Message seq and Drafty entity key this player belongs to.
    let seqId: Int
    let entityKey: Int
    weak var delegate: InlineVideoPlayerViewDelegate?

    private let player: AVPlayer
    private let playerLayer: AVPlayerLayer
    private let muteButton = UIButton(type: .custom)
    private let fullScreenButton = UIButton(type: .custom)
    private let pausedIcon = UIImageView(image: UIImage(systemName: "play.fill",
                                                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .bold)))
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let progress = UIProgressView(progressViewStyle: .bar)
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var waitingObservation: NSKeyValueObservation?

    init(url: URL, seqId: Int, entityKey: Int) {
        self.url = url
        self.seqId = seqId
        self.entityKey = entityKey
        self.player = AVPlayer(url: url)
        self.playerLayer = AVPlayerLayer(player: player)
        super.init(frame: .zero)

        backgroundColor = .black
        clipsToBounds = true
        layer.cornerRadius = 4
        isAccessibilityElement = false

        player.isMuted = true
        player.actionAtItemEnd = .pause
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)

        pausedIcon.tintColor = .white
        pausedIcon.alpha = 0.9
        pausedIcon.isHidden = true
        addSubview(pausedIcon)

        spinner.color = .white
        spinner.hidesWhenStopped = true
        addSubview(spinner)

        progress.progressTintColor = .white
        progress.trackTintColor = UIColor.white.withAlphaComponent(0.25)
        addSubview(progress)

        configure(muteButton, accessibility: NSLocalizedString("Sound", comment: "Accessibility: toggle video sound"))
        muteButton.addTarget(self, action: #selector(toggleMute), for: .touchUpInside)
        updateMuteIcon()
        configure(fullScreenButton, accessibility: NSLocalizedString("Full screen", comment: "Accessibility: play video full screen"))
        fullScreenButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right",
                                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)), for: .normal)
        fullScreenButton.addTarget(self, action: #selector(goFullScreen), for: .touchUpInside)

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] time in
            guard let self = self, let duration = self.player.currentItem?.duration, duration.isNumeric, duration.seconds > 0 else { return }
            self.progress.progress = Float(time.seconds / duration.seconds)
        }
        statusObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if item.status == .failed {
                    Cache.log.error("InlineVideo - can't play: %@", item.error?.localizedDescription ?? "unknown")
                    self.delegate?.inlineVideoFailed(self)
                }
            }
        }
        waitingObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                    self.spinner.startAnimating()
                } else {
                    self.spinner.stopAnimating()
                }
                self.pausedIcon.isHidden = player.timeControlStatus != .paused
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(playedToEnd(_:)),
                                               name: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        stop()
    }

    private func configure(_ button: UIButton, accessibility: String) {
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 15
        button.accessibilityLabel = accessibility
        addSubview(button)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        let size: CGFloat = 30
        let inset: CGFloat = 8
        muteButton.frame = CGRect(x: inset, y: bounds.height - size - inset - 3, width: size, height: size)
        fullScreenButton.frame = CGRect(x: bounds.width - size - inset, y: bounds.height - size - inset - 3, width: size, height: size)
        pausedIcon.sizeToFit()
        pausedIcon.center = CGPoint(x: bounds.midX, y: bounds.midY)
        spinner.center = pausedIcon.center
        progress.frame = CGRect(x: 0, y: bounds.height - 3, width: bounds.width, height: 3)
    }

    func play() {
        player.play()
    }

    /// A tap anywhere on the player: its buttons, or the picture (pause / resume).
    func handleTap(at point: CGPoint) {
        if muteButton.frame.insetBy(dx: -8, dy: -8).contains(point) {
            toggleMute()
        } else if fullScreenButton.frame.insetBy(dx: -8, dy: -8).contains(point) {
            goFullScreen()
        } else {
            togglePlayPause()
        }
    }

    /// Tap on the video itself.
    func togglePlayPause() {
        if player.timeControlStatus == .paused {
            player.play()
        } else {
            player.pause()
        }
    }

    func stop() {
        player.pause()
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObservation = nil
        waitingObservation = nil
        NotificationCenter.default.removeObserver(self)
    }

    var currentTime: CMTime { return player.currentTime() }

    @objc private func toggleMute() {
        player.isMuted.toggle()
        if !player.isMuted {
            // Sound was asked for explicitly: play it even with the silent switch on.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        }
        updateMuteIcon()
    }

    private func updateMuteIcon() {
        muteButton.setImage(UIImage(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)), for: .normal)
    }

    @objc private func goFullScreen() {
        player.pause()
        delegate?.inlineVideoWantsFullScreen(self, url: url, at: player.currentTime())
    }

    @objc private func playedToEnd(_ note: Notification) {
        delegate?.inlineVideoDidFinish(self)
    }
}
