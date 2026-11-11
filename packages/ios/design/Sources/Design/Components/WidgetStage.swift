import SwiftUI

/// The size of a widget in points: Apple's gallery sizes for a Pro Max.
public struct WidgetStageSize: Sendable {
  public let width: CGFloat
  public let height: CGFloat

  public static let small = WidgetStageSize(width: 170, height: 170)
  public static let medium = WidgetStageSize(width: 364, height: 170)
  public static let large = WidgetStageSize(width: 364, height: 382)
}

/// A widget as it sits on a screen: the widget's own view at its true point size, on a wallpaper, scaled down only
/// when the card holding it is narrower. Nothing is a picture, so it stays crisp at any size and in either appearance.
/// For a Home Screen widget; `LockScreenStage` is the Lock Screen's.
public struct WidgetStage<Widget: View>: View {
  let size: WidgetStageSize
  let widget: Widget

  public init(_ size: WidgetStageSize, @ViewBuilder widget: () -> Widget) {
    self.size = size
    self.widget = widget()
  }

  public var body: some View {
    ScaledStage(width: size.width, height: size.height) {
      widget
        .frame(width: size.width, height: size.height)
        .background(Ink.screen)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .allowsHitTesting(false)
    } wallpaper: {
      LinearGradient(
        colors: [Color(hex: 0xF4B98B), Color(hex: 0xC98AA3), Color(hex: 0x7C7AA8)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    }
  }
}

/// The three Lock Screen widget shapes over a lock screen wallpaper and a clock, in the vibrant white the system
/// draws them in. A gauge in them should be drawn by hand: the system's has no look outside a widget.
public struct LockScreenStage<Circular: View, Rectangular: View, Inline: View>: View {
  let circular: Circular
  let rectangular: Rectangular
  let inline: Inline

  public init(
    @ViewBuilder circular: () -> Circular, @ViewBuilder rectangular: () -> Rectangular,
    @ViewBuilder inline: () -> Inline
  ) {
    self.circular = circular()
    self.rectangular = rectangular()
    self.inline = inline()
  }

  private static var width: CGFloat { 76 + 8 + 172 }
  private static var height: CGFloat { 76 + 8 + 22 }

  public var body: some View {
    ScaledStage(width: Self.width, height: Self.height, headerHeight: 64) {
      VStack(spacing: Space.s) {
        HStack(spacing: Space.s) {
          circular
            .frame(width: 76, height: 76)
            .background(.white.opacity(0.16), in: Circle())
          rectangular
            .frame(width: 172, height: 76)
            .background(
              .white.opacity(0.16),
              in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        inline.frame(height: 22)
      }
      .foregroundStyle(.white)
      .environment(\.colorScheme, .dark)
      .allowsHitTesting(false)
    } wallpaper: {
      LinearGradient(
        colors: [Color(hex: 0x3B2F5C), Color(hex: 0x9C5A7E), Color(hex: 0xF2A65E)],
        startPoint: .top,
        endPoint: .bottom)
    } header: {
      Text("9:41")
        .font(.ourioNumber)
        .foregroundStyle(.white.opacity(0.9))
        .frame(height: 64)
    }
  }
}

/// Lays `content` at its true size on a wallpaper and scales the pair down to the width it is given.
private struct ScaledStage<Content: View, Wallpaper: View, Header: View>: View {
  let width: CGFloat
  let height: CGFloat
  let headerHeight: CGFloat
  let content: Content
  let wallpaper: Wallpaper
  let header: Header

  init(
    width: CGFloat, height: CGFloat, headerHeight: CGFloat = 0,
    @ViewBuilder content: () -> Content, @ViewBuilder wallpaper: () -> Wallpaper,
    @ViewBuilder header: () -> Header
  ) {
    self.width = width
    self.height = height
    self.headerHeight = headerHeight
    self.content = content()
    self.wallpaper = wallpaper()
    self.header = header()
  }

  private let inset = Space.l

  var body: some View {
    Color.clear
      .frame(maxWidth: .infinity)
      .aspectRatio((width + inset * 2) / (headerHeight + height + inset * 2), contentMode: .fit)
      .overlay {
        GeometryReader { geo in
          let scale = geo.size.width / (width + inset * 2)
          ZStack {
            wallpaper
            VStack(spacing: 0) {
              header
              content.frame(width: width, height: height)
            }
            .frame(width: width, height: headerHeight + height)
            .scaleEffect(scale)
          }
          .frame(width: geo.size.width, height: geo.size.height)
        }
      }
      .corners(.inner)
  }
}

extension ScaledStage where Header == EmptyView {
  init(
    width: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content,
    @ViewBuilder wallpaper: () -> Wallpaper
  ) {
    self.init(
      width: width, height: height, content: content, wallpaper: wallpaper, header: { EmptyView() })
  }
}
