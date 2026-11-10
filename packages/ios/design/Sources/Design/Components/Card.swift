import SwiftUI

extension View {
  /// `warm` is for a screen's hero card. Also the container shape, so a `ConcentricRectangle`
  /// inside follows its corners.
  public func cardSurface(radius: CGFloat = Radius.card, warm: Bool = false) -> some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    return background {
      shape.fill(Ink.surface)
      if warm { shape.fill(Color.honey.opacity(0.14)) }
    }
    .containerShape(shape)
  }
}

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

/// Every card that opens something starts with it.
/// The one card that floats: a passing note over the screen, such as a purchase with its Undo. A
/// hairline rim and a soft shadow lift it off whatever scrolls underneath.
public struct Toast<Content: View>: View {
  let content: Content

  public init(@ViewBuilder content: () -> Content) { self.content = content() }

  public var body: some View {
    content
      .padding(CardMetrics.padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface()
      .overlay {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
          .strokeBorder(Ink.separator, lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
  }
}

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

/// No tint means the accent, whose glyph is `Ink.accentText` so it reads on the wash in both
/// themes.
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
