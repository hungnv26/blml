//
//  ContactsConsent.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import UIKit
import TinodiosDB

/// Explains the contacts upload, immediately before the system prompt.
///
/// Two review rules meet here and only one shape satisfies both. 5.1.2 wants
/// the upload explained and agreed to before it happens — the system prompt
/// is a single sentence and cannot say what the server does with the data.
/// 5.1.1(iv) forbids letting that explanation *delay* the system prompt: a
/// pre-prompt with a "Not now" button was rejected, because the decision
/// belongs to the system dialog, not to us. So this sheet has one button,
/// which always continues to the system prompt; the user's real answer is
/// the one they give iOS, and denying there leaves the Contacts tab usable
/// for search by user name.
///
/// `granted` therefore means "the explanation was shown and the user
/// continued" — `ContactsSynchronizer` still refuses to read the address
/// book until iOS itself has granted access.
public enum ContactsConsent {
    private static let kKey = "contactsUploadConsent"
    private static let kGranted = "granted"
    private static let kDeclined = "declined"

    public static var granted: Bool {
        return SharedUtils.kAppDefaults.string(forKey: kKey) == kGranted
    }

    /// Forgets that the explanation was shown, so it is shown again. Used
    /// when the account changes.
    public static func revoke() {
        SharedUtils.kAppDefaults.set(kDeclined, forKey: kKey)
    }

    /// Shows the explanation, then continues to the system prompt.
    public static func offer(from viewController: UIViewController, completion: ((Bool) -> Void)? = nil) {
        let host = Cache.tinode.hostName
        let message = String(
            format: NSLocalizedString(
                "BLML can upload the phone numbers and email addresses in your Contacts to your BLML server (%@) to find which of your contacts already use BLML.\n\nThey are used only for this matching, are never shown to other users, and are not shared with anyone.\n\niOS will now ask for access to your Contacts. If you don't allow it, nothing is uploaded and you can still find people by user name.",
                comment: "Contacts upload consent: explanation"),
            host)
        let alert = UIAlertController(
            title: NSLocalizedString("Find people you know", comment: "Contacts upload consent: title"),
            message: message,
            preferredStyle: .alert)
        // One action, and it always continues to the system prompt: see the
        // note above on 5.1.1(iv). The place to say no is the iOS dialog.
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Continue", comment: "Contacts upload consent: proceed to the system prompt"),
            style: .default) { _ in
                SharedUtils.kAppDefaults.set(kGranted, forKey: kKey)
                completion?(true)
            })
        viewController.present(alert, animated: true)
    }
}
