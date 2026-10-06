import SwiftUI
import WortfallCore

/// Optional reusable dashboard. The host can instead render ProgressSnapshot in its own UI.
public struct WortfallDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var cardColor: Color { colorScheme == .dark ? Color.white.opacity(0.055) : .white }
    @ObservedObject private var progress: WortfallProgress
    private let scopeNames: [String: String]
    public init(progress: WortfallProgress, scopeNames: [String: String] = [:]) { self.progress = progress; self.scopeNames = scopeNames }
    private var words: [WordStatistics] {
        progress.snapshot.words.values.sorted {
            if $0.mistakes != $1.mistakes { return $0.mistakes > $1.mistakes }
            return $0.word.localizedStandardCompare($1.word) == .orderedAscending
        }
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Your progress").font(.system(size: 25, weight: .bold, design: .rounded))
            HStack(spacing: 12) {
                metric("Earned points", progress.snapshot.earnedPoints.formatted(), "star.fill")
                metric("Levels completed", progress.snapshot.totalCompletedLevels.formatted(), "flag.checkered")
                metric("Words practiced", words.count.formatted(), "text.book.closed.fill")
                let first = words.reduce(0) { $0 + $1.firstAttempts }
                let correct = words.reduce(0) { $0 + $1.firstTryCorrect }
                metric("First-try accuracy", first == 0 ? "—" : "\(Int(Double(correct) / Double(first) * 100))%", "target")
            }
            Text("Words to practice").font(.headline)
            Text("Most mistakes first. Retries count as attempts, but never improve first-try accuracy.")
                .font(.caption).foregroundStyle(.secondary)
            if words.isEmpty {
                Label("Take your first slide to start building your word history.", systemImage: "sparkles")
                    .padding(24).frame(maxWidth: .infinity, alignment: .leading).background(cardColor, in: RoundedRectangle(cornerRadius: 18))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(words) { word in
                        DisclosureGroup {
                            ForEach(StudyMode.directions) { mode in
                                if let stats = word.directions[mode.rawValue] {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(mode.title).font(.subheadline.bold())
                                        Text("\(stats.attempts) attempts · \(stats.mistakes) mistakes · \(stats.firstTryCorrect)/\(stats.firstAttempts) first-try correct · \(stats.meanResponseSeconds, specifier: "%.1f")s average")
                                            .font(.caption).foregroundStyle(.secondary)
                                        let confusions = stats.confusedAnswers.sorted { $0.value > $1.value }
                                        if !confusions.isEmpty {
                                            Text("Confused with: " + confusions.map { "\($0.key) (\($0.value))" }.joined(separator: ", "))
                                                .font(.caption).textSelection(.enabled)
                                        }
                                        if let date = stats.lastPracticed { Text("Last practiced: \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                                }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) { Text(word.word).bold(); Text(word.translation).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Text("\(word.mistakes) mistakes / \(word.attempts) attempts").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(16).background(cardColor, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            Text("Level history").font(.headline)
            if progress.snapshot.levels.isEmpty { Text("Completed and failed runs will appear here.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(progress.snapshot.levels.values.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }) { level in
                HStack {
                    Image(systemName: level.completions > 0 ? "checkmark.circle.fill" : "arrow.clockwise.circle").foregroundStyle(Color.teal)
                    VStack(alignment: .leading) {
                        Text("Level \(level.level) · \(level.mode.title)").font(.subheadline.bold())
                        Text("\(scopeNames[level.scopeID] ?? "Custom collection") · \(level.runs) runs · \(level.completions) wins").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Best \(level.bestScore)").monospacedDigit().font(.subheadline.bold())
                }.padding(14).background(cardColor, in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Earned points include correct answers from retries and unfinished runs. Level bests belong to finished runs; each collection and study mode has its own unlocks.")
                .font(.caption).foregroundStyle(.secondary)
        }.foregroundStyle(colorScheme == .dark ? Color(rgb: 0xEFF1FC) : Color.ink)
    }
    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color(rgb: 0x9475BD))
            Text(value).font(.system(size: 27, weight: .bold, design: .rounded)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(cardColor, in: RoundedRectangle(cornerRadius: 18))
    }
}
