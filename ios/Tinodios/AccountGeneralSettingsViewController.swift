//
//  AccountGeneralSettingsViewController.swift
//
//  Copyright © 2020-2025 Tinode LLC. All rights reserved.
//

import PhoneNumberKit
import TinodeSDK
import UIKit

class AccountGeneralSettingsViewController: UITableViewController {
    // Container for passing credentials to CredentialsChangeViewController.
    private struct CredentialContainer {
        let currentCred: Credential
        let newCred: Credential?
    }

    private static let kSectionPersonal = 0
    // Avatar = 0
    private static let kPersonalName = 1
    private static let kPersonalAlias = 2
    private static let kPersonalDescription = 3

    private static let kSectionContacts = 1

    // "About" rather than "Optional description": this is the user's own status
    // line, the same thing WhatsApp calls About. Topic descriptions elsewhere
    // keep the old wording — they really are descriptions of a group.
    private static let kDescriptionPlaceholder = NSLocalizedString("About — e.g. Hey there! I am using BLML.", comment: "Placeholder for the user's own status line")
    
    @IBOutlet weak var nameTextField: UITextField!
    @IBOutlet weak var aliasTextField: UITextField!
    @IBOutlet weak var descriptionTextView: UITextView!
    @IBOutlet weak var avatarImage: RoundImageView!
    @IBOutlet weak var loadAvatarButton: UIButton!

    private var aliasTesterTimer: Timer?

    weak var tinode: Tinode!
    weak var me: DefaultMeTopic!
    private var imagePicker: ImagePicker!

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadData()
    }

    private func setup() {
        self.tinode = Cache.tinode
        self.me = self.tinode.getMeTopic()!

        nameTextField.delegate = self
        nameTextField.tag = AccountGeneralSettingsViewController.kPersonalName

        aliasTextField.delegate = self
        aliasTextField.tag = AccountGeneralSettingsViewController.kPersonalAlias
        aliasTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)

        descriptionTextView.delegate = self
        descriptionTextView.tag = AccountGeneralSettingsViewController.kPersonalDescription

        self.imagePicker = ImagePicker(presentationController: self, delegate: self, editable: true)
    }

    private func reloadData() {
        // Title.
        self.nameTextField.text = me.pub?.fn

        // Alias
        aliasTextField.leftView = UIImageView(image: UIImage(systemName: "at"))
        aliasTextField.leftViewMode = .always
        aliasTextField.text = me.alias

        // Description (note)
        if let note = me.pub?.note {
            self.descriptionTextView.text = note
            self.descriptionTextView.textColor = UIColor.secondaryLabel
        } else {
            self.descriptionTextView.text = AccountGeneralSettingsViewController.kDescriptionPlaceholder
            self.descriptionTextView.textColor = UIColor.placeholderText
        }

        // Avatar.
        self.avatarImage.set(pub: me.pub, id: self.tinode.myUid, deleted: false)
        self.avatarImage.letterTileFont = self.avatarImage.letterTileFont.withSize(CGFloat(50))

        // Note: tableView.reloadSections() would be better but
        // it makes the [Add another] contact button disappear.
        // Likely due to this: https://stackoverflow.com/questions/3132135/initally-visible-cells-gets-invisible-after-calling-reloadsectionswithrowanimat
        self.tableView.reloadData()
    }

    @IBAction func loadAvatarClicked(_ sender: Any) {
        imagePicker.present(from: self.view)
    }


    @objc
    func textFieldDidChange(_ textField: UITextField) {
        let text = textField.text ?? ""
        if Tinode.isValidTagValueFormat(tag: text) {
            textField.clearErrorSign()
            if !text.isEmpty {
                if let timer = aliasTesterTimer {
                    timer.invalidate()
                }
                aliasTesterTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(checkAliasValidity), userInfo: nil, repeats: false)
            }
        } else {
            textField.markAsError()
        }
    }

    // This method is called for every keystroke, but validity is checked 1 second after the typing has stopped.
    @objc
    func checkAliasValidity() {
        guard let alias = self.aliasTextField.text, let caller = Cache.tinode.myUid else {
            return
        }
        // Check if alias is already taken.
        guard let fnd = self.tinode?.getOrCreateFndTopic() else {
            // Unable to check: say "all is fine".
            return
        }
        fnd.checkTagUniqueness(tag: "\(Tinode.kTagAlias)\(alias)", caller: caller)
            .thenApply { ok in
                DispatchQueue.main.async { [weak self] in
                    if ok ?? false {
                        self?.aliasTextField.clearErrorSign()
                    } else {
                        self?.aliasTextField.markAsError()
                    }
                }
                return nil
            }
            .thenCatch { err in
                DispatchQueue.main.async { [weak self] in
                    self?.aliasTextField.markAsError()
                }
                return nil
            }
    }

    @IBAction func doneEditingClicked(_ sender: Any) {
        var pub: TheCard? = nil
        if let name = nameTextField.text, name != me.pub?.fn {
            pub = TheCard(fn: name)
        }

        let desc = descriptionTextView.text
        if desc != me.pub?.note {
            pub = pub ?? TheCard()
            if (desc ?? "").isEmpty || desc == AccountGeneralSettingsViewController.kDescriptionPlaceholder {
                pub!.note = Tinode.kNullValue
            } else {
                pub!.note = desc
            }
        }
        var tags: [String]? = nil
        if let alias = self.aliasTextField.text, !alias.isEmpty {
            tags = Tinode.setUniqueTag(tags: self.me.tags, uniqueTag: "\(Tinode.kTagAlias)\(alias)")
        } else {
            tags = Tinode.clearTagPrefix(tags: self.me.tags, prefix: Tinode.kTagAlias)
        }
        if tags != nil && tags!.equals(me.tags) {
            tags = nil
        }

        if pub == nil && tags == nil {
            // Unchanged
            _ = self.navigationController?.popViewController(animated: true)
            return
        }

        self.me.setMeta(meta: MsgSetMeta(desc: pub != nil ? MetaSetDesc(pub: pub, priv: nil) : nil, tags: tags))
            .then(onSuccess: { _ in
                DispatchQueue.main.async {
                    _ = self.navigationController?.popViewController(animated: true)
                }
                return nil
            }, onFailure: UiUtils.ToastFailureHandler)
    }
}

extension AccountGeneralSettingsViewController: ImagePickerDelegate {
    func didSelect(media: ImagePickerMediaType?) {
        guard case .image(let image, _, _) = media else { return }
        UiUtils.updateAvatar(forTopic: self.me, image: image)
            .thenApply { _ in
                DispatchQueue.main.async {
                    UiUtils.showToast(message: "Avatar successfully updated", level: .info)
                    self.reloadData()
                }
                return nil
            }
    }
}

// UITableViewController
extension AccountGeneralSettingsViewController {
    /// True when the account has no phone number yet, so the section needs an
    /// "Add phone number" row. Without it there is no way to add a first
    /// credential at all: the section only ever listed existing ones.
    var needsAddPhoneRow: Bool {
        return !(me.creds?.contains { $0.meth == Credential.kMethPhone } ?? false)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == AccountGeneralSettingsViewController.kSectionContacts {
            return (me.creds?.count ?? 0) + (needsAddPhoneRow ? 1 : 0)
        }
        return super.tableView(tableView, numberOfRowsInSection: section)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section != AccountGeneralSettingsViewController.kSectionContacts {
            return super.tableView(tableView, cellForRowAt: indexPath)
        }

        // Cells with contacts.
        let cell = tableView.dequeueReusableCell(withIdentifier: "defaultCell") ?? UITableViewCell(style: .value1, reuseIdentifier: "defaultCell")

        // The trailing "Add phone number" row, when there is no phone yet.
        if indexPath.row >= (me.creds?.count ?? 0) {
            cell.textLabel?.text = NSLocalizedString("Add phone number", comment: "Button text")
            cell.textLabel?.textColor = .systemGreen
            cell.detailTextLabel?.text = ""
            cell.accessoryType = .none
            cell.selectionStyle = .default
            return cell
        }
        cell.textLabel?.textColor = .label

        let cred = me.creds![indexPath.row]

        var contact = cred.val
        if cred.meth == "tel", let tel = contact {
            if let number = try? Utils.phoneNumberKit.parse(tel) {
                contact = Utils.phoneNumberKit.format(number, toType: .international)
            }
        }
        cell.textLabel?.text = contact
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .none
        cell.textLabel?.sizeToFit()

        if !cred.isDone {
            cell.detailTextLabel?.text = NSLocalizedString("confirm", comment: "Button text")
        } else {
            cell.detailTextLabel?.text = ""
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
        if indexPath.section == AccountGeneralSettingsViewController.kSectionContacts {
            return 0
        }
        return super.tableView(tableView, indentationLevelForRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == AccountGeneralSettingsViewController.kSectionContacts {
            return tableView.rowHeight
        }

        return super.tableView(tableView, heightForRowAt: indexPath)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "Settings2CredChange", let container = sender as? CredentialContainer {
            let destVC = segue.destination as! CredentialsChangeViewController
            destVC.currentCredential = container.currentCred
            destVC.newCred = container.newCred?.val
        }
    }

    // Handle tap on a row with contact
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section != AccountGeneralSettingsViewController.kSectionContacts {
            // Don't call super.tableView.
            return
        }

        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.row >= (me.creds?.count ?? 0) {
            promptForPhoneNumber()
            return
        }

        guard let cred = me.creds?[indexPath.row], cred.meth != nil else { return }

        var container: CredentialContainer!
        if !cred.isDone {
            let oldCred = me.creds?.first(where: { $0.meth == cred.meth && $0.isDone })
            container = CredentialContainer(currentCred: oldCred!, newCred: cred)
        } else {
            container = CredentialContainer(currentCred: cred, newCred: nil)
        }
        performSegue(withIdentifier: "Settings2CredChange", sender: container)
    }

    /// Step 1: collect the number. Sent to the server, which then expects a
    /// confirmation code before it writes the "tel:" tag that address-book sync
    /// and phone search match on.
    private func promptForPhoneNumber() {
        let alert = UIAlertController(
            title: NSLocalizedString("Add phone number", comment: "Alert title"),
            message: NSLocalizedString("Other people can find you by this number, and it lets their address book match you automatically.", comment: "Alert message"),
            preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = NSLocalizedString("+61 412 345 678", comment: "Phone placeholder")
            field.keyboardType = .phonePad
            field.textContentType = .telephoneNumber
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Next", comment: "Alert action"), style: .default) { [weak self] _ in
            guard let self = self, let raw = alert.textFields?.first?.text else { return }
            // Normalize to E.164 — the server stores and matches the number as
            // given, so an unnormalized one would never match a contact card.
            var number = raw.trimmingCharacters(in: .whitespaces)
            if let parsed = try? Utils.phoneNumberKit.parse(number) {
                number = Utils.phoneNumberKit.format(parsed, toType: .e164)
            }
            guard !number.isEmpty else { return }

            self.me.setMeta(cred: Credential(meth: Credential.kMethPhone, val: number)).then(
                onSuccess: { [weak self] _ in
                    DispatchQueue.main.async { self?.promptForConfirmationCode(number: number) }
                    return nil
                },
                onFailure: { err in
                    DispatchQueue.main.async {
                        UiUtils.showToast(message: String(format: NSLocalizedString("Could not add the number: %@", comment: "Error"), err.localizedDescription))
                    }
                    return nil
                })
        })
        present(alert, animated: true)
    }

    /// Step 2: confirm it. This server sends no SMS — it accepts a fixed code —
    /// so the prompt says so rather than telling people to check their messages.
    private func promptForConfirmationCode(number: String) {
        let alert = UIAlertController(
            title: NSLocalizedString("Confirm number", comment: "Alert title"),
            message: String(format: NSLocalizedString("Enter the confirmation code for %@. This server does not send an SMS — the code is 123456.", comment: "Alert message"), number),
            preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = NSLocalizedString("Code", comment: "Placeholder")
            field.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Later", comment: "Alert action"), style: .cancel) { [weak self] _ in
            self?.reloadData()
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Confirm", comment: "Alert action"), style: .default) { [weak self] _ in
            guard let self = self, let code = alert.textFields?.first?.text, !code.isEmpty else { return }
            self.me.setMeta(cred: Credential(meth: Credential.kMethPhone, val: nil, resp: code, params: nil)).then(
                onSuccess: { [weak self] _ in
                    DispatchQueue.main.async {
                        UiUtils.showToast(message: NSLocalizedString("Phone number confirmed", comment: "Toast"), level: .info)
                        self?.reloadData()
                    }
                    return nil
                },
                onFailure: { err in
                    DispatchQueue.main.async {
                        UiUtils.showToast(message: String(format: NSLocalizedString("Wrong code: %@", comment: "Error"), err.localizedDescription))
                    }
                    return nil
                })
        })
        present(alert, animated: true)
    }

    // Enable swipe to delete credentials.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // The trailing "Add phone number" row has no credential behind it;
        // swiping it would index past the end of me.creds.
        return indexPath.section == AccountGeneralSettingsViewController.kSectionContacts
            && indexPath.row < (me.creds?.count ?? 0)
    }

    // Actual handling of swipes.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            guard let cred = me.creds?[indexPath.row] else { return }
            self.me.delCredential(cred).then(
                onSuccess: { [weak self] _ in
                    DispatchQueue.main.async {
                        tableView.deleteRows(at: [indexPath], with: .fade)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        // Update tags
                        self?.reloadData()
                    }
                    return nil
                },
                onFailure: UiUtils.ToastFailureHandler)
        }
    }
}

extension AccountGeneralSettingsViewController: UITextFieldDelegate {
    func textFieldDidEndEditing(_ textField: UITextField) {
        debugPrint("textFieldDidEndEditing \(textField.text ?? "")")
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let newLength = (textField.text ?? "").count + (string.count - range.length)
        if textField.tag == AccountGeneralSettingsViewController.kPersonalAlias {
            // Alias length.
            return newLength <= UiUtils.kMaxAliasLength
        }
        // Limit max length of the non-alias input.
        return newLength <= UiUtils.kMaxTitleLength
    }
}

extension AccountGeneralSettingsViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == .placeholderText {
            textView.text = nil
            textView.textColor = .secondaryLabel
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.isEmpty {
            textView.text = AccountGeneralSettingsViewController.kDescriptionPlaceholder
            textView.textColor = .placeholderText
        }
    }

    // Limit max length of the input.
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        return textView.text.count + (text.count - range.length) <= UiUtils.kMaxTopicDescriptionLength
    }
}
