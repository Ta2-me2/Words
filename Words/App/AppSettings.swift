import AppKit
import Observation
import SwiftUI

/// The app's own preferences — how it looks, and which model answers questions
/// about a card — and where those choices are kept.
///
/// Applied to AppKit rather than to SwiftUI: `preferredColorScheme` reaches the
/// views it is attached to and nothing else — not an alert, not a sheet opened
/// from the menu bar. `NSApplication.appearance` reaches everything the process
/// draws.
@Observable
final class AppSettings {

    enum Appearance: String, CaseIterable, Identifiable, Sendable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }

        /// `nil` means "whatever the Mac is set to", which is what AppKit wants
        /// to hear in order to follow it.
        var nsAppearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }

    private static let appearanceKey = "appearance"
    private static let companionKey = "companion"

    /// Apple's own model, which needs nothing installed.
    static let appleCompanion = "apple"

    /// Which model answers in the card assistant: `appleCompanion`, or the id of
    /// a model installed on this Mac.
    var companionID: String {
        didSet {
            guard oldValue != companionID else { return }
            UserDefaults.standard.set(companionID, forKey: Self.companionKey)
        }
    }

    var appearance: Appearance {
        didSet {
            guard oldValue != appearance else { return }
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
            apply()
        }
    }

    init() {
        appearance = UserDefaults.standard.string(forKey: Self.appearanceKey)
            .flatMap(Appearance.init(rawValue:)) ?? .system
        companionID = UserDefaults.standard.string(forKey: Self.companionKey) ?? Self.appleCompanion
    }

    func apply() {
        NSApplication.shared.appearance = appearance.nsAppearance
    }
}
