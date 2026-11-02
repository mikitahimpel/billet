import DesignSystem
import FeatureInbox
import Ink
import SwiftUI
import Wire

/// A warm wall of shelves holding every note the two of you have sent, the newest large and
/// forward. Tapping a note lifts it from its shelf and opens it.
public struct ShelfBoardView: View {
  private static let liftTime = Duration.milliseconds(240)

  private let notes: [NoteRecord]
  private let reactions: [UUID: Reaction]
  private let streak: Int
  private let detail: (NoteRecord, @escaping () -> Void) -> AnyView
  private let onClose: () -> Void

  @ScaledMetric(relativeTo: .body) private var scaledNoteWidth: CGFloat = 74
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var zoom
  @State private var opened: NoteRecord?
  @State private var lifted: UUID?

  /// - Parameters:
  ///   - streak: The days the streak has reached. The empty slots count on from it.
  ///   - detail: One note full screen. Its closure closes it.
  public init(
    notes: [NoteRecord],
    reactions: [UUID: Reaction] = [:],
    streak: Int,
    detail: @escaping (NoteRecord, @escaping () -> Void) -> AnyView,
    onClose: @escaping () -> Void
  ) {
    self.notes = notes
    self.reactions = reactions
    self.streak = streak
    self.detail = detail
    self.onClose = onClose
  }

  public var body: some View {
    ZStack(alignment: .topLeading) {
      ShelfWall()
      GeometryReader { geometry in
        let width = geometry.size.width - Spacing.medium * 2
        let noteWidth = ShelfBoard.noteWidth(scaled: scaledNoteWidth, width: width)
        ScrollView {
          content(
            ShelfBoard(notes: notes, streak: streak, width: width, noteWidth: noteWidth),
            width: width, noteWidth: noteWidth)
        }
        .scrollIndicators(.hidden)
        // A lazy stack that re-measures every row at its old offset never settles and hangs.
        .id([width, noteWidth])
      }
      LinearGradient(
        colors: [Palette.plate.color, Palette.plate.color.opacity(0)], startPoint: .top,
        endPoint: .bottom
      )
      .frame(height: Spacing.page)
      .ignoresSafeArea(edges: .top)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      IconButton("xmark", label: "Close the shelf", action: onClose)
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.small)
    }
    #if os(iOS)
      .fullScreenCover(
        item: $opened,
        onDismiss: { lifted = nil },
        content: { note in
          detail(note) { opened = nil }
            .navigationTransition(.zoom(sourceID: note.id, in: zoom))
        }
      )
    #endif
  }

  private func content(_ board: ShelfBoard, width: CGFloat, noteWidth: CGFloat) -> some View {
    let spacing = board.spacing(width: width, noteWidth: noteWidth)
    return VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: Spacing.small) {
        header
        ShelfCanopy()
      }
      .background(alignment: .bottomTrailing) {
        ShelfLampGlow()
          .offset(
            x: ShelfLampGlow.side / 2 - Spacing.page,
            y: ShelfLampGlow.side / 2 - Spacing.wide)
      }
      LazyVStack(alignment: .leading, spacing: 0) {
        if let above = board.above {
          shelf(above, noteWidth: noteWidth, spacing: spacing).padding(.top, -Spacing.small)
        }
        forward(board, width: width).padding(.top, Spacing.medium)
        ForEach(board.below) {
          shelf($0, noteWidth: noteWidth, spacing: spacing).padding(.top, Spacing.large)
        }
        if !notes.isEmpty {
          Text(notes.count == 1 ? "1 note on the shelf" : "\(notes.count) notes on the shelf")
            .billetType(.caption)
            .foregroundStyle(Palette.muted.color)
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.large)
        }
      }
    }
    .padding(.bottom, Spacing.large)
    .padding(.horizontal, Spacing.medium)
  }

  private var header: some View {
    Text("What you send each other stays on the shelf.")
      .billetType(.title)
      .foregroundStyle(Palette.paper.color)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityAddTraits(.isHeader)
      .padding(.top, Spacing.small + Target.minimum + Spacing.medium)
  }

  private func shelf(_ shelf: ShelfBoard.Shelf, noteWidth: CGFloat, spacing: CGFloat) -> some View {
    VStack(spacing: 0) {
      HStack(alignment: .bottom, spacing: spacing) {
        ForEach(shelf.items) { item in
          switch item {
          case .note(let placement): noteButton(placement, width: noteWidth)
          case .slot(let day): ShelfSlot(day: day, width: noteWidth)
          }
        }
        Spacer(minLength: 0)
      }
      plank
        .overlay(alignment: .topTrailing) {
          if let milestone = shelf.milestone {
            HousePlate(milestone, scale: 0.5)
              .padding(.trailing, Spacing.medium)
              .offset(y: Spacing.hair)
          }
        }
    }
  }

  /// Runs the full width of the wall, past the margin the notes keep.
  private var plank: some View {
    ShelfPlank().padding(.horizontal, -Spacing.medium)
  }

  private func noteButton(_ placement: ShelfBoard.Placement, width: CGFloat) -> some View {
    let isLifted = lifted == placement.id
    return Button {
      open(placement.note)
    } label: {
      ShelfNote(note: placement.note, side: 240, isWarmPaper: placement.isWarmPaper)
        .frame(
          width: width,
          height: width
            * (placement.isTall ? ShelfNoteMetrics.tallRatio : ShelfNoteMetrics.shortRatio))
    }
    .buttonStyle(.plain)
    .rotationEffect(.degrees(isLifted ? 0 : placement.tilt), anchor: .bottom)
    .scaleEffect(isLifted && !reduceMotion ? 1.3 : 1, anchor: .bottom)
    .offset(y: isLifted && !reduceMotion ? -Spacing.small : 0)
    .zIndex(isLifted ? 1 : 0)
    .calmAnimation(value: isLifted)
    .accessibilityLabel(Self.title(of: placement.note))
    .accessibilityHint("Opens the note full screen")
    .transitionSource(id: placement.id, in: zoom)
  }

  @ViewBuilder private func forward(_ board: ShelfBoard, width: CGFloat) -> some View {
    let heroWidth = board.cupsBeside ? width * 0.59 : width - Spacing.wide
    ZStack(alignment: .bottomLeading) {
      VStack(alignment: .trailing, spacing: 0) {
        if board.cupsBeside {
          ShelfCups()
        } else {
          Color.clear.frame(height: Spacing.wide)
        }
        plank
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
      ShelfKeys()
        .padding(.leading, -Spacing.hair)
        .frame(maxHeight: .infinity, alignment: .topLeading)
      Group {
        if let placement = board.forward {
          hero(placement, width: heroWidth)
        } else {
          emptyNote(width: heroWidth)
        }
      }
      .padding(.leading, Spacing.wide + Spacing.small)
      .padding(.bottom, -Spacing.small)
    }
    if !board.cupsBeside {
      VStack(alignment: .trailing, spacing: 0) {
        ShelfCups().frame(maxWidth: .infinity)
        plank
      }
      .padding(.top, Spacing.large)
    }
  }

  private func hero(_ placement: ShelfBoard.Placement, width: CGFloat) -> some View {
    let isLifted = lifted == placement.id
    return Button {
      open(placement.note)
    } label: {
      VStack(spacing: Spacing.small) {
        ShelfNote(note: placement.note, side: 900, isPlain: true)
          .aspectRatio(1, contentMode: .fit)
        HStack(alignment: .center, spacing: Spacing.small) {
          Text(placement.note.direction == .received ? "From your partner" : "From you")
            .billetType(.label)
            .foregroundStyle(Palette.clay.color)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          if streak > 0 { HousePlate(streak, scale: 0.55) }
        }
      }
      .padding(Spacing.small + Spacing.hair)
      .frame(width: width)
      .background { ForwardPaper() }
      .overlay(alignment: .topTrailing) {
        if let reaction = reactions[placement.id] {
          ReactionMark(reaction).padding(Spacing.small)
        }
      }
    }
    .buttonStyle(.plain)
    .rotationEffect(.degrees(isLifted ? 0 : -3.5))
    .scaleEffect(isLifted && !reduceMotion ? 1.05 : 1)
    .calmAnimation(value: isLifted)
    .accessibilityLabel("Newest note. " + Self.title(of: placement.note))
    .accessibilityHint("Opens the note full screen")
    .transitionSource(id: placement.id, in: zoom)
  }

  private func emptyNote(width: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Text("Nothing on the shelf yet")
        .billetType(.heading)
        .foregroundStyle(Palette.ink.color)
      Text("The first note either of you sends will stand here.")
        .billetType(.body)
        .foregroundStyle(Palette.clayDeep.color)
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding(Spacing.medium)
    .frame(width: width, alignment: .leading)
    .background { ForwardPaper() }
    .rotationEffect(.degrees(-2.5))
  }

  private func open(_ note: NoteRecord) {
    lifted = note.id
    Task {
      if !reduceMotion { try? await Task.sleep(for: Self.liftTime) }
      opened = note
    }
  }

  private static func title(of note: NoteRecord) -> String {
    let direction = note.direction == .received ? "From your partner" : "From you"
    return "\(direction), \(note.date.formatted(date: .abbreviated, time: .shortened))"
  }
}

/// The sheet the note in front stands on, casting one soft shadow onto the wall.
private struct ForwardPaper: View {
  var body: some View {
    RoundedRectangle(cornerRadius: Radius.paper)
      .fill(Palette.paper.color)
      .shadow(color: Palette.plate.color.opacity(0.7), radius: 14, x: 2, y: 8)
  }
}

/// A note's drawing on a sheet, rendered away from the main actor as it comes on screen.
private struct ShelfNote: View {
  let note: NoteRecord
  let side: Int
  var isPlain = false
  var isWarmPaper = false

  @State private var image: CGImage?

  var body: some View {
    RoundedRectangle(cornerRadius: isPlain ? Radius.scenePaper : Radius.scenePaper + 1)
      .fill(isWarmPaper ? Palette.paperTurned.color : Palette.paper.color)
      .shadow(color: isPlain ? .clear : Palette.plate.color.opacity(0.6), radius: 4, x: 1, y: 3)
      .overlay {
        if let image {
          Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFit()
            .padding(isPlain ? 0 : Spacing.hair)
        }
      }
      .task(id: note.id) {
        let strokes = note.strokes
        let side = side
        image = await Task.detached { NoteImage.cgImage(of: strokes, side: side) }.value
      }
  }
}

extension View {
  /// The note a full-screen note zooms out of.
  @ViewBuilder
  fileprivate func transitionSource(id: UUID, in namespace: Namespace.ID) -> some View {
    #if os(iOS)
      matchedTransitionSource(id: id, in: namespace)
    #else
      self
    #endif
  }
}
