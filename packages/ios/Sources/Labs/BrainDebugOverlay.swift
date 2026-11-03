import DesignSystem
import Pet
import SwiftUI

/// A card over Home that says what the cat's brain is doing and why. Folded, it shows the state
/// stack and a faster clock and leaves the room in view; open, it adds the five best utility
/// scores with what made them, the last ten moves, its traits and memory.
public struct BrainDebugOverlay: View {
  private let brain: CatBrainModel
  private let life: PetLifeModel
  @State private var open = false

  private static let speeds: [Double] = [1, 60, 600]

  public init(brain: CatBrainModel, life: PetLifeModel) {
    self.brain = brain
    self.life = life
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Button {
        open.toggle()
      } label: {
        HStack {
          Text(open ? "Brain ▾" : "Brain ▸").billetType(.label)
            .foregroundStyle(Palette.paper.color)
          Spacer(minLength: 0)
          Text(life.now.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
            .monospacedDigit()
            .billetType(.caption).foregroundStyle(Palette.muted.color)
        }
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("brainDebug.open")
      if let frame = brain.frame {
        ForEach(frame.stack.path.components(separatedBy: " › "), id: \.self) { part in
          line(part, Palette.light)
        }
      } else {
        line("Waiting for the room", Palette.muted)
      }
      if open { details }
      Picker("Speed", selection: Binding(get: { life.speed }, set: { life.setSpeed($0) })) {
        ForEach(Self.speeds, id: \.self) { Text("×\(Int($0))").tag($0) }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("brainDebug.speed")
    }
    .padding(10)
    .frame(width: 268)
    .background(Palette.pageDeep.color.opacity(0.88), in: RoundedRectangle(cornerRadius: 12))
    .accessibilityIdentifier("brainDebug")
  }

  @ViewBuilder private var details: some View {
    section("Scores")
    ForEach(Self.top(brain.scores), id: \.group) { score in
      line(Self.describe(score), Palette.paper)
    }
    section("Moves")
    ForEach(Array(brain.transitions.suffix(10).reversed().enumerated()), id: \.offset) {
      _, move in
      line(Self.describe(move), Palette.muted)
    }
    section("Cat")
    line(Self.traits(brain.personality, nature: brain.nature), Palette.paper)
    line(memorySummary, Palette.paper)
  }

  private func section(_ title: String) -> some View {
    Text(title).billetType(.caption).foregroundStyle(Palette.gold.color).padding(.top, 2)
  }

  private func line(_ text: String, _ color: Swatch) -> some View {
    Text(text).font(.system(size: 10, design: .monospaced)).foregroundStyle(color.color)
      .lineLimit(1).minimumScaleFactor(0.7)
  }

  private var memorySummary: String {
    var parts: [String] = []
    if let favourite = brain.memory.favourite {
      parts.append(
        "likes the \(favourite.rawValue) \(Int(100 * brain.memory.fondness(favourite)))%")
    }
    if let lastBy = brain.lastBy { parts.append(lastBy == life.me ? "last: you" : "last: them") }
    if brain.awayHours >= 1 { parts.append("away \(Int(brain.awayHours))h") }
    if !brain.recentToys.isEmpty {
      parts.append("toys " + brain.recentToys.map(\.rawValue).joined(separator: ","))
    }
    return parts.isEmpty ? "no memories yet" : parts.joined(separator: " · ")
  }

  static func top(_ scores: [CatUtilityScore]) -> [CatUtilityScore] {
    Array(scores.sorted { $0.score > $1.score }.prefix(5))
  }

  /// One score and the factors that made it, such as `Rest 2.31 n1.9 p1.2 t1.4 r1.3 v1`.
  static func describe(_ score: CatUtilityScore) -> String {
    func f(_ value: Double) -> String { String(format: "%.2g", value) }
    let factors = [
      "n\(f(score.need))", "p\(f(score.personality))", "t\(f(score.time))", "r\(f(score.room))",
      "b\(f(score.novelty))", "m\(f(score.mood))", "v\(f(score.vitality))",
    ]
    return "\(score.group.title) \(String(format: "%.2f", score.score)) "
      + factors.joined(separator: " ")
  }

  static func describe(_ move: CatBrainTransition) -> String {
    let time = Date(timeIntervalSince1970: move.at).formatted(
      .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
    return "\(time) \(move.cause.rawValue) → \(move.to.step.rawValue)"
  }

  /// Each trait as today's value, with the change experience made to it.
  static func traits(_ personality: CatPersonality, nature: CatPersonality) -> String {
    CatPersonality.Trait.allCases.map { trait in
      let shift = personality[trait] - nature[trait]
      let mark = abs(shift) < 0.005 ? "" : shift > 0 ? "↑" : "↓"
      return "\(trait.rawValue.prefix(3))\(Int(100 * personality[trait]))\(mark)"
    }
    .joined(separator: " ")
  }
}
