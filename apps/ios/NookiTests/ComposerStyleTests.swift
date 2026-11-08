import CoreGraphics
import Foundation
import Testing
@testable import Billet

/// The composer's Labs choice and the shape of its paper.
struct ComposerStyleTests {
    @Test func theDeskIsTheDefault() {
        UserDefaults.standard.removeObject(forKey: ComposerStyle.key)
        #expect(ComposerStyle.current == .desk)
    }

    @Test func aKeptChoiceWins() {
        UserDefaults.standard.set(ComposerStyle.papers.rawValue, forKey: ComposerStyle.key)
        defer { UserDefaults.standard.removeObject(forKey: ComposerStyle.key) }
        #expect(ComposerStyle.current == .papers)
    }

    @Test func theStickyPadHasOnePaper() {
        #expect(ComposerStyle.sticky.kinds == [.sticky])
        #expect(ComposerStyle.desk.kinds.count == 3)
    }

    @Test func theTextStaysOnItsPaper() {
        let paper = CGRect(x: 0, y: 0, width: 1, height: 1)
        for kind in PaperKind.allCases {
            #expect(paper.contains(kind.textArea))
        }
    }
}
