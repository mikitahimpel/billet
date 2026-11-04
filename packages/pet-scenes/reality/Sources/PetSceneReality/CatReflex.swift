import Foundation
import PetScene
import RealityKit

/// Small movements laid over whatever clip is playing, after it has posed the cat: a blink, an
/// ear flick, a flick of the tail tip and a breath. A clip used to have to cut in for each of
/// these; now they can come in the middle of any clip.
///
/// Each frame the rig is told how much of each to show, from 0 to 1, and eases there, so a
/// switch that is just on or off still opens and closes the eye smoothly.
struct CatReflexComponent: Component {
  /// Joint indices; empty or nil where the skeleton lacks them.
  let eyes: [Int]
  /// The right ear first: an ear flick is the right ear's, as in the clips.
  let ears: [Int]
  /// The outer tail joints, from the middle of the tail to its tip.
  let tail: [Int]
  let chest: Int?
  /// For each ear and tail joint, its ancestors from the root, for turning it about the
  /// skeleton's own axes.
  let ancestors: [Int: [Int]]

  var blinkGoal: Float = 0
  var earGoal: Float = 0
  var flickGoal: Float = 0
  var breath: Float = 0
  /// 0 until the rig is first told to show reflexes, so a cat nobody drives costs nothing.
  var strength: Float = 0

  var blink: Float = 0
  var ear: Float = 0
  var flick: Float = 0
  /// Runs while the tail is flicking, so the tip swings out and back.
  var flickClock: Float = 0
  /// The clip's pose of the joints last moved, and what was written over it: when no clip has
  /// re-posed them since, the reflexes start again from the clip's pose instead of piling up.
  var clipPose: [Int: Transform] = [:]
  var written: [Int: Transform] = [:]

  /// How fast each eases towards its goal, per second: a blink shuts in a few frames.
  static let blinkRate: Float = 28
  static let earRate: Float = 16
  static let flickRate: Float = 9
  /// The most each moves at full strength.
  static let earAngle: Float = 0.32
  static let flickAngle: Float = 0.35
  static let flickSwings: Float = 1.7
  /// How much the chest swells at the top of a breath. Small: it runs on top of clips that
  /// already breathe, asleep too.
  static let breathSwell: Float = 0.012
  /// A shut eye is squashed to this much of its height, as in the clips.
  static let shut: Float = 0.07

  init?(joints: [String]) {
    func name(_ index: Int) -> String {
      joints[index].split(separator: "/").last.map { $0.lowercased() } ?? ""
    }
    func index(_ wanted: String) -> Int? { joints.indices.first { name($0) == wanted } }
    eyes = ["eye_r", "eye_l"].compactMap(index)
    ears = ["ear_r", "ear_l"].compactMap(index)
    tail = ["tail_03", "tail_04", "tail_05"].compactMap(index)
    chest = index("spine_02")
    guard !eyes.isEmpty || !ears.isEmpty || !tail.isEmpty else { return nil }
    var ancestors: [Int: [Int]] = [:]
    for joint in ears + tail {
      let path = joints[joint]
      ancestors[joint] = joints.indices.filter { path.hasPrefix(joints[$0] + "/") }
        .sorted { joints[$0].count < joints[$1].count }
    }
    self.ancestors = ancestors
  }
}

struct CatReflexSystem: System {
  static let query = EntityQuery(where: .has(CatReflexComponent.self))
  @MainActor private static var isRegistered = false

  init(scene: RealityKit.Scene) {}

  @MainActor static func registerOnce() {
    guard !isRegistered else { return }
    isRegistered = true
    CatReflexComponent.registerComponent()
    registerSystem()
  }

  func update(context: SceneUpdateContext) {
    let start = DispatchTime.now().uptimeNanoseconds
    defer { MainActor.assumeIsolated { ScenePerf.spend("system.reflex", since: start) } }
    let delta = Float(min(context.deltaTime, 0.1))
    for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
      guard let model = entity as? ModelEntity,
        var reflex = model.components[CatReflexComponent.self]
      else { continue }
      Self.ease(&reflex, delta: delta)
      Self.apply(&reflex, to: model)
      model.components.set(reflex)
    }
  }

  static func ease(_ r: inout CatReflexComponent, delta: Float) {
    func toward(_ value: inout Float, _ goal: Float, _ rate: Float) {
      value += (goal - value) * (1 - exp(-rate * delta))
    }
    toward(&r.blink, r.blinkGoal, CatReflexComponent.blinkRate)
    toward(&r.ear, r.earGoal, CatReflexComponent.earRate)
    toward(&r.flick, r.flickGoal, CatReflexComponent.flickRate)
    r.flickClock = r.flick > 0.01 ? r.flickClock + delta : 0
  }

  /// The eye squashed shut by `blink`, the chest swollen by `breath`: scales on the clip's own.
  static func eyeScale(blink: Float) -> Float {
    1 - (1 - CatReflexComponent.shut) * min(max(blink, 0), 1)
  }

  static func chestSwell(breath: Float, strength: Float) -> Float {
    let swell = 0.5 - 0.5 * cos(2 * Float.pi * breath)
    return 1 + CatReflexComponent.breathSwell * swell * strength
  }

  /// The tail tip's swing at `clock` seconds into a flick: out and back, easing off.
  static func flickSwing(clock: Float) -> Float {
    sin(2 * Float.pi * CatReflexComponent.flickSwings * clock) * exp(-1.2 * clock)
  }

  @MainActor static func apply(_ r: inout CatReflexComponent, to model: ModelEntity) {
    let k = r.strength
    let blink = r.blink * k
    let ear = r.ear * k
    let flick = r.flick * k
    let breathing = r.chest != nil && k > 0
    var joints = model.jointTransforms
    for (joint, mine) in r.written where joints.indices.contains(joint) && joints[joint] == mine {
      joints[joint] = r.clipPose[joint] ?? mine
    }
    r.written = [:]
    r.clipPose = [:]
    guard blink > 0.002 || ear > 0.002 || flick > 0.002 || breathing else {
      model.jointTransforms = joints
      return
    }
    let touched = r.eyes + r.ears + r.tail + (r.chest.map { [$0] } ?? [])
    for joint in touched where joints.indices.contains(joint) { r.clipPose[joint] = joints[joint] }

    if blink > 0.002 {
      let squash = eyeScale(blink: blink)
      for eye in r.eyes where joints.indices.contains(eye) {
        let shut = 1 - squash
        joints[eye].scale *= [1 - 0.04 * shut, 1 - 0.15 * shut, squash]
      }
    }
    if let chest = r.chest, joints.indices.contains(chest), breathing {
      let swell = chestSwell(breath: r.breath, strength: k)
      joints[chest].scale *= [swell, 1, 1 + (swell - 1) * 0.85]
    }

    /// Turns a joint by `turn`, given about the skeleton's own axes, on top of its clip pose.
    func turnJoint(_ joint: Int, by turn: simd_quatf) {
      guard joints.indices.contains(joint), let chain = r.ancestors[joint] else { return }
      var parent = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
      for index in chain where joints.indices.contains(index) {
        parent = parent * joints[index].rotation
      }
      joints[joint].rotation = parent.inverse * turn * parent * joints[joint].rotation
    }
    if ear > 0.002, let right = r.ears.first {
      // Forward and out, as the clips' twitch: about the cat's side-to-side axis.
      turnJoint(right, by: simd_quatf(angle: -CatReflexComponent.earAngle * ear, axis: [1, 0, 0]))
    }
    if flick > 0.002 {
      let swing = flickSwing(clock: r.flickClock) * CatReflexComponent.flickAngle * flick
      for (i, joint) in r.tail.enumerated() {
        let share = Float(i + 1) / Float(r.tail.count)
        turnJoint(joint, by: simd_quatf(angle: swing * share, axis: [0, 1, 0]))
      }
    }
    for joint in touched where joints.indices.contains(joint) { r.written[joint] = joints[joint] }
    model.jointTransforms = joints
  }
}
