import Foundation
import RealityKit

/// Mochi's coat, picked in onboarding. Grey is Ilya's cat as he made it; every other coat is a recolour by billet-gpu
/// that differs from it only in each splat's colour (`f_dc_0...2`), so the app ships just those colours
/// (`Coats/<pose>-<coat>.fdc`, three little-endian floats per splat, in the PLY's order) and lays them over a copy of
/// Ilya's PLY in Caches, which the rigs then load (`bundle`); his files and CatRig stay untouched. That rebuilds
/// billet-gpu's coat PLY byte for byte (`CatCoatTests`). Where splats can't be drawn the mesh cat wears the coat's
/// colour texture instead (`Coats/<model>Color-<coat>.jpg`).
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

    /// Her round avatar in this coat: Ilya's for grey, the others rendered the same way (scripts/coats/coat-portraits.sh).
    var avatar: String { self == .grey ? "MochiPortrait" : "MochiPortrait-\(rawValue)" }

    enum Failure: Error {
        case missing(String)
        case mismatch(String)
    }

    /// The poses that have coats; each is `<pose>.ply` with its `.skin` and `.rig.json` beside it.
    static let poses = ["Mochi", "MochiStanding", "MochiLoaf", "MochiSleep"]

    /// Where the rigs are read from in this coat (`CatRig.Files(named:drawn:in:)`): the app itself for grey, else a
    /// folder in Caches holding each of `poses`' PLY in this coat, written once, beside links to Ilya's skins and rigs.
    /// Each set of poses has a folder of its own: a Bundle caches its folder's listing, so files written later go unseen.
    func bundle(poses: [String] = Self.poses, from main: Bundle = .main, caches: URL = .cachesDirectory) throws -> Bundle {
        guard self != .grey else { return main }
        // One folder per build, so an update that changes a coat's colours never reads the old ones.
        let root = caches.appending(path: "Coats")
        let build = main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let files = FileManager.default
        for old in (try? files.contentsOfDirectory(atPath: root.path)) ?? [] where old != build {
            try? files.removeItem(at: root.appending(path: old))
        }
        let set = poses == Self.poses ? "" : "-" + poses.joined(separator: "-")
        let folder = root.appending(path: "\(build)/\(rawValue)\(set).bundle")
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        for pose in poses {
            let ply = folder.appending(path: "\(pose).ply")
            if !files.fileExists(atPath: ply.path) {
                try dressedPLY(pose, from: main).write(to: ply, options: .atomic)
            }
            for (name, ext) in [(pose, "skin"), ("\(pose).rig", "json")] {
                guard let source = main.url(forResource: name, withExtension: ext) else { throw Failure.missing(name) }
                let link = folder.appending(path: "\(name).\(ext)")
                if (try? files.destinationOfSymbolicLink(atPath: link.path)) != source.path {
                    try? files.removeItem(at: link)
                    try files.createSymbolicLink(at: link, withDestinationURL: source)
                }
            }
        }
        guard let bundle = Bundle(url: folder) else { throw Failure.missing(folder.path) }
        return bundle
    }

    /// Ilya's PLY of `pose` with this coat's colours (`Coats/<pose>-<coat>.fdc`) laid over each splat's `f_dc`.
    func dressedPLY(_ pose: String, from bundle: Bundle = .main) throws -> Data {
        let name = "\(pose)-\(rawValue)"
        guard let plyURL = bundle.url(forResource: pose, withExtension: "ply") else { throw Failure.missing(pose) }
        guard let url = bundle.url(forResource: name, withExtension: "fdc") else { throw Failure.missing(name) }
        var ply = try Data(contentsOf: plyURL)
        let colours = try Data(contentsOf: url)
        guard let end = ply.range(of: Data("end_header\n".utf8))?.upperBound else { throw Failure.mismatch(pose) }
        let stride = 14 * MemoryLayout<Float>.size, offset = 11 * MemoryLayout<Float>.size
        let size = 3 * MemoryLayout<Float>.size
        let count = (ply.count - end) / stride
        guard (ply.count - end) % stride == 0, colours.count == count * size else { throw Failure.mismatch(name) }
        ply.withUnsafeMutableBytes { out in
            colours.withUnsafeBytes { from in
                for index in 0..<count {
                    (out.baseAddress! + end + index * stride + offset)
                        .copyMemory(from: from.baseAddress! + index * size, byteCount: size)
                }
            }
        }
        return ply
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
