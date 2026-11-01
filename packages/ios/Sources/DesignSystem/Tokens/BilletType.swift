import SwiftUI

/// The type ladder. Sizes step by about 1.25 and follow Dynamic Type from their anchor style.
public enum BilletType: CaseIterable, Sendable {
  case display
  case title
  case heading
  case body
  case label
  case caption
  /// House numbers and nothing else.
  case numeral

  public var size: CGFloat {
    switch self {
    case .display: 40
    case .title: 28
    case .heading: 21
    case .body: 17
    case .label: 14
    case .caption: 12
    case .numeral: 19
    }
  }

  public var lineHeight: CGFloat {
    switch self {
    case .display: 44
    case .title: 32
    case .heading: 26
    case .body: 24
    case .label: 20
    case .caption: 16
    case .numeral: 24
    }
  }

  private var anchor: Font.TextStyle {
    switch self {
    case .display: .largeTitle
    case .title: .title
    case .heading: .title3
    case .body: .body
    case .label: .subheadline
    case .caption: .caption
    case .numeral: .headline
    }
  }

  private var weight: Font.Weight {
    switch self {
    case .display, .title, .heading: .heavy
    case .body: .regular
    case .label, .caption: .medium
    case .numeral: .medium
    }
  }

  /// Display sizes close up; reading sizes keep the face's own spacing.
  public var tracking: CGFloat {
    switch self {
    case .display: -1.2
    case .title: -0.6
    case .heading: -0.2
    case .body, .label, .caption, .numeral: 0
    }
  }

  public var font: Font {
    switch self {
    case .numeral:
      .custom(BilletFonts.monoFamily, size: size, relativeTo: anchor)
    case .display, .title, .heading, .body, .label, .caption:
      .custom(BilletFonts.groteskFamily, size: size, relativeTo: anchor).weight(weight)
    }
  }
}

extension View {
  /// Sets face, weight, tracking and line height together.
  public func billetType(_ type: BilletType) -> some View {
    font(type.font)
      .tracking(type.tracking)
      .lineSpacing(type.lineHeight - type.size)
  }
}
