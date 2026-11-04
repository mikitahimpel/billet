import Foundation
import RealityKit

/// Mochi's coat, picked in onboarding. Grey is Ilya's cat as he made it; every other coat is a recolour by billet-gpu
/// that differs from it only in each splat's colour (`f_dc_0...2`), so the app ships just those colours
/// (`Coats/<pose>-<coat>.fdc`, three little-endian floats per splat, in the PLY's order) and lays them over Ilya's
/// PLY when it loads. That rebuilds billet-gpu's coat PLY byte for byte (`CatCoatTests`). Where splats can't be drawn
/// the mesh cat wears the coat's colour texture instead (`Coats/<model>Color-<coat>.jpg`).
nonisolated enum CatCoat: String, CaseIterable, Sendable {
    case grey, ginger, cream, tuxedo, black, calico

    static let key = "catCoat"

    static func current(in defaults: UserDefaults = .standard) -> CatCoat {
        defaults.string(forKey: key).flatMap(CatCoat.init(rawValue:)) ?? .grey
    }

    var title: String {
        switch self {
        case .grey: "Grey tabby"
        case .ginger: "Ginger"
        case .cream: "Cream"
        case .tuxedo: "Tuxedo"
        case .black: "Black"
        case .calico: "Calico"
        }
    }

    /// The card in the onboarding carousel: billet-gpu's render of the seated cat in this coat, on transparency.
    var portrait: String { "Coat-\(rawValue)" }

    enum Failure: Error {
        case missing(String)
        case mismatch(String)
    }

    /// `file` in this coat: the same splats with this coat's colours.
    func dress(_ file: SplatLoader.File, in bundle: Bundle = .main) throws -> SplatLoader.File {
        guard self != .grey else { return file }
        let name = "\(file.name)-\(rawValue)"
        guard let url = bundle.url(forResource: name, withExtension: "fdc") else { throw Failure.missing(name) }
        let colours = try Data(contentsOf: url)
        let size = 3 * MemoryLayout<Float>.size
        let offset = 11 * MemoryLayout<Float>.size
        guard colours.count == file.count * size, file.stride == 14 * MemoryLayout<Float>.size else {
            throw Failure.mismatch(name)
        }
        var body = Data(file.body)
        body.withUnsafeMutableBytes { out in
            colours.withUnsafeBytes { from in
                for index in 0..<file.count {
                    let at = out.baseAddress! + index * file.stride + offset
                    at.copyMemory(from: from.baseAddress! + index * size, byteCount: size)
                }
            }
        }
        return SplatLoader.File(name: file.name, count: file.count, stride: file.stride, body: body)
    }

    /// Puts this coat's colour texture on the mesh cat loaded from `model` (Cat or CatStanding).
    @MainActor func dress(_ entity: Entity, model: String, in bundle: Bundle = .main) async {
        guard self != .grey, let url = bundle.url(forResource: "\(model)Color-\(rawValue)", withExtension: "jpg"),
              let texture = try? await TextureResource(contentsOf: url, options: .init(semantic: .color))
        else { return }
        var changed = 0
        func paint(_ entity: Entity) {
            guard let model = entity as? ModelEntity, var component = model.model else { return }
            component.materials = component.materials.map { material in
                // The body and fur shells take their colour from the atlas; the eyes, lids and bell have small ones.
                guard var pbr = material as? PhysicallyBasedMaterial,
                      let current = pbr.baseColor.texture?.resource,
                      current.width == texture.width, current.height == texture.height
                else { return material }
                pbr.baseColor.texture = .init(texture)
                changed += 1
                return pbr
            }
            model.model = component
        }
        paint(entity)
        entity.forEachDescendant(paint)
        if changed == 0 { print("\(model) has no coloured material for the \(rawValue) coat") }
    }
}
