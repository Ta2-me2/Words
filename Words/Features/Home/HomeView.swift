import SwiftUI

/// The screen the app opens on: what today asks for, the days in a row, how
/// the last months went, and which words are not sticking.
///
/// A handful of blocks and no more. A home screen that has to be read is not a home
/// screen; this one is meant to be understood in the two seconds before the
/// first card.
struct HomeView: View {
    let profile: LanguageProfile

    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(AppClock.self) private var clock

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                today
                streak
                activity
                if !difficult.isEmpty { difficultWords }
                if showsLanguages { languages }
            }
            .frame(maxWidth: Metrics.pageWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .pageInsets()
        }
        .navigationTitle(AppSection.home.title)
        .navigationSubtitle(profile.languagePair)
    }

    // MARK: - Today

    private var counts: StudyCounts {
        store.library.counts(for: profile.id, asOf: clock.now)
    }

    /// Whether today's sitting was stopped part-way. A day with work left in
    /// it must never be reported as a day that is done.
    private var isUnfinished: Bool {
        store.library.snapshot(profileID: profile.id, asOf: clock.now) != nil
    }

    private var today: some View {
        let counts = counts
        let tomorrow = Insights.tomorrow(
            profile: profile,
            entries: store.library.entries,
            asOf: clock.now
        )

        return VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader("Today")

            GroupedRows {
                GroupedRow {
                    HStack(alignment: .center, spacing: 26) {
                        StatTile(value: counts.due, label: "Reviews")
                        StatTile(value: counts.new, label: "New words")

                        Spacer(minLength: 12)

                        if counts.words > 0 {
                            // Beside the button it changes, because it is a
                            // way of studying chosen at the moment of starting.
                            DirectionPicker(profile: profile, store: store)
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .controlSize(.large)
                                .fixedSize()
                                .help("Which way round the cards are asked")
                        }

                        if counts.total > 0 || isUnfinished {
                            // A split button: the ordinary thing on the left,
                            // and every other way to study behind the arrow.
                            Menu {
                                StudyMenuContent(profile: profile, deck: nil, store: store, router: router, clock: clock)
                            } label: {
                                Text(isUnfinished ? "Continue Review" : "Start Review")
                            } primaryAction: {
                                router.startStudy()
                            }
                            .menuStyle(.button)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .fixedSize()
                            .keyboardShortcut(.defaultAction)
                        } else if counts.words > 0 {
                            HStack(spacing: 12) {
                                Label("Up to date", systemImage: "checkmark.circle")
                                    .font(.callout)
                                    .foregroundStyle(Palette.secondaryText)

                                // Finishing the day's cards should not mean
                                // there is nothing left to do in the app.
                                Menu("Practice") {
                                    StudyMenuContent(profile: profile, deck: nil, store: store, router: router, clock: clock)
                                }
                                .menuStyle(.button)
                                .controlSize(.large)
                                .fixedSize()
                            }
                        } else {
                            Button("Add Words") { router.newWord() }
                                .controlSize(.large)
                        }
                    }
                    .padding(.vertical, 2)
                }

                GroupedRow(showsDivider: false) {
                    HStack(spacing: 6) {
                        Text("Tomorrow")
                            .foregroundStyle(Palette.secondaryText)
                        Text(sentence(for: tomorrow))
                            .monospacedDigit()
                        Spacer(minLength: 0)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func sentence(for plan: DailyPlan) -> String {
        guard !plan.isEmpty else { return "nothing scheduled" }
        var parts: [String] = []
        if plan.reviews > 0 {
            parts.append("\(plan.reviews) \(plan.reviews == 1 ? "review" : "reviews")")
        }
        if plan.newWords > 0 {
            parts.append("\(plan.newWords) new \(plan.newWords == 1 ? "word" : "words")")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Streak

    private var streak: some View {
        let status = store.library.streak(asOf: clock.now)

        return VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader("Streak")

            GroupedRows {
                GroupedRow {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: status.frozenToday ? "snowflake" : "flame.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(flameStyle(status))
                            .frame(width: 34)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(status.length) \(status.length == 1 ? "day" : "days")")
                                .font(.title2.weight(.semibold))
                                .monospacedDigit()
                            Text(streakSentence(status))
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryText)
                        }

                        Spacer(minLength: 12)

                        StreakWeek(days: status.week)
                    }
                    .padding(.vertical, 2)
                }

                GroupedRow(showsDivider: false) {
                    HStack(spacing: 8) {
                        Label(freezeSentence(status), systemImage: "snowflake")
                            .foregroundStyle(Palette.secondaryText)
                            .monospacedDigit()

                        Spacer(minLength: 0)

                        if status.frozenToday {
                            Button("Unfreeze Today") { store.unfreezeStreak(at: clock.now) }
                        } else if status.length > 0, !status.studiedToday {
                            Button("Freeze Today") { store.freezeStreak(at: clock.now) }
                                .disabled(!status.canFreezeToday)
                                .help("Keep the streak through a day without studying. Two a week.")
                        }
                    }
                    .font(.callout)
                }
            }
        }
    }

    /// Lit once today counts, grey while it still could.
    private func flameStyle(_ status: StreakStatus) -> Color {
        if status.frozenToday { return Palette.frozen }
        return status.studiedToday ? Palette.streak : Palette.tertiaryText
    }

    private func streakSentence(_ status: StreakStatus) -> String {
        if status.studiedToday {
            return "Today counts. Tomorrow makes it \(status.length + 1)."
        }
        if status.frozenToday {
            return "Frozen today — the streak is kept."
        }
        if status.length > 0 {
            return "One card today makes it \(status.length + 1)."
        }
        return "One card today starts a streak."
    }

    private func freezeSentence(_ status: StreakStatus) -> String {
        switch status.freezesLeft {
        case 0: "No freezes left this week"
        case 1: "1 freeze left this week"
        default: "\(status.freezesLeft) freezes left this week"
        }
    }

    // MARK: - Activity

    /// A year, which is the span this shape is read in.
    private var activityDays: [ActivityDay] {
        Insights.activity(
            reviews: store.library.reviews,
            profileID: profile.id,
            days: 53 * 7,
            asOf: clock.now
        )
    }

    private var activity: some View {
        let days = activityDays
        let total = days.reduce(0) { $0 + $1.count }

        return VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader(title: "Activity") {
                Text(total > 0 ? "\(total) reviews" : "")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryText)
            }

            ActivityCalendar(days: days)
                .cardSurface()
        }
    }

    // MARK: - Difficult words

    private var difficult: [DifficultWord] {
        Insights.difficult(entries: store.library.entries, profileID: profile.id, limit: 5)
    }

    private var difficultWords: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader(title: "Hard to Remember") {
                Button("See All") { router.show(.library) }
                    .buttonStyle(.link)
                    .font(.caption)
            }

            GroupedRows {
                ForEach(Array(difficult.enumerated()), id: \.element.id) { index, word in
                    GroupedRow(showsDivider: index < difficult.count - 1) {
                        HoverRow {
                            router.editWord(word.entry.id)
                        } content: {
                            HStack(spacing: 12) {
                                Text(word.entry.term)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                                Text(word.entry.meaning)
                                    .foregroundStyle(Palette.secondaryText)
                                    .lineLimit(1)

                                Spacer(minLength: 8)

                                // Past a certain number of lapses the schedule
                                // is not the thing at fault. No algorithm
                                // rescues a card that asks the wrong question;
                                // the row already opens the editor.
                                if word.needsAttention {
                                    Text("needs a better card")
                                        .font(.caption)
                                        .foregroundStyle(Palette.secondaryText)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Palette.subtleFill, in: .capsule)
                                }

                                Text("forgotten \(word.lapses)×")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.secondaryText)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Across languages

    /// Only worth the room when there is more than one answer in it.
    private var showsLanguages: Bool {
        Insights.studiedLanguageCount(
            profiles: store.library.profiles,
            reviews: store.library.reviews
        ) >= 2
    }

    private var languages: some View {
        let totals = Insights.totals(
            profiles: store.library.profiles,
            entries: store.library.entries,
            reviews: store.library.reviews,
            extras: store.library.extras,
            asOf: clock.now
        )

        return VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader("All Languages")

            GroupedRows {
                ForEach(Array(totals.enumerated()), id: \.element.id) { index, total in
                    GroupedRow(showsDivider: index < totals.count - 1) {
                        HoverRow {
                            router.profileID = total.profile.id
                        } content: {
                            HStack(spacing: 10) {
                                Text(total.profile.flag)
                                Text(total.profile.displayName)
                                    .font(.body.weight(total.profile.id == profile.id ? .medium : .regular))
                                    .lineLimit(1)

                                Text("\(total.words) \(total.words == 1 ? "word" : "words") · \(total.known) known")
                                    .font(.callout)
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.secondaryText)
                                    .lineLimit(1)

                                Spacer(minLength: 8)

                                if total.due > 0 {
                                    Text("\(total.due) due")
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(Palette.secondaryText)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A row that can be clicked, and says so by lifting a little under the pointer.
///
/// Hover is a whisper: the row brightens by a fill nobody would notice on its
/// own, which is the difference between an interface that is alive and one that
/// is shouting.
struct HoverRow<Content: View>: View {
    var action: () -> Void
    @ViewBuilder var content: Content

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                .fill(Palette.selection.opacity(isHovering ? 0.06 : 0))
                .padding(.horizontal, -6)
                .padding(.vertical, -4)
        }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

/// The seven days of this week, as a row of rings.
struct StreakWeek: View {
    let days: [StreakDay]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days) { day in
                VStack(spacing: 3) {
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2)
                        .foregroundStyle(day.state == .today ? Palette.primaryText : Palette.tertiaryText)

                    mark(for: day.state)
                        .frame(width: 20, height: 20)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.date.formatted(.dateTime.weekday(.wide))), \(description(of: day.state))")
            }
        }
    }

    @ViewBuilder
    private func mark(for state: StreakDay.State) -> some View {
        switch state {
        case .studied:
            Circle()
                .fill(Palette.streak)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
        case .frozen:
            Circle()
                .fill(Palette.frozen)
                .overlay {
                    Image(systemName: "snowflake")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
        case .today:
            Circle()
                .strokeBorder(Palette.streak, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
        case .missed:
            Circle()
                .strokeBorder(Palette.separator, lineWidth: 1.5)
        case .ahead:
            Circle()
                .strokeBorder(Palette.separator.opacity(0.5), lineWidth: 1)
        }
    }

    private func description(of state: StreakDay.State) -> String {
        switch state {
        case .studied: "studied"
        case .frozen: "frozen"
        case .today: "today, not studied yet"
        case .missed: "missed"
        case .ahead: "still to come"
        }
    }
}
