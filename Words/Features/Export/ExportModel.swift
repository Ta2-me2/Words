import Foundation
import Observation

/// The Export screen's state: what is ticked, what that comes to, and how the
/// writing went.
///
/// The plan is worked out again whenever a tick changes, which means reading
/// the size of every file the selection carries. Those sizes are asked of the
/// disk once each and kept, because a library with four hundred photographs
/// would otherwise stat four hundred files on every click.
@Observable
final class ExportModel {

    enum State: Equatable {
        case choosing
        case writing
        /// Written, with however many files turned out to be missing.
        case written(name: String, words: Int, missing: Int)
        case failed(String)
    }

    var selection = ExportSelection()
    private(set) var state: State = .choosing

    @ObservationIgnored private var sizes: [String: Int64] = [:]

    // MARK: - What the selection comes to

    func plan(for library: Library, mediaURL: (String) -> URL) -> ExportPlan {
        ExportPlan.make(from: library, selection: selection) { file in
            size(of: file, at: mediaURL(file))
        }
    }

    private func size(of file: String, at url: URL) -> Int64 {
        if let known = sizes[file] { return known }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        let bytes = Int64(values?.fileSize ?? 0)
        sizes[file] = bytes
        return bytes
    }

    // MARK: - The tree

    /// Everything that can be ticked for one language: its decks in the order
    /// the sidebar shows them, and the words that are in no deck.
    static func nodes(for profileID: UUID, in library: Library) -> [ExportNode] {
        var nodes: [ExportNode] = []
        for deck in library.topLevelDecks(in: profileID) {
            nodes.append(.deck(deck.id))
            nodes.append(contentsOf: library.subdecks(of: deck.id).map { .deck($0.id) })
        }
        if library.entries(in: profileID).contains(where: { $0.deckID == nil }) {
            nodes.append(.unfiled(profileID))
        }
        return nodes
    }

    /// How a language's own tick should be drawn: none of it, some of it, all.
    enum Tick { case none, some, all }

    func tick(of nodes: [ExportNode]) -> Tick {
        guard !nodes.isEmpty else { return .none }
        let chosen = nodes.count { selection.contains($0) }
        if chosen == 0 { return .none }
        return chosen == nodes.count ? .all : .some
    }

    /// Ticking a deck ticks the decks inside it, which is what a learner means
    /// by ticking "Germany"; unticking it lets them go again.
    func set(_ node: ExportNode, to wanted: Bool, in library: Library) {
        selection.set(node, to: wanted)
        if case .deck(let id) = node {
            selection.set(library.subdecks(of: id).map { .deck($0.id) }, to: wanted)
        }
    }

    // MARK: - Writing

    func reset() {
        if case .choosing = state { return }
        state = .choosing
    }

    /// The name to offer in the save panel: the one thing that was ticked, or
    /// the language, or just the app's name.
    func suggestedName(for plan: ExportPlan, in library: Library) -> String {
        guard plan.profiles.count == 1, let profile = plan.profiles.first else { return "Words Library" }

        // One deck and nothing else is a deck being handed over, and it should
        // arrive under its own name. A deck plus the odd words that were in no
        // deck is the language, whatever it happens to contain.
        let tops = plan.decks.filter { $0.parentID == nil }
        let loose = plan.entries.contains { $0.deckID == nil }
        if tops.count == 1, !loose { return tops[0].displayName }
        return profile.name
    }

    @MainActor
    func write(_ plan: ExportPlan, to url: URL, using store: LibraryStore, appVersion: String) async {
        state = .writing
        do {
            let missing = try await store.writePackage(plan, to: url, appVersion: appVersion)
            state = .written(
                name: url.lastPathComponent,
                words: plan.wordCount,
                missing: missing.count
            )
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
