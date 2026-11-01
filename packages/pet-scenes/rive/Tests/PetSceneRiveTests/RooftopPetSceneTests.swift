import CoreGraphics
import Foundation
import Pet
import PetScene
import Testing

@testable import PetSceneRive

@Suite("RooftopPetScene")
@MainActor
struct RooftopPetSceneTests {
  private let scene = RooftopPetScene()

  @Test func identityIsStable() {
    #expect(scene.id == "rooftop")
    #expect(scene.title == "Rooftop")
    #expect(scene.credit == nil)
  }

  @Test func pacingStaysInsideThePetDeadlines() {
    #expect(RooftopPetScene.pacing.delivery < PetRunner.deliveryDeadline)
    #expect(RooftopPetScene.pacing.settling < PetRunner.settlingDeadline)
  }

  @Test func bundledFileHasTheBoundNoteArrivedProperty() {
    #expect(PetWorldRive(fileName: "Rooftop", artboardName: "Rooftop") != nil)
  }

  @Test func theNoteShowsBeforeTheDeliveryEnds() throws {
    let wall = try #require(scene.noteWall)
    #expect(wall.revealDelay < RooftopPetScene.pacing.delivery)
  }

  @Test func thePaperHangsFromThePegInsideTheArtboard() throws {
    let wall = try #require(scene.noteWall)
    #expect(CGRect(origin: .zero, size: wall.artboard).contains(wall.paper))
    #expect(wall.peg.x == wall.paper.midX)
    #expect(wall.peg.y < wall.paper.minY)
  }

  @Test func everyPoseIsAPNG() throws {
    for pose in PetPose.allCases {
      let png = try #require(scene.posePNG(pose))
      #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }
  }
}
