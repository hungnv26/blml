//
//  AppearanceSettings.swift
//  Tinodios
//
//  Copyright © 2026 BLML. All rights reserved.
//

import TinodiosDB
import UIKit

/// Theme and chat-wallpaper preferences.
///
/// Android has had both since upstream; iOS only ever followed the system theme
/// and hard-coded a single wallpaper. This brings the two clients level.
public class AppearanceSettings {
    public enum Theme: String, CaseIterable {
        case system
        case light
        case dark

        public var title: String {
            switch self {
            case .system: return NSLocalizedString("Follow System", comment: "Theme option")
            case .light: return NSLocalizedString("Light", comment: "Theme option")
            case .dark: return NSLocalizedString("Dark", comment: "Theme option")
            }
        }

        var interfaceStyle: UIUserInterfaceStyle {
            switch self {
            case .system: return .unspecified
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    private static let kPrefTheme = "appearance_theme"
    private static let kPrefWallpaper = "appearance_wallpaper"

    private static var defaults: UserDefaults { SharedUtils.kAppDefaults }

    public static var theme: Theme {
        get {
            let raw = defaults.string(forKey: kPrefTheme) ?? Theme.system.rawValue
            return Theme(rawValue: raw) ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: kPrefTheme)
            apply()
        }
    }

    /// File name of the chosen wallpaper on the server, e.g. "a03.jpg".
    /// Nil means the built-in BLML doodle tile.
    public static var wallpaper: String? {
        get {
            let name = defaults.string(forKey: kPrefWallpaper)
            return (name?.isEmpty ?? true) ? nil : name
        }
        set {
            if let name = newValue, !name.isEmpty {
                defaults.set(name, forKey: kPrefWallpaper)
            } else {
                defaults.removeObject(forKey: kPrefWallpaper)
            }
        }
    }

    /// Pushes the stored theme onto every window. Called at launch and whenever
    /// the choice changes; setting it on the window rather than a single view
    /// controller is what makes it apply app-wide, including modals.
    public static func apply() {
        let style = theme.interfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }

    /// Where the server hosts its wallpaper gallery. Same layout Android reads:
    /// `<origin>/img/bkg/index.json` listing patterns and full images.
    public static func wallpaperBaseURL() -> URL? {
        let (host, tls) = SharedUtils.getConnectionSettings()
        guard let host = host else { return nil }
        return URL(string: ((tls ?? false) ? "https://" : "http://") + host + "/img/bkg/")
    }

    public static func wallpaperURL(for name: String) -> URL? {
        return wallpaperBaseURL()?.appendingPathComponent(name)
    }
}
