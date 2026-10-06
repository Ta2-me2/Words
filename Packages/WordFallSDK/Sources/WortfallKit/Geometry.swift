import RealityKit
import AppKit
import simd

struct StaticTint: Component { let color: UInt32 }

@MainActor
enum Geometry {
    static func material(_ hex: UInt32, roughness: Float = 0.32, metallic: Bool = false) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: NSColor(rgb: hex))
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: metallic ? 0.5 : 0)
        m.clearcoat = .init(floatLiteral: 0.8)
        m.clearcoatRoughness = .init(floatLiteral: 0.17)
        return m
    }
    static let sphere: MeshResource = {
        var positions: [SIMD3<Float>] = [], indices: [UInt32] = []
        let rows = 16, columns = 24
        for row in 0...rows {
            let phi = Float(row) * .pi / Float(rows)
            for column in 0...columns {
                let theta = Float(column) * 2 * .pi / Float(columns)
                positions.append([sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)])
            }
        }
        for row in 0..<rows { for column in 0..<columns {
            let a = UInt32(row * (columns + 1) + column), b = a + UInt32(columns + 1)
            indices += [a, a + 1, b, a + 1, b + 1, b]
        }}
        return (try? mesh("smooth-sphere", positions: positions, normals: positions, indices: indices)) ?? .generateSphere(radius: 1)
    }()
    static func ball(_ size: SIMD3<Float>, _ color: UInt32, at position: SIMD3<Float> = .zero) -> ModelEntity {
        let e = ModelEntity(mesh: sphere, materials: [material(color)])
        e.name = "ellipsoid-contact"
        e.components.set(StaticTint(color: color))
        e.scale = size; e.position = position; return e
    }
    static func box(_ size: SIMD3<Float>, _ color: UInt32, at position: SIMD3<Float> = .zero, radius: Float = 0.12) -> ModelEntity {
        let e = ModelEntity(mesh: .generateBox(size: size, cornerRadius: radius), materials: [material(color)])
        e.components.set(StaticTint(color: color))
        e.position = position; return e
    }
    static func mesh(_ name: String, positions: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]) throws -> MeshResource {
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffer(positions); d.normals = MeshBuffer(normals)
        d.primitives = .triangles(indices)
        return try MeshResource.generate(from: [d])
    }
    static func torus(radius: Float, tube: Float) throws -> MeshResource {
        var p: [SIMD3<Float>] = [], n: [SIMD3<Float>] = [], indices: [UInt32] = []
        let rows = 64, cols = 12
        for i in 0...rows {
            let a = Float(i) / Float(rows) * .pi * 2
            for j in 0...cols {
                let b = Float(j) / Float(cols) * .pi * 2
                let normal = SIMD3<Float>(cos(a) * cos(b), sin(a) * cos(b), sin(b))
                p.append(SIMD3<Float>(radius * cos(a), radius * sin(a), 0) + tube * normal); n.append(normal)
            }
        }
        for i in 0..<rows { for j in 0..<cols {
            let a = UInt32(i * (cols + 1) + j), b = a + UInt32(cols + 1)
            indices += [a, b, a + 1, a + 1, b, b + 1]
        }}
        return try mesh("inflatable-ring", positions: p, normals: n, indices: indices)
    }
    static func track(length: Float = 12, width: Float = 12, lift: Float = 0, start: Float = 0, variation: Float = 0) throws -> MeshResource {
        var p: [SIMD3<Float>] = [], n: [SIMD3<Float>] = [], indices: [UInt32] = []
        let across = 48, along = 4
        for j in 0...along { for i in 0...across {
            let x = -width / 2 + Float(i) / Float(across) * width
            let d = Float(j) / Float(along) * length
            let center = course(start + d, variation: variation) - course(start, variation: variation)
            p.append(center + SIMD3<Float>(x, floorHeight(x) + lift, 0))
            let derivative = course(start + d + 0.01, variation: variation) - course(start + d - 0.01, variation: variation)
            n.append(simd_normalize(simd_cross(SIMD3<Float>(1, 0.11 * x, 0), derivative)))
        }}
        for j in 0..<along { for i in 0..<across {
            let a = UInt32(j * (across + 1) + i), c = a + UInt32(across + 1)
            indices += [a, a + 1, c, a + 1, c + 1, c]
        }}
        return try mesh("half-pipe", positions: p, normals: n, indices: indices)
    }
    static let slope: Float = 0.30
    static func course(_ d: Float, variation: Float) -> SIMD3<Float> {
        TrackSurface.course(d, variation: variation)
    }
    static func floorHeight(_ x: Float) -> Float { 0.055 * x * x }
    /// A vertical textured curtain whose lower edge exactly follows the trough.
    static func answerZone(_ lane: Int) throws -> MeshResource {
        var p: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = [], indices: [UInt32] = []
        for i in 0...12 {
            let u = Float(i) / 12, x = -6 + Float(lane) * 4 + u * 4
            p += [[x, floorHeight(x) + 0.02, 0], [x, floorHeight(x) + 2.9, 0]]
            uv += [[u, 1], [u, 0]]
            if i < 12 { let a = UInt32(i * 2); indices += [a, a + 2, a + 1, a + 1, a + 2, a + 3] }
        }
        var descriptor = MeshDescriptor(name: "answer-curtain")
        descriptor.positions = MeshBuffer(p)
        descriptor.normals = MeshBuffer(Array(repeating: SIMD3<Float>(0, 0, 1), count: p.count))
        descriptor.textureCoordinates = MeshBuffer(uv)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
    static func checkpointTexture() throws -> TextureResource {
        let width = 128
        let context = CGContext(data: nil, width: width, height: width, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<8 { for x in 0..<8 {
            let alpha: CGFloat = (x + y) % 2 == 0 ? 0.48 : 0.19
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
            context.fill(CGRect(x: x * 16, y: y * 16, width: 16, height: 16))
        }}
        return try TextureResource.generate(from: context.makeImage()!, options: .init(semantic: .color))
    }
    static func text(_ string: String, height: Float, color: UInt32) -> ModelEntity {
        let mesh = MeshResource.generateText(string, extrusionDepth: 0.012, font: .systemFont(ofSize: CGFloat(height), weight: .bold), containerFrame: .zero, alignment: .center, lineBreakMode: .byWordWrapping)
        let e = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: NSColor(rgb: color))])
        let b = e.visualBounds(relativeTo: nil)
        e.position.x = -b.center.x
        return e
    }
    static func runner() -> (Entity, Entity, Entity) {
        let rig = Entity(), body = Entity()
        rig.addChild(body)
        body.addChild(ball([0.49, 0.67, 0.40], 0xFA867E, at: [0, 0.75, 0]))
        body.addChild(ball([0.44, 0.45, 0.40], 0xFFAAA0, at: [0, 1.16, 0]))
        body.addChild(ball([0.35, 0.29, 0.075], 0xFFF5DE, at: [0, 1.17, 0.365]))
        for side: Float in [-1, 1] {
            body.addChild(ball([0.048, 0.092, 0.035], 0x2B3C54, at: [side * 0.125, 1.18, 0.435]))
            let foot = ball([0.18, 0.14, 0.31], 0x49C9C0, at: [side * 0.24, 0.12, 0.10])
            foot.name = side < 0 ? "left-foot" : "right-foot"; body.addChild(foot)
            let arm = ball([0.15, 0.36, 0.15], 0xFA867E, at: [side * 0.57, 0.77, 0])
            arm.name = side < 0 ? "left-arm" : "right-arm"
            arm.orientation = simd_quatf(angle: side * 0.8, axis: [0, 0, 1]); body.addChild(arm)
        }
        let scarf = box([0.85, 0.12, 0.68], 0xFFF1CE, at: [0, 0.99, -0.04], radius: 0.055)
        body.addChild(scarf)
        let ribbon = box([0.22, 0.62, 0.07], 0xFFF1CE, at: [0.23, 0.65, -0.43], radius: 0.03)
        body.addChild(ribbon)
        body.addChild(ball([0.11, 0.16, 0.13], 0xFFD66C, at: [0.1, 1.58, 0]))
        let pack = ball([0.27, 0.33, 0.12], 0x42BEB8, at: [0, 0.74, -0.38])
        pack.addChild(box([0.08, 0.42, 0.04], 0xFFE5A0, at: [0, 0, -0.12], radius: 0.02))
        body.addChild(pack)
        // Local +Z is the belly. Flip it down while +Y (the head) points downhill.
        body.position = [0, 0.52, 0.75]
        body.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]) * simd_quatf(angle: .pi, axis: [0, 1, 0])
        return (rig, body, ribbon)
    }
}
