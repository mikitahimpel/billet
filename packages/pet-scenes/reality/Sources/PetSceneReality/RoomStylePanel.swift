import DesignSystem
import Pet
import SwiftUI

/// The parts of the room the Style tab does up, one shelf of swatches each.
enum RoomStyleSection: String, CaseIterable, Hashable {
  case walls, floor, curtains, view, lights

  var title: String {
    switch self {
    case .walls: "Walls"
    case .floor: "Floor"
    case .curtains: "Curtains"
    case .view: "View"
    case .lights: "Lights"
    }
  }

  var items: [RoomStyleItem] {
    switch self {
    case .walls: RoomWall.allCases.map(RoomStyleItem.wall)
    case .floor: RoomFloor.allCases.map(RoomStyleItem.floor)
    case .curtains: CurtainFabric.allCases.map(RoomStyleItem.curtains)
    case .view: ([nil] + WindowView.allCases).map(RoomStyleItem.view)
    case .lights: FairyColour.allCases.map(RoomStyleItem.fairy)
    }
  }
}

/// What a tap on a swatch does, given what is unlocked: a free or unlocked choice is made at
/// once for both partners; a locked one is tried on in this room only, until it is unlocked or
/// something else is chosen.
struct RoomStyleChoice: Equatable {
  /// The style both partners share.
  var style: RoomStyle
  /// A locked choice being tried on, shown here and nowhere else.
  var trying: RoomStyleItem?

  /// What the room shows.
  var shown: RoomStyle { trying.map(style.with) ?? style }

  /// Taps `item`. Returns the style to share when the tap changes it.
  mutating func tap(_ item: RoomStyleItem, unlocked: Bool) -> RoomStyle? {
    guard unlocked else {
      trying = style.shows(item) ? nil : item
      return nil
    }
    trying = nil
    guard !style.shows(item) else { return nil }
    style = style.with(item)
    return style
  }

  /// The choice being tried on, now unlocked, made for both partners.
  mutating func keep() -> RoomStyle? {
    guard let trying else { return nil }
    self.trying = nil
    style = style.with(trying)
    return style
  }
}

/// The Style tab: over the room while it is decorated, a glass panel at the foot with a row of
/// sections and a shelf of swatches for the one picked. The room above shows each choice as it
/// is made. Choices that cost stamps can be tried on first and unlocked from the panel.
struct RoomStylePanel: View {
  let style: RoomStyle
  /// What is being tried on, which the room shows in place of `style`.
  @Binding var trying: RoomStyleItem?
  let renovator: RoomRenovator?
  let onChoose: (RoomStyle) -> Void
  let onClose: () -> Void

  @State private var section = RoomStyleSection.walls
  @State private var refusal: String?
  @State private var swatches = SwatchImages()

  private var choice: RoomStyleChoice { RoomStyleChoice(style: style, trying: trying) }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      header
      sections
      shelf
      if section == .curtains, choice.shown.curtains != .none { drape }
      footer
    }
    .padding(.vertical, Spacing.medium)
    .floatingGlass()
    .animation(.snappy(duration: 0.25), value: trying)
    .animation(.snappy(duration: 0.25), value: section)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("stylePanel")
  }

  private var header: some View {
    HStack(spacing: Spacing.small) {
      Text("Style")
        .billetType(.heading)
        .foregroundStyle(Palette.paper.color)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 0)
      if let renovator {
        Label("\(renovator.stamps)", systemImage: "seal.fill")
          .billetType(.label)
          .foregroundStyle(Palette.gold.color)
          .accessibilityLabel("\(renovator.stamps) stamps")
          .accessibilityIdentifier("styleStamps")
      }
      IconButton("checkmark", label: "Done styling", action: close)
        .accessibilityIdentifier("styleDone")
    }
    .padding(.horizontal, Spacing.medium)
  }

  private var sections: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Spacing.small) {
        ForEach(RoomStyleSection.allCases, id: \.self) { part in
          let picked = part == section
          Button {
            section = part
            refusal = nil
          } label: {
            Text(part.title)
              .billetType(.label)
              .fontWeight(picked ? .semibold : .regular)
              .foregroundStyle(picked ? Palette.ink.color : Palette.paper.color)
              .padding(.horizontal, Spacing.medium - Spacing.hair)
              .frame(height: Target.minimum - Spacing.small)
              .background(
                Capsule().fill(picked ? Palette.paper.color : Palette.paper.color.opacity(0.12))
              )
              .contentShape(.capsule)
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(picked ? [.isSelected, .isButton] : .isButton)
          .accessibilityIdentifier("styleSection-\(part.rawValue)")
        }
      }
      .padding(.horizontal, Spacing.medium)
    }
    .sensoryFeedback(.selection, trigger: section)
  }

  private var shelf: some View {
    ScrollViewReader { reader in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: Spacing.small + Spacing.hair) {
          ForEach(section.items, id: \.self) { item in
            swatch(item).id(item)
          }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.hair)
      }
      .onChange(of: section, initial: true) {
        if let shown = section.items.first(where: choice.shown.shows) {
          reader.scrollTo(shown, anchor: .center)
        }
      }
    }
    .sensoryFeedback(.selection, trigger: choice.shown)
  }

  private func swatch(_ item: RoomStyleItem) -> some View {
    let shown = choice.shown.shows(item)
    let unlocked = isUnlocked(item)
    return Button {
      tap(item)
    } label: {
      RoomStyleSwatch(item: item, images: swatches)
        .frame(width: Self.swatchSize, height: Self.swatchSize)
        .overlay {
          Circle()
            .strokeBorder(
              shown ? Palette.gold.color : Palette.paper.color.opacity(0.18),
              lineWidth: shown ? 3 : 1)
        }
        .overlay(alignment: .bottomTrailing) {
          if !unlocked, let price = item.price {
            PriceTag(price: price).offset(x: 4, y: 4)
          }
        }
        .padding(Spacing.hair)
        .contentShape(.circle)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(item.title)
    .accessibilityValue(unlocked ? "" : "Locked, \(item.price ?? 0) stamps")
    .accessibilityAddTraits(shown ? [.isSelected, .isButton] : .isButton)
    .accessibilityIdentifier("style-\(item.shopID)")
  }

  static let swatchSize: CGFloat = 50

  private var drape: some View {
    HStack(spacing: Spacing.small) {
      ForEach(CurtainDrape.allCases, id: \.self) { drape in
        let picked = choice.shown.drape == drape
        Button {
          var next = style
          next.drape = drape
          if next != style { onChoose(next) }
        } label: {
          Text(drape.title)
            .billetType(.label)
            .foregroundStyle(picked ? Palette.ink.color : Palette.paper.color)
            .frame(maxWidth: .infinity)
            .frame(height: Target.minimum - Spacing.small)
            .background(
              Capsule().fill(picked ? Palette.paper.color : Palette.paper.color.opacity(0.12))
            )
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("styleDrape-\(drape.rawValue)")
      }
    }
    .padding(.horizontal, Spacing.medium)
    .sensoryFeedback(.selection, trigger: style.drape)
  }

  /// The choice shown on this shelf, by name, and for one tried on, the way to unlock it.
  private var footer: some View {
    HStack(spacing: Spacing.small) {
      if let refusal {
        Text(refusal)
          .billetType(.label)
          .foregroundStyle(Palette.clayLit.color)
          .accessibilityIdentifier("styleRefusal")
      } else {
        Text(shownTitle)
          .billetType(.label)
          .foregroundStyle(Palette.paper.color.opacity(0.8))
          .lineLimit(1)
      }
      Spacer(minLength: 0)
      if let trying, let price = trying.price {
        Button {
          unlock(trying)
        } label: {
          Label("Unlock · \(price)", systemImage: "seal.fill")
            .billetType(.action)
            .foregroundStyle(Palette.ink.color)
            .padding(.horizontal, Spacing.medium)
            .frame(height: Target.minimum)
            .contentShape(.capsule)
        }
        .billetButton(.primary)
        .accessibilityLabel("Unlock \(trying.title) for \(price) stamps")
        .accessibilityIdentifier("styleUnlock")
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
      }
    }
    .frame(minHeight: Target.minimum)
    .padding(.horizontal, Spacing.medium)
  }

  /// What the footer names: the choice being tried on, wherever it is, else this shelf's.
  private var shownTitle: String {
    if let trying { return "Trying \(trying.title)" }
    return section.items.first(where: choice.shown.shows)?.title ?? ""
  }

  private func isUnlocked(_ item: RoomStyleItem) -> Bool {
    guard item.price != nil else { return true }
    return renovator?.hasUnlocked(item) ?? false
  }

  private func tap(_ item: RoomStyleItem) {
    refusal = nil
    var next = choice
    let shared = next.tap(item, unlocked: isUnlocked(item))
    trying = next.trying
    if let shared { onChoose(shared) }
  }

  private func unlock(_ item: RoomStyleItem) {
    guard let renovator else { return }
    do throws(ShopError) {
      try renovator.unlock(item)
    } catch {
      refusal = Self.refusal(error)
      return
    }
    var next = choice
    if let shared = next.keep() { onChoose(shared) }
    trying = next.trying
  }

  static func refusal(_ error: ShopError) -> String {
    switch error {
    case .notEnoughStamps(let needed, let have):
      let short = max(needed - have, 1)
      return short == 1 ? "1 more stamp needed" : "\(short) more stamps needed"
    case .unknownItem, .alreadyOwned, .notInCloset, .wrongKind, .roomIsFull, .unknownPlacement:
      return "Couldn't unlock that"
    }
  }

  private func close() {
    trying = nil
    onClose()
  }
}

/// The price of a locked swatch, on a small gold plate.
private struct PriceTag: View {
  let price: Int

  var body: some View {
    HStack(spacing: 1) {
      Image(systemName: "seal.fill").imageScale(.small)
      Text("\(price)")
    }
    .font(.caption2.weight(.bold))
    .foregroundStyle(Palette.ink.color)
    .padding(.horizontal, 5)
    .padding(.vertical, 2)
    .background(Capsule().fill(Palette.gold.color))
    .accessibilityHidden(true)
  }
}

/// A round swatch for one choice: its colour, its pattern, a sky for a view, a glowing bulb for
/// the fairy lights.
struct RoomStyleSwatch: View {
  let item: RoomStyleItem
  let images: SwatchImages

  var body: some View {
    ZStack {
      switch item {
      case .wall(let wall):
        if wall.isWallpaper {
          pattern(.wall(wall), fallback: wall.colours.base)
        } else {
          Circle().fill(Color(hex: wall.colours.base))
        }
      case .floor(let floor):
        switch floor {
        case .plain: Circle().fill(Color(hex: floor.colour))
        case .lightWood, .darkWood, .herringbone, .tiles:
          pattern(.floor(floor), fallback: floor.colour)
        }
      case .curtains(let fabric):
        switch fabric {
        case .none:
          Circle().fill(Palette.paper.color.opacity(0.1))
          Image(systemName: "rectangle.portrait")
            .foregroundStyle(Palette.paper.color.opacity(0.8))
        case .gingham:
          pattern(
            .gingham(fabric.colours.base, fabric.colours.pattern ?? 0),
            fallback: fabric.colours.base)
        case .linen, .sheer, .rose, .forest:
          Circle().fill(Color(hex: fabric.colours.base).opacity(fabric == .sheer ? 0.6 : 1))
          Image(systemName: "curtains.closed")
            .foregroundStyle(.black.opacity(0.22))
        }
      case .view(let view):
        if let view {
          Circle().fill(
            LinearGradient(
              colors: Self.sky(view.hour).map { Color(hex: $0) }, startPoint: .top,
              endPoint: .bottom))
          Image(systemName: Self.symbol(view.weather))
            .foregroundStyle(.white.opacity(0.85))
        } else {
          Circle().fill(Palette.paper.color.opacity(0.1))
          Image(systemName: "gearshape")
            .foregroundStyle(Palette.paper.color.opacity(0.8))
        }
      case .fairy(let colour):
        Circle().fill(Color(hex: 0x1A2436))
        Circle()
          .fill(Color(hex: colour.swatch))
          .frame(width: 16, height: 16)
          .shadow(color: Color(hex: colour.swatch), radius: 8)
      }
    }
    .clipShape(.circle)
  }

  private func pattern(_ pattern: GenzStylePattern, fallback: UInt32) -> some View {
    Group {
      if let image = images.image(pattern) {
        Image(decorative: image, scale: 4).resizable(resizingMode: .tile)
      } else {
        Color(hex: fallback)
      }
    }
  }

  static func sky(_ hour: ViewHour) -> [UInt32] {
    switch hour {
    case .morning: [0x9FC3E6, 0xF6C39B]
    case .day: [0x6FB3E8, 0xD3ECF8]
    case .dusk: [0x5B4A8C, 0xF29BA8]
    case .night: [0x0E1A33, 0x2E4370]
    }
  }

  static func symbol(_ weather: ViewWeather) -> String {
    switch weather {
    case .clear: "sparkles"
    case .rain: "cloud.rain.fill"
    case .snow: "snowflake"
    case .fog: "cloud.fog.fill"
    }
  }
}

/// The swatches' patterns, drawn once each while the panel is open.
@MainActor
final class SwatchImages {
  private var images: [GenzStylePattern: CGImage] = [:]

  func image(_ pattern: GenzStylePattern) -> CGImage? {
    if let image = images[pattern] { return image }
    guard let image = pattern.image() else { return nil }
    images[pattern] = image
    return image
  }
}

extension Color {
  fileprivate init(hex: UInt32) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }
}
