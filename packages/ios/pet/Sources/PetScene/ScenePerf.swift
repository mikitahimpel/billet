import Foundation
import Pet

#if canImport(UIKit)
  import QuartzCore
  import UIKit
#endif

/// A measuring run of the scenes, set by `-perf.script <name>` and silent otherwise. Each result
/// is one line on standard error starting with `PERF`, read by `apps/ios/scripts/perf/measure.sh`.
@MainActor
public enum ScenePerf {
  public nonisolated static let script: String? = UserDefaults.standard.string(
    forKey: "perf.script")
  public nonisolated static var isOn: Bool { script != nil }
  /// The switches a `cost` run turns, or `nil` for all of them.
  nonisolated static let onlySwitches: Set<String>? = UserDefaults.standard.string(
    forKey: "perf.switches"
  ).map { Set($0.split(separator: ",").map(String.init)) }

  public struct Scene {
    public var name: String
    public var orbit: @MainActor (_ deltaX: Float, _ deltaY: Float) -> Void
    public var zoom: @MainActor (_ scale: Float) -> Void
    public var release: @MainActor () -> Void
    /// Entities, models, triangles, textures and lights, as `key=value` pairs.
    public var census: @MainActor () -> String
    /// Parts of the scene a `cost` run can switch off, and how to switch one off or back on.
    public var switches: [String]
    public var setSwitch: @MainActor (_ name: String, _ isOn: Bool) -> Void

    public init(
      name: String,
      orbit: @escaping @MainActor (_ deltaX: Float, _ deltaY: Float) -> Void,
      zoom: @escaping @MainActor (_ scale: Float) -> Void,
      release: @escaping @MainActor () -> Void,
      census: @escaping @MainActor () -> String,
      switches: [String] = [],
      setSwitch: @escaping @MainActor (_ name: String, _ isOn: Bool) -> Void = { _, _ in }
    ) {
      self.name = name
      self.orbit = orbit
      self.zoom = zoom
      self.release = release
      self.census = census
      self.switches = switches
      self.setSwitch = setSwitch
    }
  }

  public struct Host {
    public var selectTab: @MainActor (String) -> Void = { _ in }
    public var setLighting: @MainActor (RoomLighting) -> Void = { _ in }
    public var setWindowView: @MainActor (WindowViewChoice) -> Void = { _ in }
    public var cat: @MainActor () -> CatModel = { CatChoice.standard.model }
    public var setCat: @MainActor (CatModel) -> Void = { _ in }
    /// The lighting presets a run steps through; empty for an app whose rooms have none.
    public var lightings: [RoomLighting] = RoomLighting.allCases
    /// The cat models a `cats` step shows; empty for an app with one cat.
    public var cats: [CatModel] = ScenePerf.catModels
    /// Prefix of every screenshot's name, so the shots of two rooms never overwrite each other.
    public var shotPrefix = "windowSeat"
    /// Scrolls the tab on screen to `y` points from its top; a `full` run scrolls the Shop with it. An
    /// app that cannot leaves it doing nothing, and the run records a Shop held still.
    public var scroll: @MainActor (_ y: Double) -> Void = { _ in }
    /// Screens that cover the room whole, such as a full-screen canvas; a `full` run opens each and
    /// records the frames under it.
    public var covers: [String] = []
    public var setCover: @MainActor (_ name: String?) -> Void = { _ in }
    /// The rooms Home switches between, by the name each is marked on screen with, first the one on
    /// screen when asked; a `full` run goes to each and back, twice. Empty for an app with one room.
    public var rooms: @MainActor () -> [String] = { [] }
    public var selectRoom: @MainActor (_ name: String) -> Void = { _ in }
    public init() {}
  }

  public static var host = Host()
  /// The scene on screen now, set by the scene when it starts drawing.
  public static var scene: Scene?

  static var marks: [(name: String, at: Double)] = []
  private static var recorder: Recorder?

  /// Starts the frame recorder and the script. Call once, at launch.
  public static func start() {
    guard let script, recorder == nil else { return }
    let recorder = Recorder()
    self.recorder = recorder
    recorder.begin()
    Task { await run(script) }
  }

  public static func mark(_ name: String) {
    guard let recorder else { return }
    let at = recorder.sinceLaunch
    marks.append((name, at))
    emit("mark \(name.replacingOccurrences(of: " ", with: "_")) t=\(format(at))")
  }

  /// A moment inside a scene's own work, such as a room's textures being made: on the run's output
  /// as `mark trace.<name>`, but never one a script waits for.
  public static func trace(_ name: String) {
    guard let recorder else { return }
    let at = format(recorder.sinceLaunch)
    emit("mark trace.\(name.replacingOccurrences(of: " ", with: "_")) t=\(at)")
  }

  /// Counts one `name` in the phase being recorded, such as a room's step or a scene's update.
  /// Each count is reported a second, as `steps=` and `renders=` on the phase's line.
  public static func count(_ name: String) {
    recorder?.counts[name, default: 0] += 1
  }

  /// Where a scene starts drawing: it becomes the one a run drives, and its arrival is marked.
  public static func shown(_ scene: Scene) {
    guard isOn else { return }
    self.scene = scene
    mark("\(scene.name) on screen")
  }

  // MARK: - Script

  private static func run(_ script: String) async {
    guard await waitFor(suffix: "on screen", after: 0, timeout: 40) != nil else {
      emit("error no scene on screen")
      finish()
      return
    }
    // The room's opening: lights come up and the cat settles.
    await pause(4)
    census()
    await record("idle", seconds: 5)
    switch script {
    case "full":
      await full()
    case "sweep":
      await sweep()
    case "cats":
      await cats()
    case "views":
      await views()
    case "cost":
      await cost()
    case "steady":
      await pause(20)
      await record("steady", seconds: 60)
    default:
      break
    }
    finish()
  }

  private static func full() async {
    await orbit("orbit")
    await pause(1.5)
    await record("zoom", seconds: 6) { frame in
      scene?.zoom((frame / 60) % 2 == 0 ? 1.012 : 1 / 1.012)
    }
    scene?.release()
    await pause(1.5)
    census()
    for lighting in host.lightings.isEmpty ? [] : host.lightings + [RoomLighting.amberLantern] {
      host.setLighting(lighting)
      await record("light.\(lighting.rawValue)", seconds: 2)
    }
    for tab in ["shop", "notes", "us", "home", "shop", "notes", "us", "home"] {
      await timed("tab.\(tab)", until: tab == "home" ? "room on screen" : "\(tab) on screen") {
        host.selectTab(tab)
      }
      if tab != "home" { census() }
    }
    await scroll("shop")
    await scroll("notes")
    await scroll("us")
    await timed("tab.home.scroll", until: "room on screen") { host.selectTab("home") }
    await rooms()
    await covers()
    // Home again, long after launch and the switches, when nothing started earlier still runs:
    // what the room costs for good.
    await pause(20)
    await record("settled", seconds: 5)
    await orbit("settled.orbit")
    await cats()
  }

  /// A tab held still, then scrolled down its page and back up, again and again: the frames a
  /// thumb flicking through it gets. The pace is per frame, so a slow runner scrolls slower and two
  /// builds compare under the same drive.
  private static func scroll(_ tab: String) async {
    await timed("tab.\(tab).scroll", until: "\(tab) on screen") { host.selectTab(tab) }
    await pause(2)
    await record("\(tab).still", seconds: 3)
    await record("\(tab).scroll", seconds: 10) { frame in
      // 2 s down 2,400 pt and 2 s back up, at 60 frames a second.
      let t = Double(frame % 240) / 120
      host.scroll(t <= 1 ? t * 2400 : (2 - t) * 2400)
    }
    host.scroll(0)
  }

  /// Each other room and back to the first, twice: the first visit builds a room, the second shows
  /// what a switch costs once it has been made.
  private static func rooms() async {
    let rooms = host.rooms()
    guard let first = rooms.first else { return }
    for round in 1...2 {
      for name in rooms.dropFirst() + [first] {
        await pause(1.5)
        let label = name.replacingOccurrences(of: " ", with: "-")
        await timed("room.\(label).\(round)", until: "\(name) on screen") { host.selectRoom(name) }
      }
    }
  }

  /// Each cover over the room, held open, then closed again; with the room on screen underneath,
  /// what it still draws there shows in the cover's frames and CPU.
  private static func covers() async {
    for name in host.covers {
      host.setCover(name)
      await pause(2)
      await record("cover.\(name)", seconds: 5)
      host.setCover(nil)
      await pause(2)
    }
  }

  private static func orbit(_ name: String) async {
    await record(name, seconds: 6) { frame in
      let side: Float = (frame / 90) % 2 == 0 ? 7 : -7
      scene?.orbit(side, frame % 180 < 90 ? 0.6 : -0.6)
    }
    scene?.release()
  }

  /// Each switch of the scene off and on again, back to back so the two compare under the same load:
  /// the room held still, then orbiting, with the part and without it.
  private static func cost() async {
    guard let scene else { return }
    for name in scene.switches where onlySwitches?.contains(name) ?? true {
      // Which side goes first changes from launch to launch: a runner's load often climbs through a
      // launch, and the side always measured second would always look worse.
      for isOn in Bool.random() ? [true, false] : [false, true] {
        scene.setSwitch(name, isOn)
        await pause(1)
        let side = isOn ? "on" : "off"
        await record("cost.\(name).\(side).still", seconds: 3)
        await orbit("cost.\(name).\(side).orbit")
        await pause(0.5)
      }
      scene.setSwitch(name, true)
    }
  }

  /// Models a `cats` step switches through: four of different builds, so each is a model of its own.
  public nonisolated static let catModels: [CatModel] = [
    .detailedKitten, .mooCat, .britishGrey, .bengal,
  ]

  /// Shows four other cat models and then the first again, with the memory in use after each. What
  /// a model costs to hold shows as the rise after it; one let go when the next comes shows as
  /// memory that does not keep climbing, and coming back to the first as no rise at all.
  private static func cats() async {
    guard !host.cats.isEmpty else { return }
    let first = host.cat()
    for model in host.cats.filter({ $0 != first }) + [first] {
      host.setCat(model)
      await record("cat.\(model.rawValue)", seconds: 5)
      emit("timing cat.\(model.rawValue) mb=\(format(Recorder.footprint() / 1_048_576))")
    }
  }

  /// The room under each lighting preset, at the camera's extremes, held still for a screenshot.
  private static func sweep() async {
    for lighting in host.lightings {
      host.setLighting(lighting)
      await pause(2.5)
      await shot("\(host.shotPrefix)-\(lighting.rawValue)-home")
    }
    if host.lightings.isEmpty {
      await shot("\(host.shotPrefix)-home")
    } else {
      host.setLighting(.amberLantern)
      await pause(1.5)
    }
    let poses: [(String, Float, Float, Float)] = [
      ("left", 4000, 0, 1), ("right", -4000, 0, 1), ("high", 0, -4000, 1),
      ("low", 0, 4000, 1), ("near", 0, 0, 3), ("far", 0, 0, 0.3),
    ]
    for (name, x, y, scale) in poses {
      scene?.orbit(x, y)
      scene?.zoom(scale)
      await pause(1.2)
      await shot("\(host.shotPrefix)-\(name)")
      scene?.zoom(1 / scale)
      scene?.orbit(-x, -y)
      scene?.release()
      await pause(1)
    }
    for tab in ["shop", "notes"] {
      await timed("tab.\(tab)", until: "\(tab) on screen") { host.selectTab(tab) }
      await pause(3)
      await shot("\(host.shotPrefix)-tab-\(tab)")
    }
    host.selectTab("home")
  }

  /// Every window view at its own hour and weather from Home's resting camera, with what its frames
  /// cost, and back to the standard one.
  private static func views() async {
    for view in WindowView.allCases {
      host.setWindowView(WindowViewChoice(view: view))
      // Long enough for the view's plates to be painted and its lights to come on.
      await pause(3)
      await shot("view-\(view.rawValue)-home")
      await record("view.\(view.rawValue)", seconds: 3)
    }
    host.setWindowView(.standard)
  }

  // MARK: - Steps

  private static func pause(_ seconds: Double) async {
    try? await Task.sleep(for: .seconds(seconds))
  }

  /// Asks the measuring script for a screenshot, and holds still until it says it has one: the
  /// script writes `perf-shots/<name>` into the App Group, or 20 seconds pass.
  private static func shot(_ name: String) async {
    emit("shot \(name)")
    let done = FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: "group.com.mikitahimpel.billet")?
      .appending(path: "perf-shots/\(name)")
    // Generous: a busy CI runner can take most of a minute over one screenshot, and moving on
    // before it lands would photograph the next pose instead.
    let deadline = Date.now.addingTimeInterval(90)
    while Date.now < deadline {
      if let done, FileManager.default.fileExists(atPath: done.path) { return }
      await pause(0.1)
    }
    emit("error no screenshot of \(name)")
  }

  private static func census() {
    guard let scene else { return }
    emit("census scene=\(scene.name) \(scene.census())")
  }

  /// Runs `action`, then times how long until a mark ending in `suffix`, recording frames.
  private static func timed(_ name: String, until suffix: String, _ action: () -> Void) async {
    guard let recorder else { return }
    let start = recorder.sinceLaunch
    recorder.startPhase()
    action()
    let reached = await waitFor(suffix: suffix, after: start, timeout: 15)
    await pause(1.5)
    let frames = recorder.endPhase()
    let took = reached.map { format($0 - start) } ?? "timeout"
    // The memory in use once the switch has settled: what the screen left behind still holds.
    let mb = format(Recorder.footprint() / 1_048_576)
    emit("timing \(name) ms=\(took) mb=\(mb) \(frames)")
  }

  private static func record(
    _ name: String, seconds: Double, drive: (@MainActor (Int) -> Void)? = nil
  ) async {
    guard let recorder else { return }
    recorder.startPhase(drive: drive)
    await pause(seconds)
    emit("phase \(name) \(recorder.endPhase())")
  }

  private static func waitFor(suffix: String, after start: Double, timeout: Double) async
    -> Double?
  {
    let deadline = Date.now.addingTimeInterval(timeout)
    while Date.now < deadline {
      if let found = marks.first(where: { $0.at >= start && $0.name.hasSuffix(suffix) }) {
        return found.at
      }
      try? await Task.sleep(for: .milliseconds(5))
    }
    return nil
  }

  private static func finish() {
    guard let recorder else { return }
    emit("memory peakMB=\(format(recorder.peakFootprint / 1_048_576))")
    emit("done")
    exit(0)
  }

  nonisolated static func emit(_ line: String) {
    FileHandle.standardError.write(Data("PERF \(line)\n".utf8))
  }

  public nonisolated static func format(_ value: Double) -> String {
    String(format: "%.1f", value)
  }
}
