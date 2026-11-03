import Foundation
import Pet
import PetScene
import RealityKit
import simd

extension GenzRoom {
  /// Plays the reactions to play, food, lifting, calling and the partner.
  func showPlay(_ response: CatPlayResponse) {
    switch response.reaction {
    case .partnerLove:
      purr.heart(at: screen.cat)
    case .lean, .flick, .grab, .stalk, .watch, .chase, .caught, .eat, .takeTreat, .refuse,
      .dangle, .settle, .come, .ignore, .trick:
      break
    }
  }
}
