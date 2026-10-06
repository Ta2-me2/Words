import SwiftUI
import RealityKit
import AppKit

struct NativeGameView: NSViewRepresentable {
    let session: GameSession
    func makeNSView(context: Context) -> InputARView {
        let view = InputARView(frame: .zero)
        view.session = session
        do { context.coordinator.scene = try GameScene(session: session, view: view) }
        catch { DispatchQueue.main.async { session.error = error.localizedDescription } }
        return view
    }
    func updateNSView(_ nsView: InputARView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    static func dismantleNSView(_ nsView: InputARView, coordinator: Coordinator) { coordinator.scene?.stop() }
    @MainActor final class Coordinator { var scene: GameScene? }
}

final class InputARView: ARView {
    weak var session: GameSession?
    private var tracking: NSTrackingArea?
    override var acceptsFirstResponder: Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        session?.point(Double(point.x / max(1, bounds.width)))
    }
    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); mouseMoved(with: event) }
    override func keyDown(with event: NSEvent) {
        guard let session, !session.inputSuspended, !session.isLoading else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 18: session.lane(0)
        case 19: session.lane(1)
        case 20: session.lane(2)
        case 123: session.lane(max(0, session.engine.selectedLane - 1))
        case 124: session.lane(min(2, session.engine.selectedLane + 1))
        case 49: if session.engine.phase == .ready { session.start() } else { session.togglePause() }
        case 53: session.togglePause()
        default: super.keyDown(with: event)
        }
    }
}
