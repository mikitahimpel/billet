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

    @Test func everyWireMoodIsAnAppMood() {
        for wire in CheckInMood.allCases {
            #expect(PartnerMood(rawValue: wire.rawValue) != nil, "\(wire.rawValue) has no face")
        }
        #expect(PartnerMood.allCases.map(\.rawValue).sorted() == CheckInMood.allCases.map(\.rawValue).sorted())
    }

    @Test func aSharedMoodShowsItsFaceInTheInbox() {
        let names = InboxLine.Names(partner: "Anya", cat: "Mochi")
        let item = ActivityItem(id: "x", at: 0, actor: .partner, event: .moodShared(mood: .missing))
        let line = InboxLine(item, names: names)
        #expect(line.text == "Anya feels missing you")
        #expect(line.mood == .missing)
    }
}
