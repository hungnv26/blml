//
//  Passcode.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import CryptoKit
import Foundation
import SwiftKeychainWrapper

/// A four-digit passcode that locks the app, stored per account.
///
/// Deliberately NOT kept in `SharedUtils.kAppKeychain`: that keychain is wiped
/// wholesale on logout, so a passcode living there would vanish for anyone who
/// signs out and back in. This one is keyed by uid and outlives a session,
/// which is also what makes it per-user — two people sharing a device each get
/// their own code, and neither can open the other's account with it.
public enum Passcode {
    /// Four digits, matching what people expect from a phone lock screen.
    public static let kLength = 4

    private static let keychain = KeychainWrapper(serviceName: "app.blml.chat.passcode")

    private static func key(for uid: String) -> String {
        return "passcode.\(uid)"
    }

    /// Stored as `<salt-hex>:<sha256-hex>`.
    ///
    /// Hashing four digits is not much of a barrier on its own — the whole
    /// space is ten thousand entries — but the alternative is writing the
    /// code down in plain text, and the salt at least means a keychain dump
    /// cannot be compared against precomputed digests or against another
    /// account's entry to see that two users chose the same code.
    private static func digest(_ code: String, salt: Data) -> String {
        var input = salt
        input.append(contentsOf: Array(code.utf8))
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        // A failure here would silently produce a constant salt, which is
        // worse than no salt at all because it would look fine.
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return Data(UUID().uuidString.utf8)
        }
        return Data(bytes)
    }

    /// True when this account has a passcode configured.
    public static func isSet(for uid: String?) -> Bool {
        guard let uid = uid else { return false }
        return keychain.string(forKey: key(for: uid)) != nil
    }

    /// Saves a new passcode, replacing any existing one. Returns false if the
    /// code is the wrong shape or the keychain refused the write — callers
    /// must not report success on a passcode that was never stored.
    @discardableResult
    public static func set(_ code: String, for uid: String?) -> Bool {
        guard let uid = uid, isWellFormed(code) else { return false }
        let salt = randomSalt()
        let record = "\(salt.map { String(format: "%02x", $0) }.joined()):\(digest(code, salt: salt))"
        return keychain.set(record, forKey: key(for: uid), withAccessibility: .whenUnlockedThisDeviceOnly)
    }

    /// Checks a code against the stored one. False when nothing is stored:
    /// an account with no passcode cannot be unlocked by guessing.
    public static func verify(_ code: String, for uid: String?) -> Bool {
        guard let uid = uid,
              let record = keychain.string(forKey: key(for: uid)) else { return false }
        let parts = record.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let salt = Data(hexString: String(parts[0])) else { return false }
        return digest(code, salt: salt) == String(parts[1])
    }

    /// Removes the passcode for this account.
    public static func clear(for uid: String?) {
        guard let uid = uid else { return }
        keychain.removeObject(forKey: key(for: uid))
    }

    /// Exactly `kLength` ASCII digits. Guards against a paste or an autofill
    /// putting something else in the field.
    public static func isWellFormed(_ code: String) -> Bool {
        return code.count == kLength && code.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

extension Data {
    /// Parses an even-length hex string. Nil on anything malformed, so a
    /// corrupt keychain record fails verification rather than crashing.
    fileprivate init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
