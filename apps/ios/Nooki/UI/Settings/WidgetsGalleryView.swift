import Design
import SwiftUI
import UsInterface
import WidgetKit
import WidgetUI

/// Every widget and control Ourio has, drawn with the widgets' own views on sample data, and how to add one.
struct WidgetsGalleryView: View {
    var body: some View {
        Page {
            ForEach(WidgetShowcase.Group.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: Space.m) {
                    SectionHeader(group.title)
                    ForEach(WidgetShowcase.items(in: group)) { item in
                        if let preview = item.preview {
                            PreviewCard(item: item, preview: preview)
                        } else {
                            ControlRow(item: item)
                        }
                    }
                    if let footer = group.footer {
                        Text(footer)
                            .font(.ourioCaption)
                            .foregroundStyle(Ink.textSecondary)
                    }
                }
            }
        }
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PreviewCard: View {
    let item: WidgetShowcase
    let preview: WidgetShowcase.Preview

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.m) {
                WidgetPreview(preview: preview)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.title) widget")
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(item.title).font(.ourioHeadline).foregroundStyle(Ink.text)
                    Text(item.detail).font(.ourioCaption).foregroundStyle(Ink.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct ControlRow: View {
    let item: WidgetShowcase

    var body: some View {
        GroupedSection {
            Row(item.title, detail: item.detail, symbol: item.symbol, tint: UsTint.honey.color)
        }
    }
}

/// A widget as it sits on a screen, drawn live from the widget's own views.
struct WidgetPreview: View {
    let preview: WidgetShowcase.Preview

    var body: some View {
        switch preview {
        case .cat(let size): WidgetStage(size.stage) { HomeKind.cat.view(family: size.family) }
        case .us(let size): WidgetStage(size.stage) { HomeKind.us.view(family: size.family) }
        case .partner(let size): WidgetStage(size.stage) { HomeKind.partner.view(family: size.family) }
        case .coins(let size): WidgetStage(size.stage) { HomeKind.coins.view(family: size.family) }
        case .memory(let size): WidgetStage(size.stage) { HomeKind.memory.view(family: size.family) }
        case .day: WidgetStage(.large) { HomeKind.day.view(family: .systemLarge) }
        case .lockUs: lock(.us)
        case .lockStreak: lock(.streak)
        case .lockCat: lock(.cat)
        case .lockPartner: lock(.partner)
        }
    }

    private func lock(_ kind: LockKind) -> some View {
        LockScreenStage {
            kind.view(family: .accessoryCircular)
        } rectangular: {
            kind.view(family: .accessoryRectangular)
        } inline: {
            kind.view(family: .accessoryInline)
        }
        .environment(\.drawsGaugesItself, true)
    }
}

private extension WidgetShowcase.Preview.Size {
    var stage: WidgetStageSize {
        switch self {
        case .small: .small
        case .medium: .medium
        case .large: .large
        }
    }

    var family: WidgetFamily {
        switch self {
        case .small: .systemSmall
        case .medium: .systemMedium
        case .large: .systemLarge
        }
    }
}

private enum HomeKind {
    case cat, us, partner, coins, memory, day

    @ViewBuilder
    func view(family: WidgetFamily) -> some View {
        switch self {
        case .cat: MochiFamilyView(entry: .sample(drawing: true), family: family)
        case .us: UsFamilyView(entry: .sample(), family: family)
        case .partner: PartnerFamilyView(entry: .sample(mood: .missing), family: family)
        case .coins: CoinsFamilyView(entry: .sample(), family: family)
        case .memory: MemoryFamilyView(entry: .sample(photo: true), family: family)
        case .day: DayFamilyView(entry: .sample(drawing: true))
        }
    }
}

private enum LockKind {
    case us, streak, cat, partner

    @ViewBuilder
    func view(family: WidgetFamily) -> some View {
        switch self {
        case .us: UsLockView(entry: .sample(), family: family)
        case .streak: StreakLockView(entry: .sample(), family: family)
        case .cat: CatLockView(entry: .sample(drawing: true), family: family)
        case .partner: PartnerLockView(entry: .sample(mood: .missing), family: family)
        }
    }
}
