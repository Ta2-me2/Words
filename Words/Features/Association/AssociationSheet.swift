import SwiftUI

/// The small window a drawing is made in.
///
/// Small on purpose. An association is a scribble that takes twenty seconds —
/// an arrow, a face, two boxes — and a full-screen studio would turn a memory
/// aid into a task. It opens the same way from the card, from the Library and
/// from the Add Words screen, so there is one thing to learn.
struct AssociationSheet: View {

    let term: String
    let meaning: String
    let existing: Data?

    /// Handed the drawing's own data and how many strokes are in it. An empty
    /// drawing is a removal, and the caller is told so by a stroke count of nought.
    let onSave: (Data, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sketch = Sketch()
    @State private var hasLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(spacing: 12) {
                tools
                AssociationCanvas(sketch: sketch)
            }
            .padding(Metrics.cardPadding)

            Divider()
            actions
        }
        .frame(width: Sketch.size.width + Metrics.cardPadding * 2)
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            sketch.load(existing)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(term)
                .font(.headline)
            Text(meaning)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("Draw what it reminds you of")
                .font(.caption)
                .foregroundStyle(Palette.tertiaryText)
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 12)
    }

    // MARK: - Tools

    private var tools: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(SketchInk.allCases) { ink in
                    toolButton(ink.symbol, help: ink.title, isOn: sketch.tool == .ink(ink)) {
                        sketch.tool = .ink(ink)
                    }
                }

                Divider().frame(height: 18)

                ForEach(SketchShape.allCases) { shape in
                    toolButton(shape.symbol, help: shape.title, isOn: sketch.tool == .shape(shape)) {
                        sketch.tool = .shape(shape)
                    }
                }

                Divider().frame(height: 18)

                toolButton("eraser", help: "Erase a mark", isOn: sketch.tool == .eraser) {
                    sketch.tool = .eraser
                }

                Spacer(minLength: 8)

                toolButton("arrow.uturn.backward", help: "Undo", isOn: false) { sketch.undo() }
                    .disabled(!sketch.canUndo)

                toolButton("trash", help: "Clear the board", isOn: false) { sketch.clear() }
                    .disabled(sketch.isEmpty)
            }

            HStack(spacing: 6) {
                ForEach(SketchColor.allCases) { colour in
                    Button {
                        sketch.color = colour
                        if sketch.tool == .eraser { sketch.tool = .ink(.pen) }
                    } label: {
                        Circle()
                            .fill(Color(nsColor: colour.nsColor))
                            .frame(width: 18, height: 18)
                            .overlay {
                                Circle().strokeBorder(.white.opacity(0.6), lineWidth: 0.5)
                            }
                            .padding(3)
                            .overlay {
                                Circle()
                                    .strokeBorder(Palette.selection, lineWidth: sketch.color == colour ? 2 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(colour.rawValue.capitalized)
                }

                Divider().frame(height: 18)

                ForEach(SketchWidth.allCases) { width in
                    Button {
                        sketch.width = width
                    } label: {
                        Circle()
                            .fill(Palette.primaryText)
                            .frame(width: width.points + 2, height: width.points + 2)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(sketch.width == width ? Palette.subtleFill : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(width.title)
                }

                Spacer(minLength: 0)
            }
        }
        .animation(.easeOut(duration: 0.12), value: sketch.tool)
        .animation(.easeOut(duration: 0.12), value: sketch.color)
        .animation(.easeOut(duration: 0.12), value: sketch.width)
    }

    private func toolButton(_ symbol: String, help: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .imageScale(.medium)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? Palette.subtleFill : .clear)
                )
                .foregroundStyle(isOn ? Palette.selection : Palette.primaryText)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 10) {
            Text(sketch.isEmpty ? "" : "\(sketch.strokeCount) \(sketch.strokeCount == 1 ? "mark" : "marks")")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.tertiaryText)

            Spacer(minLength: 0)

            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)

            // An empty board is how a drawing is taken off a word: there is no
            // separate delete, because clearing it and saving already says it.
            Button(sketch.isEmpty && existing != nil ? "Remove" : "Save") {
                onSave(sketch.data, sketch.strokeCount)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(sketch.isEmpty && existing == nil)
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 12)
    }
}
