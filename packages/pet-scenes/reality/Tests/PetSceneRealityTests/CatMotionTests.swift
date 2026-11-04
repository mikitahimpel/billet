import Pet
import Testing

@testable import PetSceneReality

@Suite struct CatMotionTests {
  /// A cat's own moves are ones it has, play once, and start from sitting or loafing, the poses of
  /// the calm steps they cut into.
  @Test func everyOwnMoveIsAOneShotTheCatHasFromACalmPose() {
    for model in CatModel.allCases {
      let clips = CatCatalog.clips(model)
      for move in model.motion.signature {
        let clip = clips[move]
        #expect(clip != nil, "\(model) has no \(move)")
        #expect(clip?.loops == false, "\(model) \(move) loops")
        let base = clip?.base.map(\.rawValue) ?? "nothing"
        #expect(clip?.base == .sit || clip?.base == .loaf, "\(model) \(move) starts from \(base)")
      }
    }
  }

  /// Tempo stays within what still looks like a cat: no slow motion, no fast-forward.
  @Test func tempoStaysCatLike() {
    for model in CatModel.allCases {
      #expect((0.75...1.3).contains(model.motion.tempo), "\(model) tempo \(model.motion.tempo)")
      #expect(model.motion.every >= 6, "\(model) fidgets too often")
    }
  }
}
