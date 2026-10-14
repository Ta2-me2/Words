import AppKit
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
        case failed(String, String?)
    }

    private(set) var state: State = .empty

    /// Where each language in the package goes, by its identifier there.
    private(set) var destinations: [UUID: PackageImport.Destination] = [:]

    /// What opening it would do, worked out once and kept.
    ///
    /// Not a function the screen calls: a header, two columns and a footer
    /// would each ask, and `PackageImport.plan` walks every word and mints a
    /// fresh identifier for every one of them — so asking four times a pass
    /// would give four different answers and restart the preview on each.
    private(set) var plan = PackageImport.Plan()

    /// Which word the preview is showing, and whether it has been turned over.
    var position = 0 {
        didSet { if position != oldValue { isRevealed = false } }
    }

    var isRevealed = false

    /// The file, held open for as long as the package is: a package reads its
    /// photographs and recordings out of the archive when they are asked for,
    /// and the preview asks for them long after the file was chosen.
    @ObservationIgnored private var opened: URL?

    @ObservationIgnored private var pictures: [String: NSImage] = [:]

    deinit {
        opened?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Opening

    func open(_ url: URL, in library: Library) {
        // A file dropped or chosen may live outside anything this app owns,
        // and it stays open until the package is let go of.
        letGo()
        if url.startAccessingSecurityScopedResource() { opened = url }

        do {
            let package = try WordsPackage(reading: url)
            guard !package.manifest.entries.isEmpty || !package.manifest.decks.isEmpty else {
                state = .failed("There is nothing in this package.", nil)
                return
            }
            destinations = Dictionary(uniqueKeysWithValues: package.manifest.profiles.map {
                ($0.id, PackageImport.suggestedDestination(for: $0, in: library))
            })
            state = .read(package)
            replan(in: library)
        } catch let failure as WordsPackage.Failure {
            state = .failed(failure.errorDescription ?? "It could not be read.", failure.recoverySuggestion)
        } catch {
            state = .failed(error.localizedDescription, nil)
        }
    }

    func clear() {
        letGo()
        destinations = [:]
        plan = PackageImport.Plan()
        position = 0
        isRevealed = false
        pictures = [:]
        state = .empty
    }

    private func letGo() {
        opened?.stopAccessingSecurityScopedResource()
        opened = nil
    }

    func binding(for profileID: UUID, in library: Library) -> Binding<PackageImport.Destination> {
        Binding(
            get: { self.destinations[profileID] ?? .newLanguage },
            set: {
                self.destinations[profileID] = $0
                self.replan(in: library)
            }
        )
    }

    // MARK: - What it would do

    /// Works the plan out again: when the package is opened, when a language is
    /// sent somewhere else, and when the library itself has changed underneath.
    func replan(in library: Library) {
        guard case .read(let package) = state else {
            plan = PackageImport.Plan()
            return
        }
        plan = PackageImport.plan(
            package.manifest,
            into: library,
            destinations: destinations,
            mediaInPackage: package.mediaFiles
        )
        position = min(position, max(0, plan.entries.count - 1))
    }

    // MARK: - The card it would make

    /// The words the preview walks: the ones that would actually be added.
    var visible: [Entry] { plan.entries }

    var current: Entry? {
        visible.indices.contains(position) ? visible[position] : nil
    }

    func step(_ offset: Int) {
        guard !visible.isEmpty else { return }
        position = (position + offset + visible.count) % visible.count
    }

    /// The language a word will belong to once it is in — the one the package
    /// brought with it, or the one it is being sent to. A card shown under the
    /// wrong language would name the wrong column and read in the wrong voice.
    func profile(of entry: Entry, in library: Library) -> LanguageProfile? {
        plan.profiles.first { $0.id == entry.profileID } ?? library.profile(id: entry.profileID)
    }

    /// A word's photograph, out of the archive, read once.
    func picture(for entry: Entry) -> NSImage? {
        guard case .read(let package) = state, let file = entry.picture?.file else { return nil }
        if let cached = pictures[file] { return cached }
        guard let data = package.media(file), let image = NSImage(data: data) else { return nil }
        pictures[file] = image
        return image
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
