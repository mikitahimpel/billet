import SwiftUI
import UIKit

/// Every country's outline from Natural Earth (public domain), simplified to half a degree, on an equirectangular
/// map from 180°W, 84°N to 180°E, 56°S. `WorldMap.txt` is made by `scripts/places/world-map.py`.
nonisolated struct WorldMap: Sendable {
    static let size = CGSize(width: 720, height: 280)

    /// Rings by ISO 3166-1 alpha-2 code; `XX` is land without one.
    let shapes: [String: [[CGPoint]]]

    static let bundled = WorldMap(text: Bundle.main.url(forResource: "WorldMap", withExtension: "txt")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")

    init(text: String) {
        var shapes: [String: [[CGPoint]]] = [:]
        for line in text.split(separator: "\n") {
            guard let space = line.firstIndex(of: " ") else { continue }
            let rings = line[line.index(after: space)...].split(separator: "|").map { ring in
                ring.split(separator: " ").compactMap { point -> CGPoint? in
                    let xy = point.split(separator: ",")
                    guard xy.count == 2, let x = Double(xy[0]), let y = Double(xy[1]) else { return nil }
                    return CGPoint(x: x, y: y)
                }
            }
            shapes[String(line[..<space]), default: []] += rings.filter { $0.count >= 3 }
        }
        self.shapes = shapes
    }

    /// The country's outline drawn into `rect`.
    func path(_ code: String, in rect: CGRect) -> Path {
        path(shapes[code] ?? [], in: rect)
    }

    /// All the land, every country together.
    func land(in rect: CGRect) -> Path {
        path(shapes.values.flatMap(\.self), in: rect)
    }

    /// The country's middle in `rect` when it is too small to see at that size, so it can be drawn as a dot.
    func dot(_ code: String, in rect: CGRect, below points: CGFloat = 5) -> CGPoint? {
        let bounds = path(code, in: rect).boundingRect
        guard !bounds.isNull, max(bounds.width, bounds.height) < points else { return nil }
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    private func path(_ rings: [[CGPoint]], in rect: CGRect) -> Path {
        let scale = CGSize(width: rect.width / Self.size.width, height: rect.height / Self.size.height)
        var path = Path()
        for ring in rings {
            path.addLines(ring.map { CGPoint(x: rect.minX + $0.x * scale.width, y: rect.minY + $0.y * scale.height) })
            path.closeSubpath()
        }
        return path
    }
}

/// The world with the countries been to filled in honey and the ones wanted outlined.
struct WorldMapView: View {
    let been: Set<String>
    let wanted: Set<String>
    var map = WorldMap.bundled

    static let wantedColor = Color(light: Color.honeyDeep, dark: Color(hex: 0xFFE07A))

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(map.land(in: rect), with: .color(Ink.text.opacity(0.12)))
            for code in been {
                if let dot = map.dot(code, in: rect) {
                    context.fill(Path(ellipseIn: CGRect(x: dot.x - 3, y: dot.y - 3, width: 6, height: 6)),
                                 with: .color(.honey))
                } else {
                    context.fill(map.path(code, in: rect), with: .color(.honey))
                }
            }
            let dashed = StrokeStyle(lineWidth: 1.2, lineJoin: .round, dash: [2.5, 2])
            for code in wanted {
                if let dot = map.dot(code, in: rect) {
                    context.stroke(Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)),
                                   with: .color(Self.wantedColor), style: dashed)
                } else {
                    context.stroke(map.path(code, in: rect), with: .color(Self.wantedColor), style: dashed)
                }
            }
        }
        .aspectRatio(WorldMap.size.width / WorldMap.size.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// A country's round flag from circle-flags (MIT), or its emoji flag on a circle when the bundle has none.
struct CountryFlag: View {
    let code: String
    var size: CGFloat = 34

    var body: some View {
        Group {
            if let image = UIImage(named: "flag-\(code.lowercased())") {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Text(Country.emoji(code))
                    .font(.system(size: size * 0.62))
                    .frame(width: size, height: size)
                    .background(Ink.surfaceRaised, in: .circle)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(Ink.separator, lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
