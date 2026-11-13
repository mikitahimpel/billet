import DecorInterface
import RealityKit
import RoomInterface
import UIKit

/// The pieces the player has stood in the room, drawn from the shop's models. Each piece is one holder
/// entity around a clone of a shared model, so the meshes and materials exist once however many stand.
/// No piece has a light, a shadow or an animation of its own: a flat blob under each one stands for its
/// shadow, and a plate under the chosen one shows where it fits.
@MainActor
final class DecorStage {
    let root = Entity()

    private final class Node {
        let item: DecorItem
        let holder = Entity()
        /// Made when the piece is first chosen, so a piece nobody chose has none to count.
        var plate: ModelEntity?
        let blob: ModelEntity?
        var model: Entity?
        var placement: Placement?
        var lit = false

        init(item: DecorItem, blob: ModelEntity?) {
            self.item = item
            self.blob = blob
        }
    }

    /// A model sized and centred once: its bottom middle at the origin for the floor, its middle for a wall.
    private struct Template {
        let entity: Entity
        let extents: SIMD3<Float>
        /// Height of its top above the holder's origin.
        let top: Float
    }

    /// An outline where the dragged piece stood, so the player sees where it came from and where a bad drop returns it.
    private let ghost = ModelEntity(mesh: DecorStage.unitBox, materials: [DecorStage.ghostMaterial])
    private var nodes: [String: Node] = [:]
    private var templates: [String: Template] = [:]
    private var loading: Set<String> = []
    private var sharedMaterials: [String: any Material] = [:]
    private var decor = RoomDecor()
    private var receiver: ImageBasedLightReceiverComponent?
    /// Told once, when every piece of the room's own furniture that stands has its model in.
    var onBaseReady: (() -> Void)?
    private var baseReadyTold = false

    static let floorY: Float = 0.014
    private static let wallInset: Float = 0.49

    private static let unitBox = MeshResource.generateBox(size: 1, cornerRadius: 0.1)
    private static let unitPlane = MeshResource.generatePlane(width: 1, depth: 1)
    private static let fits = UnlitMaterial(color: UIColor(hex: 0x6BD08A, alpha: 0.55))
    private static let ghostMaterial = UnlitMaterial(color: UIColor(white: 1, alpha: 0.3))
    private static let misfits = UnlitMaterial(color: UIColor(hex: 0xE0605A, alpha: 0.6))
    private static let blobMaterial: UnlitMaterial = {
        var material = UnlitMaterial(color: UIColor(white: 0, alpha: 0.28))
        if let image = blobImage, let texture = try? TextureResource(image: image, options: .init(semantic: .color)) {
            material.color = .init(tint: .white, texture: .init(texture))
        }
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        return material
    }()

    /// A soft dark disc, drawn once: the contact shadow of every piece.
    private static var blobImage: CGImage? {
        let side = 64
        let space = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let colors = [UIColor(white: 0, alpha: 0.55).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return nil }
        let middle = CGPoint(x: side / 2, y: side / 2)
        context.drawRadialGradient(
            gradient, startCenter: middle, startRadius: 0, endCenter: middle, endRadius: CGFloat(side) / 2,
            options: [])
        return context.makeImage()
    }

    /// The room this stage draws, and how a piece of its own furniture is made when its model is not a file: the
    /// Bedroom's is built in code, one entity tree per piece, so a piece can be picked up and put down.
    private let space: DecorSpace
    private let room: DecorRoom
    private let build: (@MainActor (DecorItem) -> Entity?)?

    init(space: DecorSpace = .living, build: (@MainActor (DecorItem) -> Entity?)? = nil) {
        self.space = space
        room = space == .living ? .home : .bedroom
        self.build = build
        root.name = "decor"
        ghost.isEnabled = false
        root.addChild(ghost)
    }

    // MARK: Drawing

    /// Brings the entities to `decor`. Cheap when nothing changed.
    func apply(_ decor: RoomDecor, receiver: ImageBasedLightReceiverComponent?) {
        let lightChanged = receiver != nil && self.receiver == nil
        self.decor = decor
        if receiver != nil { self.receiver = receiver }

        let drawn = decor.layout.allPlacements(in: room)
        let placed = Set(drawn.map(\.item))
        for (id, node) in nodes where !placed.contains(id) {
            node.holder.removeFromParent()
            nodes[id] = nil
        }
        for placement in drawn {
            guard let item = DecorItem.item(shopID: placement.item) else { continue }
            let node = nodes[placement.item] ?? makeNode(for: item)
            if node.placement != placement || lightChanged || node.model == nil { place(node, at: placement) }
            showPlate(on: node)
        }
        showGhost()
        tellBaseReady()
    }

    private func showGhost() {
        guard case .arranging(_, _, let origin?) = decor.mode, origin.surface == .floor, origin.space == space,
            let item = DecorItem.item(shopID: origin.item)
        else {
            ghost.isEnabled = false
            return
        }
        let (width, depth) = DecorLayout.footprint(of: item, eighthTurns: origin.eighthTurns)
        ghost.scale = [Float(width), 0.003, Float(depth)]
        ghost.position = [Float(DecorGrid.metres(origin.u)), Self.floorY + 0.0015, Float(DecorGrid.metres(origin.v))]
        ghost.isEnabled = true
    }

    private func makeNode(for item: DecorItem) -> Node {
        // A built piece too small to show a shadow of its own has none, so it costs no draw.
        let small = build != nil && max(item.width, item.depth) < 0.15
        let blob = item.mount == .floor && !item.isFlat && !small
            ? ModelEntity(mesh: Self.unitPlane, materials: [Self.blobMaterial]) : nil
        let node = Node(item: item, blob: blob)
        node.holder.name = "decor.\(item.id)"
        if let blob {
            blob.position = [0, 0.001, 0]
            node.holder.addChild(blob)
        }
        root.addChild(node.holder)
        nodes[item.id] = node
        load(item)
        return node
    }

    private func tellBaseReady() {
        guard !baseReadyTold, let onBaseReady else { return }
        let base = nodes.values.filter(\.item.isBase)
        guard !base.isEmpty, base.allSatisfy({ $0.model != nil }) else { return }
        baseReadyTold = true
        onBaseReady()
    }

    private func place(_ node: Node, at placement: Placement) {
        let before = node.placement
        node.placement = placement
        let item = node.item
        let turns = Float(placement.angle)
        let position: SIMD3<Float>
        let orientation: simd_quatf
        switch placement.surface {
        case .floor:
            position = [Float(DecorGrid.metres(placement.u)), Self.floorY, Float(DecorGrid.metres(placement.v))]
            orientation = .y(turns)
        case .backWall:
            position = [Float(DecorGrid.metres(placement.u)), Float(DecorGrid.wallHeight), -Self.wallInset]
            orientation = .identity
        case .leftWall:
            position = [-Self.wallInset, Float(DecorGrid.wallHeight), Float(DecorGrid.metres(placement.u))]
            orientation = .y(.pi / 2)
        }
        // A turn or a jump of several cells (a slide, a swap, a piece nudged aside) glides; a drag follows the finger.
        if let before, node.model != nil,
            before.eighthTurns != placement.eighthTurns || max(abs(before.u - placement.u), abs(before.v - placement.v)) > 2
        {
            node.holder.move(
                to: Transform(scale: .one, rotation: orientation, translation: position), relativeTo: node.holder.parent,
                duration: 0.2, timingFunction: .easeInOut)
        } else {
            node.holder.position = position
            node.holder.orientation = orientation
        }
        if let template = templates[key(item)] { attachModel(to: node, from: template) }
        if let blob = node.blob {
            let size = Float(max(item.width, item.depth)) * 1.15
            // A built piece's shadow follows its own footprint, which the holder turns with it.
            blob.scale = build != nil ? [Float(item.width) * 1.2, 1, Float(item.depth) * 1.2] : [size, 1, size]
        }
    }

    private func attachModel(to node: Node, from template: Template) {
        if node.model == nil {
            let model = template.entity.clone(recursive: true)
            node.holder.addChild(model)
            node.model = model
            node.lit = false
            if node.item.isBase, build == nil { dress(model, casting: !node.item.isFlat) }
            onAttach?(node.item.id, model)
        }
        guard !node.lit, let receiver else { return }
        node.model?.forEachDescendant { $0.components.set(receiver) }
        node.lit = true
    }

    /// The room's own pieces keep the glow and the grounding shadow the furniture model had; a rug lies flat, so it casts none.
    private func dress(_ model: Entity, casting: Bool) {
        model.forEachDescendant { entity in
            if casting { entity.components.set(GroundingShadowComponent(castsShadow: true)) }
            if !RoomPieces.glows.keys.contains(entity.name), var mesh = entity.components[ModelComponent.self] {
                mesh.materials = mesh.materials.map { shared($0) }
                entity.components.set(mesh)
            }
            if let glow = RoomPieces.glows[entity.name], var mesh = entity.components[ModelComponent.self] {
                mesh.materials = mesh.materials.map { _ in Clay.glow(glow.tone, intensity: glow.intensity) }
                entity.components.set(mesh)
            }
        }
    }

    /// One instance per named colour for every piece: the room's pieces repeat their clay colours, and each
    /// import would otherwise make its own copy of each.
    private func shared(_ material: any Material) -> any Material {
        guard let name = material.name, !name.isEmpty else { return material }
        if let known = sharedMaterials[name] { return known }
        sharedMaterials[name] = material
        return material
    }

    private func showPlate(on node: Node) {
        guard case .arranging(let selected, let fits, _) = decor.mode, selected == node.item.id,
            let placement = node.placement
        else {
            node.plate?.isEnabled = false
            return
        }
        let plate: ModelEntity
        if let made = node.plate {
            plate = made
        } else {
            plate = ModelEntity(mesh: Self.unitBox, materials: [Self.fits])
            node.holder.addChild(plate)
            node.plate = plate
        }
        plate.isEnabled = true
        plate.model?.materials = [fits ? Self.fits : Self.misfits]
        switch placement.surface {
        case .floor:
            let (width, depth) = DecorLayout.footprint(of: node.item, eighthTurns: placement.eighthTurns)
            plate.scale = [Float(width) + 0.02, 0.004, Float(depth) + 0.02]
            plate.position = [0, 0.002, 0]
            plate.orientation = .y(-Float(placement.angle))
        case .backWall, .leftWall:
            let height = Float(node.item.fit == .height ? node.item.size : node.item.width) + 0.02
            plate.scale = [Float(node.item.width) + 0.02, height, 0.006]
            plate.position = [0, 0, 0.002]
        }
    }

    // MARK: Models

    /// What a piece's model is kept under: the room's own furniture built in code has no asset of its own.
    private func key(_ item: DecorItem) -> String { build != nil && item.isBase ? item.id : item.assetName }

    /// Told when a piece's model is attached, for a scene that keeps a handle on one of its parts.
    var onAttach: ((String, Entity) -> Void)?

    private func load(_ item: DecorItem) {
        if item.isBase, let build, let model = build(item) {
            let bounds = model.visualBounds(relativeTo: nil)
            let template = Template(entity: model, extents: bounds.extents, top: bounds.max.y)
            templates[key(item)] = template
            for node in nodes.values where key(node.item) == key(item) && node.model == nil {
                attachModel(to: node, from: template)
            }
            tellBaseReady()
            return
        }
        guard templates[key(item)] == nil, loading.insert(item.assetName).inserted else { return }
        Task { [weak self] in
            let model: Entity
            do {
                model = try await Entity(named: item.assetName, in: .main)
            } catch {
                print("\(item.assetName) failed to load: \(error)")
                return
            }
            self?.loaded(model, for: item)
        }
    }

    private func loaded(_ model: Entity, for item: DecorItem) {
        let bounds = model.visualBounds(relativeTo: nil)
        if item.isBase {
            let template = Entity()
            template.addChild(model)
            let entry = Template(entity: template, extents: bounds.extents, top: bounds.max.y)
            templates[key(item)] = entry
            for node in nodes.values where key(node.item) == key(item) && node.model == nil {
                attachModel(to: node, from: entry)
            }
            tellBaseReady()
            return
        }
        let measure = item.fit == .width ? bounds.extents.x : bounds.extents.y
        guard measure > 0 else { return }
        let scale = Float(item.size) / measure
        let template = Entity()
        template.addChild(model)
        model.scale = .init(repeating: scale)
        switch item.mount {
        case .floor:
            model.position = [-bounds.center.x * scale, -bounds.min.y * scale, -bounds.center.z * scale]
        case .wall:
            model.position = [-bounds.center.x * scale, -bounds.center.y * scale, -bounds.min.z * scale]
        }
        let entry = Template(entity: template, extents: bounds.extents * scale, top: bounds.extents.y * scale)
        templates[key(item)] = entry
        for node in nodes.values where key(node.item) == key(item) && node.model == nil {
            attachModel(to: node, from: entry)
        }
    }

    // MARK: Touch

    /// The piece standing under the finger, nearest the top first. `hit` gives the floor point under the finger for a
    /// horizontal plane that high above the floor, in the pivot's space: a tall piece is also met by its body, not
    /// only by its base.
    func floorPiece(hit: (Float) -> SIMD3<Float>?) -> String? {
        let layout = decor.layout
        let here = layout.allPlacements(in: room).reversed().filter { $0.surface == .floor }
        let solid = here.filter { !isFlat($0.item) }
        let flat = here.filter { isFlat($0.item) }
        return (solid + flat).first { placement in
            guard let item = DecorItem.item(shopID: placement.item) else { return false }
            let (width, depth) = DecorLayout.footprint(of: item, eighthTurns: placement.eighthTurns)
            let halfX = width / 2 + 0.02
            let halfZ = depth / 2 + 0.02
            let height = item.isFlat ? 0 : templates[key(item)]?.extents.y ?? 0
            return [0, 0.25, 0.5, 0.75, 1].contains { fraction in
                guard let point = hit(height * Float(fraction)) else { return false }
                return abs(Double(point.x) - DecorGrid.metres(placement.u)) <= halfX
                    && abs(Double(point.z) - DecorGrid.metres(placement.v)) <= halfZ
            }
        }?.item
    }

    /// The wall piece under `point` on `surface`, in the pivot's space.
    func wallPiece(at point: SIMD3<Float>, on surface: Placement.Surface) -> String? {
        let along = Double(surface == .backWall ? point.x : point.z)
        return decor.layout.allPlacements(in: room).reversed().first { placement in
            guard placement.surface == surface, let item = DecorItem.item(shopID: placement.item) else { return false }
            let height = item.fit == .height ? item.size : item.width
            return abs(along - DecorGrid.metres(placement.u)) <= item.width / 2 + 0.02
                && abs(Double(point.y) - DecorGrid.wallHeight) <= height / 2 + 0.02
        }?.item
    }

    /// The flat pieces standing on the floor, where each lies and how high its top is, in the pivot's space.
    func flatSurfaces() -> [FlatSurface] {
        nodes.values.compactMap { node in
            guard node.item.isFlat, let placement = node.placement, placement.surface == .floor,
                let template = templates[key(node.item)]
            else { return nil }
            return FlatSurface(
                x: DecorGrid.metres(placement.u), z: DecorGrid.metres(placement.v),
                halfWidth: Double(template.extents.x) / 2, halfDepth: Double(template.extents.z) / 2,
                yaw: placement.angle, top: Double(Self.floorY + template.top))
        }
    }

    private func isFlat(_ id: String) -> Bool { DecorItem.item(shopID: id)?.isFlat == true }
}
