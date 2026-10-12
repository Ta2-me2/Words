import SwiftUI
import WordsCompanion

/// Dictation, played with this language's own words.
///
/// The screen before the game is laid out like Home: what today asks for at
/// the top, then what the game is played with, then how it has been going. A
/// learner who opens it and does not want to play should still learn something
/// from it.
struct DictationScreen: View {
    let profile: LanguageProfile
    let close: () -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(AppClock.self) private var clock

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
            if let failure = progress.failure {
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
        // The sitting is a sheet, like a review: a task with a beginning and
        // an end, over the screen that counts what it did.
        .sheet(item: $session) { session in
            DictationPlayView(
                profile: profile,
                session: session,
                hint: progress.progress.settings.hint,
                canSlowDown: Speaker.voice(for: profile) != nil,
                speak: say,
                answered: record,
                finish: { self.session = nil; speaker.stop(); Task { await progress.flush() } }
            )
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .sentences:
                DictationSentencesView(profile: profile, store: progress)
            case .companion:
                MakeSentencesView(profile: profile, deckID: progress.progress.settings.deckID)
            }
        }
    }

    // MARK: - The screen

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                today
                playedWith
                howItGoes
                activity
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

    // MARK: - Today

    private var items: [DictationItem] {
        DictationMaterial.items(
            for: profile,
            in: store.library,
            settings: progress.progress.settings,
            sentences: progress.progress.sentences
        )
    }

    private var today: some View {
        let items = items
        let day = progress.progress.day(on: clock.now)
        let allowance = DictationMaterial.allowance(progress.progress.settings, done: day)
        let queue = DictationQueue(items: items, records: progress.progress.records, allowance: allowance, now: clock.now)
        let next = DictationMaterial.tomorrow(
            items: items,
            records: progress.progress.records,
            settings: progress.progress.settings,
            now: clock.now
        )

        return VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader("Today")

            GroupedRows {
                GroupedRow {
                    HStack(alignment: .center, spacing: 26) {
                        StatTile(value: queue.dueCount, label: "To go over")
                        StatTile(value: queue.newCount, label: "New")
                        StatTile(value: day.exercises, label: "Done today")

                        Spacer(minLength: 12)

                        if items.isEmpty {
                            Button("Add Words") { sheet = .sentences }
                                .controlSize(.large)
                        } else if queue.total > 0 {
                            Button("Start") { start(items: items, allowance: allowance) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .fixedSize()
                                .keyboardShortcut(.defaultAction)
                        } else {
                            HStack(spacing: 12) {
                                Label("Up to date", systemImage: "checkmark.circle")
                                    .font(.callout)
                                    .foregroundStyle(Palette.secondaryText)

                                // Finishing the day's phrases should not mean
                                // there is nothing left to do here.
                                Button("Practise") {
                                    start(items: items, allowance: progress.progress.settings.dailyNew)
                                }
                                .controlSize(.large)
                                .fixedSize()
                                .help("Nothing you do now changes a schedule.")
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                GroupedRow(showsDivider: false) {
                    HStack(spacing: 6) {
                        Text("Tomorrow")
                            .foregroundStyle(Palette.secondaryText)
                        Text(sentence(for: next))
                            .monospacedDigit()
                        Spacer(minLength: 0)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func sentence(for plan: (reviews: Int, new: Int)) -> String {
        var parts: [String] = []
        if plan.reviews > 0 {
            parts.append("\(plan.reviews) to go over")
        }
        if plan.new > 0 {
            parts.append("\(plan.new) new")
        }
        return parts.isEmpty ? "nothing waiting" : parts.joined(separator: " · ")
    }

    // MARK: - What it plays

    private var playedWith: some View {
        let items = items

        return VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader(title: "What It Plays") {
                Text("\(items.count) \(items.count == 1 ? "phrase" : "phrases")")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryText)
            }

            GroupedRows {
                ForEach(DictationSource.allCases, id: \.self) { source in
                    GroupedRow {
                        Toggle(isOn: binding(for: source)) {
                            HStack(spacing: 8) {
                                Text(title(of: source))
                                Spacer(minLength: 12)
                                Text("\(items.count { $0.source == source })")
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.secondaryText)
                            }
                        }
                    }
                }

                GroupedRow {
                    setting("Deck", help: "Which words the first two come from. Sentences you wrote here are always played.") {
                        Picker("", selection: deckBinding) {
                            Text("The whole language").tag(UUID?.none)
                            Divider()
                            ForEach(store.library.decks(in: profile.id)) { deck in
                                Text(store.library.path(of: deck)).tag(Optional(deck.id))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                GroupedRow {
                    setting("Give away", help: progress.progress.settings.hint.detail) {
                        Picker("", selection: hintBinding) {
                            ForEach(DictationHint.allCases) { hint in
                                Text(hint.title).tag(hint)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                GroupedRow(showsDivider: false) {
                    setting("New a day", help: "How many phrases never heard before to start in a day.") {
                        CountField(value: dailyBinding, in: 1 ... 200)
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Write Sentences…") { sheet = .sentences }
                Button("Make Sentences with \(companionName)…") { sheet = .companion }
                    .disabled(!companionReady)
                    .help(companionReady
                          ? "The companion writes an example for each word that has none."
                          : "Choose a companion in Settings first.")
                Spacer(minLength: 0)
            }
        }
    }

    /// A row of the settings block: what it is on the left, the control on the
    /// right, like every other grouped row in the app.
    private func setting(_ title: String, help: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            control()
        }
        .help(help)
    }

    // MARK: - How it goes

    private var howItGoes: some View {
        let whole = progress.progress
        let day = whole.day(on: clock.now)

        return VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader("How It Goes")

            GroupedRows {
                GroupedRow {
                    HStack(alignment: .center, spacing: 26) {
                        StatTile(value: whole.started, label: "Started")
                        StatTile(value: whole.known, label: "Known well")
                        StatTile(value: whole.streak(on: clock.now), label: "Day streak")
                        Spacer(minLength: 12)
                    }
                    .padding(.vertical, 2)
                }

                GroupedRow(showsDivider: false) {
                    HStack(alignment: .center, spacing: 26) {
                        LabelledValue(
                            value: whole.lifetimeAccuracy > 0 ? percent(whole.lifetimeAccuracy) : "—",
                            label: "Accurate"
                        )
                        LabelledValue(value: day.wordsWanted > 0 ? percent(day.accuracy) : "—", label: "Today")
                        LabelledValue(value: minutes(day.seconds), label: "Time today")
                        Spacer(minLength: 12)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    private func minutes(_ seconds: Double) -> String {
        guard seconds >= 60 else { return seconds > 0 ? "under a minute" : "—" }
        let whole = Int((seconds / 60).rounded())
        return "\(whole) min"
    }

    // MARK: - Activity

    private var activity: some View {
        let days = progress.progress.activity(days: 53 * 7, asOf: clock.now)
        let total = days.reduce(0) { $0 + $1.count }

        return VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader(title: "Activity") {
                Text(total > 0 ? "\(total) phrases" : "")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryText)
            }

            ActivityCalendar(days: days)
                .cardSurface()
        }
    }

    // MARK: - The settings behind it

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

    private func start(items: [DictationItem], allowance: Int) {
        session = DictationSession(queue: DictationQueue(
            items: items,
            records: progress.progress.records,
            allowance: allowance,
            now: clock.now
        ))
    }

    private func say(_ item: DictationItem, slowly: Bool) {
        // A word with a recording of its own is played rather than read: the
        // learner's own voice, or whoever recorded the deck, is better
        // listening practice than a synthesiser. Slowed down, there is no
        // recording to slow — the voice reads it instead.
        if !slowly, let entryID = item.entryID, let entry = store.library.entry(id: entryID) {
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

        guard slowly else {
            speaker.speak(item.text, in: profile)
            return
        }
        var slower = profile
        slower.speechRate = max(0.25, profile.speechRate * 0.6)
        speaker.speak(item.text, in: slower)
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
            retention: profile.desiredRetention,
            at: clock.now
        )
    }
}

extension DictationSession: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
