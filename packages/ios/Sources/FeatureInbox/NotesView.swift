import DesignSystem
import Foundation
import SwiftUI

/// Every note sent and received, newest first. Tapping one opens it full screen.
public struct NotesView: View {
  private let notes: [NoteRecord]
  private let loadFailed: Bool

  @Namespace private var zoom
  @State private var opened: NoteRecord?

  public init(notes: [NoteRecord], loadFailed: Bool = false) {
    self.notes = notes
    self.loadFailed = loadFailed
  }

  public var body: some View {
    ScreenScaffold("Notes") {
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
        NoteDetailView(note: note) { opened = nil }
        .navigationTransition(.zoom(sourceID: note.id, in: zoom))
      }
    #endif
  }

  @ViewBuilder private func row(_ note: NoteRecord) -> some View {
    let button = Button {
      opened = note
    } label: {
      NoteRow(note: note)
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

/// One line of the list: the drawing, its direction, and when.
private struct NoteRow: View {
  let note: NoteRecord

  @ScaledMetric(relativeTo: .body) private var thumbnail: CGFloat = 64

  var body: some View {
    ListRow(
      note.direction.title,
      subtitle: note.date.formatted(.dateTime.day().month().hour().minute())
    ) {
      NoteDrawing(note: note, side: 216)
        .frame(width: thumbnail, height: thumbnail)
    } trailing: {
      RowIcon("chevron.forward")
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(note.accessibilityTitle)
  }
}

/// One note, as large as the screen allows.
struct NoteDetailView: View {
  let note: NoteRecord
  let onClose: () -> Void

  var body: some View {
    ZStack(alignment: .topLeading) {
      EveningBackground()
      VStack(spacing: Spacing.small) {
        Spacer(minLength: Spacing.page)
        NoteDrawing(note: note, side: 1080)
          .lampGlow()
          .accessibilityLabel("Drawing")
          .padding(.bottom, Spacing.medium)
        Text(note.direction.title)
          .billetType(.heading)
          .foregroundStyle(Palette.paper.color)
        Text(note.date, format: .dateTime.weekday(.wide).day().month().hour().minute())
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
          .multilineTextAlignment(.center)
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
