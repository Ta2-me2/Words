import SwiftUI

/// The shapes both import screens are made of.
///
/// Bringing in words somebody else made is the same errand whether they come
/// from Anki or from Words: choose the file, see what is inside it, say where
/// it goes, watch it arrive. Only the nouns differ — a deck or a package, a
/// note type or a language. Two screens that did the same thing in two shapes
/// would be two things to learn, so the shape is written once here and the
/// words are passed in.
///
/// What is not here is what is genuinely different: Anki's fields and the
/// guessing of them, and a package's languages and where each one lands.

/// Nothing chosen yet: what the screen is for, and the whole of it as a place
/// to drop a file.
struct ImportInvitation: View {
    let title: String
    let systemImage: String
    let description: String
    let buttonTitle: String
    /// The extension a dropped file must have for the screen to take it.
    let fileExtension: String
    let choose: () -> Void
    let open: (URL) -> Void

    @State private var isTargeted = false

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        } actions: {
            Button(buttonTitle, action: choose)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.selection, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .opacity(isTargeted ? 1 : 0)
                .padding(Metrics.gutter)
        }
        .animation(.easeOut(duration: 0.12), value: isTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == fileExtension }) else { return false }
            open(url)
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

/// Reading, or adding: work with nothing to decide while it happens.
struct ImportProgress: View {
    let title: String
    var progress: Double?

    var body: some View {
        VStack(spacing: 12) {
            if let progress {
                ProgressView(value: progress)
                    .frame(width: 260)
            } else {
                ProgressView()
            }
            Text(title)
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The file could not be opened, and what to try instead.
struct ImportFailure: View {
    let title: String
    let message: String
    var suggestion: String?
    let buttonTitle: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text([message, suggestion].compactMap { $0 }.joined(separator: "\n\n"))
        } actions: {
            Button(buttonTitle, action: retry)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// It is in: what arrived, where it went, and the two things worth doing next.
struct ImportSuccess: View {
    let title: String
    let description: String
    let showTitle: String
    let show: () -> Void
    let againTitle: String
    let again: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "checkmark.circle")
        } description: {
            Text(description)
        } actions: {
            Button(showTitle, action: show)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            Button(againTitle, action: again)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The band along the bottom: what would happen, and the button that does it.
struct ImportFooter: View {
    let summary: String
    let buttonTitle: String
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(summary)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(2)

            Spacer(minLength: 12)

            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(isDisabled)
        }
    }
}
