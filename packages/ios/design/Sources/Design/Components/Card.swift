import SwiftUI

extension View {
  /// The app's one card surface: a flat solid fill, like the cell of a grouped list. `warm` lays a breath of
  /// honey over it, for a screen's hero card. `radius` is `Radius.card`, or `Radius.inner` for a tile nested in
  /// a card's padding. It is also the container shape, so a `ConcentricRectangle` inside follows its corners.
  public func cardSurface(radius: CGFloat = Radius.card, warm: Bool = false) -> some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    return background {
      shape.fill(Ink.surface)
      if warm { shape.fill(Color.honey.opacity(0.14)) }
    }
    .containerShape(shape)
  }
}

/// Content on the app's card, padded by `CardMetrics.padding`.
public struct Card<Content: View>: View {
  let warm: Bool
  let content: Content

  public init(warm: Bool = false, @ViewBuilder content: () -> Content) {
    self.warm = warm
    self.content = content()
  }

  public var body: some View {
    content
      .padding(CardMetrics.padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface(warm: warm)
  }
}

/// The one header of a card: a leading mark at `Size.cardMark`, the title over a quiet line, and a trailing
/// accessory (usually `RowChevron`). Every card that opens something starts with it.
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

  public var body: some View {
    HStack(spacing: Space.m) {
      leading
        .frame(width: Size.cardMark, height: Size.cardMark)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.ourioHeadline)
          .foregroundStyle(Ink.text)
          .lineLimit(2)
        detail
          .font(.ourioCaption)
          .foregroundStyle(Ink.textSecondary)
      }
      Spacer(minLength: 0)
      trailing
    }
  }
}

extension CardHeader where Leading == RowIcon, Detail == Text?, Trailing == RowChevron? {
  /// A header with an icon tile, an optional line under the title and a chevron when it opens something.
  public init(
    _ title: String, detail: String? = nil, symbol: String, tint: Color? = nil, opens: Bool = true
  ) {
    self.init(title) {
      RowIcon(symbol: symbol, tint: tint, size: Size.cardMark)
    } detail: {
      detail.map { Text($0) }
    } trailing: {
      opens ? RowChevron() : nil
    }
  }
}

/// Art in a card header's leading slot, clipped concentric with the card.
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

/// A group of rows on one card with hairlines between them, an optional caption above and a footer below: the
/// native inset-grouped list in the app's colours.
public struct GroupedSection<Content: View, Footer: View>: View {
  let header: String?
  let inset: CGFloat
  let content: Content
  let footer: Footer

  /// - Parameter inset: Where the hairlines start: under the title of a row with an icon, or at the edge
  ///   without one.
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

/// A row of a `GroupedSection`: an optional icon in a tinted circle, the title with an optional line under it,
/// and whatever goes on the right.
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

  public var body: some View {
    HStack(spacing: 14) {
      if let symbol {
        RowIcon(symbol: symbol, tint: destructive ? Optional(Ink.destructive) : tint)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.ourioBody)
          .foregroundStyle(destructive ? Ink.destructive : Ink.text)
        if let detail {
          Text(detail)
            .font(.ourioCaption)
            .foregroundStyle(Ink.textSecondary)
        }
      }
      Spacer(minLength: Space.s)
      trailing
    }
    .padding(.horizontal, Space.l)
    .padding(.vertical, Space.s + 2)
    .frame(maxWidth: .infinity, minHeight: Size.row, alignment: .leading)
    .contentShape(.rect)
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

/// The icon of a row: a full-tint SF Symbol on a soft wash of the same tint, one opacity for every tile. No
/// tint means the accent, whose glyph is `Ink.accentText` so it reads on the wash in both themes.
public struct RowIcon: View {
  static let washOpacity = 0.16

  let symbol: String
  let tint: Color?
  let size: CGFloat

  public init(symbol: String, tint: Color? = nil, size: CGFloat = 34) {
    self.symbol = symbol
    self.tint = tint
    self.size = size
  }

  public var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size * 0.44, weight: .semibold))
      .foregroundStyle(tint ?? Ink.accentText)
      .frame(width: size, height: size)
      .background((tint ?? .honey).opacity(Self.washOpacity), in: .circle)
      .accessibilityHidden(true)
  }
}

/// The chevron of a row that opens another screen.
public struct RowChevron: View {
  public init() {}

  public var body: some View {
    Image(systemName: "chevron.right")
      .font(.ourioCaption.weight(.semibold))
      .foregroundStyle(Ink.textTertiary)
      .accessibilityHidden(true)
  }
}

/// A row that switches something on and off.
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

/// A row that picks one of a few values from a menu, the current one shown on the right.
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
      Picker(title, selection: $selection) { options }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(Ink.accentText)
    }
  }
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
  /// A plain control or line as a row of a `GroupedSection`, for content that is not a `Row`.
  public func rowCell() -> some View {
    padding(.horizontal, Space.l)
      .padding(.vertical, Space.s + 2)
      .frame(maxWidth: .infinity, minHeight: Size.row, alignment: .leading)
  }

  /// A row of a `List` on `Ink.screen`.
  public func listRowSurface() -> some View {
    listRowBackground(Ink.surface)
      .listRowSeparatorTint(Ink.separator)
  }
}
