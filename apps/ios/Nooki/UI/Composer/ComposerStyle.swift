import Foundation

/// How the note composer looks; a Labs choice on this phone. All three share the canvas, the layout and the ink rule.
enum ComposerStyle: String, CaseIterable, Identifiable {
    case sticky, desk, papers

    static let key = "labs.composerStyle"
    static let standard = ComposerStyle.desk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sticky: "Sticky pad"
        case .desk: "Desk with Mochi"
        case .papers: "Papers and pen cup"
        }
    }

    var kinds: [PaperKind] {
        switch self {
        case .sticky: [.sticky]
        case .desk, .papers: PaperKind.allCases
        }
    }

    static var current: ComposerStyle {
        UserDefaults.standard.string(forKey: key).flatMap(ComposerStyle.init(rawValue:)) ?? standard
    }
}

/// The shape of the paper on the desk. It is how the note is written; the pinned note keeps only its colour.
enum PaperKind: String, CaseIterable, Identifiable {
    case sticky, letter, polaroid

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .sticky: "note.text"
        case .letter: "doc.plaintext"
        case .polaroid: "photo.on.rectangle"
        }
    }

    /// Width over height.
    var aspect: CGFloat {
        switch self {
        case .sticky: 1
        case .letter: 0.78
        case .polaroid: 0.86
        }
    }

    /// Where the text goes, as fractions of the paper.
    var textArea: CGRect {
        switch self {
        case .sticky: CGRect(x: 0.07, y: 0.07, width: 0.86, height: 0.8)
        case .letter: CGRect(x: 0.15, y: 0.07, width: 0.8, height: 0.86)
        case .polaroid: CGRect(x: 0.08, y: 0.78, width: 0.84, height: 0.2)
        }
    }

    var fontSize: CGFloat { self == .polaroid ? 17 : 22 }
}
