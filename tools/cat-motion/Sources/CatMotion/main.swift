import CoreGraphics
import Foundation
import simd

// cat-motion <label> [scenario ...]
// Plays the scenarios on the app's own cat code and splats, and writes for each one a movie
// (room view left, side view right) and its samples under ~/Library/Caches/cat-motion/<label>/.

let arguments = Array(CommandLine.arguments.dropFirst())
guard let label = arguments.first else {
  print("usage: cat-motion <label> [scenario ...]\nscenarios: \(Scenario.all.map(\.name).joined(separator: " "))")
  exit(2)
}
let wanted = Set(arguments.dropFirst())
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appending(path: "apps/ios/Nooki/Resources")
let out = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Caches/cat-motion/\(label)")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let panel = CGSize(width: 480, height: 540)
let renderer = try SplatRenderer(width: Int(panel.width), height: Int(panel.height), splats: 140_000)
let dt: Float = 1 / 60
let roomDirection = SIMD3<Float>(1, 0.82, 1)
let sideZoom: Float = 1150

if label == "report" {
  // Works the numbers out again from the samples a run left.
  for name in arguments.dropFirst() {
    let folder = out.deletingLastPathComponent().appending(path: name)
    for scenario in Scenario.all {
      guard let data = try? Data(contentsOf: folder.appending(path: "\(scenario.name).json")) else { continue }
      let report = Metrics(samples: try JSONDecoder().decode([Sample].self, from: data), dt: 1 / 60).report(scenario.name)
      try report.write(to: folder.appending(path: "\(scenario.name).txt"), atomically: true, encoding: .utf8)
      print(report)
    }
  }
  exit(0)
}

if label == "poses" {
  // cat-motion poses "<15 numbers>" ...: each candidate's standing body beside the seated one.
  let stage = try Stage(resources: resources, at: .zero, yaw: 0, lyingBodies: false)
  let fit = SwapFit(stage: stage, renderer: renderer)
  let candidates = arguments.dropFirst().map { SwapFit.Candidate(values: $0.split(separator: " ").compactMap { Float($0) }) }
  fit.gallery(candidates, to: out.appending(path: "gallery.png"))
  exit(0)
}

if label == "fit" {
  let stage = try Stage(resources: resources, at: .zero, yaw: 0, lyingBodies: false)
  let fit = SwapFit(stage: stage, renderer: renderer)
  fit.picture(.sit, to: out.appending(path: "sit.png"))
  // cat-motion fit ["<15 numbers to start from>" [index of a value to hold ...]]
  var start = SwapFit.Candidate.sit
  if arguments.count > 1 { start.values = arguments[1].split(separator: " ").compactMap { Float($0) } }
  let held = Set(arguments.dropFirst(2).compactMap { Int($0) })
  let (best, least) = fit.search(from: start, holding: held)
  fit.picture(best, to: out.appending(path: "best.png"))
  print("best \(least):", zip(SwapFit.Candidate.names, best.values).map { "\($0)=\($1)" }.joined(separator: " "))
  exit(0)
}

func drawFloor(_ context: CGContext, camera: Camera, scenario: Scenario, floor: Float, side: Bool) {
  context.setFillColor(CGColor(red: 0.93, green: 0.9, blue: 0.85, alpha: 1))
  context.fill(CGRect(origin: .zero, size: panel))
  context.setLineWidth(1)
  let reach = 8
  for i in -reach...reach {
    let v = Float(i) * 0.1
    context.setStrokeColor(CGColor(gray: i == 0 ? 0.45 : 0.72, alpha: 1))
    if side {
      // Marks every 0.1 along the floor line, fixed in the room, to see a paw slide against.
      let a = camera.project([v, floor, 0], in: panel)
      context.move(to: a)
      context.addLine(to: CGPoint(x: a.x, y: a.y - 14))
    } else {
      context.move(to: camera.project([v, floor, -0.8], in: panel))
      context.addLine(to: camera.project([v, floor, 0.8], in: panel))
      context.move(to: camera.project([-0.8, floor, v], in: panel))
      context.addLine(to: camera.project([0.8, floor, v], in: panel))
    }
    context.strokePath()
  }
  if side {
    context.setStrokeColor(CGColor(gray: 0.45, alpha: 1))
    let y = camera.project([0, floor, 0], in: panel).y
    context.move(to: CGPoint(x: 0, y: y))
    context.addLine(to: CGPoint(x: panel.width, y: y))
    context.strokePath()
  }
  context.setStrokeColor(CGColor(red: 0.5, green: 0.38, blue: 0.3, alpha: 1))
  context.setLineWidth(2)
  for piece in side ? [] : scenario.layout?.footprints ?? [] {
    let corners: [SIMD2<Float>] = [[-1, -1], [1, -1], [1, 1], [-1, 1]].map { piece.center + $0 * piece.half }
    for y in [floor, floor + piece.height] {
      let ring = corners.map { camera.project([$0.x, y, $0.y], in: panel) }
      context.addLines(between: ring + [ring[0]])
    }
    for corner in corners {
      context.move(to: camera.project([corner.x, floor, corner.y], in: panel))
      context.addLine(to: camera.project([corner.x, floor + piece.height, corner.y], in: panel))
    }
    context.strokePath()
  }
  for box in scenario.boxes {
    let h = box.half
    let corners: [SIMD3<Float>] = [[-h, 0, -h], [h, 0, -h], [h, 0, h], [-h, 0, h]]
    let top = corners.map { camera.project(box.top + $0, in: panel) }
    context.addLines(between: top + [top[0]])
    for corner in corners {
      context.move(to: camera.project(box.top + corner, in: panel))
      context.addLine(to: camera.project([box.top.x + corner.x, floor, box.top.z + corner.z], in: panel))
    }
    context.strokePath()
  }
}

for scenario in Scenario.all where wanted.isEmpty || wanted.contains(scenario.name) {
  SplatLoader.drawn = [:]
  let stage = try Stage(
    resources: resources, at: scenario.home, yaw: scenario.yaw, lyingBodies: scenario.lyingBodies)
  let room = Camera(target: scenario.focus, from: roomDirection, pixelsPerUnit: scenario.zoom)
  stage.walker.watch(simd_quatf.y(-scenario.yaw).act(roomDirection * 3) / Stage.scale)
  let recorder = try Recorder(
    url: out.appending(path: "\(scenario.name).mp4"), size: CGSize(width: panel.width * 2, height: panel.height))
  let footprints = scenario.layout?.footprints ?? []
  stage.walker.avoid = scenario.layout?.occupancy()
  var samples: [Sample] = []
  var time: Float = 0
  var action = "sit"
  var lastMask: [UInt8] = []

  func frame() {
    stage.walker.update(dt)
    time += dt
    let at = stage.group.position
    let side = Camera(target: [at.x, at.y + 0.1, at.z], from: [0, 0, 1], pixelsPerUnit: sideZoom)
    let bodies = stage.shown
    // Dissolving, each body is a layer of its own, the opaque one under the other.
    let layers = zip(bodies, stage.opacities).sorted { $0.1 > $1.1 }
    let mixed = layers.contains { $0.1 < 1 }
    func picture(_ camera: Camera) -> [(CGImage, Float)] {
      if !mixed { return renderer.draw(bodies, camera: camera).map { [($0, Float(1))] } ?? [] }
      return layers.compactMap { layer in renderer.draw([layer.0], camera: camera).map { ($0, layer.1) } }
    }
    let sideImages = picture(side)
    let roomImages = picture(room)
    if mixed { _ = renderer.draw(bodies, camera: side) }
    let mask = renderer.lastAlpha
    var sample = Sample(time: time, action: action, stage: stage)
    sample.silhouetteChange = Sample.change(lastMask, mask)
    if at.y < stage.floor + 0.02 {
      for point in Stage.outline {
        let world = stage.modelToWorld * SIMD4(point.x, 0, point.y, 1)
        for piece in footprints where piece.depth(of: [world.x, world.z]) > sample.inside {
          sample.inside = piece.depth(of: [world.x, world.z])
          sample.insideOf = piece.item
        }
      }
    }
    lastMask = mask
    samples.append(sample)
    recorder.add { context in
      drawFloor(context, camera: room, scenario: scenario, floor: stage.floor, side: false)
      if let dot = stage.dot {
        let at = room.project(dot, in: panel)
        context.setFillColor(CGColor(red: 0.95, green: 0.1, blue: 0.1, alpha: 1))
        context.fillEllipse(in: CGRect(x: at.x - 5, y: at.y - 3, width: 10, height: 6))
        if let keepOut = stage.walker.keepOut {
          let c = room.project([keepOut.center.x, stage.floor, keepOut.center.y], in: panel)
          let r = CGFloat(keepOut.radius * 0.7 * scenario.zoom)
          context.setFillColor(CGColor(gray: 0.55, alpha: 0.6))
          context.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.55, width: 2 * r, height: 1.1 * r))
        }
      }
      for (image, opacity) in roomImages {
        context.setAlpha(CGFloat(opacity))
        context.draw(image, in: CGRect(origin: .zero, size: panel))
      }
      context.setAlpha(1)
      context.translateBy(x: panel.width, y: 0)
      drawFloor(context, camera: side, scenario: scenario, floor: at.y, side: true)
      for (image, opacity) in sideImages {
        context.setAlpha(CGFloat(opacity))
        context.draw(image, in: CGRect(origin: .zero, size: panel))
      }
      context.setAlpha(1)
      context.translateBy(x: -panel.width, y: 0)
      context.setFillColor(CGColor(gray: 0.3, alpha: 1))
      context.fill(CGRect(x: panel.width - 1, y: 0, width: 2, height: panel.height))
      Picture.text(
        "\(label)  \(scenario.name)  \(String(format: "%5.2f", time)) s  \(action)", at: CGPoint(x: 10, y: 516),
        in: context)
      Picture.text(
        "\(sample.shown)\(sample.moving ? "  moving" : "")", at: CGPoint(x: panel.width + 10, y: 516), in: context)
    }
  }

  for cue in scenario.cues {
    switch cue {
    case .act(let name, let run):
      action = name
      run(stage)
    case .wait(let seconds):
      for _ in 0..<Int((seconds / dt).rounded()) { frame() }
    case .each(let seconds, let run):
      for index in 0..<Int((seconds / dt).rounded()) {
        run(stage, Float(index) * dt)
        frame()
      }
    case .untilStill:
      var frames = 0
      while frames < 12 || stage.walker.moving, frames < 60 * 60 {
        frame()
        frames += 1
      }
      action = "rest"
    }
  }
  await recorder.finish()
  try JSONEncoder().encode(samples).write(to: out.appending(path: "\(scenario.name).json"))
  let report = Metrics(samples: samples, dt: dt).report(scenario.name)
  try report.write(to: out.appending(path: "\(scenario.name).txt"), atomically: true, encoding: .utf8)
  print(report)
}
