import Foundation
import MoodInterface
import Testing

@testable import WidgetInterface

struct MochiPoseTests {
  private func pose(
    purring: Bool = false, night: Bool = false, drawing: Bool = false, mood: PartnerMood? = nil,
    want: CatNeedsGlance.Want? = nil
  ) -> MochiPose {
    MochiPose.pose(
      isPurring: purring, isNight: night, freshDrawing: drawing, partnerMood: mood, want: want)
  }

  @Test func purringBeatsEverything() {
    #expect(pose(purring: true, night: true, drawing: true, mood: .happy, want: .food) == .purring)
  }

  @Test func nightBeatsHungerAndNews() {
    #expect(pose(night: true, drawing: true, mood: .missing, want: .food) == .asleep)
  }

  @Test func eachWantHasItsOwnPose() {
    #expect(pose(want: .food) == .hungry)
    #expect(pose(want: .rest) == .drowsy)
    #expect(pose(want: .love) == .cuddly)
    #expect(pose(want: .play) == .playful)
  }

  @Test func aWantBeatsThePartnersNews() {
    #expect(pose(drawing: true, mood: .missing, want: .food) == .hungry)
  }

  @Test func newsFollowsWhenContent() {
    #expect(pose(drawing: true, mood: .happy) == .waiting)
    #expect(pose(mood: .missing) == .waiting)
    #expect(pose(mood: .happy) == .chirpy)
    #expect(pose(mood: .sleepy) == .napping)
    #expect(pose(mood: .busy) == .quiet)
    #expect(pose() == .idle)
  }

  @Test func onlyHungerAsksForAMeal() {
    #expect(pose(want: .food).care == .feed)
    for other: MochiPose in [.cuddly, .playful, .drowsy, .idle, .waiting, .purring] {
      #expect(other.care == .pet)
    }
  }

  @Test func herWordsFitTheirSpaceAndNameThePartner() {
    #expect(MochiPose.hungry.speech(partner: "M", freshDrawing: false) == "Mrrp? Dinner?")
    #expect(MochiPose.waiting.speech(partner: "M", freshDrawing: true) == "M sent art!")
    #expect(MochiPose.waiting.speech(partner: "M", freshDrawing: false) == "Where's M?")
    #expect(MochiPose.waiting.line(partner: "M", freshDrawing: true) == "M drew you something")
    #expect(MochiPose.waiting.line(partner: "M", freshDrawing: false) == "M is missing you")
    for pose in [MochiPose.purring, .asleep, .hungry, .drowsy, .cuddly, .playful, .idle] {
      #expect(pose.speech(partner: "M", freshDrawing: false).count <= 16)
    }
  }
}
