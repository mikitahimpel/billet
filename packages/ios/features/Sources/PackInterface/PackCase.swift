/// The suitcase with what lies in it so far.
public struct PackCase: Equatable, Sendable {
  public enum Problem: Equatable, Sendable {
    /// Part of it would stick out of the suitcase.
    case sticksOut
    /// It would lie on the piece with this id.
    case onTop(of: Int)
  }

  public let level: PackLevel
  public private(set) var placed: [Int: PackPlacement] = [:]

  public init(level: PackLevel) { self.level = level }

  /// The squares a piece covers when it lies like that.
  public func cells(of piece: PackPiece, _ placement: PackPlacement) -> [PackCell] {
    piece.shape.turned(placement.turns).cells.map {
      PackCell(x: $0.x + placement.at.x, y: $0.y + placement.at.y)
    }
  }

  /// Which piece lies on each covered square.
  public var covered: [PackCell: Int] {
    var covered: [PackCell: Int] = [:]
    for piece in level.pieces {
      guard let placement = placed[piece.id] else { continue }
      for cell in cells(of: piece, placement) { covered[cell] = piece.id }
    }
    return covered
  }

  public var loose: [PackPiece] { level.pieces.filter { placed[$0.id] == nil } }

  public func isIn(_ id: Int) -> Bool { placed[id] != nil }

  /// What stops the piece lying like that, a place it already has aside.
  public func problem(putting piece: PackPiece, _ placement: PackPlacement) -> Problem? {
    let covered = covered
    for cell in cells(of: piece, placement) {
      guard (0..<level.width).contains(cell.x), (0..<level.height).contains(cell.y) else {
        return .sticksOut
      }
      if let other = covered[cell], other != piece.id { return .onTop(of: other) }
    }
    return nil
  }

  /// Lays the piece down, or leaves the suitcase as it was and says why not.
  @discardableResult
  public mutating func put(_ piece: PackPiece, _ placement: PackPlacement) -> Problem? {
    if let problem = problem(putting: piece, placement) { return problem }
    placed[piece.id] = placement
    return nil
  }

  public mutating func lift(_ id: Int) { placed[id] = nil }

  /// Whether every loose piece can still go in, with what lies there left where it is.
  public var stillFits: Bool {
    let loose = loose.sorted { $0.shape.cells.count > $1.shape.cells.count }
    let room = level.width * level.height - covered.count
    guard loose.reduce(0, { $0 + $1.shape.cells.count }) <= room else { return false }
    var trial = self
    return trial.fit(loose[...])
  }

  private mutating func fit(_ pieces: ArraySlice<PackPiece>) -> Bool {
    guard let piece = pieces.first else { return true }
    for turns in 0..<4 where turns < piece.shape.turns.count {
      for y in 0..<level.height {
        for x in 0..<level.width {
          let placement = PackPlacement(at: PackCell(x: x, y: y), turns: turns)
          guard put(piece, placement) == nil else { continue }
          if fit(pieces.dropFirst()) { return true }
          lift(piece.id)
        }
      }
    }
    return false
  }
}
