import SwiftUI

extension View {
  /// The app's one card surface: a flat solid fill, like the cell of a grouped list. `warm` lays a breath of
  /// honey over it, for a screen's hero card. Give a plain control's field `radius: Radius.control`.
  public func cardSurface(radius: CGFloat = Radius.card, warm: Bool = false) -> some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    return background {
      shape.fill(Ink.surface)
      if warm { shape.fill(Color.honey.opacity(0.14)) }
    }
  }
}

/// Content on the app's card, padded by `Space.l`.
public struct Card<Content: View>: View {
  let warm: Bool
  let content: Content

  public init(warm: Bool = false, @ViewBuilder content: () -> Content) {
    self.warm = warm
    self.content = content()
  }

  public var body: some View {
    content
      .padding(Space.l)
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface(warm: warm)
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
          .font(.nookiCaption.weight(.semibold))
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
        .font(.nookiCaption)
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
          .font(.nookiBody)
          .foregroundStyle(destructive ? Ink.destructive : Ink.text)
        if let detail {
          Text(detail)
            .font(.nookiCaption)
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
      .font(.nookiCaption.weight(.semibold))
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
      Card(warm: true) { Text("A hero card").font(.nookiHeadline).foregroundStyle(Ink.text) }
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
