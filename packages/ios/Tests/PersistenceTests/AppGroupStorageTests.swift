import Foundation
import Testing

@testable import Persistence

@Suite struct AppGroupStorageTests {
  /// A fresh directory standing in for the App Group container. It is created on first write.
  static func storage() -> AppGroupStorage {
    .directory(
      FileManager.default.temporaryDirectory.appending(
        path: "billet-tests-\(UUID().uuidString)", directoryHint: .isDirectory))
  }

  @Test func readsNothingBeforeAWrite() throws {
    #expect(try Self.storage().read("a.json") == nil)
  }

  @Test func writtenDataReadsBack() throws {
    let storage = Self.storage()
    try storage.write("a.json", Data("hello".utf8))
    #expect(try storage.read("a.json") == Data("hello".utf8))
  }

  @Test func writingAgainReplaces() throws {
    let storage = Self.storage()
    try storage.write("a.json", Data("one".utf8))
    try storage.write("a.json", Data("two".utf8))
    #expect(try storage.read("a.json") == Data("two".utf8))
  }

  @Test func removeDeletesAndToleratesMissing() throws {
    let storage = Self.storage()
    try storage.write("a.json", Data("x".utf8))
    try storage.remove("a.json")
    #expect(try storage.read("a.json") == nil)
    try storage.remove("a.json")
  }

  @Test func namesCannotEscapeTheDirectory() {
    let storage = Self.storage()
    #expect(throws: PersistenceError.invalidName("../x")) { try storage.read("../x") }
    #expect(throws: PersistenceError.invalidName("")) { try storage.write("", Data()) }
  }

  @Test func jsonRoundTrips() throws {
    let storage = Self.storage()
    try storage.writeJSON([1, 2, 3], named: "n.json")
    #expect(try storage.readJSON([Int].self, named: "n.json") == [1, 2, 3])
  }

  @Test func undecodableJSONIsCorrupted() throws {
    let storage = Self.storage()
    try storage.write("n.json", Data("nope".utf8))
    #expect(throws: PersistenceError.corrupted("n.json")) {
      try storage.readJSON([Int].self, named: "n.json")
    }
  }
}
