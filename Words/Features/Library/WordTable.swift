import AppKit
import SwiftUI

/// The vocabulary table, drawn by AppKit.
///
/// A SwiftUI `Table` gives every cell a hosting view of its own and measures
/// every row it shows. At a few hundred words that was the whole cost of the
/// Library: scrolling spent half its time re-measuring rows that are all one
/// line tall, every row scrolled past kept seven hosting views alive, and
/// leaving the screen afterwards took seconds to take them down again — each
/// one removing itself from observers the window keeps in a single list. A
/// table of plain cells, of one fixed height, reused as they scroll out of
/// sight, costs the same at ten words and at ten thousand.
struct WordTable: NSViewRepresentable {
    let rows: [WordRow]
    @Binding var selection: Set<UUID>
    @Binding var sort: WordSort

    /// The word being spoken, whose speaker is drawn filled.
    let speakingID: UUID?

    let play: (UUID) -> Void
    let open: (UUID) -> Void
    let delete: (Set<UUID>) -> Void

    /// The menu for the rows a right click is about: the selection when the
    /// click was inside it, the clicked row when it was not, nothing when it
    /// was below the rows.
    let menu: (Set<UUID>) -> [NSMenuItem]

    static let rowHeight: CGFloat = 24

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = WordTableView()
        table.style = .inset
        table.rowHeight = Self.rowHeight
        table.usesAutomaticRowHeights = false
        table.usesAlternatingRowBackgroundColors = false
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.allowsColumnReordering = false
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        for column in WordColumn.allCases {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = column.title
            let (minimum, ideal) = Self.widths(column)
            tableColumn.minWidth = minimum
            tableColumn.width = ideal
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: true)
            table.addTableColumn(tableColumn)
        }

        // Before the delegate is set, so that showing the order does not read
        // as choosing it.
        table.sortDescriptors = [NSSortDescriptor(key: sort.column.rawValue, ascending: sort.ascending)]

        let coordinator = context.coordinator
        coordinator.table = table
        coordinator.rows = rows
        coordinator.speakingID = speakingID
        table.dataSource = coordinator
        table.delegate = coordinator
        table.target = coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.onDelete = { [weak coordinator] in coordinator?.deleteSelection() }

        let contextMenu = NSMenu()
        contextMenu.delegate = coordinator
        table.menu = contextMenu

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        coordinator.showSelection()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let table = coordinator.table else { return }

        if coordinator.rows != rows {
            coordinator.rows = rows
            coordinator.speakingID = speakingID
            coordinator.isUpdating = true
            table.reloadData()
            coordinator.isUpdating = false
        } else if coordinator.speakingID != speakingID {
            let changed = [coordinator.speakingID, speakingID].compactMap { $0 }
            coordinator.speakingID = speakingID
            coordinator.reloadAudio(for: changed)
        }

        let current = NSSortDescriptor(key: sort.column.rawValue, ascending: sort.ascending)
        if table.sortDescriptors.first?.key != current.key || table.sortDescriptors.first?.ascending != current.ascending {
            coordinator.isUpdating = true
            table.sortDescriptors = [current]
            coordinator.isUpdating = false
        }

        coordinator.showSelection()
    }

    private static func widths(_ column: WordColumn) -> (CGFloat, CGFloat) {
        switch column {
        case .word: (120, 200)
        case .meaning: (140, 240)
        case .deck: (80, 120)
        case .audio: (52, 60)
        case .drawing: (56, 64)
        case .stage: (100, 120)
        case .due: (90, 120)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: WordTable
        weak var table: WordTableView?
        var rows: [WordRow] = []
        var speakingID: UUID?

        /// Set while the table is being brought into line with SwiftUI, so that
        /// the callbacks this causes are not taken for the learner's doing.
        var isUpdating = false

        init(_ parent: WordTable) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let identifier = tableColumn?.identifier,
                  let column = WordColumn(rawValue: identifier.rawValue),
                  rows.indices.contains(row)
            else { return nil }

            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? WordCell
                ?? WordCell(column: column, target: self, action: #selector(playClicked(_:)))
            cell.identifier = identifier
            cell.show(rows[row], isSpeaking: rows[row].id == speakingID)
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let table else { return }
            let chosen = Set(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
            if chosen != parent.selection { parent.selection = chosen }
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isUpdating,
                  let first = tableView.sortDescriptors.first,
                  let key = first.key,
                  let column = WordColumn(rawValue: key)
            else { return }
            let chosen = WordSort(column: column, ascending: first.ascending)
            if chosen != parent.sort { parent.sort = chosen }
        }

        /// Selects the rows SwiftUI says are selected, by identity: after a
        /// search or a new order the same words are on different lines.
        func showSelection() {
            guard let table else { return }
            var indexes = IndexSet()
            if !parent.selection.isEmpty {
                for (index, row) in rows.enumerated() where parent.selection.contains(row.id) {
                    indexes.insert(index)
                }
            }
            guard indexes != table.selectedRowIndexes else { return }
            isUpdating = true
            table.selectRowIndexes(indexes, byExtendingSelection: false)
            isUpdating = false
        }

        func reloadAudio(for ids: [UUID]) {
            guard let table,
                  let column = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == WordColumn.audio.rawValue })
            else { return }
            let indexes = IndexSet(rows.indices.filter { ids.contains(rows[$0].id) })
            table.reloadData(forRowIndexes: indexes, columnIndexes: IndexSet(integer: column))
        }

        @objc func playClicked(_ sender: NSButton) {
            guard let table else { return }
            let row = table.row(for: sender)
            guard rows.indices.contains(row) else { return }
            parent.play(rows[row].id)
        }

        @objc func doubleClicked(_ sender: Any?) {
            guard let table, rows.indices.contains(table.clickedRow) else { return }
            parent.open(rows[table.clickedRow].id)
        }

        func deleteSelection() {
            guard !parent.selection.isEmpty else { return }
            parent.delete(parent.selection)
        }

        // MARK: The context menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table else { return }

            let clicked = table.clickedRow
            let ids: Set<UUID>
            if rows.indices.contains(clicked) {
                ids = table.selectedRowIndexes.contains(clicked)
                    ? parent.selection
                    : [rows[clicked].id]
            } else {
                ids = []
            }

            for item in parent.menu(ids) {
                menu.addItem(item)
            }
        }
    }
}

/// The table itself, which also answers the Delete key.
final class WordTableView: NSTableView {
    var onDelete: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        // Delete and Forward Delete, as a table of files answers them.
        if event.keyCode == 51 || event.keyCode == 117, !selectedRowIndexes.isEmpty {
            onDelete()
        } else {
            super.keyDown(with: event)
        }
    }

    @objc func delete(_ sender: Any?) {
        onDelete()
    }
}

/// One cell of the vocabulary table. Built once per column kind and then only
/// refilled as it is reused.
final class WordCell: NSTableCellView {
    private let column: WordColumn

    private let primary = NSTextField(labelWithString: "")
    private let secondary = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let button = NSButton()

    /// What the icon is drawn in when the row is not selected.
    private var iconColor: NSColor = .secondaryLabelColor

    init(column: WordColumn, target: AnyObject, action: Selector) {
        self.column = column
        super.init(frame: .zero)

        for label in [primary, secondary] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.cell?.truncatesLastVisibleLine = true
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.translatesAutoresizingMaskIntoConstraints = false
        }
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        button.translatesAutoresizingMaskIntoConstraints = false

        switch column {
        case .word:
            // The article in grey, then the word in a heavier weight.
            secondary.textColor = .secondaryLabelColor
            secondary.setContentCompressionResistancePriority(.required, for: .horizontal)
            secondary.setContentHuggingPriority(.required, for: .horizontal)
            primary.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            let stack = NSStackView(views: [secondary, primary])
            stack.orientation = .horizontal
            stack.spacing = 4
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            pin(stack)

        case .meaning, .deck, .due:
            if column == .deck { primary.textColor = .secondaryLabelColor }
            if column == .due {
                primary.textColor = .secondaryLabelColor
                primary.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            }
            addSubview(primary)
            pin(primary)
            textField = primary

        case .audio:
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.imagePosition = .imageOnly
            button.contentTintColor = .secondaryLabelColor
            button.target = target
            button.action = action
            addSubview(button)
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: leadingAnchor),
                button.centerYAnchor.constraint(equalTo: centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 22),
                button.heightAnchor.constraint(equalToConstant: 18),
            ])
            primary.stringValue = "—"
            primary.textColor = .tertiaryLabelColor
            addSubview(primary)
            pin(primary)

        case .drawing:
            addSubview(icon)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18),
                icon.heightAnchor.constraint(equalToConstant: 16),
            ])

        case .stage:
            primary.textColor = .secondaryLabelColor
            let stack = NSStackView(views: [icon, primary])
            stack.orientation = .horizontal
            stack.spacing = 5
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            pin(stack)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("Not built from an archive.")
    }

    private func pin(_ view: NSView) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            view.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func show(_ row: WordRow, isSpeaking: Bool) {
        switch column {
        case .word:
            secondary.stringValue = row.article
            secondary.isHidden = row.article.isEmpty
            primary.stringValue = row.term
            toolTip = row.article.isEmpty ? row.term : "\(row.article) \(row.term)"

        case .meaning:
            primary.stringValue = row.meaning
            toolTip = row.meaning

        case .deck:
            primary.stringValue = row.deckName.isEmpty ? "—" : row.deckName
            toolTip = nil

        case .due:
            primary.stringValue = row.dueText
            toolTip = nil

        case .audio:
            let audible: Bool
            if case .none = row.audio { audible = false } else { audible = true }
            button.isHidden = !audible
            primary.isHidden = audible
            let symbol = isSpeaking ? "speaker.wave.2.fill" : (row.audio.hasClip ? "waveform" : "speaker.wave.2")
            button.image = Self.symbol(symbol, description: row.audio.hasClip ? "Play recording" : "Listen")
            toolTip = switch row.audio {
            case .clip(.recorded): "Your recording — click to play"
            case .clip(.imported): "An imported recording — click to play"
            case .voice: "No recording; click to hear the system voice"
            case .none: nil
            }

        case .drawing:
            let symbol = row.hasPicture ? "photo" : (row.hasAssociation ? "lightbulb.fill" : "lightbulb")
            icon.image = Self.symbol(symbol, description: nil)
            iconColor = row.hasPicture || row.hasAssociation ? .secondaryLabelColor : .tertiaryLabelColor
            toolTip = row.hasPicture ? "Has a photo" : (row.hasAssociation ? "Has a drawing" : "No drawing")

        case .stage:
            icon.image = Self.symbol(row.stageSymbol, description: nil)
            iconColor = .secondaryLabelColor
            primary.stringValue = row.stageTitle
            toolTip = nil
        }
        applyColors()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyColors() }
    }

    /// A selected row is filled with the accent colour, and grey on it is
    /// unreadable: everything drawn in the row turns to the colour text takes
    /// on a selection, as the system's own tables do.
    private func applyColors() {
        let selected = backgroundStyle == .emphasized
        icon.contentTintColor = selected ? .alternateSelectedControlTextColor : iconColor
        button.contentTintColor = selected ? .alternateSelectedControlTextColor : .secondaryLabelColor
    }

    private static var symbols: [String: NSImage] = [:]

    private static func symbol(_ name: String, description: String?) -> NSImage? {
        if let cached = symbols[name] { return cached }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: NSFont.systemFontSize, weight: .regular, scale: .small))
        symbols[name] = image
        return image
    }
}
