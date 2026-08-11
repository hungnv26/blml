//
//  WallpaperViewController.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import UIKit

/// Chat wallpaper gallery, reading the same `/img/bkg/index.json` the Android
/// client uses. The gallery is served by our own server (it ships with the web
/// app's static files), so there is no third-party dependency here.
class WallpaperViewController: UIViewController {
    private struct Index: Decodable {
        struct Pattern: Decodable {
            let name: String
        }
        let patt: [Pattern]?
    }

    private var names: [String] = []
    private var collectionView: UICollectionView!
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let message = UILabel()

    // Thumbnails are small and few; an in-memory cache avoids refetching while
    // scrolling without pulling in an image-loading library.
    private var thumbnails: [String: UIImage] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("Chat wallpaper", comment: "Screen title")
        view.backgroundColor = .systemBackground

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(WallpaperCell.self, forCellWithReuseIdentifier: "wp")
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        message.textAlignment = .center
        message.numberOfLines = 0
        message.textColor = .secondaryLabel
        message.isHidden = true
        message.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(message)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            message.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            message.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            message.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("Default", comment: "Restore the built-in wallpaper"),
            style: .plain, target: self, action: #selector(restoreDefault))

        loadIndex()
    }

    @objc private func restoreDefault() {
        AppearanceSettings.wallpaper = nil
        collectionView.reloadData()
        UiUtils.showToast(message: NSLocalizedString("Wallpaper restored", comment: "Toast"), level: .info)
    }

    private func loadIndex() {
        guard let base = AppearanceSettings.wallpaperBaseURL() else {
            showMessage(NSLocalizedString("Not connected to a server.", comment: "Error"))
            return
        }
        spinner.startAnimating()
        let url = base.appendingPathComponent("index.json")
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.spinner.stopAnimating()
                guard let data = data, error == nil,
                      let index = try? JSONDecoder().decode(Index.self, from: data) else {
                    // The gallery ships with the web app; a server built without
                    // it simply has no wallpapers, which is not an app failure.
                    self.showMessage(NSLocalizedString("No wallpapers available on this server.", comment: "Error"))
                    return
                }
                self.names = (index.patt ?? []).map { $0.name }
                if self.names.isEmpty {
                    self.showMessage(NSLocalizedString("No wallpapers available on this server.", comment: "Error"))
                } else {
                    self.collectionView.reloadData()
                }
            }
        }.resume()
    }

    private func showMessage(_ text: String) {
        message.text = text
        message.isHidden = false
        collectionView.isHidden = true
    }

    fileprivate func thumbnail(for name: String, into cell: WallpaperCell) {
        if let image = thumbnails[name] {
            cell.imageView.image = image
            return
        }
        cell.imageView.image = nil
        guard let url = AppearanceSettings.wallpaperURL(for: name) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            // Keep the bytes so the chat view can paint this wallpaper without
            // going back to the network when a conversation opens.
            MessageViewController.storeWallpaper(data, named: name)
            DispatchQueue.main.async {
                self?.thumbnails[name] = image
                // The cell may have been reused for a different wallpaper by the
                // time this lands; only paint it if it still wants this one.
                if cell.name == name {
                    cell.imageView.image = image
                }
            }
        }.resume()
    }
}

extension WallpaperViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return names.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "wp", for: indexPath) as! WallpaperCell
        let name = names[indexPath.item]
        cell.name = name
        cell.isChosen = (AppearanceSettings.wallpaper == name)
        thumbnail(for: name, into: cell)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let side = (collectionView.bounds.width - 4) / 3
        return CGSize(width: side, height: side)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let name = names[indexPath.item]
        AppearanceSettings.wallpaper = name
        // The chat paints whichever of the l/d pair matches the active theme,
        // so pull the counterpart down now while the user is still here —
        // otherwise the first theme switch briefly falls back to the default.
        let counterpart = MessageViewController.themedWallpaperName(name, darkMode: name.hasPrefix("l"))
        if counterpart != name {
            MessageViewController.fetchWallpaper(named: counterpart) {}
        }
        collectionView.reloadData()
        UiUtils.showToast(message: NSLocalizedString("Wallpaper applied", comment: "Toast"), level: .info)
    }
}

private class WallpaperCell: UICollectionViewCell {
    let imageView = UIImageView()
    /// Which wallpaper this cell currently represents, so an async thumbnail
    /// that arrives after reuse can tell it is stale.
    var name: String?

    var isChosen: Bool = false {
        didSet {
            contentView.layer.borderWidth = isChosen ? 3 : 0
            contentView.layer.borderColor = UIColor.systemGreen.cgColor
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.backgroundColor = .secondarySystemBackground
        contentView.addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
