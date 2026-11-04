import CoreGraphics
import Foundation
import Pet
import Testing

@testable import PetSceneReality

@Suite struct WindowViewArtTests {
  private static let looks: [ViewLook] = WindowView.allCases.flatMap { view in
    ViewHour.allCases.flatMap { hour in
      ViewWeather.allCases.map { ViewLook(view: view, hour: hour, weather: $0) }
    }
  }

  @MainActor @Test(arguments: WindowView.allCases)
  func everyPlaneOfEveryViewPaints(_ view: WindowView) throws {
    for plane in ViewPlane.allCases {
      let key = ViewPlateCache.Key(
        look: ViewLook(view: view, hour: .night, weather: .snow), plane: plane, pixels: 380)
      let plate = try #require(ViewPlateCache.paint(key))
      #expect(plate.width == 380)
      #expect(Self.coverage(plate) > 0.02, "\(view) \(plane) is nearly empty")
    }
  }

  /// The share of a plate's pixels that are not transparent.
  private static func coverage(_ image: CGImage) -> Double {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard
      let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return 0 }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let opaque = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 8 }.count
    return Double(opaque) / Double(width * height)
  }

  @Test(arguments: looks)
  func nearerPlanesAreDarkerAtNightAndDusk(_ look: ViewLook) {
    guard look.isDark else { return }
    let palette = look.palette
    let order = ViewPlane.allCases.map { Self.lightness(palette.colour($0)) }
    #expect(zip(order, order.dropFirst()).allSatisfy { $0 >= $1 })
  }

  private static func lightness(_ colour: ViewColour) -> Double {
    0.2126 * colour.red + 0.7152 * colour.green + 0.0722 * colour.blue
  }

  @Test func lightsAreOnlyOnWhenItIsDark() {
    #expect(ViewPalette(hour: .night, weather: .clear).lampsOn)
    #expect(!ViewPalette(hour: .day, weather: .clear).lampsOn)
    #expect(ViewPalette(hour: .day, weather: .clear).litShare == 0)
  }

  @Test func theNearPlaneFollowsTheWindowMostAndTheFarOneLeast() {
    let follows = ViewPlane.allCases.map(\.follow)
    #expect(follows == follows.sorted())
    #expect(ViewSky.follow < follows[0])
  }

  @Test func theStageLinesTheWindowsBottomUpWithItsSill() throws {
    let window = [
      CGPoint(x: 20, y: 200), CGPoint(x: 380, y: 210), CGPoint(x: 380, y: 410),
      CGPoint(x: 20, y: 400),
    ]
    let frame = try #require(ViewStage.Frame(window: window))
    #expect(abs(frame.unit - 3.6) < 1e-9)
    #expect(abs(frame.point(CGPoint(x: 0, y: ViewStage.windowHeight)).y - 410) < 1e-9)
    #expect(abs(frame.point(CGPoint(x: 100, y: 0)).x - 380) < 1e-9)
    let half = ViewStage.Frame.blend(
      home: frame, live: ViewStage.Frame(unit: 4, origin: .zero), follow: 0.5)
    #expect(abs(half.unit - 3.8) < 1e-9)
  }

  @Test func aFullMoonIsHalfwayRound() {
    // 2026-11-24 14:53 UTC was a full moon.
    let fullMoon = ISO8601DateFormatter().date(from: "2026-11-24T14:53:00Z")!
    let phase = ViewSky.phase(at: fullMoon.timeIntervalSinceReferenceDate)
    #expect(abs(phase - 0.5) < 0.03)
  }

  @Test(arguments: WindowView.allCases)
  func whatTheCatWatchesIsSeenThroughTheWindow(_ view: WindowView) {
    for weather in ViewWeather.allCases {
      for step in 0..<3000 {
        let moment = ViewMoment(
          look: ViewLook(view: view, hour: .night, weather: weather), now: Double(step) * 0.7,
          time: 10)
        guard let interest = ViewRecipes.interest(at: moment) else { continue }
        #expect(interest.point.x >= -6 && interest.point.x <= 106)
        #expect(interest.point.y >= -40 && interest.point.y <= ViewStage.windowHeight + 45)
        if interest.paw { #expect(weather == .rain && interest.plane == nil) }
      }
    }
  }

  @Test func theSuburbsStreetIsAboveTheSill() {
    // A car on the road drives on its wheels, so its body is above the road line.
    #expect(SuburbNight.road < ViewStage.sillLine)
    #expect(SuburbNight.streetBase < SuburbNight.road)
  }

  @Test func theSuburbsCarsLightTheRoomInTheirDirection() {
    let recipe = SuburbNight()
    var seen = Set<Bool>()
    for step in 0..<20_000 {
      guard let light = recipe.headlight(at: Double(step) / 10) else { continue }
      #expect(light.progress >= 0 && light.progress < 1)
      seen.insert(light.leftToRight)
    }
    #expect(seen == [true, false])
  }

  @Test func theRoofCatClimbsSitsAtTheRidgeAndLeaves() {
    let cat = SuburbNight.roofCatWalk
    let pass = { (progress: Double, variant: Double) in
      ViewRhythm.Pass(index: 0, progress: progress, variant: variant, length: 50)
    }
    #expect(cat.pose(pass(0, 0.2)).0 == cat.left)
    #expect(cat.pose(pass(0.5, 0.2)) == (cat.ridge, true, 1))
    #expect(cat.pose(pass(0, 0.8)).0 == cat.right)
    #expect(abs(cat.pose(pass(0.999, 0.8)).0.x - cat.left.x) < 0.1)
  }

  @Test func theLAViewsDuskSkyIsPinkerThanTheSharedOne() {
    let shared = ViewPalette(hour: .dusk, weather: .clear)
    let pink = ViewLook(view: .pinkDusk, hour: .dusk, weather: .clear).palette
    #expect(pink.skyMiddle.red - pink.skyMiddle.blue > shared.skyMiddle.red - shared.skyMiddle.blue)
    #expect(ViewLook(view: .suburbNight, hour: .dusk, weather: .clear).palette == shared)
  }

  @Test func theDesertSkyHasFarMoreStarsThanATownsAndTheCitysFewer() {
    let shared = ViewPalette(hour: .night, weather: .clear)
    let desert = ViewLook(view: .desertStars, hour: .night, weather: .clear).palette
    let city = ViewLook(view: .neonStreet, hour: .night, weather: .clear).palette
    #expect(desert.stars > 2 * shared.stars)
    #expect(city.stars < shared.stars)
  }

  @Test func aShootingStarCrossesOnlyAClearDarkSky() {
    let star = ViewShootingStar(rhythm: ViewRhythm(seed: 5, slot: 20, chance: 1, length: 1...1.4))
    var seen = 0
    for step in 0..<4000 {
      let now = Double(step) * 0.05
      let night = ViewMoment(
        look: ViewLook(view: .desertStars, hour: .night, weather: .clear), now: now, time: 10)
      let day = ViewMoment(
        look: ViewLook(view: .desertStars, hour: .day, weather: .clear), now: now, time: 10)
      #expect(star.interest(at: day) == nil)
      guard let interest = star.interest(at: night) else { continue }
      seen += 1
      #expect(interest.point.y < 30)
    }
    #expect(seen > 0)
  }
}
