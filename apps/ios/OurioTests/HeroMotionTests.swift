import Testing
import UIKit
@testable import Billet

struct HeroMotionTests {
    @Test func theLoopJoinsWithoutAJump() {
        let start = HeroMotion.pose(at: 0), end = HeroMotion.pose(at: HeroMotion.loop - 0.001)
        #expect(abs(start.breath - end.breath) < 0.01)
        #expect(abs(start.sway - end.sway) < 0.01)
        #expect(HeroMotion.pose(at: 2.5) == HeroMotion.pose(at: 2.5 + HeroMotion.loop))
    }

    @Test func aBlinkShutsHoldsAndOpensOnTheRoomsTiming() {
        let blink = HeroMotion.blinks[0]
        #expect(HeroMotion.pose(at: blink - 0.01).blink == 0)
        #expect(HeroMotion.pose(at: blink + 0.035).blink == 1)
        #expect(HeroMotion.pose(at: blink + 0.09).blink == 2)
        #expect(HeroMotion.pose(at: blink + 0.2).blink == 1)
        #expect(HeroMotion.pose(at: blink + 0.3).blink == 0)
    }

    @Test func anEarFlicksOutAndBack() {
        let flick = HeroMotion.flicks[0]
        #expect(HeroMotion.pose(at: flick + 0.175).ear == 2)
        #expect(HeroMotion.pose(at: flick + 0.05).ear == 1)
        #expect(HeroMotion.pose(at: flick + 0.4).ear == 0)
    }

    @Test func aTapBlinksFlicksAndHops() {
        let quiet = 0.3
        #expect(HeroMotion.pose(at: quiet).blink == 0 && HeroMotion.pose(at: quiet).hop == 0)
        let poked = HeroMotion.pose(at: quiet + 0.09, pokedAt: quiet)
        #expect(poked.blink == 2)
        #expect(poked.hop > 0)
        #expect(HeroMotion.pose(at: quiet + HeroMotion.hopLength / 2, pokedAt: quiet).hop > 0.99)
        #expect(HeroMotion.pose(at: quiet + 0.6, pokedAt: quiet).hop == 0)
        #expect(HeroMotion.pose(at: quiet - 0.1, pokedAt: quiet) == HeroMotion.pose(at: quiet - 0.1))
    }

    @Test func atRestSheIsStill() {
        #expect(HeroPose.rest.blink == 0 && HeroPose.rest.ear == 0 && HeroPose.rest.hop == 0)
    }

    /// Every coat ships the rest image at 3:4 and patches exactly the size of their rectangles, so a patch lands on
    /// the pixels it was cut from.
    @Test(arguments: CatCoat.allCases)
    func everyCoatHasItsHeroAndPatchesThatFit(coat: CatCoat) async throws {
        let images = try #require(await HeroImages.load(coat))
        let rest = images.rest.size
        #expect(rest.width * 4 == rest.height * 3)
        for (patches, rect) in [(images.blink, HeroImages.blinkRect), (images.ear, HeroImages.earRect)] {
            for patch in patches {
                #expect(abs(patch.size.width - rect.width * rest.width) <= 1)
                #expect(abs(patch.size.height - rect.height * rest.height) <= 1)
            }
        }
    }
}
