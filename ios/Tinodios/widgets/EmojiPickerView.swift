//
//  EmojiPickerView.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import UIKit

/// A keyboard-sized panel of stickers, shown in place of the system keyboard.
///
/// Deliberately plain emoji rather than downloaded image packs: they need no
/// server storage, no asset pipeline and no extra permissions, they render at
/// any size, and they travel as ordinary text so every client — including the
/// web app — already displays them.
class EmojiPickerView: UIView {
    private struct Category {
        let symbol: String
        let emoji: [String]
        /// Items per row. The first page shows fewer, larger stickers; the
        /// browse-everything pages pack them tighter.
        var perRow: Int = 6
    }

    private static let categories: [Category] = [
        // The page the picker opens on: the handful of things people actually
        // send — a like, a heart, congratulations, a birthday, thanks, sure.
        // Paired emoji where one alone reads ambiguously (🎂 could be "cake",
        // 🎂🎉 is unmistakably "happy birthday").
        Category(symbol: "star.fill", emoji: [
            "👍", "❤️", "🎉", "🎂🎉", "🙏", "👌",
            "😂", "😍", "👏", "🔥", "💯", "✅",
            "👋", "🤝", "🥰", "😮", "😢", "🤔",
            "💪", "🙌", "🎁", "💐", "🍀", "⭐",
            "😅", "🤷", "😴", "☕", "🌹", "🎊"
        ], perRow: 5),
        Category(symbol: "face.smiling", emoji: [
            "😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "🙃",
            "😉", "😊", "😇", "🥰", "😍", "🤩", "😘", "😗", "😚", "😙",
            "😋", "😛", "😜", "🤪", "😝", "🤑", "🤗", "🤭", "🤫", "🤔",
            "🤐", "🤨", "😐", "😑", "😶", "😏", "😒", "🙄", "😬", "😌",
            "😔", "😪", "🤤", "😴", "😷", "🤒", "🤕", "🥵", "🥶", "🥴",
            "😵", "🤯", "🤠", "🥳", "😎", "🤓", "🧐", "😕", "😟", "🙁",
            "😮", "😯", "😲", "😳", "🥺", "😦", "😧", "😨", "😰", "😥",
            "😢", "😭", "😱", "😖", "😣", "😞", "😓", "😩", "😫", "🥱",
            "😤", "😡", "😠", "🤬", "😈", "👿", "💀", "💩", "🤡", "👻"
        ]),
        Category(symbol: "hand.thumbsup", emoji: [
            "👍", "👎", "👌", "🤌", "✌️", "🤞", "🤟", "🤘", "🤙", "👈",
            "👉", "👆", "👇", "☝️", "✋", "🤚", "🖐️", "🖖", "👋", "🤝",
            "🙏", "✊", "👊", "🤛", "🤜", "👏", "🙌", "👐", "🤲", "💪",
            "🦾", "👀", "👁️", "👂", "👃", "👄", "🧠", "🦴", "🫀", "🤳"
        ]),
        Category(symbol: "heart", emoji: [
            "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔",
            "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💟", "♥️",
            "💯", "💢", "💥", "💫", "💦", "💨", "🔥", "✨", "🌟", "⭐"
        ]),
        Category(symbol: "pawprint", emoji: [
            "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯",
            "🦁", "🐮", "🐷", "🐸", "🐵", "🙈", "🙉", "🙊", "🐔", "🐧",
            "🐦", "🐤", "🦆", "🦅", "🦉", "🦇", "🐺", "🐗", "🐴", "🦄",
            "🐝", "🐛", "🦋", "🐌", "🐞", "🐢", "🐍", "🐙", "🦑", "🦀",
            "🐬", "🐳", "🐟", "🐊", "🐆", "🦓", "🦍", "🐘", "🐫", "🦒"
        ]),
        Category(symbol: "fork.knife", emoji: [
            "🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐",
            "🍈", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🥑", "🍆",
            "🥕", "🌽", "🌶️", "🥒", "🥬", "🥦", "🧄", "🧅", "🍄", "🥜",
            "🍞", "🥐", "🥖", "🧀", "🥚", "🍳", "🥞", "🥓", "🍔", "🍟",
            "🍕", "🌭", "🥪", "🌮", "🌯", "🍜", "🍲", "🍣", "🍱", "🍚",
            "🍦", "🍰", "🎂", "🍫", "🍬", "🍭", "🍩", "🍪", "☕", "🍺"
        ]),
        Category(symbol: "figure.walk", emoji: [
            "⚽", "🏀", "🏈", "⚾", "🎾", "🏐", "🏉", "🎱", "🏓", "🏸",
            "🥅", "🏒", "🏑", "🏏", "⛳", "🏹", "🎣", "🥊", "🥋", "⛸️",
            "🎿", "🛷", "🏂", "🏋️", "🤸", "🤼", "🤽", "🤾", "🚴", "🚵",
            "🏆", "🥇", "🥈", "🥉", "🎖️", "🎯", "🎲", "🎮", "🎰", "🎳",
            "🎤", "🎧", "🎼", "🎹", "🥁", "🎷", "🎺", "🎸", "🎻", "🎬"
        ]),
        Category(symbol: "car", emoji: [
            "🚗", "🚕", "🚙", "🚌", "🚎", "🏎️", "🚓", "🚑", "🚒", "🚐",
            "🚚", "🚛", "🚜", "🛴", "🚲", "🛵", "🏍️", "✈️", "🚀", "🛸",
            "🚁", "⛵", "🚤", "🛳️", "⚓", "🚦", "🗺️", "🗿", "🗽", "🗼",
            "🏰", "🏠", "🏢", "🏥", "🏦", "🏫", "⛰️", "🏖️", "🏝️", "🌋",
            "🌅", "🌄", "🌈", "☀️", "🌤️", "⛅", "🌧️", "⛈️", "❄️", "🌙"
        ]),
        Category(symbol: "lightbulb", emoji: [
            "⌚", "📱", "💻", "⌨️", "🖥️", "🖨️", "📷", "📹", "🎥", "📺",
            "📻", "☎️", "📞", "📟", "🔋", "🔌", "💡", "🔦", "🕯️", "🧯",
            "💰", "💳", "💎", "⚖️", "🔧", "🔨", "🛠️", "🔑", "🔒", "🔓",
            "📦", "📫", "📮", "📝", "📚", "📖", "🔍", "🔎", "🎁", "🎈",
            "🎉", "🎊", "🎀", "🎄", "🧨", "🔔", "⏰", "⏳", "🧭", "🩺"
        ]),
        Category(symbol: "number", emoji: [
            "✅", "❌", "⭕", "❗", "❓", "‼️", "⁉️", "💤", "🚫", "⚠️",
            "♻️", "🔱", "⚜️", "🔰", "✳️", "❇️", "©️", "®️", "™️", "🆗",
            "🆒", "🆕", "🆓", "🔝", "🔙", "🔜", "🔛", "🔃", "🔄", "▶️",
            "⏸️", "⏹️", "⏺️", "⏭️", "⏮️", "🔀", "🔁", "🔂", "➕", "➖",
            "0️⃣", "1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣", "6️⃣", "7️⃣", "8️⃣", "9️⃣"
        ])
    ]

    /// Called with the chosen emoji.
    var onPick: ((String) -> Void)?
    /// Called when the backspace key is tapped.
    var onDelete: (() -> Void)?

    private var collectionView: UICollectionView!
    private var categoryBar: UIStackView!
    private var currentCategory = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Matches the composer bar so the panel reads as part of it.
        backgroundColor = UIColor(fromHexCode: 0xff1f2c33)

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 6
        layout.sectionInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(EmojiCell.self, forCellWithReuseIdentifier: "emoji")
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionView)

        categoryBar = UIStackView()
        categoryBar.axis = .horizontal
        categoryBar.distribution = .fillEqually
        categoryBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(categoryBar)

        for (index, cat) in EmojiPickerView.categories.enumerated() {
            let b = UIButton(type: .system)
            b.tag = index
            b.tintColor = index == 0 ? UIColor(fromHexCode: 0xff25d366) : UIColor(fromHexCode: 0xff8696a0)
            b.setImage(UIImage(systemName: cat.symbol,
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 15)), for: .normal)
            b.addTarget(self, action: #selector(categoryTapped(_:)), for: .touchUpInside)
            categoryBar.addArrangedSubview(b)
        }

        let backspace = UIButton(type: .system)
        backspace.tintColor = UIColor(fromHexCode: 0xff8696a0)
        backspace.setImage(UIImage(systemName: "delete.left",
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 15)), for: .normal)
        backspace.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        categoryBar.addArrangedSubview(backspace)

        NSLayoutConstraint.activate([
            categoryBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            categoryBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            categoryBar.topAnchor.constraint(equalTo: topAnchor),
            categoryBar.heightAnchor.constraint(equalToConstant: 40),

            collectionView.topAnchor.constraint(equalTo: categoryBar.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            // safeAreaLayoutGuide: on a home-indicator phone the last row would
            // otherwise sit under the indicator.
            collectionView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    @objc private func categoryTapped(_ sender: UIButton) {
        currentCategory = sender.tag
        for (i, v) in categoryBar.arrangedSubviews.enumerated() {
            (v as? UIButton)?.tintColor = (i == currentCategory)
                ? UIColor(fromHexCode: 0xff25d366)
                : UIColor(fromHexCode: 0xff8696a0)
        }
        collectionView.reloadData()
        collectionView.setContentOffset(.zero, animated: false)
    }

    @objc private func deleteTapped() {
        onDelete?()
    }
}

extension EmojiPickerView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return EmojiPickerView.categories[currentCategory].emoji.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "emoji", for: indexPath) as! EmojiCell
        let cat = EmojiPickerView.categories[currentCategory]
        cell.label.text = cat.emoji[indexPath.item]
        // Bigger cells on the first page deserve a bigger glyph.
        cell.label.font = .systemFont(ofSize: cat.perRow <= 5 ? 40 : 32)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        // Fixed count per row on any width, so the grid never leaves a ragged edge.
        let perRow = CGFloat(EmojiPickerView.categories[currentCategory].perRow)
        let side = floor((collectionView.bounds.width - 16) / perRow)
        return CGSize(width: side, height: side)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onPick?(EmojiPickerView.categories[currentCategory].emoji[indexPath.item])
    }
}

private class EmojiCell: UICollectionViewCell {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 32)
        label.textAlignment = .center
        // A paired entry is twice as wide as a single glyph; shrink rather
        // than clip it.
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.frame = contentView.bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
