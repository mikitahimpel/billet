import Foundation
import Metal
import RealityKit
import simd

/// One joint's motion for this frame: bind-pose mesh space to posed mesh space, and the same
/// rotation as a quaternion for turning each splat's orientation.
struct SplatJointPose: Equatable {
  var matrix: simd_float4x4
  var rotation: simd_quatf

  static let identity = SplatJointPose(
    matrix: matrix_identity_float4x4, rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))

  init(matrix: simd_float4x4, rotation: simd_quatf) {
    self.matrix = matrix
    self.rotation = rotation
  }

  init(matrix: simd_float4x4) {
    self.matrix = matrix
    let basis = simd_float3x3(
      simd_normalize(SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)),
      simd_normalize(SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z)),
      simd_normalize(SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)))
    rotation = simd_quatf(basis)
  }
}

/// Moves a splat body with a skeleton, the way a skinned mesh moves: each splat's centre is the
/// weighted blend of its joints' motions (linear blend skinning), and its orientation turns by the
/// weighted blend of their rotations. Sizes and colours stay as they are.
enum SplatSkinning {
  /// Skinning matrices for a skinned model's current pose, in the order of its skeleton's joints:
  /// each joint's model-space pose times its inverse bind pose, chained from the root through
  /// `jointTransforms`, which hold each joint relative to its parent.
  static func poses(
    local: [Transform], parents: [Int?], inverseBind: [simd_float4x4]
  ) -> [SplatJointPose] {
    var global = [simd_float4x4](repeating: matrix_identity_float4x4, count: local.count)
    var poses: [SplatJointPose] = []
    poses.reserveCapacity(local.count)
    for i in local.indices {
      let own = local[i].matrix
      global[i] = parents[i].map { global[$0] * own } ?? own
      let bind = i < inverseBind.count ? inverseBind[i] : matrix_identity_float4x4
      poses.append(SplatJointPose(matrix: global[i] * bind))
    }
    return poses
  }

  /// The posed splats on the CPU: what the GPU kernel computes, for tests and for checking it.
  static func skin(_ cloud: SplatCloud, poses: [SplatJointPose], map: [Int]) -> [Float] {
    var out = cloud.rest
    let n = SplatCloud.floatsPerSplat
    for i in 0..<cloud.count {
      let o = i * n
      let p = SIMD4(cloud.rest[o], cloud.rest[o + 1], cloud.rest[o + 2], 1)
      var moved = SIMD4<Float>.zero
      var turn = SIMD4<Float>.zero
      let first = poses[map[Int(cloud.joints[i][0])]].rotation.vector
      for k in 0..<4 {
        let w = cloud.weights[i][k]
        guard w > 0 else { continue }
        let pose = poses[map[Int(cloud.joints[i][k])]]
        moved += w * (pose.matrix * p)
        let q = pose.rotation.vector
        turn += w * (simd_dot(q, first) < 0 ? -q : q)
      }
      let blended = simd_quatf(vector: simd_length(turn) > 0 ? simd_normalize(turn) : first)
      // The file stores w x y z; simd_quatf's vector is x y z w.
      let own = simd_quatf(
        ix: cloud.rest[o + 7], iy: cloud.rest[o + 8], iz: cloud.rest[o + 9], r: cloud.rest[o + 6])
      let turned = blended * own
      out[o] = moved.x
      out[o + 1] = moved.y
      out[o + 2] = moved.z
      out[o + 6] = turned.real
      out[o + 7] = turned.imag.x
      out[o + 8] = turned.imag.y
      out[o + 9] = turned.imag.z
    }
    return out
  }

  /// The kernel, compiled at first use: one thread a splat, reading the rest layout and writing the
  /// same 14-float layout with the centre and orientation posed.
  static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Joint { float4x4 matrix; float4 rotation; };

    static float4 qmul(float4 a, float4 b) {
      return float4(a.w * b.xyz + b.w * a.xyz + cross(a.xyz, b.xyz), a.w * b.w - dot(a.xyz, b.xyz));
    }

    kernel void skinSplats(device const float *rest [[buffer(0)]],
                           device const uchar4 *joints [[buffer(1)]],
                           device const float4 *weights [[buffer(2)]],
                           device const Joint *poses [[buffer(3)]],
                           device float *out [[buffer(4)]],
                           constant uint &count [[buffer(5)]],
                           uint i [[thread_position_in_grid]]) {
      if (i >= count) return;
      uint o = i * 14;
      float4 p = float4(rest[o], rest[o + 1], rest[o + 2], 1);
      uchar4 j = joints[i];
      float4 w = weights[i];
      float4 first = poses[j.x].rotation;
      float4 moved = 0;
      float4 turn = 0;
      for (uint k = 0; k < 4; k++) {
        if (w[k] <= 0) continue;
        Joint pose = poses[j[k]];
        moved += w[k] * (pose.matrix * p);
        float4 q = pose.rotation;
        turn += w[k] * (dot(q, first) < 0 ? -q : q);
      }
      float4 blended = length(turn) > 0 ? normalize(turn) : first;
      // rest holds w x y z; the maths here keeps x y z w.
      float4 own = float4(rest[o + 7], rest[o + 8], rest[o + 9], rest[o + 6]);
      float4 turned = qmul(blended, own);
      out[o] = moved.x; out[o + 1] = moved.y; out[o + 2] = moved.z;
      for (uint c = 3; c < 6; c++) out[o + c] = rest[o + c];
      out[o + 6] = turned.w; out[o + 7] = turned.x; out[o + 8] = turned.y; out[o + 9] = turned.z;
      for (uint c = 10; c < 14; c++) out[o + c] = rest[o + c];
    }
    """
}

/// The GPU side of `SplatSkinning`: the rest splats, their joints and weights live in buffers, and
/// each frame `encode` writes the posed splats into a destination buffer.
final class SplatSkinner {
  struct GPUJoint {
    var matrix: simd_float4x4
    var rotation: SIMD4<Float>
  }

  let count: Int
  let device: MTLDevice
  let queue: MTLCommandQueue
  private let pipeline: MTLComputePipelineState
  private let rest: MTLBuffer
  private let joints: MTLBuffer
  private let weights: MTLBuffer
  private let poses: MTLBuffer
  /// The splat's joints as indices into the skeleton the poses come from.
  private let map: [Int]

  init?(cloud: SplatCloud, map: [Int], device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
    guard let device, let queue = device.makeCommandQueue(),
      let library = try? device.makeLibrary(source: SplatSkinning.source, options: nil),
      let function = library.makeFunction(name: "skinSplats"),
      let pipeline = try? device.makeComputePipelineState(function: function),
      let rest = device.makeBuffer(
        bytes: cloud.rest, length: cloud.rest.count * MemoryLayout<Float>.stride),
      let joints = device.makeBuffer(
        bytes: cloud.joints, length: cloud.count * MemoryLayout<SIMD4<UInt8>>.stride),
      let weights = device.makeBuffer(
        bytes: cloud.weights, length: cloud.count * MemoryLayout<SIMD4<Float>>.stride),
      let poses = device.makeBuffer(
        length: max(cloud.jointNames.count, 1) * MemoryLayout<GPUJoint>.stride)
    else { return nil }
    count = cloud.count
    self.device = device
    self.queue = queue
    self.pipeline = pipeline
    self.rest = rest
    self.joints = joints
    self.weights = weights
    self.poses = poses
    self.map = map
  }

  /// Uploads this frame's joint poses (in the skeleton's order) and encodes the kernel that writes
  /// the posed splats into `destination`.
  func encode(
    poses skeleton: [SplatJointPose], into destination: MTLBuffer, on buffer: MTLCommandBuffer
  ) {
    let pointer = poses.contents().bindMemory(to: GPUJoint.self, capacity: map.count)
    for (i, index) in map.enumerated() {
      let pose = index < skeleton.count ? skeleton[index] : .identity
      pointer[i] = GPUJoint(matrix: pose.matrix, rotation: pose.rotation.vector)
    }
    guard let encoder = buffer.makeComputeCommandEncoder() else { return }
    var n = UInt32(count)
    encoder.setComputePipelineState(pipeline)
    encoder.setBuffer(rest, offset: 0, index: 0)
    encoder.setBuffer(joints, offset: 0, index: 1)
    encoder.setBuffer(weights, offset: 0, index: 2)
    encoder.setBuffer(poses, offset: 0, index: 3)
    encoder.setBuffer(destination, offset: 0, index: 4)
    encoder.setBytes(&n, length: MemoryLayout<UInt32>.stride, index: 5)
    let width = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
    encoder.dispatchThreads(
      MTLSize(width: count, height: 1, depth: 1),
      threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
    encoder.endEncoding()
  }
}
