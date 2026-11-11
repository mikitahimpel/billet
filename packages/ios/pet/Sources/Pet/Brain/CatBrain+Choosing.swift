import Foundation

extension CatBrain {
  /// One of the group's scripts, weighted by what the room has, the cat's traits and the hour.
  func chooseScript(_ group: CatActivityGroup, at t: Double) -> [CatActivityStep] {
    let p = personality
    let away = awayHours(at: t) > CatBrainConfig.missingAfterHours
    // A cat shooed off enough keeps off the desk and the cardigan.
    let stayOn = 1 - 0.9 * upbringing.stayingOff
    let feeling = feeling
    let drama = temperament?.drama ?? 1
    let low = lifeConfig.lowBelow
    let bored = life.needs.playful < low ? 1.0 : 0
    let lonely = life.needs.loved < low
    let happy = feeling == .happy
    let clock = hour(at: t)
    let dusk = Self.near(clock, 19, 1.8)
    let midday = Self.near(clock, 13, 2.5)
    let sunny = isSunny(at: t) && room.has(.window)
    let candidates: [([CatActivityStep], Double)] =
      switch group {
      case .idle:
        [
          ([.sit], 1), ([.loaf], 0.4 + p.lazy), ([.sit, .lookAround], 0.4 + p.curious),
          ([.lookAround, .sit], 0.3 + p.curious), ([.bellyUp], happy ? 1.2 + p.cuddly : 0),
          ([.sit, .heardNoise, .lookAround], 0.5 + p.curious),
        ]
      case .explore:
        [
          ([.wander, .sniffObject], 1), ([.wander], 0.4), ([.wander, .sniffObject, .wander], 1),
          ([.inspectFurniture, .sniffObject], novelPiece(at: t) != nil ? 4 : 0),
        ]
      case .groom:
        [
          ([.groomPaw], 1), ([.groomPaw, .groomFlank], 1), ([.groomFlank, .groomTail], 0.7),
          ([.groomPaw, .groomFlank, .groomTail], 0.4 + p.lazy),
          ([.bask, .groomPaw, .groomFlank], sunny ? 1 + 4 * midday : 0),
          ([.groomPaw, .bask], sunny ? 1 + 2 * midday : 0),
        ]
      case .eat: eatScripts(at: t, feeling: feeling)
      case .play:
        [
          ([.stalk, .pounce], 0.4), ([.stalk, .pounce, .chase], 0.3 + p.bold),
          ([.batObject], room.reachable(.toy) ? 0.8 : 0.3),
          ([.zoomies], 0.1 + p.playful * 0.3 + bored * drama), ([.chase, .pounce], 0.4),
          (
            [.scratch],
            room.reachable(.scratchingPost) || room.reachable(.soft)
              ? 0.15 + 1.5 * bored * drama : 0
          ),
          ([.stalk, .pounce, .batObject], room.reachable(.toy) ? 0.3 + 1.5 * bored : 0),
          ([.spotMote, .windUp, .pounce, .shakeOff], 0.6 + p.curious + p.playful),
          ([.stalk, .windUp, .pounce, .shakeOff], 0.8 + p.bold),
          ([.windUp, .zoomies, .skid], 0.3 + 2.5 * dusk + p.playful + 2 * bored * drama),
          ([.chaseTail], 0.4 + p.playful),
        ]
      case .watch:
        [
          ([.watchWindow], 0.5), ([.watchPartnerWindow], away ? 1.5 : 0),
          ([.watchWindow, .trackMover, .watchWindow], 1.2),
          ([.watchWindow, .trackMover, .chatter, .watchWindow], 0.5 + p.curious + p.vocal),
        ]
      case .social:
        [
          ([.seekYou, .rub], 0.6 + p.cuddly), ([.slowBlink], 0.8),
          ([.seekYou, .slowBlink], 0.4 + p.vocal),
          (
            [.bringToy, .dropToy, .slowBlink],
            room.reachable(.toy)
              ? 0.3 + p.playful * 0.5 + upbringing.playfulness + 2 * bored : 0
          ),
          ([.waitByDoor], away ? 1.2 : 0),
          // Lonely, it sulks: more the bigger its feelings, less the more it loves company.
          ([.sulk], lonely ? 2.5 * drama * (1.4 - p.cuddly) : 0),
        ]
      case .mischief:
        [
          ([.pushItem, .glanceBack], room.reachable(.smallItem) ? 0.5 + p.bold : 0),
          ([.sitInCardigan], room.reachable(.soft) ? (0.6 + p.cuddly) * stayOn : 0),
          ([.sitOnDesk], room.reachable(.desk) ? (0.6 + p.bold) * stayOn : 0),
        ]
      case .rest: [([.findNapSpot, .curl, .wake], 1)]
      case .react: [([.curiousTilt], 1)]
      }
    let open = candidates.map { ($0.0, $0.1 * variety($0.0, at: t)) }.filter { $0.1 > 0 }
    let total = open.reduce(0) { $0 + $1.1 }
    guard total > 0 else { return [.sit] }
    var left = dice(t, 5) * total
    for (script, weight) in open {
      left -= weight
      if left < 0 { return script }
    }
    return open.last?.0 ?? [.sit]
  }

  /// How many scripts the cat remembers having played.
  static let scriptMemory = 8

  /// Rare steps: seconds before one can come again, and how many a day. A script with one in it
  /// is offered only when it is off cooldown and under its cap.
  static let rarities: [CatActivityStep: (cooldown: Double, perDay: Int)] = [
    .heardNoise: (2400, 6), .chaseTail: (5400, 3),
  ]

  /// Scales a script's weight for how lately it was played and for being rare: 0.12 if it was one
  /// of the last two, a half if one of the last five, and 0 for a rare one that is resting.
  func variety(_ script: [CatActivityStep], at t: Double) -> Double {
    for step in script {
      guard let rarity = Self.rarities[step] else { continue }
      let log = rareLog[step] ?? []
      if log.count >= rarity.perDay { return 0 }
      if let last = log.last, t - last < rarity.cooldown { return 0 }
    }
    guard let index = scriptLog.lastIndex(of: script) else { return 1 }
    let age = scriptLog.count - index
    return age <= 2 ? 0.12 : age <= 5 ? 0.5 : 1
  }

  static func near(_ hour: Double, _ peak: Double, _ width: Double) -> Double {
    var gap = abs(hour - peak).truncatingRemainder(dividingBy: 24)
    if gap > 12 { gap = 24 - gap }
    return exp(-(gap * gap) / (2 * width * width))
  }

  /// What a cat at the bowl does, by how hungry it is: a snack from a full bowl, waiting for the
  /// meal it is used to, asking at an empty one, and a tantrum once it is hangry.
  private func eatScripts(at t: Double, feeling: CatFeeling) -> [([CatActivityStep], Double)] {
    // At the hour it is fed, even a starving cat mostly sits by the bowl: it knows dinner comes.
    let mealtime = isMealtime(at: t) ? 4.0 : 0
    switch feeling {
    case .hangry:
      let reach = room.reachable(.smallItem) ? 1.0 : 0
      return [
        ([.yowl, .knockOff], 1.6 * reach), ([.walkToBowl, .pawBowl, .yowl], 1.2), ([.flop], 1),
        ([.beg, .yowl], 1), ([.knockOff, .flop], 1.2 * reach),
        ([.walkToBowl, .waitByBowl], mealtime),
      ]
    case .hungry:
      // It waits where the food comes, facing you, so a glance at the room says what it wants.
      // With no bowl it can reach, it begs at you instead.
      let bowl = room.reachable(.bowl)
      return [
        ([.walkToBowl, .waitByBowl], bowl ? 2 + mealtime : 0),
        ([.walkToBowl, .pawBowl, .waitByBowl], bowl ? 1 : 0), ([.beg], bowl ? 0 : 1),
      ]
    case .asleep, .lonely, .bored, .sleepy, .happy, .content:
      return [
        ([.walkToBowl, .eat, .lickLips], 1),
        ([.walkToBowl, .waitByBowl], isMealtime(at: t) ? 4 : 0),
      ]
    }
  }

  /// Where to curl up: a bed or something soft, the sun by day, the rug, else its own place.
  /// A spot it has rested and been petted in a lot is up to four times likelier.
  func chooseNapSpot(at t: Double) -> RoomAffordance.Kind? {
    let options = napSpots(at: t).map { kind, weight in
      (kind, weight * (1 + 3 * memory.fondness(kind)))
    }
    let total = options.reduce(0) { $0 + $1.1 }
    guard total > 0 else { return nil }
    var left = dice(t, 6) * total
    for (kind, weight) in options {
      left -= weight
      if left < 0 { return kind }
    }
    return options.last?.0
  }

  /// The places the cat can curl up in now, weighted by its traits.
  private func napSpots(at t: Double) -> [(RoomAffordance.Kind, Double)] {
    let sunny = isSunny(at: t)
    let options: [(RoomAffordance.Kind, Double)] = [
      (.bed, 3), (.soft, 2 + personality.cuddly), (.sunbeam, sunny ? 3 : 0), (.rug, 1),
      (.box, 1 + personality.curious), (.shelf, personality.bold * 1.5),
      (.sofa, 2.5 + personality.cuddly), (.catBed, 3), (.crate, 1 + personality.curious),
      (.windowSeat, sunny ? 3 : 1.5),
    ]
    return options.filter { kind, weight in
      weight > 0 && (kind == .sunbeam ? sunny && room.reachable(.window) : room.reachable(kind))
    }
  }

  // MARK: - Utility

  public func utilityInput(at t: Double) -> CatUtilityInput {
    CatUtilityInput(
      now: t, needs: life.needs, focus: focus.focus, mood: life.mood, hour: hour(at: t),
      vitality: vitality, sleepy: life.pressure > config.drowsyAbove, personality: personality,
      temperament: temperament,
      room: effectiveRoom(at: t), weather: weather,
      recent: recent, awayHours: awayHours(at: t), hasNovelty: novelPiece(at: t) != nil,
      spotFondness: napSpots(at: t).map { memory.fondness($0.0) }.max() ?? 0,
      upbringing: upbringing, mealtime: isMealtime(at: t), stuffed: life.stuffed, hunger: hunger,
      habits: Dictionary(
        uniqueKeysWithValues: CatActivityGroup.chosen.map {
          ($0, memory.habit($0, hour: Int(hour(at: t))))
        }))
  }

  /// Whether it is the hour the pair feeds it and it has not eaten yet.
  func isMealtime(at t: Double) -> Bool {
    upbringing.isMealtime(at: t, utcOffset: utcOffset) && life.needs[.full] < Self.waitsBelow
  }

  /// How long a piece counts as new after it appears, in seconds.
  public static let noveltySeconds = 24.0 * 3600

  /// A piece put in the room within the last day that the cat has not been to look at yet.
  func novelPiece(at t: Double) -> RoomAffordance? {
    room.furniture.first { piece in
      guard let since = piece.since, t >= since, t - since < Self.noveltySeconds else {
        return false
      }
      return !inspected.contains(piece.id)
    }
  }

  /// The room with a sunbeam under the window by day in clear weather.
  private func effectiveRoom(at t: Double) -> RoomAffordances {
    guard isSunny(at: t), room.has(.window), !room.has(.sunbeam) else { return room }
    let window = room.all.first { $0.kind == .window }
    return RoomAffordances(
      room.all + [
        RoomAffordance(id: "sunbeam", kind: .sunbeam, reachable: window?.reachable ?? false)
      ])
  }

  private func isSunny(at t: Double) -> Bool {
    let hour = hour(at: t)
    return weather == .clear && hour >= 9 && hour < 17
  }

  /// Who did something for the cat last, of the events folded so far.
  public var lastBy: String? {
    lastSeen.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }?.key
  }

  /// How long the partner seen least recently has been away. With only one partner seen yet,
  /// nobody is missed.
  public func awayHours(at t: Double) -> Double {
    guard lastSeen.count >= 2, let oldest = lastSeen.values.min() else { return 0 }
    return max(t - oldest, 0) / 3600
  }
}
