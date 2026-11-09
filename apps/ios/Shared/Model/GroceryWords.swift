import Foundation

/// How grocery names compare: case, ё and е, and plural endings don't count, so "Lemons" is "lemon" and "лимоны" is
/// "лимон". A stem keeps at least three letters, so short words stay whole.
public nonisolated enum GroceryWords {
    /// Lowercase words with ё as е, split on anything that is not a letter or a digit.
    public static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    public static func stems(_ text: String) -> [String] { words(text).map(stem) }

    /// The same for every spelling of one product: the key the pair's history is kept under.
    public static func key(_ text: String) -> String { stems(text).joined(separator: " ") }

    public static func isCyrillic(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
    }

    public static func stem(_ word: String) -> String {
        isCyrillic(word) ? russianStem(word) : englishStem(word)
    }

    // Longest first, so "ые" goes before "е".
    private static let russianEndings = [
        "ами", "ями", "ого", "его", "ов", "ев", "ей", "ые", "ие", "ое", "ая", "яя", "ый", "ий", "ой", "ую", "ам", "ям",
        "ах", "ях", "ы", "и", "а", "я", "о", "е", "ь", "й", "у", "ю",
    ]

    private static func russianStem(_ word: String) -> String {
        for ending in russianEndings where word.hasSuffix(ending) && word.count - ending.count >= 3 {
            return String(word.dropLast(ending.count))
        }
        return word
    }

    private static func englishStem(_ word: String) -> String {
        func drop(_ n: Int, adding tail: String = "") -> String? {
            word.count - n >= 3 ? String(word.dropLast(n)) + tail : nil
        }
        if word.hasSuffix("ies") { return drop(3, adding: "y") ?? word }
        if word.hasSuffix("oes") || word.hasSuffix("ches") || word.hasSuffix("shes") || word.hasSuffix("xes")
            || word.hasSuffix("sses") {
            return drop(2) ?? word
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss") { return drop(1) ?? word }
        return word
    }
}
