import SwiftUI

/// Making a deck, or changing one: its name and icon, where it sits, the decks
/// inside it, and how many new words a day it starts.
///
/// The top of the sheet is the sidebar as it is about to look. A tree is easy
/// to describe and hard to picture — "a subdeck of a deck at the top level" is
/// a sentence nobody reads twice — so the sheet shows the rows themselves, with
/// the one being made picked out, and they change as the name is typed, the
/// icon chosen, the deck moved or a subdeck added.
struct DeckEditor: View {

    enum Mode {
        /// A new deck, at the top of the language or inside the deck given.
        case add(profileID: UUID, parentID: UUID?)
        case edit(Deck)
    }

    let mode: Mode

    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var icon: DeckIcon
    @State private var parentID: UUID?
    @State private var followsAbove: Bool
    @State private var dailyNewLimit: Int

    /// Subdecks written in this sheet and not made yet. They are made with
    /// the deck, in one change.
    @State private var pending: [PendingSubdeck] = []
    @State private var draft = ""

    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case name
        case draft
        case pending(UUID)
    }

    private struct PendingSubdeck: Identifiable {
        let id = UUID()
        var name: String
        var icon: DeckIcon = .standard
    }

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add(_, let parentID):
            _name = State(initialValue: "")
            _icon = State(initialValue: .standard)
            _parentID = State(initialValue: parentID)
            _followsAbove = State(initialValue: true)
            _dailyNewLimit = State(initialValue: 20)
        case .edit(let deck):
            _name = State(initialValue: deck.name)
            _icon = State(initialValue: deck.displayIcon)
            _parentID = State(initialValue: deck.parentID)
            _followsAbove = State(initialValue: deck.dailyNewLimit == nil)
            _dailyNewLimit = State(initialValue: deck.dailyNewLimit ?? 20)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title, subtitle: subtitle)

            Form {
                Section("In the Sidebar") {
                    preview
                }

                Section {
                    HStack(spacing: 12) {
                        DeckIconPicker(icon: $icon, languageCode: profile?.learningCode ?? "")

                        TextField("Name", text: $name, prompt: Text(parentID == nil ? "Germany, Verbs, Kitchen…" : "A1, Chapter 3, Irregular…"))
                            .labelsHidden()
                            .font(.title3)
                            .focused($focus, equals: .name)
                    }
                    .padding(.vertical, 2)

                    Picker("Inside", selection: $parentID) {
                        Text("No Deck — Top Level").tag(UUID?.none)
                        if !parents.isEmpty {
                            Divider()
                            ForEach(parents) { deck in
                                Text(deck.displayName).tag(Optional(deck.id))
                            }
                        }
                    }
                    .disabled(hasSubdecks)
                } footer: {
                    Text(placementNote)
                }

                if parentID == nil {
                    subdecksSection
                }

                Section {
                    Toggle(followLabel, isOn: $followsAbove)

                    if !followsAbove {
                        LabeledContent("New words a day") {
                            CountField(value: $dailyNewLimit, in: 0...999)
                        }
                    }
                } footer: {
                    Text("A deck studied on its own gets its own allowance of new words, so working through one shelf does not use up another's day.")
                }
            }
            .formStyle(.grouped)

            Divider()

            SheetActions {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(isEditing ? "Save" : "Create Deck") { commit() }
                    // Return adds a subdeck while one is being typed, and only
                    // makes the deck from anywhere else — or "A1⏎" would make
                    // "Germany" before "A2" could be written.
                    .keyboardShortcut(returnMakesDeck ? .defaultAction : nil)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmed(name).isEmpty)
            }
        }
        .frame(width: 460, height: 600)
        .animation(.easeOut(duration: 0.15), value: parentID)
        .animation(.easeOut(duration: 0.15), value: pending.map(\.id))
        .task { focus = .name }
    }

    // MARK: - The sidebar, as it is about to look

    private var preview: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let parent = store.library.deck(id: parentID) {
                previewRow(parent.displayName, icon: parent.displayIcon, depth: 0, role: .existing)
                ForEach(Array(siblingsAround.enumerated()), id: \.offset) { _, item in
                    switch item {
                    case .this:
                        previewRow(shownName, icon: icon, depth: 1, role: .this)
                    case .sibling(let deck):
                        previewRow(deck.displayName, icon: deck.displayIcon, depth: 1, role: .existing)
                    case .more(let count):
                        previewMore(count, depth: 1)
                    }
                }
            } else {
                previewRow(shownName, icon: icon, depth: 0, role: .this)
                ForEach(existingSubdecks.prefix(4)) { deck in
                    previewRow(deck.displayName, icon: deck.displayIcon, depth: 1, role: .existing)
                }
                if existingSubdecks.count > 4 {
                    previewMore(existingSubdecks.count - 4, depth: 1)
                }
                ForEach(pending.filter { !trimmed($0.name).isEmpty }) { child in
                    previewRow(trimmed(child.name), icon: child.icon, depth: 1, role: .added)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Three kinds of row. The deck this sheet is about is picked out the way
    /// a selected row is; subdecks written in the sheet read as ordinary rows,
    /// because that is what they are about to be; decks that already exist are
    /// dimmed, as context rather than subject.
    private enum PreviewRole {
        case this
        case added
        case existing
    }

    private func previewRow(_ title: String, icon: DeckIcon, depth: Int, role: PreviewRole) -> some View {
        DeckLabel(title: title, icon: icon)
            .lineLimit(1)
            .foregroundStyle(role == .existing ? Palette.secondaryText : Palette.primaryText)
            .fontWeight(role == .this ? .medium : .regular)
            .padding(.leading, CGFloat(depth) * 22 + 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if role == .this {
                    RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                        .fill(Palette.selection.opacity(0.16))
                }
            }
    }

    private func previewMore(_ count: Int, depth: Int) -> some View {
        Text("and \(count) more")
            .font(.caption)
            .foregroundStyle(Palette.tertiaryText)
            .padding(.leading, CGFloat(depth) * 22 + 6 + 26)
            .padding(.vertical, 2)
    }

    private enum PreviewItem {
        case this
        case sibling(Deck)
        case more(Int)
    }

    /// The new deck among the decks it will sit beside, in the order the
    /// sidebar will put them — with the rest folded away if there are many.
    private var siblingsAround: [PreviewItem] {
        guard let parentID else { return [] }
        let siblings = store.library.subdecks(of: parentID).filter { $0.id != editingID }
        let position = siblings.firstIndex { $0.displayName.localizedStandardCompare(shownName) == .orderedDescending } ?? siblings.count

        var items: [PreviewItem] = siblings.map { .sibling($0) }
        items.insert(.this, at: position)

        // Two either side of it is enough to show where it goes.
        let low = max(0, position - 2)
        let high = min(items.count, position + 3)
        var shown = Array(items[low..<high])
        if low > 0 { shown.insert(.more(low), at: 0) }
        if high < items.count { shown.append(.more(items.count - high)) }
        return shown
    }

    // MARK: - Subdecks

    private var subdecksSection: some View {
        Section {
            ForEach(existingSubdecks) { deck in
                LabeledContent {
                    let words = store.library.wordCount(inDeck: deck.id)
                    Text(words == 0 ? "Empty" : "\(words) \(words == 1 ? "word" : "words")")
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryText)
                } label: {
                    DeckLabel(title: deck.displayName, icon: deck.displayIcon)
                }
            }

            ForEach($pending) { $child in
                HStack(spacing: 10) {
                    DeckIconPicker(icon: $child.icon, languageCode: profile?.learningCode ?? "", size: 26)

                    TextField("Subdeck", text: $child.name)
                        .labelsHidden()
                        .focused($focus, equals: .pending(child.id))

                    Button {
                        pending.removeAll { $0.id == child.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .buttonStyle(.borderless)
                    .help("Don't make this subdeck")
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Palette.selection)
                    .frame(width: 26)

                TextField("New subdeck", text: $draft, prompt: Text("Add a subdeck — A1, A2…"))
                    .labelsHidden()
                    .focused($focus, equals: .draft)
                    .onSubmit(addDraft)

                if !trimmed(draft).isEmpty {
                    Button("Add", action: addDraft)
                        .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Subdecks")
        } footer: {
            Text("Studying “\(shownName)” studies every deck inside it. A subdeck holds words, not decks of its own.")
        }
    }

    private func addDraft() {
        let name = trimmed(draft)
        guard !name.isEmpty else { return }
        pending.append(PendingSubdeck(name: name))
        draft = ""
        focus = .draft
    }

    // MARK: - Saying what will happen

    private var title: String {
        switch mode {
        case .add(_, let parentID): parentID == nil ? "New Deck" : "New Subdeck"
        case .edit(let deck): deck.isSubdeck ? "Subdeck" : "Deck"
        }
    }

    private var subtitle: String? {
        guard !isEditing else { return nil }
        if let parent = store.library.deck(id: parentID) {
            return "A deck inside “\(parent.displayName)”, studied on its own or together with it."
        }
        return "A shelf inside \(profile?.displayName ?? "this language"). Words can be studied one deck at a time."
    }

    private var placementNote: String {
        if hasSubdecks {
            return "A deck with subdecks stays at the top. Decks go two levels deep."
        }
        guard let parent = store.library.deck(id: parentID) else {
            return "Shows under Library, and can hold subdecks of its own."
        }
        return "Shows inside “\(parent.displayName)” and is studied with it."
    }

    private var followLabel: String {
        guard let parent = store.library.deck(id: parentID) else { return "Follow the language's limit" }
        return "Follow \(parent.displayName)’s limit"
    }

    // MARK: - What the sheet is working on

    private var profile: LanguageProfile? {
        switch mode {
        case .add(let profileID, _): store.library.profile(id: profileID)
        case .edit(let deck): store.library.profile(id: deck.profileID)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editingID: UUID? {
        if case .edit(let deck) = mode { return deck.id }
        return nil
    }

    /// The decks this one could go inside: decks at the top of the language,
    /// other than itself.
    private var parents: [Deck] {
        guard let profile else { return [] }
        return store.library.topLevelDecks(in: profile.id).filter { store.library.canNest(editingID, inside: $0.id) }
    }

    private var existingSubdecks: [Deck] {
        guard let editingID else { return [] }
        return store.library.subdecks(of: editingID)
    }

    private var hasSubdecks: Bool { !existingSubdecks.isEmpty }

    private var shownName: String {
        let name = trimmed(name)
        return name.isEmpty ? (parentID == nil ? "New Deck" : "New Subdeck") : name
    }

    private var returnMakesDeck: Bool {
        switch focus {
        case .none, .name: true
        case .draft, .pending: false
        }
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Doing it

    private func commit() {
        // A subdeck typed and not yet added is still one the learner wrote.
        addDraft()

        let chosenIcon: DeckIcon? = icon == .standard ? nil : icon
        let limit = followsAbove ? nil : dailyNewLimit
        let children = parentID == nil
            ? pending.map { (name: $0.name, icon: $0.icon == .standard ? nil : Optional($0.icon)) }
            : []

        switch mode {
        case .add(let profileID, _):
            if let deck = store.addDeck(
                profileID: profileID,
                name: name,
                parentID: parentID,
                icon: chosenIcon,
                dailyNewLimit: limit,
                subdecks: children
            ) {
                // A deck you have just made is the one you want to be looking at.
                router.show(deck: deck.id)
            }

        case .edit(let deck):
            var updated = deck
            updated.name = trimmed(name)
            updated.icon = chosenIcon
            updated.dailyNewLimit = limit
            if let parentID {
                if store.library.canNest(deck.id, inside: parentID) { updated.parentID = parentID }
            } else {
                updated.parentID = nil
            }
            store.save(updated)

            for child in children {
                store.addDeck(profileID: deck.profileID, name: child.name, parentID: deck.id, icon: child.icon)
            }
        }
        dismiss()
    }
}
