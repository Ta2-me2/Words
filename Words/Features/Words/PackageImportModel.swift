import Foundation
import Observation
import SwiftUI

/// The From Words screen's state: the package that was opened, where each
/// language in it should land, and how the adding went.
@Observable
final class PackageImportModel {

    enum State {
        case empty
        case read(WordsPackage)
        case importing
        case added(words: Int, duplicates: Int, languages: [String])
        case failed(String)
    }

    private(set) var state: State = .empty

    /// Where each language in the package goes, by its identifier there.
    private(set) var destinations: [UUID: PackageImport.Destination] = [:]

    // MARK: - Opening

    func open(_ url: URL, in library: Library) {
        // A file dropped or chosen may live outside anything this app owns.
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }

        do {
            let package = try WordsPackage(reading: url)
            guard !package.manifest.entries.isEmpty || !package.manifest.decks.isEmpty else {
                state = .failed("There is nothing in this package.")
                return
            }
            destinations = Dictionary(uniqueKeysWithValues: package.manifest.profiles.map {
                ($0.id, PackageImport.suggestedDestination(for: $0, in: library))
            })
            state = .read(package)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func clear() {
        destinations = [:]
        state = .empty
    }

    func binding(for profileID: UUID) -> Binding<PackageImport.Destination> {
        Binding(
            get: { self.destinations[profileID] ?? .newLanguage },
            set: { self.destinations[profileID] = $0 }
        )
    }

    // MARK: - What it would do

    func plan(for library: Library) -> PackageImport.Plan {
        guard case .read(let package) = state else { return PackageImport.Plan() }
        return PackageImport.plan(
            package.manifest,
            into: library,
            destinations: destinations,
            mediaInPackage: package.mediaFiles
        )
    }

    // MARK: - Adding it

    @MainActor
    func add(_ plan: PackageImport.Plan, from package: WordsPackage, to store: LibraryStore) async {
        state = .importing
        // Read before the import, because a language made by it does not exist
        // in the library yet and one it went into is about to have more words.
        let landed = languages(of: plan, in: store.library)
        let words = await store.importPackage(package, applying: plan)
        state = .added(words: words, duplicates: plan.duplicates, languages: landed)
    }

    /// The languages the words ended up in, named, so that somebody who sent
    /// six words into a language they are not looking at is told which.
    private func languages(of plan: PackageImport.Plan, in library: Library) -> [String] {
        var names: [String] = []
        for id in Set(plan.entries.map(\.profileID)) {
            if let made = plan.profiles.first(where: { $0.id == id }) {
                names.append(made.name)
            } else if let mine = library.profile(id: id) {
                names.append(mine.name)
            }
        }
        return names.sorted()
    }
}
