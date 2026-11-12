import Foundation
import Wire

/// "2016 · Movie · 1 h 56 min · ★ 7.6", leaving out what TMDB doesn't know.
enum TitleCaption {
  static func of(_ title: TitleSummary, genre: String? = nil) -> String {
    var parts: [String] = []
    if let year = title.year { parts.append(String(year)) }
    if let genre { parts.append(genre) } else { parts.append(kind(title.kind)) }
    if let runtime = title.runtime { parts.append(minutes(runtime)) }
    if let seasons = title.seasons {
      parts.append(seasons == 1 ? "1 season" : "\(seasons) seasons")
    }
    if let rating = title.rating {
      parts.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))")
    }
    return parts.joined(separator: " · ")
  }

  static func kind(_ kind: ListMediaKind) -> String {
    switch kind {
    case .movie: "Movie"
    case .tv: "Show"
    }
  }

  static func minutes(_ minutes: Int) -> String {
    minutes < 60
      ? "\(minutes) min"
      : minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
  }
}
