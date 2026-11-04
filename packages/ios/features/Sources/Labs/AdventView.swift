import DesignSystem
import SwiftUI
import Wire

/// Home's advent calendar: twenty-four doors. An empty door is drawn behind for the partner, one
/// the partner filled opens from its day in December.
public struct AdventSection: View {
  private let store: AdventStore
  private let onDraw: (Int) -> Void

  @State private var viewing: Viewing?
  /// Pretends it is 12 December, so the doors can be tried before December.
  @State private var peeking = false

  public init(store: AdventStore, onDraw: @escaping (Int) -> Void) {
    self.store = store
    self.onDraw = onDraw
  }

  private struct Viewing: Identifiable {
    let number: Int
    let strokes: [Stroke]
    var id: Int { number }
  }

  private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.small), count: 6)

  public var body: some View {
    TimelineView(.everyMinute) { context in
      let calendar = Calendar.current
      let now =
        peeking ? Self.twelfthOfDecember(of: context.date, calendar: calendar) : context.date
      VStack(alignment: .leading, spacing: Spacing.small) {
        Text("Advent")
          .billetType(.body)
          .foregroundStyle(Palette.paper.color)
        Text(Self.words(today: AdventCalendar.todaysDoor(on: now, calendar: calendar)))
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
        LazyVGrid(columns: columns, spacing: Spacing.small) {
          ForEach(Array(AdventCalendar.doors), id: \.self) { number in
            door(number, now: now, calendar: calendar)
          }
        }
        if calendar.component(.month, from: context.date) != 12 {
          BilletButton(peeking ? "Back to today" : "Peek at 12 December", rank: .secondary) {
            peeking.toggle()
          }
        }
      }
      .padding(Spacing.medium)
      .frame(maxWidth: .infinity, alignment: .leading)
      .card()
      .accessibilityIdentifier("advent")
    }
    #if os(iOS)
      .fullScreenCover(item: $viewing) { viewing in
        ZStack(alignment: .topLeading) {
          EveningBackground()
          VStack(spacing: Spacing.medium) {
            Text("Door \(viewing.number)")
            .billetType(.heading)
            .foregroundStyle(Palette.paper.color)
            ReplayDrawing(strokes: viewing.strokes).lampGlow()
          }
          .padding(Spacing.medium)
          .frame(maxHeight: .infinity)
          IconButton("xmark", label: "Close door") { self.viewing = nil }
          .padding(Spacing.medium)
        }
      }
    #endif
  }

  static func twelfthOfDecember(of date: Date, calendar: Calendar) -> Date {
    calendar.date(
      from: DateComponents(
        year: calendar.component(.year, from: date), month: 12, day: 12, hour: 12))
      ?? date
  }

  static func words(today: Int?) -> String {
    if let today { return "Today's door is \(today). Open the ones your partner filled." }
    return "Draw behind a door for each other. They open from their day in December."
  }

  private func door(_ number: Int, now: Date, calendar: Calendar) -> some View {
    let filled = store.calendar.door(number)
    let openable = AdventCalendar.isOpenable(number, on: now, calendar: calendar)
    let canOpen = filled?.maker == .partner && filled?.opened == false && openable
    return Button {
      if let filled, filled.maker == .partner {
        if openable, let strokes = store.open(number, on: now, calendar: calendar) {
          viewing = Viewing(number: number, strokes: strokes)
        } else if filled.opened {
          viewing = Viewing(number: number, strokes: filled.strokes)
        }
      } else if filled == nil {
        onDraw(number)
      }
    } label: {
      Text("\(number)")
        .billetType(.label)
        .monospacedDigit()
        .foregroundStyle(foreground(filled))
        .frame(maxWidth: .infinity, minHeight: Target.minimum)
        .background(fill(filled), in: .rect(cornerRadius: Radius.paper))
        .overlay {
          RoundedRectangle(cornerRadius: Radius.paper)
            .strokeBorder(
              canOpen ? Palette.gold.color : Palette.paper.color.opacity(0.18),
              lineWidth: canOpen ? 2 : 1)
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label(number, filled, canOpen: canOpen))
  }

  private func fill(_ door: AdventCalendar.Door?) -> Color {
    guard let door else { return .clear }
    switch (door.maker, door.opened) {
    case (.partner, true): return Palette.light.color
    case (.partner, false): return Palette.clay.color
    case (.me, _): return Palette.wood.color
    }
  }

  private func foreground(_ door: AdventCalendar.Door?) -> Color {
    guard let door else { return Palette.muted.color }
    return door.maker == .partner && door.opened ? Palette.ink.color : Palette.paper.color
  }

  private func label(_ number: Int, _ door: AdventCalendar.Door?, canOpen: Bool) -> String {
    guard let door else { return "Door \(number), empty. Draw behind it." }
    switch door.maker {
    case .me: return "Door \(number), you drew behind it."
    case .partner:
      if door.opened { return "Door \(number), opened." }
      return canOpen
        ? "Door \(number), ready to open." : "Door \(number), from your partner, not yet."
    }
  }
}
