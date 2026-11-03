import CoreGraphics
import DesignSystem
import Foundation
import ImageIO
import Pet
import SwiftUI
import WidgetBridge
import WidgetKit

/// What the note widget knows about the cat at one moment, read once by its provider.
public struct NoteCat: Sendable {
  public var cat: WidgetCat
  public var catName: String?
  /// Encoded stills the app published: asleep, and sitting up.
  public var sleepingPose: Data?
  public var awakePose: Data?
  /// When the button works again, while it rests after the last care.
  public var coolingUntil: Date?
  /// The care that started the rest, for the button's label while it rests.
  public var lastCare: WidgetCare?
  public var partnerCare: PartnerCare?
  public var now: Date

  public init(
    snapshot: WidgetSnapshot, sleepingPose: Data?, awakePose: Data?, lastCare: CatCareRecord?,
    now: Date, calendar: Calendar
  ) {
    cat = WidgetCat(snapshot: snapshot, now: now, calendar: calendar)
    catName = snapshot.catName
    self.sleepingPose = sleepingPose
    self.awakePose = awakePose
    coolingUntil = CatCareRequest.cooling(last: lastCare, now: now)
    self.lastCare = coolingUntil == nil ? nil : lastCare?.care
    partnerCare = snapshot.partnerCare.flatMap { $0.isFresh(at: now) ? $0 : nil }
    self.now = now
  }

  /// "Your partner petted Mochi · 5 min ago", or nil when there is nothing recent to say.
  public var partnerLine: String? {
    guard let partnerCare else { return nil }
    let seconds = now.timeIntervalSince(partnerCare.at)
    guard seconds >= 60 else { return "\(partnerCare.line(cat: catName)) · just now" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    let ago = formatter.localizedString(for: partnerCare.at, relativeTo: now)
    return "\(partnerCare.line(cat: catName)) · \(ago)"
  }

  /// The button's words and symbol, and whether it can be pressed.
  public var button: (title: String, symbol: String, isEnabled: Bool) {
    if let lastCare {
      return (lastCare == .pet ? "Petted" : "Fed", "checkmark", false)
    }
    switch cat.care {
    case .pet: return ("Pet", "hand.raised.fill", true)
    case .treat: return ("Treat", "fish.fill", true)
    }
  }
}

/// The note widget: the partner's drawing on the paper, and on the medium and large sizes the cat
/// in the bottom-trailing corner with one button. The cat has its own column or strip, so it never
/// covers the ink; the small size keeps only the note.
public struct NoteCatView: View {
  @Environment(\.widgetFamily) private var family
  @Environment(\.widgetRenderingMode) private var renderingMode

  private let image: CGImage?
  private let cat: NoteCat?

  public init(image: CGImage?, cat: NoteCat?) {
    self.image = image
    self.cat = cat
  }

  public var body: some View {
    switch (family, cat) {
    case (.systemMedium, .some(let cat)):
      HStack(spacing: 0) {
        VStack(spacing: 0) {
          NotePaperView(image: image)
          line(cat).padding([.leading, .bottom], Spacing.medium)
        }
        corner(cat, catSize: 72)
          .frame(width: 104)
          .padding([.vertical, .trailing], Spacing.medium)
      }
    case (.systemLarge, .some(let cat)), (.systemExtraLarge, .some(let cat)):
      VStack(spacing: 0) {
        NotePaperView(image: image)
        HStack(alignment: .bottom, spacing: Spacing.small) {
          line(cat).frame(maxWidth: .infinity, alignment: .leading)
          corner(cat, catSize: 84).frame(width: 112)
        }
        .padding([.horizontal, .bottom], Spacing.medium)
      }
    default:
      NotePaperView(image: image)
    }
  }

  @ViewBuilder private func line(_ cat: NoteCat) -> some View {
    if let text = cat.partnerLine {
      Text(text)
        .billetType(.caption)
        .foregroundStyle(ink.opacity(0.75))
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func corner(_ cat: NoteCat, catSize: CGFloat) -> some View {
    VStack(spacing: Spacing.hair) {
      CatStill(cat: cat)
        .frame(width: catSize, height: catSize)
        .frame(maxHeight: .infinity, alignment: .bottom)
      careButton(cat)
    }
  }

  private func careButton(_ cat: NoteCat) -> some View {
    let state = cat.button
    return Button(intent: CareForCatIntent()) {
      HStack(spacing: Spacing.hair) {
        Image(systemName: state.symbol).font(.caption.weight(.semibold))
        Text(state.title).billetType(.action).lineLimit(1).minimumScaleFactor(0.7)
      }
      .foregroundStyle(state.isEnabled ? Palette.ink.color : Palette.muted.color)
      .padding(.horizontal, Spacing.small)
      .frame(maxWidth: .infinity, minHeight: 32)
      .background(
        (state.isEnabled ? Palette.gold : Palette.raisedTop).color.opacity(
          renderingMode == .fullColor ? 1 : 0.25),
        in: .capsule
      )
      .widgetAccentable()
    }
    .buttonStyle(.plain)
    .disabled(!state.isEnabled)
    .accessibilityLabel(state.title)
  }

  private var ink: Color {
    renderingMode == .fullColor ? Palette.ink.color : .primary
  }
}

/// The cat's still for its pose, with its want in a bubble while it waits.
private struct CatStill: View {
  let cat: NoteCat

  var body: some View {
    art
      .overlay(alignment: .topTrailing) {
        if cat.cat.pose == .waiting {
          Image(systemName: bubble)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.clay.color)
            .padding(5)
            .background(Palette.paper.color, in: Circle())
            .widgetAccentable()
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(label)
  }

  @ViewBuilder private var art: some View {
    if let image = Self.decode(pose) {
      Image(decorative: image, scale: 1)
        .resizable()
        .widgetAccentedRenderingMode(.desaturated)
        .scaledToFit()
    } else {
      Image(systemName: cat.cat.pose == .sleeping ? "moon.zzz.fill" : "cat.fill")
        .resizable()
        .scaledToFit()
        .foregroundStyle(Palette.clay.color)
        .padding(Spacing.small)
        .widgetAccentable()
    }
  }

  private var pose: Data? {
    switch cat.cat.pose {
    case .sleeping: cat.sleepingPose
    case .sitting, .waiting: cat.awakePose
    }
  }

  private var bubble: String {
    switch cat.cat.thought {
    case .full: "fish.fill"
    case .rested: "zzz"
    case .loved: "heart.fill"
    case .playful: "tennisball.fill"
    case nil: cat.cat.care == .treat ? "fish.fill" : "heart.fill"
    }
  }

  private var label: String {
    let name = cat.catName ?? "The cat"
    switch cat.cat.pose {
    case .sleeping: return "\(name), asleep"
    case .sitting: return "\(name), sitting"
    case .waiting: return cat.cat.care == .treat ? "\(name), hungry" : "\(name), waiting for you"
    }
  }

  private static func decode(_ data: Data?) -> CGImage? {
    guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }
}
