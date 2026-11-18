import Foundation
import Testing

@testable import WidgetInterface

struct DeepLinkTests {
  @Test(arguments: [
    "https://ourio-api.example.dev/i/K7QM4R2XHP", "https://ourio-api.example.dev/i/k7qm4-r2xhp",
    "ourio://invite/K7QM4R2XHP", "nooki://invite/k7qm4r2xhp",
  ])
  func anInviteLinkCarriesTheCodeAsTheServerTakesIt(_ link: String) {
    #expect(DeepLink(url: URL(string: link)!) == .invite("K7QM4R2XHP"))
  }

  @Test(arguments: [
    "https://ourio-api.example.dev/i/K7QM4", "https://ourio-api.example.dev/i/K7QM4R2XH0",
    "ourio://invite/nope",
  ])
  func anInviteLinkWithABrokenCodeStillOpensTheCodePageEmpty(_ link: String) {
    #expect(DeepLink(url: URL(string: link)!) == .invite(""))
  }

  @Test(arguments: [
    "https://ourio-api.example.dev/i/K7QM4R2XHP/more", "https://ourio-api.example.dev/v1/pair",
    "https://ourio-api.example.dev/", "mailto:K7QM4R2XHP",
  ])
  func otherLinksAreNoInvite(_ link: String) {
    #expect(DeepLink(url: URL(string: link)!) == nil)
  }
}
