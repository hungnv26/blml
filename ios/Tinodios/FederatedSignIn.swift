//
//  FederatedSignIn.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import TinodeSDK
import TinodiosDB
import UIKit

/// Sign in with Google or Apple.
///
/// The provider signs the person in, Firebase Auth turns that into a Firebase
/// ID token, and the token is the secret for the server's "firebase" auth
/// scheme. The server verifies it and either signs the person into the account
/// bound to that identity or answers 404 — no account yet — in which case we
/// ask for a display name and an optional phone number, show the Terms, and
/// create one.
///
/// Apple requires Sign in with Apple wherever another third-party sign-in is
/// offered (guideline 4.8), so both buttons always go together on iOS.
final class FederatedSignIn: NSObject {
    static let kScheme = "firebase"
    static let kTermsURL = URL(string: SharedUtils.kTermsOfUseUrl)!

    /// Firebase is otherwise started only after login (push setup), but the
    /// sign-in buttons live on the login screen.
    static func ensureFirebase() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }

    /// Google needs the OAuth client ID from GoogleService-Info.plist, which is
    /// only present once Google sign-in is enabled in the Firebase console.
    /// Off until Sign in with Apple/Google is set up in Firebase Authentication
    /// for project blml-80011 (both providers still answer CONFIGURATION_NOT_FOUND).
    /// A sign-in button that can't sign anyone in gets the app rejected (2.1).
    static let isEnabled = false

    static var isGoogleAvailable: Bool {
        ensureFirebase()
        return FirebaseApp.app()?.options.clientID != nil
    }

    private weak var presenter: UIViewController?
    // Sign in with Apple state for the request in flight.
    private var currentNonce: String?
    private var appleCompletion: ((ASAuthorizationAppleIDCredential?, Error?) -> Void)?

    init(presenter: UIViewController) {
        self.presenter = presenter
        super.init()
        FederatedSignIn.ensureFirebase()
    }

    // MARK: - Google

    func signInWithGoogle() {
        guard let presenter = presenter, let clientID = FirebaseApp.app()?.options.clientID else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { [weak self] result, error in
            guard let self = self else { return }
            if let error = error {
                // Cancelling the Google sheet is not an error worth a toast.
                if (error as NSError).code != GIDSignInError.canceled.rawValue {
                    self.fail(error)
                }
                return
            }
            guard let user = result?.user, let idToken = user.idToken?.tokenString else {
                self.fail(nil)
                return
            }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                           accessToken: user.accessToken.tokenString)
            self.finish(with: credential, suggestedName: user.profile?.name)
        }
    }

    // MARK: - Apple

    func signInWithApple() {
        requestApple { [weak self] appleCredential, error in
            guard let self = self else { return }
            if let error = error {
                if (error as? ASAuthorizationError)?.code != .canceled {
                    self.fail(error)
                }
                return
            }
            guard let appleCredential = appleCredential,
                  let tokenData = appleCredential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = self.currentNonce else {
                self.fail(nil)
                return
            }
            let credential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: nonce,
                                                           fullName: appleCredential.fullName)
            // Apple sends the name only the very first time; after that it is nil.
            let name = appleCredential.fullName.flatMap {
                PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
            }
            self.finish(with: credential, suggestedName: name)
        }
    }

    private func requestApple(completion: @escaping (ASAuthorizationAppleIDCredential?, Error?) -> Void) {
        let nonce = FederatedSignIn.randomNonce()
        currentNonce = nonce
        appleCompletion = completion
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = FederatedSignIn.sha256(nonce)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: - Firebase → server

    private func finish(with credential: AuthCredential, suggestedName: String?) {
        showProgress(true)
        Auth.auth().signIn(with: credential) { [weak self] result, error in
            guard let self = self else { return }
            guard let user = result?.user, error == nil else {
                self.showProgress(false)
                self.fail(error)
                return
            }
            user.getIDToken { idToken, error in
                guard let idToken = idToken, error == nil else {
                    self.showProgress(false)
                    self.fail(error)
                    return
                }
                self.serverLogin(idToken: idToken, firebaseUid: user.uid,
                                 suggestedName: suggestedName ?? user.displayName)
            }
        }
    }

    /// The server reads the secret as base64 bytes; a Firebase ID token is a
    /// plain "header.payload.signature" string, so it is wrapped here.
    private static func secret(from idToken: String) -> String {
        return Data(idToken.utf8).base64EncodedString()
    }

    private func serverLogin(idToken: String, firebaseUid: String, suggestedName: String?) {
        let tinode = Cache.tinode
        do {
            try tinode.connectDefault(inBackground: false)?
                .thenApply { _ in
                    return tinode.login(scheme: FederatedSignIn.kScheme,
                                        secret: FederatedSignIn.secret(from: idToken), creds: nil)
                }
                .then(onSuccess: { [weak self] _ in
                    self?.signedIn(firebaseUid: firebaseUid)
                    return nil
                }, onFailure: { [weak self] err in
                    DispatchQueue.main.async {
                        self?.showProgress(false)
                        if case TinodeError.serverResponseError(let code, _, _)? = err as? TinodeError,
                           code == 404 {  // server: no account bound to this identity yet
                            // Verified identity, no account yet: offer to create one.
                            self?.completeSignUp(idToken: idToken, firebaseUid: firebaseUid,
                                                 suggestedName: suggestedName)
                        } else {
                            self?.fail(err)
                        }
                    }
                    return nil
                })
        } catch {
            showProgress(false)
            fail(error)
        }
    }

    private func signedIn(firebaseUid: String) {
        let tinode = Cache.tinode
        SharedUtils.saveAuthToken(for: FederatedSignIn.kScheme + ":" + firebaseUid,
                                  token: tinode.authToken, expires: tinode.authTokenExpires)
        if let token = tinode.authToken {
            tinode.setAutoLoginWithToken(token: token)
        }
        DispatchQueue.main.async { self.showProgress(false) }
        UiUtils.routeToChatListVC()
    }

    // MARK: - New account

    /// Name (prefilled from the provider), optional phone number, and the Terms,
    /// which must be accepted before an account is created (guideline 1.2).
    private func completeSignUp(idToken: String, firebaseUid: String, suggestedName: String?,
                                name: String? = nil, phone: String? = nil) {
        guard let presenter = presenter else { return }
        let alert = UIAlertController(
            title: NSLocalizedString("Create your BLML account", comment: "Alert title"),
            message: NSLocalizedString("Add a phone number so people who have it in their contacts can find you (optional).\n\nBy tapping Agree & Create you accept the Terms of Use: no objectionable content, no abusive behaviour.", comment: "Federated sign-up: phone and terms"),
            preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = NSLocalizedString("Your name", comment: "Placeholder")
            field.text = name ?? suggestedName
            field.autocapitalizationType = .words
            field.textContentType = .name
        }
        alert.addTextField { field in
            field.placeholder = NSLocalizedString("Phone number (optional)", comment: "Placeholder")
            field.text = phone
            field.keyboardType = .phonePad
            field.textContentType = .telephoneNumber
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Read the Terms", comment: "Alert action"), style: .default) { [weak self] _ in
            let typedName = alert.textFields?[0].text
            let typedPhone = alert.textFields?[1].text
            UIApplication.shared.open(FederatedSignIn.kTermsURL) { _ in
                // Come back to the same form with what was already typed.
                self?.completeSignUp(idToken: idToken, firebaseUid: firebaseUid, suggestedName: suggestedName,
                                     name: typedName, phone: typedPhone)
            }
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel) { _ in
            FederatedSignIn.signOut()
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Agree & Create", comment: "Alert action"), style: .default) { [weak self] _ in
            let name = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let rawPhone = alert.textFields?[1].text?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !name.isEmpty else {
                self?.completeSignUp(idToken: idToken, firebaseUid: firebaseUid, suggestedName: suggestedName,
                                     name: name, phone: rawPhone)
                return
            }
            var creds: [Credential]?
            if !rawPhone.isEmpty {
                guard let e164 = Utils.normalizedPhone(rawPhone) else {
                    UiUtils.showToast(message: Utils.kNotAPhoneNumberMessage)
                    self?.completeSignUp(idToken: idToken, firebaseUid: firebaseUid, suggestedName: suggestedName,
                                         name: name, phone: rawPhone)
                    return
                }
                creds = [Credential(meth: Credential.kMethPhone, val: e164)]
            }
            self?.createAccount(idToken: idToken, firebaseUid: firebaseUid, name: name, creds: creds)
        })
        alert.preferredAction = alert.actions.last
        presenter.present(alert, animated: true)
    }

    private func createAccount(idToken: String, firebaseUid: String, name: String, creds: [Credential]?) {
        showProgress(true)
        let desc = MetaSetDesc<TheCard, String>(pub: TheCard(fn: name), priv: nil)
        Cache.tinode.account(uid: Tinode.kUserNew, scheme: FederatedSignIn.kScheme,
                             secret: FederatedSignIn.secret(from: idToken), loginNow: true,
                             tags: nil, desc: desc, creds: creds)
            .then(onSuccess: { [weak self] _ in
                self?.signedIn(firebaseUid: firebaseUid)
                return nil
            }, onFailure: { [weak self] err in
                DispatchQueue.main.async {
                    self?.showProgress(false)
                    let text = err.localizedDescription
                    if text.contains("409") || text.lowercased().contains("duplicate") {
                        UiUtils.showToast(message: NSLocalizedString("That phone number is already used by another account.", comment: "Error: phone number taken"))
                    } else {
                        self?.fail(err)
                    }
                }
                return nil
            })
    }

    // MARK: - Sign-out and account deletion

    /// Signs out of Firebase and Google too, so the next person on this device
    /// is not silently signed in as the previous one.
    static func signOut() {
        // Logout also runs at launch when there is no saved session, before
        // FirebaseApp.configure(); Auth.auth() then aborts the app. Nothing can
        // be signed in to Firebase before it is configured anyway.
        if FirebaseApp.app() != nil {
            try? Auth.auth().signOut()
        }
        GIDSignIn.sharedInstance.signOut()
    }

    /// Before deleting a BLML account that signed in with Apple, Apple requires
    /// the app to revoke its Sign in with Apple token; that needs a fresh
    /// authorization code, so the Apple sheet is shown once more. Google and
    /// password accounts need nothing here. Calls `completion(true)` to go ahead.
    func prepareForAccountDeletion(completion: @escaping (Bool) -> Void) {
        guard FirebaseApp.app() != nil, let user = Auth.auth().currentUser else {
            completion(true)
            return
        }
        let isApple = user.providerData.contains { $0.providerID == "apple.com" }
        guard isApple else {
            user.delete { _ in completion(true) }
            return
        }
        requestApple { appleCredential, error in
            guard error == nil,
                  let codeData = appleCredential?.authorizationCode,
                  let code = String(data: codeData, encoding: .utf8) else {
                // Could not reach Apple: do not delete half-way.
                completion(false)
                return
            }
            Auth.auth().revokeToken(withAuthorizationCode: code) { _ in
                user.delete { _ in completion(true) }
            }
        }
    }

    // MARK: - Helpers

    private func showProgress(_ visible: Bool) {
        guard let presenter = presenter else { return }
        DispatchQueue.main.async {
            UiUtils.toggleProgressOverlay(in: presenter, visible: visible,
                                          title: visible ? NSLocalizedString("Signing in...", comment: "Progress overlay") : nil)
        }
    }

    private func fail(_ error: Error?) {
        Cache.log.error("FederatedSignIn failed: %@", error?.localizedDescription ?? "unknown")
        FederatedSignIn.signOut()
        DispatchQueue.main.async {
            UiUtils.showToast(message: NSLocalizedString("Sign-in failed. Please try again.", comment: "Error"))
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, length, &bytes) != errSecSuccess {
            // Fall back to UUID randomness rather than a predictable nonce.
            return UUID().uuidString + UUID().uuidString
        }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension FederatedSignIn: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let completion = appleCompletion
        appleCompletion = nil
        completion?(authorization.credential as? ASAuthorizationAppleIDCredential, nil)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let completion = appleCompletion
        appleCompletion = nil
        completion?(nil, error)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return presenter?.view.window ?? ASPresentationAnchor()
    }
}
