import Foundation
import Transport
import Wire

/// The two onboarding calls: the questions, and one step's answer. Signed, like every route but sign-in.
struct OnboardingClient: Sendable {
    var fetch: @Sendable () async throws(TransportError) -> OnboardingResponse
    var save: @Sendable (SaveOnboardingAnswerRequest) async throws(TransportError) -> Void

    static let offline = OnboardingClient(
        fetch: { () async throws(TransportError) in throw .network("offline") },
        save: { (_) async throws(TransportError) in throw .network("offline") })

    static func live(http: HTTPService, token: @escaping @Sendable () async -> String?) -> OnboardingClient {
        @Sendable func signed(_ request: HTTPRequest) async throws(TransportError) -> HTTPRequest {
            guard let token = await token() else { throw .api(.unauthorized) }
            var request = request
            request.headers[Routes.authorizationHeader] = Routes.bearerPrefix + token
            return request
        }
        return OnboardingClient(
            fetch: { () async throws(TransportError) in
                let route = Routes.getOnboarding
                return try await http.perform(
                    try await signed(HTTPRequest(method: route.method, path: route.path)), as: OnboardingResponse.self)
            },
            save: { (body) async throws(TransportError) in
                let route = Routes.saveOnboardingAnswer
                try await http.performEmpty(
                    try await signed(try HTTPRequest.json(route.method, path: route.path, body: body)))
            })
    }
}

/// The questions the app ships, for a phone that is offline or has no server.
nonisolated enum BundledOnboarding {
    static func load(from bundle: Bundle = .main) -> OnboardingResponse {
        guard let url = bundle.url(forResource: "Onboarding", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let response = try? JSONDecoder().decode(OnboardingResponse.self, from: data)
        else { return OnboardingResponse(version: "bundled", steps: []) }
        return response
    }
}
