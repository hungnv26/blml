//
//  NotificationService.swift
//  TinodiosNSExtension
//
//  Copyright © 2019-2022 Tinode. All rights reserved.
//

import UserNotifications
import TinodeSDK
import TinodiosDB

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    let log = TinodeSDK.Log(subsystem: BaseDb.kBundleId)

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        self.bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        // New message notification (msg):
        // - P2P
        //   Title: <sender name> || 'Unknown'
        //   Body: <message content> || 'New message'
        // - GRP
        //   Title: <topic name> || 'Unknown'
        //   Body: <sender name>: <message content> || 'New message'
        //
        // Subscription notification (sub):
        // - P2P
        //   Title: 'New chat'
        //   Body: <sender name> || 'Unknown'
        // - GRP
        //   Title: 'New chat'
        //   Body: <group name> || 'Unknown'
        // Deleted subscription:
        //   Always invisible.
        //

        if let bestAttemptContent = bestAttemptContent {
            let payload = bestAttemptContent.userInfo
            defer { self.contentHandler!(bestAttemptContent) }

            guard let topicName = payload["topic"] as? String, !topicName.isEmpty, let from = payload["xfrom"] as? String, !from.isEmpty else { return }

            let action = payload["what"] as? String ?? "msg"

            guard ["msg", "sub"].contains(action) else {
                // Not handling it here.
                return
            }

            let store = BaseDb.sharedInstance.sqlStore!
            let topicType = Tinode.topicTypeByName(name: topicName)
            let senderName: String
            switch topicType {
            case .p2p:
                var user = store.userGet(uid: from) as? DefaultUser
                var fetchedName: String?
                if user == nil {
                    // If we don't have the user info, fetch it from the server.
                    let tinode = SharedUtils.createTinode()
                    self.log.info("Fetching desc from server for user %@.", from)
                    if SharedUtils.fetchDesc(using: tinode, for: from) == .newData {
                        // The above call blocks until the servers replies, but it takes time to sync data to local store. Give the thread 1 second to persist the data.
                        Thread.sleep(forTimeInterval: 1)
                        user = store.userGet(uid: from) as? DefaultUser
                    } else {
                        self.log.info("No new desc data fetched for %@.", from)
                    }
                    if user == nil && store.topicGet(from: nil, withName: topicName) == nil {
                        // A stranger (typically a chat request): nothing cached to name them by.
                        fetchedName = SharedUtils.fetchPublicName(using: tinode, for: from)
                    }
                    tinode.disconnect()
                }
                // In a p2p chat the topic is named after the peer, so a cached topic carries the name too
                // (the user row may be missing while the topic is known, and then nothing is fetched).
                let topic = user == nil ? store.topicGet(from: nil, withName: topicName) as? DefaultComTopic : nil
                senderName = user?.pub?.fn ?? topic?.pub?.fn ?? fetchedName ?? NSLocalizedString("Unknown", comment: "Placeholder for missing user name")
                break
            case .grp:
                let topic = store.topicGet(from: nil, withName: topicName) as? DefaultComTopic
                senderName = topic?.pub?.fn ?? NSLocalizedString("Unknown", comment: "Placeholder for missing topic name")
                break
            default:
                return
            }

            if action == "msg" {
                bestAttemptContent.title = senderName
                if topicType == .grp {
                    bestAttemptContent.body = senderName + ": " + bestAttemptContent.body
                }
            } else if action == "sub" {
                // 1:1 chat request (server p2p_requires_accept): my side was created with
                // want "JA" — no R/W until I accept. Say what it is and what to do.
                let modeWant = payload["modeWant"] as? String ?? ""
                if topicType == .p2p && modeWant.contains("J") && !modeWant.contains("W") && !modeWant.contains("R") {
                    bestAttemptContent.title = String(format: NSLocalizedString("%@ wants to chat with you", comment: "Push title: incoming chat request"), senderName)
                    bestAttemptContent.body = NSLocalizedString("Open BLML to accept or decline the request.", comment: "Push body: incoming chat request")
                } else {
                    bestAttemptContent.title = NSLocalizedString("New chat", comment: "Push notification title")
                    bestAttemptContent.body = senderName
                }
            }
        } else {
            self.contentHandler!(request.content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // 30 seconds.
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

}
