import Foundation
import Testing

@testable import Pet

@Suite struct WindowViewTests {
  @Test(arguments: WindowView.allCases)
  func everyViewHasWords(_ view: WindowView) {
    #expect(!view.title.isEmpty)
    #expect(!view.detail.isEmpty)
  }

  @Test func theStandardChoiceIsTheSuburbInItsOwnWeatherAndTheRoomsHour() {
    let choice = WindowViewChoice.standard
    #expect(choice.view == .suburbNight)
    #expect(choice.shownWeather == WindowView.suburbNight.weather)
    #expect(choice.shownHour(room: nil) == .night)
    #expect(choice.shownHour(room: .at(hour: 13)) == .day)
  }

  @Test func aChosenModifierWinsOverTheViewAndTheRoom() {
    let choice = WindowViewChoice(view: .suburbNight, weather: .snow, hour: .dusk)
    #expect(choice.shownWeather == .snow)
    #expect(choice.shownHour(room: .at(hour: 13)) == .dusk)
  }

  @Test func aViewMadeForDuskShowsDuskUntilTheRoomOrChoiceSaysOtherwise() {
    let choice = WindowViewChoice(view: .pinkDusk)
    #expect(choice.shownHour(room: nil) == .dusk)
    #expect(choice.shownHour(room: .at(hour: 13)) == .day)
    #expect(WindowViewChoice(view: .pinkDusk, hour: .night).shownHour(room: nil) == .night)
  }

  @Test func theNewViewsAreMadeForTheirOwnHourAndWeather() {
    #expect(WindowView.mistyLake.hour == .morning)
    #expect(WindowView.autumnPark.hour == .day)
    #expect(WindowView.sunsetBeach.hour == .dusk)
    #expect(WindowView.desertStars.hour == .night)
    #expect(WindowView.neonStreet.weather == .rain)
    #expect(WindowView.moonlitPeaks.weather == .clear)
  }

  @Test func everyViewHasATitleAndADetailOfItsOwn() {
    #expect(Set(WindowView.allCases.map(\.title)).count == WindowView.allCases.count)
    #expect(Set(WindowView.allCases.map(\.detail)).count == WindowView.allCases.count)
  }

  @Test(arguments: ViewHour.allCases)
  func eachHourIsLitAsItsPartOfTheDay(_ hour: ViewHour) {
    #expect(ViewHour(hour.light.phase) == hour)
  }

  @Test func aChoiceSurvivesCoding() throws {
    let choice = WindowViewChoice(view: .suburbNight, weather: .rain, hour: .morning)
    let data = try JSONEncoder().encode(choice)
    #expect(try JSONDecoder().decode(WindowViewChoice.self, from: data) == choice)
  }

  @Test func anUnknownViewDecodesAsTheStandardOneKeepingItsModifiers() throws {
    let data = Data(#"{"view":"moonBase","weather":"fog","hour":"bogus"}"#.utf8)
    let choice = try JSONDecoder().decode(WindowViewChoice.self, from: data)
    #expect(choice == WindowViewChoice(view: .standard, weather: .fog))
  }

  // MARK: - Rhythm

  private let cars = ViewRhythm(seed: 21, slot: 16, chance: 0.75, length: 3.6...5.4)

  /// The passes over `seconds`, sampled every tenth of a second: start time and pass.
  private func passes(_ rhythm: ViewRhythm, over seconds: Double, from start: Double = 0)
    -> [(Double, ViewRhythm.Pass)]
  {
    var found: [(Double, ViewRhythm.Pass)] = []
    var last: Int64?
    for step in 0..<Int(seconds * 10) {
      let time = start + Double(step) / 10
      if let pass = rhythm.pass(at: time), pass.index != last {
        found.append((time, pass))
        last = pass.index
      }
    }
    return found
  }

  @Test func aPassRunsFromStartToEndWithinItsLength() {
    for step in 0..<6000 {
      guard let pass = cars.pass(at: Double(step) / 10) else { continue }
      #expect(pass.progress >= 0 && pass.progress < 1)
      #expect(pass.length >= 3.6 && pass.length <= 5.4)
      #expect(pass.variant >= 0 && pass.variant <= 1)
    }
  }

  @Test func theSameMomentAlwaysGivesTheSamePass() {
    for time in [12.3, 400.1, 812_345_678.9] {
      #expect(cars.pass(at: time) == cars.pass(at: time))
    }
  }

  @Test func passesComeAboutAsOftenAsTheirChance() {
    let found = passes(cars, over: 16 * 400)
    let share = Double(found.count) / 400
    #expect(share > 0.63 && share < 0.87)
  }

  @Test func gapsNeverSettleIntoALoop() {
    let starts = passes(cars, over: 1200).map(\.0)
    let gaps = zip(starts, starts.dropFirst()).map { ($1 - $0).rounded() }
    #expect(Set(gaps).count > 12)
    let late = passes(cars, over: 1200, from: 812_345_000).map(\.0)
    #expect(starts.count > 30 && late.count > 30)
  }

  @Test func passesNeverOverlap() {
    var wasIndex: Int64?
    var ended = Set<Int64>()
    for step in 0..<20_000 {
      guard let pass = cars.pass(at: Double(step) / 10) else { continue }
      if pass.index != wasIndex, let wasIndex { ended.insert(wasIndex) }
      #expect(!ended.contains(pass.index))
      wasIndex = pass.index
    }
  }

  @Test func theHashIsStableAndSpread() {
    let values = (0..<1000).map { ViewRhythm.hash($0, seed: 41) }
    #expect(values == (0..<1000).map { ViewRhythm.hash($0, seed: 41) })
    #expect(values.allSatisfy { $0 >= 0 && $0 <= 1 })
    let low = values.filter { $0 < 0.5 }.count
    #expect(low > 400 && low < 600)
  }
}
