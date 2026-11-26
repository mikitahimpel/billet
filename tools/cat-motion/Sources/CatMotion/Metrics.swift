import Foundation
import simd

/// One frame of a run. Lengths in room units unless a name says model; angles in radians.
struct Sample: Codable {
  struct Paw: Codable {
    var at: SIMD3<Float>
    var planted: Bool
    var upper: Float
    var lower: Float
  }

  var time: Float
  var action: String
  var shown: String
  var moving: Bool
  var at: SIMD3<Float>
  var yaw: Float
  /// The body's posture as the standing rig holds it.
  var lift: Float, pitch: Float, roll: Float, bend: Float, headPitch: Float, headYaw: Float, tail: Float
  var paws: [Paw]
  /// How far behind the body's origin the hind paws are, model units.
  var hindReach: Float = 0
  /// Share of the side view's silhouette that changed since the frame before: pixels covered in one
  /// of the two only, over pixels covered in either.
  var silhouetteChange: Float = 0

  /// Her head's small parts and the tail's tip, as the standing rig holds them.
  struct Face: Codable {
    var roll: Float
    var earTurn: SIMD2<Float>
    var earFlick: SIMD2<Float>
    var lid: Float
    var tailTip: Float
    /// The chest's turn under the head; the rig's head yaw is from the chest.
    var chestYaw: Float
  }
  var face: Face?

  init(time: Float, action: String, stage: Stage) {
    self.time = time
    self.action = action
    shown = stage.shownName
    moving = stage.walker.moving
    at = stage.group.position
    yaw = stage.walker.heading
    let rig = stage.standing
    let p = rig.pose
    (lift, pitch, roll, bend, headPitch, headYaw) = (p.lift, p.pitch, p.roll, p.bend, p.headPitch, p.headYaw)
    tail = p.tail.first?.lift ?? 0
    // Chest and hips as CatRig.update poses them, to read the legs' angles off the same solver.
    var body = Pose.about(rig.spineMid, .x(p.pitch) * .z(p.roll))
    body.t.y += p.lift
    body.t.z += p.back
    let chest = Pose.about(rig.spineMid, .x(p.bend / 2)).under(body).under(p.chestMove)
    let hips = Pose.about(rig.spineMid, .y(p.wiggle) * .x(-p.bend / 2)).under(body).under(p.hipsMove)
    let toWorld = stage.modelToWorld
    let standing = shown == "MochiStanding"
    paws = rig.legs.enumerated().map { i, leg in
      let parent = leg.fore ? chest : hips
      let (upper, lower, _) = Gait.solveLeg(
        hip: leg.hip, knee: leg.knee, paw: leg.paw, target: parent.inverse.apply(p.feet[i]))
      let world = toWorld * SIMD4(p.feet[i], 1)
      return Paw(
        at: [world.x, world.y, world.z], planted: standing && p.feet[i].y < leg.paw.y + 0.0015, upper: upper,
        lower: lower)
    }
    hindReach = Self.hindReach(stage)
    face = Face(
      roll: p.headRoll, earTurn: [p.earTurnLeft, p.earTurnRight], earFlick: [p.earLeft, p.earRight],
      lid: max(p.lidLeft, p.lidRight), tailTip: p.tail.last?.sway ?? 0,
      chestYaw: 2 * atan2(p.chestMove.q.imag.y, p.chestMove.q.real))
  }

  static func hindReach(_ stage: Stage) -> Float {
    let rig = stage.standing
    let hind = rig.legs.indices.filter { !rig.legs[$0].fore }
    return hind.reduce(Float(0)) { $0 + rig.pose.feet[$1].z } / Float(max(hind.count, 1))
  }

  static func change(_ a: [UInt8], _ b: [UInt8]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var either = 0, one = 0
    for i in a.indices {
      let (x, y) = (a[i] > 96, b[i] > 96)
      if x || y { either += 1 }
      if x != y { one += 1 }
    }
    return either > 0 ? Float(one) / Float(either) : 0
  }
}

/// Numbers that say how mechanical a run looks.
struct Metrics {
  let samples: [Sample]
  let dt: Float

  private func rate(_ value: (Sample) -> Float) -> [Float] {
    [0] + zip(samples, samples.dropFirst()).map { (value($1) - value($0)) / dt }
  }

  private func difference(_ values: [Float]) -> [Float] {
    [0] + zip(values, values.dropFirst()).map { ($1 - $0) / dt }
  }

  /// Runs of at least `least` frames where `test` holds, as index ranges.
  private func runs(least: Int = 1, bridging gap: Int = 0, _ test: (Int) -> Bool) -> [Range<Int>] {
    var found: [Range<Int>] = []
    var start: Int?
    for i in samples.indices {
      if test(i) {
        if start == nil { start = i }
      } else if let s = start {
        found.append(s..<i)
        start = nil
      }
    }
    if let s = start { found.append(s..<samples.count) }
    var merged: [Range<Int>] = []
    for run in found {
      if let last = merged.last, run.lowerBound - last.upperBound <= gap {
        merged[merged.count - 1] = last.lowerBound..<run.upperBound
      } else {
        merged.append(run)
      }
    }
    return merged.filter { $0.count >= least }
  }

  private var channels: [(name: String, value: (Sample) -> Float, least: Float)] {
    var all: [(String, (Sample) -> Float, Float)] = [
      ("lift", { $0.lift }, 0.003), ("pitch", { $0.pitch }, 0.03), ("bend", { $0.bend }, 0.03),
      ("headPitch", { $0.headPitch }, 0.03), ("tail", { $0.tail }, 0.05),
    ]
    // The hind paws' place under her, in model units along her length, apart from the gait's steps.
    if (samples.first?.paws.count ?? 0) > 0 { all.append(("hindPaws", { $0.hindReach }, 0.004)) }
    return all
  }

  func report(_ name: String) -> String {
    guard samples.count > 3 else { return "\(name): no samples" }
    var lines = ["== \(name) (\(String(format: "%.2f", samples.last!.time)) s) =="]
    func line(_ key: String, _ value: String) { lines.append("  " + key.padding(toLength: 34, withPad: " ", startingAt: 0) + value) }
    func f(_ x: Float, _ digits: Int = 2) -> String { String(format: "%.\(digits)f", x) }

    let speed = [0] + zip(samples, samples.dropFirst()).map { simd_distance($0.at, $1.at) / dt }
    let yawRate = rate { $0.yaw }
    let posture = zip(rate { $0.lift }, rate { $0.pitch }).map { max(abs($0) / 0.05, abs($1) / 0.5) }
    let legRate = (0..<(samples[0].paws.count)).map { i in rate { $0.paws[i].upper } }

    // Stance paws that slide along the floor.
    var slide: Float = 0, slideStill: Float = 0, worst: Float = 0
    for i in samples.indices.dropFirst() {
      for (a, b) in zip(samples[i - 1].paws, samples[i].paws) where a.planted && b.planted {
        let d = simd_distance(SIMD2(a.at.x, a.at.z), SIMD2(b.at.x, b.at.z))
        slide += d
        if speed[i] < 1e-3 && abs(yawRate[i]) < 0.02 { slideStill += d }
        worst = max(worst, d / dt)
      }
    }
    line("stance paw slide, total", "\(f(slide * 1000, 1)) mm (of it standing in place \(f(slideStill * 1000, 1)) mm)")
    line("stance paw slide, peak speed", "\(f(worst * 1000, 1)) mm/s")

    // Frozen while still busy: the walker says she is moving and nothing of the body does.
    let frozen = runs(least: 2) { i in
      samples[i].moving && speed[i] < 1e-3 && abs(yawRate[i]) < 0.02 && posture[i] < 0.02
        && legRate.allSatisfy { abs($0[i]) < 0.05 }
    }
    let frozenTime = Float(frozen.reduce(0) { $0 + $1.count }) * dt
    line("dead still inside a move", "\(frozen.count) times, \(f(frozenTime)) s in all, longest \(f(Float(frozen.map(\.count).max() ?? 0) * dt)) s")
    // Full stops between two bouts of travel: the root stops and starts again within the same errand.
    let busy = runs { samples[$0].moving }
    var stops = 0
    for run in busy {
      let moves = runs(bridging: 2) { run.contains($0) && (speed[$0] > 5e-3 || abs(yawRate[$0]) > 0.1) }
      stops += max(0, moves.count - 1)
    }
    line("full stops within an errand", "\(stops)")

    // Travel.
    let travelling = samples.indices.filter { speed[$0] > 5e-3 }
    if !travelling.isEmpty {
      let turnAll = yawRate.reduce(0) { $0 + abs($1) * dt }
      let turnWalking = travelling.reduce(Float(0)) { $0 + abs(yawRate[$1]) * dt }
      line("turning done while walking", "\(f(100 * turnWalking / max(turnAll, 1e-6), 0)) % of \(f(turnAll)) rad")
      let peak = speed.max() ?? 0
      let cruise = travelling.map { speed[$0] }.filter { $0 > 0.8 * peak }
      let mean = cruise.reduce(0, +) / Float(max(cruise.count, 1))
      let deviation = sqrt(cruise.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(max(cruise.count, 1)))
      line("speed", "peak \(f(peak, 3)) /s, at cruise \(f(100 * Float(cruise.count) / Float(travelling.count), 0)) % of travel, varying \(f(100 * deviation / max(mean, 1e-6), 1)) %")
    }
    let turning = samples.indices.filter { abs(yawRate[$0]) > 0.1 }
    if !turning.isEmpty {
      let lead = turning.reduce(Float(0)) { $0 + samples[$1].headYaw * (yawRate[$1] > 0 ? 1 : -1) } / Float(turning.count)
      let yawJerk = difference(difference(yawRate)).map(abs).max() ?? 0
      line("turn", "peak \(f(yawRate.map(abs).max() ?? 0)) rad/s, head ahead of body by \(f(lead)) rad on average, peak jerk \(f(yawJerk, 0)) rad/s3")
    }

    // Body swaps.
    for i in samples.indices.dropFirst() where samples[i].shown != samples[i - 1].shown {
      let around = (max(1, i - 20)...min(samples.count - 1, i + 20)).filter { $0 != i && samples[$0].shown == samples[$0 - 1].shown }
        .map { samples[$0].silhouetteChange }.sorted()
      let usual = around.isEmpty ? 0 : around[around.count / 2]
      line("swap at \(f(samples[i].time)) s", "\(samples[i - 1].shown) -> \(samples[i].shown): silhouette changes \(f(100 * samples[i].silhouetteChange, 1)) % in one frame (frames around it \(f(100 * usual, 1)) %)")
    }

    // Pose changes in place: how far apart in time the parts move, and whether anything overshoots.
    let changes = runs(least: 12, bridging: 6) { speed[$0] < 1e-3 && abs(yawRate[$0]) < 0.02 && posture[$0] > 0.05 }
    for run in changes {
      let (a, b) = (samples[run.lowerBound - (run.lowerBound > 0 ? 1 : 0)], samples[run.upperBound - 1])
      var halves: [(String, Float)] = []
      var over: Float = 0
      var jerk: Float = 0
      for channel in channels {
        let (from, to) = (channel.value(a), channel.value(b))
        let values = run.map { channel.value(samples[$0]) }
        if channel.name == "pitch" { jerk = difference(difference(difference(values))).dropFirst(3).map(abs).max() ?? 0 }
        guard abs(to - from) > channel.least else { continue }
        let progress = values.map { ($0 - from) / (to - from) }
        if let half = progress.firstIndex(where: { $0 >= 0.5 }) { halves.append((channel.name, Float(half) * dt)) }
        over = max(over, (progress.max() ?? 1) - 1)
      }
      guard let first = halves.min(by: { $0.1 < $1.1 }), let last = halves.max(by: { $0.1 < $1.1 }) else { continue }
      line("pose change \(f(a.time))-\(f(b.time)) s", "\(halves.count) parts half way within \(f((last.1 - first.1) * 1000, 0)) ms of each other (first \(first.0), last \(last.0)); overshoot \(f(100 * over, 0)) %; pitch jerk \(f(jerk, 0)) rad/s3")
    }
    lines += attention(line: { key, value in
      "  " + key.padding(toLength: 34, withPad: " ", startingAt: 0) + value
    })
    return lines.joined(separator: "\n")
  }

  /// How she attends: turns of the head and what leads them, how still she holds between, what she
  /// does before she sets off and after she arrives, and how much of her is alive on the move.
  private func attention(line: (String, String) -> String) -> [String] {
    guard samples.allSatisfy({ $0.face != nil }) else { return [] }
    func f(_ x: Float, _ digits: Int = 2) -> String { String(format: "%.\(digits)f", x) }
    var lines: [String] = []
    let speed = [0] + zip(samples, samples.dropFirst()).map { simd_distance($0.at, $1.at) / dt }
    let head = zip(rate { $0.headYaw + ($0.face?.chestYaw ?? 0) }, rate { $0.headPitch }).map { hypot($0, $1) }
    let ears = zip(rate { $0.face?.earTurn.x ?? 0 }, rate { $0.face?.earTurn.y ?? 0 }).map { max(abs($0), abs($1)) }
    let tip = rate { $0.face?.tailTip ?? 0 }.map(abs)

    // At rest: turns of the head, the holds between them, and whether an ear went first.
    let resting = samples.indices.filter { !samples[$0].moving }
    if resting.count > 600 {
      let turns = runs(least: 3, bridging: 4) { !samples[$0].moving && head[$0] > 0.5 }.filter { run in
        hypot(
          samples[run.upperBound - 1].headYaw - samples[run.lowerBound].headYaw,
          samples[run.upperBound - 1].headPitch - samples[run.lowerBound].headPitch) > 0.1
      }
      let minutes = Float(resting.count) * dt / 60
      let peak = turns.map { run in run.map { head[$0] }.max() ?? 0 }
      line2("head turns at rest", "\(f(Float(turns.count) / minutes, 1)) a minute, peak speed \(f(peak.min() ?? 0, 1))–\(f(peak.max() ?? 0, 1)) rad/s")
      let holds = zip(turns, turns.dropFirst()).map { Float($1.lowerBound - $0.upperBound) * dt }.sorted()
      if !holds.isEmpty {
        line2("holds between turns", "median \(f(holds[holds.count / 2], 1)) s, shortest \(f(holds[0], 1)) s, longest \(f(holds[holds.count - 1], 1)) s")
      }
      let led = turns.filter { run in
        let before = max(run.lowerBound - 24, 0)..<max(run.lowerBound - 2, 0)
        return before.contains { ears[$0] > 1.5 } && before.allSatisfy { head[$0] < 0.5 }
      }
      line2("turns an ear led", "\(led.count) of \(turns.count)")
      let alone = runs(least: 2, bridging: 6) { i in
        !samples[i].moving && ears[i] > 1.5 && (max(i - 6, 0)...min(i + 6, samples.count - 1)).allSatisfy { head[$0] < 0.3 }
      }
      line2("ear moves with the head still", "\(f(Float(alone.count) / minutes, 1)) a minute")
      // Stock still but for the ears and the tail's tip.
      let frozen = runs(least: 30) { !samples[$0].moving && head[$0] < 0.04 }
      let twitching = frozen.filter { run in run.contains { tip[$0] > 0.6 || ears[$0] > 0.8 } }
      line2("head held still 0.5 s or more", "\(f(100 * Float(frozen.reduce(0) { $0 + $1.count }) / Float(resting.count), 0)) % of her rest, in \(frozen.count) holds; an ear or the tail's tip moves in \(twitching.count) of them")
    }

    // Each errand: what she does before her body stirs, and between her last step and sitting.
    for run in runs(least: 30, { samples[$0].moving }) where run.contains(where: { speed[$0] > 5e-3 }) {
      let start = samples[run.lowerBound]
      let stir = run.first { samples[$0].shown != start.shown || speed[$0] > 1e-3 } ?? run.lowerBound
      func heading(_ sample: Sample) -> Float { sample.headYaw + (sample.face?.chestYaw ?? 0) }
      let looked = (run.lowerBound..<stir).map { abs(heading(samples[$0]) - heading(start)) }.max() ?? 0
      line2("errand at \(f(start.time, 1)) s, before", "\(f(Float(stir - run.lowerBound) * dt)) s from being sent to stirring, head turned \(f(looked)) rad meanwhile")
      let lastStep = run.last { speed[$0] > 5e-3 } ?? run.upperBound - 1
      let seated = (lastStep..<run.upperBound).first { samples[$0].shown != samples[lastStep].shown } ?? run.upperBound - 1
      let about = (lastStep..<seated).map { heading(samples[$0]) }
      line2("errand at \(f(start.time, 1)) s, after", "\(f(Float(seated - lastStep) * dt)) s from her last step to seated, head through \(f((about.max() ?? 0) - (about.min() ?? 0))) rad meanwhile")
    }

    // On the move: the head apart from where she steers, and the ears.
    let travelling = samples.indices.filter { speed[$0] > 5e-3 }
    if travelling.count > 60 {
      let turns = runs(least: 3, bridging: 4) { speed[$0] > 5e-3 && head[$0] > 0.5 }
      let earRange = [\Sample.Face.earTurn.x, \Sample.Face.earTurn.y].map { path -> Float in
        let values = travelling.compactMap { samples[$0].face?[keyPath: path] }
        return (values.max() ?? 0) - (values.min() ?? 0)
      }
      line2("walking", "\(turns.count) quick head moves in \(f(Float(travelling.count) * dt, 1)) s, ears through \(f(earRange.max() ?? 0)) rad")
    }
    func line2(_ key: String, _ value: String) { lines.append(line(key, value)) }
    return lines
  }
}
