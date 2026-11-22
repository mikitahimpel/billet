import Foundation

/// The episodes this build ships. A new one is a JSON file in `Resources` and a line here.
public enum EpisodeCatalog {
  public static let files = ["fish-plush"]

  /// Every shipped episode, in the order a pair plays them. A file that fails to decode or validate is a
  /// build error, caught by the catalog test, never a crash in the field: it is left out.
  public static var all: [Episode] {
    files.compactMap { try? load($0) }
  }

  public static func load(_ name: String) throws -> Episode {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
      throw CocoaError(.fileNoSuchFile)
    }
    let episode = try JSONDecoder().decode(Episode.self, from: Data(contentsOf: url))
    try episode.validate()
    return episode
  }

  public static func episode(_ id: String) -> Episode? { all.first { $0.id == id } }
}
