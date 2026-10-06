import RealityKit
import AppKit
import simd

/// Preallocated entities, meshes and materials. Answer effects only reset transforms and velocities.
@MainActor
final class ParticlePool {
    private struct Slot {
        let entity: ModelEntity
        var velocity = SIMD3<Float>.zero
        var scale = SIMD3<Float>(repeating: 1)
        var life: Float = 0
    }
    private var slots: [Slot] = []
    private var cursor = 0
    init(parent: Entity) {
        let mesh = MeshResource.generateBox(size: 1)
        let palette: [UInt32] = [0xFFD571, 0xFFFFFF, 0x83E3D2, 0xBCA4F5, 0xF99CA9]
        let materials = palette.map { UnlitMaterial(color: NSColor(rgb: $0)) }
        slots.reserveCapacity(128)
        for i in 0..<128 {
            let entity = ModelEntity(mesh: mesh, materials: [materials[i % materials.count]])
            entity.isEnabled = false; parent.addChild(entity); slots.append(Slot(entity: entity))
        }
    }
    func emit(at position: SIMD3<Float>, velocity: SIMD3<Float>, scale: SIMD3<Float>, life: Float) {
        let i = cursor; cursor = (cursor + 1) % slots.count
        slots[i].entity.position = position; slots[i].entity.orientation = simd_quatf()
        slots[i].entity.scale = scale; slots[i].entity.isEnabled = true
        slots[i].velocity = velocity; slots[i].scale = scale; slots[i].life = life
    }
    func update(_ dt: Float) {
        let spin = simd_quatf(angle: dt * 4, axis: [0, 1, 0])
        for i in slots.indices where slots[i].life > 0 {
            slots[i].life -= dt
            if slots[i].life <= 0 { slots[i].entity.isEnabled = false; continue }
            slots[i].velocity.y -= 4.5 * dt
            slots[i].entity.position += slots[i].velocity * dt
            slots[i].entity.orientation *= spin
            slots[i].entity.scale = slots[i].scale * max(0.05, min(1, slots[i].life / 0.25))
        }
    }
    func reset() { for i in slots.indices { slots[i].life = 0; slots[i].entity.isEnabled = false } }
}
