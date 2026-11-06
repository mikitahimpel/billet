import Foundation
import Testing

@testable import Transport

/// Reads the contracts' route table, so a route changed there fails here.
@Suite struct RoutesContractTests {
  /// `name: route("METHOD", "/path")` lines of `routes.ts`, by name.
  static func contractRoutes() throws -> [String: Route] {
    let file = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "packages/contracts/http-api/src/routes.ts")
    let source = try String(contentsOf: file, encoding: .utf8)
    let pattern = #/(\w+): route\("(GET|POST|PUT|DELETE)", "([^"]+)"\)/#
    var result: [String: Route] = [:]
    for match in source.matches(of: pattern) {
      let method = try #require(HTTPMethod(rawValue: String(match.2)))
      result[String(match.1)] = Route(method, String(match.3))
    }
    return result
  }

  @Test func everyContractRouteIsMirrored() throws {
    let contract = try Self.contractRoutes()
    let mirrored: [String: Route] = [
      "authChallenge": Routes.authChallenge,
      "authAnonymous": Routes.authAnonymous,
      "authApple": Routes.authApple,
      "authAppleLink": Routes.authAppleLink,
      "getAccount": Routes.getAccount,
      "deleteAccount": Routes.deleteAccount,
      "authSignOut": Routes.authSignOut,
      "registerPushToken": Routes.registerPushToken,
      "createInvite": Routes.createInvite,
      "claimInvite": Routes.claimInvite,
      "unpair": Routes.unpair,
      "getPair": Routes.getPair,
      "setMood": Routes.setMood,
      "uploadImage": Routes.uploadImage,
      "downloadImage": Route(.get, Routes.downloadImagePrefix + "*"),
      "sendNote": Routes.sendNote,
      "getOnboarding": Routes.getOnboarding,
      "saveOnboardingAnswer": Routes.saveOnboardingAnswer,
      "listNotes": Routes.listNotes,
      "listInks": Routes.listInks,
      "getCoins": Routes.getCoins,
      "buyItem": Routes.buyItem,
      "getShop": Routes.getShop,
      "placeOrder": Routes.placeOrder,
      "setWish": Routes.setWish,
      "openGift": Routes.openGift,
      "claimBonus": Routes.claimBonus,
      "earnCoins": Routes.earnCoins,
      "getGifts": Routes.getGifts,
      "saveGiftWish": Routes.saveGiftWish,
      "deleteGiftWish": Routes.deleteGiftWish,
      "setGiftPlan": Routes.setGiftPlan,
      "markGiftReceived": Routes.markGiftReceived,
      "saveLoves": Routes.saveLoves,
      "getLists": Routes.getLists,
      "changeList": Routes.changeList,
      "searchTitles": Routes.searchTitles,
      "getTitle": Routes.getTitle,
      "getFlags": Routes.getFlags,
      "getStatus": Routes.getStatus,
      "getDateCatalog": Routes.getDateCatalog,
      "getCat": Routes.getCat,
      "saveCat": Routes.saveCat,
      "listCatJournal": Routes.listCatJournal,
      "react": Routes.react,
      "listReactions": Routes.listReactions,
      "recordCatEvent": Routes.recordCatEvent,
      "listActivity": Routes.listActivity,
      "markActivityRead": Routes.markActivityRead,
      "reportEvents": Routes.reportEvents,
      "purchase": Routes.purchase,
      "mockPurchase": Routes.mockPurchase,
      "createDemoPartner": Routes.createDemoPartner,
      "getDemoPartner": Routes.getDemoPartner,
      "removeDemoPartner": Routes.removeDemoPartner,
      "getPurchases": Routes.getPurchases,
      "appStoreNotifications": Routes.appStoreNotifications,
    ]
    #expect(contract == mirrored)
  }

  @Test func theSocketRouteMatchesTheContract() throws {
    let file = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "packages/contracts/realtime/src/socket-route.ts")
    let source = try String(contentsOf: file, encoding: .utf8)
    #expect(source.contains(#"{ method: "GET", path: "\#(Routes.socket.path)" }"#))
  }

  @Test func theAuthorizationHeaderMatchesTheContract() throws {
    let file = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "packages/contracts/http-api/src/routes.ts")
    let source = try String(contentsOf: file, encoding: .utf8)
    #expect(
      source.contains(#"authorizationHeader = "\#(Routes.authorizationHeader.lowercased())""#))
    #expect(source.contains(#"bearerPrefix = "\#(Routes.bearerPrefix)""#))
  }

  @Test func theClientHeadersMatchTheContract() throws {
    let file = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "packages/contracts/http-api/src/routes.ts")
    let source = try String(contentsOf: file, encoding: .utf8)
    #expect(source.contains(#"appVersion: "\#(Routes.appVersionHeader.lowercased())""#))
    #expect(source.contains(#"os: "\#(Routes.osHeader.lowercased())""#))
    #expect(source.contains(#"demoRoomHeader = "\#(Routes.demoRoomHeader.lowercased())""#))
  }

  @Test func theSocketRequestIsSignedAndSecure() throws {
    let base = try #require(URL(string: "https://api.example"))
    let request = try #require(URLRequest.socket(baseURL: base, token: "t"))
    #expect(request.url?.absoluteString == "wss://api.example/v1/socket")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
    #expect(URLRequest.socket(baseURL: URL(fileURLWithPath: "/x"), token: "t") == nil)
  }
}
