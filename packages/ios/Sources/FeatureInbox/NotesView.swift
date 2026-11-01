import DesignSystem
import Foundation
import SwiftUI

/// Every note sent and received, newest first. Tapping one opens it full screen.
public struct NotesView: View {
  private let notes: [NoteRecord]
  private let loadFailed: Bool

  @State private var opened: NoteRecord?

  public init(notes: [NoteRecord], loadFailed: Bool = false) {
    self.notes = notes
    self.loadFailed = loadFailed
  }

  public var body: some View {
    ZStack {
      EveningBackground()
      if notes.isEmpty {
        empty
      } else {
        list
      }
    }
    #if os(iOS)
      .fullScreenCover(item: $opened) { note in
        NoteDetailView(note: note) { opened = nil }
      }
    #endif
  }

  private var list: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.medium) {
        Text("Notes").screenTitle()
        LazyVStack(spacing: Spacing.small) {
          ForEach(notes) { note in
            Button {
              opened = note
            } label: {
              NoteRow(note: note)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the note full screen")
          }
        }
      }
      .padding(Spacing.medium)
    }
  }

  private var empty: some View {
    EmptyWire(
      title: loadFailed ? "Notes couldn't be loaded" : "No notes yet",
      message: loadFailed
        ? "Your saved notes couldn't be read on this device."
        : "Notes you send and receive will hang here."
    )
  }
}

/// One line of the list: the drawing, its direction, and when.
private struct NoteRow: View {
  let note: NoteRecord

  @ScaledMetric(relativeTo: .body) private var thumbnail: CGFloat = 72

  var body: some View {
    HStack(spacing: Spacing.medium) {
      NoteDrawing(note: note, side: 216)
        .frame(width: thumbnail, height: thumbnail)
      VStack(alignment: .leading, spacing: Spacing.hair) {
        Text(note.direction.title)
          .billetType(.body)
          .foregroundStyle(Palette.paper.color)
        Text(note.date, format: .dateTime.day().month().hour().minute())
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
      }
      Spacer(minLength: 0)
    }
    .padding(Spacing.small)
    .frame(minHeight: Target.minimum)
    .litPanel(cornerRadius: Radius.control)
    .contentShape(.rect(cornerRadius: Radius.control))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(note.accessibilityTitle)
  }
}

/// One note, as large as the screen allows.
struct NoteDetailView: View {
  let note: NoteRecord
  let onClose: () -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      EveningBackground()
      VStack(spacing: Spacing.medium) {
        Spacer(minLength: Spacing.page)
        NoteDrawing(note: note, side: 1080)
          .rotationEffect(.degrees(note.handTilt / 2))
          .lampGlow()
          .accessibilityLabel("Drawing")
        Text(note.direction.title)
          .billetType(.heading)
          .foregroundStyle(Palette.paper.color)
        Text(note.date, format: .dateTime.weekday(.wide).day().month().hour().minute())
          .billetType(.label)
          .foregroundStyle(Palette.paperTurned.color)
          .multilineTextAlignment(.center)
        Spacer(minLength: 0)
      }
      .padding(Spacing.medium)
      Button("Close", action: onClose)
        .buttonStyle(InlineButtonStyle())
        .padding(.horizontal, Spacing.medium)
        .accessibilityLabel("Close note")
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
  /// A small tilt that stays the same for a note, as if it were pinned up by hand.
  fileprivate var handTilt: Double {
    date.timeIntervalSince1970.truncatingRemainder(dividingBy: 5).rounded(.down) - 2
  }

  fileprivate var accessibilityTitle: String {
    "\(direction.title) note, \(date.formatted(date: .abbreviated, time: .shortened))"
  }
}
