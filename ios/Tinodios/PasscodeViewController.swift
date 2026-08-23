//
//  PasscodeViewController.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import UIKit

/// The four-digit passcode screen, used both to set a code and to unlock the
/// app with it.
///
/// It draws its own keypad rather than using the system number pad. A lock
/// screen has to be unmissable and undismissable, and a keyboard can be
/// dismissed, resized, or replaced by a third-party one — none of which is
/// acceptable on the screen standing between someone and a stranger's chats.
class PasscodeViewController: UIViewController {

    enum Mode {
        /// Blocks the app until the correct code is entered.
        case unlock
        /// First-time setup: enter, then confirm.
        case setup
        /// Confirm the current code, then set a new one.
        case change
        /// Confirm the current code, then delete it.
        case remove
    }

    private let mode: Mode
    private let uid: String?
    /// Called with true when the user completed the flow, false if they backed out.
    private let onFinish: ((Bool) -> Void)?

    /// What the current entry means, which changes as a flow progresses.
    private enum Stage {
        case verifyCurrent
        case enterNew
        case confirmNew
    }
    private var stage: Stage
    /// The first of the two matching entries during setup.
    private var firstEntry: String?
    private var entry: String = "" {
        didSet { refreshDots() }
    }

    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private let errorLabel = UILabel()
    private let dotsRow = UIStackView()
    private var dots: [UIView] = []
    private let footerButton = UIButton(type: .system)

    private static let kDotSize: CGFloat = 16
    private static let kKeyDiameter: CGFloat = 76

    init(mode: Mode, uid: String?, onFinish: ((Bool) -> Void)? = nil) {
        self.mode = mode
        self.uid = uid
        self.onFinish = onFinish
        // Setup has no current code to confirm; everything else starts there.
        self.stage = (mode == .setup) ? .enterNew : .verifyCurrent
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        // The unlock screen must not be swiped away.
        isModalInPresentation = (mode == .unlock)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildLayout()
        refreshPrompt()
        refreshDots()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }

    // MARK: - Layout

    private func buildLayout() {
        titleLabel.font = UIFont.systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        hintLabel.font = UIFont.systemFont(ofSize: 15)
        hintLabel.textColor = .secondaryLabel
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0

        errorLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        errorLabel.textColor = .systemRed
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        // Reserve the line so the layout does not jump when an error appears.
        errorLabel.text = " "

        dotsRow.axis = .horizontal
        dotsRow.alignment = .center
        dotsRow.distribution = .equalSpacing
        dotsRow.spacing = 22
        for _ in 0..<Passcode.kLength {
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: PasscodeViewController.kDotSize).isActive = true
            dot.heightAnchor.constraint(equalToConstant: PasscodeViewController.kDotSize).isActive = true
            dot.layer.cornerRadius = PasscodeViewController.kDotSize / 2
            dot.layer.borderWidth = 1.5
            dot.layer.borderColor = UIColor.separator.cgColor
            dots.append(dot)
            dotsRow.addArrangedSubview(dot)
        }

        let header = UIStackView(arrangedSubviews: [titleLabel, hintLabel])
        header.axis = .vertical
        header.spacing = 8

        let top = UIStackView(arrangedSubviews: [header, dotsRow, errorLabel])
        top.axis = .vertical
        top.alignment = .center
        top.spacing = 28

        let keypad = buildKeypad()

        configureFooterButton()

        let root = UIStackView(arrangedSubviews: [top, keypad, footerButton])
        root.axis = .vertical
        root.alignment = .center
        root.spacing = 40
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            root.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            root.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            header.widthAnchor.constraint(lessThanOrEqualToConstant: 320)
        ])

        if mode != .unlock {
            navigationItem.leftBarButtonItem = nil
            let cancel = UIButton(type: .system)
            cancel.setTitle(NSLocalizedString("Cancel", comment: ""), for: .normal)
            cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
            cancel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(cancel)
            NSLayoutConstraint.activate([
                cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
                cancel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20)
            ])
        }
    }

    private func buildKeypad() -> UIStackView {
        let grid = UIStackView()
        grid.axis = .vertical
        grid.alignment = .center
        grid.spacing = 16

        let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]]
        for row in rows {
            let line = UIStackView()
            line.axis = .horizontal
            line.spacing = 24
            line.alignment = .center
            for label in row {
                line.addArrangedSubview(makeKey(label))
            }
            grid.addArrangedSubview(line)
        }
        return grid
    }

    private func makeKey(_ label: String) -> UIView {
        let size = PasscodeViewController.kKeyDiameter
        if label.isEmpty {
            // A spacer, so "0" stays centred under "8".
            let filler = UIView()
            filler.translatesAutoresizingMaskIntoConstraints = false
            filler.widthAnchor.constraint(equalToConstant: size).isActive = true
            filler.heightAnchor.constraint(equalToConstant: size).isActive = true
            return filler
        }

        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: size).isActive = true
        button.heightAnchor.constraint(equalToConstant: size).isActive = true
        button.setTitle(label, for: .normal)

        if label == "⌫" {
            button.titleLabel?.font = UIFont.systemFont(ofSize: 24)
            button.setTitleColor(.secondaryLabel, for: .normal)
            button.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)
        } else {
            button.titleLabel?.font = UIFont.systemFont(ofSize: 30, weight: .regular)
            button.setTitleColor(.label, for: .normal)
            button.backgroundColor = .secondarySystemBackground
            button.layer.cornerRadius = size / 2
            button.addTarget(self, action: #selector(digitTapped(_:)), for: .touchUpInside)
        }
        return button
    }

    private func configureFooterButton() {
        switch mode {
        case .unlock:
            // Without a way out, forgetting the code would leave the app
            // permanently unusable and reinstalling the only remedy.
            footerButton.setTitle(NSLocalizedString("Forgot passcode? Log out", comment: "Passcode screen escape hatch"), for: .normal)
            footerButton.addTarget(self, action: #selector(logOutTapped), for: .touchUpInside)
        default:
            footerButton.setTitle("", for: .normal)
            footerButton.isHidden = true
        }
        footerButton.titleLabel?.font = UIFont.systemFont(ofSize: 15)
    }

    // MARK: - Prompt and dots

    private func refreshPrompt() {
        switch (mode, stage) {
        case (.unlock, _):
            titleLabel.text = NSLocalizedString("Enter passcode", comment: "Passcode screen title")
            hintLabel.text = NSLocalizedString("BLML is locked.", comment: "Passcode screen subtitle")
        case (.change, .verifyCurrent), (.remove, .verifyCurrent):
            titleLabel.text = NSLocalizedString("Enter current passcode", comment: "Passcode screen title")
            hintLabel.text = nil
        case (_, .enterNew):
            titleLabel.text = NSLocalizedString("Choose a passcode", comment: "Passcode screen title")
            hintLabel.text = NSLocalizedString("Four digits. You will need it every time you open BLML.", comment: "Passcode screen subtitle")
        case (_, .confirmNew):
            titleLabel.text = NSLocalizedString("Confirm your passcode", comment: "Passcode screen title")
            hintLabel.text = NSLocalizedString("Enter the same four digits again.", comment: "Passcode screen subtitle")
        default:
            titleLabel.text = NSLocalizedString("Enter passcode", comment: "Passcode screen title")
            hintLabel.text = nil
        }
    }

    private func refreshDots() {
        for (index, dot) in dots.enumerated() {
            let filled = index < entry.count
            dot.backgroundColor = filled ? UIColor(fromHexCode: 0xff00a884) : .clear
            dot.layer.borderColor = filled ? UIColor(fromHexCode: 0xff00a884).cgColor : UIColor.separator.cgColor
        }
    }

    private func showError(_ message: String) {
        errorLabel.text = message
        entry = ""
        let shake = CAKeyframeAnimation(keyPath: "position.x")
        shake.values = [0, 10, -10, 8, -8, 0] as [NSNumber]
        shake.duration = 0.35
        shake.isAdditive = true
        dotsRow.layer.add(shake, forKey: "shake")
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    // MARK: - Input

    @objc private func digitTapped(_ sender: UIButton) {
        guard entry.count < Passcode.kLength, let digit = sender.title(for: .normal) else { return }
        errorLabel.text = " "
        entry.append(digit)
        if entry.count == Passcode.kLength {
            // Let the last dot paint before the screen changes under it.
            let complete = entry
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.process(complete)
            }
        }
    }

    @objc private func backspaceTapped() {
        guard !entry.isEmpty else { return }
        entry.removeLast()
    }

    @objc private func cancelTapped() {
        dismiss(animated: true) { [weak self] in self?.onFinish?(false) }
    }

    @objc private func logOutTapped() {
        let alert = UIAlertController(
            title: nil,
            message: NSLocalizedString("Logging out clears the passcode. You will need your account password to sign back in.", comment: "Passcode logout warning"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Log out", comment: "Alert action"), style: .destructive, handler: { [weak self] _ in
            guard let self = self else { return }
            Passcode.clear(for: self.uid)
            self.dismiss(animated: false) {
                UiUtils.logoutAndRouteToLoginVC()
            }
        }))
        present(alert, animated: true)
    }

    // MARK: - Flow

    private func process(_ code: String) {
        switch stage {
        case .verifyCurrent:
            guard Passcode.verify(code, for: uid) else {
                showError(NSLocalizedString("Wrong passcode. Try again.", comment: "Passcode error"))
                return
            }
            switch mode {
            case .unlock:
                finish(true)
            case .remove:
                Passcode.clear(for: uid)
                finish(true)
            default:
                entry = ""
                stage = .enterNew
                refreshPrompt()
            }

        case .enterNew:
            firstEntry = code
            entry = ""
            stage = .confirmNew
            refreshPrompt()

        case .confirmNew:
            guard code == firstEntry else {
                // Send them back to the first entry: re-confirming against a
                // code they may have mistyped would lock in the typo.
                firstEntry = nil
                stage = .enterNew
                refreshPrompt()
                showError(NSLocalizedString("Those did not match. Start again.", comment: "Passcode error"))
                return
            }
            guard Passcode.set(code, for: uid) else {
                showError(NSLocalizedString("Could not save the passcode.", comment: "Passcode error"))
                return
            }
            finish(true)
        }
    }

    private func finish(_ success: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss(animated: true) { [weak self] in self?.onFinish?(success) }
    }
}
