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
        let plate: ModelEntity
        let blob: ModelEntity?
        var model: Entity?
        var placement: Placement?
        var lit = false

        init(item: DecorItem, plate: ModelEntity, blob: ModelEntity?) {
            self.item = item
            self.plate = plate
            self.blob = blob
        }
    }

    /// A model sized and centred once: its bottom middle at the origin for the floor, its middle for a wall.
    private struct Template {
        let entity: Entity
        let extents: SIMD3<Float>
    }

    private var nodes: [String: Node] = [:]
    private var templates: [String: Template] = [:]
    private var loading: Set<String> = []
    private var decor = RoomDecor()
    private var receiver: ImageBasedLightReceiverComponent?

    static let floorY: Float = 0.014
    private static let wallInset: Float = 0.49

    private static let unitBox = MeshResource.generateBox(size: 1, cornerRadius: 0.1)
    private static let unitPlane = MeshResource.generatePlane(width: 1, depth: 1)
    private static let fits = UnlitMaterial(color: UIColor(hex: 0x6BD08A, alpha: 0.55))
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

    init() {
        root.name = "decor"
    }

    // MARK: Drawing

    /// Brings the entities to `decor`. Cheap when nothing changed.
    func apply(_ decor: RoomDecor, receiver: ImageBasedLightReceiverComponent?) {
        let lightChanged = receiver != nil && self.receiver == nil
        self.decor = decor
        if receiver != nil { self.receiver = receiver }

        let placed = Set(decor.layout.placements.map(\.item))
        for (id, node) in nodes where !placed.contains(id) {
            node.holder.removeFromParent()
            nodes[id] = nil
        }
        for placement in decor.layout.placements {
            guard let item = DecorItem.item(shopID: placement.item) else { continue }
            let node = nodes[placement.item] ?? makeNode(for: item)
            if node.placement != placement || lightChanged || node.model == nil { place(node, at: placement) }
            showPlate(on: node)
        }
    }

    private func makeNode(for item: DecorItem) -> Node {
        let plate = ModelEntity(mesh: Self.unitBox, materials: [Self.fits])
        plate.isEnabled = false
        let blob = item.mount == .floor && !item.isFlat
            ? ModelEntity(mesh: Self.unitPlane, materials: [Self.blobMaterial]) : nil
        let node = Node(item: item, plate: plate, blob: blob)
        node.holder.name = "decor.\(item.id)"
        node.holder.addChild(plate)
        if let blob {
            blob.position = [0, 0.001, 0]
            node.holder.addChild(blob)
        }
        root.addChild(node.holder)
        nodes[item.id] = node
        load(item)
        return node
    }

    private func place(_ node: Node, at placement: Placement) {
        node.placement = placement
        let item = node.item
        let turns = Float(placement.quarterTurns) * .pi / 2
        switch placement.surface {
        case .floor:
            node.holder.position = [Float(DecorGrid.metres(placement.u)), Self.floorY, Float(DecorGrid.metres(placement.v))]
            node.holder.orientation = .y(turns)
        case .backWall:
            node.holder.position = [Float(DecorGrid.metres(placement.u)), Float(DecorGrid.wallHeight), -Self.wallInset]
            node.holder.orientation = .identity
        case .leftWall:
            node.holder.position = [-Self.wallInset, Float(DecorGrid.wallHeight), Float(DecorGrid.metres(placement.u))]
            node.holder.orientation = .y(.pi / 2)
        }
        if let template = templates[item.assetName] { attachModel(to: node, from: template) }
        if let blob = node.blob {
            let size = Float(max(item.width, item.depth)) * 1.15
            blob.scale = [size, 1, size]
        }
    }

    private func attachModel(to node: Node, from template: Template) {
        if node.model == nil {
            let model = template.entity.clone(recursive: true)
            node.holder.addChild(model)
            node.model = model
            node.lit = false
        }
        guard !node.lit, let receiver else { return }
        node.model?.forEachDescendant { $0.components.set(receiver) }
        node.lit = true
    }

    private func showPlate(on node: Node) {
        guard case .arranging(let selected, let fits) = decor.mode, selected == node.item.id,
            let placement = node.placement
        else {
            node.plate.isEnabled = false
            return
        }
        node.plate.isEnabled = true
        node.plate.model?.materials = [fits ? Self.fits : Self.misfits]
        let turned = placement.quarterTurns % 2 == 1
        let width = Float(turned ? node.item.depth : node.item.width) + 0.02
        let depth = Float(turned ? node.item.width : node.item.depth) + 0.02
        switch placement.surface {
        case .floor:
            node.plate.scale = [width, 0.004, depth]
            node.plate.position = [0, 0.002, 0]
        case .backWall, .leftWall:
            let height = Float(node.item.fit == .height ? node.item.size : node.item.width) + 0.02
            node.plate.scale = [width, height, 0.006]
            node.plate.position = [0, 0, 0.002]
        }
    }

    // MARK: Models

    private func load(_ item: DecorItem) {
        guard templates[item.assetName] == nil, loading.insert(item.assetName).inserted else { return }
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
        let entry = Template(entity: template, extents: bounds.extents * scale)
        templates[item.assetName] = entry
        for node in nodes.values where node.item.assetName == item.assetName && node.model == nil {
            attachModel(to: node, from: entry)
        }
    }

    // MARK: Touch

    /// The piece standing under the floor point `point`, in the pivot's space, nearest the top first.
    func floorPiece(at point: SIMD3<Float>) -> String? {
        let layout = decor.layout
        let solid = layout.placements.reversed().filter { $0.surface == .floor && !isFlat($0.item) }
        let flat = layout.placements.reversed().filter { $0.surface == .floor && isFlat($0.item) }
        return (solid + flat).first { placement in
            guard let item = DecorItem.item(shopID: placement.item) else { return false }
            let turned = placement.quarterTurns % 2 == 1
            let halfX = (turned ? item.depth : item.width) / 2 + 0.02
            let halfZ = (turned ? item.width : item.depth) / 2 + 0.02
            return abs(Double(point.x) - DecorGrid.metres(placement.u)) <= halfX
                && abs(Double(point.z) - DecorGrid.metres(placement.v)) <= halfZ
        }?.item
    }

    /// The wall piece under `point` on `surface`, in the pivot's space.
    func wallPiece(at point: SIMD3<Float>, on surface: Placement.Surface) -> String? {
        let along = Double(surface == .backWall ? point.x : point.z)
        return decor.layout.placements.reversed().first { placement in
            guard placement.surface == surface, let item = DecorItem.item(shopID: placement.item) else { return false }
            let height = item.fit == .height ? item.size : item.width
            return abs(along - DecorGrid.metres(placement.u)) <= item.width / 2 + 0.02
                && abs(Double(point.y) - DecorGrid.wallHeight) <= height / 2 + 0.02
        }?.item
    }

    private func isFlat(_ id: String) -> Bool { DecorItem.item(shopID: id)?.isFlat == true }
}
