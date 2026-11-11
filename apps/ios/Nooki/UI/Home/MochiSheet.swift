import Design
import Pet
import RoomInterface
import SwiftUI

/// Mochi's sheet, top to bottom: how she is right now, her four needs with the care each takes, her day so far and
/// what kind of cat she is. It draws what it is given, so the gallery shows its parts with a fixed cat.
struct MochiSheetContent<Portrait: View, ExtraCare: View>: View {
    let name: String
    let status: CatStatus
    let level: Int
    /// The way to the next level, 0...1.
    let progress: Double
    let days: Int
    var care: (NeedCare) -> Void
    @ViewBuilder var portrait: Portrait
    /// The care no need's tile offers, under the tiles.
    @ViewBuilder var extraCare: ExtraCare

    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            MochiHero(mood: status.needs?.moodLine(name: name) ?? "Settling in", level: level, progress: progress,
                      days: days) { portrait }
            VStack(alignment: .leading, spacing: Space.m) {
                NeedGrid(name: name, needs: status.needs, asleep: status.about?.asleep ?? false, care: care)
                extraCare
            }
            if let about = status.about {
                MochiDay(name: name, doing: status.doing, moments: about.day)
                MochiNature(about: about)
            }
        }
    }
}

/// The sheet's one warm card: her portrait, her mood in a line, how long she has been with the couple, and her level
/// as a bar with the pets still to go.
struct MochiHero<Portrait: View>: View {
    let mood: String
    let level: Int
    let progress: Double
    let days: Int
    @ViewBuilder var portrait: Portrait
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Card(warm: true) {
            VStack(alignment: .leading, spacing: Space.l) {
                // At accessibility sizes her words take the card's whole width under her portrait.
                if dynamicTypeSize.isAccessibilitySize {
                    portrait
                    words
                } else {
                    HStack(spacing: Space.l) {
                        portrait
                        words
                    }
                }
                levelBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Past this the mood line alone fills an SE's screen and pushes her needs below the fold.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(mood)
                .font(.ourioValue)
                .foregroundStyle(Ink.text)
                .contentTransition(.opacity)
                .fixedSize(horizontal: false, vertical: true)
            Chip("With you two for \(days == 1 ? "1 day" : "\(days) days")", symbol: "heart.fill",
                 style: .tinted(.blushPink))
        }
    }

    private var levelBar: some View {
        VStack(spacing: Space.xs) {
            MeterBar(value: progress)
            HStack(alignment: .firstTextBaseline) {
                Text("Lv. \(level)")
                    .font(.ourioMicro)
                    .foregroundStyle(Ink.text)
                    .contentTransition(.numericText())
                Spacer(minLength: Space.s)
                Text(CatCare.towardNext(level: level, progress: progress))
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.textSecondary)
                    .contentTransition(.opacity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(level)")
        .accessibilityValue("\(PetNeed.percent(progress)) percent to level \(level + 1)")
    }
}

/// Her day so far as a strip of moments, with what she is doing now beside the title.
struct MochiDay: View {
    let name: String
    let doing: String
    let moments: [CatDayMoment]
    /// The zone and locale her day's times are told in.
    var zone: TimeZone = .current
    var locale: Locale = .current

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("\(name)'s day", symbol: "sun.max.fill") { Text("Now: \(doing.lowercased())") }
            if moments.isEmpty {
                Card {
                    Text("Her day is only starting. What she gets up to shows here.")
                        .font(.ourioCallout)
                        .foregroundStyle(Ink.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                MomentStrip(moments.map { moment in
                    StripMoment(id: moment.id, symbol: moment.kind.symbol, tint: moment.kind.tint,
                                title: moment.kind.title, time: moment.time(in: zone, locale: locale))
                })
            }
        }
    }
}

/// What kind of cat she is: her type and its line, her six traits as bars, and her favourite spot.
struct MochiNature: View {
    let about: CatAbout

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("About her", symbol: "pawprint.fill")
            Card {
                VStack(alignment: .leading, spacing: Space.l) {
                    CardHeader(about.temperament.title, detail: about.temperament.line,
                               symbol: about.temperament.symbol, opens: false)
                    ItemGrid {
                        ForEach(CatPersonality.Trait.allCases, id: \.self) { trait in
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text(trait.title)
                                    .font(.ourioCaption)
                                    .foregroundStyle(Ink.textSecondary)
                                // One quiet tone: a tint here would read as one of her needs.
                                MeterBar(value: about.personality[trait], tint: Ink.textSecondary)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(trait.title)
                            .accessibilityValue("\(PetNeed.percent(about.personality[trait])) percent")
                        }
                    }
                    if let spot = about.favourite?.spotName {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                                spotLabel
                                Spacer(minLength: Space.s)
                                spotName(spot)
                            }
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                spotLabel
                                spotName(spot)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var spotLabel: some View {
        Label("Favourite spot", systemImage: "mappin.and.ellipse")
            .font(.ourioCaption)
            .foregroundStyle(Ink.textSecondary)
    }

    private func spotName(_ spot: String) -> some View {
        Text(spot)
            .font(.ourioCallout.weight(.semibold))
            .foregroundStyle(Ink.text)
    }
}
