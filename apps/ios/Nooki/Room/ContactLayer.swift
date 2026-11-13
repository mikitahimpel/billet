#if DEBUG || LABS_YES
import DecorInterface
import RealityKit
import UIKit

/// The layout a baked contact-shadow layer was drawn for.
struct ContactGroup: Component {
    var layout: DecorLayout
}

/// The soft blobs under the room's pieces drawn once into one image, laid on the floor as one quad: one transparent
/// draw where there were one for every piece. The pieces' own blobs are switched off while it stands.
enum ContactLayer {
    private static let half: Float = 0.6
    private static let side = 512

    static func layout(in stage: Entity) -> DecorLayout? {
        stage.children.first { $0.name == RoomStats.blobLayerName }?.components[ContactGroup.self]?.layout
    }

    private static func blobs(in stage: Entity) -> [ModelEntity] {
        stage.children.filter { $0.name.hasPrefix("decor.") }.flatMap { holder in
            holder.children.compactMap { $0 as? ModelEntity }.filter { $0.model?.mesh.bounds.extents.y == 0 }
        }
    }

    static func remove(_ stage: Entity) {
        stage.children.filter { $0.name == RoomStats.blobLayerName }.forEach { $0.removeFromParent() }
        for blob in blobs(in: stage) { blob.isEnabled = true }
    }

    static func bake(_ stage: Entity, layout: DecorLayout) {
        remove(stage)
        let found = blobs(in: stage)
        let pixels = Float(side) / (2 * half)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let space = CGColorSpaceCreateDeviceRGB()
            let colors = [UIColor(white: 0, alpha: 0.55).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
            for blob in found {
                let at = blob.position(relativeTo: stage)
                let middle = CGPoint(x: CGFloat((at.x + half) * pixels), y: CGFloat((at.z + half) * pixels))
                let radius = CGFloat(blob.scale(relativeTo: stage).x / 2 * pixels)
                context.cgContext.drawRadialGradient(
                    gradient, startCenter: middle, startRadius: 0, endCenter: middle, endRadius: radius, options: [])
            }
        }
        guard let cgImage = image.cgImage,
            let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color))
        else { return }
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        let quad = ModelEntity(mesh: .generatePlane(width: 2 * half, depth: 2 * half), materials: [material])
        quad.name = RoomStats.blobLayerName
        quad.position = [0, DecorStage.floorY + 0.001, 0]
        quad.components.set(ContactGroup(layout: layout))
        stage.addChild(quad)
        for blob in found { blob.isEnabled = false }
    }
}
#endif
