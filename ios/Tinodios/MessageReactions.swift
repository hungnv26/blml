//
//  MessageReactions.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import TinodeSDK
import TinodiosDB
import UIKit

/// Emoji reactions, Zalo-style. Tinode has no native reactions, so a reaction
/// travels as an ordinary `{pub}` whose head carries `reaction` (the emoji)
/// and `ref` (the seq id of the message it reacts to), with the emoji as the
/// content. Clients that understand the head hide these messages from the
/// transcript and draw them as a pill on the target bubble; clients that do
/// not (the web app, for now) show a plain emoji message — a graceful
/// degradation rather than a protocol break.
enum MessageReactions {
    /// Matched to the set family members know from Zalo: love, like, haha,
    /// wow, sad, angry. The laugh squints rather than weeping with joy, and
    /// the sad one sobs rather than shedding a single tear — those two read as
    /// the wrong feeling otherwise.
    static let kQuickReactions = ["❤️", "👍", "😆", "😮", "😭", "😡"]

    struct Entry {
        let emoji: String
        let fromUid: String?
        /// Seq id of the reaction message itself — needed to retract it.
        let seqId: Int
    }

    /// Splits a raw transcript into visible messages and a map of
    /// target-seq → reactions.
    static func split(_ all: [StoredMessage]) -> (visible: [StoredMessage], byTarget: [Int: [Entry]]) {
        var visible: [StoredMessage] = []
        var byTarget: [Int: [Entry]] = [:]
        for msg in all {
            if let head = msg.head,
               case let .string(emoji)? = head["reaction"],
               let refValue = head["ref"], case let .int(ref) = refValue {
                // A retracted reaction lingers locally as a deletion marker
                // that still carries the head — it must not count.
                if !msg.isDeleted {
                    byTarget[ref, default: []].append(Entry(emoji: emoji, fromUid: msg.from, seqId: msg.seqId))
                }
            } else {
                visible.append(msg)
            }
        }
        return (visible, byTarget)
    }

    /// "❤️ 2 😂 1" — the pill text for one message, nil when unreacted.
    static func summary(for entries: [Entry]?) -> String? {
        guard let entries = entries, !entries.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        var order: [String] = []
        for e in entries {
            if counts[e.emoji] == nil { order.append(e.emoji) }
            counts[e.emoji, default: 0] += 1
        }
        return order.map { counts[$0]! > 1 ? "\($0) \(counts[$0]!)" : $0 }.joined(separator: " ")
    }
}
