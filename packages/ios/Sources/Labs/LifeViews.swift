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

/// Four soft rings round the cat's portrait, one per need, in warm colours and without numbers.
public struct LifeRings: View {
  private let needs: PetNeeds
  private let portrait: Image?
  private let name: String

  public init(needs: PetNeeds, portrait: Image?, name: String) {
    self.needs = needs
    self.portrait = portrait
    self.name = name
  }

  private static let width: CGFloat = 11
  private static let gap: CGFloat = 4

  public var body: some View {
    VStack(spacing: Spacing.medium) {
      ZStack {
        ForEach(Array(PetNeed.allCases.enumerated()), id: \.element) { index, need in
          let inset = CGFloat(index) * (Self.width + Self.gap)
          ring(need).padding(inset)
        }
        portraitView
          .padding(CGFloat(PetNeed.allCases.count) * (Self.width + Self.gap) + Self.gap)
      }
      .frame(width: 236, height: 236)
      HStack(spacing: Spacing.medium) {
        ForEach(PetNeed.allCases, id: \.self) { need in
          HStack(spacing: 5) {
            Circle().fill(need.swatch.color).frame(width: 8, height: 8)
            Text(need.title).billetType(.label).foregroundStyle(Palette.paper.color)
          }
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Self.spoken(needs, name: name))
    .accessibilityIdentifier("lifeRings")
  }

  private func ring(_ need: PetNeed) -> some View {
    ZStack {
      Circle().stroke(need.swatch.color.opacity(0.16), lineWidth: Self.width)
      Circle()
        .trim(from: 0, to: max(0.02, min(1, needs[need])))
        .stroke(
          need.swatch.color.opacity(0.9),
          style: StrokeStyle(lineWidth: Self.width, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
        .shadow(color: need.swatch.color.opacity(0.35), radius: 4)
    }
    .padding(Self.width / 2)
  }

  @ViewBuilder private var portraitView: some View {
    if let portrait {
      portrait.resizable().scaledToFill().clipShape(Circle())
    } else {
      Circle().fill(Palette.raised.color)
        .overlay {
          Image(systemName: "pawprint.fill").font(.system(size: 34))
            .foregroundStyle(Palette.gold.color)
        }
    }
  }

  /// Words, not numbers: how each need is, for VoiceOver.
  static func spoken(_ needs: PetNeeds, name: String) -> String {
    let parts = PetNeed.allCases.map { "\($0.title): \(LifeChips.word(needs[$0]))" }
    return "\(name). " + parts.joined(separator: ", ")
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

  /// The needs in the card's order, with the short names people use.
  public static let rows: [(need: PetNeed, title: String)] = [
    (.full, "Food"), (.playful, "Play"), (.loved, "Love"), (.rested, "Sleep"),
  ]
}

/// A compact card: the mood in words, what the cat wants now, and a bar per need. Shown from the
/// paw chip and gone again with a swipe; nothing of it stays on Home.
public struct CatNeedsCard: View {
  private let snapshot: CatNeedsSnapshot
  private let isNamed: Bool

  /// - Parameter isNamed: Whether the card stands alone, its mood line starting with the cat's
  ///   name and its own margins around it. A sheet titled with the name leaves out both.
  public init(_ snapshot: CatNeedsSnapshot, isNamed: Bool = true) {
    self.snapshot = snapshot
    self.isNamed = isNamed
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.medium) {
      VStack(alignment: .leading, spacing: Spacing.hair) {
        Text(isNamed ? "\(snapshot.name) · \(snapshot.feeling.words)" : snapshot.feeling.words)
          .billetType(.heading)
          .foregroundStyle(Palette.paper.color)
        Text("Wants: \(snapshot.feeling.wants)")
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
      }
      VStack(spacing: Spacing.small) {
        ForEach(CatNeedsSnapshot.rows, id: \.need) { row in
          bar(row.need, title: row.title)
        }
      }
    }
    .padding(isNamed ? Spacing.medium : 0)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Self.spoken(snapshot))
    .accessibilityIdentifier("catNeedsCard")
  }

  private func bar(_ need: PetNeed, title: String) -> some View {
    let value = min(max(snapshot.needs[need], 0), 1)
    let low = value < LifeConfig.standard.lowBelow
    return HStack(spacing: Spacing.small) {
      Text(title)
        .billetType(.label)
        .foregroundStyle(Palette.paper.color)
        .frame(width: 48, alignment: .leading)
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(need.swatch.color.opacity(0.18))
          Capsule()
            .fill(need.swatch.color.opacity(low ? 0.65 : 0.95))
            .frame(width: max(8, proxy.size.width * value))
        }
      }
      .frame(height: 10)
      .calmAnimation(value: value)
    }
  }

  /// The card for VoiceOver: the mood, what it wants, and each need in a word.
  static func spoken(_ snapshot: CatNeedsSnapshot) -> String {
    let needs = CatNeedsSnapshot.rows.map {
      "\($0.title): \(LifeChips.word(snapshot.needs[$0.need]))"
    }
    return "\(snapshot.name) is \(snapshot.feeling.rawValue). Wants: \(snapshot.feeling.wants). "
      + needs.joined(separator: ", ")
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
