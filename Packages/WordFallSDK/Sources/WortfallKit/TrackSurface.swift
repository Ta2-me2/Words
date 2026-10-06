import simd
import Foundation

/// Matches the piecewise-linear mesh, including its 3 m longitudinal segments and cross-section grid.
struct TrackSurface {
    let distance: Float
    let variation: Float
    private var origin: SIMD3<Float> { Self.course(distance, variation: variation) }
    static func course(_ d: Float, variation: Float) -> SIMD3<Float> {
        [5 * (sin(d * .pi / 144 + variation) - sin(variation)), -0.30 * d + 2.4 * sin(d * .pi / 36 + variation), -d]
    }
    func height(x: Float, z: Float) -> Float {
        let d = distance - z
        let start = floor(d / 3) * 3, t = (d - start) / 3
        let a = Self.course(start, variation: variation), b = Self.course(start + 3, variation: variation)
        let center = a + (b - a) * t - origin
        let localX = x - center.x
        let width: Float = abs(localX) <= 4.9 ? 9.8 : 12
        let step = width / 48
        let left = floor((localX + width / 2) / step) * step - width / 2
        let u = (localX - left) / step
        let crossHeight = 0.055 * (left * left * (1 - u) + (left + step) * (left + step) * u)
        return center.y + crossHeight + (width == 9.8 ? 0.025 : 0)
    }
    func normal(x: Float, z: Float, span: Float = 0.35) -> SIMD3<Float> {
        let dx = (height(x: x + span, z: z) - height(x: x - span, z: z)) / (2 * span)
        let dz = (height(x: x, z: z + span) - height(x: x, z: z - span)) / (2 * span)
        return simd_normalize([-dx, 1, -dz])
    }
    func orientation(x: Float, steering: Float) -> simd_quatf {
        // Fit the support plane beneath the whole torso, not a single terrain vertex.
        let dx = (height(x: x + 0.5, z: 0) - height(x: x - 0.5, z: 0)) / 1.0
        let dz = (height(x: x, z: 0.75) - height(x: x, z: -0.75)) / 1.5
        let up = simd_normalize(SIMD3<Float>(-dx, 1, -dz))
        let tangent = Self.course(distance + 0.1, variation: variation) - Self.course(distance - 0.1, variation: variation)
        let heading = SIMD3<Float>(tangent.x / 0.2 + steering, 0, -1)
        let forward = simd_normalize(heading - up * simd_dot(heading, up))
        let right = simd_normalize(simd_cross(forward, up))
        return simd_quatf(simd_float3x3(columns: (right, simd_cross(right, forward), -forward)))
    }
    /// Lowest point of a transformed unit sphere along a plane normal (ellipsoid support mapping).
    static func support(transform: simd_float4x4, normal: SIMD3<Float>) -> SIMD3<Float> {
        let a = simd_float3x3(columns: (SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z), SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z), SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)))
        let local = simd_transpose(a) * normal
        let offset = a * (local / max(0.00001, simd_length(local)))
        return SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z) - offset
    }
}
