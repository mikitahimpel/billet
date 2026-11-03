import Foundation
import Metal
import Pet
import RealityKit
import Testing
import simd

@testable import PetSceneReality

@Suite struct SplatCloudTests {
  /// A two-splat file packed the way `pack_splat.py` packs one.
  static func packed(joints: [String] = ["root", "root/spine_01"]) -> Data {
    var raw = Data("BSPL".utf8)
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { raw.append(contentsOf: $0) } }
    func f32(_ v: Float) {
      withUnsafeBytes(of: v.bitPattern.littleEndian) { raw.append(contentsOf: $0) }
    }
    u32(1)
    u32(2)
    u32(UInt32(joints.count))
    for v: Float in [0, 0, 0, 1, 2, 4, -6, -2] { f32(v) }
    for name in joints {
      let bytes = Data(name.utf8)
      withUnsafeBytes(of: UInt16(bytes.count).littleEndian) { raw.append(contentsOf: $0) }
      raw.append(bytes)
    }
    while raw.count % 4 != 0 { raw.append(0) }
    // Positions: the box's low corner, then its high corner.
    for v: UInt16 in [0, 0, 0, 65535, 65535, 65535] {
      withUnsafeBytes(of: v.littleEndian) { raw.append(contentsOf: $0) }
    }
    raw.append(contentsOf: [0, 0, 0, 255, 255, 255] as [UInt8])  // log scales: -6, then -2
    raw.append(contentsOf: [127, 0, 0, 0, 0, 0, 0, 127].map { UInt8(bitPattern: $0) })  // w=1; z=1
    raw.append(contentsOf: [128, 255] as [UInt8])  // opacity
    raw.append(contentsOf: [128, 128, 128, 255, 0, 255] as [UInt8])  // colour
    raw.append(contentsOf: [0, 0, 0, 0, 1, 0, 0, 0] as [UInt8])  // joints
    raw.append(contentsOf: [255, 0, 0, 0, 128, 128, 0, 0] as [UInt8])  // weights
    return (try? (raw as NSData).compressed(using: .zlib) as Data) ?? Data()
  }

  @Test func decodesAPackedFile() throws {
    let cloud = try SplatCloud.decode(Self.packed(), name: "test")
    #expect(cloud.count == 2)
    #expect(cloud.jointNames == ["root", "root/spine_01"])
    #expect(cloud.rest.count == 2 * SplatCloud.floatsPerSplat)
    let second = Array(cloud.rest[14..<28])
    #expect(abs(second[0] - 1) < 1e-4 && abs(second[1] - 2) < 1e-4 && abs(second[2] - 4) < 1e-4)
    #expect(abs(second[3] + 2) < 1e-4)
    #expect(abs(cloud.rest[3] + 6) < 1e-4)
    // Rotation w x y z: the second splat turns half a turn about z.
    #expect(abs(second[6]) < 1e-4 && abs(second[9] - 1) < 1e-4)
    // Opacity 255 decodes to a large logit, colour 0.5 to SH zero.
    #expect(second[10] > 5)
    #expect(abs(cloud.rest[11]) < 0.02)
    #expect(cloud.weights[0] == SIMD4(1, 0, 0, 0))
    #expect(abs(cloud.weights[1].x - 0.5) < 1e-4 && cloud.joints[1].y == 0)
  }

  @Test func rejectsATruncatedOrForeignFile() {
    #expect(throws: SplatLoadError.unreadable("x")) {
      try SplatCloud.decode(Data([1, 2, 3]), name: "x")
    }
    let raw = Data("NOPE".utf8)
    let packed = (try? (raw as NSData).compressed(using: .zlib) as Data) ?? Data()
    #expect(throws: SplatLoadError.unreadable("x")) { try SplatCloud.decode(packed, name: "x") }
  }

  @Test func jointsMatchTheSkeletonByTheirLastName() throws {
    let cloud = try SplatCloud.decode(Self.packed(), name: "test")
    #expect(cloud.jointMap(to: ["root/spine_01", "root"]) == [1, 0])
    #expect(cloud.jointMap(to: ["root"]) == nil)
  }

  @Test func skinningFollowsTheJoints() throws {
    let cloud = try SplatCloud.decode(Self.packed(), name: "test")
    let still = SplatSkinning.skin(cloud, poses: [.identity, .identity], map: [0, 1])
    for (a, b) in zip(still, cloud.rest) { #expect(abs(a - b) < 1e-5) }

    // The second joint moves up by 1 and turns a quarter about y; the second splat is half on it.
    let turn = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
    var moved = matrix_float4x4(turn)
    moved.columns.3 = [0, 1, 0, 1]
    let posed = SplatSkinning.skin(
      cloud, poses: [.identity, SplatJointPose(matrix: moved)], map: [0, 1])
    let p = SIMD4<Float>(1, 2, 4, 1)
    let expected = 0.5 * p + 0.5 * (moved * p)
    #expect(abs(posed[14] - expected.x) < 1e-4)
    #expect(abs(posed[15] - expected.y) < 1e-4)
    #expect(abs(posed[16] - expected.z) < 1e-4)
    // The first splat is wholly on the still root.
    #expect(Array(posed[0..<14]) == Array(cloud.rest[0..<14]))
  }

  @Test func posesChainFromTheRoot() {
    let up = Transform(translation: [0, 1, 0])
    let poses = SplatSkinning.poses(
      local: [up, up], parents: [nil, 0],
      inverseBind: [matrix_identity_float4x4, matrix_identity_float4x4])
    #expect(poses[1].matrix.columns.3 == SIMD4(0, 2, 0, 1))
  }

  /// Every splat body opens, and its joints are all in the skeleton of the mesh it falls back to.
  @Test @MainActor func everySplatCatFitsItsMeshSkeleton() async throws {
    for model in CatModel.allCases {
      guard let name = model.splatBody else { continue }
      let cloud = try SplatCloud.load(named: name, in: .module)
      #expect((65_536...262_144).contains(cloud.count), "\(model)")
      #expect(model.mesh.splatBody == nil, "\(model)")
      let cat = try #require(await NookiAssets.compiledCat(model.mesh))
      var skinned: ModelEntity?
      SceneParts.visit(cat) { node in
        if skinned == nil, let m = node as? ModelEntity, !m.jointNames.isEmpty { skinned = m }
      }
      let joints = try #require(skinned?.jointNames, "\(model)")
      let map = try #require(cloud.jointMap(to: joints), "\(model)")
      #expect(Set(map).count == cloud.jointNames.count)
      #expect(cloud.weights.allSatisfy { abs($0.sum() - 1) < 1e-3 })
    }
  }

  @Test func theKernelMatchesTheReference() throws {
    guard let device = MTLCreateSystemDefaultDevice() else { return }
    let cloud = try SplatCloud.decode(Self.packed(), name: "test")
    let turn = simd_quatf(angle: 0.7, axis: simd_normalize([1, 1, 0]))
    var moved = matrix_float4x4(turn)
    moved.columns.3 = [0.2, -0.1, 0.3, 1]
    let poses = [SplatJointPose.identity, SplatJointPose(matrix: moved)]
    let skinner = try #require(SplatSkinner(cloud: cloud, map: [0, 1], device: device))
    let out = try #require(
      device.makeBuffer(length: cloud.rest.count * 4, options: .storageModeShared))
    let commands = try #require(skinner.queue.makeCommandBuffer())
    skinner.encode(poses: poses, into: out, on: commands)
    commands.commit()
    commands.waitUntilCompleted()
    let gpu = Array(
      UnsafeBufferPointer(
        start: out.contents().bindMemory(to: Float.self, capacity: cloud.rest.count),
        count: cloud.rest.count))
    let cpu = SplatSkinning.skin(cloud, poses: poses, map: [0, 1])
    for (a, b) in zip(gpu, cpu) { #expect(abs(a - b) < 1e-4) }
  }
}
