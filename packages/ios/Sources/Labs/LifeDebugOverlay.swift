import DesignSystem
import Pet
import SwiftUI

/// A small card over Home for tuning the pet's life: the four needs and mood as they are, a
/// faster clock, and a button for each event. Everything it adds stays on this phone.
public struct LifeDebugOverlay: View {
  private let model: PetLifeModel
  @State private var asPartner = false

  private static let speeds: [Double] = [1, 60, 600]

  public init(model: PetLifeModel) {
    self.model = model
  }

  public var body: some View {
    let state = model.state
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Life").billetType(.label).foregroundStyle(Palette.paper.color)
        Spacer(minLength: 0)
        Text(Self.clock(model.now)).monospacedDigit()
          .billetType(.caption).foregroundStyle(Palette.muted.color)
      }
      ForEach(PetNeed.allCases, id: \.self) { need in
        bar(need.title, state.needs[need], highlighted: model.drive.focus == need)
      }
      bar("Mood", state.mood, highlighted: false)
      Text(summary(state))
        .billetType(.caption).foregroundStyle(Palette.muted.color)
      Picker("Speed", selection: Binding(get: { model.speed }, set: { model.setSpeed($0) })) {
        ForEach(Self.speeds, id: \.self) { Text("×\(Int($0))").tag($0) }
      }
      .pickerStyle(.segmented)
      HStack(spacing: 4) {
        ForEach(LifeEvent.Kind.allCases, id: \.self) { kind in
          Button(kind.rawValue) { model.debug(kind, asPartner: asPartner) }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .accessibilityIdentifier("lifeDebug.\(kind.rawValue)")
        }
      }
      Toggle("As partner", isOn: $asPartner)
        .billetType(.caption).foregroundStyle(Palette.paper.color)
        .controlSize(.mini)
    }
    .padding(10)
    .frame(width: 236)
    .background(Palette.pageDeep.color.opacity(0.88), in: RoundedRectangle(cornerRadius: 12))
    .accessibilityIdentifier("lifeDebug")
  }

  private func bar(_ title: String, _ value: Double, highlighted: Bool) -> some View {
    HStack(spacing: 6) {
      Text(title).billetType(.caption)
        .foregroundStyle(highlighted ? Palette.light.color : Palette.paper.color)
        .frame(width: 52, alignment: .leading)
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule().fill(Palette.paper.color.opacity(0.15))
          Capsule().fill(Palette.gold.color)
            .frame(width: geometry.size.width * min(1, max(0, value)))
        }
      }
      .frame(height: 6)
      Text(String(format: "%.2f", value)).monospacedDigit()
        .billetType(.caption).foregroundStyle(Palette.muted.color)
        .frame(width: 34, alignment: .trailing)
    }
  }

  private func summary(_ state: LifeState) -> String {
    var parts = [state.asleep ? "asleep" : "awake"]
    if let focus = model.drive.focus { parts.append("wants \(focus.title.lowercased())") }
    if let missing = state.missing {
      parts.append(missing == model.me ? "misses you" : "misses them")
    }
    parts.append("\(model.log.events.count + model.debugEvents.count) events")
    return parts.joined(separator: " · ")
  }

  private static func clock(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
  }
}
