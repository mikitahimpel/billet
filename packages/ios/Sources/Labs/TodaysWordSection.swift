import DesignSystem
import FeatureInbox
import Pet
import SwiftUI

/// Home's card for the day's word: draw it, or put it away until tomorrow. It also goes once a
/// note has been sent today.
public struct TodaysWordSection: View {
  private let notes: [NoteRecord]
  private let onDraw: () -> Void

  @AppStorage("labs.todaysWord.dismissedDay") private var dismissedDay = ""

  public init(notes: [NoteRecord], onDraw: @escaping () -> Void) {
    self.notes = notes
    self.onDraw = onDraw
  }

  public var body: some View {
    TimelineView(.everyMinute) { context in
      let calendar = Calendar.current
      let day = TreatDay.key(for: context.date, calendar: calendar)
      let sentToday = notes.contains {
        $0.direction == .sent && calendar.isDate($0.date, inSameDayAs: context.date)
      }
      if let word = TodaysWord.word(onDay: day),
        TodaysWord.isShown(
          onDay: day, dismissedDay: dismissedDay.isEmpty ? nil : dismissedDay, sentToday: sentToday)
      {
        card(word: word, day: day)
          .transition(.opacity)
      }
    }
  }

  private func card(word: String, day: String) -> some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Text("Today's word")
        .billetType(.label)
        .foregroundStyle(Palette.muted.color)
      Text(word)
        .billetType(.heading)
        .foregroundStyle(Palette.paper.color)
        .accessibilityIdentifier("todaysWord")
      HStack(spacing: Spacing.small) {
        BilletButton("Draw it", rank: .secondary, action: onDraw)
        BilletButton("Not today", rank: .secondary) {
          withAnimation(Motion.spring) { dismissedDay = day }
        }
      }
    }
    .padding(Spacing.medium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }
}
