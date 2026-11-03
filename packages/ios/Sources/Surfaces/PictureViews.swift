import CoreGraphics
import DesignSystem
import Foundation
import ImageIO
import Pet
import SwiftUI
import WidgetBridge
import WidgetKit

/// Everything a picture needs to draw, read once by the widget.
public struct PictureContext: Sendable {
  public var snapshot: WidgetSnapshot?
  public var drawing: CGImage?
  /// Encoded still of the sleeping cat, if the app has published one.
  public var catPose: Data?
  /// Encoded still of the cat sitting up, shown for an awake mood while its needs are on.
  public var catAwakePose: Data?
  public var now: Date
  public var calendar: Calendar

  public init(
    snapshot: WidgetSnapshot?, drawing: CGImage?, catPose: Data? = nil,
    catAwakePose: Data? = nil, now: Date, calendar: Calendar
  ) {
    self.snapshot = snapshot
    self.drawing = drawing
    self.catPose = catPose
    self.catAwakePose = catAwakePose
    self.now = now
    self.calendar = calendar
  }

  var phase: DayPhase { DayPhase(hour: calendar.component(.hour, from: now)) }

  var partnerHere: Bool {
    snapshot?.current(now: now, calendar: calendar).partnerHere ?? false
  }

  func caption(_ mode: PictureMode) -> PictureCaption {
    PictureCaption.make(mode, snapshot: snapshot, now: now, calendar: calendar)
  }
}

/// The ground behind a picture: the sky for the pictures of the house, the evening for the rest.
public struct PictureBackground: View {
  private let choice: PicturePlan.Choice
  private let context: PictureContext

  public init(_ choice: PicturePlan.Choice, context: PictureContext) {
    self.choice = choice
    self.context = context
  }

  public var body: some View {
    switch choice {
    case .picture(.timeOfDay), .picture(.partnerWindow), .picture(.nudge):
      Sky(phase: context.phase)
    case .picture, .allOff, .nothingYet:
      EveningBackground()
    }
  }
}

/// The shape a widget gives a picture. The widget maps its family onto one of these, which keeps
/// this package free of family cases that exist only on iOS.
public enum PictureLayout: Hashable, Sendable {
  case inline
  case circular
  case rectangular
  case small
  case roomy
}

/// One picture, drawn for the layout of the widget it runs in.
public struct PictureView: View {
  private let choice: PicturePlan.Choice
  private let context: PictureContext
  private let layout: PictureLayout

  public init(_ choice: PicturePlan.Choice, context: PictureContext, layout: PictureLayout) {
    self.choice = choice
    self.context = context
    self.layout = layout
  }

  public var body: some View {
    switch choice {
    case .allOff:
      message("Pictures are off", "Turn one on in billet Settings.")
    case .nothingYet:
      LatestNoteView(image: nil)
    case .picture(.partnerDrawing):
      drawing
    case .picture(let mode):
      picture(mode, context.caption(mode))
    }
  }

  @ViewBuilder private var drawing: some View {
    switch layout {
    case .rectangular: LockNoteRectangular(image: context.drawing)
    case .circular: LockNoteCircular(image: context.drawing)
    case .inline: Label("New note", systemImage: "scribble")
    case .small, .roomy: LatestNoteView(image: context.drawing)
    }
  }

  @ViewBuilder private func picture(_ mode: PictureMode, _ caption: PictureCaption) -> some View {
    switch layout {
    case .inline:
      Label(caption.headline, systemImage: caption.symbol)
    case .circular:
      ZStack {
        AccessoryWidgetBackground()
        if let number = caption.number {
          Text(verbatim: "\(number)")
            .billetType(.numeral)
            .minimumScaleFactor(0.5)
            .padding(Spacing.small)
        } else {
          Image(systemName: caption.symbol)
            .font(IconStyle.font)
            .widgetAccentable()
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(caption.headline)
    case .rectangular:
      HStack(spacing: Spacing.small) {
        Image(systemName: caption.symbol)
          .font(IconStyle.font)
          .widgetAccentable()
        VStack(alignment: .leading, spacing: 0) {
          Text(caption.headline).billetType(.action).lineLimit(1)
          Text(caption.detail).billetType(.caption).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    case .small, .roomy:
      full(mode, caption)
    }
  }

  private func full(_ mode: PictureMode, _ caption: PictureCaption) -> some View {
    VStack(spacing: Spacing.small) {
      art(mode, caption)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      VStack(spacing: 0) {
        Text(caption.headline)
          .billetType(.heading)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        if layout != .small {
          Text(caption.detail)
            .billetType(.label)
            .lineLimit(2)
            .multilineTextAlignment(.center)
        }
      }
      .foregroundStyle(Palette.paper.color)
    }
    .padding(Spacing.medium)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(caption.headline). \(caption.detail)")
  }

  @ViewBuilder private func art(_ mode: PictureMode, _ caption: PictureCaption) -> some View {
    switch mode {
    case .timeOfDay, .nudge:
      HouseAtWindow(lit: context.phase == .night || context.phase == .dusk)
    case .partnerWindow:
      HouseAtWindow(lit: context.partnerHere)
    case .catMood:
      CatMoodArt(
        symbol: caption.symbol, pose: moodPose,
        thought: context.snapshot?.life?.thought(at: context.now).map(Self.thoughtSymbol))
    case .streak:
      // The flame stands behind the plate, so the number still reads first.
      ZStack(alignment: .bottom) {
        FlameGlyph(streak: caption.number ?? 0)
        HousePlate(caption.number ?? 0, scale: layout == .small ? 0.8 : 1.2)
      }
    case .daysTogether:
      HousePlate(caption.number ?? 0, scale: layout == .small ? 1 : 1.5)
    case .partnerDrawing:
      EmptyView()
    }
  }

  private var mood: CatMood? {
    context.snapshot.map { CatMood(snapshot: $0, now: context.now, calendar: context.calendar) }
  }

  /// The still for the mood: asleep, or, while the cat's needs are on, sitting up.
  private var moodPose: Data? {
    if mood == .sleepy { return context.catPose }
    return context.snapshot?.life == nil ? nil : context.catAwakePose
  }

  /// What the cat thinks of in the widget's bubble, as in the app.
  static func thoughtSymbol(_ need: PetNeed) -> String {
    switch need {
    case .full: "fish.fill"
    case .rested: "zzz"
    case .loved: "heart.fill"
    case .playful: "tennisball.fill"
    }
  }

  private func message(_ title: String, _ detail: String) -> some View {
    VStack(spacing: Spacing.hair) {
      Text(title).billetType(.heading)
      if layout == .small || layout == .roomy {
        Text(detail).billetType(.label).multilineTextAlignment(.center)
      }
    }
    .foregroundStyle(Palette.paper.color)
    .minimumScaleFactor(0.6)
    .padding(Spacing.medium)
  }
}

private struct Sky: View {
  let phase: DayPhase

  var body: some View {
    ZStack {
      LinearGradient(colors: colors.map(\.color), startPoint: .top, endPoint: .bottom)
      GeometryReader { geometry in
        if phase == .night {
          Sparkle()
            .fill(Palette.gold.color.opacity(0.8))
            .frame(width: Spacing.medium, height: Spacing.medium)
            .position(x: geometry.size.width * 0.8, y: geometry.size.height * 0.2)
          Sparkle()
            .fill(Palette.gold.color.opacity(0.5))
            .frame(width: Spacing.small, height: Spacing.small)
            .position(x: geometry.size.width * 0.2, y: geometry.size.height * 0.3)
        } else {
          Circle()
            .fill(Palette.light.color)
            .frame(width: Spacing.wide, height: Spacing.wide)
            .lampGlow()
            .position(
              x: geometry.size.width * 0.8, y: geometry.size.height * (phase == .day ? 0.2 : 0.35))
        }
      }
    }
    .accessibilityHidden(true)
  }

  private var colors: [Swatch] {
    switch phase {
    case .dawn: [Palette.skyLit, Palette.woodLit]
    case .day: [Palette.greenBright, Palette.paperTurned]
    case .dusk: [Palette.sky, Palette.clay]
    case .night: [Palette.skyNight, Palette.sky]
    }
  }
}

/// The house with its two windows. A lit window is the light of someone being home.
struct HouseAtWindow: View {
  let lit: Bool

  private static let windows = [
    CGRect(x: 15, y: 31, width: 10, height: 10),
    CGRect(x: 31, y: 31, width: 10, height: 10),
  ]

  var body: some View {
    GeometryReader { geometry in
      let unit = min(geometry.size.width, geometry.size.height) / 56
      ZStack(alignment: .topLeading) {
        ForEach(Self.windows.indices, id: \.self) { index in
          let window = Self.windows[index]
          Rectangle()
            .fill((lit ? Palette.light : Palette.clayNight).color)
            .frame(width: window.width * unit, height: window.height * unit)
            .shadow(color: Palette.light.color.opacity(lit ? 0.9 : 0), radius: Glow.lamp)
            .offset(x: window.minX * unit, y: window.minY * unit)
        }
        LockHouseGlyph()
          .fill(Palette.clay.color, style: FillStyle(eoFill: true))
          .frame(width: 56 * unit, height: 56 * unit)
          .widgetAccentable()
      }
      .frame(width: 56 * unit, height: 56 * unit)
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
    .aspectRatio(1, contentMode: .fit)
  }
}

private struct CatMoodArt: View {
  let symbol: String
  let pose: Data?
  var thought: String?

  var body: some View {
    art.overlay(alignment: .topTrailing) {
      if let thought {
        Image(systemName: thought)
          .font(.system(size: 13, weight: .semibold, design: .rounded))
          .foregroundStyle(Palette.clay.color)
          .padding(7)
          .background(Palette.paper.color, in: Circle())
          .widgetAccentable()
          .accessibilityHidden(true)
      }
    }
  }

  @ViewBuilder private var art: some View {
    if let image = Self.decode(pose) {
      Image(decorative: image, scale: 1)
        .resizable()
        .scaledToFit()
    } else {
      Image(systemName: symbol)
        .resizable()
        .scaledToFit()
        .foregroundStyle(Palette.gold.color)
        .padding(Spacing.large)
        .widgetAccentable()
    }
  }

  private static func decode(_ data: Data?) -> CGImage? {
    guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }
}

/// The buttons of a widget: each runs an App Intent that queues the action for the app.
public struct ActionButtonsView: View {
  private let kinds: [WidgetActionKind]
  private let snapshot: WidgetSnapshot?
  private let pending: [WidgetAction]
  private let surface: ActionSurface
  private let layout: PictureLayout
  private let now: Date
  private let calendar: Calendar

  public init(
    kinds: [WidgetActionKind], snapshot: WidgetSnapshot?, pending: [WidgetAction],
    surface: ActionSurface, layout: PictureLayout, now: Date, calendar: Calendar
  ) {
    self.kinds = kinds
    self.snapshot = snapshot
    self.pending = pending
    self.surface = surface
    self.layout = layout
    self.now = now
    self.calendar = calendar
  }

  public var body: some View {
    if kinds.isEmpty {
      Text("Buttons are off")
        .billetType(.label)
        .foregroundStyle(Palette.paper.color)
        .multilineTextAlignment(.center)
        .padding(Spacing.medium)
    } else {
      switch layout {
      case .small:
        VStack(spacing: Spacing.small) { buttons }.padding(Spacing.medium)
      case .roomy:
        HStack(spacing: Spacing.small) { buttons }.padding(Spacing.medium)
      case .rectangular:
        HStack(spacing: Spacing.small) { buttons }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .circular:
        ZStack {
          AccessoryWidgetBackground()
          buttons.padding(Spacing.hair)
        }
      case .inline:
        EmptyView()
      }
    }
  }

  @ViewBuilder private var buttons: some View {
    let shown = layout == .circular ? Array(kinds.prefix(1)) : kinds
    ForEach(shown, id: \.self) { kind in
      let state = ActionButtonState.make(
        kind, snapshot: snapshot, pending: pending, now: now, calendar: calendar)
      button(kind) { label(state) }
        .buttonStyle(.plain)
        .disabled(!state.isEnabled)
        .accessibilityLabel(state.title)
    }
  }

  @ViewBuilder private func label(_ state: ActionButtonState) -> some View {
    switch layout {
    case .small, .roomy:
      HStack(spacing: Spacing.small) {
        Image(systemName: state.symbol).font(IconStyle.font)
        Text(state.title).billetType(.action).lineLimit(1).minimumScaleFactor(0.7)
      }
      .foregroundStyle(state.isEnabled ? Palette.ink.color : Palette.muted.color)
      .frame(maxWidth: .infinity, minHeight: Target.minimum)
      .background(
        (state.isEnabled ? Palette.gold : Palette.raisedTop).color, in: .capsule)
    case .rectangular, .circular, .inline:
      Image(systemName: state.symbol)
        .font(IconStyle.font)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(state.isEnabled ? 1 : 0.5)
        .widgetAccentable()
    }
  }

  @ViewBuilder private func button<Label: View>(
    _ kind: WidgetActionKind, @ViewBuilder label: () -> Label
  ) -> some View {
    switch kind {
    case .treat: Button(intent: GiveTreatIntent(surface: surface), label: label)
    case .pet: Button(intent: PetCatIntent(surface: surface), label: label)
    case .heart: Button(intent: SendHeartIntent(surface: surface), label: label)
    case .openCanvas: Button(intent: OpenCanvasIntent(surface: surface), label: label)
    }
  }
}
