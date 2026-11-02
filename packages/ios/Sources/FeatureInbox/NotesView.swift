import DesignSystem
import Foundation
import SwiftUI

/// Every note sent and received, newest first. Tapping one opens it full screen.
public struct NotesView: View {
  private let notes: [NoteRecord]
  private let loadFailed: Bool
  private let reactions: [UUID: Reaction]
  private let onReact: ((NoteRecord, Reaction) -> Void)?
  private let detailDrawing: ((NoteRecord) -> AnyView)?
  private let detailActions: ((NoteRecord) -> AnyView)?
  private let board: ((NoteBoard) -> AnyView)?

  @Namespace private var zoom
  @State private var opened: NoteRecord?
  @State private var boardOpen = false

  /// - Parameters:
  ///   - reactions: The reaction each note has received.
  ///   - onReact: Called when a received note is reacted to. `nil` shows no way to react.
  ///   - detailDrawing: Shows a note's drawing in the full-screen view instead of the still one.
  ///   - detailActions: Extra controls shown under a note in the full-screen view.
  ///   - board: Another way to see the notes, reached from the top of the list.
  public init(
    notes: [NoteRecord],
    loadFailed: Bool = false,
    reactions: [UUID: Reaction] = [:],
    onReact: ((NoteRecord, Reaction) -> Void)? = nil,
    detailDrawing: ((NoteRecord) -> AnyView)? = nil,
    detailActions: ((NoteRecord) -> AnyView)? = nil,
    board: ((NoteBoard) -> AnyView)? = nil
  ) {
    self.detailDrawing = detailDrawing
    self.detailActions = detailActions
    self.board = board
    self.notes = notes
    self.loadFailed = loadFailed
    self.reactions = reactions
    self.onReact = onReact
  }

  public var body: some View {
    ScreenScaffold("Notes") {
      if board != nil { boardRow }
      if notes.isEmpty {
        EmptyWire(
          title: loadFailed ? "Notes couldn't be loaded" : "No notes yet",
          message: loadFailed
            ? "Your saved notes couldn't be read on this device."
            : "Notes you send and receive will hang here."
        )
        .transition(.opacity)
      } else {
        LazyVStack(spacing: 0) {
          ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
            if index > 0 {
              ListDivider()
            }
            row(note)
          }
        }
        .card()
        .transition(.opacity)
      }
    }
    .calmAnimation(value: notes.count)
    #if os(iOS)
      .fullScreenCover(item: $opened) { note in
        detail(of: note) { opened = nil }
        .navigationTransition(.zoom(sourceID: note.id, in: zoom))
      }
      .fullScreenCover(isPresented: $boardOpen) {
        if let board {
          board(
            NoteBoard(
              notes: notes, reactions: reactions, detail: { AnyView(detail(of: $0, close: $1)) },
              close: { boardOpen = false }))
        }
      }
    #endif
  }

  private func detail(of note: NoteRecord, close: @escaping () -> Void) -> some View {
    NoteDetailView(
      note: note, reaction: reactions[note.id], drawing: detailDrawing?(note),
      actions: detailActions?(note),
      onReact: note.direction == .received ? onReact.map { react in { react(note, $0) } } : nil,
      onClose: close)
  }

  private var boardRow: some View {
    Button {
      boardOpen = true
    } label: {
      ListRow("The shelf", subtitle: "Everything you have sent each other") {
        ShelfMark().frame(width: 34, height: 28).accessibilityHidden(true)
      } trailing: {
        RowIcon("chevron.forward")
      }
    }
    .buttonStyle(RowButtonStyle())
    .card()
    .accessibilityIdentifier("shelfBoard")
  }

  @ViewBuilder private func row(_ note: NoteRecord) -> some View {
    let button = Button {
      opened = note
    } label: {
      NoteRow(note: note, reaction: reactions[note.id])
    }
    .buttonStyle(RowButtonStyle())
    .accessibilityHint("Opens the note full screen")
    #if os(iOS)
      button.matchedTransitionSource(id: note.id, in: zoom)
    #else
      button
    #endif
  }
}

/// What another view of the notes is given by the list.
public struct NoteBoard {
  public let notes: [NoteRecord]
  public let reactions: [UUID: Reaction]
  /// One note full screen. The closure closes it.
  public let detail: (NoteRecord, @escaping () -> Void) -> AnyView
  public let close: () -> Void
}

/// Two small sheets on a plank, the row's picture.
private struct ShelfMark: View {
  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .bottom, spacing: 3) {
        RoundedRectangle(cornerRadius: 1.5).fill(Palette.paper.color)
          .frame(width: 13, height: 18).rotationEffect(.degrees(-5))
        RoundedRectangle(cornerRadius: 1.5).fill(Palette.paperTurned.color)
          .frame(width: 11, height: 14).rotationEffect(.degrees(4))
      }
      RoundedRectangle(cornerRadius: 1).fill(Palette.woodLit.color).frame(height: 4)
    }
  }
}

/// One line of the list: the drawing, its direction, and when.
private struct NoteRow: View {
  let note: NoteRecord
  let reaction: Reaction?

  @ScaledMetric(relativeTo: .body) private var thumbnail: CGFloat = 64

  var body: some View {
    ListRow(
      note.direction.title,
      subtitle: note.date.formatted(NoteDate.style(of: note.date))
    ) {
      NoteDrawing(note: note, side: 216)
        .frame(width: thumbnail, height: thumbnail)
    } trailing: {
      HStack(spacing: Spacing.small) {
        if let reaction { ReactionMark(reaction) }
        RowIcon("chevron.forward")
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(note.accessibilityTitle + (reaction.map { ", \($0.title)" } ?? ""))
  }
}

/// One note, as large as the screen allows.
struct NoteDetailView: View {
  let note: NoteRecord
  let reaction: Reaction?
  /// Stands in for the still drawing when given.
  let drawing: AnyView?
  /// Extra controls under the note.
  let actions: AnyView?
  /// `nil` when the note is not one to react to.
  let onReact: ((Reaction) -> Void)?
  let onClose: () -> Void

  var body: some View {
    ZStack(alignment: .topLeading) {
      EveningBackground()
      VStack(spacing: Spacing.small) {
        Spacer(minLength: Spacing.page)
        Group {
          if let drawing {
            drawing
          } else {
            NoteDrawing(note: note, side: 1080)
          }
        }
        .lampGlow()
        .accessibilityLabel("Drawing")
        .padding(.bottom, Spacing.medium)
        Text(note.direction.title)
          .billetType(.heading)
          .foregroundStyle(Palette.paper.color)
        Text(note.date, format: NoteDate.style(of: note.date).weekday(.wide))
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
          .multilineTextAlignment(.center)
        if let onReact {
          ReactionBar(chosen: reaction, onReact: onReact)
            .padding(.top, Spacing.small)
        } else if let reaction {
          ReactionMark(reaction)
            .padding(.top, Spacing.small)
        }
        if let actions { actions }
        Spacer(minLength: 0)
      }
      .padding(Spacing.medium)
      IconButton("xmark", label: "Close note", action: onClose)
        .padding(Spacing.medium)
    }
  }
}

extension NoteRecord.Direction {
  fileprivate var title: String {
    switch self {
    case .sent: "Sent"
    case .received: "Received"
    }
  }
}

extension NoteRecord {
  fileprivate var accessibilityTitle: String {
    "\(direction.title) note, \(date.formatted(date: .abbreviated, time: .shortened))"
  }
}

/// How a note's date reads. A note from another year says which.
enum NoteDate {
  static func style(
    of date: Date, now: Date = .now, calendar: Calendar = .current
  ) -> Date.FormatStyle {
    let style = Date.FormatStyle.dateTime.day().month().hour().minute()
    return calendar.isDate(date, equalTo: now, toGranularity: .year) ? style : style.year()
  }
}
