//
//  AttachmentSheetViewController.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import UIKit

/// What the user picked from the attachment sheet. The plain Bool this replaced
/// could only say "file or image", which is not enough to open the camera
/// directly instead of going through a second action sheet.
public enum AttachmentKind {
    case document
    case camera
    case gallery
    case audio
}

/// WhatsApp-style attachment sheet: a grid of coloured circles sliding up from
/// the bottom, instead of a stock action sheet.
///
/// Presented over the current context rather than with
/// `sheetPresentationController`, which is iOS 15+; the app still targets 14.
public class AttachmentSheetViewController: UIViewController {
    private struct Item {
        let kind: AttachmentKind
        let title: String
        let systemImage: String
        let color: UIColor
    }

    // Only capabilities the app actually has. No Location/Contact/Poll rows
    // that would open nothing.
    private let items: [Item] = [
        Item(kind: .document, title: NSLocalizedString("Document", comment: "Attachment type"),
             systemImage: "doc.fill", color: UIColor(fromHexCode: 0xff7f66ff)),
        Item(kind: .camera, title: NSLocalizedString("Camera", comment: "Attachment type"),
             systemImage: "camera.fill", color: UIColor(fromHexCode: 0xffff2e74)),
        Item(kind: .gallery, title: NSLocalizedString("Gallery", comment: "Attachment type"),
             systemImage: "photo.fill", color: UIColor(fromHexCode: 0xffc042f5)),
        Item(kind: .audio, title: NSLocalizedString("Audio", comment: "Attachment type"),
             systemImage: "headphones", color: UIColor(fromHexCode: 0xffff7a1a))
    ]

    private let panel = UIView()
    private let dimmer = UIView()
    private var panelBottom: NSLayoutConstraint!

    /// Called with the chosen kind after the sheet has dismissed itself.
    public var onSelect: ((AttachmentKind) -> Void)?

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dimmer.alpha = 0
        dimmer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimmer)
        dimmer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissSheet)))

        panel.backgroundColor = .systemBackground
        panel.layer.cornerRadius = 18
        // Round only the top corners, so the panel reads as attached to the
        // bottom edge the way WhatsApp's does.
        panel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)

        let grabber = UIView()
        grabber.backgroundColor = .tertiaryLabel
        grabber.layer.cornerRadius = 2.5
        grabber.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(grabber)

        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.alignment = .top
        row.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(row)

        for (index, item) in items.enumerated() {
            row.addArrangedSubview(makeButton(for: item, tag: index))
        }

        panelBottom = panel.topAnchor.constraint(equalTo: view.bottomAnchor)

        NSLayoutConstraint.activate([
            dimmer.topAnchor.constraint(equalTo: view.topAnchor),
            dimmer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dimmer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Extends past the bottom safe area so no gap shows under the panel.
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panelBottom,

            grabber.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
            grabber.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 36),
            grabber.heightAnchor.constraint(equalToConstant: 5),

            row.topAnchor.constraint(equalTo: grabber.bottomAnchor, constant: 20),
            row.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            row.bottomAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    private func makeButton(for item: Item, tag: Int) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.alignment = .center
        container.spacing = 8

        let circle = UIButton(type: .custom)
        circle.tag = tag
        circle.backgroundColor = item.color
        circle.layer.cornerRadius = 29
        circle.tintColor = .white
        circle.setImage(UIImage(systemName: item.systemImage,
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)),
                        for: .normal)
        circle.addTarget(self, action: #selector(itemTapped(_:)), for: .touchUpInside)
        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.widthAnchor.constraint(equalToConstant: 58).isActive = true
        circle.heightAnchor.constraint(equalToConstant: 58).isActive = true

        let label = UILabel()
        label.text = item.title
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.textAlignment = .center

        container.addArrangedSubview(circle)
        container.addArrangedSubview(label)
        return container
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Slide up from below the screen once the panel's real height is known.
        view.layoutIfNeeded()
        panelBottom.isActive = false
        UIView.animate(withDuration: 0.25) {
            self.dimmer.alpha = 1
            self.view.layoutIfNeeded()
        }
    }

    @objc private func itemTapped(_ sender: UIButton) {
        let kind = items[sender.tag].kind
        // Report only after dismissal completes: the camera and document
        // pickers are presented by the same parent and cannot come up while it
        // is still dismissing this sheet.
        dismiss(animated: false) { [weak self] in
            self?.onSelect?(kind)
        }
    }

    @objc private func dismissSheet() {
        UIView.animate(withDuration: 0.2, animations: {
            self.dimmer.alpha = 0
        }, completion: { _ in
            self.dismiss(animated: false)
        })
    }

    /// Presents the sheet over `parent`.
    public static func present(over parent: UIViewController, onSelect: @escaping (AttachmentKind) -> Void) {
        let sheet = AttachmentSheetViewController()
        sheet.onSelect = onSelect
        sheet.modalPresentationStyle = .overFullScreen
        sheet.modalTransitionStyle = .crossDissolve
        parent.present(sheet, animated: false)
    }
}
