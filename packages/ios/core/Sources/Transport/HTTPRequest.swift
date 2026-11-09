import Foundation

public enum HTTPMethod: String, Sendable {
  case get = "GET"
  case post = "POST"
  case put = "PUT"
  case patch = "PATCH"
  case delete = "DELETE"
}

/// A request described as data. The contracts define payloads but no routes, so the caller
/// supplies the path.
public struct HTTPRequest: Equatable, Sendable {
  public var method: HTTPMethod
  public var path: String
  public var headers: [String: String]
  public var body: Data?

  public init(
    method: HTTPMethod, path: String, headers: [String: String] = [:], body: Data? = nil
  ) {
    self.method = method
    self.path = path
    self.headers = headers
    self.body = body
  }

  public static func json<Body: Encodable>(
    _ method: HTTPMethod, path: String, body: Body, headers: [String: String] = [:]
  ) throws(TransportError) -> HTTPRequest {
    let data: Data
    do {
      data = try JSONEncoder().encode(body)
    } catch {
      throw .encoding
    }
    var headers = headers
    headers["Content-Type"] = "application/json"
    return HTTPRequest(method: method, path: path, headers: headers, body: data)
  }
}

public struct HTTPResponse: Equatable, Sendable {
  public var status: Int
  public var body: Data

  public init(status: Int, body: Data) {
    self.status = status
    self.body = body
  }
}
