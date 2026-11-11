import SwiftUI

public struct Card<Content: View>: View {
  let warm: Bool
  let state: CardState
  let content: Content

  public init(warm: Bool = false, state: CardState = .rest, @ViewBuilder content: () -> Content) {
    self.warm = warm
    self.state = state
    self.content = content()
  }

  public var body: some View {
    content
      .padding(CardMetrics.padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface(warm: warm, state: state)
  }
}

/// The one card that floats: a passing note over the screen, such as a purchase with its Undo.
public struct Toast<Content: View>: View {
  let content: Content

  public init(@ViewBuilder content: () -> Content) { self.content = content() }

  public var body: some View {
    content
      .padding(CardMetrics.padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface()
  }
}

/// Every card that opens something starts with it.
public struct CardHeader<Leading: View, Detail: View, Trailing: View>: View {
  let title: String
  let leading: Leading
  let detail: Detail
  let trailing: Trailing

  public init(
    _ title: String, @ViewBuilder leading: () -> Leading, @ViewBuilder detail: () -> Detail,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.leading = leading()
    self.detail = detail()
    self.trailing = trailing()
  }

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// At accessibility sizes the mark and the trailing view share the first line and the words take
  /// the card's whole width under them, so a title wraps at word ends instead of truncating.
  public var body: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: Space.s) {
        HStack(spacing: Space.m) {
          mark
          Spacer(minLength: 0)
          trailing
        }
        words
      }
    } else {
      HStack(spacing: Space.m) {
        mark
        words.lineLimit(2)
        Spacer(minLength: 0)
        trailing
      }
    }
  }

  private var mark: some View {
    leading.frame(width: Size.cardMark, height: Size.cardMark)
  }

  private var words: some View {
    VStack(alignment: .leading, spacing: Space.xxs) {
      Text(title)
        .font(.ourioHeadline)
        .foregroundStyle(Ink.text)
        .fixedSize(horizontal: false, vertical: true)
      detail
        .font(.ourioCaption)
        .foregroundStyle(Ink.textSecondary)
    }
  }
}

extension CardHeader where Leading == RowIcon, Detail == Text?, Trailing == RowChevron? {
  public init(
    _ title: String, detail: String? = nil, symbol: String, tint: Color? = nil, opens: Bool = true
  ) {
    self.init(title) {
      RowIcon(symbol: symbol, tint: tint, size: Size.cardMark, style: .clay)
    } detail: {
      detail.map { Text($0) }
    } trailing: {
      opens ? RowChevron() : nil
    }
  }
}

public struct CardArt: View {
  let image: Image

  public init(_ image: Image) { self.image = image }

  public var body: some View {
    image
      .resizable()
      .scaledToFill()
      .frame(width: Size.cardMark, height: Size.cardMark)
      .clipShape(.rect(cornerRadius: Radius.inner, style: .continuous))
      .accessibilityHidden(true)
  }
}

public struct GroupedSection<Content: View, Footer: View>: View {
  let header: String?
  let inset: CGFloat
  let content: Content
  let footer: Footer

  /// - Parameter inset: Where the hairlines start; 0 for rows without an icon.
  public init(
    header: String? = nil, inset: CGFloat = RowMetrics.iconInset,
    @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer
  ) {
    self.header = header
    self.inset = inset
    self.content = content()
    self.footer = footer()
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Space.s) {
      if let header {
        Text(header)
          .font(.ourioCaption.weight(.semibold))
          .foregroundStyle(Ink.textSecondary)
          .padding(.horizontal, Space.l)
          .accessibilityAddTraits(.isHeader)
      }
      VStack(spacing: 0) {
        Group(subviews: content) { rows in
          ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            if index > 0 {
              Rectangle().fill(Ink.separator).frame(height: 0.5).padding(.leading, inset)
            }
            row
          }
        }
      }
      .cardSurface()
      footer
        .font(.ourioCaption)
        .foregroundStyle(Ink.textSecondary)
        .padding(.horizontal, Space.l)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

extension GroupedSection where Footer == Text? {
  public init(
    header: String? = nil, footer: String? = nil, inset: CGFloat = RowMetrics.iconInset,
    @ViewBuilder content: () -> Content
  ) {
    self.init(header: header, inset: inset, content: content) { footer.map { Text($0) } }
  }
}

public enum RowMetrics {
  /// The hairlines of a row with an icon start under its title.
  public static let iconInset: CGFloat = Space.l + 34 + 14
}

public struct Row<Trailing: View>: View {
  let title: String
  let detail: String?
  let symbol: String?
  let tint: Color?
  let destructive: Bool
  let trailing: Trailing

  public init(
    _ title: String, detail: String? = nil, symbol: String? = nil, tint: Color? = nil,
    destructive: Bool = false, @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.detail = detail
    self.symbol = symbol
    self.tint = tint
    self.destructive = destructive
    self.trailing = trailing()
  }

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// At accessibility sizes the icon and the trailing control share the first line and the words
  /// take the row's whole width under them; without an icon the control goes under the words.
  public var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: Space.s) {
          if let symbol {
            HStack(spacing: Space.m) {
              icon(symbol)
              Spacer(minLength: Space.s)
              trailing
            }
            words
          } else {
            words
            trailing
          }
        }
      } else {
        HStack(spacing: 14) {
          if let symbol { icon(symbol) }
          words.layoutPriority(1)
          Spacer(minLength: Space.s)
          trailing
        }
      }
    }
    .padding(.horizontal, Space.l)
    .padding(.vertical, Space.s + 2)
    .frame(maxWidth: .infinity, minHeight: Size.row, alignment: .leading)
    .contentShape(.rect)
  }

  private func icon(_ symbol: String) -> some View {
    RowIcon(symbol: symbol, tint: destructive ? Optional(Ink.destructive) : tint)
  }

  private var words: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.ourioBody)
        .foregroundStyle(destructive ? Ink.destructive : Ink.text)
        .fixedSize(horizontal: false, vertical: true)
      if let detail {
        Text(detail)
          .font(.ourioCaption)
          .foregroundStyle(Ink.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

extension Row where Trailing == EmptyView {
  public init(
    _ title: String, detail: String? = nil, symbol: String? = nil, tint: Color? = nil,
    destructive: Bool = false
  ) {
    self.init(title, detail: detail, symbol: symbol, tint: tint, destructive: destructive) {
      EmptyView()
    }
  }
}

/// A symbol on a rounded tile. `clay` is the mark of a card or a tile: filled with its tint, lit at
/// the top and shaded at the foot, the glyph in the tint's own deep shade. `well` is the quiet mark
/// of a row in a list. No tint means the accent.
public struct RowIcon: View {
  public enum Style: Hashable, Sendable {
    case clay
    case well
  }

  static let washOpacity = 0.2
  static let cornerFraction = 0.32
  static let glyphFraction = 0.5

  let symbol: String
  let tint: Color?
  let size: CGFloat
  let style: Style
  @Environment(\.colorScheme) private var colorScheme

  public init(symbol: String, tint: Color? = nil, size: CGFloat = 34, style: Style = .well) {
    self.symbol = symbol
    self.tint = tint
    self.size = size
    self.style = style
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: size * Self.cornerFraction, style: .continuous)
  }

  private var base: Color { tint ?? .honey }
  private var deep: Color { base.mix(with: Ink.heroInk, by: 0.7) }

  public var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size * Self.glyphFraction, weight: .semibold))
      .foregroundStyle(glyph)
      .frame(width: size, height: size)
      .background { face }
      .accessibilityHidden(true)
  }

  private var glyph: Color {
    switch style {
    case .clay:
      return deep
    case .well:
      guard let tint else { return Ink.accentText }
      return colorScheme == .dark
        ? tint.mix(with: .white, by: 0.15) : tint.mix(with: Ink.heroInk, by: 0.45)
    }
  }

  @ViewBuilder private var face: some View {
    switch style {
    case .clay:
      shape.fill(
        LinearGradient(
          colors: [base.mix(with: Ink.paper, by: 0.38), base], startPoint: .top, endPoint: .bottom))
      shape.strokeBorder(
        LinearGradient(
          stops: [
            .init(color: .white.opacity(0.4), location: 0),
            .init(color: .white.opacity(0), location: 0.45),
            .init(color: deep.opacity(0.3), location: 1),
          ], startPoint: .top, endPoint: .bottom),
        lineWidth: 1.5)
    case .well:
      shape.fill(base.opacity(Self.washOpacity))
      shape.strokeBorder(base.opacity(0.22), lineWidth: 1)
    }
  }
}

public struct RowChevron: View {
  public init() {}

  public var body: some View {
    Image(systemName: "chevron.right")
      .font(.ourioCaption.weight(.semibold))
      .foregroundStyle(Ink.textTertiary)
      .accessibilityHidden(true)
  }
}

public struct ToggleRow: View {
  let title: String
  let detail: String?
  let symbol: String?
  let tint: Color?
  @Binding var isOn: Bool

  public init(
    _ title: String, detail: String? = nil, symbol: String? = nil, tint: Color? = nil,
    isOn: Binding<Bool>
  ) {
    self.title = title
    self.detail = detail
    self.symbol = symbol
    self.tint = tint
    _isOn = isOn
  }

  public var body: some View {
    Row(title, detail: detail, symbol: symbol, tint: tint) {
      Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(.honey)
    }
    .accessibilityElement(children: .combine)
  }
}

public struct PickerRow<Value: Hashable, Options: View>: View {
  let title: String
  let symbol: String?
  let tint: Color?
  @Binding var selection: Value
  let options: Options

  public init(
    _ title: String, symbol: String? = nil, tint: Color? = nil, selection: Binding<Value>,
    @ViewBuilder options: () -> Options
  ) {
    self.title = title
    self.symbol = symbol
    self.tint = tint
    _selection = selection
    self.options = options()
  }

  public var body: some View {
    Row(title, symbol: symbol, tint: tint) {
      // A menu picker is a UIKit button: it ignores `lineLimit` and reports less height than it
      // draws once its value wraps, so its type stops growing where a short value still fits a line.
      Picker(title, selection: $selection) { options }
        .pickerStyle(.menu)
        .labelsHidden()
        .lineLimit(1)
        .truncationMode(.middle)
        .dynamicTypeSize(...Self.largestType)
        .tint(Ink.accentText)
    }
  }

  static var largestType: DynamicTypeSize { .xxxLarge }
}

#Preview("Grouped section") {
  BothSchemes {
    Page {
      GroupedSection(header: "Settings", footer: "Haptics are only on this phone.") {
        Row("Profile", detail: "Mikita", symbol: "person.fill") { RowChevron() }
        ToggleRow("Haptics", symbol: "hand.tap.fill", tint: .blushPink, isOn: .constant(true))
        Row("Erase all data", symbol: "trash.fill", destructive: true)
      }
      Card(warm: true) {
        CardHeader("Anniversary", detail: "In 12 days · Friday 21 November", symbol: "heart.fill")
      }
      Card {
        CardHeader("Date night", detail: "3 matches waiting", symbol: "dice.fill", tint: .pink)
      }
    }
  }
}

extension View {
  public func rowCell() -> some View {
    padding(.horizontal, Space.l)
      .padding(.vertical, Space.s + 2)
      .frame(maxWidth: .infinity, minHeight: Size.row, alignment: .leading)
  }

  public func listRowSurface() -> some View {
    listRowBackground(Ink.surface)
      .listRowSeparatorTint(Ink.separator)
  }
}

#Preview("Toast") {
  BothSchemes {
    VStack {
      Spacer()
      Toast {
        HStack(spacing: Space.m) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Tea for Two is yours").font(.ourioHeadline).foregroundStyle(Ink.text)
            Text("It's in your room's closet.").font(.ourioCaption)
              .foregroundStyle(Ink.textSecondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          PillButton("Undo") {}
        }
      }
      .padding(Space.l)
    }
    .background(Ink.screen)
  }
}
