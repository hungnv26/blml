//
//  ChatListTableViewCell.swift
//
//  Copyright © 2019-2025 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB

class ChatListViewCell: UITableViewCell {
    private static let kIconWidth: CGFloat = 18
    private static let kMessageStatusWidth: CGFloat = 14
    private static let kIconSeparator: CGFloat = 4

    @IBOutlet weak var icon: AvatarWithOnlineIndicator!
    @IBOutlet weak var title: UILabel!
    @IBOutlet weak var subtitle: UILabel!
    @IBOutlet weak var unreadCount: UILabel!
    @IBOutlet weak var iconBlocked: UIImageView!
    @IBOutlet weak var iconMuted: UIImageView!
    @IBOutlet weak var iconBlockedWidth: NSLayoutConstraint!
    @IBOutlet weak var unreadCountWidth: NSLayoutConstraint!
    @IBOutlet weak var channelIndicator: UIImageView!
    @IBOutlet weak var channelIndicatorWidth: NSLayoutConstraint!
    @IBOutlet weak var iconMessageStatus: UIImageView!
    @IBOutlet weak var iconMessageStatusWidth: NSLayoutConstraint!
    @IBOutlet weak var badgeVerified: UIImageView!
    @IBOutlet weak var badgeVerifiedWidth: NSLayoutConstraint!
    @IBOutlet weak var badgeStaff: UIImageView!
    @IBOutlet weak var badgeStaffWidth: NSLayoutConstraint!
    @IBOutlet weak var badgeDanger: UIImageView!
    @IBOutlet weak var badgeDangerWidth: NSLayoutConstraint!

    // WhatsApp-style right-aligned timestamp, added in code: the XIB layout
    // stays untouched, the label floats in the cell's top-right corner.
    let timeLabel = UILabel()

    override func awakeFromNib() {
        super.awakeFromNib()
        // WhatsApp-weight list typography: semibold names, and a subtitle gray
        // picked per theme. The XIB had an 18pt regular title over a fixed 33%
        // gray subtitle — reported as "too thin, hard to read" in light mode.
        title.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        subtitle.font = UIFont.systemFont(ofSize: 15)
        subtitle.textColor = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(fromHexCode: 0xff8696a0) : UIColor(fromHexCode: 0xff667781) }

        iconMuted.tintColor = UIColor.init(fromHexCode: 0xFFCCCCCC)
        iconBlocked.tintColor = iconMuted.tintColor

        // WhatsApp-style green pill for the unread count.
        unreadCount.backgroundColor = UIColor(fromHexCode: 0xff25d366)
        unreadCount.textColor = .white
        unreadCount.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        unreadCount.layer.cornerRadius = ChatListViewCell.kIconWidth / 2
        unreadCount.layer.masksToBounds = true
        unreadCount.textAlignment = .center

        timeLabel.font = UIFont.systemFont(ofSize: 12)
        timeLabel.textColor = .secondaryLabel
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(timeLabel)
        NSLayoutConstraint.activate([
            timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)
        ])
    }

    // WhatsApp-style timestamp: time today, "Yesterday", weekday within a week,
    // short date otherwise.
    private static func whatsAppTimestamp(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let cal = Calendar.current
        let fmt = DateFormatter()
        if cal.isDateInToday(date) {
            fmt.timeStyle = .short
            fmt.dateStyle = .none
        } else if cal.isDateInYesterday(date) {
            return NSLocalizedString("Yesterday", comment: "Chat list timestamp")
        } else if let days = cal.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            fmt.dateFormat = "EEEE"
        } else {
            fmt.dateStyle = .short
            fmt.timeStyle = .none
        }
        return fmt.string(from: date)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }

    private func setMessageStatusVisibility(hidden: Bool) {
        let width: CGFloat = hidden ? 0 : ChatListViewCell.kMessageStatusWidth
        iconMessageStatus.isHidden = hidden
        iconMessageStatusWidth.constant = width
    }

    public func fillFromTopic(topic: DefaultComTopic) {
        title.text = topic.isSlfType ? NSLocalizedString("Saved messages", comment: "Title of the slf topic") :
            topic.pub?.fn ?? NSLocalizedString("Unknown or unnamed", comment: "Topic title when it has no name")
        title.sizeToFit()
        if let msg = topic.latestMessage as? StoredMessage {
            // If we have a latestMessage and its up to date.
            subtitle.attributedText = msg.attributedPreview(fitIn: subtitle.frame.size)
            if msg.from == Cache.tinode.myUid {
                setMessageStatusVisibility(hidden: false)
                let (image, tint) = UiUtils.deliveryMarkerIcon(for: msg, in: topic)
                iconMessageStatus.image = image
                iconMessageStatus.tintColor = tint
            } else {
                setMessageStatusVisibility(hidden: true)
            }
        } else {
            subtitle.text = topic.isSlfType ?
                NSLocalizedString("Notes, messages, links, files saved for posterity", comment: "Explanation for Saved messages topic") :
                topic.comment
            setMessageStatusVisibility(hidden: true)
        }
        subtitle.sizeToFit()
        if topic.isChannel {
            channelIndicator.isHidden = false
            channelIndicatorWidth.constant = ChatListViewCell.kIconWidth
        } else {
            channelIndicator.isHidden = true
            channelIndicatorWidth.constant = .leastNonzeroMagnitude
        }

        if topic.isVerified {
            badgeVerified.isHidden = false
            badgeVerifiedWidth.constant = ChatListViewCell.kIconWidth
        } else {
            badgeVerified.isHidden = true
            badgeVerifiedWidth.constant = .leastNonzeroMagnitude
        }
        if topic.isStaffManaged {
            badgeStaff.isHidden = false
            badgeStaffWidth.constant = ChatListViewCell.kIconWidth
        } else {
            badgeStaff.isHidden = true
            badgeStaffWidth.constant = .leastNonzeroMagnitude
        }
        if topic.isDangerous {
            badgeDanger.isHidden = false
            badgeDangerWidth.constant = ChatListViewCell.kIconWidth
        } else {
            badgeDanger.isHidden = true
            badgeDangerWidth.constant = .leastNonzeroMagnitude
        }

        let unread = topic.unread
        if unread > 0 {
            unreadCount.text = unread > 9 ? "9+" : String(unread)
            unreadCount.isHidden = false
            unreadCountWidth.constant = ChatListViewCell.kIconWidth
        } else {
            unreadCount.isHidden = true
            unreadCountWidth.constant = .leastNonzeroMagnitude
        }

        timeLabel.text = ChatListViewCell.whatsAppTimestamp(topic.touched)
        // WhatsApp turns the timestamp green when there are unread messages.
        timeLabel.textColor = unread > 0 ? UIColor(fromHexCode: 0xff25d366) : .secondaryLabel

        iconBlocked.isHidden = !topic.isJoiner
        iconBlockedWidth.constant = topic.isJoiner ? .leastNonzeroMagnitude : ChatListViewCell.kIconWidth + ChatListViewCell.kIconSeparator * 2

        iconMuted.isHidden = topic.isSlfType || !topic.isMuted

        // Avatar image
        icon.set(pub: topic.pub, id: topic.name, online: (topic.isChannel || topic.isSlfType) ? nil : topic.online, deleted: topic.deleted)
    }
}
