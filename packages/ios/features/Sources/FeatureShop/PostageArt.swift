#if canImport(UIKit)
  import Design
  import ShopInterface
  import SwiftUI
  import Wire

  extension NoteStamp {
    public var art: StampArt {
      switch self {
      case .heart: .heart
      case .moon: .moon
      case .bloom: .bloom
      case .paw: .paw
      case .sun: .sun
      }
    }
  }

  extension NoteSeal {
    public var art: SealArt {
      switch self {
      case .rose: .rose
      case .night: .night
      case .meadow: .meadow
      case .honey: .honey
      case .plum: .plum
      }
    }
  }

  /// A stamp or seal drawn at `size` points across, as the composer's tray and the Shop show it.
  public struct PostageArtView: View {
    let postage: NotePostage
    let size: CGFloat

    public init(_ postage: NotePostage, size: CGFloat) {
      self.postage = postage
      self.size = size
    }

    public var body: some View {
      switch postage.kind {
      case .stamp(let stamp): PostageStamp(stamp.art, width: size * 0.8)
      case .seal(let seal): WaxSeal(seal.art, size: size)
      }
    }
  }
#endif
