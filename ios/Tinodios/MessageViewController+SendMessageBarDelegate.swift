//
//  MessageViewController+SendMessageBarDelegate.swift
//  Tinodios
//
//  Copyright © 2019-2025 Tinode. All rights reserved.
//

import AVFoundation
import MobileCoreServices
import MobileVLCKit
import TinodeSDK
import UIKit
import UniformTypeIdentifiers

extension MessageViewController: SendMessageBarDelegate {
    // Default 256K server limit. Does not account for base64 compression and overhead.
    static let kMaxInbandAttachmentSize: Int64 = 1 << 18
    // Default upload size.
    static let kMaxAttachmentSize: Int64 = 1 << 23

    func sendMessageBar(sendText: String) {
        let content = Drafty(content: sendText)
        if !pendingMentions.isEmpty {
            attachMentions(to: content)
            pendingMentions = [:]
        }
        interactor?.sendMessage(content: content)
    }

    /// Convert "@Name" tokens for picked members into Drafty MN mention spans.
    /// Runs over the parsed document's text, not the raw input, because the
    /// markdown parser may have shifted offsets.
    private func attachMentions(to d: Drafty) {
        let chars = Array(d.txt)
        for (name, uid) in pendingMentions {
            let token = Array("@" + name)
            guard !token.isEmpty, chars.count >= token.count else { continue }
            var i = 0
            while i <= chars.count - token.count {
                if Array(chars[i..<(i + token.count)]) == token {
                    let boundaryBefore = i == 0 || chars[i - 1] == " " || chars[i - 1] == "\n"
                    let after = i + token.count
                    let boundaryAfter = after == chars.count || !(chars[after].isLetter || chars[after].isNumber)
                    if boundaryBefore && boundaryAfter {
                        if d.ent == nil { d.ent = [] }
                        if d.fmt == nil { d.fmt = [] }
                        let key = d.ent!.count
                        d.ent!.append(Entity(tp: "MN", data: ["val": .string(uid)]))
                        d.fmt!.append(Style(at: i, len: token.count, key: key))
                        i = after
                        continue
                    }
                }
                i += 1
            }
        }
    }

    /// Shows the member picker when "@" starts a word in a group chat.
    func maybeShowMentionPicker(for text: String) {
        guard let topic = topic, topic.isGrpType, presentedViewController == nil else { return }
        guard text.hasSuffix("@") else { return }
        if text.count >= 2 {
            // Mid-word @ (an email address, say) must not trigger the picker.
            let prev = text[text.index(text.endIndex, offsetBy: -2)]
            guard prev == " " || prev == "\n" else { return }
        }
        guard let subs = topic.getSubscriptions(), !subs.isEmpty else { return }

        let me = Cache.tinode.myUid
        let sheet = UIAlertController(title: NSLocalizedString("Mention", comment: "Mention picker title"),
                                      message: nil, preferredStyle: .actionSheet)
        var added = 0
        for sub in subs {
            guard let uid = sub.user, uid != me, let name = sub.pub?.fn, !name.isEmpty else { continue }
            sheet.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.pendingMentions[name] = uid
                // The field already holds the "@"; complete the token.
                self.sendMessageBar.inputField.insertText(name + " ")
            })
            added += 1
        }
        guard added > 0 else { return }
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sendMessageBar
            popover.sourceRect = sendMessageBar.bounds
        }
        present(sheet, animated: true)
    }

    func sendMessageBar(attachment: AttachmentKind) {
        switch attachment {
        case .document:
            attachFile(ofTypes: [.item, .image])
        case .audio:
            attachFile(ofTypes: [.audio])
        case .camera:
            imagePicker?.present(source: .camera, from: self.view)
        case .gallery:
            imagePicker?.present(source: .photoLibrary, from: self.view)
        }
    }

    private func attachFile(ofTypes types: [UTType]) {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        documentPicker.delegate = self
        documentPicker.modalPresentationStyle = .formSheet
        self.present(documentPicker, animated: true, completion: nil)
    }

    func sendMessageBar(textChangedTo text: String) {
        if self.sendTypingNotifications {
            interactor?.sendTypingNotification()
        }
        maybeShowMentionPicker(for: text)
    }

    func sendMessageBar(enablePeersMessaging: Bool) {
        if enablePeersMessaging {
            interactor?.enablePeersMessaging()
        }
    }

    func sendMessageBar(recordAudio action: AudioBarAction) {
        switch action {
        case .start:
            Cache.mediaRecorder.delegate = self
            Cache.mediaRecorder.start()
        case .stopAndSend:
            Cache.mediaRecorder.stop()
            currentAudioPlayer?.stop()
            currentAudioPlayer = nil
            if let recordURL = Cache.mediaRecorder.recordFileURL {
                sendAudioAttachment(url: recordURL, duration: Cache.mediaRecorder.duration!, preview: Cache.mediaRecorder.preview)
            }
        case .stopRecording:
            Cache.mediaRecorder.stop()
        case .pauseRecording:
            Cache.mediaRecorder.pause()
        case .stopAndDelete:
            Cache.mediaRecorder.stop(discard: true)
            currentAudioPlayer?.stop()
            currentAudioPlayer = nil
            (self.inputAccessoryView as! SendMessageBar).audioPlaybackAction(.playbackReset)
        case .playbackStart:
            if let recordURL = Cache.mediaRecorder.recordFileURL {
                currentAudioPlayer = VLCMediaPlayer()
                currentAudioPlayer!.delegate = self
                currentAudioPlayer!.media = VLCMedia(url: recordURL)
                currentAudioPlayer!.play()
                (self.inputAccessoryView as! SendMessageBar).audioPlaybackAction(.playbackStart)
            }
        case .playbackPause:
            currentAudioPlayer?.pause()
            (self.inputAccessoryView as! SendMessageBar).audioPlaybackAction(.playbackPause)
            break
        default:
            Cache.log.error("Unknown recording action")
        }
    }
}

extension MessageViewController: UIDocumentPickerDelegate {
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true, completion: nil)
        // NOTE(Apple's bug, Tinode's hack):
        // When UIDocumentPickerDelegate is dismissed it keeps the keyboard window
        // active. If then we show a toast, the keyboard window is counted "last"
        // in the window stack and we attempt to present the toast over it.
        // In reality, though, the window turns out at the bottom of the stack
        // and thus the toast ends up covered by the key window and never presented
        // to the user.
        // sendMessageBar.becomeFirstResponder() "fixes" the window stack.
        // This is UGLY because it pops the keyboard. Find a better solution.
        (self.inputAccessoryView as? SendMessageBar)?.inputField.becomeFirstResponder()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        // Convert file to Data and attach to message
        do {
            // See comment in documentPickerWasCancelled().
            (self.inputAccessoryView as? SendMessageBar)?.inputField.becomeFirstResponder()

            let bits = try Data(contentsOf: urls[0], options: .mappedIfSafe)
            let fname = urls[0].lastPathComponent
            var mimeType = Utils.mimeForUrl(url: urls[0])
            if mimeType == "application/json" {
                // Replace JSON mime type with 'application/octet-stream' to avoid collision with Drafty form responses.
                // Remove this code in 2026.
                mimeType = "application/octet-stream"
            }
            let maxAttachmentSize = Cache.tinode.getServerLimit(for: Tinode.kMaxFileUploadSize, withDefault: MessageViewController.kMaxAttachmentSize)
            guard bits.count <= maxAttachmentSize else {
                UiUtils.showToast(message: String(format: NSLocalizedString("The file size exceeds the limit %@", comment: "Error message"), UiUtils.bytesToHumanSize(maxAttachmentSize)))
                return
            }

            let pendingPreview = (self.inputAccessoryView as! SendMessageBar).pendingPreviewText
            let content = FilePreviewContent(
                data: bits,
                refUrl: urls[0],
                fileName: fname,
                contentType: mimeType,
                size: bits.count,
                pendingMessagePreview: pendingPreview
            )
            performSegue(withIdentifier: "ShowFilePreview", sender: content)
        } catch {
            Cache.log.error("MessageVC - failed to read file: %@", error.localizedDescription)
        }
    }
}

extension MessageViewController: ImagePickerDelegate {
    func didSelect(media: ImagePickerMediaType?) {
        guard let media = media else { return }
        switch media {
        case .image(let image, let mime, let fname):
            guard let image = image else { return }

            let width = Int(image.size.width * image.scale)
            let height = Int(image.size.height * image.scale)

            let pendingPreview = (self.inputAccessoryView as! SendMessageBar).pendingPreviewText
            let content = ImagePreviewContent(
                imgContent: ImagePreviewContent.ImageContent.uiimage(image),
                caption: nil,
                fileName: fname,
                contentType: mime,
                size: 0,
                width: width,
                height: height,
                pendingMessagePreview: pendingPreview)

            performSegue(withIdentifier: "ShowImagePreview", sender: content)
        case .video(let videoUrl, let mime, let fname):
            guard let videoUrl = videoUrl else { return }
            let pendingPreview = (self.inputAccessoryView as! SendMessageBar).pendingPreviewText
            let content = VideoPreviewContent(
                videoSrc: .local(videoUrl, nil),
                duration: 0,
                fileName: fname,
                contentType: mime,
                size: 0,
                width: nil,
                height: nil, caption: nil,
                pendingMessagePreview: pendingPreview)

            performSegue(withIdentifier: "ShowVideoPreview", sender: content)
        }
    }
}

extension MessageViewController: MediaRecorderDelegate {
    func didStartRecording(recorder: MediaRecorder) {
        /* do nothing */
    }

    func didFinishRecording(recorder: MediaRecorder, url: URL?, duration: TimeInterval) {
        (self.inputAccessoryView as! SendMessageBar).audioPlaybackPreview(recorder.preview, duration: duration)
    }

    func didUpdateRecording(recorder: MediaRecorder, amplitude: Float, atTime: TimeInterval) {
        let wave = (self.inputAccessoryView as! SendMessageBar).wavePreviewImageView
        wave?.put(amplitude: amplitude, atTime: atTime)
        (self.inputAccessoryView as! SendMessageBar).audioDurationLabel.text = atTime.asDurationString
    }

    func didFailRecording(recorder: MediaRecorder, _ error: Error) {
        if let err = error as? MediaRecorderError, err != .cancelledByUser {
            Cache.log.error("Recording failed: %@", error.localizedDescription)
            UiUtils.showToast(message: String(format: NSLocalizedString("Recording failed", comment: "Error message")))
        }
        (self.inputAccessoryView as! SendMessageBar).showAudioBar(.hidden)
    }
}

extension MessageViewController: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ notification: Notification) {
        guard let player = notification.object as? VLCMediaPlayer else { return }

        switch player.state {
        case .playing:
            // It's never called due to a bug: https://code.videolan.org/videolan/VLCKit/-/issues/129
            break
        case .opening, .paused, .buffering, .esAdded:
            break
        case .error:
            Cache.log.error("Playback failed")
            UiUtils.showToast(message: String(format: NSLocalizedString("Playback failed", comment: "Error message")))
            fallthrough
        case .stopped:
            fallthrough
        case .ended:
            (self.inputAccessoryView as! SendMessageBar).showAudioBar(.longPaused)
            (self.inputAccessoryView as! SendMessageBar).audioPlaybackAction(.playbackReset)
        default:
            break
        }
    }

    func mediaPlayerTimeChanged(_ notification: Notification) {
        /* do nothing */
    }
}

