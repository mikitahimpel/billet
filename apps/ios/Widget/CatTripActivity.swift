import ActivityKit
import AppIntents
import DesignSystem
import SwiftUI
import WidgetBridge
import WidgetKit

/// The cat on its way with a note: a Lock Screen banner and the Dynamic Island.
struct CatTripActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CatTripAttributes.self) { context in
      CatTripBanner(name: context.attributes.catName, content: context.state)
        .padding(Spacing.medium)
        .activityBackgroundTint(Palette.page.color)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: "pawprint.fill").foregroundStyle(Palette.gold.color)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(CatTripBanner.title(context.attributes.catName, context.state))
            .billetType(.action)
        }
        DynamicIslandExpandedRegion(.trailing) {
          CatTripHeart(content: context.state)
        }
        DynamicIslandExpandedRegion(.bottom) {
          CatTripProgress(content: context.state)
        }
      } compactLeading: {
        Image(systemName: "pawprint.fill").foregroundStyle(Palette.gold.color)
      } compactTrailing: {
        Image(systemName: context.state.phase == .hung ? "checkmark" : "envelope.fill")
          .foregroundStyle(Palette.paper.color)
      } minimal: {
        Image(systemName: "pawprint.fill").foregroundStyle(Palette.gold.color)
      }
    }
  }
}

private struct CatTripBanner: View {
  let name: String?
  let content: CatTrip.Content

  static func title(_ name: String?, _ content: CatTrip.Content) -> String {
    let cat = name ?? "The cat"
    switch content.phase {
    case .onItsWay: return "\(cat) is on its way"
    case .hung: return "\(cat) hung your note"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      HStack(spacing: Spacing.medium) {
        Image(systemName: "pawprint.fill")
          .font(IconStyle.font)
          .foregroundStyle(Palette.gold.color)
        Text(Self.title(name, content))
          .billetType(.heading)
          .foregroundStyle(Palette.paper.color)
          .frame(maxWidth: .infinity, alignment: .leading)
        CatTripHeart(content: content)
      }
      CatTripProgress(content: content)
    }
  }
}

/// A bar that runs by itself from the start to the expected arrival.
private struct CatTripProgress: View {
  let content: CatTrip.Content

  var body: some View {
    switch content.phase {
    case .onItsWay:
      ProgressView(timerInterval: content.startedAt...content.arrivesAt, countsDown: false) {
        EmptyView()
      } currentValueLabel: {
        EmptyView()
      }
      .tint(Palette.gold.color)
    case .hung:
      ProgressView(value: 1).tint(Palette.gold.color)
    }
  }
}

private struct CatTripHeart: View {
  let content: CatTrip.Content

  var body: some View {
    Button(intent: HeartTripIntent()) {
      Image(systemName: content.hearted ? "heart.fill" : "heart")
        .font(IconStyle.font)
        .foregroundStyle(Palette.clayLit.color)
        .frame(width: Target.minimum, height: Target.minimum)
    }
    .buttonStyle(.plain)
    .disabled(content.hearted)
    .accessibilityLabel(content.hearted ? "Heart queued" : "Send a heart")
  }
}
