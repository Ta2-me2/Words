import AppKit
import SwiftUI

@main
struct WordsApp: App {

    @State private var store = LibraryStore()
    @State private var router = Router()
    @State private var settings = AppSettings()
    @State private var clock = AppClock()
    @State private var installer = CompanionInstaller()

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .environment(settings)
                .environment(clock)
                .environment(installer)
                .frame(
                    minWidth: Metrics.windowMinWidth,
                    minHeight: Metrics.windowMinHeight
                )
                .task {
                    settings.apply()
                    // Quitting has to write the library, and only the delegate
                    // is told that the app is about to go.
                    delegate.store = store
                }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1040, height: 680)
        .commands {
            WordsCommands(store: store, router: router)
        }

        Settings {
            SettingsView()
                .environment(settings)
                .environment(installer)
        }
    }
}

/// The one thing AppKit still has to be asked: hold the quit until the library
/// is on disk. Everything else the app does goes through SwiftUI.
final class AppDelegate: NSObject, NSApplicationDelegate {

    var store: LibraryStore?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        Task {
            await store.saveNow()
            // A game's last answers are queued, not written; the game asks to
            // be flushed before the process goes.
            await WortfallHost.shared.flushAll()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// One window, one library: closing it means the work is done.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// The menu bar.
///
/// Almost everything a learner sets belongs to a language and is set with it.
/// What the Settings window behind ⌘, holds is the app's own: how it looks, and
/// which model answers questions about a card.
struct WordsCommands: Commands {
    let store: LibraryStore
    let router: Router

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Word") { router.newWord() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(router.profileID == nil)

            Button("New Deck…") { router.newDeck() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(router.profileID == nil)

            Button("Import Words…") {
                router.newWord()
                router.importWords()
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(router.profileID == nil)

            Button("Add Recordings…") { router.matchAudio() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(router.profileID == nil)

            Button("New Language…") { router.newLanguage() }
                .keyboardShortcut("n", modifiers: [.command, .shift])

            // The switcher is a small control in a corner; everything it can do
            // has to be reachable from the menu bar as well.
            Button("Edit Language…") {
                if let id = router.profileID { router.editLanguage(id) }
            }
            .disabled(router.profileID == nil)
        }

        // The sections, in the order they are in the sidebar, on the numbers
        // every Mac application puts them on.
        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { router.show(section) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .disabled(router.profileID == nil)
            }
        }

        CommandMenu("Study") {
            Button("Start Review") { router.startStudy() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(router.profileID == nil)

            // Beside Start Review rather than with the practice below: it is
            // real study, and it moves real schedules.
            Button("I Want More…") { router.studyMore() }
                .disabled(router.profileID.map { !store.library.canStudyMore(for: $0, asOf: .now) } ?? true)

            Divider()

            // Practice changes nothing, which is why it is worth having its own
            // shortcuts: a learner who has finished today should be able to
            // keep going without wondering what it will cost them tomorrow.
            Button("Practice Today's Cards") { router.startStudy(mode: .practiceToday) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(router.profileID == nil)

            Button("Endless Practice") { router.startStudy(mode: .endless(.everything)) }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(router.profileID == nil)

            Button("Endless Practice · Words I've Seen") { router.startStudy(mode: .endless(.seen)) }
                .disabled(router.profileID == nil)

            Divider()

            Button("Save Now") {
                Task { await store.saveNow() }
            }
            .keyboardShortcut("s", modifiers: .command)
        }
    }
}
