//
//  PhoneNumberPrompt.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import UIKit
import TinodeSDK

/// Collects a phone number and saves it on the account, where it becomes the
/// "tel:" tag that other people's address books are matched against.
///
/// Phonebook search only finds accounts that have a number, so this is offered
/// in two places: the "Add phone number" row in Settings, and once after
/// sign-in for accounts that have no number yet.
///
/// This server confirms a number as soon as it is entered (no SMS) and says so
/// with "done" in the reply. A server that texts codes leaves it out, and the
/// code prompt follows.
enum PhoneNumberPrompt {
    private static let kOfferedKeyPrefix = "phoneNumberOffered."

    /// Step 1: collect the number and send it.
    static func collect(from vc: UIViewController, me: DefaultMeTopic,
                        title: String, message: String, prefill: String? = nil,
                        onChange: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = prefill
            field.placeholder = NSLocalizedString("+61 412 345 678", comment: "Phone placeholder")
            field.keyboardType = .phonePad
            field.textContentType = .telephoneNumber
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Not now", comment: "Alert action"), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Save", comment: "Alert action"), style: .default) { [weak vc] _ in
            guard let vc = vc, let raw = alert.textFields?.first?.text,
                  !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            // Normalize to E.164: numbers are stored and matched in that form.
            // Spaces, dashes, brackets and local format ("0412 345 678", read in
            // the device's region) are all fine. Only something that can't be a
            // phone number is refused, and then the prompt comes back with why.
            guard let number = Utils.normalizedPhone(raw) else {
                collect(from: vc, me: me, title: title, message: Utils.kNotAPhoneNumberMessage,
                        prefill: raw, onChange: onChange)
                return
            }

            me.setMeta(cred: Credential(meth: Credential.kMethPhone, val: number)).then(
                onSuccess: { [weak vc] msg in
                    let confirmed = msg?.ctrl?.getBoolParam(for: "done") ?? false
                    DispatchQueue.main.async {
                        if confirmed {
                            UiUtils.showToast(message: NSLocalizedString("Phone number saved", comment: "Toast"), level: .info)
                            onChange()
                        } else if let vc = vc {
                            confirmCode(from: vc, me: me, number: number, onChange: onChange)
                        }
                    }
                    return nil
                },
                onFailure: { err in
                    DispatchQueue.main.async {
                        UiUtils.showToast(message: phoneErrorMessage(err))
                    }
                    return nil
                })
        })
        vc.present(alert, animated: true)
    }

    /// Step 2, only on a server that texts codes: confirm the number.
    static func confirmCode(from vc: UIViewController, me: DefaultMeTopic, number: String,
                            wrongCode: Bool = false, onChange: @escaping () -> Void) {
        let prompt = wrongCode
            ? NSLocalizedString("That code was not right. Check the SMS and try again.", comment: "Alert message after a wrong code")
            : String(format: NSLocalizedString("Enter the confirmation code sent to %@.", comment: "Alert message"), number)
        let alert = UIAlertController(
            title: NSLocalizedString("Confirm number", comment: "Alert title"),
            message: prompt,
            preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = NSLocalizedString("Code", comment: "Placeholder")
            field.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Later", comment: "Alert action"), style: .cancel) { _ in
            onChange()
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Confirm", comment: "Alert action"), style: .default) { [weak vc] _ in
            guard let code = alert.textFields?.first?.text, !code.isEmpty else { return }
            me.setMeta(cred: Credential(meth: Credential.kMethPhone, val: nil, resp: code, params: nil)).then(
                onSuccess: { _ in
                    DispatchQueue.main.async {
                        UiUtils.showToast(message: NSLocalizedString("Phone number confirmed", comment: "Toast"), level: .info)
                        onChange()
                    }
                    return nil
                },
                onFailure: { [weak vc] _ in
                    // Re-ask rather than dropping out of the flow. A mistyped
                    // digit otherwise left a pending, unconfirmable number
                    // behind with no obvious way to finish.
                    DispatchQueue.main.async {
                        if let vc = vc {
                            confirmCode(from: vc, me: me, number: number, wrongCode: true, onChange: onChange)
                        }
                    }
                    return nil
                })
        })
        vc.present(alert, animated: true)
    }

    /// A duplicate number is the likely failure now that numbers are confirmed
    /// on entry: say so plainly instead of showing the raw server error.
    static func phoneErrorMessage(_ err: Error) -> String {
        let text = err.localizedDescription
        if text.contains("409") || text.lowercased().contains("duplicate") {
            return NSLocalizedString("This phone number is already used by another account.", comment: "Error: phone number taken")
        }
        return String(format: NSLocalizedString("Could not add the number: %@", comment: "Error"), text)
    }

    /// Offers to add a number once per account, for accounts that have none.
    /// Does nothing until the account's credentials have loaded, so it is safe
    /// to call on every appearance of the chat list.
    static func offerOnceIfMissing(from vc: UIViewController) {
        guard !Passcode.isLocked,
              vc.presentedViewController == nil,
              let me = Cache.tinode.getMeTopic(),
              let uid = Cache.tinode.myUid,
              let creds = me.creds else { return }
        guard !creds.contains(where: { $0.meth == Credential.kMethPhone }) else { return }

        let key = kOfferedKeyPrefix + uid
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        // Recorded when shown, not when answered: "Not now" means not now,
        // and the Settings row stays available for later.
        UserDefaults.standard.set(true, forKey: key)

        collect(from: vc, me: me,
                title: NSLocalizedString("Add your phone number", comment: "Alert title"),
                message: NSLocalizedString("People who have your number in their contacts can then find you on BLML. You can also add it later in Settings.", comment: "Alert message"),
                onChange: {})
    }
}
