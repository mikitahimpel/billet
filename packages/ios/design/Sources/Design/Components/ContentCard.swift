import SwiftUI

/// A card with fixed slots: title and subtitle with an optional state chip at the trailing edge,
/// any content under them, and a row of actions last. The actions sit side by side while they fit
/// at their own width and stack, full width, when they don't or at accessibility text sizes, so
/// a button is never squeezed or truncated. A card without actions is a `Card` with a `CardHeader`.
public struct ContentCard<Content: View, Actions: View>: View {
  let title: String
  let subtitle: String?
  let chip: Chip?
  let warm: Bool
  let content: Content
  let actions: Actions

  public init(
    _ title: String, subtitle: String? = nil, chip: Chip? = nil, warm: Bool = false,
    @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions
  ) {
    self.title = title
    self.subtitle = subtitle
    self.chip = chip
    self.warm = warm
    self.content = content()
    self.actions = actions()
  }

  public var body: some View {
    Card(warm: warm) {
      VStack(alignment: .leading, spacing: Space.m) {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
          VStack(alignment: .leading, spacing: Space.xxs) {
            Text(title)
              .font(.ourioHeadline)
              .foregroundStyle(Ink.text)
              .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
              Text(subtitle)
                .font(.ourioCaption)
                .foregroundStyle(Ink.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityElement(children: .combine)
          chip
        }
        content
        ActionRow { actions }
      }
    }
  }
}

extension ContentCard where Content == EmptyView {
  public init(
    _ title: String, subtitle: String? = nil, chip: Chip? = nil, warm: Bool = false,
    @ViewBuilder actions: () -> Actions
  ) {
    self.init(
      title, subtitle: subtitle, chip: chip, warm: warm, content: { EmptyView() },
      actions: actions)
  }
}

/// Buttons side by side at their own width while they fit, otherwise stacked full width. The first
/// is the leading one; put the primary last, as in `Screen`.
public struct ActionRow<Content: View>: View {
  let content: Content
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(@ViewBuilder content: () -> Content) { self.content = content() }

  public var body: some View {
    if dynamicTypeSize.isAccessibilitySize {
      stacked
    } else {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: Space.s) {
          Group(subviews: content) { subviews in
            ForEach(subviews) { $0.fixedSize() }
          }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        stacked
      }
    }
  }

  private var stacked: some View {
    VStack(spacing: Space.s) { content }.frame(maxWidth: .infinity)
  }
}

#Preview("Content card") {
  BothSchemes {
    VStack(spacing: Space.m) {
      ContentCard(
        "Weekend in Lisbon", subtitle: "Saved by both of you", chip: Chip("Plan", style: .honey)
      ) {
        SecondaryButton("Edit", fullWidth: false) {}
        PrimaryButton("Book it", fullWidth: false) {}
      }
      ContentCard("A much longer title that wraps onto a second line", subtitle: "Two actions") {
        Text("Body copy sits between the header and the actions.")
          .font(.ourioBody)
          .foregroundStyle(Ink.textSecondary)
      } actions: {
        SecondaryButton("Remind me tomorrow", fullWidth: false) {}
        PrimaryButton("Answer together now", fullWidth: false) {}
      }
    }
    .padding(Space.gutter)
  }
}
