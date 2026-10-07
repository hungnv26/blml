//
//  SignupViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import PhoneNumberKit
import TinodeSDK
import UIKit
import TinodiosDB

class SignupViewController: UITableViewController {
    // UI positions of the Contacts fields.
    private static let kSectionGeneral = 2
    private static let kGeneralInviteCode = 1
    private static let kSectionContacts = 3
    private static let kContactsEmail = 0
    private static let kContactsTel = 1

    @IBOutlet weak var avatarImageView: RoundImageView!
    @IBOutlet weak var loginTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    @IBOutlet weak var nameTextField: UITextField!
    @IBOutlet weak var descriptionTextField: UITextField!

    /// Turns the server's raw "permission denied (403)" into something the person
    /// signing up can act on. Nothing else in signup is permission-checked, so a
    /// 403 here means the invite code was missing or wrong — and showing an HTTP
    /// status taught the reader nothing about the one field they left blank.
    private static func isInviteRefusal(_ error: Error) -> Bool {
        let text = error.localizedDescription
        return text.contains("403") || text.lowercased().contains("permission denied")
    }

    private static func signupErrorMessage(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.contains("403") || text.lowercased().contains("permission denied") {
            return NSLocalizedString(
                "This server needs an invite code. Ask whoever invited you for it.",
                comment: "Sign-up rejected because the invite code was missing or wrong")
        }
        if text.contains("409") || text.lowercased().contains("duplicate") {
            return NSLocalizedString(
                "That user name or phone number is already used by another account.",
                comment: "Sign-up rejected: login or phone number taken")
        }
        return String(format: NSLocalizedString("Failed to create account: %@",
                                                comment: "Error message"), text)
    }

    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var telTextField: PhoneNumberTextField!
    @IBOutlet weak var signUpButton: UIButton!

    // Tags sent at account creation; carries the invite code when the server is
    // configured invite-only.
    private var signupTags: [String]?

    var imagePicker: ImagePicker!
    var avatarReceived: Bool = false

    // Required credential methods.
    private var credMethods: [String]?
    // The invite code row stays hidden until the server refuses sign-up
    // without one (403): most servers, including chat.blml.app, are open.
    private var inviteRequired = false

    override func viewDidLoad() {
        super.viewDidLoad()

        // Get required credential methods.
        self.signUpButton.isEnabled = false
        _ = try? Cache.tinode.connectDefault(inBackground: false)?.then(
            onSuccess: { _ in
                if let creds = Cache.tinode.getRequiredCredMethods(forAuthLevel: "auth") {
                    self.credMethods = creds
                }
                if self.credMethods?.isEmpty ?? true {
                    self.credMethods = [Credential.kMethEmail]
                }
                DispatchQueue.main.async { self.signUpButton.isEnabled = true }
                return nil
            },
            onFailure: { err in
                Cache.log.error("Error connecting to tinode %@", err.localizedDescription)
                DispatchQueue.main.async { UiUtils.showToast(message: NSLocalizedString("Service unavailable at this time. Please try again later.", comment: "Service unavailable")) }
                return nil
            }).thenFinally {
                DispatchQueue.main.async { self.tableView.reloadData() }
            }

        self.imagePicker = ImagePicker(presentationController: self, delegate: self, editable: true)

        // Listen to text change events to clear the possible error from earlier attempt.
        loginTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        passwordTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        nameTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        emailTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        telTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        telTextField.withFlag = true
        telTextField.withPrefix = true
        telTextField.withExamplePlaceholder = true
        telTextField.withDefaultPickerUI = true
        passwordTextField.showSecureEntrySwitch()
        UiUtils.dismissKeyboardForTaps(onView: self.view)
        setupTermsFooter()
    }

    /// "By signing up you agree to the Terms of Use and the Privacy Policy" with tappable links,
    /// below the Sign up button (App Review 1.2: users must accept the terms before posting).
    private func setupTermsFooter() {
        let terms = NSLocalizedString("Terms of Use", comment: "Link to the Terms of Use")
        let privacy = NSLocalizedString("Privacy Policy", comment: "Link to the Privacy Policy")
        let text = String(format: NSLocalizedString("By signing up you agree to the %1$@ and the %2$@. No objectionable content, no abusive behaviour.", comment: "Sign-up: terms acceptance. %1$@ is 'Terms of Use', %2$@ is 'Privacy Policy'"), terms, privacy)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .footnote),
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: paragraph
        ])
        let nsText = text as NSString
        if let url = URL(string: SharedUtils.kTermsOfUseUrl) {
            attributed.addAttribute(.link, value: url, range: nsText.range(of: terms))
        }
        if let url = URL(string: SharedUtils.kPrivacyPolicyUrl) {
            attributed.addAttribute(.link, value: url, range: nsText.range(of: privacy))
        }

        let textView = UITextView()
        textView.attributedText = attributed
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 16, bottom: 24, right: 16)
        textView.accessibilityIdentifier = "signupTerms"
        termsFooter = textView
        tableView.tableFooterView = textView
    }
    private var termsFooter: UITextView?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Size the terms footer to its text.
        guard let footer = termsFooter else { return }
        let width = tableView.bounds.width
        let height = ceil(footer.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        if footer.frame.width != width || footer.frame.height != height {
            footer.frame = CGRect(x: 0, y: 0, width: width, height: height)
            tableView.tableFooterView = footer
        }
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == SignupViewController.kSectionGeneral &&
            indexPath.row == SignupViewController.kGeneralInviteCode && !inviteRequired {
            return CGFloat.leastNonzeroMagnitude
        }
        // Show only required credential fields.
        if indexPath.section == SignupViewController.kSectionContacts {
            let method = self.credMethods?.first
            // The phone row is always shown: a number is optional, but it is
            // what lets people who have it in their contacts find you.
            if indexPath.row == SignupViewController.kContactsTel {
                return super.tableView(tableView, heightForRowAt: indexPath)
            }
            if method == nil ||
                (indexPath.row == SignupViewController.kContactsEmail && method! != Credential.kMethEmail) {
                return CGFloat.leastNonzeroMagnitude
            }
        }

        return super.tableView(tableView, heightForRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == SignupViewController.kSectionContacts {
            return NSLocalizedString(
                "Phone number is optional. People who have it in their contacts can find you on BLML.",
                comment: "Sign-up: why the phone number is asked for")
        }
        return super.tableView(tableView, titleForFooterInSection: section)
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        textField.clearErrorSign()
    }

    @IBAction func addAvatarClicked(_ sender: Any) {
        // Get avatar image
        self.imagePicker.present(from: self.view)
    }

    @IBAction func signUpClicked(_ sender: Any) {
        let login = UiUtils.ensureDataInTextField(loginTextField)
        let pwd = UiUtils.ensureDataInTextField(passwordTextField)
        let name = UiUtils.ensureDataInTextField(nameTextField, maxLength: UiUtils.kMaxTitleLength)

        guard !login.isEmpty && !pwd.isEmpty && !name.isEmpty else { return }

        // The first contact field is labelled "Email or phone number": take
        // either. A phone typed there used to get an unexplained red "!".
        // Phone numbers are read leniently (spaces, local format, "possible"
        // numbers) and sent as E.164; a message says what is wrong otherwise.
        let contactText = (emailTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let telText = (telTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var contactEmail: String?
        var contactPhone: String?
        if !contactText.isEmpty {
            if case let .email(email)? = ValidatedCredential.parse(from: contactText) {
                contactEmail = email
            } else if let phone = Utils.normalizedPhone(contactText) {
                contactPhone = phone
            } else {
                emailTextField.markAsError()
                UiUtils.showToast(message: NSLocalizedString(
                    "Enter an email address or a phone number.",
                    comment: "Sign-up: the contact field holds neither an email nor a phone number"))
                return
            }
        }
        var telPhone: String?
        // The tel field shows just the country prefix ("+61") until digits are typed.
        let telDigits = telText.filter { ("0"..."9").contains($0) }
        let shownPrefix = Utils.phoneNumberKit.countryCode(for: telTextField.currentRegion).map { String($0) }
        if !telDigits.isEmpty && !(telText.hasPrefix("+") && telDigits == shownPrefix) {
            guard let phone = Utils.normalizedPhone(telText) else {
                telTextField.markAsError()
                UiUtils.showToast(message: Utils.kNotAPhoneNumberMessage)
                return
            }
            telPhone = phone
        }
        if let a = contactPhone, let b = telPhone, a != b {
            telTextField.markAsError()
            UiUtils.showToast(message: NSLocalizedString(
                "Two different phone numbers were entered. Keep one of them.",
                comment: "Sign-up: phone in the contact field differs from the phone field"))
            return
        }
        let phone = telPhone ?? contactPhone

        // Methods the server itself requires; an empty list falls back to email
        // in viewDidLoad, but then a phone number does just as well.
        let serverRequired = Cache.tinode.getRequiredCredMethods(forAuthLevel: "auth") ?? []
        var creds = [Credential]()
        for method in self.credMethods ?? [] {
            switch method {
            case Credential.kMethEmail:
                if let email = contactEmail {
                    creds.append(Credential(meth: method, val: email))
                } else if phone == nil || serverRequired.contains(Credential.kMethEmail) {
                    emailTextField.markAsError()
                    UiUtils.showToast(message: serverRequired.contains(Credential.kMethEmail) ?
                        NSLocalizedString("Enter your email address.", comment: "Sign-up: email is required") :
                        NSLocalizedString("Enter an email address or a phone number.", comment: "Sign-up: no contact given"))
                    return
                }
            case Credential.kMethPhone:
                guard phone != nil else {
                    telTextField.markAsError()
                    UiUtils.showToast(message: NSLocalizedString("Enter your phone number.", comment: "Sign-up: phone is required"))
                    return
                }
            default:
                break
            }
        }
        // The phone number, required or not, becomes the "tel:" tag that other
        // people's address books match against. The server confirms it on entry.
        if let phone = phone {
            creds.append(Credential(meth: Credential.kMethPhone, val: phone))
        }

        func doSignUp(withPublicCard pub: TheCard, withCredentials creds: [Credential]) {
            let desc = MetaSetDesc<TheCard, String>(pub: pub, priv: nil)
            desc.attachments = pub.photoRefs

            UiUtils.toggleProgressOverlay(in: self, visible: true, title: NSLocalizedString("Registering...", comment: "Progress overlay"))

            do {
                try Cache.tinode.connectDefault(inBackground: false)?
                    .thenApply { _ in
                        return Cache.tinode.createAccountBasic(uname: login, pwd: pwd, login: true, tags: self.signupTags, desc: desc, creds: creds)
                    }
                    .thenApply { [weak self] msg in
                        let tinode = Cache.tinode
                        SharedUtils.saveAuthToken(for: login, token: tinode.authToken, expires: tinode.authTokenExpires)
                        if let ctrl = msg?.ctrl, ctrl.code >= 300, ctrl.text.contains("validate credentials") {
                            DispatchQueue.main.async {
                                guard let signupVC = self else { return }
                                UiUtils.routeToCredentialsVC(in: signupVC.navigationController, verifying: ctrl.getStringArray(for: "cred")?.first)
                            }
                        } else {
                            if let token = Cache.tinode.authToken {
                                Cache.tinode.setAutoLoginWithToken(token: token)
                            }
                            UiUtils.routeToChatListVC()
                        }
                        return nil
                    }
                    .thenCatch { [weak self] err in
                        Cache.log.error("Failed to create account: %@", err.localizedDescription)
                        DispatchQueue.main.async {
                            UiUtils.showToast(message: SignupViewController.signupErrorMessage(err))
                            if let signupVC = self, SignupViewController.isInviteRefusal(err), !signupVC.inviteRequired {
                                signupVC.inviteRequired = true
                                signupVC.tableView.reloadData()
                                signupVC.descriptionTextField.becomeFirstResponder()
                            }
                        }
                        Cache.tinode.disconnect()
                        return nil
                    }
                    .thenFinally { [weak self] in
                        guard let signupVC = self else { return }
                        DispatchQueue.main.async {
                            signupVC.signUpButton.isUserInteractionEnabled = true
                            UiUtils.toggleProgressOverlay(in: signupVC, visible: false)
                        }
                    }
            } catch {
                Cache.tinode.disconnect()
                DispatchQueue.main.async {
                    UiUtils.showToast(message: SignupViewController.signupErrorMessage(error))
                    if SignupViewController.isInviteRefusal(error) && !self.inviteRequired {
                        self.inviteRequired = true
                        self.tableView.reloadData()
                        self.descriptionTextField.becomeFirstResponder()
                    }
                    self.signUpButton.isUserInteractionEnabled = true
                    UiUtils.toggleProgressOverlay(in: self, visible: false)
                }
            }
        }

        signUpButton.isUserInteractionEnabled = false

        var avatar = avatarReceived ? avatarImageView?.image?.resize(width: UiUtils.kMaxAvatarSize, height: UiUtils.kMaxAvatarSize, clip: true) : nil
        if avatar != nil && (avatar!.size.width < UiUtils.kMinAvatarSize || avatar!.size.height < UiUtils.kMinAvatarSize) {
            avatar = nil
        }

        // The former "Description" field now carries the invite code. It is sent as
        // a "code:<value>" tag, which every Tinode SDK already supports, and the
        // server strips it before storing so it never lands on the account.
        let description: String? = nil
        let inviteCode = self.descriptionTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.signupTags = inviteCode.isEmpty ? nil : ["code:" + inviteCode]
        // Remember it so "Invite a friend" can pass the same code on. Stored
        // even if signup then fails — a wrong code is overwritten by the retry.
        SharedUtils.setInviteCode(inviteCode)
        if let imageBits = avatar?.pixelData(forMimeType: Photo.kDefaultType) {
            if imageBits.count > UiUtils.kMaxInbandAvatarBytes {
                // Sending image out of band.
                Cache.getLargeFileHelper().startAvatarUpload(mimetype: Photo.kDefaultType, data: imageBits, topicId: "newacc", completionCallback: {(srvmsg, error) in
                    guard let error = error else {
                        let thumbnail = avatar!.resize(width: UiUtils.kAvatarPreviewDimensions, height: UiUtils.kAvatarPreviewDimensions, clip: true)
                        let photo = Photo(data: thumbnail?.pixelData(forMimeType: Photo.kDefaultType), ref: srvmsg?.ctrl?.getStringParam(for: "url"), width: Int(avatar!.size.width), height: Int(avatar!.size.height))
                        doSignUp(withPublicCard: TheCard(fn: name, avatar: photo, note: description), withCredentials: creds)
                        return
                    }
                    UiUtils.ToastFailureHandler(err: error)
                    DispatchQueue.main.async {
                        self.signUpButton.isUserInteractionEnabled = true
                    }
                })
                return
            }
        }

        doSignUp(withPublicCard: TheCard(fn: name, avatar: avatar, note: description), withCredentials: creds)
    }
}

extension SignupViewController: ImagePickerDelegate {
    func didSelect(media: ImagePickerMediaType?) {
        guard case .image(let image, _, _) = media,
            let image = image?.resize(width: CGFloat(UiUtils.kMaxAvatarSize), height: CGFloat(UiUtils.kMaxAvatarSize), clip: true) else { return }

        self.avatarImageView.image = image
        avatarReceived = true
    }
}
