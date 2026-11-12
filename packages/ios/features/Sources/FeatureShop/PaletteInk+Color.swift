#if canImport(UIKit)
  import Design
  import ShopInterface
  import SwiftUI

  extension PaletteInk {
    public func color(onDark: Bool) -> Color { Color(hex: onDark ? dark : light) }
  }
#endif
