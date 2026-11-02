import Foundation
import Wire

/// The HTTP dependency: one closure that performs a request. Tests pass a fake.
public struct HTTPService: Sendable {
  public var send: @Sendable (HTTPRequest) async throws(TransportError) -> HTTPResponse

  public init(
    send: @escaping @Sendable (HTTPRequest) async throws(TransportError) -> HTTPResponse
  ) {
    self.send = send
  }

  /// Sends `request` and decodes a successful body as `Response`.
  ///
  /// A non-2xx answer becomes ``TransportError/api(_:)`` when the body is a contract `ApiError`,
  /// and ``TransportError/status(_:)`` otherwise.
  public func perform<Response: Decodable & Sendable>(
    _ request: HTTPRequest, as type: Response.Type
  ) async throws(TransportError) -> Response {
    let body = try await performRaw(request)
    do {
      return try JSONDecoder().decode(Response.self, from: body)
    } catch {
      throw .decoding
    }
  }

  /// Sends `request` and ignores a successful body, for the routes that answer 204.
  public func performEmpty(_ request: HTTPRequest) async throws(TransportError) {
    _ = try await performRaw(request)
  }

  /// Sends `request` and returns a successful body as it came, for the routes that answer bytes.
  public func performRaw(_ request: HTTPRequest) async throws(TransportError) -> Data {
    let response = try await send(request)
    if (200..<300).contains(response.status) {
      return response.body
    }
    if let apiError = try? JSONDecoder().decode(ApiError.self, from: response.body) {
      throw .api(apiError)
    }
    throw .status(response.status)
  }
}

extension HTTPService {
  /// The live service over `URLSession`, resolving each path against `baseURL`.
  public static func urlSession(baseURL: URL, session: URLSession) -> HTTPService {
    HTTPService { request throws(TransportError) in
      // `URL(string:relativeTo:)` lets an absolute path replace the base's host, which would send
      // whatever headers the request carries to another server. A path is a path only.
      guard let parts = URLComponents(string: request.path), parts.scheme == nil,
        parts.host == nil, let url = URL(string: request.path, relativeTo: baseURL)
      else {
        throw .network("invalid path \(request.path)")
      }
      var urlRequest = URLRequest(url: url)
      urlRequest.httpMethod = request.method.rawValue
      urlRequest.httpBody = request.body
      for (name, value) in request.headers {
        urlRequest.setValue(value, forHTTPHeaderField: name)
      }
      let result: (Data, URLResponse)
      do {
        result = try await session.data(for: urlRequest)
      } catch {
        throw .network(error.localizedDescription)
      }
      guard let http = result.1 as? HTTPURLResponse else {
        throw .network("response was not HTTP")
      }
      return HTTPResponse(status: http.statusCode, body: result.0)
    }
  }
}
