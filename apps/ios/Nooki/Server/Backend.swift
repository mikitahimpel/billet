import FeatureOnboarding
import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import Persistence
import Transport
import UsInterface

/// The billet server this build talks to: the API client, the saved session and the anonymous account key in the
/// iCloud Keychain. The host comes from the build (`BILLET_API_HOST`, Info.plist `BilletAPIHost`), never the
/// repository; a build without one has no backend and keeps everything on the phone.
struct Backend {
    let baseURL: URL
    let api: APIClient
    let accounts: AccountStore
    let keys: AccountKeyStore
    var onboarding: OnboardingClient = .offline
    var catEvents: CatEventsClient = .offline
    var streak = StreakRemote(load: { .offline }, record: { _ in .offline }, restore: { .offline })
    /// The coin pack routes; never reached in a build without a server.
    var purchases = PurchasesClient(
        purchase: { (_) async throws(TransportError) in throw .network("offline") },
        mockPurchase: { (_) async throws(TransportError) in throw .network("offline") },
        stamps: { () async throws(TransportError) in throw .network("offline") })

    static let infoKey = "BilletAPIHost"
    /// The Keychain service of the session token and the account key; the same as billet's first app, so a phone
    /// that had it signs in to the same account.
    static let keychainService = "com.ourio.app"

    /// `https://<host>`, or `http` for a server on this Mac. Nil for an empty or unusable host.
    nonisolated static func baseURL(host: String?) -> URL? {
        guard let host = host?.trimmingCharacters(in: .whitespaces), !host.isEmpty, !host.contains("/") else {
            return nil
        }
        let local = host.hasPrefix("localhost") || host.hasPrefix("127.0.0.1")
        guard let url = URL(string: "\(local ? "http" : "https")://\(host)"), url.host() != nil else { return nil }
        return url
    }

    static func live(info: [String: Any]? = Bundle.main.infoDictionary) -> Backend? {
        guard let baseURL = baseURL(host: info?[infoKey] as? String) else { return nil }
        let tokens = SessionTokenStore.keychain(client: .security, service: keychainService, accessGroup: nil)
        let storage = (try? AppGroupStorage.appGroup(identifier: AppGroupStorage.billetIdentifier))
            ?? .directory(URL.applicationSupportDirectory.appending(path: "Account"))
        let accounts = AccountStore.live(tokens: tokens, storage: storage)
        let http = HTTPService.urlSession(baseURL: baseURL, session: .shared, headers: ClientInfo.current().headers)
        let token: @Sendable () async -> String? = { (try? accounts.load())?.token }
        let api = APIClient.live(http: http, token: token)
        let keys = AccountKeyStore.keychain(client: .security, service: keychainService)
        return Backend(
            baseURL: baseURL, api: api, accounts: accounts, keys: keys,
            onboarding: .live(http: http, token: token), catEvents: .live(http: http, token: token),
            streak: .live(http: http, token: token, you: { (try? accounts.load())?.record.userID }), purchases: .live(http: http, caller: .session(token)))
    }
}
