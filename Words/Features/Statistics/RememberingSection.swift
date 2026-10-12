import SwiftUI

/// Whether the schedule is telling the truth.
///
/// The app aims for a share of words to still be there when they come round —
/// nine in ten unless the learner says otherwise — and every other screen is
/// built on the assumption that it manages it. This is the one that checks.
/// Anki shows the same figure and calls it true retention; it is here under
/// the name of the thing it measures.
///
/// Three questions, in the order worth asking them: how is it going, does it
/// hold as the waits get longer, and has it always been like this.
struct RememberingSection: View {
    let profile: LanguageProfile

    @Environment(LibraryStore.self) private var store
    @Environment(AppClock.self) private var clock

    private var target: Double { profile.desiredRetention }

    var body: some View {
        let periods = TrueRetention.periods(
            reviews: store.library.reviews,
            profileID: profile.id,
            asOf: clock.now
        )

        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader(title: "Remembering") {
                Text("Scheduled reviews only")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }

            if let headline = TrueRetention.headline(periods), let share = headline.all.share {
                summary(headline, share: share)
                waits
                overTime(periods)
                declaredKnown
            } else {
                Text("No word has come round yet. This fills in as the words you have learned fall due — a learning step is not a memory being tested, so none of them is counted here.")
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
            }
        }
    }

    // MARK: - How it is going

    private func summary(_ headline: RetentionPeriod, share: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 30) {
                LabelledValue(
                    value: Self.percent(share),
                    label: "Remembered, \(headline.span.title.lowercased())"
                )
                LabelledValue(value: Self.percent(target), label: "Aimed for")
                StatTile(value: headline.all.total, label: "Reviews counted")
                Spacer(minLength: 0)
            }

            Text(verdict(share: share, total: headline.all.total))
                .font(.callout)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// What the number means, said plainly, and what to do about it.
    ///
    /// The gap has to be worth mentioning before anything is said about it:
    /// the figure wobbles by several points on a few dozen answers, and an app
    /// that cries wolf at every wobble teaches the learner to ignore it.
    private func verdict(share: Double, total: Int) -> String {
        guard total >= TrueRetention.enoughToJudge else {
            return "Only \(total) \(total == 1 ? "review has" : "reviews have") come round so far — the figure settles as more words fall due."
        }
        if share < target - 0.07 {
            return "Below what the schedule aims for: words are coming back round before you can recall them. Asking for a higher share in this language's settings shortens every interval."
        }
        if share > target + 0.07 {
            return "Above what the schedule aims for — you are remembering more than it plans for. Asking for a lower share would stretch the intervals and save you reviews."
        }
        return "About what the schedule aims for, which is what it is meant to do."
    }

    // MARK: - By how long the word waited

    private var waits: some View {
        let bands = TrueRetention.bands(reviews: store.library.reviews, profileID: profile.id)

        return VStack(alignment: .leading, spacing: 6) {
            Text("By how long the word waited")
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)

            GroupedRows {
                ForEach(Array(bands.enumerated()), id: \.element.id) { index, band in
                    GroupedRow(showsDivider: index < bands.count - 1) {
                        HStack(spacing: 12) {
                            Text(band.wait.title)
                                .frame(width: 150, alignment: .leading)
                                .foregroundStyle(band.count.total == 0 ? Palette.tertiaryText : Palette.primaryText)

                            RetentionBar(share: band.count.share, target: target)

                            Text(band.count.share.map(Self.percent) ?? "—")
                                .monospacedDigit()
                                .foregroundStyle(band.count.total == 0 ? Palette.tertiaryText : Palette.primaryText)
                                .frame(width: 44, alignment: .trailing)

                            Text(band.count.total == 0 ? "" : "\(band.count.total)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Palette.tertiaryText)
                                .frame(width: 40, alignment: .trailing)
                        }
                        // A band standing on a handful of answers is dimmed
                        // rather than hidden: it is there, it just cannot be
                        // read as a verdict yet.
                        .opacity(band.count.total > 0 && band.count.total < 10 ? 0.5 : 1)
                        .help(Self.detail(band.count))
                    }
                }
            }

            Text("The line across each bar is what the schedule aims for. A band that falls short of it is one where the intervals have outrun your memory.")
                .font(.caption)
                .foregroundStyle(Palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Has it always been like this

    private func overTime(_ periods: [RetentionPeriod]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Over time")
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)

            GroupedRows {
                GroupedRow {
                    HStack(spacing: 0) {
                        Text("")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        heading("Young")
                        heading("Known")
                        heading("All")
                    }
                }

                ForEach(Array(periods.enumerated()), id: \.element.id) { index, period in
                    GroupedRow(showsDivider: index < periods.count - 1) {
                        HStack(spacing: 0) {
                            Text(period.span.title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            cell(period.young)
                            cell(period.mature)
                            cell(period.all, strong: true)
                        }
                    }
                }
            }

            Text("Young is a word still waiting under three weeks; known is one waiting longer, which is where the line is usually drawn.")
                .font(.caption)
                .foregroundStyle(Palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(Palette.secondaryText)
            .frame(width: 86, alignment: .trailing)
    }

    private func cell(_ count: RecallCount, strong: Bool = false) -> some View {
        Text(count.share.map(Self.percent) ?? "—")
            .monospacedDigit()
            .fontWeight(strong ? .medium : .regular)
            .foregroundStyle(count.total == 0 ? Palette.tertiaryText : Palette.primaryText)
            .frame(width: 86, alignment: .trailing)
            .help(Self.detail(count))
    }

    // MARK: - The words that were already known

    @ViewBuilder
    private var declaredKnown: some View {
        let known = TrueRetention.declaredKnown(reviews: store.library.reviews, profileID: profile.id)

        if known.declared > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Words you already knew")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)

                HStack(alignment: .top, spacing: 30) {
                    StatTile(value: known.declared, label: "Set aside on sight")
                    StatTile(value: known.waiting, label: "Not back yet")
                    LabelledValue(
                        value: known.count.share.map(Self.percent) ?? "—",
                        label: "Kept, of those that returned"
                    )
                    Spacer(minLength: 0)
                }

                Text("Easy on a word never seen before means “I knew this already”, and the word is set aside for a month rather than days. This is the row that says whether that holds.")
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    // MARK: -

    private static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    private static func detail(_ count: RecallCount) -> String {
        guard count.total > 0 else { return "Nothing has come round in this band yet." }
        return "\(count.remembered) remembered, \(count.forgotten) forgotten, out of \(count.total)"
    }
}

/// One band's share, drawn against the share the schedule is aiming for.
///
/// A bar rather than a number alone because the question is never "what is the
/// figure" but "is it under the line", and a line is read in one glance.
private struct RetentionBar: View {
    let share: Double?
    let target: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.subtleFill)

                if let share {
                    Capsule()
                        .fill(share + 0.02 >= target ? Palette.complete : Palette.warning)
                        .frame(width: max(2, width * share))
                }

                Rectangle()
                    .fill(Palette.primaryText.opacity(0.55))
                    .frame(width: 1.5)
                    .offset(x: width * target)
            }
        }
        .frame(height: 8)
        .frame(maxWidth: .infinity)
    }
}
