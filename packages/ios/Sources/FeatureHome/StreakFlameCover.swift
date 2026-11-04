import DesignSystem
import FeatureInbox
import Foundation
import Pet
import PetScene
import SwiftUI

/// How Home opens the streak's flame: what to show now, and the scene that shows it.
struct StreakFlameHost {
  /// Remembers this visit and returns what the flame shows for it. Called once per opening.
  let open: @MainActor () -> FlameSceneState
  /// The flame for `state`, closed with `close`.
  let view: @MainActor (_ state: FlameSceneState, _ close: @escaping () -> Void) -> AnyView
}

/// The streak's flame, full screen: the scene, a close button top left, and the day count with the
/// next glow at the bottom, in soft words. It closes with the button or a swipe down.
struct StreakFlameCover: View {
  let scene: any PetScene
  let state: FlameSceneState
  let onClose: () -> Void

  @State private var celebrations = 0
  @State private var touches = 0
  @Environment(\.appEvents) private var events

  /// How far down a swipe has to go to close the scene.
  private static let closeDistance: CGFloat = 120

  var body: some View {
    ZStack {
      (scene.makeFlameScene(state: state, onEvent: handle) ?? AnyView(FlameFallback()))
        .ignoresSafeArea()
      VStack(spacing: 0) {
        HStack {
          IconButton("xmark", label: "Close the flame", action: onClose)
            .floatingGlass()
            .accessibilityIdentifier("flameClose")
          Spacer(minLength: 0)
        }
        .padding(.top, Spacing.small)
        .padding(.horizontal, Spacing.medium)
        Spacer(minLength: 0)
        caption
      }
    }
    .background(Color(red: 0.055, green: 0.078, blue: 0.141).ignoresSafeArea())
    .simultaneousGesture(
      DragGesture(minimumDistance: 24)
        .onEnded { value in
          let down = value.translation.height
          if down > Self.closeDistance, abs(value.translation.width) < down * 0.7 { onClose() }
        }
    )
    .sensoryFeedback(.success, trigger: celebrations)
    .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.45), trigger: touches)
    .accessibilityAction(.escape, onClose)
    .accessibilityIdentifier("streakFlame")
    .onAppear {
      events(.streakOpened)
      if let milestone = state.visit.milestone { events(.streakMilestoneSeen(milestone)) }
    }
  }

  private func handle(_ event: FlameSceneEvent) {
    switch event {
    case .touched: touches += 1
    case .celebrated: celebrations += 1
    }
  }

  private var caption: some View {
    VStack(spacing: Spacing.hair) {
      Text(state.flame.stage.title)
        .billetType(.heading)
        .foregroundStyle(Palette.paper.color)
      Text(state.flame.caption)
        .billetType(.label)
        .foregroundStyle(Palette.paper.color.opacity(0.85))
        .accessibilityIdentifier("flameCaption")
      if let line = state.flame.isEmber ? FlameCopy.ember : state.today.line {
        Text(line)
          .billetType(.caption)
          .foregroundStyle(Palette.muted.color)
      }
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, Spacing.page)
    .padding(.top, Spacing.page)
    .padding(.bottom, Spacing.wide)
    .background {
      LinearGradient(
        colors: [.clear, Color.black.opacity(0.45)], startPoint: .top, endPoint: .bottom
      )
      .ignoresSafeArea(edges: .bottom)
      .allowsHitTesting(false)
    }
    .accessibilityElement(children: .combine)
  }
}

/// The flame's soft words that are not the flame's own.
enum FlameCopy {
  /// Under a resting ember: what lights it again, never what was missed.
  static let ember = "It keeps warm. Your next day together lights it again."
}

/// Today's additions to the flame: a note either way, or a treat given.
enum FlameToday {
  static func contributions(
    notes: [NoteRecord], treat: TreatLedger.Status, now: Date, calendar: Calendar
  ) -> FlameContributions {
    let today = notes.filter { calendar.isDate($0.date, inSameDayAs: now) }
    let treatMine = treat == .fed || treat == .waitingOnPartner
    let treatTheirs = treat == .fed || treat == .waitingOnMe
    return FlameContributions(
      mine: treatMine || today.contains { $0.direction == .sent },
      theirs: treatTheirs || today.contains { $0.direction == .received })
  }
}

/// What this phone remembers of the flame between openings, in `defaults`.
enum FlameMemoryStore {
  static func key(fakePartner: Bool) -> String {
    fakePartner ? "flame.memory.fake" : "flame.memory"
  }

  /// Opens the flame at `streak`: returns what is new since the last opening, and remembers this
  /// one.
  static func visit(
    streak: Int, newestNote: UUID?, key: String, defaults: UserDefaults = .standard
  ) -> FlameVisit {
    var memory =
      defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(FlameMemory.self, from: $0) }
      ?? FlameMemory()
    let visit = memory.visit(streak: streak, newestNote: newestNote)
    if let data = try? JSONEncoder().encode(memory) { defaults.set(data, forKey: key) }
    return visit
  }
}

/// A flat flame for a scene with no 3D flame of its own.
private struct FlameFallback: View {
  var body: some View {
    Image(systemName: "flame.fill")
      .font(.system(size: 96))
      .foregroundStyle(
        LinearGradient(
          colors: [Palette.gold.color, Color(red: 1, green: 0.56, blue: 0.48)], startPoint: .top,
          endPoint: .bottom)
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityHidden(true)
  }
}
