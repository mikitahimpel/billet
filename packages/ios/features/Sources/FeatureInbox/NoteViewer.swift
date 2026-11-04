import DesignSystem
import SwiftUI

/// One note full screen, as the list opens it: the drawing (or its replay), the reactions and any
/// extra actions. For screens outside the list that open a note, such as the desk.
public struct NoteViewer: View {
  private let note: NoteRecord
  private let reaction: Reaction?
  private let drawing: AnyView?
  private let actions: AnyView?
  private let onReact: ((Reaction) -> Void)?
  private let onClose: () -> Void

  /// - Parameters:
  ///   - drawing: Stands in for the still drawing when given.
  ///   - actions: Extra controls under the note.
  ///   - onReact: Called when a received note is reacted to. Ignored for a sent note.
  public init(
    note: NoteRecord,
    reaction: Reaction?,
    drawing: AnyView? = nil,
    actions: AnyView? = nil,
    onReact: ((Reaction) -> Void)? = nil,
    onClose: @escaping () -> Void
  ) {
    self.note = note
    self.reaction = reaction
    self.drawing = drawing
    self.actions = actions
    self.onReact = onReact
    self.onClose = onClose
  }

  public var body: some View {
    NoteDetailView(
      note: note, reaction: reaction, drawing: drawing, actions: actions,
      onReact: note.direction == .received ? onReact : nil, onClose: onClose)
  }
}
