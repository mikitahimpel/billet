import Foundation
import Observation
import Wire

/// Twenty-four small doors. Each of you draws behind some for the other, and a door can be opened
/// from its own day in December.
public struct AdventCalendar: Codable, Equatable, Sendable {
  public static let doors = 1...24

  public struct Door: Codable, Equatable, Sendable {
    public enum Maker: String, Codable, Sendable {
      /// Drawn on this phone, for the partner.
      case me
      /// Drawn by the partner, for this phone.
      case partner
    }

    public let strokes: [Stroke]
    public let maker: Maker
    public var opened: Bool

    public init(strokes: [Stroke], maker: Maker, opened: Bool = false) {
      self.strokes = strokes
      self.maker = maker
      self.opened = opened
    }
  }

  /// The year of December the doors are for.
  public let year: Int
  public private(set) var filled: [Int: Door]

  public init(year: Int, filled: [Int: Door] = [:]) {
    self.year = year
    self.filled = filled.filter { Self.doors.contains($0.key) }
  }

  /// The year of the December that comes next, or the current one during it.
  public static func year(at date: Date, calendar: Calendar) -> Int {
    calendar.component(.year, from: date)
  }

  /// A door opens from its own day in December on, and a December's doors stay open to its end.
  public static func isOpenable(_ number: Int, on date: Date, calendar: Calendar) -> Bool {
    guard doors.contains(number), calendar.component(.month, from: date) == 12 else { return false }
    return calendar.component(.day, from: date) >= number
  }

  /// Today's door number during December up to the 24th, else nil.
  public static func todaysDoor(on date: Date, calendar: Calendar) -> Int? {
    guard calendar.component(.month, from: date) == 12 else { return nil }
    let day = calendar.component(.day, from: date)
    return doors.contains(day) ? day : nil
  }

  /// Draws behind an empty door for the partner. A door that is already filled stays as it is.
  @discardableResult
  public mutating func fillForPartner(_ number: Int, strokes: [Stroke]) -> Bool {
    guard Self.doors.contains(number), filled[number] == nil, !strokes.isEmpty else { return false }
    filled[number] = Door(strokes: strokes, maker: .me)
    return true
  }

  /// The partner filled a door for this phone. Their door never replaces one this phone filled.
  public mutating func partnerFilled(_ number: Int, strokes: [Stroke]) {
    guard Self.doors.contains(number), filled[number] == nil else { return }
    filled[number] = Door(strokes: strokes, maker: .partner)
  }

  /// Opens a partner's door on a day it can be opened, and returns what is behind it.
  public mutating func open(_ number: Int, on date: Date, calendar: Calendar) -> [Stroke]? {
    guard Self.isOpenable(number, on: date, calendar: calendar), let door = filled[number],
      door.maker == .partner
    else { return nil }
    filled[number]?.opened = true
    return door.strokes
  }

  public func door(_ number: Int) -> Door? { filled[number] }
}

/// The advent calendar, kept in `defaults` for the year it is for.
@MainActor
@Observable
public final class AdventStore {
  public private(set) var calendar: AdventCalendar
  /// The door the canvas is open for, if it is.
  public var drawingFor: Int?

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let key: String

  public init(
    year: Int, defaults: UserDefaults = .standard, key: String = "labs.advent"
  ) {
    self.defaults = defaults
    self.key = key
    let stored = defaults.data(forKey: key).flatMap {
      try? JSONDecoder().decode(AdventCalendar.self, from: $0)
    }
    // A calendar from another year starts over.
    calendar = stored.flatMap { $0.year == year ? $0 : nil } ?? AdventCalendar(year: year)
  }

  /// Puts the drawing behind the door the canvas was opened for. Returns the door, or nil when
  /// there is none or it cannot be filled.
  @discardableResult
  public func finishDrawing(_ strokes: [Stroke]) -> Int? {
    defer { drawingFor = nil }
    guard let number = drawingFor, calendar.fillForPartner(number, strokes: strokes) == true else {
      return nil
    }
    save()
    return number
  }

  public func partnerFilled(_ number: Int, strokes: [Stroke]) {
    calendar.partnerFilled(number, strokes: strokes)
    save()
  }

  public func open(_ number: Int, on date: Date, calendar cal: Calendar) -> [Stroke]? {
    let strokes = calendar.open(number, on: date, calendar: cal)
    if strokes != nil { save() }
    return strokes
  }

  private func save() {
    defaults.set(try? JSONEncoder().encode(calendar), forKey: key)
  }
}
