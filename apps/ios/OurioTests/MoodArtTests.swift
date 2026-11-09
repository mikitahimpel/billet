import Testing
import UIKit
import Wire
@testable import Billet

@Suite struct MoodArtTests {
    @Test func everyMoodHasItsOwnFace() {
        let names = PartnerMood.allCases.map(\.artName) + [MoodArt.neutralName]
        #expect(Set(names).count == names.count)
        for name in names {
            #expect(UIImage(named: name) != nil, "no \(name) in Moods.xcassets")
        }
    }

    @Test func aSharedMoodShowsItsFaceInTheInbox() {
        let names = InboxLine.Names(partner: "Anya", cat: "Mochi")
        let item = ActivityItem(id: "x", at: 0, actor: .partner, event: .moodShared(mood: .missing))
        let line = InboxLine(item, names: names)
        #expect(line.text == "Anya feels missing you")
        #expect(line.mood == .missing)
    }
}
