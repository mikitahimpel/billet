/// `GET /v1/status`, which needs no session.
public struct StatusResponse: Codable, Hashable, Sendable {
  public let status: AppStatus

  public init(status: AppStatus) {
    self.status = status
  }
}
