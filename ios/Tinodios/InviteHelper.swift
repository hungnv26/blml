//
//  InviteHelper.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import TinodiosDB
import UIKit

/// Builds and presents the "Invite a friend" share message.
///
/// BLML is invite-only, so an invitation is useless without three things: the
/// app, the server address, and the registration code. Sending them together is
/// the whole point of this feature — a bare "install BLML" leaves the recipient
/// stuck at a 403 on the signup screen.
public class InviteHelper {

    /// Where a newcomer downloads the app. No public listing yet, so this stays
    /// a plain instruction rather than a dead App Store link.
    private static let kInstallInstructions =
        NSLocalizedString("Ask me for the app install link.",
                          comment: "Invite message: how to get the app")

    /// The invite text. `code` is omitted entirely when unknown, rather than
    /// printed as an empty line the recipient would puzzle over.
    public static func inviteText() -> String {
        let (host, tls) = SharedUtils.getConnectionSettings()
        let server = host ?? SharedUtils.kDefaultHostName
        let scheme = (tls ?? false) ? "https://" : "http://"

        var lines = [
            NSLocalizedString("Join me on BLML — our private group chat.",
                              comment: "Invite message: opening line"),
            "",
            "1. " + kInstallInstructions,
            "2. " + String(format: NSLocalizedString("Server: %@", comment: "Invite message: server address"),
                           scheme + server)
        ]

        if let code = SharedUtils.getInviteCode() {
            lines.append("3. " + String(format: NSLocalizedString("Invite code: %@",
                                                                 comment: "Invite message: registration code"), code))
        } else {
            // Better to say the code is needed than to let them hit a 403 and
            // assume the server is broken.
            lines.append("3. " + NSLocalizedString("You'll need an invite code — ask me for it.",
                                                   comment: "Invite message: code unknown"))
        }

        return lines.joined(separator: "\n")
    }

    /// True when the code is known, so callers can offer to fill it in.
    public static var hasInviteCode: Bool {
        return SharedUtils.getInviteCode() != nil
    }

    /// Presents the system share sheet with the invite text.
    /// `sourceView` positions the popover on iPad, where a share sheet without
    /// an anchor crashes.
    public static func share(from controller: UIViewController, sourceView: UIView?) {
        let sheet = UIActivityViewController(activityItems: [inviteText()], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView ?? controller.view
            popover.sourceRect = (sourceView ?? controller.view).bounds
            popover.permittedArrowDirections = [.up, .down]
        }
        controller.present(sheet, animated: true)
    }

    /// Lets the user record the invite code when the app never saw it — an
    /// account created on another device, or before the code was stored.
    public static func promptForCode(from controller: UIViewController, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(
            title: NSLocalizedString("Invite code", comment: "Alert title"),
            message: NSLocalizedString("The code new members type when signing up. It is stored on this device only.",
                                       comment: "Alert message"),
            preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = NSLocalizedString("Invite code", comment: "Text field placeholder")
            field.text = SharedUtils.getInviteCode()
            field.autocapitalizationType = .allCharacters
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Save", comment: "Alert action"), style: .default) { _ in
            let code = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            SharedUtils.setInviteCode(code)
            completion?()
        })
        controller.present(alert, animated: true)
    }
}
