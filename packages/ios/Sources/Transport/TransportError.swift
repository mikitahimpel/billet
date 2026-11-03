import Wire

public enum TransportError: Error, Equatable, Sendable {
  /// The request never produced a response.
  case network(String)
  /// The server answered with a contract error.
  case api(ApiError)
  /// The server answered with an unsuccessful status and no contract error.
  case status(Int)
  /// The service is down for maintenance: a 503 whose body is a contract `MaintenanceResponse`,
  /// with the status it carried. Reads still work; a write can be tried again once it is over.
  case maintenance(AppStatus)
  case encoding
  case decoding
}
