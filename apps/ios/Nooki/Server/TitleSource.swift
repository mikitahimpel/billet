import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import Transport
import UsInterface
import Wire

/// Films and shows from TMDB through the billet server, for the To watch list, in the phone's language and with
/// where to watch them in the phone's region.
struct TitleSource: Sendable {
    var search: @Sendable (_ query: String) async throws(TransportError) -> [TitleSummary]
    var details: @Sendable (_ kind: ListMediaKind, _ tmdb: Int) async throws(TransportError) -> TitleDetails
    /// What TMDB recommends to those who liked `seeds`, the first 5 of them.
    var recommendations: @Sendable (_ seeds: [ListMedia]) async throws(TransportError) -> [TitleSummary]

    static func live(_ api: APIClient, locale: Locale = .current) -> TitleSource {
        let region = locale.region?.identifier
        let country = region.flatMap { $0.count == 2 ? $0 : nil } ?? "US"
        let language = Self.language(of: locale, country: region)
        return TitleSource(
            search: { (query) async throws(TransportError) in try await api.searchTitles(query, language).results },
            details: { (kind, tmdb) async throws(TransportError) in
                try await api.title(kind, tmdb, country, language)
            },
            recommendations: { (seeds) async throws(TransportError) in
                try await api.titleRecommendations(seeds, language).results
            })
    }

    /// TMDB's tag for the phone's language, such as `pt-BR`; English when TMDB could not read it.
    static func language(of locale: Locale, country: String?) -> String {
        guard let code = locale.language.languageCode?.identifier, code.count == 2 else { return "en" }
        guard let country, country.count == 2, country.allSatisfy(\.isUppercase) else { return code }
        return "\(code)-\(country)"
    }
}

/// TMDB's image server. Posters load straight from it, never through billet, and `URLCache` keeps them.
enum TmdbImage {
    enum Size: String {
        /// The poster grid.
        case grid = "w342"
        /// The card's backdrop and poster.
        case card = "w780"
        /// Search results and provider logos.
        case small = "w154"
    }

    static func url(_ path: String?, _ size: Size) -> URL? {
        guard let path, path.hasPrefix("/") else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size.rawValue)\(path)")
    }
}
