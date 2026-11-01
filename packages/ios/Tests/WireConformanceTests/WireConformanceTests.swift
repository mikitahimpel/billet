import Foundation
import Testing

@testable import Wire

/// Decodes a fixture into its Wire type and encodes it back to JSON.
typealias RoundTrip = @Sendable (Data) throws -> Data

/// Maps a fixture's top-level directory name to the Wire type that must round-trip it.
/// Every Wire type adds its entry here; a fixture without one fails.
let roundTrips: [String: RoundTrip] = [:]

let fixturesDirectory = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent().deletingLastPathComponent()
  .appending(path: "packages/contracts/fixtures/golden", directoryHint: .isDirectory)

func fixtureURLs() -> [URL] {
  guard
    let files = FileManager.default.enumerator(
      at: fixturesDirectory, includingPropertiesForKeys: nil)
  else { return [] }
  return files.compactMap { $0 as? URL }
    .filter { $0.pathExtension == "json" }
    .sorted { $0.path < $1.path }
}

struct Mismatch: Error, CustomStringConvertible {
  let description: String
}

func roundTrip(fixture url: URL) throws {
  let relative = url.path.dropFirst(fixturesDirectory.path.count + 1)
  guard let family = relative.split(separator: "/").first.map(String.init),
    relative.contains("/")
  else {
    throw Mismatch(description: "\(relative): fixtures live in <Type>/<case>.json")
  }
  guard let transform = roundTrips[family] else {
    throw Mismatch(description: "\(relative): no Wire round trip registered for \(family)")
  }
  let original = try Data(contentsOf: url)
  let encoded = try transform(original)
  let before = try JSONSerialization.jsonObject(with: original, options: [.fragmentsAllowed])
  let after = try JSONSerialization.jsonObject(with: encoded, options: [.fragmentsAllowed])
  guard (before as AnyObject).isEqual(after) else {
    throw Mismatch(description: "\(relative): re-encoded JSON differs from the fixture")
  }
}

@Test("Wire round-trips fixture", arguments: fixtureURLs())
func wireRoundTrips(fixture: URL) throws {
  try roundTrip(fixture: fixture)
}

@Test("Reports when there are no fixtures to round-trip")
func reportsFixtureCount() {
  let count = fixtureURLs().count
  print(
    count == 0
      ? "No golden fixtures in packages/contracts/fixtures/golden yet; nothing to round-trip."
      : "Round-tripping \(count) golden fixture(s).")
}
