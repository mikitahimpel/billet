import Wire

public enum TransportError: Error, Equatable, Sendable {
  /// The request never produced a response.
  case network(String)
  /// The server answered with a contract error.
  case api(ApiError)
  /// The server answered with an unsuccessful status and no contract error.
  case status(Int)
  case encoding
  case decoding
}
