import DesignSystem
import SwiftUI

/// Pick the colour of your lamp, and see the colour of your partner's window. No labels: a colour
/// means what the two of you say it means.
public struct LampColourSection: View {
  private let store: LampStore
  private let catName: String?
  private let showsColours: Bool
  private let showsGoodnight: Bool
  private let onGoodnight: (Bool) -> Void

  /// - Parameters:
  ///   - showsColours: Whether the colour choice and the partner's window show.
  ///   - showsGoodnight: Whether the goodnight button shows.
  ///   - onGoodnight: Called with true when this phone's lamp goes out, and false when it comes
  ///     back on.
  public init(
    store: LampStore, catName: String?, showsColours: Bool, showsGoodnight: Bool,
    onGoodnight: @escaping (Bool) -> Void
  ) {
    self.store = store
    self.catName = catName
    self.showsColours = showsColours
    self.showsGoodnight = showsGoodnight
    self.onGoodnight = onGoodnight
  }

  public var body: some View {
    VStack(spacing: Spacing.small) {
      if showsColours { colours }
      if showsGoodnight { goodnight }
    }
    .padding(Spacing.medium)
    .frame(maxWidth: .infinity)
    .card()
    .calmAnimation(value: store.theirs?.colour)
    .accessibilityIdentifier("lampColours")
  }

  private var goodnight: some View {
    TimelineView(.everyMinute) { context in
      let night = store.night(at: context.date)
      VStack(spacing: Spacing.small) {
        Text(Self.words(night, catName: catName))
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
          .multilineTextAlignment(.center)
        switch night {
        case .waitingOnThem, .asleep:
          BilletButton("Light the lamp again", rank: .secondary) {
            store.wakeUp()
            onGoodnight(false)
          }
        case .awake, .waitingOnMe:
          BilletButton("Say goodnight", rank: .secondary, systemImage: "moon") {
            store.sayGoodnight(at: .now)
            onGoodnight(true)
          }
        }
      }
    }
  }

  static func words(_ night: LightsOut.Night, catName: String?) -> String {
    let cat = catName ?? "The cat"
    switch night {
    case .awake: return "Put your lamp out when you are going to sleep."
    case .waitingOnThem: return "Your lamp is out. \(cat) waits for theirs."
    case .waitingOnMe: return "Your partner's lamp is out."
    case .asleep: return "Both lamps are out. \(cat) has curled up."
    }
  }

  private var colours: some View {
    HStack(alignment: .center, spacing: Spacing.medium) {
      VStack(alignment: .leading, spacing: Spacing.small) {
        Text("Your lamp")
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
        HStack(spacing: Spacing.small) {
          ForEach(LampColour.allCases, id: \.self) { colour in
            Button {
              store.choose(colour)
            } label: {
              Circle()
                .fill(colour.swatch.color)
                .frame(width: 28, height: 28)
                .overlay {
                  Circle().strokeBorder(
                    Palette.paper.color, lineWidth: store.mine == colour ? 3 : 0)
                }
                .frame(width: Target.minimum, height: Target.minimum)
                .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(colour.spokenName)
            .accessibilityAddTraits(store.mine == colour ? [.isButton, .isSelected] : .isButton)
          }
        }
      }
      Spacer(minLength: 0)
      VStack(spacing: Spacing.hair) {
        Window(colour: store.theirs?.colour)
        Text("Their window")
          .billetType(.caption)
          .foregroundStyle(Palette.muted.color)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        store.theirs.map { "Your partner's lamp is \($0.colour.spokenName)" }
          ?? "Your partner has not set a lamp")
    }
  }

  private struct Window: View {
    let colour: LampColour?

    var body: some View {
      RoundedRectangle(cornerRadius: 6)
        .fill(Palette.pageDeep.color)
        .overlay {
          RoundedRectangle(cornerRadius: 6)
            .fill((colour?.swatch ?? Palette.muted).color.opacity(colour == nil ? 0.15 : 0.9))
            .padding(4)
        }
        .overlay { RoundedRectangle(cornerRadius: 6).stroke(Palette.wood.color, lineWidth: 2) }
        .frame(width: 44, height: 44)
        .shadow(
          color: (colour?.swatch ?? Palette.muted).color.opacity(colour == nil ? 0 : 0.6),
          radius: 10)
    }
  }
}

/// The dark laid over the scene while both lamps are out. Touches go through.
public struct NightOverlay: View {
  private let night: LightsOut.Night

  public init(night: LightsOut.Night) {
    self.night = night
  }

  public var body: some View {
    Palette.skyNight.color
      .opacity(night == .asleep ? 0.62 : 0)
      .allowsHitTesting(false)
      .ignoresSafeArea()
      .calmAnimation(value: night)
      .accessibilityHidden(true)
  }
}
