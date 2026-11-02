import RealityKit
import Testing

@testable import PetSceneReality

/// A view's content is modelled by a parent entity: adding is `addChild`, and a view that goes
/// removes what it added.
@MainActor
@Suite struct NookiHandOverTests {
  @Test func aViewThatGoesLeavesTheRoomWithTheViewThatTookIt() {
    let diorama = NookiDiorama()
    let rehearsal = Entity()
    let added = diorama.makeHolder()
    rehearsal.addChild(added)
    let stage = Entity()
    let taken = diorama.makeHolder()
    stage.addChild(taken)

    added.removeFromParent()

    #expect(diorama.root.parent === taken)
    #expect(taken.parent === stage)
  }
}
