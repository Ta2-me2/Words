import XCTest
import SwiftUI
import AppKit
@testable import WortfallKit

@MainActor
private final class AppearanceRoute: ObservableObject {
    @Published var screen = 0
    let progress = WortfallProgress()
}
private struct AppearanceHost: View {
    @ObservedObject var route: AppearanceRoute
    var body: some View {
        VStack {
            Text("Host toolbar")
            switch route.screen {
            case 1: WortfallLibraryView(libraryID: "appearance-test", decks: [], progress: route.progress)
            case 2: WortfallGameView()
            case 3: Text("Preference control").preferredColorScheme(.dark)
            default: Text("Host screen")
            }
        }.frame(width: 900, height: 700)
    }
}
final class HostAppearanceTests: XCTestCase {
    @MainActor
    func testGameDoesNotOverrideHostWindowAppearance() async throws {
        let app = NSApplication.shared
        let previous = app.appearance
        app.appearance = NSAppearance(named: .aqua)
        let route = AppearanceRoute()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AppearanceHost(route: route))
        window.orderFront(nil)
        defer { window.close(); app.appearance = previous }
        func settle() async throws { try await Task.sleep(nanoseconds: 500_000_000) }
        try await settle()
        XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
        // Positive control: window-level preferences must be observable by this harness.
        route.screen = 3; try await settle()
        XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        route.screen = 0; try await settle()
        route.screen = 1; try await settle()
        XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua, "The dark game menu must not darken its light host")
        route.screen = 0; try await settle()
        XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
        app.appearance = NSAppearance(named: .darkAqua)
        route.screen = 2; try await settle()
        XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua, "The light game surface must not lighten its dark host")
        route.screen = 0; try await settle()
        XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
    }
}
