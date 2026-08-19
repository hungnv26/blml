//
//  AddFriendViewController.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import TinodeSDK
import UIKit

/// Zalo-style "Add friend" screen, reached from the "+" on the Contacts tab:
/// your own QR card up top, then add-by-phone, add-by-email, scan a QR code,
/// and people you may know (members of your groups you have no chat with yet).
class AddFriendViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case myCode = 0
        case byPhone
        case byEmail
        case scanQR
        case suggestions
    }

    /// Group members who share a group with me but have no P2P chat yet.
    private var suggestions: [(uid: String, pub: TheCard?)] = []

    private let phoneField = UITextField()
    private let emailField = UITextField()

    // Held strongly: the fnd topic keeps only a weak reference.
    private var fndListener: SearchListener?

    private class SearchListener: DefaultFndTopic.Listener {
        var onResults: (() -> Void)?
        override func onSubsUpdated() {
            DispatchQueue.main.async { self.onResults?() }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("Add friend", comment: "Screen title")
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.register(UINib(nibName: "ContactViewCell", bundle: nil), forCellReuseIdentifier: "ContactViewCell")
        configureField(phoneField,
                       placeholder: NSLocalizedString("Phone number", comment: "Input placeholder"),
                       keyboard: .phonePad)
        configureField(emailField,
                       placeholder: NSLocalizedString("Email address", comment: "Input placeholder"),
                       keyboard: .emailAddress)
        buildSuggestions()
    }

    private func configureField(_ field: UITextField, placeholder: String, keyboard: UIKeyboardType) {
        field.placeholder = placeholder
        field.keyboardType = keyboard
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
    }

    // MARK: - Suggestions

    /// On a family server "people you may know" has a precise meaning: everyone
    /// who shares a group chat with me and does not have a direct chat yet.
    /// Built entirely from the local store — no network round-trip.
    private func buildSuggestions() {
        let tinode = Cache.tinode
        guard let myUid = tinode.myUid else { return }
        var seen = Set<String>()
        var result: [(String, TheCard?)] = []
        for topic in tinode.getFilteredTopics(filter: { $0.topicType == .grp }) ?? [] {
            guard let grp = topic as? DefaultComTopic else { continue }
            for sub in grp.getSubscriptions() ?? [] {
                guard let uid = sub.user, uid != myUid, !seen.contains(uid) else { continue }
                seen.insert(uid)
                if tinode.getTopic(topicName: uid) == nil {
                    result.append((uid, sub.pub))
                }
            }
        }
        suggestions = result
    }

    // MARK: - Directory search by phone or email

    private func search(tag: String, value: String) {
        guard !value.isEmpty else { return }
        view.endEditing(true)

        let listener = SearchListener()
        listener.onResults = { [weak self] in
            guard let self = self else { return }
            let subs = Cache.tinode.getOrCreateFndTopic().getSubscriptions() ?? []
            guard let first = subs.first, let uid = first.uniqueId else {
                UiUtils.showToast(message: NSLocalizedString("No member found with that phone number or email", comment: "Toast"))
                return
            }
            if let pub = first.pub {
                ContactsManager.default.processSubscription(sub: first)
                _ = pub // keep the card; processSubscription stores it for the chat title
            }
            self.presentChatReplacingCurrentVC(with: uid)
        }
        fndListener = listener

        UiUtils.attachToFndTopic(fndListener: listener)?.then(
            onSuccess: { _ in
                let fnd = Cache.tinode.getOrCreateFndTopic()
                _ = fnd.setMeta(desc: MetaSetDesc(pub: tag + value, priv: nil))
                _ = fnd.getMeta(query: fnd.metaGetBuilder().withSub().build())
                return nil
            },
            onFailure: { err in
                Cache.log.error("AddFriend - fnd attach failed: %@", err.localizedDescription)
                DispatchQueue.main.async {
                    UiUtils.showToast(message: NSLocalizedString("Not connected to server", comment: "Toast error"))
                }
                return nil
            })
    }

    private func searchPhone() {
        guard let phone = Utils.asPhone(phoneField.text ?? "") else {
            UiUtils.showToast(message: NSLocalizedString("Enter a full phone number with country code, like +61…", comment: "Toast"))
            return
        }
        search(tag: Tinode.kTagPhone, value: phone)
    }

    private func searchEmail() {
        guard let email = Utils.asEmail(emailField.text ?? "") else {
            UiUtils.showToast(message: NSLocalizedString("That does not look like an email address", comment: "Toast"))
            return
        }
        search(tag: Tinode.kTagEmail, value: email)
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .myCode: return nil
        case .byPhone: return NSLocalizedString("Add by phone number", comment: "Section header")
        case .byEmail: return NSLocalizedString("By email", comment: "Section header")
        case .scanQR: return nil
        case .suggestions:
            return suggestions.isEmpty ? nil
                : NSLocalizedString("People you may know", comment: "Section header")
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .suggestions: return suggestions.count
        default: return 1
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .myCode:
            return myCodeCell()
        case .byPhone:
            return inputCell(field: phoneField) { [weak self] in self?.searchPhone() }
        case .byEmail:
            return inputCell(field: emailField) { [weak self] in self?.searchEmail() }
        case .scanQR:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            var content = cell.defaultContentConfiguration()
            content.text = NSLocalizedString("Scan QR code", comment: "Menu row")
            content.image = UIImage(systemName: "qrcode.viewfinder")
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell
        case .suggestions:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ContactViewCell", for: indexPath) as! ContactViewCell
            let item = suggestions[indexPath.row]
            cell.avatar.set(pub: item.pub, id: item.uid, deleted: false)
            cell.title.text = item.pub?.fn ?? item.uid
            cell.subtitle.text = NSLocalizedString("In a group with you", comment: "Suggestion subtitle")
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .scanQR:
            let vc = QRScanViewController()
            vc.hidesBottomBarWhenPushed = true
            navigationController?.pushViewController(vc, animated: true)
        case .suggestions:
            presentChatReplacingCurrentVC(with: suggestions[indexPath.row].uid)
        default:
            break
        }
    }

    // MARK: - Cell builders

    /// The Zalo-style card: name, QR code, caption.
    private func myCodeCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none

        let name = UILabel()
        name.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        name.textAlignment = .center
        name.text = Cache.tinode.getMeTopic()?.pub?.fn ?? ""

        let qr = UIImageView()
        qr.contentMode = .scaleAspectFit
        if let myUid = Cache.tinode.myUid {
            qr.image = Utils.generateQRCode(from: Utils.kTopicUriPrefix + myUid)
        }

        let caption = UILabel()
        caption.font = UIFont.preferredFont(forTextStyle: .footnote)
        caption.textColor = .secondaryLabel
        caption.textAlignment = .center
        caption.numberOfLines = 0
        caption.text = NSLocalizedString("Scan this code to chat with me on BLML", comment: "QR card caption")

        let stack = UIStackView(arrangedSubviews: [name, qr, caption])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            qr.widthAnchor.constraint(equalToConstant: 190),
            qr.heightAnchor.constraint(equalToConstant: 190)
        ])
        return cell
    }

    /// Text field with a round "go" button, the way Zalo lays out its phone row.
    private func inputCell(field: UITextField, action: @escaping () -> Void) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none

        let go = GoButton(action: action)

        field.translatesAutoresizingMaskIntoConstraints = false
        go.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(field)
        cell.contentView.addSubview(go)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            field.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: 44),
            field.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
            field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
            go.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 8),
            go.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -12),
            go.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            go.widthAnchor.constraint(equalToConstant: 34),
            go.heightAnchor.constraint(equalToConstant: 34)
        ])
        return cell
    }

    /// UIButton with an attached closure; avoids @objc target plumbing per row.
    private class GoButton: UIButton {
        private let action: () -> Void
        init(action: @escaping () -> Void) {
            self.action = action
            super.init(frame: .zero)
            setImage(UIImage(systemName: "arrow.right.circle.fill",
                             withConfiguration: UIImage.SymbolConfiguration(pointSize: 28)), for: .normal)
            tintColor = UIColor(fromHexCode: 0xff00a884)
            addTarget(self, action: #selector(fire), for: .touchUpInside)
        }
        required init?(coder: NSCoder) { fatalError("not used") }
        @objc private func fire() { action() }
    }
}
