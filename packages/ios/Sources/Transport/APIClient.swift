import Foundation
import Wire

/// What the app asks of the backend, one closure per route. Tests pass fakes.
///
/// ``live(http:token:)`` builds the requests from ``Routes`` and signs them with the session token.
public struct APIClient: Sendable {
  public var authChallenge: @Sendable () async throws(TransportError) -> AuthChallengeResponse
  public var signInWithApple:
    @Sendable (SignInWithAppleRequest) async throws(TransportError) -> SessionResponse
  public var signOut: @Sendable () async throws(TransportError) -> Void
  public var registerPushToken:
    @Sendable (RegisterPushTokenRequest) async throws(TransportError) -> Void
  public var createInvite: @Sendable () async throws(TransportError) -> CreateInviteResponse
  public var claimInvite:
    @Sendable (ClaimInviteRequest) async throws(TransportError) -> ClaimInviteResponse
  public var unpair: @Sendable () async throws(TransportError) -> Void
  public var uploadImage: @Sendable (Data) async throws(TransportError) -> UploadImageResponse
  public var downloadImage: @Sendable (MediaKey) async throws(TransportError) -> Data
  public var sendNote: @Sendable (SendNoteRequest) async throws(TransportError) -> SendNoteResponse
  /// One page of history after `seq`, oldest first.
  public var listNotes: @Sendable (_ after: Int?) async throws(TransportError) -> ListNotesResponse
  /// The test variants the server has given this pair. Empty without a partner.
  public var flags: @Sendable () async throws(TransportError) -> FlagsResponse
  /// Maintenance, the oldest build that may run, and a notice. Needs no session.
  public var status: @Sendable () async throws(TransportError) -> StatusResponse
  /// Counts a few named things the app did. Names only; the server stamps the time.
  public var reportEvents:
    @Sendable (_ events: [ClientEventName]) async throws(TransportError) -> Void

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
      @escaping @Sendable (_ events: [ClientEventName]) async throws(TransportError) -> Void
  ) {
    self.authChallenge = authChallenge
    self.signInWithApple = signInWithApple
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
      uploadImage: { (png) async throws(TransportError) in
        try await http.perform(
          try await request(
            Routes.uploadImage, signed: true, headers: ["Content-Type": "image/png"], body: png),
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
