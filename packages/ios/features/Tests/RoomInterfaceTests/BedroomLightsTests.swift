import Foundation
import Testing

@testable import RoomInterface

@Suite struct BedroomLightsTests {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
  }()

  private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: hour, minute: minute))!
  }

  @Test(arguments: [(18, 0), (21, 30), (23, 59), (0, 0), (3, 15), (5, 59)])
  func theSwitchShowsInTheBedroomFromSixInTheEveningToSixInTheMorning(hour: Int, minute: Int) {
    #expect(BedroomLights.showsSwitch(in: .city, at: at(hour, minute), calendar: calendar))
  }

  @Test(arguments: [(6, 0), (9, 0), (12, 0), (17, 59)])
  func byDayThereIsNoSwitch(hour: Int, minute: Int) {
    #expect(!BedroomLights.showsSwitch(in: .city, at: at(hour, minute), calendar: calendar))
  }

  @Test func theLivingRoomAndTheBoardNeverHaveOne() {
    for hour in 0..<24 {
      #expect(!BedroomLights.showsSwitch(in: .home, at: at(hour), calendar: calendar))
      #expect(!BedroomLights.showsSwitch(in: .board, at: at(hour), calendar: calendar))
    }
  }

  @Test(arguments: BedroomLights.Choice.allCases)
  func byDayTheLampsFollowTheHourWhateverWasChosen(choice: BedroomLights.Choice) {
    #expect(BedroomLights.lamps(choice, at: at(12), calendar: calendar) == nil)
  }

  @Test func atNightTheChoiceLightsOrDimsTheRoom() {
    #expect(BedroomLights.lamps(.on, at: at(22), calendar: calendar) == true)
    #expect(BedroomLights.lamps(.off, at: at(22), calendar: calendar) == false)
    #expect(BedroomLights.lamps(.unset, at: at(22), calendar: calendar) == true)
  }

  @Test func aTapTurnsTheLampsTheOtherWay() {
    #expect(BedroomLights.toggled(.unset) == .off)
    #expect(BedroomLights.toggled(.on) == .off)
    #expect(BedroomLights.toggled(.off) == .on)
  }

  @Test func theSwitchNextComesOrGoesAtSixOClock() {
    #expect(BedroomLights.nextChange(after: at(12), calendar: calendar) == at(18))
    #expect(
      BedroomLights.nextChange(after: at(18), calendar: calendar)
        == at(6).addingTimeInterval(86_400))
    #expect(BedroomLights.nextChange(after: at(2), calendar: calendar) == at(6))
  }
}
