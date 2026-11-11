import Design
import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import Testing
import UsInterface
@testable import Billet

struct LockWallpaperTests {
    private func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }

    @Test func theWhiteClockReadsOnEveryWallpaperStop() {
        for wallpaper in LockWallpaper.allCases {
            for stop in wallpaper.stops {
                #expect(contrast(0xFFFFFF, stop) >= 4.5, "\(wallpaper) \(String(stop, radix: 16))")
            }
        }
    }

    @Test func everyInkReadsOnEveryWallpaperStop() {
        for wallpaper in LockWallpaper.allCases {
            for stop in wallpaper.stops {
                for ink in PaletteInk.bundled {
                    #expect(contrast(ink.dark, stop) >= 3, "\(ink.name) on \(wallpaper) \(String(stop, radix: 16))")
                }
            }
        }
    }
}
