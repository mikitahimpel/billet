#include <metal_stdlib>
using namespace metal;

// Quaternions as (x, y, z, w), like simd_quatf's vector; the splat file stores its rotations w first.
struct DualQuat {
    float4 real;
    float4 dual;
};

static float4 multiply(float4 a, float4 b) {
    return float4(a.w * b.xyz + b.w * a.xyz + cross(a.xyz, b.xyz), a.w * b.w - dot(a.xyz, b.xyz));
}

/// Writes every splat of `out` from its rest pose in `rest`, 14 floats each in GaussianSplatResource's layout: the
/// center and rotation follow the blend of its four bones, scale, opacity and color are copied as trained. `skin` holds
/// per splat four bone indices, then four weights out of 255.
kernel void skinSplats(device const float *rest [[buffer(0)]],
                       device const uchar4 *skin [[buffer(1)]],
                       constant DualQuat *bones [[buffer(2)]],
                       device float *out [[buffer(3)]],
                       constant uint &count [[buffer(4)]],
                       uint i [[thread_position_in_grid]]) {
    if (i >= count) return;
    uchar4 index = skin[2 * i];
    float4 weight = float4(skin[2 * i + 1]) / 255;
    float4 first = bones[index.x].real;
    float4 real = 0;
    float4 dual = 0;
    for (int k = 0; k < 4; k++) {
        DualQuat bone = bones[index[k]];
        // Antipodal quaternions are the same turn; blending one against the other would cancel it.
        float w = dot(bone.real, first) < 0 ? -weight[k] : weight[k];
        real += w * bone.real;
        dual += w * bone.dual;
    }
    float n = length(real);
    real /= n;
    dual /= n;
    float3 t = 2 * multiply(dual, float4(-real.xyz, real.w)).xyz;

    device const float *r = rest + 14 * i;
    device float *o = out + 14 * i;
    float3 p = float3(r[0], r[1], r[2]);
    p += 2 * cross(real.xyz, cross(real.xyz, p) + real.w * p) + t;
    float4 q = multiply(real, float4(r[7], r[8], r[9], r[6]));
    o[0] = p.x;
    o[1] = p.y;
    o[2] = p.z;
    o[3] = r[3];
    o[4] = r[4];
    o[5] = r[5];
    o[6] = q.w;
    o[7] = q.x;
    o[8] = q.y;
    o[9] = q.z;
    for (int k = 10; k < 14; k++) o[k] = r[k];
}
