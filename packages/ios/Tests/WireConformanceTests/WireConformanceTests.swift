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
  guard compact(original) == compact(encoded) else {
    throw Mismatch(description: "\(relative): re-encoded JSON differs from the fixture")
  }
}

/// Strips whitespace outside strings and keeps every other byte, so `1`, `1.0`, `true` and key
/// order must match the fixture exactly. Fixtures are canonical (sorted keys), so a round trip
/// must encode with `.sortedKeys` and `.withoutEscapingSlashes`.
func compact(_ data: Data) -> [UInt8] {
  var output: [UInt8] = []
  var inString = false
  var escaped = false
  for byte in data {
    if inString {
      if escaped {
        escaped = false
      } else if byte == UInt8(ascii: "\\") {
        escaped = true
      } else if byte == UInt8(ascii: "\"") {
        inString = false
      }
      output.append(byte)
    } else if byte == UInt8(ascii: "\"") {
      inString = true
      output.append(byte)
    } else if ![0x20, 0x09, 0x0A, 0x0D].contains(byte) {
      output.append(byte)
    }
  }
  return output
}

@Test("Wire round-trips fixture", arguments: fixtureURLs())
func wireRoundTrips(fixture: URL) throws {
  try roundTrip(fixture: fixture)
}

@Test("Golden fixtures exist")
func goldenFixturesExist() {
  #expect(
    !fixtureURLs().isEmpty,
    "No fixtures found in \(fixturesDirectory.path); conformance would check nothing.")
}
