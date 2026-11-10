import Foundation
import RoomInterface

/// Grey is the original cat; every other coat is a billet-gpu recolour differing only in each splat's `f_dc_0...2`.
/// The app ships those (`Coats/<pose>-<coat>.fdc`, 3 little-endian floats per splat, PLY order) over a Caches copy
/// of the original PLY, byte for byte billet-gpu's (`CatCoatTests`). Meshes wear `Coats/<model>Color-<coat>.jpg`.
typealias CatCoat = RoomInterface.CatCoat

nonisolated extension CatCoat {
    enum Failure: Error {
        case missing(String)
        case mismatch(String)
    }

    /// The poses that have coats; each is `<pose>.ply` with its `.skin` and `.rig.json` beside it.
    static let poses = ["Mochi", "MochiStanding"]

    /// The app itself for grey, else a Caches folder with each of `poses`' PLY in this coat, written once, beside links
    /// to the original skins and rigs. One folder per set of poses: a Bundle caches its folder's listing, so files
    /// written later go unseen.
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

    /// The original PLY of `pose` with this coat's colours (`Coats/<pose>-<coat>.fdc`) laid over each splat's `f_dc`.
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
}
