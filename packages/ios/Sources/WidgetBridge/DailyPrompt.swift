import Foundation

/// The day's question and doodle prompt. They depend only on the calendar day, so both partners
/// are asked the same thing without the room being involved.
public enum DailyPrompt {
  public static let questions = [
    "What made you smile today?",
    "What is one small thing you are looking forward to?",
    "What did you eat that you would share?",
    "What is the view from where you are?",
    "Which song is stuck in your head?",
    "What would you do with a free hour right now?",
    "What is something you noticed today that no one else did?",
    "Where would you like to be this weekend?",
    "What is the nicest thing someone did for you this week?",
    "What are you wearing, and is it warm enough?",
    "What was the best part of your morning?",
    "What is something you want to learn?",
    "What did you dream about?",
    "What is on your desk right now?",
  ]

  public static let doodles = [
    "Draw the cat asleep.",
    "Draw your lunch.",
    "Draw the weather outside.",
    "Draw your mood as a creature.",
    "Draw a tiny house with the lights on.",
    "Draw what is in your left hand.",
    "Draw the view from your window.",
    "Draw yourself as a cat.",
    "Draw a gift for your partner.",
    "Draw the moon, however you remember it.",
    "Draw your favourite mug.",
    "Draw a plant that does not exist.",
    "Draw a hat for the cat.",
    "Draw the shape of today.",
  ]

  public static func question(on day: String) -> String {
    questions[index(day, count: questions.count)]
  }

  public static func doodle(on day: String) -> String {
    doodles[index(day, count: doodles.count)]
  }

  /// Whole days since 1970 for a `yyyy-MM-dd` key, so consecutive days take consecutive prompts.
  static func index(_ day: String, count: Int) -> Int {
    let parts = day.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return 0 }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    guard
      let date = calendar.date(
        from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    else { return 0 }
    let days = Int((date.timeIntervalSince1970 / 86_400).rounded())
    return ((days % count) + count) % count
  }

  /// The prompt the canvas shows: the question if that card is on, else the doodle.
  public static func canvasPrompt(features: WidgetFeatures, day: String) -> String? {
    if features.isOn(.questionCard) { return question(on: day) }
    if features.isOn(.doodleCard) { return doodle(on: day) }
    return nil
  }
}
