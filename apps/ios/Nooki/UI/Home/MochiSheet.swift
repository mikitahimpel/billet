import Design
import Pet
import RoomInterface
import SwiftUI

/// Mochi's sheet, top to bottom: how she is right now, her four needs with the care each takes, her day so far and
/// what kind of cat she is. It draws what it is given, so the gallery shows it with a fixed cat.
struct MochiSheetContent<Portrait: View, ExtraCare: View>: View {
    let name: String
    let status: CatStatus
    let level: Int
    /// The way to the next level, 0...1.
    let progress: Double
    let days: Int
    /// The zone her day's times are told in.
    var zone: TimeZone = .current
    var care: (NeedCare) -> Void
    @ViewBuilder var portrait: Portrait
    /// The care no need's tile offers, under the tiles.
    @ViewBuilder var extraCare: ExtraCare
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            hero
            VStack(alignment: .leading, spacing: Space.m) {
                NeedGrid(name: name, needs: status.needs, asleep: status.about?.asleep ?? false, care: care)
                extraCare
            }
            if let about = status.about {
                day(about)
                character(about)
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        Card(warm: true) {
            VStack(alignment: .leading, spacing: Space.l) {
                // At accessibility sizes her words take the card's whole width under her portrait.
                if dynamicTypeSize.isAccessibilitySize {
                    portrait
                    mood
                } else {
                    HStack(spacing: Space.l) {
                        portrait
                        mood
                    }
                }
                levelBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Past this the mood line alone fills an SE's screen and pushes her needs below the fold.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var mood: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(status.needs?.moodLine(name: name) ?? "Settling in")
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

    // MARK: Her day

    private func day(_ about: CatAbout) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("\(name)'s day", symbol: "sun.max.fill") { Text("Now: \(status.doing.lowercased())") }
            if about.day.isEmpty {
                Card {
                    Text("Her day is only starting. What she gets up to shows here.")
                        .font(.ourioCallout)
                        .foregroundStyle(Ink.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                MomentStrip(about.day.map { moment in
                    StripMoment(id: moment.id, symbol: moment.kind.symbol, tint: moment.kind.tint,
                                title: moment.kind.title, time: moment.time(in: zone))
                })
            }
        }
    }

    // MARK: About her

    private func character(_ about: CatAbout) -> some View {
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
                                MeterBar(value: about.personality[trait], tint: trait.tint)
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
