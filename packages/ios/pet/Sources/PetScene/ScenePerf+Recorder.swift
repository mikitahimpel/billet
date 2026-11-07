import Foundation
import Pet

#if canImport(UIKit)
  import QuartzCore
  import UIKit
#endif

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
    var counts: [String: Int] = [:]
    private var phaseStart = 0.0
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
      counts.removeAll()
      phaseStart = Self.now()
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
      // The whole process's CPU over the phase's wall time, in milliseconds a second: how much a
      // phone spends on the app, the nearest a Simulator comes to its energy.
      let seconds = max(Self.now() - phaseStart, 0.001)
      let cpuPerSecond = (Self.processCPU() - processCPUAtStart) / seconds
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
        + "slowBusyMs=\(ScenePerf.format(slowBusy)) cpuMsPerS=\(ScenePerf.format(cpuPerSecond)) "
        + "steps=\(perSecond("steps")) renders=\(perSecond("renders"))"
    }

    /// How many of `name` were counted a second in the phase.
    private func perSecond(_ name: String) -> String {
      let seconds = max(Self.now() - phaseStart, 0.001)
      return ScenePerf.format(Double(counts[name] ?? 0) / seconds)
    }

    #if canImport(UIKit)
      @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if frame == 0, intervals.isEmpty, lastFrame == nil,
          !ScenePerf.marks.contains(where: { $0.name == "first frame" })
        {
          ScenePerf.mark("first frame")
        }
        let cpu = Self.threadCPU()
        if let lastFrame {
          let length = (now - lastFrame) * 1000
          intervals.append(length)
          if length > Self.slowFrame { slow.append((length, cpu - lastFrameCPU)) }
          // A frame of half a second or more, where in the phase it fell and how much of it the main thread worked.
          if length > 500 {
            ScenePerf.emit(
              "frame long ms=\(ScenePerf.format(length)) at=\(frame)"
                + " busyMs=\(ScenePerf.format((cpu - lastFrameCPU) * 1000))")
          }
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
    static func footprint() -> Double {
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
