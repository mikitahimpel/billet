import CoreGraphics
import DesignSystem
import FeatureInbox
import Foundation
import Ink
import Labs
import Pet
import PetScene
import SwiftUI

/// Home for the room: the room fills the screen and the controls float over it. The streak sits
/// top left. The latest note lives in the room, marked while it is unread, and a toast says so
/// for a moment when one has just come. Treats are given in the room itself, and notes are drawn
/// from the Notes tab. The closet comes from ``HomeShop``. Tapping the streak opens
/// its flame, zooming out of the chip.
struct StyledHome: View {
  private static let streakSource = "streak"
  /// The scene's view, with the host's environment already set.
  let scene: AnyView
  let notes: [NoteRecord]
  let streak: Int
  let isFakePartner: Bool
  /// Whether the newest note from the partner has not been opened yet.
  var isNoteUnread = false
  let onOpenNotes: () -> Void
  /// Whether the room is being decorated, which hides everything over it but its own controls.
  var isDecorating = false
  /// Whether the launch's glide into the room is playing, which keeps the controls back.
  var isOpening = false
  /// Opens the room for moving its furniture, right where it is.
  var onDecorate: (() -> Void)?
  /// Opens the streak's flame, or `nil` when the chip only shows the count.
  var flame: StreakFlameHost?
  /// The cat's needs and mood, for the paw by the streak, or nil to leave it out.
  var mood: CatNeedsSnapshot?
  /// Does a need's action from the needs card, as the room's own gestures do.
  var onAnswer: ((PetNeed) -> Void)?
  /// First in the top row, before the streak: the way into "Us".
  var leading: AnyView?
  /// Last in the top row, at the far edge: the closet.
  var trailing: AnyView?

  @State private var latestDrawing: CGImage?
  /// What the flame shows, set as it opens so the visit is remembered once, and kept while it
  /// zooms closed.
  @State private var flameState: FlameSceneState?
  @State private var isFlameOpen = false
  /// The note the toast is telling about, while it shows.
  @State private var toastNote: UUID?
  @State private var arrivals = NoteArrivals()
  @State private var isMoodOpen = false
  @Namespace private var zoom

  private var latestReceived: NoteRecord? {
    notes.first { $0.direction == .received }
  }

  var body: some View {
    ZStack {
      scene
        .environment(\.petSceneDrawing, latestDrawing)
        .ignoresSafeArea()
      if !isDecorating, !isOpening {
        VStack(spacing: 0) {
          header
          Spacer(minLength: 0)
          if toastNote != nil {
            toast
              .padding(.bottom, Spacing.medium)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }
        .transition(.opacity)
      }
    }
    .calmAnimation(value: isDecorating)
    .calmAnimation(value: isOpening)
    .calmAnimation(value: toastNote)
    .environment(\.petSceneNoteUnread, isNoteUnread)
    .task(id: latestReceived?.id) {
      guard arrivals.update(latestReceived?.id) else { return }
      await noteArrived(latestReceived?.id)
    }
    .task(id: latestReceived?.id) {
      guard let note = latestReceived else {
        latestDrawing = nil
        return
      }
      latestDrawing = NoteImage.cgImage(of: note.strokes)
    }
    .needsSheet(isPresented: $isMoodOpen, mood: mood) { onAnswer?($0) }
    .task {
      guard let delay = ShotHooks.openNeeds else { return }
      try? await Task.sleep(for: delay)
      isMoodOpen = true
    }
    .flameCover(isPresented: $isFlameOpen, source: Self.streakSource, in: zoom) {
      if let flame, let flameState {
        flame.view(flameState) { isFlameOpen = false }
      }
    }
  }

  /// One row of glass chips, all one height on one line, at the same side margins as the cards
  /// under it.
  private var header: some View {
    GlassGroup {
      HStack(spacing: Spacing.small) {
        if let leading { usChip(leading) }
        streakChip
        if let mood {
          CatMoodChip(mood) { isMoodOpen = true }
        }
        if let onDecorate {
          IconButton("sofa.fill", label: "Decorate the room", action: onDecorate)
            .accessibilityIdentifier("styledDecorateButton")
        }
        Spacer(minLength: 0)
        if let trailing { trailing }
      }
      .frame(height: Target.minimum)
    }
    .padding(.top, Spacing.small)
    .padding(.horizontal, Spacing.medium)
  }

  /// The way into "Us" as a chip like the others. While the partner is scripted, a gold dot on
  /// it says so, so nobody takes the replies for a person.
  private func usChip(_ avatars: AnyView) -> some View {
    avatars
      .padding(.horizontal, Spacing.small)
      .frame(height: Target.minimum)
      .floatingGlass()
      .overlay(alignment: .topTrailing) {
        if isFakePartner { demoDot }
      }
  }

  private var demoDot: some View {
    Circle()
      .fill(Palette.gold.color)
      .frame(width: Self.dot, height: Self.dot)
      .overlay(Circle().stroke(Palette.pageDeep.color.opacity(0.55), lineWidth: 1.5))
      .accessibilityElement()
      .accessibilityLabel("Demo: a fake partner with scripted replies, on this phone only")
      .accessibilityIdentifier("fakePartnerNotice")
  }

  /// The size of the demo dot, which sits on the chip's corner like a badge.
  private static let dot: CGFloat = 10

  @ViewBuilder private var streakChip: some View {
    if let flame {
      Button {
        flameState = flame.open()
        isFlameOpen = true
      } label: {
        streakLabel.contentShape(.capsule)
      }
      .buttonStyle(RowButtonStyle())
      .floatingGlass()
      .accessibilityLabel("Streak: \(streak) \(streak == 1 ? "day" : "days")")
      .accessibilityHint("Opens your shared flame")
      .accessibilityIdentifier("styledStreak")
      .streakSource(id: Self.streakSource, in: zoom)
    } else {
      streakLabel
        .floatingGlass()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Streak: \(streak) \(streak == 1 ? "day" : "days")")
        .accessibilityIdentifier("styledStreak")
    }
  }

  private var streakLabel: some View {
    HStack(spacing: Spacing.small) {
      Image(systemName: "flame.fill")
        .font(IconStyle.font)
        .foregroundStyle(Palette.gold.color)
        .accessibilityHidden(true)
      Text(verbatim: "\(streak)")
        .billetType(.action)
        .foregroundStyle(Palette.paper.color)
        .contentTransition(.numericText(value: Double(streak)))
      Text(streak == 1 ? "day" : "days")
        .billetType(.label)
        .foregroundStyle(Palette.paper.color)
    }
    .padding(.leading, Spacing.medium - Spacing.hair)
    .padding(.trailing, Spacing.medium)
    .frame(minHeight: Target.minimum)
  }

  /// Says a note has just come, for a moment, over the bottom of the room. Tapping it opens the
  /// note, as tapping the note in the room does.
  private var toast: some View {
    Button {
      toastNote = nil
      onOpenNotes()
    } label: {
      HStack(spacing: Spacing.small) {
        Image(systemName: "envelope.fill")
          .font(IconStyle.font)
          .foregroundStyle(Palette.gold.color)
          .accessibilityHidden(true)
        Text(Self.toastText)
          .billetType(.action)
          .foregroundStyle(Palette.paper.color)
      }
      .padding(.horizontal, Spacing.medium + Spacing.hair)
      .frame(minHeight: Target.minimum)
      .contentShape(.capsule)
    }
    .buttonStyle(RowButtonStyle())
    .floatingGlass()
    .accessibilityHint("Opens the note")
    .accessibilityIdentifier("newNoteToast")
  }

  static let toastText = "New note from your partner"
  /// How long the toast stays.
  static let toastHold = Duration.milliseconds(3_500)

  /// Shows the toast for a note that has just come in while Home is up, and not for the one that
  /// was already there when it opened.
  private func noteArrived(_ id: UUID?) async {
    guard let id, isNoteUnread else { return }
    toastNote = id
    #if os(iOS)
      AccessibilityNotification.Announcement(Self.toastText).post()
    #endif
    try? await Task.sleep(for: Self.toastHold)
    guard !Task.isCancelled, toastNote == id else { return }
    toastNote = nil
  }
}

extension View {
  /// The flame over everything, zooming out of `source`, on iOS.
  fileprivate func flameCover<Content: View>(
    isPresented: Binding<Bool>, source: String, in namespace: Namespace.ID,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    #if os(iOS)
      fullScreenCover(isPresented: isPresented) {
        content().navigationTransition(.zoom(sourceID: source, in: namespace))
      }
    #else
      self
    #endif
  }

  /// Where the flame zooms out of, on iOS.
  fileprivate func streakSource(id: String, in namespace: Namespace.ID) -> some View {
    #if os(iOS)
      matchedTransitionSource(id: id, in: namespace)
    #else
      self
    #endif
  }
}

/// Tells a note that has just come from the one Home opened on.
struct NoteArrivals: Equatable {
  private var known: UUID??

  /// Takes the newest note's id, and says whether it is a new one arriving: never the first id
  /// seen, nor no note at all.
  mutating func update(_ id: UUID?) -> Bool {
    defer { known = .some(id) }
    guard let known else { return false }
    return id != nil && id != known
  }
}
