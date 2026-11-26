import Design
import MomentsInterface
import ProfileInterface
import SwiftUI
import UsInterface
import WidgetInterface
import WidgetUI

/// The top of Us: the couple's days together in one big number, and the love streak in a ring that fills toward its
/// next badge, with one line on what today needs. Unpaired, the number gives way to the wait for the partner and a
/// way to invite them.
struct StreakCard: View {
  let store: StreakStore
  let daysTogether: Int?
  let partner: String

  var body: some View {
    // Ticks each minute so the midnight rollover shows while the tab is open.
    TimelineView(.periodic(from: .now, by: 60)) { context in
      StreakHero(
        copy: StreakCopy(
          streak: store.streak, on: context.date, daysTogether: daysTogether, partner: partner,
          cat: CatProfile.name()),
        restorable: store.streak.count,
        restore: { Task { await store.restore() } }
      ) {
        #if canImport(UIKit)
          PairToPlayButton(fullWidth: true)
        #endif
      }
    }
  }
}

/// The hero for one moment of the streak. The ring keeps its place at the trailing edge in every state, so pairing
/// swaps the wait for the number beside it and moves nothing else. `invite` is the way to pair, shown while unpaired.
public struct StreakHero<Invite: View>: View {
  let copy: StreakCopy
  let restorable: Int
  let restore: () -> Void
  let invite: Invite
  @Environment(\.dynamicTypeSize) private var typeSize

  /// - Parameter restorable: The days a restore would bring back.
  public init(
    copy: StreakCopy, restorable: Int, restore: @escaping () -> Void,
    @ViewBuilder invite: () -> Invite
  ) {
    self.copy = copy
    self.restorable = restorable
    self.restore = restore
    self.invite = invite()
  }

  public var body: some View {
    Card(warm: true) {
      VStack(alignment: .leading, spacing: Space.m) {
        VStack(alignment: .leading, spacing: Space.m) {
          if let days = copy.daysTogether {
            // Side by side while "days together" keeps its line; the ring goes under it at the largest sizes.
            ViewThatFits(in: .horizontal) {
              beside { together(days) }
              stacked { together(days) }
            }
          } else if typeSize.isAccessibilitySize {
            stacked { waiting }
          } else {
            // Copy wraps, so it has no width of its own for ViewThatFits to try: the text size decides.
            beside { waiting }
          }
          if let line = copy.line {
            // Its lead words in full ink, the rest quieter.
            (Text(line.lead).font(.ourioCallout.weight(.semibold)).foregroundStyle(Ink.text)
              + Text(line.rest).font(.ourioCallout).foregroundStyle(Ink.textSecondary))
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(copy.spoken)
        if copy.status == .restorable {
          Button(action: restore) {
            Label("Restore \(restorable)-day streak", systemImage: "arrow.counterclockwise")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(PrimaryButtonStyle())
        }
        if !copy.isPaired {
          invite
        }
      }
    }
    .animation(Motion.spring(0.3), value: copy.days)
  }

  private func beside(@ViewBuilder _ lead: () -> some View) -> some View {
    HStack(alignment: .center, spacing: Space.m) {
      lead().frame(maxWidth: .infinity, alignment: .leading)
      ring
    }
  }

  private func stacked(@ViewBuilder _ lead: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: Space.m) {
      lead()
      ring.frame(maxWidth: .infinity)
    }
  }

  private func together(_ days: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(days, format: .number)
        .font(.ourioHeroDigits)
        .foregroundStyle(Ink.text)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
      Text(days == 1 ? "day together" : "days together")
        .font(.ourioHeadline)
        .foregroundStyle(Ink.textSecondary)
    }
  }

  private var waiting: some View {
    VStack(alignment: .leading, spacing: Space.xs) {
      Text(Couple.waitingLine)
        .font(.ourioTitle)
        .foregroundStyle(Ink.text)
        .fixedSize(horizontal: false, vertical: true)
      Text("Your days together start when they join.")
        .font(.ourioCallout)
        .foregroundStyle(Ink.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var ring: some View {
    VStack(spacing: Space.xs) {
      ProgressRing(
        value: copy.next.map { Double(copy.days) / Double($0) } ?? 1,
        tint: Color(light: .honeyDeep, dark: .honeyBright)
      ) {
        VStack(spacing: 0) {
          Flame(days: copy.days, state: flame)
          Text(copy.days, format: .number)
            .font(.ourioTitleDigits)
            .foregroundStyle(Ink.text)
            .contentTransition(.numericText())
        }
      }
      Text("day streak")
        .font(.ourioCaption)
        .foregroundStyle(Ink.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
  }

  private var flame: Flame.State {
    if copy.status == .done { return .lit }
    return copy.turn == nil ? .unlit : .half
  }
}

// MARK: - Pieces

/// Flame that warms with the streak: orange, pink from 30 days, purple from 100. At 0 it is an outline, a flame
/// waiting to be lit; while today doesn't count yet it is quieter, less so once one partner did their part.
private struct Flame: View {
  enum State { case lit, half, unlit }

  let days: Int
  let state: State

  private var opacity: Double {
    switch state {
    case .lit: 1
    case .half: 0.85
    case .unlit: 0.65
    }
  }

  private var colors: [Color] {
    if days >= 100 { return [Color(hex: 0xD9B8FF), Color(hex: 0x8A5CFF)] }
    if days >= 30 { return [Color(hex: 0xFFB3C4), Color(hex: 0xFF5C8A)] }
    return [Color(hex: 0xFFD27A), Color(hex: 0xFF6A3D)]
  }

  var body: some View {
    Group {
      if days == 0 {
        Image(systemName: "flame")
          .foregroundStyle(Ink.textSecondary)
      } else {
        Image(systemName: "flame.fill")
          .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
          .opacity(opacity)
      }
    }
    .font(.ourioLargeTitleDigits)
    .accessibilityHidden(true)
  }
}
