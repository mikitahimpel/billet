import Foundation
import Pet
import PetScene
import RealityKit
import simd

extension NookiDiorama {
  func showPlay(_ response: CatPlayResponse) {
    switch response.reaction {
    case .partnerLove:
      purr.heart(at: strokePointOrCat)
    case .lean, .flick, .grab, .stalk, .watch, .chase, .caught, .eat, .takeTreat, .refuse,
      .dangle, .settle, .come, .ignore, .trick:
      break
    }
  }

  var strokePointOrCat: CGPoint? { catBody().map { CGPoint(x: $0.head.x, y: $0.head.y) } }
}
