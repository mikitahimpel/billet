import Foundation
import OurioShared
import Persistence
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

    /// The saved catalog, plus any bundled question it lacks: a saved copy from before an app update can be older than
    /// the bundle, and a round may ask a question only the bundle has.
    static var current: GuessCatalogResponse? {
        guard let saved else { return bundled }
        guard let bundled else { return saved }
        let known = Set(saved.questions.map(\.id))
        return GuessCatalogResponse(version: saved.version,
                                    questions: saved.questions + bundled.questions.filter { !known.contains($0.id) })
    }
}
