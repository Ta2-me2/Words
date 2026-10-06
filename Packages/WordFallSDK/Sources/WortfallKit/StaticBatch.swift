import RealityKit
import simd

/// Bake static props once per level. Each tint/shader uses one mesh per tile.
/// Dynamic character limbs and particles are deliberately kept independent.
@MainActor
enum StaticBatch {
    private struct Group {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let material: any Material
    }
    static func bake(_ root: Entity) {
        var groups: [String: Group] = [:]
        var originals: [ModelEntity] = []
        func collect(_ entity: Entity) {
            if let model = entity as? ModelEntity,
               let tint = model.components[StaticTint.self],
               let component = model.model, let material = component.materials.first {
                let key = "\(tint.color)-\(material is UnlitMaterial)"
                var group = groups[key] ?? Group(material: material)
                let transform = model.transformMatrix(relativeTo: root)
                let linear = float3x3(SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z), SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z), SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
                let normalMatrix = linear.inverse.transpose
                for meshModel in component.mesh.contents.models {
                    for part in meshModel.parts {
                        guard let normals = part.normals?.elements, let indices = part.triangleIndices?.elements else { continue }
                        let offset = UInt32(group.positions.count)
                        group.positions += part.positions.elements.map { p in
                            let v = transform * SIMD4(p, 1); return SIMD3(v.x, v.y, v.z)
                        }
                        group.normals += normals.map { simd_normalize(normalMatrix * $0) }
                        group.indices += indices.map { $0 + offset }
                    }
                }
                groups[key] = group; originals.append(model)
            }
            for child in entity.children { collect(child) }
        }
        collect(root)
        var baked: [ModelEntity] = []
        do {
            for (key, group) in groups where !group.indices.isEmpty {
                let mesh = try Geometry.mesh("static-\(key)", positions: group.positions, normals: group.normals, indices: group.indices)
                let model = ModelEntity(mesh: mesh, materials: [group.material])
                if #available(macOS 15.0, *) { model.components.set(DynamicLightShadowComponent(castsShadow: false)) }
                baked.append(model)
            }
        } catch { return } // Preserve original scene if baking fails.
        for original in originals { original.model = nil }
        // All descendants are static; flattened geometry replaces the hierarchy.
        func prune(_ entity: Entity) {
            for child in Array(entity.children) {
                prune(child)
                if child.children.isEmpty && (child as? ModelEntity)?.model == nil { child.removeFromParent() }
            }
        }
        prune(root)
        for model in baked { root.addChild(model) }
    }
}
