import CoreGraphics
import Foundation
import simd

/// Searches the standing rig's postures for the one whose silhouette lies closest on the seated
/// splat's, seen from the side, front, back and the room camera's height: the pose to swap the two in.
struct SwapFit {
  /// A candidate: the standing body's posture, and how far both bodies lean forward about the floor.
  struct Candidate {
    static let names = [
      "lift", "back", "pitch", "bend", "foreUp", "foreBack", "hindUp", "hindBack", "tail0", "tail1", "tail2", "lean",
      "sway0", "sway1", "sway2",
    ]
    static let steps: [Float] = [0.01, 0.01, 0.15, 0.2, 0.01, 0.01, 0.01, 0.015, 0.3, 0.3, 0.3, 0.08, 0.4, 0.4, 0.4]
    var values: [Float]

    /// CatWalker.Posture.sit.
    static let sit = Candidate(values: [-0.005, -0.005, 0.5, -0.7, 0, 0, 0, -0.035, -0.8, -0.5, -0.4, 0, 0, 0, 0])
  }

  let stage: Stage
  let renderer: SplatRenderer
  let views: [Camera]

  init(stage: Stage, renderer: SplatRenderer) {
    self.stage = stage
    self.renderer = renderer
    let target = stage.group.position + [0, 0.1, 0]
    let facing = simd_quatf.y(stage.walker.heading)
    views = [[1, 0, 0], [0, 0, -1], [0, 0, 1], [1, 0.82, 1], [-1, 0.82, 1], [1, 0.82, -1]].map {
      Camera(target: target, from: facing.act($0), pixelsPerUnit: 1150)
    }
  }

  private func pose(_ c: Candidate) {
    let v = c.values
    let seated = stage.seated, standing = stage.standing
    let spine = seated.spineMid + seated.mount
    let lean = Pose.about([spine.x, 0, spine.z], .x(-v[11]))
    var p = standing.pose
    (p.lift, p.back, p.pitch, p.bend, p.headSeat) = (v[0], v[1], v[2], v[3], 1)
    p.chestMove = lean
    p.hipsMove = lean
    for (i, leg) in standing.legs.enumerated() {
      p.feet[i] = leg.paw + (leg.fore ? [0, v[4], v[5]] : [0, v[6], v[7]])
    }
    for i in p.tail.indices { p.tail[i] = .init(sway: v[12 + min(i, 2)], lift: v[8 + min(i, 2)], lean: 0) }
    standing.pose = p
    standing.update()
    var s = seated.pose
    let mount = seated.mount
    let local = Pose(q: lean.q, t: lean.t + lean.q.act(mount) - mount)
    s.chestMove = local
    s.hipsMove = local
    seated.pose = s
    seated.update()
  }

  private func masks(_ name: String) -> [[UInt8]] {
    guard let body = SplatLoader.drawn[name] else { return [] }
    let rig = name == "Mochi" ? stage.seated : stage.standing
    var toWorld = stage.modelToWorld
    if let at = rig.entity?.position { toWorld = toWorld * simd_float4x4(translation: at) }
    return views.map { view in
      _ = renderer.draw([(body, toWorld)], camera: view)
      return renderer.lastAlpha
    }
  }

  func loss(_ c: Candidate) -> Float {
    pose(c)
    let (a, b) = (masks("Mochi"), masks("MochiStanding"))
    let each = zip(a, b).map { Sample.change($0, $1) }
    return each.reduce(0, +) / Float(each.count)
  }

  /// Coordinate descent from `start`, halving the steps when no move helps.
  func search(from start: Candidate, holding held: Set<Int> = [], rounds: Int = 5) -> (Candidate, Float) {
    var best = start
    var least = loss(best)
    var steps = Candidate.steps
    print("start", least)
    for round in 0..<rounds {
      var improved = true
      while improved {
        improved = false
        for i in best.values.indices where !held.contains(i) {
          for sign in [Float(1), -1] {
            var next = best
            next.values[i] += sign * steps[i]
            let l = loss(next)
            if l < least - 1e-4 {
              (best, least, improved) = (next, l, true)
              break
            }
          }
        }
      }
      print("round \(round): \(least)", zip(Candidate.names, best.values).map { "\($0)=\(String(format: "%.3f", $1))" }.joined(separator: " "))
      steps = steps.map { $0 / 2 }
    }
    return (best, least)
  }

  /// The seated body and then each candidate's standing body, drawn from the side and from the room camera's side.
  func gallery(_ candidates: [Candidate], to url: URL) {
    let (w, h) = (renderer.width, renderer.height)
    let shots = [views[0], views[3]]
    let context = Picture.context(CGSize(width: w * (candidates.count + 1), height: h * shots.count))
    context.setFillColor(CGColor(red: 0.93, green: 0.9, blue: 0.85, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
    func draw(_ name: String, column: Int) {
      guard let body = SplatLoader.drawn[name] else { return }
      let rig = name == "Mochi" ? stage.seated : stage.standing
      var toWorld = stage.modelToWorld
      if let at = rig.entity?.position { toWorld = toWorld * simd_float4x4(translation: at) }
      for (row, view) in shots.enumerated() {
        if let image = renderer.draw([(body, toWorld)], camera: view) {
          context.draw(image, in: CGRect(x: column * w, y: (shots.count - 1 - row) * h, width: w, height: h))
        }
      }
    }
    pose(candidates.first ?? .sit)
    draw("Mochi", column: 0)
    for (i, candidate) in candidates.enumerated() {
      pose(candidate)
      draw("MochiStanding", column: i + 1)
      Picture.text(String(format: "%.3f", loss(candidate)), at: CGPoint(x: (i + 1) * w + 10, y: 10), in: context)
    }
    if let image = context.makeImage() { Picture.write(image, to: url) }
  }

  /// The two bodies over each other in each view, the seated one in red and the standing one in blue.
  func picture(_ c: Candidate, to url: URL) {
    pose(c)
    let (a, b) = (masks("Mochi"), masks("MochiStanding"))
    let (w, h) = (renderer.width, renderer.height)
    let context = Picture.context(CGSize(width: w * views.count, height: h))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: w * views.count, height: h))
    for v in views.indices {
      for y in 0..<h {
        for x in 0..<w {
          let (s, t) = (a[v][y * w + x] > 96, b[v][y * w + x] > 96)
          guard s || t else { continue }
          context.setFillColor(
            s && t ? CGColor(gray: 0.55, alpha: 1) : s ? CGColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
              : CGColor(red: 0.2, green: 0.3, blue: 0.9, alpha: 1))
          context.fill(CGRect(x: v * w + x, y: h - 1 - y, width: 1, height: 1))
        }
      }
    }
    if let image = context.makeImage() { Picture.write(image, to: url) }
  }
}

extension simd_float4x4 {
  init(translation t: SIMD3<Float>) {
    self = matrix_identity_float4x4
    columns.3 = SIMD4(t, 1)
  }
}
