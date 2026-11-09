import Foundation
import MoodInterface
import Testing

struct MoodCheckInTests {
  @Test func aNoteIsTrimmedAndCutToWhatTheServerKeeps() {
    #expect(MoodCheckIn.clean("   ") == nil)
    #expect(MoodCheckIn.clean(nil) == nil)
    #expect(MoodCheckIn.clean(" hi ") == "hi")
    let long = String(repeating: "😴", count: 50)
    #expect(MoodCheckIn.clean(long)?.utf16.count == MoodCheckIn.noteLimit)
  }

  @Test func aLaterCheckInStaysUnlessReplaced() {
    let now = Date.now
    var latest: [String: MoodCheckIn] = ["M": MoodCheckIn(mood: .happy, date: now)]
    let older = MoodCheckIn(mood: .busy, date: now.addingTimeInterval(-1))

    #expect(!MoodCheckIn.take(older, for: "M", into: &latest))
    #expect(latest["M"]?.mood == .happy)
    #expect(MoodCheckIn.take(older, for: "M", into: &latest, replacing: true))
    #expect(latest["M"]?.mood == .busy)
  }

  @Test func theFileKeepsTheShapeTheWidgetsRead() throws {
    let json = Data(#"{"mood":"missing","date":0,"note":"hi"}"#.utf8)
    let check = try JSONDecoder().decode(MoodCheckIn.self, from: json)
    #expect(
      check
        == MoodCheckIn(mood: .missing, date: Date(timeIntervalSinceReferenceDate: 0), note: "hi"))
  }
}
