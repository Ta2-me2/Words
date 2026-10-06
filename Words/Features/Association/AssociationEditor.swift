import AppKit
import PencilKit
import SwiftUI
import UniformTypeIdentifiers

/// What sits in a word's one place for a picture.
enum DrawingContent: Equatable {
    case none
    /// A drawing made on the board: the drawing's own data, and its stroke count.
    case drawing(Data, strokes: Int)
    /// A photograph: its bytes and the extension its kind calls for.
    case photo(Data, fileExtension: String)
}

/// The row where a word gets its picture, wherever a word is being written.
///
/// One place, two ways of filling it. A drawing is made here on the board and
/// is offered during study to a word that keeps going; a photograph is chosen,
/// dropped or pasted, and is shown with the word every time. A word has one or
/// the other, and the row says which.
///
/// What is already there is read once rather than on every pass through a
/// form's body: it is a file on disk and a picture to render, and a form's body
/// runs on every keystroke.
struct AssociationEditor: View {
    let term: String
    let meaning: String

    /// Deferred on purpose — see above. Called once, when the row appears.
    let load: () -> DrawingContent

    let save: (DrawingContent) -> Void

    @State private var content: DrawingContent = .none
    @State private var thumbnail: NSImage?
    @State private var isDrawing = false
    @State private var isChoosingPhoto = false
    @State private var isTargeted = false
    @State private var hasLoaded = false

    var body: some View {
        HStack(spacing: 12) {
            switch content {
            case .none:
                Button { isDrawing = true } label: {
                    Label("Draw an Association", systemImage: "lightbulb")
                }
                .disabled(term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button { isChoosingPhoto = true } label: {
                    Label("Add Photo…", systemImage: "photo")
                }

                if canPaste {
                    Button("Paste") { paste() }
                        .help("Use the image on the clipboard")
                }

            case .drawing:
                thumbnailView(help: "Change the drawing") { isDrawing = true }
                VStack(alignment: .leading, spacing: 4) {
                    Button("Edit…") { isDrawing = true }
                    Button("Remove", role: .destructive) { apply(.none) }
                }
                .buttonStyle(.link)
                .font(.callout)

            case .photo:
                thumbnailView(help: "Choose another photo") { isChoosingPhoto = true }
                VStack(alignment: .leading, spacing: 4) {
                    Button("Replace…") { isChoosingPhoto = true }
                    Button("Remove", role: .destructive) { apply(.none) }
                }
                .buttonStyle(.link)
                .font(.callout)
            }

            Spacer(minLength: 0)
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Palette.selection, lineWidth: isTargeted ? 1.5 : 0)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            return takePhoto(from: url)
        } isTargeted: { isTargeted = $0 }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            show(load())
        }
        .sheet(isPresented: $isDrawing) {
            AssociationSheet(term: term, meaning: meaning, existing: existingDrawing) { drawn, strokes in
                apply(strokes == 0 ? .none : .drawing(drawn, strokes: strokes))
            }
        }
        .fileImporter(isPresented: $isChoosingPhoto, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { _ = takePhoto(from: url) }
        }
    }

    private func thumbnailView(help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
            }
            .frame(width: 96, height: 62)
            .background(AssociationCanvas.paper)
            .clipShape(.rect(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Palette.separator)
            }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var existingDrawing: Data? {
        if case .drawing(let data, _) = content { return data }
        return nil
    }

    private var canPaste: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    // MARK: - Changing it

    private func apply(_ new: DrawingContent) {
        show(new)
        save(new)
    }

    private func show(_ new: DrawingContent) {
        content = new
        switch new {
        case .none: thumbnail = nil
        case .drawing(let data, _): thumbnail = AssociationRenderer.image(from: data)
        case .photo(let data, _): thumbnail = NSImage(data: data)
        }
    }

    @discardableResult
    private func takePhoto(from url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let prepared = PhotoPreparation.prepare(data) else { return false }
        apply(.photo(prepared.data, fileExtension: prepared.fileExtension))
        return true
    }

    private func paste() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
              let tiff = image.tiffRepresentation,
              let prepared = PhotoPreparation.prepare(tiff)
        else { return }
        apply(.photo(prepared.data, fileExtension: prepared.fileExtension))
    }
}

/// Makes a photograph fit to keep.
///
/// A photo straight off a phone is twelve megapixels of HEIC; a card shows it a
/// few hundred points wide. Anything that is not already a modest JPEG or PNG is
/// redrawn as a JPEG no larger than it will ever be looked at.
enum PhotoPreparation {
    static let longestSide: CGFloat = 1600

    static func prepare(_ data: Data) -> (data: Data, fileExtension: String)? {
        let kind = MediaKind.sniff(data)
        if let kind, kind == .jpeg || kind == .png, data.count <= 1_500_000 {
            return (data, kind.fileExtension)
        }

        guard let image = NSImage(data: data),
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let scale = min(1, longestSide / CGFloat(max(source.width, source.height)))
        let width = Int(CGFloat(source.width) * scale)
        let height = Int(CGFloat(source.height) * scale)

        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let resized = context.makeImage() else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: resized)
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return nil }
        return (jpeg, "jpg")
    }
}

extension AssociationRenderer {

    /// A picture from bytes that may not have a file yet — the Add Words screen
    /// holds a drawing in the air until the word it belongs to exists.
    static func image(from data: Data) -> NSImage? {
        guard let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return nil }
        return AssociationCanvas.render(drawing)
    }
}
