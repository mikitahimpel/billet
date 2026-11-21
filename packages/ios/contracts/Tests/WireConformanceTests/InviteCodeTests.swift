import Foundation
import Testing

@testable import Wire

@Suite struct InviteCodeTests {
  @Test(arguments: [
    ("K7QM4R2XHP", "K7QM4R2XHP"), ("k7qm4-r2xhp", "K7QM4R2XHP"), (" K7QM 4R2X HP ", "K7QM4R2XHP"),
    ("ABCD2345EFGHJKLMNPQRSTUVWX", "ABCD2345EFGHJKLMNPQRSTUVWX"),
  ])
  func aCodeInAnyCaseOrGroupingReadsAsTheServerTakesIt(typed: String, code: String) {
    #expect(InviteCode.parsed(typed) == InviteCode(code))
  }

  @Test(arguments: ["", "K7QM4", "K7QM4R2XH0", "K7QM4R2XHPX", "K7QM4R2XH!", "<script>"])
  func anythingElseIsNoCode(_ typed: String) {
    #expect(InviteCode.parsed(typed) == nil)
  }

  @Test func aTypedCodeKeepsOnlyACodesSymbolsAndReadsInFives() {
    #expect(InviteCode.cleaned("k7qm4 r2-xhp!") == "K7QM4R2XHP")
    #expect(InviteCode.cleaned("O0I1") == "")
    #expect(InviteCode.cleaned(String(repeating: "A", count: 30)).count == InviteCode.reviewLength)
    #expect(InviteCode.grouped("K7QM4R2XHP") == "K7QM4 R2XHP")
    #expect(InviteCode.grouped("K7QM4R") == "K7QM4 R")
    #expect(InviteCode.grouped("K7QM") == "K7QM")
    #expect(InviteCode.grouped("") == "")
  }

  @Test func theLinkIsTheServersInvitePath() {
    let server = URL(string: "https://ourio-api-dev.example.dev")!
    #expect(
      InviteCode("K7QM4R2XHP").link(on: server).absoluteString
        == "https://ourio-api-dev.example.dev/i/K7QM4R2XHP")
  }
}
