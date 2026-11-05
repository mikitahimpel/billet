import SwiftUI

/// Mochi's coats: her own grey tabby and the ones tools/cat-gen/coats.py writes beside her splats, by the same names.
/// The choice is this phone's, kept in UserDefaults.
enum CatCoat: String, CaseIterable, Identifiable {
    case tabby, ginger, cream, black, tuxedo, white

    static let key = "catCoat"

    static var current: CatCoat {
        UserDefaults.standard.string(forKey: key).flatMap(CatCoat.init(rawValue:)) ?? .tabby
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .tabby: "Tabby"
        case .ginger: "Ginger"
        case .cream: "Cream"
        case .black: "Black"
        case .tuxedo: "Tuxedo"
        case .white: "White"
        }
    }

    /// The name in the .coats files; her own colors are the splat's.
    var file: String? { self == .tabby ? nil : rawValue }

    /// Fur and markings, for the picker's swatch.
    var swatch: (fur: Color, marks: Color) {
        switch self {
        case .tabby: (Color(hex: 0x9C9893), Color(hex: 0x4A4744))
        case .ginger: (Color(hex: 0xE08C40), Color(hex: 0x9A4A18))
        case .cream: (Color(hex: 0xEFD9B4), Color(hex: 0xC9A47C))
        case .black: (Color(hex: 0x1C1A1B), Color(hex: 0x0A0A0B))
        case .tuxedo: (Color(hex: 0x1C1A1B), Color(hex: 0xF4F2EE))
        case .white: (Color(hex: 0xF4F2EE), Color(hex: 0xDAD6D0))
        }
    }
}
