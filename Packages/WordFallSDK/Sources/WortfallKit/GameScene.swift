import AppKit
import RealityKit
import Combine
import WortfallCore
import simd

@MainActor
final class GameScene {
    weak var session: GameSession?
    weak var view: ARView?
    private let anchor = AnchorEntity(world: .zero)
    private let world = Entity()
    private let camera = PerspectiveCamera()
    private let runner: Entity
    private let body: Entity
    private let scarf: Entity
    private var tiles: [Entity] = []
    private var gate = Entity()
    private var builtLevel = 0
    private var gateRevision = -1
    private var zones: [ModelEntity] = []
    private var zoneMaterials: [UnlitMaterial] = []
    private var rejectedMaterial = UnlitMaterial()
    private var finish = Entity()
    private var subscription: Cancellable?
    private let zoneMeshes: [MeshResource]
    private let checkpointTexture: TextureResource
    private var particles: ParticlePool!
    private var limbs: [Entity?] = []
    private var contactShadow: Entity?
    private var contacts: [Entity] = []
    private var contactReady = false
    private var firstTile = Int.min
    private var lastGateDistance: Float = -.infinity
    private var projectionTime: Float = 0
    private let audio = GameAudio()
    private let boostLight = PointLight()
    private var clock: Float = 0
    private var impact: Float = 0
    private var celebration: Float = 0
    private var trailTime: Float = 0
    private var variation: Float { Float((session?.engine.level ?? 1) - 1) * 0.71 }
    private func point(_ d: Float) -> SIMD3<Float> { Geometry.course(d, variation: variation) }
    private var theme: WorldTheme { WorldTheme.level(session?.engine.level ?? 1) }

    init(session: GameSession, view: ARView) throws {
        self.session = session; self.view = view
        zoneMeshes = try (0..<3).map { try Geometry.answerZone($0) }
        checkpointTexture = try Geometry.checkpointTexture()
        (runner, body, scarf) = Geometry.runner()
        view.environment.background = .color(NSColor(rgb: theme.sky))
        boostLight.light.color = NSColor(rgb: 0x8FFFF0)
        boostLight.light.intensity = 250
        boostLight.light.attenuationRadius = 5
        anchor.addChild(boostLight)
        anchor.addChild(world); anchor.addChild(runner); anchor.addChild(camera)
        camera.camera.fieldOfViewInDegrees = 54
        let sun = DirectionalLight()
        sun.light.color = NSColor(rgb: 0xFFF4E4)
        sun.light.intensity = 2600
        sun.shadow = .init(maximumDistance: 45, depthBias: 1)
        sun.look(at: [0, -5, -20], from: [-12, 24, 12], relativeTo: nil)
        anchor.addChild(sun)
        let fill = DirectionalLight()
        fill.light.color = NSColor(rgb: 0xD5EDFF); fill.light.intensity = 1100
        fill.look(at: .zero, from: [15, 12, -15], relativeTo: nil); anchor.addChild(fill)
        // Soft contact shadow remains stable while the character squashes and leans.
        let shadow = Geometry.ball([0.57, 0.012, 0.9], 0x9C89AD, at: [0, 0.055, 0])
        contactShadow = shadow; anchor.addChild(shadow)
        limbs = ["left-arm", "right-arm", "left-foot", "right-foot"].map { body.findEntity(named: $0) }
        func gatherContacts(_ entity: Entity) {
            if entity.name == "ellipsoid-contact" || ["left-arm", "right-arm", "left-foot", "right-foot"].contains(entity.name) { contacts.append(entity) }
            for child in entity.children { gatherContacts(child) }
        }
        gatherContacts(body)
        particles = ParticlePool(parent: anchor)
        view.scene.addAnchor(anchor)
        session.scene = self
        rebuild()
        subscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated { self?.update(Float(event.deltaTime)) }
        }
    }
    #if DEBUG
    func advanceForTesting(_ dt: Float) { update(dt) }
    var contactClearanceForTesting: Float {
        guard let e = session?.engine else { return 0 }
        let surface = TrackSurface(distance: Float(e.distance * e.profile.visualScale), variation: variation)
        var minimum: Float = .infinity
        for entity in contacts {
            let matrix = entity.transformMatrix(relativeTo: anchor)
            for latitude in 0...8 {
                let phi = Float(latitude) * .pi / 8
                for longitude in 0..<16 {
                    let theta = Float(longitude) * .pi / 8
                    let v = matrix * SIMD4<Float>(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta), 1)
                    minimum = min(minimum, v.y - surface.height(x: v.x, z: v.z))
                }
            }
        }
        return minimum
    }
    var entityIDsForTesting: Set<ObjectIdentifier> {
        var ids = Set<ObjectIdentifier>()
        func collect(_ entity: Entity) { ids.insert(ObjectIdentifier(entity)); for child in entity.children { collect(child) } }
        collect(anchor); return ids
    }
    var entityCountForTesting: Int {
        func count(_ entity: Entity) -> Int { 1 + entity.children.reduce(0) { $0 + count($1) } }
        return count(anchor)
    }
    #endif
    func focus() { if let view { view.window?.makeFirstResponder(view) } }
    func stop() { subscription?.cancel(); subscription = nil; audio.stop(); anchor.removeFromParent() }
    func rebuild() {
        guard beginRebuild() else { return }
        for index in 0..<24 { appendTile(index) }
        finishRebuild()
    }
    func rebuildWithProgress(_ progress: (Double, String) -> Void) async {
        guard beginRebuild() else { return }
        for index in 0..<24 {
            appendTile(index)
            progress(Double(index + 1) / 26, "Building the slope · \(index + 1) of 24 sections")
            // Yield a render opportunity between bounded main-actor RealityKit batches.
            try? await Task.sleep(for: .milliseconds(16))
        }
        progress(25.0 / 26, "Setting up the finish and lighting")
        try? await Task.sleep(for: .milliseconds(16))
        finishRebuild()
    }
    private func appendTile(_ index: Int) {
        let entity = tile(index); tiles.append(entity); world.addChild(entity)
    }
    private func beginRebuild() -> Bool {
        if builtLevel == session?.engine.level {
            particles.reset(); contactReady = false; firstTile = Int.min
            lastGateDistance = -.infinity; gateRevision = -1
            impact = 0; celebration = 0; update(0)
            return false
        }
        builtLevel = session?.engine.level ?? 1
        for child in Array(world.children) { child.removeFromParent() }
        tiles = []; zones = []; gateRevision = -1; gate = Entity(); finish = Entity()
        world.addChild(gate); world.addChild(finish)
        particles.reset()
        contactReady = false
        firstTile = Int.min
        lastGateDistance = -.infinity
        let colors: [UInt32] = [0x70D5D1, 0xE8B1E7, 0xFFE399]
        zoneMaterials = colors.map { color in
            var material = UnlitMaterial()
            material.color = .init(tint: NSColor(rgb: color), texture: .init(checkpointTexture))
            material.blending = .transparent(opacity: .init(floatLiteral: 0.65))
            return material
        }
        rejectedMaterial = UnlitMaterial(color: NSColor(rgb: 0xF57991, alpha: 0.35))
        for i in 0..<3 {
            let zone = ModelEntity(mesh: zoneMeshes[i], materials: [zoneMaterials[i]])
            gate.addChild(zone); zones.append(zone)
        }
        // Exactly one periodic set. Tiles are repositioned, never generated during gameplay.
        return true
    }
    private func finishRebuild() {
        view?.environment.background = .color(NSColor(rgb: theme.sky))
        let banner = Geometry.box([11.4, 0.8, 0.35], theme.accent, at: [0, 5.2, 0])
        finish.addChild(banner)
        let text = Geometry.text("WELL DONE!", height: 0.48, color: 0xFFFFFF)
        text.position.y = 5.03; text.position.z = 0.22; finish.addChild(text)
        for x: Float in [-5.4, 5.4] { finish.addChild(Geometry.box([0.28, 5, 0.28], theme.rail, at: [x, 2.7, 0])) }
        for i in 0..<12 { for j in 0..<2 {
            finish.addChild(Geometry.box([0.92, 0.04, 0.9], (i + j) % 2 == 0 ? 0xFFFFFF : 0x5C547B, at: [Float(i) * 0.92 - 5.06, Geometry.floorHeight(Float(i) * 0.92 - 5.06) + 0.08 + Float(j) * 0.2, Float(j) * 0.9], radius: 0))
        }}
        impact = 0; celebration = 0; update(0)
    }
    private func tile(_ index: Int) -> Entity {
        let root = Entity()
        let start = Float(index) * 12
        let trackMesh = (try? Geometry.track(start: start, variation: variation)) ?? .generatePlane(width: 12, depth: 12)
        let ribbonMesh = (try? Geometry.track(width: 9.8, lift: 0.025, start: start, variation: variation)) ?? trackMesh
        let floor = ModelEntity(mesh: trackMesh, materials: [Geometry.material(theme.track, roughness: 0.4)])
        root.addChild(floor)
        let iceColor: UInt32 = theme.motif == 2 ? 0xA5ACE7 : 0xCDC6F2
        let slide = ModelEntity(mesh: ribbonMesh, materials: [Geometry.material(iceColor, roughness: 0.16)])
        root.addChild(slide)
        for side: Float in [-1, 1] {
            for segment in 0..<4 {
                let d0 = Float(segment) * 3, d1 = d0 + 3
                let a = point(start + d0) - point(start) + SIMD3<Float>(side * 5.95, 2.12, 0)
                let b = point(start + d1) - point(start) + SIMD3<Float>(side * 5.95, 2.12, 0)
                let rail = Geometry.box([0.34, 0.34, simd_distance(a, b) + 0.16], theme.rail, at: (a + b) / 2, radius: 0.16)
                rail.orientation = simd_quatf(from: [0, 0, 1], to: simd_normalize(b - a)); root.addChild(rail)
            }
            for d: Float in [2, 6, 10] {
                let center = point(start + d) - point(start)
                let dash = Geometry.box([0.055, 0.02, 1.1], 0xFFFFFF, at: center + SIMD3<Float>(side * 1.65, Geometry.floorHeight(1.65) + 0.06, 0), radius: 0.01)
                dash.orientation = simd_quatf(from: [0, 0, -1], to: simd_normalize(point(start + d + 0.1) - point(start + d))); root.addChild(dash)
            }
            let n = Float(abs(index * 17 + Int(side) * 7) % 9)
            let island = Entity(); island.position = [side * (11 + n), -1.5 + n * 0.15, -6]
            island.addChild(Geometry.ball([4.5, 1.1, 3.3], theme.island))
            island.addChild(Geometry.ball([4.6, 0.32, 3.4], theme.track, at: [0, 0.75, 0]))
            if theme.motif == 2 {
                for k in 0..<3 {
                    let crystal = Geometry.box([0.9, 3 + Float(k), 0.9], k % 2 == 0 ? theme.accent : theme.rail, at: [Float(k) - 1, 2, 0], radius: 0.1)
                    crystal.orientation = simd_quatf(angle: Float(k - 1) * 0.25, axis: [0, 0, 1]); island.addChild(crystal)
                }
            } else if theme.motif == 1 {
                island.addChild(Geometry.box([0.35, 3.5, 0.35], 0xEAC28C, at: [0, 2.3, 0]))
                for k in 0..<5 {
                    let leaf = Geometry.ball([2, 0.2, 0.5], 0x62C6AC, at: [0, 4, 0])
                    leaf.orientation = simd_quatf(angle: Float(k) * 1.256, axis: [0, 1, 0]); island.addChild(leaf)
                }
            } else {
                island.addChild(Geometry.box([0.15, 3, 0.15], 0xFFF5E9, at: [0, 2, 0]))
                let sweet = Geometry.ball([1.25, 1.25, 0.55], theme.accent, at: [0, 3.4, 0])
                sweet.addChild(Geometry.ball([0.65, 0.65, 0.10], theme.track, at: [0, 0, 0.53])); island.addChild(sweet)
            }
            if index % 2 == 0 { root.addChild(island) }
            let cloud = Entity(); cloud.position = [side * (24 + n * 2), 5 + n * 0.9, -4 - n]
            for k in 0..<3 { cloud.addChild(Geometry.ball([2.6, 1.2 + Float(k % 2), 1.6], 0xF8F4FF, at: [Float(k) * 2 - 2, 0, 0])) }
            if (index + Int(side)) % 3 == 0 { root.addChild(cloud) }
            if (index + Int(side)) % 5 == 0 {
                let balloon = Entity(); balloon.position = [side * (15 + n), 12 + n, -6]
                balloon.addChild(Geometry.ball([2, 2.6, 2], theme.accent))
                balloon.addChild(Geometry.ball([0.7, 2.65, 2.04], theme.track))
                balloon.addChild(Geometry.box([0.8, 0.55, 0.8], theme.island, at: [0, -3.5, 0]))
                for x: Float in [-0.35, 0.35] { balloon.addChild(Geometry.box([0.035, 1.5, 0.035], 0xFFF5DD, at: [x, -2.8, 0])) }
                root.addChild(balloon)
            }
        }
        for side: Float in [-1, 1] {
            let marker = Geometry.box([0.13, 0.06, 2.1], theme.accent, at: point(start + 4) - point(start) + SIMD3<Float>(side * 4.6, Geometry.floorHeight(4.6) + 0.1, 0), radius: 0.03)
            marker.model?.materials = [UnlitMaterial(color: NSColor(rgb: theme.accent))]
            marker.orientation = simd_quatf(from: [0, 0, -1], to: simd_normalize(point(start + 4.1) - point(start + 4)))
            root.addChild(marker)
            for k in 0..<3 {
                let mote = Geometry.ball([0.045, 0.045, 0.045], 0xFFF1AF, at: [side * (4.3 + Float(k) * 0.24), 1.6 + Float(k) * 0.4, -Float(k) * 3])
                mote.model?.materials = [UnlitMaterial(color: NSColor(rgb: 0xFFF1AF))]; root.addChild(mote)
            }
        }
        // Directional chevrons give the surface a sense of motion.
        if index % 2 == 0 {
            for side: Float in [-1, 1] {
                let arrow = Geometry.box([0.1, 0.025, 0.8], 0xFFFFFF, at: point(start + 6) - point(start) + SIMD3<Float>(side * 0.24, 0.09, 0), radius: 0.02)
                arrow.orientation = simd_quatf(angle: -side * 0.6, axis: [0, 1, 0]); root.addChild(arrow)
            }
        }
        StaticBatch.bake(root)
        return root
    }
    private func refreshGate() {
        guard let e = session?.engine, e.eventSerial != gateRevision else { return }
        gateRevision = e.eventSerial
        for lane in 0..<3 { zones[lane].model?.materials = [e.challenge.rejectedLanes.contains(lane) ? rejectedMaterial : zoneMaterials[lane]] }
    }
    private func update(_ rawDelta: Float) {
        guard let session else { return }
        if session.isLoading && rawDelta > 0 { return }
        if session.engine.isPaused { audio.update(enabled: session.soundEnabled, sliding: false, speed: 6); return }
        let dt = min(0.1, max(0, rawDelta))
        session.tick(Double(dt))
        let e = session.engine
        let active = !e.isPaused && ![.ready, .won, .lost].contains(e.phase)
        if !e.isPaused { clock += dt }
        let scale = Float(e.profile.visualScale)
        let d = Float(e.distance) * scale
        let first = Int(floor(d / 12)) - 2
        let last = min(first + 13, Int(ceil(e.finishDistance * e.profile.visualScale / 12)) + 2)
        world.position = -point(d)
        if first != firstTile {
            firstTile = first
            let firstSlot = ((first % 24) + 24) % 24
            for slot in tiles.indices {
                let index = first + (slot - firstSlot + 24) % 24
                let visible = index <= last
                if tiles[slot].isEnabled != visible { tiles[slot].isEnabled = visible }
                if visible { tiles[slot].position = point(Float(index) * 12) }
            }
        }
        refreshGate()
        let gateDistance = Float(e.gateDistance) * scale
        if gateDistance != lastGateDistance { gate.position = point(gateDistance); lastGateDistance = gateDistance }
        gate.isEnabled = e.phase != .finishing && e.phase != .won
        finish.position = point(Float(e.finishDistance) * scale)
        let x = Float(e.x), lean = Float(e.targetX - e.x)
        let surface = TrackSurface(distance: d, variation: variation)
        let targetOrientation = surface.orientation(x: x, steering: max(-0.25, min(0.25, lean * 0.10)))
        runner.orientation = contactReady ? simd_slerp(runner.orientation, targetOrientation, 1 - exp(-18 * dt)) : targetOrientation
        runner.position.x = x
        runner.position.z = 0
        if e.phase == .lost {
            body.orientation = simd_quatf(angle: 1.65, axis: [0, 0, 1]) * simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]) * simd_quatf(angle: .pi, axis: [0, 1, 0])
        } else {
            body.orientation = simd_quatf(angle: -.pi / 2 + (e.phase == .rebound && !session.reducedMotion ? sin(clock * 18) * impact * 0.06 : 0), axis: [1, 0, 0]) * simd_quatf(angle: .pi, axis: [0, 1, 0])
        }
        body.scale = [1 + impact * 0.15, 1 - impact * 0.18, 1]
        let motion: Float = session.reducedMotion ? 0 : 1
        for (index, side): (Int, Float) in [(0, -1), (1, 1)] {
            limbs[index]?.orientation = simd_quatf(angle: side * (1.13 + sin(clock * 8 + side) * 0.13 * motion), axis: [0, 0, 1])
        }
        for (index, side): (Int, Float) in [(2, -1), (3, 1)] {
            limbs[index]?.position.z = 0.10 - (1 + sin(clock * 9 + side * 1.5)) * 0.035 * motion
        }
        // Resolve the height after limb animation, so feet cannot be animated through the mesh.
        var correction: Float = -.infinity
        for contact in contacts {
            let matrix = contact.transformMatrix(relativeTo: anchor)
            let center = SIMD3<Float>(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
            let normal = surface.normal(x: center.x, z: center.z)
            let support = TrackSurface.support(transform: matrix, normal: normal)
            correction = max(correction, surface.height(x: support.x, z: support.z) + 0.018 - support.y)
        }
        if correction.isFinite {
            // Immediate collision correction upward; damp downward settling within a 2 cm envelope.
            let settled = correction >= 0 || !contactReady ? correction : min(correction + 0.02, correction * (1 - exp(-24 * dt)))
            runner.position.y += settled
        }
        contactReady = true
        boostLight.position = [x, Geometry.floorHeight(x) + 0.9, 0.6]
        boostLight.light.intensity = 160 + Float(e.boost) * 250 + celebration * 650
        scarf.orientation = simd_quatf(angle: sin(clock * 12) * 0.2, axis: [1, 0, 0])
        contactShadow?.orientation = surface.orientation(x: x, steering: 0)
        contactShadow?.position = [x, surface.height(x: x, z: 0) + 0.012, 0]
        if !e.isPaused { impact = max(0, impact - dt * 1.8); celebration = max(0, celebration - dt) }
        let shake: Float = session.reducedMotion ? 0 : sin(clock * 65) * impact * 0.1
        let fov: Float = session.reducedMotion ? 54 : 56 + Float(e.boost) * 7 + min(1, celebration) * 1.2
        camera.camera.fieldOfViewInDegrees = fov
        camera.look(at: [x * 0.13, -2.0, -15], from: [x * 0.15 + shake, 6.2, 10.4], relativeTo: nil)
        if !e.isPaused { particles.update(dt) }
        if active && e.phase != .rebound && !session.reducedMotion {
            trailTime += dt
            if trailTime > 0.035 { trailTime = 0; trail(x: x, speed: Float(e.speed) * scale, streak: e.streak) }
        }
        projectionTime += dt
        if projectionTime >= 1.0 / 30 || rawDelta == 0 {
            projectionTime = 0
            if let view {
                session.projection.anchors = (0..<3).map { lane in
                    let gx = Float(GameEngine.laneCenters[lane])
                    guard let projected = view.project(world.position + gate.position + SIMD3<Float>(gx, Geometry.floorHeight(gx) + 3.0, 0)) else { return .zero }
                    return CGPoint(x: projected.x, y: view.bounds.height - projected.y)
                }
            }
        }
        audio.update(enabled: session.soundEnabled, sliding: active, speed: 6 + Float(e.boost) * 7)
    }
    func event(_ event: GameEvent?) {
        guard let event, let session else { return }
        switch event {
        case .correct(_, let healed):
            celebration = 1.0
            burst(count: session.reducedMotion ? 10 : min(64, 28 + session.engine.streak * 4))
            audio.play(healed ? "heal" : "correct", enabled: session.soundEnabled)
        case .wrong, .missed:
            impact = 1; burst(count: 10); audio.play("bump", enabled: session.soundEnabled)
        case .died:
            impact = 1; audio.play("bump", enabled: session.soundEnabled)
        case .completed:
            celebration = 4; burst(count: session.reducedMotion ? 16 : 64); audio.play("finish", enabled: session.soundEnabled)
        }
    }
    private func burst(count: Int) {
        guard let e = session?.engine else { return }
        let origin = SIMD3<Float>(Float(e.x), Geometry.floorHeight(Float(e.x)) + 0.8, -0.5)
        for _ in 0..<count {
            particles.emit(at: origin, velocity: [Float.random(in: -4...4), Float.random(in: 2...6), Float.random(in: -4...3)], scale: [0.11, 0.05, 0.20], life: Float.random(in: 0.7...1.3))
        }
    }
    private func trail(x: Float, speed: Float, streak: Int) {
        for side: Float in [-1, 1] {
            particles.emit(at: [x + side * 0.35, TrackSurface(distance: Float(session?.engine.distance ?? 0) * Float(session?.engine.profile.visualScale ?? 1), variation: variation).height(x: x + side * 0.35, z: 0.5) + 0.04, 0.5], velocity: [side * 0.2, 0.2, speed * 0.8], scale: [0.065, 0.018, streak > 2 ? 0.8 : 0.4], life: 0.4)
        }
    }
}
