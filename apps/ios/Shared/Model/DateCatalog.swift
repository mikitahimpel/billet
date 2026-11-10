import Foundation
import Persistence

/// Every date idea, as `GET /v1/dates/catalog` sends it. The build ships the server's catalog file
/// (`packages/backend/dates/src/date-catalog.json`), and the app keeps the latest one the server sent in the app
/// group, where the widgets read it too.
public nonisolated struct DateCatalog: Codable, Hashable, Sendable {
    public let version: String
    public let ideas: [DateIdea]

    public init(version: String, ideas: [DateIdea]) {
        self.version = version
        self.ideas = ideas
    }

    public static let file = "DateCatalog.json"

    public static var bundled: DateCatalog? {
        guard let url = Bundle.main.url(forResource: "date-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DateCatalog.self, from: data)
    }

    public static var saved: DateCatalog? { SharedFile.read(DateCatalog.self, from: file) }
}
