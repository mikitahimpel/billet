import SwiftUI

/// A hint: an icon, a title, a short message and optional actions, drawn dark so it reads over
/// the room and over a sheet alike. The arrow toward its anchor is the system's (`TipView`,
/// `popoverTip`) or `CalloutPointer`'s.
public struct Callout<Icon: View, Title: View, Message: View, Actions: View>: View {
  let icon: Icon
  let title: Title
  let message: Message
  let close: (() -> Void)?
  let actions: Actions

  public init(
    close: (() -> Void)? = nil, @ViewBuilder icon: () -> Icon, @ViewBuilder title: () -> Title,
    @ViewBuilder message: () -> Message, @ViewBuilder actions: () -> Actions
  ) {
    self.close = close
    self.icon = icon()
    self.title = title()
    self.message = message()
    self.actions = actions()
  }

  public var body: some View {
    HStack(alignment: .top, spacing: Space.m) {
      icon
        .font(.ourioTitle)
        .symbolRenderingMode(.monochrome)
        .foregroundStyle(Color.honey)
        .frame(width: 30)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Space.xs) {
        title.font(.ourioHeadline).foregroundStyle(Ink.primary)
        message.font(.ourioCallout).foregroundStyle(Ink.secondary).lineLimit(3)
        actions
      }
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      if let close {
        Button(action: close) {
          Image(systemName: "xmark")
            .ourioScaledFont(size: 13, weight: .bold)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .foregroundStyle(Ink.secondary)
            .frame(width: Size.control, height: Size.control)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close hint")
      }
    }
    .padding(Space.l)
    .environment(\.colorScheme, .dark)
  }
}

extension Callout where Icon == Image, Title == Text, Message == Text, Actions == EmptyView {
  public init(symbol: String, title: String, message: String, close: (() -> Void)? = nil) {
    self.init(
      close: close, icon: { Image(systemName: symbol) }, title: { Text(title) },
      message: { Text(message) }, actions: { EmptyView() })
  }
}

/// The action inside a `Callout`: a small honey capsule.
public struct CalloutButton<Label: View>: View {
  let action: () -> Void
  let label: Label

  public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
    self.action = action
    self.label = label()
  }

  public var body: some View {
    Button(action: action) { label }
      .font(.ourioCallout.weight(.semibold))
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.capsule)
      .tint(.honey)
      .foregroundStyle(Ink.heroInk)
      .padding(.top, Space.xs)
  }
}

/// Where a `Callout`'s arrow points: the edge it sits on and how far along it, from 0 to 1.
public struct CalloutPointer: Equatable, Sendable {
  public enum Edge: Sendable { case top, bottom }
  public let edge: Edge
  public let position: CGFloat

  public init(edge: Edge, position: CGFloat = 0.5) {
    self.edge = edge
    self.position = min(max(position, 0), 1)
  }
}

extension View {
  /// A glass bubble with an arrow toward its anchor.
  public func calloutBubble(pointer: CalloutPointer? = nil) -> some View {
    modifier(CalloutBubble(pointer: pointer))
  }
}

private struct CalloutBubble: ViewModifier {
  let pointer: CalloutPointer?

  func body(content: Content) -> some View {
    content
      .glass(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
      .overlay { arrow }
  }

  @ViewBuilder private var arrow: some View {
    if let pointer {
      GeometryReader { proxy in
        let x = Radius.card + (proxy.size.width - 2 * Radius.card) * pointer.position
        ArrowShape(pointsUp: pointer.edge == .top)
          .fill(Ink.glassFill)
          .frame(width: Space.l, height: Space.s)
          .position(x: x, y: pointer.edge == .top ? -Space.s / 2 : proxy.size.height + Space.s / 2)
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }
}

private struct ArrowShape: Shape {
  let pointsUp: Bool

  func path(in rect: CGRect) -> Path {
    var path = Path()
    if pointsUp {
      path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    } else {
      path.move(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    }
    path.closeSubpath()
    return path
  }
}

#Preview("Callout") {
  BothSchemes {
    VStack(spacing: Space.l) {
      Callout(
        symbol: "hand.wave.fill", title: "Say hi", message: "Tap her in the room to pet her.",
        close: {}
      )
      .calloutBubble(pointer: CalloutPointer(edge: .bottom, position: 0.3))
    }
    .padding(.vertical, Space.gutter)
  }
}
