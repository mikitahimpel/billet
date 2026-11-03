import Foundation
import Metal
import OSLog
import Pet
import RealityKit

/// Shows a cat as a Gaussian splat where RealityKit can draw splats, moved by the cat's own skeleton.
///
/// The loaded cat stays as it is: its rig plays every clip and the rooms drive it as usual. The
/// splat body is added beside the skinned mesh, which turns invisible, and every frame the mesh's
/// joint poses skin the splats on the GPU (`SplatSkinning`). Where splats can't be drawn (an SDK
/// before iOS 27's, an older system, or a GPU before Apple7) nothing changes and the mesh shows.
enum SplatCat {
  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "SplatCat")

  /// Whether this build and device can draw splats.
  static var isAvailable: Bool {
    #if compiler(>=6.4)
      if #available(iOS 27, macOS 27, *) {
        return MTLCreateSystemDefaultDevice()?.supportsFamily(.apple7) ?? false
      }
    #endif
    return false
  }

  /// Gives `cat` its splat body, if the model has one and splats can be drawn. Returns whether it did.
  @MainActor @discardableResult
  static func dress(_ cat: Entity, as model: CatModel) -> Bool {
    guard let name = model.splatBody, isAvailable else { return false }
    #if compiler(>=6.4)
      if #available(iOS 27, macOS 27, *) {
        do throws(SplatLoadError) {
          let cloud = try SplatCloud.load(named: name, in: .module)
          return SplatCatBody.attach(cloud, to: cat)
        } catch {
          log.error("\(name, privacy: .public): \(String(describing: error), privacy: .public)")
        }
      }
    #endif
    return false
  }
}

#if compiler(>=6.4)
  /// The splat body of one cat: the skinned mesh it follows and the GPU state that poses it.
  @available(iOS 27, macOS 27, *)
  struct SplatCatBody: Component {
    weak var skinned: ModelEntity?
    let skinner: SplatSkinner
    let buffer: LowLevelBuffer
    let parents: [Int?]
    let inverseBind: [simd_float4x4]

    /// Builds the splat entity beside the cat's skinned mesh and hides the mesh. False when the cat
    /// has no skinned mesh or the splat's joints are not in its skeleton.
    @MainActor
    static func attach(_ cloud: SplatCloud, to cat: Entity) -> Bool {
      guard let skinned = firstSkinned(in: cat), let parent = skinned.parent,
        let skeleton = skinned.model?.mesh.contents.skeletons.first,
        let map = cloud.jointMap(to: skinned.jointNames),
        let skinner = SplatSkinner(cloud: cloud, map: map)
      else { return false }
      let floats = SplatCloud.floatsPerSplat
      let stride = floats * MemoryLayout<Float>.stride
      let bytes = cloud.count * stride
      guard
        let buffer = try? LowLevelBuffer(
          descriptor: .init(capacity: (bytes + 15) & ~0xF, sizeMultiple: 16))
      else { return false }
      buffer.withUnsafeMutableBytes { target in
        cloud.rest.withUnsafeBytes { target.copyMemory(from: $0) }
      }
      func field(_ format: MTLAttributeFormat, at index: Int)
        -> GaussianSplatResource.BufferDescriptor
      {
        .init(
          buffer: buffer, format: format, stride: stride, offset: index * MemoryLayout<Float>.stride
        )
      }
      guard
        let splats = try? GaussianSplatResource.BufferResource(
          count: cloud.count,
          position: field(.float3, at: 0),
          scale: field(.float3, at: 3),
          rotation: field(.float4, at: 6),
          opacity: field(.float, at: 10),
          sphericalHarmonics: (field(.float3, at: 11), .zero))
      else { return false }
      let resource = GaussianSplatResource(splats)
      resource.scaleActivation = .exponential
      resource.opacityActivation = .sigmoid

      let body = Entity()
      body.name = "SplatBody"
      body.transform = skinned.transform
      body.components.set(GaussianSplatComponent(resource))
      body.components.set(
        SplatCatBody(
          skinned: skinned, skinner: skinner, buffer: buffer,
          parents: skeleton.joints.map(\.parentIndex),
          inverseBind: skeleton.joints.map(\.inverseBindPoseMatrix)))
      parent.addChild(body)
      // The mesh keeps animating, so its joints still pose the splats, but no longer draws.
      skinned.components.set(OpacityComponent(opacity: 0))
      SplatCatSystem.registerOnce()
      return true
    }

    @MainActor
    private static func firstSkinned(in entity: Entity) -> ModelEntity? {
      if let model = entity as? ModelEntity, !model.jointNames.isEmpty { return model }
      for child in entity.children {
        if let found = firstSkinned(in: child) { return found }
      }
      return nil
    }
  }

  /// Poses every splat body from its skinned mesh, once a frame.
  @available(iOS 27, macOS 27, *)
  struct SplatCatSystem: System {
    static let query = EntityQuery(where: .has(SplatCatBody.self))
    @MainActor private static var isRegistered = false

    init(scene: RealityKit.Scene) {}

    @MainActor static func registerOnce() {
      guard !isRegistered else { return }
      isRegistered = true
      registerSystem()
    }

    func update(context: SceneUpdateContext) {
      for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
        guard let body = entity.components[SplatCatBody.self], let skinned = body.skinned else {
          continue
        }
        entity.transform = skinned.transform
        let poses = SplatSkinning.poses(
          local: skinned.jointTransforms, parents: body.parents, inverseBind: body.inverseBind)
        guard let commands = body.skinner.queue.makeCommandBuffer() else { continue }
        let target = body.buffer.replace(using: commands)
        body.skinner.encode(poses: poses, into: target, on: commands)
        commands.commit()
      }
    }
  }
#endif
