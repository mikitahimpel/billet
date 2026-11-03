import CoreGraphics
import DesignSystem
import FeatureInbox
import Foundation
import Ink
import Pet
import PetScene
import SwiftUI

/// Home for the room: the room fills the screen and the controls float over it. The streak sits
/// top left and the latest note's caption at the bottom. Treats are given in the room itself, and
/// notes are drawn from the Notes tab. The closet comes from ``HomeShop``. Tapping the streak opens
/// its flame, zooming out of the chip.
struct StyledHome: View {
  private static let streakSource = "streak"
  /// The scene's view, with the host's environment already set.
  let scene: AnyView
  let notes: [NoteRecord]
  let streak: Int
  let isFakePartner: Bool
  let onOpenNotes: () -> Void
  /// Whether the room is being decorated, which hides everything over it but its own controls.
  var isDecorating = false
  /// Whether the launch's glide into the room is playing, which keeps the controls back.
  var isOpening = false
  /// Opens the room for moving its furniture, right where it is.
  var onDecorate: (() -> Void)?
  /// Opens the streak's flame, or `nil` when the chip only shows the count.
  var flame: StreakFlameHost?

  @State private var latestDrawing: CGImage?
  /// What the flame shows, set as it opens so the visit is remembered once, and kept while it
  /// zooms closed.
  @State private var flameState: FlameSceneState?
  @State private var isFlameOpen = false
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
          bottom
        }
        .transition(.opacity)
      }
    }
    .calmAnimation(value: isDecorating)
    .calmAnimation(value: isOpening)
    .task(id: latestReceived?.id) {
      guard let note = latestReceived else {
        latestDrawing = nil
        return
      }
      latestDrawing = NoteImage.cgImage(of: note.strokes)
    }
    .flameCover(isPresented: $isFlameOpen, source: Self.streakSource, in: zoom) {
      if let flame, let flameState {
        flame.view(flameState) { isFlameOpen = false }
      }
    }
  }

  private var header: some View {
    HStack(spacing: Spacing.small) {
      streakChip
      if let onDecorate {
        IconButton("sofa.fill", label: "Decorate the room", action: onDecorate)
          .accessibilityIdentifier("styledDecorateButton")
      }
      Spacer(minLength: 0)
    }
    .padding(.top, Spacing.small)
    .padding(.horizontal, Spacing.medium)
  }

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

  private var bottom: some View {
    VStack(spacing: Spacing.medium) {
      if isFakePartner {
        Text("Fake partner: scripted replies, on this phone only")
          .billetType(.caption)
          .foregroundStyle(Palette.muted.color)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("fakePartnerNotice")
      }
      Button(action: onOpenNotes) { caption }
        .buttonStyle(RowButtonStyle())
        .accessibilityIdentifier("styledCaption")
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.top, Spacing.page)
    .padding(.bottom, Spacing.small)
    .background {
      LinearGradient(
        stops: [
          .init(color: .clear, location: 0),
          .init(color: Self.ground.opacity(0.92), location: 0.45),
          .init(color: Self.ground, location: 1),
        ], startPoint: .top, endPoint: .bottom
      )
      .ignoresSafeArea(edges: .bottom)
      .allowsHitTesting(false)
    }
  }

  /// The room's own night colour, which the bottom fades into.
  static let ground = Color(red: 0.047, green: 0.075, blue: 0.125)

  private var caption: some View {
    VStack(alignment: .leading, spacing: Spacing.hair) {
      if let note = latestReceived {
        TimelineView(.everyMinute) { context in
          Text(Self.caption(for: note.date, now: context.date))
            .billetType(.heading)
            .foregroundStyle(Palette.paper.color)
        }
        Text("Tap the note to open it")
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
      } else {
        Text("No notes yet")
          .billetType(.heading)
          .foregroundStyle(Palette.paper.color)
        Text("Draw one from the Notes tab")
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// "A note from your partner · 5 minutes ago". A date a little ahead of `now`, from a clock
  /// that runs fast, reads as now.
  static func caption(for date: Date, now: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.dateTimeStyle = .named
    let when = formatter.localizedString(for: min(date, now), relativeTo: now)
    return "A note from your partner · \(when)"
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
