import AppKit
import PencilKit
import SwiftUI

/// The board: paper, a dot grid, everything drawn so far, and the mark being
/// made this instant.
///
/// The paper is paper in both appearances. A drawing is a document — it is
/// written to a file, it can leave the app, and a black line made in the dark
/// must not vanish in the light — so the board does not follow the theme the
/// way the rest of the window does.
struct AssociationCanvas: View {
    let sketch: Sketch

    /// Everything already committed, rendered by PencilKit. Rebuilt when the
    /// drawing changes and not once per frame.
    @State private var rendered: NSImage?
    @State private var renderedRevision = -1

    /// Whether a mark is in progress. The gesture's own phase is not enough:
    /// its first event may already carry a translation.
    @State private var isMarking = false

    private static let dotSpacing: CGFloat = 20

    var body: some View {
        let live = sketch.live
        let size = Sketch.size

        ZStack {
            Canvas { context, canvas in
                context.fill(Path(CGRect(origin: .zero, size: canvas)), with: .color(Self.paper))
                context.fill(Self.dots(in: canvas), with: .color(Self.grid))
            }

            if let rendered {
                Image(nsImage: rendered)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
            }

            Canvas { context, _ in
                guard !live.isEmpty else { return }
                var path = Path()
                for polyline in live where polyline.count > 1 {
                    path.addLines(polyline)
                }
                context.stroke(
                    path,
                    with: .color(Color(nsColor: sketch.color.nsColor).opacity(sketch.tool.ink == .marker ? 0.45 : 0.85)),
                    style: StrokeStyle(lineWidth: sketch.width.points, lineCap: .round, lineJoin: .round)
                )
            }
            .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Begun from `startLocation`, not from the first event's
                    // location: a hand that moves quickly can have travelled
                    // before the first event arrives, and a mark that only
                    // starts once the pointer has slowed down is a mark that
                    // sometimes does not start at all.
                    start(value)
                    sketch.extend(to: clamped(value.location))
                }
                .onEnded { value in
                    start(value)
                    sketch.extend(to: clamped(value.location))
                    sketch.finish()
                    isMarking = false
                }
        )
        .clipShape(.rect(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.separator)
        }
        .onChange(of: sketch.revision, initial: true) { render() }
    }

    private func start(_ value: DragGesture.Value) {
        guard !isMarking else { return }
        isMarking = true
        sketch.begin(at: clamped(value.startLocation))
    }

    private func render() {
        guard renderedRevision != sketch.revision else { return }
        renderedRevision = sketch.revision
        rendered = sketch.isEmpty ? nil : AssociationCanvas.render(sketch.drawing)
    }

    /// A mark begun inside the board and dragged past its edge stops at the
    /// edge rather than being lost off the side of the paper.
    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x), Sketch.size.width),
            y: min(max(0, point.y), Sketch.size.height)
        )
    }

    private static func dots(in size: CGSize) -> Path {
        var path = Path()
        var y = dotSpacing
        while y < size.height {
            var x = dotSpacing
            while x < size.width {
                path.addEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
                x += dotSpacing
            }
            y += dotSpacing
        }
        return path
    }

    static let paper = Color(nsColor: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    static let grid = Color(nsColor: NSColor(srgbRed: 0.72, green: 0.72, blue: 0.74, alpha: 1))

    /// PencilKit lightens dark ink when it renders into a dark appearance — the
    /// right thing on a dark canvas, and exactly wrong here, because this paper
    /// is always paper. Rendering in the light appearance whatever the app is
    /// set to keeps black ink black, on screen and in anything exported.
    static func render(_ drawing: PKDrawing) -> NSImage {
        let rect = CGRect(origin: .zero, size: Sketch.size)
        guard let light = NSAppearance(named: .aqua) else { return drawing.image(from: rect, scale: 2) }

        var image: NSImage?
        light.performAsCurrentDrawingAppearance { image = drawing.image(from: rect, scale: 2) }
        return image ?? drawing.image(from: rect, scale: 2)
    }
}

/// Turning a stored drawing into a picture, once per drawing rather than once
/// per row that shows it.
///
/// The Library learned this lesson with voices: anything that costs real work
/// must not be done inside a list's body.
@MainActor
enum AssociationRenderer {

    private static var cache: [String: NSImage] = [:]
    private static var order: [String] = []
    private static let limit = 48

    static func image(for association: Association, store: LibraryStore) -> NSImage? {
        let key = "\(association.file)@\(association.updatedAt.timeIntervalSinceReferenceDate)"
        if let cached = cache[key] { return cached }

        guard let data = store.associationData(for: association),
              let drawing = try? PKDrawing(data: data),
              !drawing.strokes.isEmpty
        else { return nil }

        let image = AssociationCanvas.render(drawing)
        cache[key] = image
        order.append(key)
        if order.count > limit, let oldest = order.first {
            order.removeFirst()
            cache[oldest] = nil
        }
        return image
    }

    /// A drawing shown as a picture on paper, at whatever size it is given.
    static func view(for association: Association, store: LibraryStore) -> some View {
        Group {
            if let image = image(for: association, store: store) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(Sketch.size.width / Sketch.size.height, contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .background(AssociationCanvas.paper)
        .clipShape(.rect(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.separator)
        }
    }
}
