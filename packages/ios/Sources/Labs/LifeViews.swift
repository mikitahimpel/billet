import DesignSystem
import Pet
import SwiftUI

extension PetNeed {
  /// The need's warm colour, shared by the rings and the words.
  public var swatch: Swatch {
    switch self {
    case .full: Palette.woodLit
    case .rested: Palette.lightWarm
    case .loved: Palette.clayLit
    case .playful: Palette.gold
    }
  }

  /// What the cat thinks of when the need is low.
  public var thought: String {
    switch self {
    case .full: "fish.fill"
    case .rested: "zzz"
    case .loved: "heart.fill"
    case .playful: "tennisball.fill"
    }
  }

  /// What answering the thought does, for VoiceOver.
  public var answer: String {
    switch self {
    case .full: "Give a treat"
    case .rested: "Tuck it in"
    case .loved: "Pet the cat"
    case .playful: "Play with the cat"
    }
  }
}

/// The one need the cat is thinking about, if one is low enough to show: the focus of the
/// behaviour, so the bubble and what the cat does always agree.
public enum LifeThought {
  public static func need(_ drive: LifeDrive) -> PetNeed? {
    drive.asleep ? nil : drive.focus
  }
}

/// A small thought bubble over the cat. Tapping it answers the need.
public struct LifeBubble: View {
  private let need: PetNeed
  private let onTap: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var floating = false

  public init(need: PetNeed, onTap: @escaping () -> Void) {
    self.need = need
    self.onTap = onTap
  }

  public var body: some View {
    Button(action: onTap) {
      ZStack(alignment: .bottomLeading) {
        Circle().fill(Palette.paper.color).frame(width: 8, height: 8).offset(x: -10, y: 16)
        Circle().fill(Palette.paper.color).frame(width: 13, height: 13).offset(x: -2, y: 6)
        Image(systemName: need.thought)
          .font(.system(size: 22, weight: .semibold, design: .rounded))
          .foregroundStyle(need.swatch.color)
          .frame(width: 54, height: 46)
          .background(Palette.paper.color, in: Capsule())
          .shadow(color: Palette.ink.color.opacity(0.25), radius: 6, y: 2)
      }
    }
    .buttonStyle(.plain)
    .offset(y: floating && !reduceMotion ? -4 : 0)
    .animation(
      reduceMotion ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
      value: floating
    )
    .onAppear { floating = true }
    .transition(.scale(scale: 0.6).combined(with: .opacity))
    .accessibilityLabel(need.answer)
    .accessibilityIdentifier("lifeBubble.\(need.rawValue)")
  }
}

/// The four needs as small words that glow when met and fade when not. No numbers, no levels.
public struct LifeChips: View {
  private let needs: PetNeeds

  public init(needs: PetNeeds) {
    self.needs = needs
  }

  public var body: some View {
    HStack(spacing: Spacing.small) {
      ForEach(PetNeed.allCases, id: \.self) { need in
        chip(need)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      PetNeed.allCases.map { "\($0.title): \(Self.word(needs[$0]))" }.joined(separator: ", ")
    )
    .accessibilityIdentifier("lifeChips")
  }

  private func chip(_ need: PetNeed) -> some View {
    let value = needs[need]
    let met = Self.glow(value)
    return Text(need.title)
      .billetType(.label)
      .foregroundStyle(
        met > 0.5 ? Palette.ink.color : Palette.paper.color.opacity(0.55 + 0.45 * met)
      )
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background {
        Capsule().fill(need.swatch.color.opacity(0.12 + 0.88 * met))
      }
      .overlay {
        Capsule().strokeBorder(need.swatch.color.opacity(0.5), lineWidth: 1)
      }
      .shadow(color: need.swatch.color.opacity(0.45 * met), radius: 6)
      .calmAnimation(value: met)
  }

  /// How brightly a chip glows for a need at `value`: dim near the floor, full once well met.
  static func glow(_ value: Double) -> Double {
    min(1, max(0, (value - 0.3) / 0.5))
  }

  /// A word for a need's level, for VoiceOver.
  static func word(_ value: Double) -> String {
    switch value {
    case ..<0.35: "low"
    case ..<0.65: "fine"
    default: "good"
    }
  }
}

/// What the needs card shows: the needs, how the cat feels, and its name.
public struct CatNeedsSnapshot: Hashable, Sendable {
  public var needs: PetNeeds
  public var feeling: CatFeeling
  public var name: String

  public init(needs: PetNeeds, feeling: CatFeeling, name: String) {
    self.needs = needs
    self.feeling = feeling
    self.name = name
  }

  /// The need to answer first: the one behind how the cat feels, if it feels one.
  public var urgent: PetNeed? {
    feeling.need
  }

  /// The four needs, most urgent first: the feeling's need, then from the lowest up. Ties keep
  /// the card's usual order: food, love, play, sleep.
  public var ordered: [PetNeed] {
    let usual: [PetNeed] = [.full, .loved, .playful, .rested]
    let rest = usual.filter { $0 != urgent }.enumerated().sorted { a, b in
      let (x, y) = (needs[a.element], needs[b.element])
      return x == y ? a.offset < b.offset : x < y
    }.map(\.element)
    return (urgent.map { [$0] } ?? []) + rest
  }

  /// One short line in the cat's voice: how it is and what it would like.
  public var line: String {
    "\(name) is \(feeling.state). \(feeling.ask)"
  }

  /// Whether the need's action can be done now: a cat that is already asleep needs no tucking in.
  public func canAnswer(_ need: PetNeed) -> Bool {
    !(need == .rested && feeling == .asleep)
  }
}

extension CatFeeling {
  /// The feeling as the end of "Mochi is …".
  public var state: String {
    switch self {
    case .asleep: "fast asleep"
    case .hangry: "hangry"
    case .hungry: "hungry"
    case .lonely: "sulking"
    case .bored: "restless"
    case .sleepy: "sleepy"
    case .happy: "happy"
    case .content: "content"
    }
  }

  /// What the cat would ask for, in its own words.
  public var ask: String {
    switch self {
    case .asleep: "Shh 💤"
    case .hangry: "Food, now! 😾"
    case .hungry: "A treat? 🐟"
    case .lonely: "A pet, maybe two? 😿"
    case .bored: "Play with me? 🧶"
    case .sleepy: "A little nap? 🥱"
    case .happy: "Just stay a while 😻"
    case .content: "Say hi? 😺"
    }
  }
}

extension PetNeed {
  /// The need's short name on the card.
  public var cardTitle: String {
    switch self {
    case .full: "Food"
    case .rested: "Sleep"
    case .loved: "Love"
    case .playful: "Play"
    }
  }

  /// The button that fills the need.
  public var action: String {
    switch self {
    case .full: "Feed"
    case .rested: "Let it nap"
    case .loved: "Pet"
    case .playful: "Play"
    }
  }
}

/// What the cat needs and what to do about it: a line in its voice, then one row per need, the
/// most urgent first, each with a bar and the button that fills it. The room stays in sight
/// behind it.
public struct CatNeedsCard: View {
  private let snapshot: CatNeedsSnapshot
  private let onAnswer: ((PetNeed) -> Void)?
  /// The order the rows had when the card opened, kept while it shows so a row never moves under
  /// a finger; the bars and the line still follow the cat.
  @State private var openedOrder: [PetNeed]?

  private var order: [PetNeed] { openedOrder ?? snapshot.ordered }

  /// One width for every action, the widest's, so the bars beside them are all as long.
  @ScaledMetric(relativeTo: .body) private var actionWidth: CGFloat = 116

  /// - Parameter onAnswer: Does a need's action, or `nil` for a card with no buttons.
  public init(_ snapshot: CatNeedsSnapshot, onAnswer: ((PetNeed) -> Void)? = nil) {
    self.snapshot = snapshot
    self.onAnswer = onAnswer
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Text(snapshot.line)
        .billetType(.body)
        .contentTransition(.opacity)
        .foregroundStyle(Palette.paper.color)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("catNeedsLine")
      VStack(spacing: 0) {
        ForEach(order, id: \.self) { need in
          row(need)
          if need != order.last { ListDivider() }
        }
      }
      .frame(maxWidth: .infinity)
      .card()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onAppear { openedOrder = snapshot.ordered }
    .accessibilityIdentifier("catNeedsCard")
  }

  private func row(_ need: PetNeed) -> some View {
    let value = min(max(snapshot.needs[need], 0), 1)
    let urgent = need == snapshot.urgent
    return HStack(spacing: Spacing.medium) {
      Image(systemName: need.thought)
        .font(IconStyle.font)
        .foregroundStyle(need.swatch.color)
        .frame(width: 28)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Spacing.hair) {
        Text(need.cardTitle)
          .billetType(.label)
          .foregroundStyle(Palette.paper.color)
        NeedBar(value: value, swatch: need.swatch, low: value < LifeConfig.standard.lowBelow)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(need.cardTitle): \(LifeChips.word(value))")
      if let onAnswer {
        let can = snapshot.canAnswer(need)
        Button {
          onAnswer(need)
        } label: {
          Text(need.action)
            .billetType(.action)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(
              !can ? Palette.muted.color : urgent ? Palette.ink.color : Palette.paper.color
            )
            .padding(.horizontal, Spacing.small)
            .frame(width: actionWidth)
            .frame(minHeight: Target.minimum)
            .contentShape(.capsule)
        }
        .billetButton(urgent ? .primary : .secondary)
        .disabled(!can)
        .accessibilityHint(need.answer)
        .accessibilityIdentifier("catNeedsAction.\(need.rawValue)")
      }
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.vertical, Spacing.small)
    .frame(maxWidth: .infinity, minHeight: Target.row, alignment: .leading)
    .accessibilityIdentifier("catNeedsRow.\(need.rawValue)")
  }

  /// The card for VoiceOver and tests: the line, then each need in a word.
  static func spoken(_ snapshot: CatNeedsSnapshot) -> String {
    let needs = snapshot.ordered.map { "\($0.cardTitle): \(LifeChips.word(snapshot.needs[$0]))" }
    return "\(snapshot.line) " + needs.joined(separator: ", ")
  }
}

/// How full one need is, as a short bar that warms as it fills.
private struct NeedBar: View {
  let value: Double
  let swatch: Swatch
  let low: Bool

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(swatch.color.opacity(0.18))
        Capsule()
          .fill(swatch.color.opacity(low ? 0.65 : 0.95))
          .frame(width: max(6, proxy.size.width * value))
      }
    }
    .frame(height: 6)
    .calmAnimation(value: value)
  }
}

/// The small paw by the streak that opens the needs card. A dot shows when the cat wants
/// something.
public struct CatMoodChip: View {
  private let snapshot: CatNeedsSnapshot
  private let action: () -> Void

  public init(_ snapshot: CatNeedsSnapshot, action: @escaping () -> Void) {
    self.snapshot = snapshot
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      Image(systemName: "pawprint.fill")
        .font(IconStyle.font)
        .foregroundStyle(Palette.paper.color)
        .frame(width: Target.minimum, height: Target.minimum)
        .overlay(alignment: .topTrailing) {
          if snapshot.feeling.isNeedy {
            Circle()
              .fill(Palette.clayLit.color)
              .frame(width: 9, height: 9)
              .offset(x: -9, y: 9)
              .transition(.scale.combined(with: .opacity))
          }
        }
        .contentShape(.circle)
    }
    .buttonStyle(.plain)
    .floatingGlass()
    .calmAnimation(value: snapshot.feeling.isNeedy)
    .accessibilityLabel("\(snapshot.name): \(snapshot.feeling.rawValue)")
    .accessibilityHint("Shows what the cat needs")
    .accessibilityIdentifier("catMoodChip")
  }
}
