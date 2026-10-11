import SwiftUI
import WordsCompanion

/// Dictation, played with this language's own words.
///
/// The screen before the game is the game's own home: what today asks for,
/// what it is played with, and how the last fortnight went. A learner who
/// opens it and does not want to play should still learn something from it.
struct DictationScreen: View {
    let profile: LanguageProfile
    let close: () -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var progress = DictationStore()
    @State private var session: DictationSession?
    @State private var sheet: Sheet?

    private let speaker = Speaker.shared

    private enum Sheet: String, Identifiable {
        case sentences, companion
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if let session {
                DictationPlayView(
                    profile: profile,
                    session: session,
                    hint: progress.progress.settings.hint,
                    speak: say,
                    answered: record,
                    finish: end
                )
            } else if let failure = progress.failure {
                ContentUnavailableView {
                    Label("Your Progress Couldn’t Be Read", systemImage: "exclamationmark.triangle")
                } description: {
                    // Left exactly as it is: progress that cannot be read is
                    // not progress to replace with an empty file.
                    Text(failure)
                } actions: {
                    Button("Back to Games", action: close)
                }
            } else {
                home
            }
        }
        .task(id: profile.id) { await progress.load(for: profile.id) }
        .onDisappear { Task { await progress.flush() } }
        .sheet(item: $sheet) { which in
            switch which {
            case .sentences:
                DictationSentencesView(profile: profile, store: progress)
            case .companion:
                DictationCompanionView(profile: profile, deckID: progress.progress.settings.deckID)
            }
        }
    }

    // MARK: - Before playing

    private var home: some View {
        let items = material
        let day = progress.progress.day(on: .now)
        let allowance = DictationMaterial.allowance(progress.progress.settings, done: day)
        let queue = DictationQueue(items: items, records: progress.progress.records, allowance: allowance)

        return ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                today(queue: queue, day: day, items: items)
                playedWith(items)
                howItGoes()
            }
            .frame(maxWidth: Metrics.pageWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .pageInsets()
        }
        .navigationTitle(GameKind.dictation.title)
        .navigationSubtitle(profile.languagePair)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Games", systemImage: "chevron.left", action: close)
                    .help("Back to the games")
            }
        }
    }

    @ViewBuilder
    private func today(queue: DictationQueue, day: DictationDay, items: [DictationItem]) -> some View {
        SectionCard(title: "Today") {
            if items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("There is nothing to hear yet.")
                        .foregroundStyle(Palette.secondaryText)
                    Text("Add words to this language, write sentences of your own, or let the companion make a sentence for each word you have.")
                        .font(.callout)
                        .foregroundStyle(Palette.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(alignment: .top, spacing: 28) {
                    figure("\(queue.dueCount)", "to go over")
                    figure("\(queue.newCount)", "new")
                    figure("\(day.exercises)", "done today")
                    if day.wordsWanted > 0 {
                        figure("\(Int((day.accuracy * 100).rounded()))%", "accurate")
                    }
                    Spacer(minLength: 8)
                }

                if queue.total == 0 {
                    Label("That is everything for today. Come back tomorrow.", systemImage: "checkmark.circle")
                        .foregroundStyle(Palette.complete)
                }

                HStack(spacing: 10) {
                    Button(queue.total == 0 ? "Practise Anyway" : "Start") {
                        start(items: items, allowance: queue.total == 0 ? progress.progress.settings.dailyNew : nil)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(items.isEmpty)

                    if queue.total == 0 {
                        Text("Nothing you do now changes a schedule.")
                            .font(.caption)
                            .foregroundStyle(Palette.tertiaryText)
                    }
                }
            }
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.medium)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Palette.secondaryText)
        }
    }

    @ViewBuilder
    private func playedWith(_ items: [DictationItem]) -> some View {
        @Bindable var progress = progress

        SectionCard(title: "Played with") {
            Form {
                ForEach(DictationSource.allCases, id: \.self) { source in
                    Toggle(isOn: binding(for: source)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title(of: source))
                            Text("\(items.count { $0.source == source }) ready")
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }
                }

                Picker("Deck", selection: deckBinding) {
                    Text("The whole language").tag(UUID?.none)
                    Divider()
                    ForEach(store.library.decks(in: profile.id)) { deck in
                        Text(store.library.path(of: deck)).tag(Optional(deck.id))
                    }
                }

                Picker("Give away", selection: hintBinding) {
                    ForEach(DictationHint.allCases) { hint in
                        Text(hint.title).tag(hint)
                    }
                }

                Stepper(value: dailyBinding, in: 1 ... 100, step: 5) {
                    LabeledContent("New a day", value: "\(progress.progress.settings.dailyNew)")
                }
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)
            .scrollDisabled(true)

            HStack(spacing: 10) {
                Button("Write Sentences…") { sheet = .sentences }
                Button("Make Sentences with \(companionName)…") { sheet = .companion }
                    .disabled(!companionReady)
                    .help(companionReady
                          ? "The companion writes an example for each word that has none."
                          : "Choose a companion in Settings first.")
            }
        }
    }

    @ViewBuilder
    private func howItGoes() -> some View {
        let whole = progress.progress

        SectionCard(title: "How it goes") {
            HStack(alignment: .top, spacing: 28) {
                figure("\(whole.started)", "phrases started")
                figure("\(whole.known)", "known well")
                figure(whole.lifetimeAccuracy > 0 ? "\(Int((whole.lifetimeAccuracy * 100).rounded()))%" : "—", "accurate")
                figure("\(whole.streak(on: .now))", "day streak")
                Spacer(minLength: 8)
            }

            let recent = whole.recentDays(before: .now, count: 14)
            if recent.isEmpty {
                Text("Nothing played yet.")
                    .font(.callout)
                    .foregroundStyle(Palette.tertiaryText)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(recent.prefix(7), id: \.day) { day in
                        HStack {
                            Text(day.day).font(.caption.monospaced()).foregroundStyle(Palette.secondaryText)
                            Spacer()
                            Text("\(day.work.exercises) phrases")
                                .font(.caption).monospacedDigit()
                            Text("\(Int((day.work.accuracy * 100).rounded()))%")
                                .font(.caption).monospacedDigit()
                                .foregroundStyle(Palette.secondaryText)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: - What it is played with

    private var material: [DictationItem] {
        DictationMaterial.items(
            for: profile,
            in: store.library,
            settings: progress.progress.settings,
            sentences: progress.progress.sentences
        )
    }

    private func title(of source: DictationSource) -> String {
        switch source {
        case .word: "Words of this language, one at a time"
        case .example: "The example kept with a word"
        case .written: "Sentences you wrote here"
        }
    }

    private func binding(for source: DictationSource) -> Binding<Bool> {
        Binding(
            get: { progress.progress.settings.sources.contains(source) },
            set: { wanted in
                progress.update { settings in
                    var sources = settings.sources
                    if wanted { sources.insert(source) } else { sources.remove(source) }
                    // Never all off: a game with nothing in it is a game that
                    // can only say so.
                    settings.sources = sources.isEmpty ? [source] : sources
                }
            }
        )
    }

    private var deckBinding: Binding<UUID?> {
        Binding(
            get: { progress.progress.settings.deckID },
            set: { id in progress.update { $0.deckID = id } }
        )
    }

    private var hintBinding: Binding<DictationHint> {
        Binding(
            get: { progress.progress.settings.hint },
            set: { hint in progress.update { $0.hint = hint } }
        )
    }

    private var dailyBinding: Binding<Int> {
        Binding(
            get: { progress.progress.settings.dailyNew },
            set: { count in progress.update { $0.dailyNew = count } }
        )
    }

    // MARK: - The companion

    private var companion: CompanionModel? { CompanionModel.named(settings.companionID) }

    private var companionName: String { companion?.name ?? "Apple Intelligence" }

    private var companionReady: Bool { CardAssistant.readiness(for: companion) == .ready }

    // MARK: - Playing

    private func start(items: [DictationItem], allowance: Int?) {
        let day = progress.progress.day(on: .now)
        let owed = allowance ?? DictationMaterial.allowance(progress.progress.settings, done: day)
        session = DictationSession(queue: DictationQueue(
            items: items,
            records: progress.progress.records,
            allowance: owed
        ))
    }

    private func say(_ item: DictationItem) {
        // A word with a recording of its own is played rather than read: the
        // learner's own voice, or whoever recorded the deck, is better
        // listening practice than a synthesiser.
        if let entryID = item.entryID, let entry = store.library.entry(id: entryID) {
            switch item.source {
            case .word where entry.audio != nil:
                speaker.speak(entry, in: profile, store: store)
                return
            case .example where entry.exampleAudio != nil:
                speaker.speakExample(entry, in: profile, store: store)
                return
            default:
                break
            }
        }
        speaker.speak(item.text, in: profile)
    }

    private func record(
        _ item: DictationItem,
        result: DictationResult,
        grade: ReviewGrade,
        seconds: Double,
        counted: Bool
    ) {
        progress.record(
            item,
            result: result,
            grade: grade,
            seconds: seconds,
            countsTowardsTheDay: counted,
            retention: profile.desiredRetention
        )
    }

    private func end() {
        session = nil
        speaker.stop()
        Task { await progress.flush() }
    }
}

/// A titled block on the game's home screen.
private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
