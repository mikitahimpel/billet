import Foundation
import Wire

/// What the app asks of the backend, one closure per route. Tests pass fakes.
///
/// ``live(http:token:)`` builds the requests from ``Routes`` and signs them with the session token.
public struct APIClient: Sendable {
  public var authChallenge: @Sendable () async throws(TransportError) -> AuthChallengeResponse
  /// Signs in with the account key, opening the account the first time the key is seen.
  public var signInAnonymously:
    @Sendable (SignInAnonymouslyRequest) async throws(TransportError) -> SessionResponse
  public var signInWithApple:
    @Sendable (SignInWithAppleRequest) async throws(TransportError) -> SessionResponse
  /// Links the signed-in account to an Apple ID. `.api(.appleIdInUse)` if another account has it.
  public var linkApple:
    @Sendable (SignInWithAppleRequest) async throws(TransportError) -> AccountResponse
  public var account: @Sendable () async throws(TransportError) -> AccountResponse
  /// Deletes the account and everything it owns. The session is gone afterwards.
  public var deleteAccount: @Sendable (DeleteAccountRequest) async throws(TransportError) -> Void
  public var signOut: @Sendable () async throws(TransportError) -> Void
  public var registerPushToken:
    @Sendable (RegisterPushTokenRequest) async throws(TransportError) -> Void
  public var createInvite: @Sendable () async throws(TransportError) -> CreateInviteResponse
  public var claimInvite:
    @Sendable (ClaimInviteRequest) async throws(TransportError) -> ClaimInviteResponse
  public var unpair: @Sendable () async throws(TransportError) -> Void
  /// A PNG drawing or a JPEG or HEIC photo, sent with the content type its bytes declare.
  public var uploadImage: @Sendable (Data) async throws(TransportError) -> UploadImageResponse
  public var downloadImage: @Sendable (MediaKey) async throws(TransportError) -> Data
  public var sendNote: @Sendable (SendNoteRequest) async throws(TransportError) -> SendNoteResponse
  /// One page of history after `seq`, oldest first.
  public var listNotes: @Sendable (_ after: Int?) async throws(TransportError) -> ListNotesResponse
  /// The test variants the server has given this pair. Empty without a partner.
  public var flags: @Sendable () async throws(TransportError) -> FlagsResponse
  /// Maintenance, the oldest build that may run, and a notice. Needs no session.
  public var status: @Sendable () async throws(TransportError) -> StatusResponse
  /// Counts a few things the app did: names, with a catalogue id or a price for some. The server
  /// stamps the time.
  public var reportEvents: @Sendable (_ events: [ClientEvent]) async throws(TransportError) -> Void
  /// One page of the pair's activity, newest first, from `before` (the previous page's `next`).
  public var listActivity:
    @Sendable (_ before: String?) async throws(TransportError) -> ActivityResponse
  /// Moves this user's read mark up to a cursor and answers the unread count left.
  public var markActivityRead:
    @Sendable (MarkActivityReadRequest) async throws(TransportError) -> ActivityUnreadResponse
  /// Sets or takes back this user's reaction to one of the partner's photos.
  public var react: @Sendable (ReactRequest) async throws(TransportError) -> ReactResponse
  /// Every reaction change after `rev`, oldest first.
  public var listReactions:
    @Sendable (_ after: Int) async throws(TransportError) -> ListReactionsResponse
  /// Every ink the shop sells and the ones the pair owns.
  public var listInks: @Sendable () async throws(TransportError) -> InksResponse
  /// The pair's coin balance, as the server keeps it, and its wallet entries after the entry id
  /// `after` (from the first when nil), oldest first, a page at a time.
  public var getCoins: @Sendable (_ after: String?) async throws(TransportError) -> CoinsResponse
  /// Buys one ink at its catalog price: `.api(.notEnoughCoins)` when the balance is short,
  /// `.api(.alreadyOwned)` when the pair has it. A retry with the same `id` buys nothing twice.
  public var buyItem: @Sendable (BuyRequest) async throws(TransportError) -> BuyResponse
  /// The caller's pair and both members, the caller first. `.api(.notFound)` while unpaired.
  public var pair: @Sendable () async throws(TransportError) -> PairResponse
  /// What the pair has: balance, inks, room pieces and wishlist.
  public var shop: @Sendable () async throws(TransportError) -> ShopResponse
  /// Buys one offer at the server's price. Repeat the request's `id` on a retry.
  public var placeOrder: @Sendable (OrderRequest) async throws(TransportError) -> OrderResponse
  public var setWish: @Sendable (WishRequest) async throws(TransportError) -> ShopResponse
  /// Opens the day's gift, once a day for the pair. The partner's open answers with the first.
  public var openGift: @Sendable (OpenGiftRequest) async throws(TransportError) -> OpenGiftResponse
  /// Collects a complete collection's bonus, once. `.api(.collectionIncomplete)` while a piece is
  /// missing.
  public var claimBonus:
    @Sendable (ClaimBonusRequest) async throws(TransportError) -> ClaimBonusResponse
  /// Pays something the couple did in the app, once per ref and within the day's cap.
  public var earnCoins: @Sendable (EarnRequest) async throws(TransportError) -> EarnResponse
  /// The pair's gifts as the caller may see them. `.api(.notFound)` while unpaired; every change
  /// answers the view after it, and `.api(.invalidRequest)` for a change that is not the caller's.
  public var gifts: @Sendable () async throws(TransportError) -> GiftsResponse
  public var saveGiftWish:
    @Sendable (SaveGiftWishRequest) async throws(TransportError) -> GiftsResponse
  public var deleteGiftWish:
    @Sendable (DeleteGiftWishRequest) async throws(TransportError) -> GiftsResponse
  public var setGiftPlan:
    @Sendable (SetGiftPlanRequest) async throws(TransportError) -> GiftsResponse
  public var markGiftReceived:
    @Sendable (MarkGiftReceivedRequest) async throws(TransportError) -> GiftsResponse
  public var saveLoves: @Sendable (SaveLovesRequest) async throws(TransportError) -> GiftsResponse
  /// The pair's lists. `.api(.notFound)` while unpaired; a change answers the lists after it, and
  /// `.api(.notFound)` when the list or item it names is gone.
  public var lists: @Sendable () async throws(TransportError) -> ListsResponse
  public var changeList: @Sendable (ChangeListRequest) async throws(TransportError) -> ListsResponse
  /// Films and shows on TMDB matching `query`, in `language` (`en`, `pt-BR`). `.api(.unavailable)`
  /// while TMDB is down or asks the server to slow down.
  public var searchTitles:
    @Sendable (_ query: String, _ language: String) async throws(TransportError) ->
      TitleSearchResponse
  /// One film or show, with where to watch it in `country` (ISO 3166-1 alpha-2).
  /// `.api(.notFound)` when TMDB has no such title.
  public var title:
    @Sendable (_ kind: ListMediaKind, _ tmdb: Int, _ country: String, _ language: String)
      async throws(TransportError) -> TitleDetails
  /// Films and shows TMDB recommends for those who liked `seeds` (1 to 5), in `language`.
  public var titleRecommendations:
    @Sendable (_ seeds: [ListMedia], _ language: String) async throws(TransportError) ->
      TitleSearchResponse
  /// The pair's Pick tonight session as this user sees it. `.api(.notFound)` while unpaired.
  public var pickTonight: @Sendable () async throws(TransportError) -> PickTonightResponse
  /// One Pick tonight swipe; answers the session after it, with the match it made.
  public var swipePickTonight:
    @Sendable (PickSwipeRequest) async throws(TransportError) -> PickTonightResponse
  /// Replaces this user's check-in and answers with it as stored, the note trimmed.
  /// `.api(.invalidRequest)` for a note over 80 UTF-16 code units once trimmed.
  public var setMood: @Sendable (SetMoodRequest) async throws(TransportError) -> PartnerCheckIn
  /// Dev server only: whether the caller is paired with their bot partner. `.api(.notFound)` on
  /// any other server, which has no dev tools.
  public var demoPartner: @Sendable () async throws(TransportError) -> DemoPartnerResponse
  /// Dev server only: pairs the unpaired caller with a new bot partner. `.api(.alreadyPaired)`
  /// with a partner.
  public var createDemoPartner: @Sendable () async throws(TransportError) -> PairResponse
  /// Dev server only: unpairs the caller from their bot partner and deletes it.
  public var removeDemoPartner: @Sendable () async throws(TransportError) -> Void
  /// Every date idea. Needs no session.
  public var dateCatalog: @Sendable () async throws(TransportError) -> DateCatalogResponse

  public init(
    authChallenge: @escaping @Sendable () async throws(TransportError) -> AuthChallengeResponse,
    signInWithApple:
      @escaping @Sendable (SignInWithAppleRequest) async throws(TransportError) ->
      SessionResponse,
    signOut: @escaping @Sendable () async throws(TransportError) -> Void,
    registerPushToken:
      @escaping @Sendable (RegisterPushTokenRequest) async throws(TransportError)
      -> Void,
    createInvite: @escaping @Sendable () async throws(TransportError) -> CreateInviteResponse,
    claimInvite:
      @escaping @Sendable (ClaimInviteRequest) async throws(TransportError) ->
      ClaimInviteResponse,
    unpair: @escaping @Sendable () async throws(TransportError) -> Void,
    uploadImage: @escaping @Sendable (Data) async throws(TransportError) -> UploadImageResponse,
    downloadImage: @escaping @Sendable (MediaKey) async throws(TransportError) -> Data,
    sendNote:
      @escaping @Sendable (SendNoteRequest) async throws(TransportError) ->
      SendNoteResponse,
    listNotes:
      @escaping @Sendable (_ after: Int?) async throws(TransportError) ->
      ListNotesResponse,
    flags: @escaping @Sendable () async throws(TransportError) -> FlagsResponse,
    status: @escaping @Sendable () async throws(TransportError) -> StatusResponse,
    reportEvents:
      @escaping @Sendable (_ events: [ClientEvent]) async throws(TransportError) -> Void,
    signInAnonymously:
      @escaping @Sendable (SignInAnonymouslyRequest) async throws(TransportError) ->
      SessionResponse = { (_) async throws(TransportError) in throw .network("offline") },
    linkApple:
      @escaping @Sendable (SignInWithAppleRequest) async throws(TransportError) ->
      AccountResponse = { (_) async throws(TransportError) in throw .network("offline") },
    account: @escaping @Sendable () async throws(TransportError) -> AccountResponse = {
      () async throws(TransportError) in throw .network("offline")
    },
    deleteAccount:
      @escaping @Sendable (DeleteAccountRequest) async throws(TransportError) -> Void = {
        (_) async throws(TransportError) in throw .network("offline")
      },
    listActivity:
      @escaping @Sendable (_ before: String?) async throws(TransportError) -> ActivityResponse = {
        (_) async throws(TransportError) in throw .network("offline")
      },
    markActivityRead:
      @escaping @Sendable (MarkActivityReadRequest) async throws(TransportError) ->
      ActivityUnreadResponse = { (_) async throws(TransportError) in throw .network("offline") },
    react:
      @escaping @Sendable (ReactRequest) async throws(TransportError) -> ReactResponse = {
        (_) async throws(TransportError) in throw .network("offline")
      },
    listReactions:
      @escaping @Sendable (_ after: Int) async throws(TransportError) -> ListReactionsResponse = {
        (_) async throws(TransportError) in throw .network("offline")
      },
    listInks: @escaping @Sendable () async throws(TransportError) -> InksResponse = {
      () async throws(TransportError) in throw .network("offline")
    },
    getCoins:
      @escaping @Sendable (_ after: String?) async throws(TransportError) -> CoinsResponse = {
        (_) async throws(TransportError) in throw .network("offline")
      },
    buyItem: @escaping @Sendable (BuyRequest) async throws(TransportError) -> BuyResponse = {
      (_) async throws(TransportError) in throw .network("offline")
    },
    pair: @escaping @Sendable () async throws(TransportError) -> PairResponse = {
      () async throws(TransportError) in throw .network("offline")
    },
    shop: @escaping @Sendable () async throws(TransportError) -> ShopResponse = {
      () async throws(TransportError) in throw .network("offline")
    },
    placeOrder:
      @escaping @Sendable (OrderRequest) async throws(TransportError) -> OrderResponse = {
        (_) async throws(TransportError) in throw .network("offline")
      },
    setWish:
      @escaping @Sendable (WishRequest) async throws(TransportError) -> ShopResponse = {
        (_) async throws(TransportError) in throw .network("offline")
      },
    openGift:
      @escaping @Sendable (OpenGiftRequest) async throws(TransportError) -> OpenGiftResponse = {
        (_) async throws(TransportError) in throw .network("offline")
      },
    claimBonus:
      @escaping @Sendable (ClaimBonusRequest) async throws(TransportError) -> ClaimBonusResponse =
      { (_) async throws(TransportError) in throw .network("offline") },
    earnCoins:
      @escaping @Sendable (EarnRequest) async throws(TransportError) -> EarnResponse = {
        (_) async throws(TransportError) in throw .network("offline")
      },
    gifts: @escaping @Sendable () async throws(TransportError) -> GiftsResponse = {
      () async throws(TransportError) in throw .network("offline")
    },
    saveGiftWish:
      @escaping @Sendable (SaveGiftWishRequest) async throws(TransportError) -> GiftsResponse = {
        (_) async throws(TransportError) in throw .network("offline")
      },
    deleteGiftWish:
      @escaping @Sendable (DeleteGiftWishRequest) async throws(TransportError) -> GiftsResponse = {
        (_) async throws(TransportError) in throw .network("offline")
      },
    setGiftPlan:
      @escaping @Sendable (SetGiftPlanRequest) async throws(TransportError) -> GiftsResponse = {
        (_) async throws(TransportError) in throw .network("offline")
      },
    markGiftReceived:
      @escaping @Sendable (MarkGiftReceivedRequest) async throws(TransportError) ->
      GiftsResponse = { (_) async throws(TransportError) in throw .network("offline") },
    saveLoves:
      @escaping @Sendable (SaveLovesRequest) async throws(TransportError) -> GiftsResponse = {
        (_) async throws(TransportError) in throw .network("offline")
      },
    lists: @escaping @Sendable () async throws(TransportError) -> ListsResponse = {
      () async throws(TransportError) in throw .network("offline")
    },
    changeList:
      @escaping @Sendable (ChangeListRequest) async throws(TransportError) -> ListsResponse = {
        (_) async throws(TransportError) in throw .network("offline")
      },
    searchTitles:
      @escaping @Sendable (_ query: String, _ language: String) async throws(TransportError) ->
      TitleSearchResponse = { (_, _) async throws(TransportError) in throw .network("offline") },
    title:
      @escaping @Sendable (
        _ kind: ListMediaKind, _ tmdb: Int, _ country: String, _ language: String
      )
      async throws(TransportError) -> TitleDetails = {
        (_, _, _, _) async throws(TransportError) in throw .network("offline")
      },
    titleRecommendations:
      @escaping @Sendable (_ seeds: [ListMedia], _ language: String) async throws(TransportError)
      -> TitleSearchResponse = { (_, _) async throws(TransportError) in throw .network("offline") },
    pickTonight: @escaping @Sendable () async throws(TransportError) -> PickTonightResponse = {
      () async throws(TransportError) in throw .network("offline")
    },
    swipePickTonight:
      @escaping @Sendable (PickSwipeRequest) async throws(TransportError) -> PickTonightResponse = {
        (_) async throws(TransportError) in throw .network("offline")
      },
    setMood:
      @escaping @Sendable (SetMoodRequest) async throws(TransportError) -> PartnerCheckIn = {
        (_) async throws(TransportError) in throw .network("offline")
      },
    demoPartner:
      @escaping @Sendable () async throws(TransportError) -> DemoPartnerResponse = {
        () async throws(TransportError) in throw .network("offline")
      },
    createDemoPartner: @escaping @Sendable () async throws(TransportError) -> PairResponse = {
      () async throws(TransportError) in throw .network("offline")
    },
    removeDemoPartner: @escaping @Sendable () async throws(TransportError) -> Void = {
      () async throws(TransportError) in throw .network("offline")
    },
    dateCatalog: @escaping @Sendable () async throws(TransportError) -> DateCatalogResponse = {
      () async throws(TransportError) in throw .network("offline")
    }
  ) {
    self.authChallenge = authChallenge
    self.signInAnonymously = signInAnonymously
    self.signInWithApple = signInWithApple
    self.linkApple = linkApple
    self.account = account
    self.deleteAccount = deleteAccount
    self.signOut = signOut
    self.registerPushToken = registerPushToken
    self.createInvite = createInvite
    self.claimInvite = claimInvite
    self.unpair = unpair
    self.uploadImage = uploadImage
    self.downloadImage = downloadImage
    self.sendNote = sendNote
    self.listNotes = listNotes
    self.flags = flags
    self.status = status
    self.reportEvents = reportEvents
    self.listActivity = listActivity
    self.markActivityRead = markActivityRead
    self.react = react
    self.listReactions = listReactions
    self.listInks = listInks
    self.getCoins = getCoins
    self.buyItem = buyItem
    self.pair = pair
    self.shop = shop
    self.placeOrder = placeOrder
    self.setWish = setWish
    self.openGift = openGift
    self.claimBonus = claimBonus
    self.earnCoins = earnCoins
    self.gifts = gifts
    self.saveGiftWish = saveGiftWish
    self.deleteGiftWish = deleteGiftWish
    self.setGiftPlan = setGiftPlan
    self.markGiftReceived = markGiftReceived
    self.saveLoves = saveLoves
    self.lists = lists
    self.changeList = changeList
    self.searchTitles = searchTitles
    self.title = title
    self.titleRecommendations = titleRecommendations
    self.pickTonight = pickTonight
    self.swipePickTonight = swipePickTonight
    self.setMood = setMood
    self.demoPartner = demoPartner
    self.createDemoPartner = createDemoPartner
    self.removeDemoPartner = removeDemoPartner
    self.dateCatalog = dateCatalog
  }
}

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

extension APIClient {
  /// A client whose every call fails as offline. Tests start from it and replace the calls they
  /// care about.
  public static let offline = APIClient(
    authChallenge: { () async throws(TransportError) in throw .network("offline") },
    signInWithApple: { (_) async throws(TransportError) in throw .network("offline") },
    signOut: { () async throws(TransportError) in throw .network("offline") },
    registerPushToken: { (_) async throws(TransportError) in throw .network("offline") },
    createInvite: { () async throws(TransportError) in throw .network("offline") },
    claimInvite: { (_) async throws(TransportError) in throw .network("offline") },
    unpair: { () async throws(TransportError) in throw .network("offline") },
    uploadImage: { (_) async throws(TransportError) in throw .network("offline") },
    downloadImage: { (_) async throws(TransportError) in throw .network("offline") },
    sendNote: { (_) async throws(TransportError) in throw .network("offline") },
    listNotes: { (_) async throws(TransportError) in throw .network("offline") },
    flags: { () async throws(TransportError) in throw .network("offline") },
    status: { () async throws(TransportError) in throw .network("offline") },
    reportEvents: { (_) async throws(TransportError) in throw .network("offline") })
}

extension APIClient {
  /// The MIME type an image's signature declares: JPEG, HEIC, or PNG for anything else, as the
  /// server reads the bytes themselves anyway.
  static func contentType(ofImage data: Data) -> String {
    let bytes = [UInt8](data.prefix(12))
    if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
    if bytes.count == 12, bytes[4..<8].elementsEqual(Array("ftyp".utf8)) { return "image/heic" }
    return "image/png"
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
