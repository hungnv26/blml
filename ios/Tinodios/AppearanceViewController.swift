//
//  AppearanceViewController.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import UIKit

/// Theme picker plus an entry to the chat wallpaper gallery.
/// Mirrors Android's General settings screen, which has had both for a while.
class AppearanceViewController: UITableViewController {
    private static let kSectionTheme = 0
    private static let kSectionWallpaper = 1

    private let themes = AppearanceSettings.Theme.allCases

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("Appearance", comment: "Screen title")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == AppearanceViewController.kSectionTheme
            ? NSLocalizedString("Select theme", comment: "Section header")
            : NSLocalizedString("Chat wallpaper", comment: "Section header")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == AppearanceViewController.kSectionTheme ? themes.count : 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryView = nil

        if indexPath.section == AppearanceViewController.kSectionTheme {
            let theme = themes[indexPath.row]
            cell.textLabel?.text = theme.title
            cell.accessoryType = theme == AppearanceSettings.theme ? .checkmark : .none
            cell.imageView?.image = UIImage(systemName: {
                switch theme {
                case .system: return "circle.lefthalf.filled"
                case .light: return "sun.max"
                case .dark: return "moon"
                }
            }())
        } else {
            cell.textLabel?.text = NSLocalizedString("Change wallpaper", comment: "Menu item")
            cell.imageView?.image = UIImage(systemName: "photo.on.rectangle")
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == AppearanceViewController.kSectionTheme {
            AppearanceSettings.theme = themes[indexPath.row]
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
        } else {
            navigationController?.pushViewController(WallpaperViewController(), animated: true)
        }
    }
}
