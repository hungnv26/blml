//
//  MainNavigationController.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import UIKit

/// Navigation controller for the three root tabs (Chats, Contacts, Settings).
///
/// - The floating tab bar belongs to the three root screens only. Everything
///   pushed on top of them (a chat, a viewer, info and settings pages) hides it;
///   otherwise iOS 26's floating bar shows through behind the chat composer and
///   over full-screen media.
/// - Compact, standard-height bars with the title inline everywhere: large
///   titles cost ~50pt of every screen for a word the back button already says.
class MainNavigationController: UINavigationController {

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationBar.prefersLargeTitles = false
    }

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        if !viewControllers.isEmpty {
            viewController.hidesBottomBarWhenPushed = true
        }
        viewController.navigationItem.largeTitleDisplayMode = .never
        super.pushViewController(viewController, animated: animated)
    }

    override func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
        viewControllers.dropFirst().forEach { $0.hidesBottomBarWhenPushed = true }
        viewControllers.forEach { $0.navigationItem.largeTitleDisplayMode = .never }
        super.setViewControllers(viewControllers, animated: animated)
    }
}
