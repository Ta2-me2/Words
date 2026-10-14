import SwiftUI

/// Where words are added: one at a time, a list at once, or a deck somebody
/// else made.
///
/// Its own screen rather than a sheet, because adding vocabulary is the thing a
/// learner does most often and it is where the app will grow first. The screen
/// itself is only the four sides and what they share — which deck everything
/// lands in — and each side is its own view.
struct AddWordsView: View {
    let profile: LanguageProfile

    @Environment(Router.self) private var router

    /// Which deck a word lands in, whichever way it is being added. Shared
    /// between the sides, because filling a shelf should not mean choosing it
    /// again for every way of filling it.
    @State private var deckID: UUID?

    var body: some View {
        // The mode is read inside the switch and the picker, never here. The
        // toolbar is made from this body, and a body that changed with the
        // mode handed AppKit a new toolbar on every click — which laid out
        // again the very control that had been clicked, halfway through its
        // animation.
        AddModeSwitch(
            oneWord: WordCardEditor(profile: profile, deckID: $deckID),
            list: ImportWordsView(profile: profile, deckID: $deckID),
            anki: AnkiImportView(profile: profile),
            package: ImportPackageView()
        )
        .navigationTitle(AppSection.add.title)
        .navigationSubtitle(profile.languagePair)
        .toolbar {
            ToolbarItem(id: "add.mode", placement: .principal) {
                AddModePicker()
            }
        }
        .task {
            deckID = router.lastDeckID
        }
        .onChange(of: router.lastDeckID) {
            // Arriving from a deck files into that deck: filling a shelf should
            // not mean choosing it again for every word.
            deckID = router.lastDeckID
        }
    }
}

/// The four sides of the screen, with the one the mode asks for in front.
///
/// The sides are kept, not rebuilt, once they have been made. Making one is a
/// whole form or a list editor laid out from nothing, a few frames of work on
/// the main thread; switching between kept ones is only a change of which is
/// visible. Those frames are the ones the mode control needs for its glass to
/// settle, and taking them showed as a lens that froze and then jumped. A kept
/// side also keeps what was typed in it, which is what someone who looks at the
/// other side for a moment expects to find when they come back.
private struct AddModeSwitch<OneWord: View, WordList: View, Anki: View, Package: View>: View {
    let oneWord: OneWord
    let list: WordList
    let anki: Anki
    let package: Package

    @Environment(Router.self) private var router

    /// The sides that exist. The one on show is made at once; the others a
    /// moment after the screen has arrived, when nothing is animating.
    @State private var made: Set<AddMode> = []

    var body: some View {
        ZStack {
            side(.single) { oneWord }
            side(.list) { list }
            side(.anki) { anki }
            side(.package) { package }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            made.formUnion(AddMode.allCases)
        }
        .onChange(of: router.addMode, initial: true) { made.insert(router.addMode) }
    }

    @ViewBuilder
    private func side(_ mode: AddMode, @ViewBuilder content: () -> some View) -> some View {
        let isShown = router.addMode == mode
        if isShown || made.contains(mode) {
            content()
                .opacity(isShown ? 1 : 0)
                // A hidden side must not take a drop, a click, the focus or
                // Return: each side has a default button of its own.
                .allowsHitTesting(isShown)
                .disabled(!isShown)
                .accessibilityHidden(!isShown)
        }
    }
}

/// The control that chooses between adding one word, a list, or a deck.
///
/// It shows the segment that was clicked at once and hands the choice on a
/// moment later, because of where a click on a segmented control is handled:
/// inside the control's own event loop, which is also where its glass
/// animation plays. Building a whole screen — a form, a list editor, an
/// import — inside that loop took the animation's frames for itself, which is
/// why a click looked flat and a drag, which only commits on release, did not.
private struct AddModePicker: View {
    @Environment(Router.self) private var router

    /// The segment clicked, until the screen has caught up with it.
    @State private var chosen: AddMode?

    var body: some View {
        Picker("Add", selection: Binding(
            get: { chosen ?? router.addMode },
            set: { choose($0) }
        )) {
            ForEach(AddMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 380)
        // The menu bar can change the mode too; the control follows it.
        .onChange(of: router.addMode) { chosen = nil }
    }

    private func choose(_ mode: AddMode) {
        guard mode != (chosen ?? router.addMode) else { return }
        chosen = mode
        // The default mode is the one the run loop returns to once the
        // control's tracking is over; nothing queued for it runs while the
        // click is still being handled.
        let router = router
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated { router.addMode = mode }
        }
    }
}
