import SwiftUI

/// Empty states are part of the design, not a placeholder.
///
/// A new library is empty by definition, so this is the first screen anyone
/// sees. It says what the screen is for and offers the one action that makes
/// sense there — never a welcome mat that has to be got past.
struct LibraryEmptyState: View {
    let title: String
    let message: String
    let symbol: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        // Fills whatever it is given. Without this the enclosing stack sizes to
        // its content and gets centred as a whole, taking the bar above it into
        // the middle of the window.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown while the library file is being opened.
struct LibraryLoadingState: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Opening library…")
                .font(.callout)
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown when the library could not be read. Deliberately blunt: this is the
/// one failure the owner must not miss.
struct LibraryFailureState: View {
    let message: String
    var retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Library Unavailable", systemImage: "exclamationmark.triangle")
                .foregroundStyle(Palette.critical)
        } description: {
            VStack(spacing: 8) {
                Text(message)
                Text(LibraryLocation.libraryURL.path(percentEncoded: false))
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.tertiaryText)
                    .textSelection(.enabled)
            }
        } actions: {
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
