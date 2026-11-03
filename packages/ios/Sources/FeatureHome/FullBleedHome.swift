import DesignSystem
import Foundation
import Pet
import PetScene
import SwiftUI

/// Home with the room edge to edge, under the status bar and behind the tab bar. A pen draws, a
/// handle at the foot pulls up everything else, and each variant adds its own way of meeting the
/// room: an opening, a room that answers touch and tilt, or the light of the hour.
struct FullBleedHome<Drawer: View>: View {
  let variant: HomeVariant
  /// The scene's view, with the host's environment already set.
  let scene: AnyView
  let director: CatDirector
  let isFakePartner: Bool
  /// The partner's time zone, when they share it.
  let theirTimeZone: TimeZone?
  /// The hour the night-and-day variant pretends it is, or `nil` to follow the clock.
  let pretendHour: Int?
  /// Whether the opening has already played since launch.
  let hasOpened: Bool
  let onOpened: () -> Void
  let onTreat: () -> Void
  let onDraw: () -> Void
  /// Whether the room is being decorated, which hides everything over it but its own controls.
  var isDecorating = false
  /// Opens the room for decorating in place.
  var onDecorate: (() -> Void)?
  /// Whether the panel with everything else is pulled up. Home closes it when something covers it.
  @Binding var drawerOpen: Bool
  @ViewBuilder let drawer: () -> Drawer

  @State private var drawerDrag: CGFloat = 0
  @State private var flyIn: PetSceneFlyIn?
  @State private var isOpening = false
  @State private var gaze: CGPoint?
  @State private var lastTouch = Date.distantPast
  @State private var controlsShown = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.eveningGround) private var eveningGround

  /// The cinematic variant keeps its controls back from the first frame until its opening is over.
  private var showsControls: Bool {
    controlsShown && !isOpening && !(variant == .cinematic && !hasOpened)
      && !(variant == .livingWindow && lastTouch == .distantPast)
  }

  /// How long the room is left alone before the living window shows its controls.
  static var quietBeforeControls: Duration { .seconds(3) }

  var body: some View {
    ZStack {
      room
      if isOpening {
        // A tap anywhere during the opening skips to its end.
        Color.clear
          .contentShape(Rectangle())
          .ignoresSafeArea()
          .onTapGesture { skipOpening() }
          .accessibilityAddTraits(.isButton)
          .accessibilityLabel("Skip the opening")
      }
      controls
        .opacity(showsControls && !isDecorating ? 1 : 0)
        .allowsHitTesting(showsControls && !isDecorating)
        .calmAnimation(value: controlsShown)
        .calmAnimation(value: isOpening)
      if drawerOpen { panel }
    }
    .calmAnimation(value: drawerOpen)
    .calmAnimation(value: isDecorating)
    .task { await openIfDue() }
    .task(id: lastTouch) { await showControlsWhenQuiet() }
  }

  /// The pulled-up panel, over a shade that closes it. Drawn in place rather than as a sheet, so
  /// the sheets and the canvas its cards open come up as they do from classic Home.
  private var panel: some View {
    ZStack(alignment: .bottom) {
      Color.black.opacity(0.35)
        .ignoresSafeArea()
        .onTapGesture { drawerOpen = false }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Close")
      VStack(spacing: 0) {
        Capsule()
          .fill(Palette.paper.color.opacity(0.5))
          .frame(width: 36, height: 5)
          .padding(.vertical, Spacing.small)
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
          .gesture(
            DragGesture()
              .onChanged { drawerDrag = max($0.translation.height, 0) }
              .onEnded { value in
                if value.translation.height > 80 { drawerOpen = false }
                drawerDrag = 0
              }
          )
          .accessibilityHidden(true)
        ScrollView {
          drawer()
            .padding(.horizontal, Spacing.medium)
            .padding(.bottom, Spacing.large)
        }
        .scrollBounceBehavior(.basedOnSize)
      }
      .frame(maxHeight: Self.panelHeight)
      .fixedSize(horizontal: false, vertical: true)
      .background {
        UnevenRoundedRectangle(topLeadingRadius: Radius.card, topTrailingRadius: Radius.card)
          .fill(eveningGround.middle.color)
          .ignoresSafeArea(edges: .bottom)
      }
      .offset(y: drawerDrag)
      .transition(.move(edge: .bottom))
      .accessibilityIdentifier("homeDrawer")
    }
  }

  private static var panelHeight: CGFloat { 560 }

  private var room: some View {
    TimelineView(.everyMinute) { context in
      scene
        .environment(\.petSceneFillsView, true)
        .environment(\.petSceneShowsControls, false)
        .environment(\.petSceneFlyIn, flyIn)
        .environment(\.petSceneOpeningEnded) { isOpening = false }
        .environment(\.petSceneCatCue, director.latest)
        .environment(\.petSceneGaze, gaze)
        .environment(\.petSceneOrbits, variant != .livingWindow)
        .environment(\.petSceneFollowsTilt, variant == .livingWindow)
        .environment(\.petSceneDayLight, dayLight(at: context.date))
    }
    .ignoresSafeArea()
    .simultaneousGesture(watching, including: variant == .livingWindow ? .all : .subviews)
    .simultaneousGesture(holdForTreat, including: variant == .livingWindow ? .all : .subviews)
  }

  /// The light of the hour here and where the partner is, for the night-and-day variant.
  private func dayLight(at date: Date) -> PetSceneDayLight? {
    guard variant == .nightAndDay else { return nil }
    let date = DayLight.pretending(date, hour: pretendHour, in: .current)
    return PetSceneDayLight(
      here: DayLight.at(date, in: .current),
      theirs: theirTimeZone.map { DayLight.at(date, in: $0) })
  }

  /// The cat watches a finger resting on or moving over the room.
  private var watching: some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .local)
      .onChanged { value in
        gaze = value.location
        touched()
      }
      .onEnded { _ in
        gaze = nil
        touched()
      }
  }

  /// Holding the room gives the cat a treat. While decorating, holding picks up a piece instead.
  private var holdForTreat: some Gesture {
    LongPressGesture(minimumDuration: 0.6)
      .onEnded { _ in
        guard !isDecorating else { return }
        onTreat()
        touched()
      }
  }

  private func touched() {
    lastTouch = .now
    if controlsShown { controlsShown = false }
  }

  /// The living window keeps its controls out of the way until the room is left alone.
  private func showControlsWhenQuiet() async {
    guard variant == .livingWindow else {
      controlsShown = true
      return
    }
    try? await Task.sleep(for: Self.quietBeforeControls)
    guard !Task.isCancelled else { return }
    controlsShown = true
  }

  private func openIfDue() async {
    if variant == .livingWindow, lastTouch == .distantPast {
      controlsShown = false
      lastTouch = .now
    }
    guard variant == .cinematic, !hasOpened else { return }
    onOpened()
    if reduceMotion {
      flyIn = PetSceneFlyIn(id: 1, isSkipped: true)
      return
    }
    flyIn = PetSceneFlyIn(id: 1)
    isOpening = true
    // The room says when its opening is over. This only frees the screen if it never does.
    try? await Task.sleep(for: .seconds(FlyInTimeline.length + Self.roomStartAllowance))
    isOpening = false
  }

  /// Time allowed for the room to come on screen before its opening starts.
  private static var roomStartAllowance: Double { 8 }

  private func skipOpening() {
    flyIn?.isSkipped = true
    isOpening = false
  }

  private var controls: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)
      HStack(alignment: .bottom) {
        Spacer(minLength: 0)
        handle
        Spacer(minLength: 0)
      }
      .overlay(alignment: .bottomTrailing) { pen }
      .overlay(alignment: .bottomLeading) { decorate }
      .padding(.horizontal, Spacing.medium)
      .padding(.bottom, Spacing.small)
    }
  }

  /// Pulls up the sheet with everything that used to sit on Home. With a fake partner a small
  /// amber dot sits beside it; the panel says what the dot means.
  private var handle: some View {
    Button {
      drawerOpen = true
    } label: {
      Capsule()
        .fill(Palette.paper.color.opacity(0.7))
        .frame(width: 44, height: 5)
        .overlay(alignment: .trailing) {
          if isFakePartner {
            Circle()
              .fill(Palette.gold.color)
              .frame(width: 7, height: 7)
              .offset(x: 14)
              .accessibilityIdentifier("fakePartnerDot")
          }
        }
        .frame(width: Target.minimum * 2, height: Target.minimum)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .simultaneousGesture(
      DragGesture(minimumDistance: 10).onEnded { value in
        if value.translation.height < -20 { drawerOpen = true }
      }
    )
    .accessibilityLabel(
      isFakePartner
        ? "More: streak, treats, shop and cards. Fake partner, scripted replies"
        : "More: streak, treats, shop and cards"
    )
    .accessibilityIdentifier("homeDrawerHandle")
  }

  /// Opens the room for moving its furniture, right where it is.
  @ViewBuilder private var decorate: some View {
    if let onDecorate {
      Button(action: onDecorate) {
        Image(systemName: "sofa.fill")
          .font(.title3.weight(.semibold))
          .foregroundStyle(Palette.paper.color)
          .frame(width: 48, height: 48)
          .background(.ultraThinMaterial, in: Circle())
          .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
          .frame(width: 60, height: 60)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Decorate the room")
      .accessibilityIdentifier("homeDecorateButton")
    }
  }

  private var pen: some View {
    Button(action: onDraw) {
      Image(systemName: "pencil.tip")
        .font(.title2.weight(.semibold))
        .foregroundStyle(Palette.ink.color)
        .frame(width: 60, height: 60)
        .background(Palette.gold.color, in: Circle())
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Draw a note")
    .accessibilityIdentifier("homeDrawButton")
  }
}
