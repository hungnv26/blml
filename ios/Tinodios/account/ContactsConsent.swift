//
//  ContactsConsent.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import UIKit
import TinodiosDB

/// The user's answer to "may BLML upload your address book to the server?"
///
/// The system Contacts permission is not that answer: its prompt is a single
/// sentence and it cannot say what the server does with the data. App Review
/// (5.1.2) requires that the app explain the upload and get a yes *before*
/// asking the system, so this sheet runs first and `ContactsSynchronizer`
/// refuses to touch the address book until it has been accepted. Declining
/// keeps the Contacts tab usable for search by username; the offer is made
/// again only when the user starts something that needs contacts.
public enum ContactsConsent {
    private static let kKey = "contactsUploadConsent"
    private static let kGranted = "granted"
    private static let kDeclined = "declined"

    public static var granted: Bool {
        return SharedUtils.kAppDefaults.string(forKey: kKey) == kGranted
    }

    /// True once the user has answered either way.
    public static var decided: Bool {
        return SharedUtils.kAppDefaults.string(forKey: kKey) != nil
    }

    public static func revoke() {
        SharedUtils.kAppDefaults.set(kDeclined, forKey: kKey)
    }

    /// Presents the consent sheet. Calls `completion(true)` only if the user
    /// accepted; the caller then starts the synchronizer, which asks the
    /// system for permission.
    public static func offer(from viewController: UIViewController, completion: ((Bool) -> Void)? = nil) {
        let host = Cache.tinode.hostName
        let message = String(
            format: NSLocalizedString(
                "BLML can upload the phone numbers and email addresses in your Contacts to your BLML server (%@) to find which of your contacts already use BLML.\n\nThey are used only for this matching, are never shown to other users, and are not shared with anyone. You can stop this at any time in Settings › Privacy & Security › Contacts.",
                comment: "Contacts upload consent: explanation"),
            host)
        let alert = UIAlertController(
            title: NSLocalizedString("Find people you know", comment: "Contacts upload consent: title"),
            message: message,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Not now", comment: "Contacts upload consent: decline"),
            style: .cancel) { _ in
                SharedUtils.kAppDefaults.set(kDeclined, forKey: kKey)
                completion?(false)
            })
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Upload contacts", comment: "Contacts upload consent: accept"),
            style: .default) { _ in
                SharedUtils.kAppDefaults.set(kGranted, forKey: kKey)
                completion?(true)
            })
        alert.preferredAction = alert.actions.last
        viewController.present(alert, animated: true)
    }
}
