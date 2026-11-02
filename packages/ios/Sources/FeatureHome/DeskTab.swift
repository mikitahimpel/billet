import CoreGraphics
import DesignSystem
import FeatureCanvas
import FeatureInbox
import Ink
import Pet
import PetScene
import SwiftUI
import WidgetBridge

/// The Notes tab as a desk: tap the paper to draw in the canvas, tap a note on the board to open
/// it full screen. The list of every note stays one tap away, for VoiceOver and for many notes.
struct DeskTab: View {
  let session: PairSession
  let scene: any PetScene
  let widgetFeatures: WidgetFeaturesModel
  /// Stands in for a note's still drawing in the full-screen view.
  let detailDrawing: ((NoteRecord) -> AnyView)?
  /// Extra controls under a note in the full-screen view.
  let detailActions: ((NoteRecord) -> AnyView)?
  /// The list of notes, as Notes shows it without the desk.
  let list: () -> AnyView

  @State private var desk: [DeskNote] = []
  @State private var drawing = false
  @State private var opened: NoteRecord?
  @State private var listOpen = false

  var body: some View {
    ZStack(alignment: .topTrailing) {
      scene.makeDeskScene(state: DeskSceneState(notes: desk)) { event in
        switch event {
        case .paperTapped: drawing = true
        case .noteTapped(let id): opened = session.notes.first { $0.id == id }
        }
      }
      GlassGroup {
        IconButton("list.bullet", label: "All notes") { listOpen = true }
      }
      .padding(.horizontal, Spacing.medium)
      .padding(.top, Spacing.small)
      .accessibilityIdentifier("notesList")
    }
    .environment(\.petSceneCat, session.labs.cat)
    .task(id: session.notes.map(\.id)) {
      desk = Self.pinned(session.notes)
    }
    #if os(iOS)
      .fullScreenCover(isPresented: $drawing) {
        CanvasView(
          prompt: DailyPrompt.canvasPrompt(
            features: widgetFeatures.features, day: TreatDay.key(for: .now, calendar: .current)),
          onClose: { drawing = false },
          onSend: {
            session.send($0)
            drawing = false
          }
        )
      }
      .fullScreenCover(item: $opened) { note in
        NoteViewer(
          note: note, reaction: session.play.reactions[note.id], drawing: detailDrawing?(note),
          actions: detailActions?(note), onReact: { session.react(to: note, $0) },
          onClose: { opened = nil })
      }
    #endif
    .sheet(isPresented: $listOpen) {
      list()
        .overlay(alignment: .topTrailing) {
          IconButton("xmark", label: "Close the list") { listOpen = false }
            .padding(Spacing.medium)
        }
        .presentationDetents([.large])
    }
  }

  /// The notes the board can hold, newest first, with their drawings.
  static func pinned(_ notes: [NoteRecord]) -> [DeskNote] {
    notes.sorted { $0.date > $1.date }.prefix(DeskTab.boardSize).compactMap { note in
      NoteImage.cgImage(of: note.strokes).map {
        DeskNote(id: note.id, image: $0, isReceived: note.direction == .received)
      }
    }
  }

  /// As many notes as the desk's board pins; the rest are in the list.
  static let boardSize = 9
}
