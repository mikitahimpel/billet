import Design
import UsInterface
import SwiftUI

/// Every widget and control Ourio has, as the Home Screen and Lock Screen show it, and how to add one.
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
    let preview: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.m) {
                Image(preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: item.group == .lockScreen ? Radius.inner : Radius.card, style: .continuous))
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
