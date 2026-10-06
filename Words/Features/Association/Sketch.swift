import AppKit
import Observation
import PencilKit

/// What the pointer is currently doing.
///
/// macOS has no `PKCanvasView` and no `PKToolPicker` — Apple ships those for
/// iPad only — so the board, the tools and the gestures are this app's. What is
/// *not* this app's is the ink: every mark ends up as a `PKStroke` in a
/// `PKDrawing`, drawn by PencilKit's own renderer, so a pencil looks like a
/// pencil and a marker bleeds like a marker.
nonisolated enum SketchTool: Hashable, Sendable {
    case ink(SketchInk)
    case shape(SketchShape)
    case eraser

    var ink: SketchInk? {
        if case .ink(let ink) = self { return ink }
        return nil
    }

    var shape: SketchShape? {
        if case .shape(let shape) = self { return shape }
        return nil
    }
}

/// The three that earn their place. PencilKit has more; a vocabulary app that
/// offers a watercolour brush is a vocabulary app nobody finishes a card in.
nonisolated enum SketchInk: String, CaseIterable, Identifiable, Sendable {
    case pen
    case marker
    case pencil

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: "Pen"
        case .marker: "Marker"
        case .pencil: "Pencil"
        }
    }

    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .marker: "highlighter"
        case .pencil: "pencil"
        }
    }

    var inkType: PKInk.InkType {
        switch self {
        case .pen: .pen
        case .marker: .marker
        case .pencil: .pencil
        }
    }
}

nonisolated enum SketchShape: String, CaseIterable, Identifiable, Sendable {
    case line
    case arrow
    case rectangle
    case ellipse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line: "Line"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Oval"
        }
    }

    var symbol: String {
        switch self {
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "oval"
        }
    }
}

/// Six, fixed, and not taken from the system palette.
///
/// The colour is written into the file. A colour that changes with the app's
/// appearance would mean a drawing made in the dark looked wrong in the light —
/// and the paper is always paper, so these are chosen to read on white.
nonisolated enum SketchColor: String, CaseIterable, Identifiable, Sendable {
    case graphite
    case red
    case orange
    case green
    case blue
    case purple

    var id: String { rawValue }

    var components: (red: Double, green: Double, blue: Double) {
        switch self {
        case .graphite: (0.11, 0.11, 0.12)
        case .red: (0.88, 0.19, 0.19)
        case .orange: (0.91, 0.35, 0.05)
        case .green: (0.18, 0.62, 0.27)
        case .blue: (0.10, 0.44, 0.76)
        case .purple: (0.44, 0.28, 0.91)
        }
    }

    var nsColor: NSColor {
        let parts = components
        return NSColor(srgbRed: parts.red, green: parts.green, blue: parts.blue, alpha: 1)
    }
}

nonisolated enum SketchWidth: String, CaseIterable, Identifiable, Sendable {
    case thin
    case medium
    case thick

    var id: String { rawValue }

    var points: CGFloat {
        switch self {
        case .thin: 3
        case .medium: 7
        case .thick: 14
        }
    }

    var title: String {
        switch self {
        case .thin: "Thin"
        case .medium: "Medium"
        case .thick: "Thick"
        }
    }
}

/// The drawing being made, and everything the board needs to show it.
///
/// It owns a `PKDrawing` and nothing else of consequence: what is saved is that
/// drawing's own data, which is a document in Apple's format rather than
/// anything this app invented.
@Observable
final class Sketch {

    /// The board, in points. Fixed, so that a drawing means the same thing
    /// wherever it is later shown — on the card, in the Library, in a file
    /// somebody exported.
    static let size = CGSize(width: 560, height: 360)

    private(set) var drawing = PKDrawing()

    /// Snapshots, for undo. A drawing is a few kilobytes; twenty of them is
    /// cheaper than being clever.
    private var history: [PKDrawing] = []
    private static let historyLimit = 24

    var tool: SketchTool = .ink(.pen)
    var color: SketchColor = .graphite
    var width: SketchWidth = .medium

    /// The mark being made this instant, as plain polylines. PencilKit renders
    /// the finished stroke; until the pointer comes up there is nothing for it
    /// to render, so the board draws this itself.
    private(set) var live: [[CGPoint]] = []

    private var origin: CGPoint?
    private var startedAt = Date.now

    /// Bumped whenever the finished drawing changes, so the board knows to
    /// build a fresh image rather than diffing a `PKDrawing`.
    private(set) var revision = 0

    init(data: Data? = nil) {
        load(data)
    }

    func load(_ data: Data?) {
        guard let data, let restored = try? PKDrawing(data: data) else { return }
        drawing = restored
        revision += 1
    }

    var isEmpty: Bool { drawing.strokes.isEmpty }
    var strokeCount: Int { drawing.strokes.count }
    var canUndo: Bool { !history.isEmpty }

    /// What gets written to disk.
    var data: Data { drawing.dataRepresentation() }

    // MARK: - Drawing

    func begin(at point: CGPoint) {
        origin = point
        startedAt = .now

        switch tool {
        case .ink:
            live = [[point]]
        case .shape:
            live = []
        case .eraser:
            erase(at: point)
        }
    }

    func extend(to point: CGPoint) {
        guard let origin else { return }

        switch tool {
        case .ink:
            guard var path = live.first else { return }
            // Points arrive as fast as the mouse moves; anything closer than a
            // point adds nothing but work.
            if let last = path.last, hypot(point.x - last.x, point.y - last.y) < 1 { return }
            path.append(point)
            live = [path]
        case .shape(let shape):
            live = Self.outline(of: shape, from: origin, to: point)
        case .eraser:
            erase(at: point)
        }
    }

    func finish() {
        defer {
            live = []
            origin = nil
        }
        guard tool.ink != nil || tool.shape != nil else { return }

        let paths = live.filter { $0.count > 1 }
        guard !paths.isEmpty else {
            // A single click with a pen is a dot, which is a legitimate mark.
            if let point = live.first?.first, tool.ink != nil {
                commit([stroke(through: [point, CGPoint(x: point.x + 0.6, y: point.y)])])
            }
            return
        }
        commit(paths.map { stroke(through: $0) })
    }

    // MARK: - Undoing

    func undo() {
        guard let previous = history.popLast() else { return }
        drawing = previous
        revision += 1
    }

    func clear() {
        guard !drawing.strokes.isEmpty else { return }
        remember()
        drawing = PKDrawing()
        revision += 1
    }

    // MARK: - Making strokes

    private func commit(_ strokes: [PKStroke]) {
        guard !strokes.isEmpty else { return }
        remember()
        drawing = drawing.appending(PKDrawing(strokes: strokes))
        revision += 1
    }

    private func remember() {
        history.append(drawing)
        if history.count > Self.historyLimit { history.removeFirst() }
    }

    private func stroke(through points: [CGPoint]) -> PKStroke {
        let inkType = (tool.ink ?? .pen).inkType
        let ink = PKInk(inkType, color: color.nsColor)
        let size = CGSize(width: width.points, height: width.points)

        let controls = points.enumerated().map { index, point in
            PKStrokePoint(
                location: point,
                timeOffset: Double(index) / 120,
                size: size,
                opacity: 1,
                force: 1,
                azimuth: 0,
                // Straight up: no tilt, because a mouse has none to report and
                // inventing one would make every pencil line look shaded.
                altitude: .pi / 2
            )
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: controls, creationDate: startedAt))
    }

    // MARK: - Erasing

    /// A stroke eraser, not a pixel one: a mark is a thing the learner made, and
    /// rubbing a hole in the middle of it is almost never what they meant.
    private func erase(at point: CGPoint) {
        let radius = max(10, width.points)
        let survivors = drawing.strokes.filter { !Self.stroke($0, passesWithin: radius, of: point) }
        guard survivors.count != drawing.strokes.count else { return }
        remember()
        drawing = PKDrawing(strokes: survivors)
        revision += 1
    }

    private static func stroke(_ stroke: PKStroke, passesWithin radius: CGFloat, of point: CGPoint) -> Bool {
        guard stroke.renderBounds.insetBy(dx: -radius, dy: -radius).contains(point) else { return false }

        let count = stroke.path.count
        guard count > 0 else { return false }
        let steps = min(120, max(8, count * 3))
        let last = CGFloat(count - 1)

        for step in 0...steps {
            let parametric = last * CGFloat(step) / CGFloat(steps)
            let located = stroke.path.interpolatedLocation(at: parametric).applying(stroke.transform)
            if hypot(located.x - point.x, located.y - point.y) <= radius { return true }
        }
        return false
    }

    // MARK: - Shapes

    /// A shape is not a special kind of object: it is a stroke like any other,
    /// so it erases, undoes and exports exactly the way a hand-drawn line does.
    /// An arrow is two of them, because one path cannot lift off the paper.
    static func outline(of shape: SketchShape, from start: CGPoint, to end: CGPoint) -> [[CGPoint]] {
        switch shape {
        case .line:
            return [interpolate(from: start, to: end)]

        case .arrow:
            let angle = atan2(end.y - start.y, end.x - start.x)
            let length = min(24, max(8, hypot(end.x - start.x, end.y - start.y) / 3))
            let spread = CGFloat.pi / 7
            let left = CGPoint(
                x: end.x - cos(angle - spread) * length,
                y: end.y - sin(angle - spread) * length
            )
            let right = CGPoint(
                x: end.x - cos(angle + spread) * length,
                y: end.y - sin(angle + spread) * length
            )
            return [
                interpolate(from: start, to: end),
                interpolate(from: left, to: end) + interpolate(from: end, to: right).dropFirst(),
            ]

        case .rectangle:
            let corners = [
                start,
                CGPoint(x: end.x, y: start.y),
                end,
                CGPoint(x: start.x, y: end.y),
                start,
            ]
            var path: [CGPoint] = []
            for index in 0..<(corners.count - 1) {
                let segment = interpolate(from: corners[index], to: corners[index + 1])
                path += index == 0 ? segment : Array(segment.dropFirst())
            }
            return [path]

        case .ellipse:
            let centre = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let radiusX = abs(end.x - start.x) / 2
            let radiusY = abs(end.y - start.y) / 2
            let steps = 64
            return [(0...steps).map { step in
                let angle = 2 * CGFloat.pi * CGFloat(step) / CGFloat(steps)
                return CGPoint(x: centre.x + cos(angle) * radiusX, y: centre.y + sin(angle) * radiusY)
            }]
        }
    }

    /// Straight lines still need points along them: PencilKit interpolates
    /// between control points, and two of them a hundred points apart make a
    /// line that tapers.
    private static func interpolate(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let distance = hypot(end.x - start.x, end.y - start.y)
        let steps = max(2, min(64, Int(distance / 6)))
        return (0...steps).map { step in
            let fraction = CGFloat(step) / CGFloat(steps)
            return CGPoint(
                x: start.x + (end.x - start.x) * fraction,
                y: start.y + (end.y - start.y) * fraction
            )
        }
    }
}
