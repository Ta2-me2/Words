import Charts
import SwiftUI

/// The long view: how much has been learned, how the answers went, and what the
/// next fortnight looks like.
///
/// Everything here is counted from the review history, which has been kept
/// since the first day precisely so that this screen could be honest rather
/// than encouraging.
struct StatisticsView: View {
    let profile: LanguageProfile

    @Environment(LibraryStore.self) private var store
    @Environment(AppClock.self) private var clock

    /// What the pointer is over in each chart. A bar is a shape, and a shape
    /// cannot be read.
    @State private var reviewsNote: HoverPoint?
    @State private var forecastNote: HoverPoint?
    @State private var answersNote: HoverPoint?

    var body: some View {
        Group {
            if summary.words == 0 {
                LibraryEmptyState(
                    title: "Nothing to Count Yet",
                    message: "Add words and review them. Every answer is kept, and this screen is built from them.",
                    symbol: "chart.bar"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                        vocabulary
                        reviewsPerDay
                        forecast
                        answers
                    }
                    .frame(maxWidth: Metrics.pageWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .pageInsets()
                }
            }
        }
        .navigationTitle(AppSection.statistics.title)
        .navigationSubtitle(profile.languagePair)
    }

    private var summary: ProfileSummary {
        Insights.summary(
            entries: store.library.entries,
            reviews: store.library.reviews,
            profileID: profile.id,
            asOf: clock.now
        )
    }

    // MARK: - Where the vocabulary stands

    private var vocabulary: some View {
        let summary = summary

        return VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader("Vocabulary")

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 30) {
                    StatTile(value: summary.words, label: "Words")
                    StatTile(value: summary.known, label: "In review")
                    StatTile(value: summary.mature, label: "Known well")
                    StatTile(value: summary.learning, label: "Learning")
                    StatTile(value: summary.newWords, label: "Not started")
                    Spacer(minLength: 0)
                }

                StageBar(summary: summary)
            }
            .cardSurface()

            HStack(alignment: .top, spacing: 30) {
                StatTile(value: summary.reviews, label: "Answers given")
                StatTile(value: summary.reviewsToday, label: "Today")
                LabelledValue(
                    value: String(format: "%.1f", summary.averagePerDay),
                    label: "A day, last month"
                )
                LabelledValue(
                    value: summary.accuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                    label: "Remembered"
                )
                Spacer(minLength: 0)
            }
            .cardSurface()
        }
    }

    // MARK: - Reviews per day

    private var reviewsPerDay: some View {
        let days = Insights.activity(
            reviews: store.library.reviews,
            profileID: profile.id,
            days: 30,
            asOf: clock.now
        )

        return VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader(title: "Reviews") {
                Text("Last 30 days")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }

            Chart(days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Reviews", day.count)
                )
                .foregroundStyle(Palette.selection)
                .cornerRadius(2)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .chartHover($reviewsNote) { proxy, point in
                guard let date: Date = proxy.value(atX: point.x),
                      let day = days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }),
                      day.count > 0
                else { return nil }
                return "\(day.count) \(day.count == 1 ? "review" : "reviews") · \(day.date.formatted(.dateTime.day().month(.abbreviated)))"
            }
            .frame(height: 160)
            .cardSurface()
        }
    }

    // MARK: - What is coming

    private var forecast: some View {
        let days = Insights.forecast(
            entries: store.library.entries,
            profileID: profile.id,
            days: 14,
            asOf: clock.now
        )

        return VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader(title: "Coming Up") {
                Text("Next 14 days")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }

            Chart(days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Cards", day.count)
                )
                .foregroundStyle(Palette.selection.opacity(0.7))
                .cornerRadius(2)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .chartHover($forecastNote) { proxy, point in
                guard let date: Date = proxy.value(atX: point.x),
                      let day = days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }),
                      day.count > 0
                else { return nil }
                return "\(day.count) \(day.count == 1 ? "card" : "cards") · \(day.date.formatted(.dateTime.day().month(.abbreviated)))"
            }
            .frame(height: 160)
            .cardSurface()
        }
    }

    // MARK: - How the answers went

    private var answers: some View {
        let grades = Insights.grades(reviews: store.library.reviews, profileID: profile.id)
        let total = grades.reduce(0) { $0 + $1.count }

        return VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader("Answers")

            if total == 0 {
                Text("No answers yet.")
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryText)
                    .cardSurface()
            } else {
                Chart(grades) { grade in
                    BarMark(
                        x: .value("Answers", grade.count),
                        y: .value("Answer", grade.grade.title)
                    )
                    .foregroundStyle(Palette.selection.opacity(grade.grade == .again ? 1 : 0.55))
                    .cornerRadius(3)
                    .annotation(position: .trailing) {
                        // Nothing is written where nothing happened: a row of
                        // noughts reads as a broken screen.
                        if grade.count > 0 {
                            Text("\(grade.count)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                    }
                }
                .chartHover($answersNote) { proxy, point in
                    guard let title: String = proxy.value(atY: point.y),
                          let grade = grades.first(where: { $0.grade.title == title }),
                          grade.count > 0
                    else { return nil }
                    let share = Int((Double(grade.count) / Double(total) * 100).rounded())
                    return "\(grade.count) \(grade.grade.title) · \(share)%"
                }
                .frame(height: 150)
                .cardSurface()
            }
        }
    }
}

/// The vocabulary as one bar: not started, learning, in review, known well.
///
/// A single line rather than four numbers repeated as a chart — the point is
/// the proportion, and a bar says it in one glance.
struct StageBar: View {
    let summary: ProfileSummary

    @State private var note: HoverPoint?

    private static let space = "stage-bar"

    var body: some View {
        let parts: [(String, Int, Double)] = [
            ("Known well", summary.mature, 1),
            ("In review", max(0, summary.known - summary.mature), 0.66),
            ("Learning", summary.learning, 0.4),
            ("Not started", summary.newWords, 0.16)
        ]
        let total = max(1, parts.reduce(0) { $0 + $1.1 })

        return GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(parts, id: \.0) { part in
                    if part.1 > 0 {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Palette.selection.opacity(part.2))
                            .frame(width: max(3, geometry.size.width * Double(part.1) / Double(total) - 2))
                            .onContinuousHover(coordinateSpace: .named(Self.space)) { phase in
                                show(phase, count: part.1, stage: part.0, of: total)
                            }
                    }
                }
            }
        }
        .frame(height: 8)
        .coordinateSpace(.named(Self.space))
        .hoverNote(note)
    }

    private func show(_ phase: HoverPhase, count: Int, stage: String, of total: Int) {
        guard case .active(let point) = phase else {
            note = nil
            return
        }
        let share = Int((Double(count) / Double(total) * 100).rounded())
        let words = count == 1 ? "word" : "words"
        note = HoverPoint("\(count) \(words) · \(stage.lowercased()) · \(share)%", at: CGPoint(x: point.x, y: 0))
    }
}

/// A number that is not a count — an average, a percentage — beside its label.
struct LabelledValue: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
        }
    }
}


private extension View {

    /// Answers the pointer with whatever the chart has under it.
    ///
    /// The note is placed at the pointer's own x and just inside the top of the
    /// plot, so it never covers the bar it is describing and never leaves the
    /// card it belongs to.
    func chartHover(_ note: Binding<HoverPoint?>, _ describe: @escaping (ChartProxy, CGPoint) -> String?) -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        guard case .active(let point) = phase,
                              let plot = proxy.plotFrame.map({ geometry[$0] }),
                              plot.contains(point),
                              let text = describe(proxy, CGPoint(x: point.x - plot.minX, y: point.y - plot.minY))
                        else {
                            note.wrappedValue = nil
                            return
                        }
                        note.wrappedValue = HoverPoint(text, at: CGPoint(x: point.x, y: plot.minY + 4))
                    }
            }
        }
        .hoverNote(note.wrappedValue, side: .below)
    }
}
