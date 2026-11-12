import Design
import MomentsInterface
import ProfileInterface
import SwiftUI
import UsInterface
import WidgetInterface
import WidgetUI

/// The top of Us: the couple's days together in one big number, and the love streak in a ring that fills toward its
/// next badge, with one line on what today needs.
struct StreakCard: View {
  let store: StreakStore
  let daysTogether: Int
  let partner: String

  var body: some View {
    // Ticks each minute so the midnight rollover shows while the tab is open.
    TimelineView(.periodic(from: .now, by: 60)) { context in
      content(now: context.date)
    }
  }

  private func content(now: Date) -> some View {
    let streak = store.streak
    let status = streak.status(on: now)
    let days = streak.current(on: now)
    let next = streak.milestone(on: now).next
    let turn = streak.turn(on: now)
    let flame: Flame.State = status == .done ? .lit : turn == nil ? .unlit : .half

    return Card(warm: true) {
      VStack(alignment: .leading, spacing: Space.m) {
        // Side by side while "days together" keeps its line; the ring goes under it at the largest sizes.
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .center, spacing: Space.m) {
            together
            Spacer(minLength: 0)
            ring(days: days, flame: flame, next: next)
          }
          VStack(alignment: .leading, spacing: Space.m) {
            together
            ring(days: days, flame: flame, next: next)
          }
        }
        line(status, turn: turn, days: days, next: next)
          .fixedSize(horizontal: false, vertical: true)
        if status == .restorable {
          Button {
            Task { await store.restore() }
          } label: {
            Label("Restore \(streak.count)-day streak", systemImage: "arrow.counterclockwise")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(PrimaryButtonStyle())
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(label(days: days, turn: turn, next: next))
    .animation(Motion.spring(0.3), value: days)
  }

  private var together: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(daysTogether, format: .number)
        .font(.ourioHeroDigits)
        .foregroundStyle(Ink.text)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
      Text(daysTogether == 1 ? "day together" : "days together")
        .font(.ourioHeadline)
        .foregroundStyle(Ink.textSecondary)
    }
  }

  private func ring(days: Int, flame: Flame.State, next: Int?) -> some View {
    VStack(spacing: Space.xs) {
      ProgressRing(
        value: next.map { Double(days) / Double($0) } ?? 1,
        tint: Color(light: .honeyDeep, dark: .honeyBright)
      ) {
        VStack(spacing: 0) {
          Flame(days: days, state: flame)
          Text(days, format: .number)
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

  /// Its lead words in full ink, the rest quieter.
  private func line(_ status: LoveStreak.Status, turn: LoveStreak.Turn?, days: Int, next: Int?)
    -> Text
  {
    let (lead, rest) = words(status, turn: turn, days: days, next: next)
    return Text(lead).font(.ourioCallout.weight(.semibold)).foregroundStyle(Ink.text)
      + Text(rest).font(.ourioCallout).foregroundStyle(Ink.textSecondary)
  }

  private func words(_ status: LoveStreak.Status, turn: LoveStreak.Turn?, days: Int, next: Int?)
    -> (lead: String, rest: String)
  {
    switch turn {
    case .yours:
      return (
        "\(partner) did their part.", " Your turn: pet \(CatProfile.name()) or leave a note."
      )
    case .partners:
      return ("You did your part.", " The flame lights when \(partner) does theirs.")
    case nil: break
    }
    switch status {
    case .done:
      return ("Day \(days) is in.", next.map { " Badge at day \($0)." } ?? " See you tomorrow.")
    case .atRisk: return ("Keep it going.", " You both do one small thing today.")
    case .restorable: return ("You missed a day.", " You can bring the flame back once a month.")
    case .cold: return ("Light the flame", " together today.")
    }
  }

  private func label(days: Int, turn: LoveStreak.Turn?, next: Int?) -> String {
    let together = daysTogether == 1 ? "1 day together" : "\(daysTogether) days together"
    let streak = days == 1 ? "1-day streak" : "\(days)-day streak"
    let waiting =
      switch turn {
      case .yours: " \(partner) did their part, your turn."
      case .partners: " Waiting for \(partner)."
      case nil: ""
      }
    guard let next else { return "\(together). \(streak).\(waiting)" }
    let left = next - days
    return
      "\(together). \(streak), \(left) \(left == 1 ? "day" : "days") to the \(next)-day badge.\(waiting)"
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
