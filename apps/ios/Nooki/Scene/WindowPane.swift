import CoreGraphics
import Foundation
import Metal
import Pet
import RealityKit
import UIKit
import WindowViews

/// The City room window's view, built in depth behind the glass: the sky, the four planes of the
/// chosen view, and the air and glass in front, each on its own quad a little further back than the
/// one in front of it. Turning the room slides the far planes against the near ones, which is the
/// parallax the old app's flat views faked. The layers sit in a world of their own, seen only
/// through a portal the size of the window, so their margins never show around the wall.
///
/// The layers are laid out so that from the room's home camera the view lines up with the glass as
/// the old room's did, its bottom on the sill. They are unlit and skip the room's tone mapping:
/// the painted colours reach the screen as painted.
final class WindowPane {
    /// How often the view's life is repainted.
    static let rate: Float = 12

    /// How far behind the glass each layer sits, in meters.
    static func depth(_ layer: PaneLayer) -> Float {
        switch layer {
        case .sky: 0.26
        case .far: 0.17
        case .middle: 0.1
        case .street: 0.05
        case .near: 0.018
        case .air: 0.002
        }
    }

    /// The pane: add it where the glass is, facing into the room (+Z).
    let entity = Entity()
    /// True once a painted view is showing, so the room's own fallback can stand down.
    private(set) var isShowing = false

    private let world = Entity()
    private let width: Float
    private let height: Float
    /// The home camera's direction from the glass, in the pane's space, as x and y per unit of z.
    private let slant: SIMD2<Float>
    private let painter = WindowLayerPainter()
    private var stills: [PaneLayer: (model: ModelEntity, texture: TextureResource)] = [:]
    private var lifeSlices: [PaneLayer: ModelEntity] = [:]
    private var lifeTexture: TextureResource?
    private var lifeShown: [PaneLayer] = []
    private let backdrop: ModelEntity
    private let flat: ModelEntity
    private var flatTexture: TextureResource?

    private var lifeAge: Float = .infinity
    private var choiceAge: Float = .infinity
    private var choice = WindowChoice.current
    private var weather = WindowChoice.weather

    /// A pane for a `width` × `height` window (meters) seen at home from `eye`, a direction from the
    /// glass toward the camera in the pane's space.
    init(width: Float, height: Float, eye: SIMD3<Float>) {
        self.width = width
        self.height = height
        slant = SIMD2(eye.x, eye.y) / max(eye.z, 0.05)

        world.components.set(WorldComponent())
        entity.addChild(world)
        let portal = ModelEntity(mesh: .generatePlane(width: width + 0.01, height: height + 0.01),
                                 materials: [PortalMaterial()])
        portal.components.set(PortalComponent(target: world))
        entity.addChild(portal)

        // Whatever the layers don't reach at a steep angle, in the sky's colour.
        backdrop = ModelEntity(mesh: .generatePlane(width: 12, height: 12), materials: [Self.colour(0.55, 0.62, 0.72)])
        backdrop.position = [0, 0, -Self.depth(.sky) - 0.05]
        backdrop.components.set(Self.order(-1))
        world.addChild(backdrop)

        flat = ModelEntity(mesh: .generatePlane(width: width, height: height), materials: [])
        flat.position = [0, 0, -0.001]
        flat.components.set(Self.order(20))
        flat.isEnabled = false
        world.addChild(flat)
    }

    /// Paints what is due this frame: a still layer when the look has changed or the sky is due,
    /// and the life a few times a second while the view moves. Returns false when there is no view
    /// to show, for the room's fallback.
    @discardableResult
    func tick(_ dt: Float, hour: Float) -> Bool {
        lifeAge += dt
        choiceAge += dt
        // Settings are read once a second rather than every frame.
        if choiceAge > 1 {
            choiceAge = 0
            choice = WindowChoice.current
            weather = WindowChoice.weather
        }
        let look = choice.look(hour: hour, weather: weather)
        if painter.prepare(look.view, hour: look.hour, weather: look.weather) {
            lifeAge = .infinity
            let c = painter.backdrop
            backdrop.model?.materials = [Self.colour(c.red, c.green, c.blue)]
        }
        if let still = painter.nextStill() { show(still) }
        if lifeAge >= 1 / Self.rate, painter.moves || lifeShown != painter.lifeLayers || lifeTexture == nil {
            lifeAge = 0
            if let atlas = painter.life() { showLife(atlas) }
        }
        return isShowing
    }

    /// Shows `image` filling the window flat, in place of the layers: the room's fallback picture.
    func showFlat(_ image: CGImage) {
        if let flatTexture {
            try? flatTexture.replace(withImage: image, options: .init(semantic: .color))
        } else if let texture = try? TextureResource(image: image, options: .init(semantic: .color)) {
            flatTexture = texture
            flat.model?.materials = [Self.material(texture, transparent: false)]
        }
        flat.isEnabled = !isShowing
    }

    // MARK: - Layers

    private func show(_ still: WindowLayerPainter.Still) {
        let options = TextureResource.CreateOptions(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
        if let existing = stills[still.layer] {
            try? existing.texture.replace(withImage: still.image, options: options)
        } else if let texture = try? TextureResource(image: still.image, options: options) {
            let area = WindowLayerPainter.stillArea
            let model = ModelEntity(
                mesh: .generatePlane(width: Float(area.width) * unit, height: Float(area.height) * unit),
                materials: [Self.material(texture, transparent: still.layer != .sky)])
            model.position = place(area, depth: Self.depth(still.layer))
            model.components.set(Self.order(still.layer.rawValue * 2))
            world.addChild(model)
            stills[still.layer] = (model, texture)
        }
        if still.layer == .near, !isShowing {
            isShowing = true
            flat.isEnabled = false
        }
    }

    private func showLife(_ atlas: CGImage) {
        let options = TextureResource.CreateOptions(semantic: .color, mipmapsMode: .none)
        let layers = painter.lifeLayers
        if let lifeTexture, layers == lifeShown, lifeTexture.width == atlas.width, lifeTexture.height == atlas.height {
            try? lifeTexture.replace(withImage: atlas, options: options)
            return
        }
        guard let texture = try? TextureResource(image: atlas, options: options) else { return }
        lifeTexture = texture
        lifeShown = layers
        for slice in lifeSlices.values { slice.removeFromParent() }
        lifeSlices = [:]
        let area = WindowLayerPainter.lifeArea
        for (index, layer) in layers.enumerated() {
            guard let mesh = Self.slice(width: Float(area.width) * unit, height: Float(area.height) * unit,
                                        index: index, of: layers.count) else { continue }
            let model = ModelEntity(mesh: mesh, materials: [Self.material(texture, transparent: true)])
            // Just in front of its plane, so its cars and lights sit on that plane's road and houses.
            model.position = place(area, depth: Self.depth(layer) - 0.0015)
            model.components.set(Self.order(layer.rawValue * 2 + 1))
            world.addChild(model)
            lifeSlices[layer] = model
        }
    }

    /// Meters per stage unit: the window is 100 units across.
    private var unit: Float { width / 100 }

    /// Where a layer covering `area` (stage units) sits at `depth` behind the glass. The stage's
    /// window has its bottom on the pane's bottom edge, and each layer is slid along the home
    /// camera's line of sight so that, from there, it lines up with the glass.
    private func place(_ area: CGRect, depth: Float) -> SIMD3<Float> {
        let top = WindowLayerPainter.windowHeight - height / unit
        let x = (Float(area.midX) - 50) * unit
        let y = height / 2 - (Float(area.midY) - top) * unit
        return [x - depth * slant.x, y - depth * slant.y, -depth]
    }

    // MARK: - Materials

    /// Layers in front draw after the ones behind them.
    private static func order(_ index: Int) -> ModelSortGroupComponent {
        ModelSortGroupComponent(group: sortGroup, order: Int32(index))
    }

    private static let sortGroup = ModelSortGroup(depthPass: nil)

    private static func material(_ texture: TextureResource, transparent: Bool) -> UnlitMaterial {
        var material = UnlitMaterial(color: .white, applyPostProcessToneMap: false)
        material.color = .init(tint: .white, texture: .init(texture, sampler: sampler))
        if transparent { material.blending = .transparent(opacity: .init(floatLiteral: 1)) }
        return material
    }

    private static func colour(_ red: Float, _ green: Float, _ blue: Float) -> UnlitMaterial {
        UnlitMaterial(color: UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1),
                      applyPostProcessToneMap: false)
    }

    /// Trilinear and anisotropic: the window is mostly seen at a slant, where plain mipmaps blur it.
    private static let sampler: MaterialParameters.Texture.Sampler = {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.maxAnisotropy = 8
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        return MaterialParameters.Texture.Sampler(descriptor)
    }()

    /// A quad showing slice `index` of `count`, stacked top to bottom in one texture.
    private static func slice(width: Float, height: Float, index: Int, of count: Int) -> MeshResource? {
        let top = 1 - Float(index) / Float(count)
        let bottom = 1 - Float(index + 1) / Float(count)
        var descriptor = MeshDescriptor(name: "windowLife")
        descriptor.positions = MeshBuffer([
            [-width / 2, -height / 2, 0], [width / 2, -height / 2, 0],
            [width / 2, height / 2, 0], [-width / 2, height / 2, 0],
        ])
        descriptor.normals = MeshBuffer(Array(repeating: SIMD3<Float>(0, 0, 1), count: 4))
        descriptor.textureCoordinates = MeshBuffer([[0, bottom], [1, bottom], [1, top], [0, top]])
        descriptor.primitives = .triangles([0, 1, 2, 0, 2, 3])
        return try? MeshResource.generate(from: [descriptor])
    }
}
