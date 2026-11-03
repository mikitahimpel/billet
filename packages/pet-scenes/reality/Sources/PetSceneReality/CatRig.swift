import CoreGraphics
import Foundation
import OSLog
import Pet
import RealityKit

/// A loaded cat: its clips trimmed from the one timeline, cross-faded on request, a head that can
/// turn towards a point, and a coat that can be repainted. Works for every model in the catalog.
@MainActor
final class CatRig {
  static let blend: TimeInterval = 0.35
  /// Into and out of sleep the body moves a long way, so it eases for longer.
  static let sleepBlend: TimeInterval = 0.7

  let entity: Entity
  let info: [CatAction: CatClipInfo]
  /// The body this rig moves, for where its mouth is.
  let anatomy: PetAnatomy
  private let player: Entity
  private let skinned: ModelEntity?
  private var clips: [CatAction: AnimationResource] = [:]
  private var controller: AnimationPlaybackController?
  /// The head joint and every joint above it, from the root down, for finding the mouth.
  private let headChain: [Int]
  /// Where the skeleton sits in the model, so joints chained from the root land on the mesh.
  private let skeletonPlace: simd_float4x4
  private(set) var current: CatAction?
  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "CatRig")

  /// How far a clip may run past the end of the compiled timeline. realitytool drops trailing
  /// samples that do not change, so a last clip that ends by holding its base pose comes out
  /// that much shorter than its table says (0.2 s for the made cats' reachUp).
  nonisolated static let droppedTail: TimeInterval = 0.5

  /// Whether a clip from the table is in the timeline: it starts inside it and ends no further
  /// past it than a dropped tail. Such a clip is trimmed at the timeline's end, where the pose it
  /// held is the one the timeline ends on.
  nonisolated static func fits(_ range: CatClipRange, timelineDuration duration: TimeInterval)
    -> Bool
  {
    range.trimStart < duration && range.trimEnd <= duration + droppedTail
  }

  /// Nil for a model with no timeline to trim.
  init?(
    model: Entity, clips table: [CatAction: CatClipRange],
    anatomy: PetAnatomy = CatChoice.standard.model.anatomy
  ) {
    guard let player = Self.firstAnimated(in: model),
      let timeline = player.availableAnimations.map(\.definition)
        .max(by: { $0.duration < $1.duration })
    else { return nil }
    entity = model
    self.anatomy = anatomy
    self.player = player
    var clips: [CatAction: AnimationResource] = [:]
    for (action, range) in table where Self.fits(range, timelineDuration: timeline.duration) {
      let view = AnimationView(
        source: timeline, name: action.rawValue, repeatMode: range.loops ? .repeat : .none,
        fillMode: .forwards, trimStart: range.trimStart,
        trimEnd: min(range.trimEnd, timeline.duration))
      clips[action] = try? AnimationResource.generate(with: view)
    }
    self.clips = clips
    info = CatCatalog.info(table.filter { clips[$0.key] != nil })
    guard clips[.sleep] != nil || clips[.idle] != nil else { return nil }
    skinned = Self.firstSkinned(in: model)
    let headChain = skinned.map { Self.chain(to: "head", in: $0.jointNames) } ?? []
    self.headChain = headChain
    skeletonPlace =
      skinned.map { Self.skeletonPlace(of: $0, chain: headChain) }
      ?? matrix_identity_float4x4
    if let skinned, let look = CatLookComponent(joints: skinned.jointNames) {
      CatLookSystem.registerOnce()
      skinned.components.set(look)
    }
    if let skinned, let reflex = CatReflexComponent(joints: skinned.jointNames) {
      CatReflexSystem.registerOnce()
      skinned.components.set(reflex)
    }
  }

  /// Moves to `action` at `rate`. Asking again for the action already playing only changes the
  /// rate. An action this cat lacks keeps whatever is playing.
  func play(_ action: CatAction, rate: Float = 1, blend: TimeInterval? = nil) {
    if action == current {
      controller?.speed = rate
      return
    }
    guard let resource = clips[action] else { return }
    let fade = blend ?? (action == .sleep || current == .sleep ? Self.sleepBlend : Self.blend)
    let wasPlaying = current != nil
    current = action
    let next = player.playAnimation(
      resource, transitionDuration: wasPlaying ? fade : 0, startsPaused: false)
    next.speed = rate
    controller = next
  }

  var isPlaying: Bool { controller?.isPlaying == true }

  /// How long the clip has been trimmed to, or infinity for one that repeats.
  func duration(of action: CatAction) -> TimeInterval? {
    clips[action]?.definition.duration
  }

  /// Points the head at `target`, in world space, as far as `weight` allows (0 lets the clip
  /// have the head). The turn eases in the look system, so this can be called every frame.
  func look(at target: SIMD3<Float>, weight: Float) {
    guard let skinned, var look = skinned.components[CatLookComponent.self] else { return }
    look.target = target
    look.weightGoal = weight
    skinned.components.set(look)
  }

  /// Lays small movements over the playing clip: how shut the eyes are, how far the right ear
  /// flicks and the tail tip swings (each 0 to 1, eased in the reflex system, so plain on and off
  /// is fine), where the breath is from 0 to 1, and how strong all of it is. Call every frame.
  func reflex(blink: Float, earTwitch: Float, tailFlick: Float, breath: Float, strength: Float = 1)
  {
    guard let skinned, var reflex = skinned.components[CatReflexComponent.self] else { return }
    reflex.blinkGoal = blink
    reflex.earGoal = earTwitch
    reflex.flickGoal = tailFlick
    reflex.breath = breath
    reflex.strength = strength
    skinned.components.set(reflex)
  }

  /// Whether this cat's skeleton has the joints the reflexes move.
  var hasReflexes: Bool { skinned?.components[CatReflexComponent.self] != nil }

  /// Puts `palette` on every surface painted from the model's palette, and says how many
  /// materials took it.
  @discardableResult
  func paint(_ palette: CGImage) -> Int {
    guard let texture = try? TextureResource(image: palette, options: .init(semantic: .color))
    else { return 0 }
    var painted = 0
    NookiDiorama.visit(entity) { node in
      guard var model = node.components[ModelComponent.self] else { return }
      var changed = false
      model.materials = model.materials.map { material in
        guard var physical = material as? PhysicallyBasedMaterial else { return material }
        physical.baseColor = .init(tint: physical.baseColor.tint, texture: .init(texture))
        changed = true
        painted += 1
        return physical
      }
      if changed { node.components.set(model) }
    }
    return painted
  }

  /// Where the mouth is now, in world space: a little in front of and below the head joint, as
  /// the clip has posed it. Nil for a model without a head joint.
  func mouth() -> SIMD3<Float>? {
    guard let skinned, !headChain.isEmpty else { return nil }
    let joints = skinned.jointTransforms
    guard headChain.allSatisfy(joints.indices.contains) else { return nil }
    var pose = skeletonPlace
    for index in headChain { pose = pose * joints[index].matrix }
    let head = skinned.convert(
      position: SIMD3(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z), to: nil)
    let forward = simd_normalize(entity.convert(direction: [0, 0, -1], to: nil))
    let size = entity.scale(relativeTo: nil).x
    return head + (forward * anatomy.mouth.x + [0, -anatomy.mouth.y, 0]) * size
  }

  /// The skeleton's own place in the model: the head's bind pose as the mesh has it, against the
  /// same pose chained from the root's rest transforms. Identity when the mesh does not say.
  private static func skeletonPlace(of model: ModelEntity, chain: [Int]) -> simd_float4x4 {
    guard let head = chain.last,
      let joints = model.model?.mesh.contents.skeletons.first?.joints,
      chain.allSatisfy(joints.indices.contains)
    else { return matrix_identity_float4x4 }
    var rest = matrix_identity_float4x4
    for index in chain { rest = rest * joints[index].restPoseTransform.matrix }
    let bound = joints[head].inverseBindPoseMatrix.inverse
    return bound * rest.inverse
  }

  /// Indices of the joint named `name` and all its ancestors, root first; empty if it has none.
  static func chain(to name: String, in joints: [String]) -> [Int] {
    guard
      let target = joints.firstIndex(where: {
        $0.split(separator: "/").last?.lowercased() == name
      })
    else { return [] }
    let path = joints[target]
    return joints.indices.filter { path.hasPrefix(joints[$0] + "/") || $0 == target }
      .sorted { joints[$0].count < joints[$1].count }
  }

  private static func firstAnimated(in entity: Entity) -> Entity? {
    if !entity.availableAnimations.isEmpty { return entity }
    return entity.children.lazy.compactMap(firstAnimated).first
  }

  static func firstSkinned(in entity: Entity) -> ModelEntity? {
    if let model = entity as? ModelEntity, !model.jointNames.isEmpty { return model }
    return entity.children.lazy.compactMap(firstSkinned).first
  }
}

/// Turns a skinned cat's neck and head towards a point after its clip has posed it. The clip
/// keeps the rest of the body; the turn is split between the neck and the head and clamped.
struct CatLookComponent: Component {
  /// Joint indices: every ancestor of the neck from the root, then the neck and the head.
  let chain: [Int]
  let neck: Int
  let head: Int
  var target: SIMD3<Float> = .zero
  var weightGoal: Float = 0
  var weight: Float = 0
  var yaw: Float = 0
  var pitch: Float = 0

  static let yawLimit: Float = 0.9
  static let pitchUp: Float = 0.45
  static let pitchDown: Float = -0.3
  static let rate: Float = 5
  static let neckShare: Float = 0.4

  /// Nil when the skeleton has no head joint. A model with a head but no neck turns the head.
  init?(joints: [String]) {
    func index(_ name: String) -> Int? {
      joints.firstIndex { $0.split(separator: "/").last?.lowercased() == name }
    }
    guard let head = index("head") else { return nil }
    let neck = index("neck") ?? head
    let neckPath = joints[neck]
    chain = joints.indices.filter { neckPath.hasPrefix(joints[$0] + "/") }
      .sorted { joints[$0].count < joints[$1].count }
    self.neck = neck
    self.head = head
  }
}

struct CatLookSystem: System {
  static let query = EntityQuery(where: .has(CatLookComponent.self))
  @MainActor private static var isRegistered = false

  init(scene: RealityKit.Scene) {}

  @MainActor static func registerOnce() {
    guard !isRegistered else { return }
    isRegistered = true
    CatLookComponent.registerComponent()
    registerSystem()
  }

  func update(context: SceneUpdateContext) {
    let delta = Float(min(context.deltaTime, 0.1))
    for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
      guard let model = entity as? ModelEntity, var look = model.components[CatLookComponent.self]
      else { continue }
      Self.step(&look, model: model, delta: delta)
      model.components.set(look)
    }
  }

  @MainActor static func step(_ look: inout CatLookComponent, model: ModelEntity, delta: Float) {
    let ease = 1 - exp(-CatLookComponent.rate * delta)
    look.weight += (look.weightGoal - look.weight) * ease
    var joints = model.jointTransforms
    guard joints.indices.contains(look.neck), joints.indices.contains(look.head) else { return }
    // The neck's place and its parent's turn, in the skeleton's space, from the posed joints.
    var parent = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    var place = SIMD3<Float>.zero
    for index in look.chain {
      place += parent.act(joints[index].translation)
      parent = parent * joints[index].rotation
    }
    place += parent.act(joints[look.neck].translation)
    let towards = model.convert(position: look.target, from: nil) - place
    let flat = simd_length(SIMD2(towards.x, towards.z))
    var yawGoal = atan2(-towards.x, -towards.z)
    var pitchGoal = atan2(towards.y, flat)
    // Behind the cat it would have to spin: it looks ahead instead.
    if abs(yawGoal) > 2.2 {
      yawGoal = 0
      pitchGoal = 0
    }
    yawGoal = min(max(yawGoal, -CatLookComponent.yawLimit), CatLookComponent.yawLimit)
    pitchGoal = min(max(pitchGoal, CatLookComponent.pitchDown), CatLookComponent.pitchUp)
    look.yaw += (yawGoal - look.yaw) * ease
    look.pitch += (pitchGoal - look.pitch) * ease
    guard look.weight > 0.002 else { return }

    func turn(_ share: Float) -> simd_quatf {
      simd_quatf(angle: look.yaw * look.weight * share, axis: [0, 1, 0])
        * simd_quatf(angle: look.pitch * look.weight * share, axis: [1, 0, 0])
    }
    let neckShare = look.neck == look.head ? 0 : CatLookComponent.neckShare
    if look.neck != look.head {
      joints[look.neck].rotation =
        parent.inverse * turn(neckShare) * parent * joints[look.neck].rotation
    }
    let headParent = look.neck == look.head ? parent : parent * joints[look.neck].rotation
    joints[look.head].rotation =
      headParent.inverse * turn(1 - neckShare) * headParent * joints[look.head].rotation
    model.jointTransforms = joints
  }
}
