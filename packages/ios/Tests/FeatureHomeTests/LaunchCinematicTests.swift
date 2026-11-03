import Testing

@testable import FeatureHome

@MainActor
@Suite struct LaunchCinematicTests {
  @Test func aColdLaunchPlaysItOnceAndNeverAgainThatLaunch() {
    let launch = LaunchCinematic()
    #expect(launch.claim(onboardingPlayed: false))
    // Home made again, or the app back from the background: the same launch.
    #expect(!launch.claim(onboardingPlayed: false))
    #expect(!launch.claim(onboardingPlayed: false))
  }

  @Test func aLaunchThatOpenedOnTheHeartDoesNotGlideIntoTheRoomAfter() {
    let launch = LaunchCinematic()
    #expect(!launch.claim(onboardingPlayed: true))
    #expect(!launch.claim(onboardingPlayed: false))
  }
}
