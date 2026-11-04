import Foundation
import OSLog
import RealityKit

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
      idolModels[prop] = matte(model, glows: prop.glows)
    }
  }

  static let idolFile = "IdolProps"
  private static let idolLog = Logger(subsystem: "com.mikitahimpel.billet", category: "IdolProps")

  /// The model with every material made the room's matte: the baked colour, no shine. One that
  /// glows also gives off its baked colour, so it stays lit when the room's lights are low.
  private func matte(_ model: Entity, glows: Bool) -> Entity {
    SceneParts.visit(model) { entity in
      guard let part = entity as? ModelEntity, var component = part.model else { return }
      component.materials = component.materials.map { material in
        guard let lit = material as? PhysicallyBasedMaterial else { return material }
        var material = PhysicallyBasedMaterial()
        material.baseColor = lit.baseColor
        material.roughness = 0.9
        material.metallic = 0.0
        if glows {
          material.emissiveColor = .init(texture: lit.baseColor.texture)
          material.emissiveIntensity = 0.8
        }
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
