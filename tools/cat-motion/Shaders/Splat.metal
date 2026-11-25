#include <metal_stdlib>
using namespace metal;

// Draws a skinned splat body through an orthographic camera: every Gaussian as a quad over three of
// its standard deviations, back to front, premultiplied.

struct View {
    float4x4 toCamera;     // model space to camera space; the camera looks down -Z
    float2 viewport;       // pixels
    float pixelsPerUnit;
    float pad;
};

struct Fragment {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex Fragment splatVertex(uint vertexID [[vertex_id]],
                            uint instance [[instance_id]],
                            const device float *moving [[buffer(0)]],
                            const device float *still [[buffer(1)]],
                            const device uint *order [[buffer(2)]],
                            constant View &view [[buffer(3)]]) {
    uint id = order[instance];
    const device float *m = moving + 8 * id;
    const device float *s = still + 8 * id;
    float3 center = float3(m[0], m[1], m[2]);
    float4 q = normalize(float4(m[5], m[6], m[7], m[4]));   // x, y, z, w
    float3 scale = exp(float3(s[0], s[1], s[2]));
    float opacity = 1 / (1 + exp(-s[3]));
    float3 color = saturate(0.5 + 0.28209479 * float3(s[4], s[5], s[6]));

    float x = q.x, y = q.y, z = q.z, w = q.w;
    float3x3 turn = float3x3(float3(1 - 2 * (y * y + z * z), 2 * (x * y + w * z), 2 * (x * z - w * y)),
                             float3(2 * (x * y - w * z), 1 - 2 * (x * x + z * z), 2 * (y * z + w * x)),
                             float3(2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y)));
    float3x3 linear = float3x3(view.toCamera[0].xyz, view.toCamera[1].xyz, view.toCamera[2].xyz);
    float3x3 axes = linear * turn * float3x3(float3(scale.x, 0, 0), float3(0, scale.y, 0), float3(0, 0, scale.z));
    float3x3 cov = axes * transpose(axes);
    float k = view.pixelsPerUnit;
    float a = k * k * cov[0][0] + 0.3;
    float b = k * k * cov[0][1];
    float c = k * k * cov[1][1] + 0.3;
    float mid = 0.5 * (a + c);
    float radius = sqrt(max(mid * mid - (a * c - b * b), 1e-6));
    float l1 = mid + radius, l2 = max(mid - radius, 0.05);
    float2 v1 = abs(b) > 1e-6 ? normalize(float2(b, l1 - a)) : (a >= c ? float2(1, 0) : float2(0, 1));
    float2 v2 = float2(-v1.y, v1.x);

    float2 corner = float2(vertexID & 1 ? 1.0 : -1.0, vertexID & 2 ? 1.0 : -1.0);
    float3 camera = (view.toCamera * float4(center, 1)).xyz;
    float2 pixel = k * camera.xy + 3 * (corner.x * sqrt(l1) * v1 + corner.y * sqrt(l2) * v2);

    Fragment out;
    out.position = float4(2 * pixel / view.viewport, 0.5, 1);
    out.uv = 3 * corner;
    out.color = float4(color, opacity);
    return out;
}

fragment float4 splatFragment(Fragment in [[stage_in]]) {
    float alpha = in.color.a * exp(-0.5 * dot(in.uv, in.uv));
    if (alpha < 1.0 / 255) discard_fragment();
    return float4(in.color.rgb * alpha, alpha);
}
