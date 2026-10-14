import SwiftUI

/// The small button beside the sidebar toggle: the app's own settings.
///
/// It opens the same window as ⌘, rather than a panel of its own. There was
/// once only one preference worth setting — how the application looks — and a
/// popover was the honest size for it; since then the window has grown a
/// companion to choose and a model to install, and two doors onto the same
/// settings, one of which showed half of them, is how a learner comes to
/// believe the other half does not exist.
struct SettingsButton: View {
    var body: some View {
        SettingsLink {
            Image(systemName: "gearshape")
        }
        .help("Settings (⌘,)")
    }
}
