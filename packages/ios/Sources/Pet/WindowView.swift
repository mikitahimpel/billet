import Foundation

/// What a styled room's window looks out on. Each view is a flag in Labs and later a shop item;
/// the raw value is what gets stored, so it stays stable across releases.
public enum WindowView: String, CaseIterable, Codable, Hashable, Sendable {
  /// A US suburb at night: roofs, power lines, a water tower, the street lamp.
  case suburbNight
  /// The suburb in the rain: a corner store's window, a bus shelter, puddles, lightning.
  case rainySuburb
  /// A snowy December street with Christmas lights on the houses.
  case snowyDecember
  /// A summer cul-de-sac with fireflies, a sprinkler and a trampoline.
  case summerCulDeSac
  /// A college quad at night: a brick dorm's windows, globe lamps, students crossing.
  case dormQuad
  /// A New York walk-up's fire escape over a street of yellow cabs and steam.
  case fireEscape
  /// Los Angeles at pink dusk: tall palms, a taco truck, parrots and planes lining up to land.
  case pinkDusk
  /// A beach at sunset: gentle waves, a sailboat on the horizon, gulls and a lifeguard tower.
  case sunsetBeach
  /// A cabin in a pine forest at night, its window lit and smoke from the chimney, fireflies.
  case forestCabin
  /// Snowy mountains under the moon, a lit chalet and a gondola crossing on its cable.
  case moonlitPeaks
  /// A narrow city street in the rain: neon signs, umbrellas and a train on the line above.
  case neonStreet
  /// Old city rooftops at dusk: chimney pots, zinc roofs, a dome and balconies with flowers.
  case rooftopsDusk
  /// An autumn park: leaves falling from orange trees, a pond, joggers and dogs.
  case autumnPark
  /// A lake at sunrise with mist on the water, a canoe and ducks.
  case mistyLake
  /// A desert at night under a huge starry sky, a camper van glowing by the mesas.
  case desertStars

  /// What a window shows before anyone chooses.
  public static let standard = WindowView.suburbNight

  /// The views that have a 3D version, behind Labs' "3D view" switch.
  public static let inDepth: Set<WindowView> = [.suburbNight]

  public var title: String {
    switch self {
    case .suburbNight: "Suburb at night"
    case .rainySuburb: "Rainy suburb"
    case .snowyDecember: "Snowy December"
    case .summerCulDeSac: "Summer cul-de-sac"
    case .dormQuad: "College dorm quad"
    case .fireEscape: "NYC fire escape"
    case .pinkDusk: "LA palms at pink dusk"
    case .sunsetBeach: "Beach at sunset"
    case .forestCabin: "Forest cabin at night"
    case .moonlitPeaks: "Mountains under the moon"
    case .neonStreet: "Neon street in the rain"
    case .rooftopsDusk: "Rooftops at dusk"
    case .autumnPark: "Autumn park"
    case .mistyLake: "Misty lake at sunrise"
    case .desertStars: "Desert under the stars"
    }
  }

  public var detail: String {
    switch self {
    case .suburbNight: "Power lines, a water tower, a street lamp and the neighbours' windows."
    case .rainySuburb:
      "Rain on the glass, a corner store's window, puddles and now and then lightning."
    case .snowyDecember:
      "Christmas lights on the gutters, chimney smoke and a house that went all out."
    case .summerCulDeSac: "Fireflies at dusk, a sprinkler, a trampoline and a hoop over the garage."
    case .dormQuad:
      "LED strips in the dorm windows, the clock tower and people cutting across the lawn."
    case .fireEscape: "Pigeons on the railing, cabs below, a steam stack and the skyline behind."
    case .pinkDusk:
      "Palms against a pink sky, a taco truck, wild parrots and planes coming in to land."
    case .sunsetBeach: "Gentle waves at sunset, a sailboat going by, gulls and a lifeguard tower."
    case .forestCabin: "A lit cabin among the pines, smoke from the chimney and fireflies."
    case .moonlitPeaks: "Snowy peaks in moonlight, a lit chalet and a gondola on its cable."
    case .neonStreet: "Neon signs in the rain, umbrellas below and a train rattling over."
    case .rooftopsDusk: "Chimney pots and zinc roofs at dusk, flowers on the balconies, pigeons."
    case .autumnPark: "Orange trees letting go of their leaves, a pond, joggers and dogs."
    case .mistyLake: "Mist lifting off a still lake at sunrise, a canoe and a line of ducks."
    case .desertStars: "Mesas under a sky full of stars, shooting stars and a glowing camper."
    }
  }

  /// The weather the view is made for, used when the choice leaves weather to the view.
  public var weather: ViewWeather {
    switch self {
    case .suburbNight, .summerCulDeSac, .dormQuad, .fireEscape, .pinkDusk, .sunsetBeach,
      .forestCabin, .moonlitPeaks, .rooftopsDusk, .autumnPark, .mistyLake, .desertStars:
      .clear
    case .rainySuburb, .neonStreet: .rain
    case .snowyDecember: .snow
    }
  }

  /// The hour the view is made for, used when neither the choice nor the room sets one.
  public var hour: ViewHour {
    switch self {
    case .suburbNight, .rainySuburb, .snowyDecember, .summerCulDeSac, .dormQuad, .fireEscape,
      .forestCabin, .moonlitPeaks, .neonStreet, .desertStars:
      .night
    case .pinkDusk, .sunsetBeach, .rooftopsDusk: .dusk
    case .autumnPark: .day
    case .mistyLake: .morning
    }
  }
}

/// Weather over a window view: on the glass and in the air between its planes.
public enum ViewWeather: String, CaseIterable, Codable, Hashable, Sendable {
  case clear
  case rain
  case snow
  case fog

  public var title: String {
    switch self {
    case .clear: "Clear"
    case .rain: "Rain"
    case .snow: "Snow"
    case .fog: "Fog"
    }
  }
}

/// The hour a window view is lit for, when it is not left to the room's own light.
public enum ViewHour: String, CaseIterable, Codable, Hashable, Sendable {
  case morning
  case day
  case dusk
  case night

  public var title: String {
    switch self {
    case .morning: "Morning"
    case .day: "Day"
    case .dusk: "Dusk"
    case .night: "Night"
    }
  }

  /// The light of a typical hour of this part of the day.
  public var light: DayLight {
    switch self {
    case .morning: .at(hour: 7.5)
    case .day: .at(hour: 13)
    case .dusk: .at(hour: 19.5)
    case .night: .at(hour: 23)
    }
  }

  public init(_ phase: DayLight.Phase) {
    switch phase {
    case .morning: self = .morning
    case .day: self = .day
    case .goldenHour: self = .dusk
    case .night: self = .night
    }
  }
}

/// A window view with its modifiers, as chosen in Labs. `nil` leaves a modifier to the view (its
/// own weather) or to the room (its light, which is night unless the room follows the clock).
public struct WindowViewChoice: Codable, Hashable, Sendable {
  public var view: WindowView
  public var weather: ViewWeather?
  public var hour: ViewHour?
  /// Labs: the view in 3D, with true depth as the room turns, where the view has a 3D version
  /// for the weather and hour shown. Elsewhere the flat view stays.
  public var inDepth: Bool

  public static let standard = WindowViewChoice(view: .standard, inDepth: true)

  public init(
    view: WindowView, weather: ViewWeather? = nil, hour: ViewHour? = nil, inDepth: Bool = true
  ) {
    self.view = view
    self.weather = weather
    self.hour = hour
    self.inDepth = inDepth
  }

  /// The weather shown: the chosen one, or the view's own.
  public var shownWeather: ViewWeather { weather ?? view.weather }

  /// The hour shown: the chosen one, or the room's, or the view's own.
  public func shownHour(room: DayLight?) -> ViewHour {
    hour ?? room.map { ViewHour($0.phase) } ?? view.hour
  }

  // A view dropped from a later release decodes as the standard one, keeping the modifiers.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let raw = try container.decode(String.self, forKey: .view)
    view = WindowView(rawValue: raw) ?? .standard
    weather = try? container.decodeIfPresent(ViewWeather.self, forKey: .weather)
    hour = try? container.decodeIfPresent(ViewHour.self, forKey: .hour)
    inDepth = (try? container.decodeIfPresent(Bool.self, forKey: .inDepth)) ?? true
  }

  /// Whether the view is shown in 3D in `weather` at `hour`: only the suburb has a 3D street so
  /// far, made for a clear night.
  public func showsInDepth(weather: ViewWeather, hour: ViewHour) -> Bool {
    inDepth && WindowView.inDepth.contains(view) && weather == .clear && hour == .night
  }
}

/// Something small that happens now and then in a view, such as a car passing: at most one pass
/// in each slot of `slot` seconds, at a place in the slot and with a variant drawn from a hash of
/// the slot's number. Gaps, order and variants never settle into a loop, and any moment is found
/// without stepping through the ones before it.
public struct ViewRhythm: Hashable, Sendable {
  /// One pass of the event.
  public struct Pass: Hashable, Sendable {
    /// Which slot it is in, the same for every frame of the pass.
    public var index: Int64
    /// From 0 when it starts to 1 when it ends.
    public var progress: Double
    /// From 0 to 1, fixed for the pass: a direction, a colour, a lane.
    public var variant: Double
    /// Seconds the pass lasts.
    public var length: Double

    public init(index: Int64, progress: Double, variant: Double, length: Double) {
      self.index = index
      self.progress = progress
      self.variant = variant
      self.length = length
    }
  }

  public var seed: UInt64
  /// Seconds per slot.
  public var slot: Double
  /// From 0 to 1, how many slots hold a pass.
  public var chance: Double
  /// Seconds a pass lasts, picked per pass. Kept below `slot`.
  public var length: ClosedRange<Double>

  public init(seed: UInt64, slot: Double, chance: Double, length: ClosedRange<Double>) {
    self.seed = seed
    self.slot = max(slot, 0.1)
    self.chance = chance
    self.length = min(length.lowerBound, self.slot)...min(length.upperBound, self.slot)
  }

  /// The pass under way at `time`, or `nil` between passes.
  public func pass(at time: Double) -> Pass? {
    let index = Int64((time / slot).rounded(.down))
    for candidate in [index, index - 1] {
      if let pass = pass(in: candidate, at: time) { return pass }
    }
    return nil
  }

  /// The pass in slot `index`, if it is under way at `time`. A pass may run past its slot's end
  /// into the next one, so the slot before is asked too.
  private func pass(in index: Int64, at time: Double) -> Pass? {
    var random = SplitMix64(seed: seed ^ UInt64(bitPattern: index) &* 0x9E37_79B9_7F4A_7C15)
    guard random.next(in: 0...1) < chance else { return nil }
    let length = random.next(in: length)
    let start = Double(index) * slot + random.next(in: 0...slot)
    let variant = random.next(in: 0...1)
    guard time >= start, time < start + length else { return nil }
    return Pass(index: index, progress: (time - start) / length, variant: variant, length: length)
  }

  /// A number from 0 to 1 for `index`, the same every time it is asked: for picking things that
  /// stay put, such as which windows are lit.
  public static func hash(_ index: Int, seed: UInt64) -> Double {
    var random = SplitMix64(seed: seed ^ UInt64(truncatingIfNeeded: index) &* 0xBF58_476D_1CE4_E5B9)
    return random.next(in: 0...1)
  }
}
