import AVKit
import SwiftUI

/// The tour: a short film of what the app does, with the companion beside it.
///
/// The film is a file in the bundle. Until there is one, this draws the frame
/// it will sit in and runs to its own end anyway, so the sequence either side
/// of it can be watched and tuned without waiting for the film to exist.
struct TourFilm: View {

    var onEnd: () -> Void

    @State private var player: AVPlayer?
    @State private var rehearsing = 0.0

    /// What the film is called when it arrives. Any of these, in this order.
    private static let names: [(String, String)] = [
        ("IntroTour", "mp4"), ("IntroTour", "mov"), ("IntroTour", "m4v"),
    ]

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
            } else {
                placeholder
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        }
        .shadow(color: .black.opacity(0.22), radius: 28, y: 14)
        .task { await run() }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [CompanionPalette.sky.opacity(0.45), CompanionPalette.blush.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 14) {
                Image(systemName: "play.circle")
                    .font(.system(size: 54, weight: .thin))
                    .foregroundStyle(.white.opacity(0.9))

                Text("The tour goes here")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.95))

                Text("Drop IntroTour.mp4 into the app's resources")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            // Something honest to watch while there is nothing to watch, so
            // the pacing of what comes after it can be judged.
            GeometryReader { proxy in
                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: proxy.size.width * rehearsing, height: 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private func run() async {
        if let url = Self.names.lazy.compactMap({ Bundle.main.url(forResource: $0.0, withExtension: $0.1) }).first {
            let item = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: item)
            for await _ in NotificationCenter.default.notifications(
                named: AVPlayerItem.didPlayToEndTimeNotification, object: item
            ) {
                onEnd()
                return
            }
            return
        }

        let seconds = 7.0
        let started = Date.now
        while rehearsing < 1 {
            try? await Task.sleep(for: .milliseconds(40))
            if Task.isCancelled { return }
            rehearsing = min(1, Date.now.timeIntervalSince(started) / seconds)
        }
        onEnd()
    }
}

/// The whole list, for when the typed word was not understood or the learner
/// would rather point than type.
struct LanguageChoice: View {

    var onPick: (String) -> Void
    var onInvent: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Which language?",
                subtitle: "The one you want to learn."
            )

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(LanguageCatalog.sortedCodes, id: \.self) { code in
                        Button { onPick(code) } label: {
                            HStack(spacing: 10) {
                                Text(LanguageCatalog.defaultFlag(for: code))
                                    .font(.title3)
                                Text(LanguageCatalog.name(for: code))
                                    .font(.body)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.quaternary.opacity(0.35))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Metrics.cardPadding)
            }

            SheetActions {
                Button("Mine isn’t here…", action: onInvent)
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.secondaryText)

                Spacer(minLength: 0)

                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(Metrics.cardPadding)
        }
        .frame(width: 520, height: 520)
    }
}

/// A language the app has never heard of, named by the person learning it.
struct InventLanguage: View {

    var onMake: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var flag = ""

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Your Language",
                subtitle: "Name it and give it a flag. Everything else works the same."
            )

            Form {
                Section {
                    HStack(spacing: 10) {
                        FlagField(flag: $flag)
                        TextField("Name", text: $name, prompt: Text("Language name"))
                            .labelsHidden()
                            .onSubmit(make)
                    }
                } footer: {
                    Text("Press ⌃⌘Space for the emoji picker.")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .formStyle(.grouped)

            SheetActions {
                Spacer(minLength: 0)

                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Start", action: make)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(Metrics.cardPadding)
        }
        .frame(width: 440, height: 290)
    }

    private func make() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onMake(trimmed, flag.isEmpty ? "🏳️" : flag)
    }
}
