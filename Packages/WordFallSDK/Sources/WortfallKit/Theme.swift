import AppKit
import SwiftUI

struct WorldTheme {
    let name: String
    let subtitle: String
    let sky: UInt32
    let track: UInt32
    let rail: UInt32
    let accent: UInt32
    let island: UInt32
    let motif: Int
    static let all: [WorldTheme] = [
        .init(name: "Peach clouds", subtitle: "ABOVE THE CLOUDS", sky: 0xB8DCF2, track: 0xFFE6A1, rail: 0xF789AC, accent: 0xF86783, island: 0xB1A6E9, motif: 0),
        .init(name: "Mint archipelago", subtitle: "AN OCEAN OF POSSIBILITY", sky: 0x97DFDC, track: 0xDAF6E8, rail: 0x43B8A7, accent: 0xFEBD69, island: 0x7CCCCC, motif: 1),
        .init(name: "Blueberry orbit", subtitle: "FIND YOUR RHYTHM", sky: 0x353966, track: 0xBDBAF4, rail: 0xF1A5DC, accent: 0x8CEDDA, island: 0x6D69A6, motif: 2),
        .init(name: "Lemon carnival", subtitle: "ONE MORE FLIGHT", sky: 0xBCE9F4, track: 0xFFF3B2, rail: 0xA89BF1, accent: 0xF69C68, island: 0xB6DFA9, motif: 3),
        .init(name: "Rose sunset", subtitle: "ON TO SOMETHING NEW", sky: 0xEDBED5, track: 0xFFE0C4, rail: 0xC691D4, accent: 0xF46F8D, island: 0xD9A2CC, motif: 0),
        .init(name: "Azure ice", subtitle: "CLARITY AND SPEED", sky: 0xA7CFE7, track: 0xE1F4FF, rail: 0x70B7DA, accent: 0xB8A0F5, island: 0x94B6DA, motif: 2)
    ]
    static func level(_ n: Int) -> WorldTheme { all[(n - 1) % all.count] }
}
extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: alpha)
    }
}
extension Color {
    init(rgb: UInt32) { self.init(nsColor: NSColor(rgb: rgb)) }
    static let ink = Color(rgb: 0x253552)
}
