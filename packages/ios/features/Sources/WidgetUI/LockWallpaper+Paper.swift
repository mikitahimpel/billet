import Design
import Wire

extension LockWallpaper {
  /// The wallpaper a drawing was sent on; blush when the sender chose none.
  public init(paper: PaperColor?) {
    switch paper {
    case .blush, nil: self = .blush
    case .butter: self = .butter
    case .sage: self = .sage
    case .sky: self = .sky
    case .cream: self = .cream
    }
  }

  public var paper: PaperColor {
    switch self {
    case .blush: .blush
    case .butter: .butter
    case .sage: .sage
    case .sky: .sky
    case .cream: .cream
    }
  }
}
