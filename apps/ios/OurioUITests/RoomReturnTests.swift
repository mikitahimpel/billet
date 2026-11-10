import UIKit
import XCTest

/// A room still draws after the World has been left long enough for a RealityView that went away to free what it drew.
final class RoomReturnTests: XCTestCase {
    @MainActor
    func testTheRoomDrawsAfterALongTripToAnotherTab() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil, "needs a Simulator that can draw")
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "YES", "-uitestNoHints", "YES"]
        app.launch()

        let room = app.buttons["roomSwitch.Room"]
        XCTAssertTrue(room.waitForExistence(timeout: 60))
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.otherElements["launch-splash"])
        wait(for: [gone], timeout: 60)
        Thread.sleep(forTimeInterval: 3)
        let before = try XCTUnwrap(FloorPixels(app.screenshot().image))
        XCTAssertGreaterThan(before.shade, 0.05, "the room never drew")

        for kind in ["Room", "City"] {
            app.buttons["roomSwitch.\(kind)"].tap()
            Thread.sleep(forTimeInterval: 3)
            app.buttons["Shop"].tap()
            Thread.sleep(forTimeInterval: 10)
            app.buttons["World"].tap()
            Thread.sleep(forTimeInterval: 4)
            let after = try XCTUnwrap(FloorPixels(app.screenshot().image))
            XCTAssertGreaterThan(after.shade, 0.05, "the \(kind) came back blank")
        }
    }
}

/// The room's floor, the left 60% of the screen from half to three quarters down, away from the City's window.
private struct FloorPixels {
    /// The share of samples darker than 70 of 255: a drawn room's shadows and boards are 0.13 or more of it, the bare
    /// backdrop under a blank room under 0.01.
    let shade: Double

    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return nil }
        let width = 24, height = 24
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let crop = CGRect(x: 0, y: CGFloat(cgImage.height) * 0.5, width: CGFloat(cgImage.width) * 0.6,
                          height: CGFloat(cgImage.height) * 0.25)
        guard let floor = cgImage.cropping(to: crop) else { return nil }
        context.draw(floor, in: CGRect(x: 0, y: 0, width: width, height: height))
        let brightness = stride(from: 0, to: pixels.count, by: 4).map {
            (Int(pixels[$0]) + Int(pixels[$0 + 1]) + Int(pixels[$0 + 2])) / 3
        }
        shade = Double(brightness.filter { $0 < 70 }.count) / Double(brightness.count)
    }
}
