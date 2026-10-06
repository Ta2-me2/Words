import XCTest
import simd
@testable import WortfallKit

final class TrackSurfaceTests: XCTestCase {
    func testSurfaceMatchesRenderedVertices() {
        for d: Float in stride(from: 0, through: 288, by: 3) {
            let surface = TrackSurface(distance: 17.3, variation: 0.71)
            let center = TrackSurface.course(d, variation: 0.71) - TrackSurface.course(17.3, variation: 0.71)
            for i in 1..<48 {
                let x: Float = -4.9 + Float(i) * 9.8 / 48
                XCTAssertEqual(surface.height(x: center.x + x, z: center.z), center.y + 0.055 * x * x + 0.025, accuracy: 0.0002)
            }
        }
    }
    func testSupportOrientationTracksBothSlopes() {
        for d: Float in stride(from: 0, through: 288, by: 2) {
            for x: Float in [-4, 0, 4] {
                let surface = TrackSurface(distance: d, variation: 0.2)
                let up = surface.orientation(x: x, steering: 0).act([0, 1, 0])
                XCTAssertGreaterThan(simd_dot(up, surface.normal(x: x, z: 0)), 0.995)
            }
        }
    }
}
