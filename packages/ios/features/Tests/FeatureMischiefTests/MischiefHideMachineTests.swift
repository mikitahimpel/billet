import MischiefInterface
import Testing

@testable import FeatureMischief

struct MischiefHideMachineTests {
  typealias M = MischiefHideMachine

  @Test func openingStartsAnEmptyDraft() {
    #expect(M.transition(.closed, .opened) == (.choosing(.init()), []))
  }

  @Test func openingTwiceKeepsTheDraft() {
    let state = M.State.choosing(.init(spot: .sofa, line: "hi"))
    #expect(M.transition(state, .opened) == (state, []))
  }

  @Test func aSpotAndALineFillTheDraft() {
    var state = M.transition(.closed, .opened).0
    state = M.transition(state, .picked(.basket)).0
    state = M.transition(state, .wrote("under the rug?")).0
    #expect(state == .choosing(.init(spot: .basket, line: "under the rug?")))
  }

  @Test func pickingAgainReplacesTheSpot() {
    let state = M.transition(.choosing(.init(spot: .sofa)), .picked(.crate)).0
    #expect(state == .choosing(.init(spot: .crate)))
  }

  @Test func theLineIsClippedAsItIsTyped() {
    let long = String(repeating: "a", count: 60) + "\u{7}"
    guard case .choosing(let draft) = M.transition(.choosing(.init()), .wrote(long)).0 else {
      Issue.record("not choosing")
      return
    }
    #expect(draft.line.unicodeScalars.count == MischiefLine.maxScalars)
  }

  @Test func submittingHidesAtTheSpotWithTheTrimmedLine() {
    let state = M.State.choosing(.init(spot: .basket, line: "  you looked under the rug first  "))
    let (next, outputs) = M.transition(state, .submitted)
    #expect(next == .closed)
    #expect(outputs == [.hide(spot: .basket, line: "you looked under the rug first")])
  }

  @Test func submittingWithAnEmptyLineSendsNone() {
    let (_, outputs) = M.transition(.choosing(.init(spot: .crate, line: "   ")), .submitted)
    #expect(outputs == [.hide(spot: .crate, line: nil)])
  }

  @Test func submittingWithoutASpotIsRejected() {
    let state = M.State.choosing(.init(spot: nil, line: "hi"))
    #expect(M.transition(state, .submitted) == (state, []))
  }

  @Test func cancellingClosesWithoutHiding() {
    #expect(M.transition(.choosing(.init(spot: .sofa)), .cancelled) == (.closed, []))
  }

  @Test(arguments: [
    M.Event.picked(.sofa), .wrote("x"), .submitted, .cancelled,
  ])
  func aClosedSheetIgnoresEverythingButOpening(event: M.Event) {
    #expect(M.transition(.closed, event) == (.closed, []))
  }
}
