import CoreGraphics
import DesignSystem
import FeatureInbox
import Foundation
import Ink
import Pet
import PetScene
import SwiftUI

/// Home for a styled room: the room fills the screen and the controls float over it. The streak
/// and a switch of room style sit top left, the treat chip follows the cat, and the latest note's
/// caption and the Draw button sit at the bottom. The closet and the shop come from ``HomeShop``.
/// Tapping the streak opens its flame, zooming out of the chip.
struct StyledHome: View {
  private static let streakSource = "streak"
  let style: RoomStyle
  /// The scene's view, with the host's environment already set.
  let scene: AnyView
  let notes: [NoteRecord]
  let streak: Int
  let treats: Int
  let isFakePartner: Bool
  let onChooseStyle: (RoomStyle) -> Void
  let onTreat: () -> Void
  let onOpenNotes: () -> Void
  let onDraw: () -> Void
  /// Whether the room is being decorated, which hides everything over it but its own controls.
  var isDecorating = false
  /// Opens the room for moving its furniture, right where it is.
  var onDecorate: (() -> Void)?
  /// Opens the streak's flame, or `nil` when the chip only shows the count.
  var flame: StreakFlameHost?

  @State private var latestDrawing: CGImage?
  @State private var openings = 0
  @State private var choosingStyle = false
  /// What the flame shows, set as it opens so the visit is remembered once, and kept while it
  /// zooms closed.
  @State private var flameState: FlameSceneState?
  @State private var isFlameOpen = false
  @Namespace private var zoom
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var latestReceived: NoteRecord? {
    notes.first { $0.direction == .received }
  }

  var body: some View {
    ZStack {
      scene
        .environment(\.petSceneRoomStyle, style)
        .environment(\.petSceneDrawing, latestDrawing)
        .environment(\.petSceneOpeningCount, openings)
        .ignoresSafeArea()
        .overlayPreferenceValue(PetSceneCatAnchorKey.self) { anchor in
          GeometryReader { proxy in
            if let anchor, !isDecorating {
              treatChip
                .position(Self.chipPosition(near: proxy[anchor], in: proxy.size))
            }
          }
        }
      if !isDecorating {
        VStack(spacing: 0) {
          header
          Spacer(minLength: 0)
          bottom
        }
        .transition(.opacity)
      }
    }
    .calmAnimation(value: isDecorating)
    .task(id: latestReceived?.id) {
      guard let note = latestReceived else {
        latestDrawing = nil
        return
      }
      latestDrawing = NoteImage.cgImage(of: note.strokes)
    }
    .confirmationDialog("Room style", isPresented: $choosingStyle, titleVisibility: .visible) {
      ForEach(RoomStyle.allCases, id: \.self) { option in
        Button(option == style ? "\(option.title) ✓" : option.title) { onChooseStyle(option) }
      }
      Button("Play the opening again") { openings += 1 }
    }
    #if os(iOS)
      .fullScreenCover(isPresented: $isFlameOpen) {
        if let flame, let flameState {
          flame.view(flameState) { isFlameOpen = false }
            .navigationTransition(.zoom(sourceID: Self.streakSource, in: zoom))
        }
      }
    #endif
  }

  /// Below and to the right of the cat's head, kept inside the view.
  static func chipPosition(near cat: CGPoint, in size: CGSize) -> CGPoint {
    let x = min(max(cat.x + 44, 40), size.width - 40)
    let y = min(max(cat.y + 64, 120), size.height - 220)
    return CGPoint(x: x, y: y)
  }

  private var header: some View {
    HStack(spacing: Spacing.small) {
      IconButton("paintbrush.pointed.fill", label: "Room style") { choosingStyle = true }
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

  private var treatChip: some View {
    Button(action: onTreat) {
      HStack(spacing: Spacing.hair) {
        Image(systemName: "fish.fill")
          .font(IconStyle.font)
          .foregroundStyle(Palette.gold.color)
        if treats > 0 {
          Text(verbatim: "\(treats)")
            .billetType(.action)
            .foregroundStyle(Palette.paper.color)
        }
      }
      .padding(.horizontal, Spacing.medium - Spacing.hair)
      .frame(minWidth: Target.minimum, minHeight: Target.minimum)
      .contentShape(.capsule)
    }
    .buttonStyle(RowButtonStyle())
    .floatingGlass()
    .accessibilityLabel(
      treats > 0 ? "Give the cat a treat, \(treats) left" : "Give today's treat"
    )
    .accessibilityIdentifier("styledTreat")
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
      BilletButton(
        "Draw for your partner", rank: .primary, systemImage: "pencil.tip", action: onDraw)
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.top, Spacing.page)
    .padding(.bottom, Spacing.small)
    .background {
      LinearGradient(
        stops: [
          .init(color: .clear, location: 0),
          .init(color: Self.ground(style).opacity(0.92), location: 0.45),
          .init(color: Self.ground(style), location: 1),
        ], startPoint: .top, endPoint: .bottom
      )
      .ignoresSafeArea(edges: .bottom)
      .allowsHitTesting(false)
    }
  }

  /// The room's own night colour, which the bottom fades into.
  static func ground(_ style: RoomStyle) -> Color {
    switch style {
    case .sunsetLamp: Color(red: 0.078, green: 0.071, blue: 0.102)
    case .windowSeat: Color(red: 0.047, green: 0.075, blue: 0.125)
    case .nooki: Color(red: 0.047, green: 0.141, blue: 0.133)
    }
  }

  @ViewBuilder private var caption: some View {
    let time = latestReceived.map { $0.date.formatted(date: .omitted, time: .shortened) }
    switch style {
    case .windowSeat:
      VStack(alignment: .leading, spacing: Spacing.hair) {
        Text(time == nil ? "Nothing on the window yet" : "Your partner taped this to your window")
          .billetType(.heading)
          .foregroundStyle(Palette.paper.color)
        Text(time.map { "\($0) · tap the note to open it" } ?? "Draw the first note")
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    case .sunsetLamp, .nooki:
      HStack(spacing: Spacing.small) {
        Circle()
          .fill(Palette.greenBright.color)
          .frame(width: Spacing.small, height: Spacing.small)
          .accessibilityHidden(true)
        Text(time.map { "Your partner taped this up, \($0)" } ?? "Nothing taped up yet")
          .billetType(.label)
          .foregroundStyle(Palette.paper.color)
        Spacer(minLength: Spacing.small)
        Text(time == nil ? "Draw the first" : "Tap the note")
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
      }
      .frame(minHeight: Target.minimum)
    }
  }
}

extension View {
  /// Where the flame zooms out of, on iOS.
  fileprivate func streakSource(id: String, in namespace: Namespace.ID) -> some View {
    #if os(iOS)
      matchedTransitionSource(id: id, in: namespace)
    #else
      self
    #endif
  }
}
