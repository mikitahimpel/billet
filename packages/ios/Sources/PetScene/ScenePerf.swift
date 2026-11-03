import Foundation
import Pet

#if canImport(UIKit)
  import QuartzCore
  import UIKit
#endif

/// A measuring run of the scenes, switched on by a launch argument and silent otherwise.
///
/// `-perf.script launch` measures a cold launch and the idle room, then quits. `-perf.script full`
/// also orbits, zooms, switches rooms, lighting and tabs, then idles and orbits again once settled. `-perf.script sweep` holds each camera
/// pose and lighting preset still and asks for a screenshot of it. Every result is one line on
/// standard error that starts with `PERF`, read by `apps/ios/scripts/perf/measure.sh`.
@MainActor
public enum ScenePerf {
  /// The script to run, or `nil` when the app runs as usual.
  public nonisolated static let script: String? = UserDefaults.standard.string(
    forKey: "perf.script")
  public nonisolated static var isOn: Bool { script != nil }

  /// What the shown room or tab scene lets a run do with it.
  public struct Scene {
    public var name: String
    public var orbit: @MainActor (_ deltaX: Float, _ deltaY: Float) -> Void
    public var zoom: @MainActor (_ scale: Float) -> Void
    public var release: @MainActor () -> Void
    /// Entities, models, triangles, textures and lights, as `key=value` pairs.
    public var census: @MainActor () -> String

    public init(
      name: String,
      orbit: @escaping @MainActor (_ deltaX: Float, _ deltaY: Float) -> Void,
      zoom: @escaping @MainActor (_ scale: Float) -> Void,
      release: @escaping @MainActor () -> Void,
      census: @escaping @MainActor () -> String
    ) {
      self.name = name
      self.orbit = orbit
      self.zoom = zoom
      self.release = release
      self.census = census
    }
  }

  /// What the app's shell lets a run change.
  public struct Host {
    public var selectTab: @MainActor (String) -> Void = { _ in }
    public var setLighting: @MainActor (RoomLighting) -> Void = { _ in }
    public init() {}
  }

  public static var host = Host()
  /// The scene on screen now, set by the scene when it starts drawing.
  public static var scene: Scene?

  private static var marks: [(name: String, at: Double)] = []
  private static var recorder: Recorder?

  /// Starts the frame recorder and the script. Call once, at launch.
  public static func start() {
    guard let script, recorder == nil else { return }
    let recorder = Recorder()
    self.recorder = recorder
    recorder.begin()
    Task { await run(script) }
  }

  /// A moment of a run, such as a room drawing its first frame.
  public static func mark(_ name: String) {
    guard let recorder else { return }
    let at = recorder.sinceLaunch
    marks.append((name, at))
    emit("mark \(name.replacingOccurrences(of: " ", with: "_")) t=\(format(at))")
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
    for lighting in RoomLighting.allCases + [RoomLighting.amberLantern] {
      host.setLighting(lighting)
      await record("light.\(lighting.rawValue)", seconds: 2)
    }
    for tab in ["shop", "notes", "home", "shop", "notes", "home"] {
      await timed("tab.\(tab)", until: tab == "home" ? "room on screen" : "\(tab) on screen") {
        host.selectTab(tab)
      }
      if tab != "home" { census() }
    }
    // Home again, long after launch and the switches, when nothing started earlier still runs:
    // what the room costs for good.
    await pause(20)
    await record("settled", seconds: 5)
    await orbit("settled.orbit")
  }

  private static func orbit(_ name: String) async {
    await record(name, seconds: 6) { frame in
      let side: Float = (frame / 90) % 2 == 0 ? 7 : -7
      scene?.orbit(side, frame % 180 < 90 ? 0.6 : -0.6)
    }
    scene?.release()
  }

  /// The room under each lighting preset, at the camera's extremes, held still for a screenshot.
  private static func sweep() async {
    for lighting in RoomLighting.allCases {
      host.setLighting(lighting)
      await pause(2.5)
      await shot("windowSeat-\(lighting.rawValue)-home")
    }
    host.setLighting(.amberLantern)
    await pause(1.5)
    let poses: [(String, Float, Float, Float)] = [
      ("left", 4000, 0, 1), ("right", -4000, 0, 1), ("high", 0, -4000, 1),
      ("low", 0, 4000, 1), ("near", 0, 0, 3), ("far", 0, 0, 0.3),
    ]
    for (name, x, y, scale) in poses {
      scene?.orbit(x, y)
      scene?.zoom(scale)
      await pause(1.2)
      await shot("windowSeat-\(name)")
      scene?.zoom(1 / scale)
      scene?.orbit(-x, -y)
      scene?.release()
      await pause(1)
    }
    for tab in ["shop", "notes"] {
      await timed("tab.\(tab)", until: "\(tab) on screen") { host.selectTab(tab) }
      await pause(3)
      await shot("tab-\(tab)")
    }
    host.selectTab("home")
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
    let deadline = Date.now.addingTimeInterval(20)
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
    emit("timing \(name) ms=\(took) \(frames)")
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

// MARK: - Recorder

extension ScenePerf {
  /// Frame intervals from the display, the main thread's and the process's CPU, and memory.
  @MainActor
  final class Recorder: NSObject {
    private let launchedAt: Double
    private var intervals: [Double] = []
    /// Each slow frame's length and how much of it the main thread was busy, in milliseconds.
    private var slow: [(length: Double, busy: Double)] = []
    private var lastFrame: Double?
    private var lastFrameCPU = 0.0
    private var frame = 0
    private var drive: (@MainActor (Int) -> Void)?
    private var mainCPUAtStart = 0.0
    private var processCPUAtStart = 0.0
    private var lastSample = 0.0
    private(set) var peakFootprint = 0.0
    #if canImport(UIKit)
      private var link: CADisplayLink?
    #endif

    override init() {
      launchedAt = Self.processStart()
      super.init()
    }

    /// Milliseconds since the process started.
    var sinceLaunch: Double { (Self.now() - launchedAt) * 1000 }

    func begin() {
      #if canImport(UIKit)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
      #endif
    }

    func startPhase(drive: (@MainActor (Int) -> Void)? = nil) {
      intervals.removeAll(keepingCapacity: true)
      slow.removeAll()
      lastFrame = nil
      frame = 0
      self.drive = drive
      mainCPUAtStart = Self.threadCPU()
      processCPUAtStart = Self.processCPU()
    }

    /// The phase's frames as `key=value` pairs, in milliseconds.
    func endPhase() -> String {
      drive = nil
      let count = max(intervals.count, 1)
      let main = (Self.threadCPU() - mainCPUAtStart) / Double(count)
      let process = (Self.processCPU() - processCPUAtStart) / Double(count)
      let sorted = intervals.sorted()
      func at(_ fraction: Double) -> String {
        guard !sorted.isEmpty else { return "nan" }
        return ScenePerf.format(sorted[min(Int(Double(sorted.count) * fraction), sorted.count - 1)])
      }
      let hitches = intervals.filter { $0 > 25 }.count
      let longest = sorted.last.map(ScenePerf.format) ?? "nan"
      let fps = intervals.isEmpty ? 0 : 1000 * Double(intervals.count) / intervals.reduce(0, +)
      // A slow frame the main thread spent busy is our own work; one it spent idle waited on the
      // renderer or on the rest of the machine.
      let slowLength = slow.reduce(0) { $0 + $1.length }
      let slowBusy = slow.reduce(0) { $0 + $1.busy }
      return
        "frames=\(intervals.count) fps=\(ScenePerf.format(fps)) p50=\(at(0.5)) p95=\(at(0.95)) "
        + "p99=\(at(0.99)) max=\(longest) hitches=\(hitches) "
        + "mainCPU=\(String(format: "%.2f", main)) procCPU=\(String(format: "%.2f", process)) "
        + "slow=\(slow.count) slowMs=\(ScenePerf.format(slowLength)) "
        + "slowBusyMs=\(ScenePerf.format(slowBusy))"
    }

    #if canImport(UIKit)
      @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if frame == 0, intervals.isEmpty, lastFrame == nil, ScenePerf.marks.isEmpty {
          ScenePerf.mark("first frame")
        }
        let cpu = Self.threadCPU()
        if let lastFrame {
          let length = (now - lastFrame) * 1000
          intervals.append(length)
          if length > Self.slowFrame { slow.append((length, cpu - lastFrameCPU)) }
        }
        lastFrame = now
        lastFrameCPU = cpu
        drive?(frame)
        frame += 1
        if now - lastSample > 0.5 {
          lastSample = now
          peakFootprint = max(peakFootprint, Self.footprint())
        }
      }
    #endif

    /// A frame this long, three refreshes at 60 Hz, counts as slow.
    private static let slowFrame = 50.0

    // MARK: Clocks

    private static func now() -> Double {
      var time = timespec()
      clock_gettime(CLOCK_REALTIME, &time)
      return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
    }

    private static func processStart() -> Double {
      var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
      var info = kinfo_proc()
      var size = MemoryLayout<kinfo_proc>.stride
      guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return now() }
      let started = info.kp_proc.p_starttime
      return Double(started.tv_sec) + Double(started.tv_usec) / 1e6
    }

    /// The calling thread's CPU time, in milliseconds.
    private static func threadCPU() -> Double {
      var info = thread_basic_info()
      var count = mach_msg_type_number_t(
        MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
      let port = mach_thread_self()
      defer { mach_port_deallocate(mach_task_self_, port) }
      _ = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
          thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
        }
      }
      let seconds = Double(info.user_time.seconds + info.system_time.seconds)
      let micros = Double(info.user_time.microseconds + info.system_time.microseconds)
      return seconds * 1000 + micros / 1000
    }

    /// The whole process's CPU time, in milliseconds.
    private static func processCPU() -> Double {
      var usage = rusage()
      getrusage(RUSAGE_SELF, &usage)
      let seconds = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
      let micros = Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec)
      return seconds * 1000 + micros / 1000
    }

    /// The memory the system charges the app for, in bytes.
    private static func footprint() -> Double {
      var info = task_vm_info_data_t()
      var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
      let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
          task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
      }
      return result == KERN_SUCCESS ? Double(info.phys_footprint) : 0
    }
  }
}
