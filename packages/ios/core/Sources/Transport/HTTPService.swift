import Foundation
import Wire

public struct HTTPService: Sendable {
  public var send: @Sendable (HTTPRequest) async throws(TransportError) -> HTTPResponse

  public init(
    send: @escaping @Sendable (HTTPRequest) async throws(TransportError) -> HTTPResponse
  ) {
    self.send = send
  }

  /// A non-2xx answer becomes ``TransportError/maintenance(_:)`` for the maintenance 503,
  /// ``TransportError/api(_:)`` for a contract `ApiError` body, else ``TransportError/status(_:)``.
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

  /// For the routes that answer 204.
  public func performEmpty(_ request: HTTPRequest) async throws(TransportError) {
    _ = try await performRaw(request)
  }

  /// For the routes that answer bytes.
  public func performRaw(_ request: HTTPRequest) async throws(TransportError) -> Data {
    let response = try await send(request)
    if (200..<300).contains(response.status) {
      return response.body
    }
    if let status = response.maintenance {
      throw .maintenance(status)
    }
    if let apiError = try? JSONDecoder().decode(ApiError.self, from: response.body) {
      throw .api(apiError)
    }
    throw .status(response.status)
  }
}

extension HTTPService {
  /// Tells `report` of each maintenance 503 before the caller sees the failure, so one place
  /// learns of maintenance whichever request met it.
  public func reportingMaintenance(
    to report: @escaping @Sendable (AppStatus) async -> Void
  ) -> HTTPService {
    let send = send
    return HTTPService { (request: HTTPRequest) async throws(TransportError) -> HTTPResponse in
      let response = try await send(request)
      if let status = response.maintenance { await report(status) }
      return response
    }
  }
}

extension HTTPResponse {
  /// The status a maintenance 503 carries, or `nil` for any other answer.
  public var maintenance: AppStatus? {
    guard status == 503 else { return nil }
    return (try? JSONDecoder().decode(MaintenanceResponse.self, from: body))?.status
  }
}

extension HTTPService {
  /// `headers` go on every request; a header the request sets itself wins.
  public static func urlSession(
    baseURL: URL, session: URLSession, headers: [String: String] = [:]
  ) -> HTTPService {
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
      for (name, value) in headers {
        urlRequest.setValue(value, forHTTPHeaderField: name)
      }
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
