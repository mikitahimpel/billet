import BilletKit

/// One of the two who pack. The first packs before the other's things are seen.
public enum PackPacker: Hashable, Sendable {
  case first, second

  public var other: PackPacker {
    switch self {
    case .first: .second
    case .second: .first
    }
  }
}

public enum PackThing: String, CaseIterable, Hashable, Sendable {
  case boots, umbrella, guitar, camera, books, sweater, hat, towel, teapot, lantern, map, scarf

  public var title: String {
    switch self {
    case .boots: "Boots"
    case .umbrella: "Umbrella"
    case .guitar: "Guitar"
    case .camera: "Camera"
    case .books: "Books"
    case .sweater: "Sweater"
    case .hat: "Hat"
    case .towel: "Towel"
    case .teapot: "Teapot"
    case .lantern: "Lantern"
    case .map: "Map"
    case .scarf: "Scarf"
    }
  }
}

public struct PackPiece: Hashable, Sendable, Identifiable {
  public enum Content: Hashable, Sendable {
    case thing(PackThing, of: PackPacker)
    /// She is nobody's luggage and goes in last, if there is room.
    case cat
  }

  public let id: Int
  public let content: Content
  public let shape: PackShape

  public init(id: Int, content: Content, shape: PackShape) {
    self.id = id
    self.content = content
    self.shape = shape
  }

  public var isCat: Bool {
    switch content {
    case .thing: false
    case .cat: true
    }
  }

  public func belongs(to packer: PackPacker) -> Bool {
    switch content {
    case .thing(_, let owner): owner == packer
    case .cat: false
    }
  }
}

/// Where a piece lies: the square its outline's top-left corner is on, and how far it is turned.
public struct PackPlacement: Hashable, Sendable {
  public let at: PackCell
  public let turns: Int

  public init(at: PackCell, turns: Int) {
    self.at = at
    self.turns = ((turns % 4) + 4) % 4
  }
}

/// A suitcase and what has to go in it: three things each and the cat.
public struct PackLevel: Equatable, Sendable {
  public static let side = 6
  public static let thingsEach = 3

  public let width: Int
  public let height: Int
  public let pieces: [PackPiece]
  /// One way everything goes in. A level is cut out of a full suitcase, so there always is one.
  public let solution: [Int: PackPlacement]

  public init(width: Int, height: Int, pieces: [PackPiece], solution: [Int: PackPlacement]) {
    self.width = width
    self.height = height
    self.pieces = pieces
    self.solution = solution
  }

  public func piece(_ id: Int) -> PackPiece? { pieces.first { $0.id == id } }

  /// The same level for the same seed, on both phones.
  public static func make(seed: UInt64) -> PackLevel {
    var random = SeededRandom(seed: seed)
    let side = PackLevel.side
    let count = 2 * thingsEach + 1
    while true {
      // The last region is the cat: always four squares, a loaf or a stretch.
      let targets = (0..<count).map { $0 == count - 1 ? 4 : 3 + random.below(3) }
      guard let regions = carve(side: side, targets: targets, random: &random) else { continue }

      var things = PackThing.allCases
      var owners =
        Array(repeating: PackPacker.first, count: thingsEach)
        + Array(repeating: PackPacker.second, count: thingsEach)
      random.shuffle(&things)
      random.shuffle(&owners)

      var pieces: [PackPiece] = []
      var solution: [Int: PackPlacement] = [:]
      for (index, region) in regions.enumerated() {
        let lying = PackShape(region)
        // Handed over turned some other way, so the answer is not how it arrives.
        let handed = random.below(4)
        let content: PackPiece.Content =
          index == count - 1 ? .cat : .thing(things[index], of: owners[index])
        pieces.append(PackPiece(id: index + 1, content: content, shape: lying.turned(handed)))
        let corner = PackCell(
          x: region.map(\.x).min() ?? 0, y: region.map(\.y).min() ?? 0)
        solution[index + 1] = PackPlacement(at: corner, turns: 4 - handed)
      }
      return PackLevel(width: side, height: side, pieces: pieces, solution: solution)
    }
  }

  /// Grows a region from a square for each target until it is as big as asked or walled in. Nil when one
  /// came out under three squares.
  private static func carve(
    side: Int, targets: [Int], random: inout SeededRandom
  ) -> [[PackCell]]? {
    var owner: [PackCell: Int] = [:]
    var regions: [[PackCell]] = []
    while regions.count < targets.count {
      let cell = PackCell(x: random.below(side), y: random.below(side))
      guard owner[cell] == nil else { continue }
      owner[cell] = regions.count
      regions.append([cell])
    }
    func free(around region: [PackCell]) -> [PackCell] {
      var found: Set<PackCell> = []
      for cell in region {
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
          let next = PackCell(x: cell.x + dx, y: cell.y + dy)
          if (0..<side).contains(next.x), (0..<side).contains(next.y), owner[next] == nil {
            found.insert(next)
          }
        }
      }
      return found.sorted()
    }
    while true {
      let growing = regions.indices.filter {
        regions[$0].count < targets[$0] && !free(around: regions[$0]).isEmpty
      }
      guard !growing.isEmpty else { break }
      let index = growing[random.below(growing.count)]
      let choices = free(around: regions[index])
      let cell = choices[random.below(choices.count)]
      owner[cell] = index
      regions[index].append(cell)
    }
    guard regions.indices.allSatisfy({ regions[$0].count >= min(3, targets[$0]) }),
      regions.last?.count == targets.last
    else { return nil }
    return regions
  }
}

extension SeededRandom {
  mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }

  mutating func shuffle<T>(_ items: inout [T]) {
    guard items.count > 1 else { return }
    for index in stride(from: items.count - 1, to: 0, by: -1) {
      items.swapAt(index, below(index + 1))
    }
  }
}
