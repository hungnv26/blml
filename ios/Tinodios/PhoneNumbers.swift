//
//  PhoneNumbers.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import Foundation
import PhoneNumberKit
import TinodeSDK

/// One reader for every place the app takes a phone number: sign-up, the
/// "Add phone number" prompt, changing the number, password reset, search and
/// the address-book upload.
///
/// People type numbers the way they say them: with spaces, dashes or brackets,
/// in local format ("0491 570 104"), with the trunk zero after the country
/// code ("+61 (0)491 570 104"), or with 00 instead of +. All of those are
/// accepted. A number PhoneNumberKit can't fully validate (new ranges, its
/// metadata lagging behind the carriers) is still accepted when its length is
/// possible for the country — the same "possible number" rule the server uses.
/// The result is always E.164, which is how numbers are stored and matched.
extension Utils {
    static let kNotAPhoneNumberMessage = NSLocalizedString(
        "That doesn't look like a phone number. Check the digits, or start with + and the country code, like +61 412 345 678.",
        comment: "Error shown when the text entered as a phone number cannot be a phone number")

    /// Reads `raw` as a phone number and returns it in E.164 ("+61491570104"),
    /// or nil when it can't be a phone number.
    /// - Parameter region: region for numbers typed without a country code. By
    ///   default the device region, then the region of the account's own number.
    static func normalizedPhone(_ raw: String, region: String? = nil) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("tel:") {
            text = String(text.dropFirst(4))
        }
        // Digits, one leading +, and the separators people actually use.
        let allowed = CharacterSet(charactersIn: "0123456789+ -().‐‑–—/\u{00A0}\u{202F}")
        guard !text.isEmpty, text.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        let plusCount = text.filter { $0 == "+" }.count
        guard plusCount == 0 || (plusCount == 1 && text.first == "+") else { return nil }

        var digits = String(text.filter { ("0"..."9").contains($0) })
        var international = text.first == "+"
        if !international && digits.hasPrefix("00") {
            // 00 is the international prefix almost everywhere outside North America.
            digits.removeFirst(2)
            international = true
        }
        // Shortest real numbers are 4–5 digits plus a country code; E.164 caps at 15.
        guard digits.count >= 5 && digits.count <= 17 else { return nil }

        if international {
            return internationalToE164(digits)
        }

        let regions = region.map { [$0.uppercased()] } ?? phoneRegions()
        // Fully valid in one of the regions.
        for r in regions {
            if let e164 = validPersonalNumber(digits, region: r) {
                return e164
            }
        }
        // Possible but not (yet) valid: drop the trunk prefix, add the region's code.
        for r in regions {
            guard let meta = phoneNumberKit.metadata(for: r) else { continue }
            var national = digits
            if let prefix = meta.nationalPrefix, !prefix.isEmpty, national.hasPrefix(prefix) {
                national.removeFirst(prefix.count)
            }
            if isPossibleNational(national, countryCode: meta.countryCode) {
                return "+\(meta.countryCode)\(national)"
            }
        }
        // Typed with the country code but without the "+" ("61 491 570 104").
        if let e164 = internationalToE164(digits), digits.count >= 8 {
            return e164
        }
        return nil
    }

    /// Regions used for numbers typed without a country code: the device
    /// region first, then the region of the account's own number (a SIM-less
    /// iPad or a phone set to another region still reads home numbers right).
    static func phoneRegions() -> [String] {
        var regions = [PhoneNumberUtility.defaultRegionCode()]
        if let own = ownPhoneRegion(), !regions.contains(own) {
            regions.append(own)
        }
        return regions
    }

    /// Region of the phone number on the signed-in account, if there is one.
    static func ownPhoneRegion() -> String? {
        guard let tel = Cache.tinode.getMeTopic()?.creds?.first(where: { $0.meth == Credential.kMethPhone })?.val,
              let parsed = try? phoneNumberKit.parse(tel, ignoreType: true) else { return nil }
        return phoneNumberKit.getRegionCode(of: parsed)
    }

    /// `digits` is country code + national number, without the "+".
    private static func internationalToE164(_ digits: String) -> String? {
        if let e164 = validPersonalNumber("+" + digits, region: nil) {
            return e164
        }
        // Country codes are 1–3 digits, never start with 0, and are prefix-free,
        // so at most one matches.
        guard !digits.hasPrefix("0") else { return nil }
        for len in 1...3 where digits.count > len {
            guard let code = UInt64(digits.prefix(len)),
                  phoneNumberKit.mainCountry(forCode: code) != nil else { continue }
            let national = String(digits.dropFirst(len))
            // The trunk zero typed after the country code: "+61 0491…", "+44 (0)20…".
            if let prefix = nationalPrefix(forCode: code), national.hasPrefix(prefix) {
                let stripped = String(national.dropFirst(prefix.count))
                if let e164 = validPersonalNumber("+\(code)\(stripped)", region: nil) {
                    return e164
                }
                if !isPossibleNational(national, countryCode: code) && isPossibleNational(stripped, countryCode: code) {
                    return "+\(code)\(stripped)"
                }
            }
            return isPossibleNational(national, countryCode: code) ? "+\(code)\(national)" : nil
        }
        return nil
    }

    /// Fully valid per PhoneNumberKit's metadata, and the kind of number a
    /// person has (with the type check off, PhoneNumberKit also takes 5-digit
    /// service numbers, so "12345" would pass).
    private static func validPersonalNumber(_ number: String, region: String?) -> String? {
        let parsed: PhoneNumber
        do {
            if let region = region {
                parsed = try phoneNumberKit.parse(number, withRegion: region, ignoreType: false)
            } else {
                parsed = try phoneNumberKit.parse(number, ignoreType: false)
            }
        } catch {
            return nil
        }
        guard [.fixedLine, .mobile, .fixedOrMobile, .voip, .personalNumber].contains(parsed.type) else { return nil }
        return phoneNumberKit.format(parsed, toType: .e164)
    }

    private static func nationalPrefix(forCode code: UInt64) -> String? {
        guard let region = phoneNumberKit.mainCountry(forCode: code),
              let prefix = phoneNumberKit.metadata(for: region)?.nationalPrefix, !prefix.isEmpty else { return nil }
        return prefix
    }

    /// Kinds of number a person has as their own. Service numbers (UAN, toll
    /// free, premium…) allow 5–6 digit lengths in many countries, which would
    /// make almost any digit string "possible".
    private static let kLengthTypes: [PhoneNumberType] = [.fixedLine, .mobile, .voip, .personalNumber]

    /// libphonenumber's "possible number" test, limited to personal numbers:
    /// the national number's length is one the country uses for them.
    private static func isPossibleNational(_ national: String, countryCode code: UInt64) -> Bool {
        guard !national.isEmpty, national.count + String(code).count <= 15,
              let region = phoneNumberKit.mainCountry(forCode: code) else { return false }
        var lengths = Set<Int>()
        for type in kLengthTypes {
            lengths.formUnion(phoneNumberKit.possiblePhoneNumberLengths(forCountry: region, phoneNumberType: type, lengthType: .national))
        }
        if lengths.isEmpty {
            // No length data for this country: accept anything reasonable.
            return (4...14).contains(national.count)
        }
        return lengths.contains(national.count)
    }
}
