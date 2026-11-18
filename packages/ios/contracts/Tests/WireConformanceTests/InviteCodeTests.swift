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

  @Test func theLinkIsTheServersInvitePath() {
    let server = URL(string: "https://ourio-api-dev.example.dev")!
    #expect(
      InviteCode("K7QM4R2XHP").link(on: server).absoluteString
        == "https://ourio-api-dev.example.dev/i/K7QM4R2XHP")
  }
}
