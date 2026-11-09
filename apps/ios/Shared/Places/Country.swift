import Foundation

/// The 195 countries a pair can go to: the UN's 193 members, the Holy See and Palestine, as ISO 3166-1 alpha-2
/// codes. Names come from the phone's locale, so none are bundled.
public nonisolated enum Country {
    public enum Region: String, CaseIterable, Sendable {
        case africa, americas, asia, europe, oceania

        public var title: String {
            switch self {
            case .africa: "Africa"
            case .americas: "Americas"
            case .asia: "Asia"
            case .europe: "Europe"
            case .oceania: "Oceania"
            }
        }

        fileprivate var codes: String {
            switch self {
            case .africa:
                "DZ AO BJ BW BF BI CV CM CF TD KM CG CD CI DJ EG GQ ER SZ ET GA GM GH GN GW KE LS LR LY MG MW ML MR "
                    + "MU MA MZ NA NE NG RW ST SN SC SL SO ZA SS SD TZ TG TN UG ZM ZW"
            case .americas:
                "AG AR BS BB BZ BO BR CA CL CO CR CU DM DO EC SV GD GT GY HT HN JM MX NI PA PY PE KN LC VC SR TT US "
                    + "UY VE"
            case .asia:
                "AF AM AZ BH BD BT BN KH CN CY GE IN ID IR IQ IL JP JO KZ KW KG LA LB MY MV MN MM NP KP OM PK PS PH "
                    + "QA SA SG KR LK SY TJ TH TL TR TM AE UZ VN YE"
            case .europe:
                "AL AD AT BY BE BA BG HR CZ DK EE FI FR DE GR HU IS IE IT LV LI LT LU MT MD MC ME NL MK NO PL PT RO "
                    + "RU SM RS SK SI ES SE CH UA GB VA"
            case .oceania:
                "AU FJ KI MH FM NR NZ PW PG WS SB TO TV VU"
            }
        }
    }

    private static let regions: [String: Region] = Dictionary(uniqueKeysWithValues: Region.allCases.flatMap { region in
        region.codes.split(separator: " ").map { (String($0), region) }
    })

    public static let codes: [String] = regions.keys.sorted()
    public static var count: Int { regions.count }

    public static func isCountry(_ code: String) -> Bool { regions[code] != nil }

    public static func region(_ code: String) -> Region? { regions[code] }

    /// The country's name in `locale`, or its code when the locale has none.
    public static func name(_ code: String, locale: Locale = .current) -> String {
        locale.localizedString(forRegionCode: code) ?? code
    }

    /// The two regional indicator letters, which the system draws as the flag.
    public static func emoji(_ code: String) -> String {
        String(String.UnicodeScalarView(code.uppercased().unicodeScalars.compactMap {
            Unicode.Scalar(0x1F1E6 + $0.value - 0x41)
        }))
    }

    /// Countries whose name in `locale` or in English has a word starting with `query`, ignoring case and accents;
    /// names that start with it come first.
    public static func search(_ query: String, locale: Locale = .current) -> [String] {
        let query = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return [] }
        let english = Locale(identifier: "en")
        var leading: [String] = [], inside: [String] = []
        for code in codes {
            let names = [fold(name(code, locale: locale)), fold(name(code, locale: english))]
            if names.contains(where: { $0.hasPrefix(query) }) {
                leading.append(code)
            } else if names.contains(where: { $0.contains(" " + query) || $0.contains("-" + query) }) {
                inside.append(code)
            }
        }
        let byName = { (a: String, b: String) in
            name(a, locale: locale).localizedStandardCompare(name(b, locale: locale)) == .orderedAscending
        }
        return leading.sorted(by: byName) + inside.sorted(by: byName)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// A country or a place in one that couples go to most, offered before anything is typed.
public nonisolated struct PopularPlace: Hashable, Sendable {
    public let country: String
    /// Set for a place in the country, such as Bali.
    public var place: String?

    public init(country: String, place: String? = nil) {
        self.country = country
        self.place = place
    }

    public static let all: [PopularPlace] = [
        .init(country: "GR"), .init(country: "TH"), .init(country: "FR"), .init(country: "ID", place: "Bali"),
        .init(country: "IT"), .init(country: "JP"), .init(country: "ES"), .init(country: "PT"),
        .init(country: "IS"), .init(country: "MX"),
    ]
}

extension ListItem {
    /// A country on a travel list, rather than a place in one or a line of text.
    public nonisolated var isCountry: Bool { !place && country.map(Country.isCountry) == true }
}

extension UsList {
    /// The countries the pair has been to, each once however many items name it; places don't count.
    public nonisolated var beenCountries: Set<String> {
        Set(items.compactMap { $0.done != nil && $0.isCountry ? $0.country : nil })
    }

    public nonisolated var wantedCountries: Set<String> {
        Set(items.compactMap { $0.done == nil && $0.isCountry ? $0.country : nil }).subtracting(beenCountries)
    }

    /// "7 of 195 countries together · 4%".
    public nonisolated var travelSummary: (been: Int, percent: Int) {
        let been = beenCountries.count
        return (been, Int((Double(been) / Double(Country.count) * 100).rounded()))
    }
}

/// A month the pair went somewhere, kept as `2026-10`.
public nonisolated struct TravelMonth: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public init?(_ text: String) {
        let parts = text.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else {
            return nil
        }
        self.init(year: year, month: month)
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 2000, month: parts.month ?? 1)
    }

    public var text: String { String(format: "%04d-%02d", year, month) }

    /// "October 2026", in the phone's language.
    public func formatted(calendar: Calendar = .current) -> String {
        let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
        return date.formatted(.dateTime.month(.wide).year())
    }

    public static func < (a: TravelMonth, b: TravelMonth) -> Bool { (a.year, a.month) < (b.year, b.month) }
}
