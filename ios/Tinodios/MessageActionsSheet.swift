//
//  MessageActionsSheet.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import UIKit

/// The Zalo-style hold-a-message sheet: a quick-reaction emoji row on top,
/// then the actions that apply to the pressed message. Replaces the old
/// UIMenuController strip.
class MessageActionsSheet: UIViewController {

    struct Action {
        let title: String
        let systemImage: String
        let destructive: Bool
        let handler: () -> Void

        init(_ title: String, _ systemImage: String, destructive: Bool = false, handler: @escaping () -> Void) {
            self.title = title
            self.systemImage = systemImage
            self.destructive = destructive
            self.handler = handler
        }
    }

    private let actions: [Action]
    private let onReaction: (String) -> Void

    init(actions: [Action], onReaction: @escaping (String) -> Void) {
        self.actions = actions
        self.onReaction = onReaction
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissSheet)))

        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 0

        // Quick reactions.
        let reactionsRow = UIStackView()
        reactionsRow.axis = .horizontal
        reactionsRow.distribution = .fillEqually
        reactionsRow.heightAnchor.constraint(equalToConstant: 56).isActive = true
        for emoji in MessageReactions.kQuickReactions {
            let b = UIButton(type: .system)
            b.setTitle(emoji, for: .normal)
            b.titleLabel?.font = UIFont.systemFont(ofSize: 30)
            b.addAction(UIAction { [weak self] _ in
                self?.dismiss(animated: true) { self?.onReaction(emoji) }
            }, for: .touchUpInside)
            reactionsRow.addArrangedSubview(b)
        }
        card.addArrangedSubview(wrap(reactionsRow, cornerRadius: 24, margin: 0))
        card.setCustomSpacing(10, after: card.arrangedSubviews.last!)

        // Action rows.
        let list = UIStackView()
        list.axis = .vertical
        for (i, action) in actions.enumerated() {
            if i > 0 {
                let sep = UIView()
                sep.backgroundColor = .separator
                sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                list.addArrangedSubview(sep)
            }
            list.addArrangedSubview(row(for: action))
        }
        card.addArrangedSubview(wrap(list, cornerRadius: 14, margin: 0))

        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            card.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func wrap(_ inner: UIView, cornerRadius: CGFloat, margin: CGFloat) -> UIView {
        let box = UIView()
        box.backgroundColor = .systemBackground
        box.layer.cornerRadius = cornerRadius
        box.clipsToBounds = true
        inner.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: box.topAnchor, constant: margin),
            inner.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -margin),
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: margin),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -margin)
        ])
        return box
    }

    private func row(for action: Action) -> UIView {
        let color: UIColor = action.destructive ? .systemRed : .label
        var config = UIButton.Configuration.plain()
        config.title = action.title
        config.image = UIImage(systemName: action.systemImage)
        config.imagePadding = 14
        config.baseForegroundColor = color
        config.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 18, bottom: 13, trailing: 18)
        let b = UIButton(configuration: config)
        b.contentHorizontalAlignment = .leading
        b.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true) { action.handler() }
        }, for: .touchUpInside)
        return b
    }

    @objc private func dismissSheet() {
        dismiss(animated: true)
    }
}
