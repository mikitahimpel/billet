import Foundation
import Wire

/// Every Who knows who question, as `GET /v1/guess/catalog` sends it. The build ships the server's catalog file
/// (`packages/backend/guess/src/question-catalog.json`), and the app keeps the latest one the server sent in the app
/// group.
enum GuessCatalog {
    static let file = "GuessCatalog.json"

    static var bundled: GuessCatalogResponse? {
        guard let url = Bundle.main.url(forResource: "question-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GuessCatalogResponse.self, from: data)
    }

    static var saved: GuessCatalogResponse? { SharedFile.read(GuessCatalogResponse.self, from: file) }

    static var current: GuessCatalogResponse? { saved ?? bundled }
}
