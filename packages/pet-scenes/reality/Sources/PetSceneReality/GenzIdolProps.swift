import Foundation
import OSLog
import RealityKit

/// The Window Seat props made by machine rather than by hand: a FLUX.2-klein picture in the room's
/// look, turned into a 3D model by Idol, then remeshed to a closed surface of 1–3 thousand
/// triangles with its colour baked onto one texture all of them share. They live in
/// `IdolProps.reality`, one model each, named `Idol_<raw value>`.
///
/// Each model is in metres, at its real size, with its flat bottom at y = 0, its pivot at the
/// middle of its base, and its front facing +z.
enum IdolProp: String, CaseIterable, Sendable {
  case beanbag
  case floorlamp
  case throwblanket
  case monstera
  case cactus
  case books
  case recordplayer
  case mugs
  case stringlights
  case rug
  case catbed

  var kind: GenzPiece.Kind {
    switch self {
    case .beanbag: .idolBeanBag
    case .floorlamp: .idolFloorLamp
    case .throwblanket: .idolThrow
    case .monstera: .idolMonstera
    case .cactus: .idolCactus
    case .books: .idolBooks
    case .recordplayer: .idolRecordPlayer
    case .mugs: .idolMugs
    case .stringlights: .idolStringLights
    case .rug: .idolRug
    case .catbed: .idolCatBed
    }
  }

  var modelName: String { "Idol_\(rawValue)" }

  /// The model's width (x), depth (z) and height (y) in metres, as the asset script wrote them.
  var metres: SIMD3<Float> {
    switch self {
    case .beanbag: [0.8, 0.8, 0.6]
    case .floorlamp: [0.4, 0.4, 1.5]
    case .throwblanket: [0.5, 0.4, 0.12]
    case .monstera: [0.75, 0.75, 1.1]
    case .cactus: [0.12, 0.12, 0.18]
    case .books: [0.28, 0.2, 0.2]
    case .recordplayer: [0.42, 0.34, 0.13]
    case .mugs: [0.22, 0.1, 0.1]
    case .stringlights: [0.36, 0.36, 0.08]
    case .rug: [1.2, 1.2, 0.015]
    case .catbed: [0.5, 0.5, 0.18]
    }
  }

  /// How much of its bounding box the cat must keep off: a round thing fills less than its box.
  var footprint: Float {
    switch self {
    case .beanbag, .monstera, .cactus, .mugs, .stringlights, .rug, .catbed: 0.85
    case .floorlamp: 0.6
    case .throwblanket, .books, .recordplayer: 1
    }
  }

  /// Whether the cat may get up on it and sit or lie there, as on the cardigan.
  var catSitsOnTop: Bool {
    switch self {
    case .beanbag, .throwblanket, .books, .rug, .catbed: true
    case .floorlamp, .monstera, .cactus, .recordplayer, .mugs, .stringlights: false
    }
  }
}

extension GenzRoomPoint {
  /// Room units in a metre, for things modelled at their real size: the room is 5.4 units high,
  /// about 2.45 m, and a mug 0.2 units, about 9 cm.
  static let perMetre: Float = 2.2
}

extension GenzPiece.Kind {
  /// The generated prop this kind shows, or nil for a piece made by hand.
  var idol: IdolProp? {
    IdolProp.allCases.first { $0.kind == self }
  }

  /// Whether the cat may get up on it and lie there, as on the cardigan.
  var catSitsOnTop: Bool {
    self == .cardigan || idol?.catSitsOnTop == true
  }
}

extension GenzLayout {
  /// Window Seat with the generated props in place of the hand-made pieces they stand for, at the
  /// same spots, and a few more of them about the room. The first simple set is left as it is.
  func withIdolProps() -> GenzLayout {
    guard furniture != .original else { return self }
    var layout = self
    layout.idolProps = true
    let swaps: [GenzPiece.Kind: GenzPiece.Kind] = [
      .patternRug: .idolRug,
      .leafyPlant: .idolMonstera,
      .catBed: .idolCatBed,
      .knitPouf: .idolBeanBag,
      .mugs: .idolMugs,
      .cardigan: .idolThrow,
      .recordPlayer: .idolRecordPlayer,
      .candles: .idolCactus,
    ]
    layout.pieces = pieces.map { placement in
      guard let kind = swaps[placement.piece.kind] else { return placement }
      var swapped = placement
      swapped.piece = GenzPiece(kind)
      return swapped
    }
    var extras = [
      Placement(piece: GenzPiece(.idolFloorLamp), centre: GenzRoomPoint(0.55, 5.3, 0)),
      Placement(
        piece: GenzPiece(.idolStringLights), centre: GenzRoomPoint(1.5, 4.75, 0), yaw: 0.5),
      Placement(piece: GenzPiece(.idolBooks), centre: GenzRoomPoint(4.75, 1.25, 1.3), yaw: -0.2),
    ]
    if !layout.pieces.contains(where: { $0.piece.kind == .idolBeanBag }) {
      extras.append(Placement(piece: GenzPiece(.idolBeanBag), centre: GenzRoomPoint(3.1, 3.3, 0)))
    }
    layout.pieces += extras
    return layout
  }
}

@MainActor
extension GenzKit {
  /// Loads the generated props once, from their compiled file. A missing or unreadable file leaves
  /// them out: their pieces are then empty, and the room is still whole.
  func loadIdolProps() async {
    guard idolModels.isEmpty, !idolPropsTried else { return }
    idolPropsTried = true
    guard let file = await NookiAssets.compiled(Self.idolFile) else {
      Self.idolLog.error("No \(Self.idolFile, privacy: .public) file")
      return
    }
    for prop in IdolProp.allCases {
      guard let model = file.findEntity(named: prop.modelName) else {
        Self.idolLog.error("\(prop.modelName, privacy: .public) missing")
        continue
      }
      model.removeFromParent()
      idolModels[prop] = matte(model)
    }
  }

  static let idolFile = "IdolProps"
  private static let idolLog = Logger(subsystem: "com.mikitahimpel.billet", category: "IdolProps")

  /// The model with every material made the room's matte: the baked colour, no shine.
  private func matte(_ model: Entity) -> Entity {
    SceneParts.visit(model) { entity in
      guard let part = entity as? ModelEntity, var component = part.model else { return }
      component.materials = component.materials.map { material in
        guard let lit = material as? PhysicallyBasedMaterial else { return material }
        var material = PhysicallyBasedMaterial()
        material.baseColor = lit.baseColor
        material.roughness = 0.9
        material.metallic = 0.0
        return material
      }
      part.model = component
    }
    return model
  }

  /// The generated prop's parts, scaled to room units with the near floor corner of its box at
  /// the origin, as the hand-made pieces are built. None while its model is not loaded.
  func idolParts(_ prop: IdolProp) -> [Entity] {
    guard let prototype = idolModels[prop] else { return [] }
    let model = prototype.clone(recursive: true)
    model.scale = .one * GenzRoomPoint.perMetre
    let size = prop.kind.size
    model.position = GenzRoomPoint(size.x / 2, size.y / 2, 0).scene
    return [model]
  }
}
