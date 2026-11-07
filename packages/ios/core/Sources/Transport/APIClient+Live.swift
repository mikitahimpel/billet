import Foundation
import Wire

extension APIClient {
  /// The client over `http`. `token` is read for each signed request, so a sign-out or a new
  /// session takes effect at once. A signed route called without a token fails as unauthorized
  /// without leaving the device.
  public static func live(
    http: HTTPService, token: @escaping @Sendable () async -> String?
  ) -> APIClient {
    @Sendable func request(
      _ route: Route, signed: Bool, headers: [String: String] = [:], body: Data? = nil
    )
      async throws(TransportError) -> HTTPRequest
    {
      var headers = headers
      if signed {
        guard let token = await token() else { throw .api(.unauthorized) }
        headers[Routes.authorizationHeader] = Routes.bearerPrefix + token
      }
      return HTTPRequest(method: route.method, path: route.path, headers: headers, body: body)
    }

    @Sendable func json<Body: Encodable & Sendable>(
      _ route: Route, signed: Bool, body: Body
    ) async throws(TransportError) -> HTTPRequest {
      let unsigned = try HTTPRequest.json(route.method, path: route.path, body: body)
      return try await request(
        route, signed: signed, headers: unsigned.headers, body: unsigned.body)
    }

    @Sendable func riddleRoute(_ route: Route, _ id: RiddleId) -> Route {
      Route(route.method, route.path.replacingOccurrences(of: ":id", with: id.rawValue))
    }

    return APIClient(
      authChallenge: { () async throws(TransportError) in
        try await http.perform(
          try await request(Routes.authChallenge, signed: false), as: AuthChallengeResponse.self)
      },
      signInWithApple: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.authApple, signed: false, body: body), as: SessionResponse.self)
      },
      signOut: { () async throws(TransportError) in
        try await http.performEmpty(try await request(Routes.authSignOut, signed: true))
      },
      registerPushToken: { (body) async throws(TransportError) in
        try await http.performEmpty(
          try await json(Routes.registerPushToken, signed: true, body: body))
      },
      createInvite: { () async throws(TransportError) in
        try await http.perform(
          try await request(Routes.createInvite, signed: true), as: CreateInviteResponse.self)
      },
      claimInvite: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.claimInvite, signed: true, body: body),
          as: ClaimInviteResponse.self)
      },
      unpair: { () async throws(TransportError) in
        try await http.performEmpty(try await request(Routes.unpair, signed: true))
      },
      blockPartner: { () async throws(TransportError) in
        try await http.performEmpty(try await request(Routes.blockPartner, signed: true))
      },
      reportPartner: { (body) async throws(TransportError) in
        try await http.performEmpty(try await json(Routes.reportPartner, signed: true, body: body))
      },
      uploadImage: { (image) async throws(TransportError) in
        try await http.perform(
          try await request(
            Routes.uploadImage, signed: true,
            headers: ["Content-Type": APIClient.contentType(ofImage: image)], body: image),
          as: UploadImageResponse.self)
      },
      downloadImage: { (key) async throws(TransportError) in
        try await http.performRaw(
          try await request(Routes.downloadImage(key: key.rawValue), signed: true))
      },
      sendNote: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.sendNote, signed: true, body: body), as: SendNoteResponse.self)
      },
      listNotes: { (after) async throws(TransportError) in
        var route = Routes.listNotes
        if let after { route = Route(route.method, route.path + "?after=\(after)") }
        return try await http.perform(
          try await request(route, signed: true), as: ListNotesResponse.self)
      },
      flags: { () async throws(TransportError) in
        try await http.perform(
          try await request(Routes.getFlags, signed: true), as: FlagsResponse.self)
      },
      status: { () async throws(TransportError) in
        try await http.perform(
          try await request(Routes.getStatus, signed: false), as: StatusResponse.self)
      },
      reportEvents: { (events) async throws(TransportError) in
        try await http.performEmpty(
          try await json(
            Routes.reportEvents, signed: true, body: ReportEventsRequest(events: events)))
      },
      signInAnonymously: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.authAnonymous, signed: false, body: body),
          as: SessionResponse.self)
      },
      linkApple: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.authAppleLink, signed: true, body: body),
          as: AccountResponse.self)
      },
      account: { () async throws(TransportError) in
        try await http.perform(
          try await request(Routes.getAccount, signed: true), as: AccountResponse.self)
      },
      deleteAccount: { (body) async throws(TransportError) in
        try await http.performEmpty(try await json(Routes.deleteAccount, signed: true, body: body))
      },
      listActivity: { (before) async throws(TransportError) in
        var route = Routes.listActivity
        if let before,
          let cursor = before.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed)
        {
          route = Route(route.method, route.path + "?before=\(cursor)")
        }
        return try await http.perform(
          try await request(route, signed: true), as: ActivityResponse.self)
      },
      markActivityRead: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.markActivityRead, signed: true, body: body),
          as: ActivityUnreadResponse.self)
      },
      react: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.react, signed: true, body: body), as: ReactResponse.self)
      },
      listReactions: { (after) async throws(TransportError) in
        let route = Route(
          Routes.listReactions.method, Routes.listReactions.path + "?after=\(after)")
        return try await http.perform(
          try await request(route, signed: true), as: ListReactionsResponse.self)
      },
      listInks: { () async throws(TransportError) in
        try await http.perform(
          try await request(Routes.listInks, signed: true), as: InksResponse.self)
      },
      getCoins: { (after) async throws(TransportError) in
        var path = Routes.getCoins.path
        if let after, let query = after.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        {
          path += "?after=\(query)"
        }
        return try await http.perform(
          try await request(Route(Routes.getCoins.method, path), signed: true),
          as: CoinsResponse.self)
      },
      buyItem: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.buyItem, signed: true, body: body), as: BuyResponse.self)
      },
      pair: { () async throws(TransportError) in
        try await http.perform(
          try await request(Routes.getPair, signed: true), as: PairResponse.self)
      },
      shop: { () async throws(TransportError) in
        try await http.perform(
          try await request(Routes.getShop, signed: true), as: ShopResponse.self)
      },
      placeOrder: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.placeOrder, signed: true, body: body), as: OrderResponse.self)
      },
      setWish: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.setWish, signed: true, body: body), as: ShopResponse.self)
      },
      openGift: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.openGift, signed: true, body: body), as: OpenGiftResponse.self)
      },
      claimBonus: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.claimBonus, signed: true, body: body),
          as: ClaimBonusResponse.self)
      },
      earnCoins: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.earnCoins, signed: true, body: body), as: EarnResponse.self)
      },
      gifts: { () async throws(TransportError) in
        try await http.perform(
          try await request(Routes.getGifts, signed: true), as: GiftsResponse.self)
      },
      saveGiftWish: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.saveGiftWish, signed: true, body: body), as: GiftsResponse.self)
      },
      deleteGiftWish: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.deleteGiftWish, signed: true, body: body), as: GiftsResponse.self)
      },
      setGiftPlan: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.setGiftPlan, signed: true, body: body), as: GiftsResponse.self)
      },
      markGiftReceived: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.markGiftReceived, signed: true, body: body),
          as: GiftsResponse.self)
      },
      saveLoves: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.saveLoves, signed: true, body: body), as: GiftsResponse.self)
      },
      lists: { () async throws(TransportError) in
        try await http.perform(
          try await request(Routes.getLists, signed: true), as: ListsResponse.self)
      },
      changeList: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.changeList, signed: true, body: body), as: ListsResponse.self)
      },
      searchTitles: { (query, language) async throws(TransportError) in
        let route = Route(
          Routes.searchTitles.method,
          Routes.searchTitles.path + "?" + queryString(["q": query, "lang": language]))
        return try await http.perform(
          try await request(route, signed: true), as: TitleSearchResponse.self)
      },
      title: { (kind, tmdb, country, language) async throws(TransportError) in
        let path = Routes.getTitle.path
          .replacingOccurrences(of: ":kind", with: kind.rawValue)
          .replacingOccurrences(of: ":tmdb", with: String(tmdb))
        let route = Route(
          Routes.getTitle.method,
          path + "?" + queryString(["country": country, "lang": language]))
        return try await http.perform(
          try await request(route, signed: true), as: TitleDetails.self)
      },
      titleRecommendations: { (seeds, language) async throws(TransportError) in
        let ids = seeds.prefix(5).map { "\($0.kind.rawValue):\($0.tmdb)" }.joined(separator: ",")
        let route = Route(
          Routes.titleRecommendations.method,
          Routes.titleRecommendations.path + "?" + queryString(["ids": ids, "lang": language]))
        return try await http.perform(
          try await request(route, signed: true), as: TitleSearchResponse.self)
      },
      pickTonight: { () async throws(TransportError) in
        try await http.perform(
          try await request(Routes.getPickTonight, signed: true), as: PickTonightResponse.self)
      },
      swipePickTonight: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.swipePickTonight, signed: true, body: body),
          as: PickTonightResponse.self)
      },
      guess: { () async throws(TransportError) in
        try await http.perform(
          try await request(Routes.getGuess, signed: true), as: GuessResponse.self)
      },
      answerGuess: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.answerGuess, signed: true, body: body), as: GuessResponse.self)
      },
      guessCatalog: { () async throws(TransportError) in
        // The route is cached for an hour; a phone that needs a newer catalog asks the server
        // whether its copy is still current, which costs a 304 when it is.
        try await http.perform(
          try await request(
            Routes.getGuessCatalog, signed: false, headers: ["Cache-Control": "no-cache"]),
          as: GuessCatalogResponse.self)
      },
      riddles: { () async throws(TransportError) in
        try await http.perform(
          try await request(Routes.getRiddles, signed: true), as: RiddlesResponse.self)
      },
      sendRiddle: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.sendRiddle, signed: true, body: body), as: Riddle.self)
      },
      guessRiddle: { (id, key, guess) async throws(TransportError) in
        try await http.perform(
          try await json(
            riddleRoute(Routes.guessRiddle, id), signed: true,
            body: GuessRiddleRequest(key: key, guess: guess)),
          as: GuessRiddleResponse.self)
      },
      hintRiddle: { (id) async throws(TransportError) in
        try await http.perform(
          try await request(riddleRoute(Routes.hintRiddle, id), signed: true), as: Riddle.self)
      },
      giveUpRiddle: { (id) async throws(TransportError) in
        try await http.perform(
          try await request(riddleRoute(Routes.giveUpRiddle, id), signed: true), as: Riddle.self)
      },
      setMood: { (body) async throws(TransportError) in
        try await http.perform(
          try await json(Routes.setMood, signed: true, body: body), as: PartnerCheckIn.self)
      },
      demoPartner: { () async throws(TransportError) in
        try await http.perform(
          try await request(Routes.getDemoPartner, signed: true), as: DemoPartnerResponse.self)
      },
      createDemoPartner: { () async throws(TransportError) in
        try await http.perform(
          try await request(Routes.createDemoPartner, signed: true), as: PairResponse.self)
      },
      removeDemoPartner: { () async throws(TransportError) in
        try await http.performEmpty(try await request(Routes.removeDemoPartner, signed: true))
      },
      dateCatalog: { () async throws(TransportError) in
        try await http.perform(
          try await request(Routes.getDateCatalog, signed: false), as: DateCatalogResponse.self)
      })
  }
}

/// `name=value` pairs joined with `&`, in name order, each value escaped.
private func queryString(_ values: [String: String]) -> String {
  values.sorted { $0.key < $1.key }
    .map { name, value in
      "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? "")"
    }
    .joined(separator: "&")
}

extension CharacterSet {
  /// What may stand unescaped in a query value: `&`, `=` and `+` are taken out of the query set.
  fileprivate static let urlQueryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(
    CharacterSet(charactersIn: "&=+"))
}
