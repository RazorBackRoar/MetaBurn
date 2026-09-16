import Foundation
import simd

/// Uniforms shared with the runtime-compiled Metal fire shader. Layout must stay packed
/// and 16-byte friendly so Swift and Metal agree without a bridging header.
struct FireUniforms {
    var resolution: SIMD2<Float> = .zero
    var pointer: SIMD2<Float> = .zero
    var burst: SIMD2<Float> = .zero
    var time: Float = 0
    var pointerStrength: Float = 0
    var intensity: Float = 0.7
    var isLight: Float = 0
    var burstAge: Float = 10
    var pad: Float = 0
}

enum FireShader {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct FireUniforms {
        float2 resolution;
        float2 pointer;
        float2 burst;
        float time;
        float pointerStrength;
        float intensity;
        float isLight;
        float burstAge;
        float pad;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut fire_vertex(uint vid [[vertex_id]]) {
        float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        VertexOut out;
        out.position = float4(positions[vid], 0.0, 1.0);
        out.uv = positions[vid] * 0.5 + 0.5;
        return out;
    }

    float hash21(float2 p) {
        return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
    }

    float noise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        float a = hash21(i);
        float b = hash21(i + float2(1.0, 0.0));
        float c = hash21(i + float2(0.0, 1.0));
        float d = hash21(i + float2(1.0, 1.0));
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }

    float fbm(float2 p) {
        float v = 0.0;
        float a = 0.5;
        for (int i = 0; i < 5; i++) {
            v += a * noise(p);
            p = p * 2.03 + float2(1.7, 9.2);
            a *= 0.5;
        }
        return v;
    }

    float3 firePalette(float t) {
        t = saturate(t);
        float3 c = float3(0.035, 0.008, 0.010);
        c = mix(c, float3(0.12, 0.015, 0.018), smoothstep(0.00, 0.22, t));
        c = mix(c, float3(0.32, 0.025, 0.022), smoothstep(0.18, 0.42, t));
        c = mix(c, float3(0.58, 0.07, 0.03), smoothstep(0.38, 0.68, t));
        c = mix(c, float3(0.78, 0.14, 0.04), smoothstep(0.62, 0.88, t));
        c = mix(c, float3(0.92, 0.32, 0.06), smoothstep(0.84, 1.00, t));
        return c;
    }

    fragment float4 fire_fragment(VertexOut in [[stage_in]],
                                  constant FireUniforms &u [[buffer(0)]]) {
        float2 uv = in.uv;
        float t = u.time;
        float intensity = clamp(u.intensity, 0.0, 1.2);

        float2 nUV = float2(uv.x * 3.2, uv.y * 2.4 - t * (0.18 + 0.22 * intensity));
        float warp = fbm(nUV + float2(0.0, t * 0.08));
        float n = fbm(nUV + warp * 1.25);
        float n2 = fbm(float2(uv.x * 5.4 + 8.0, uv.y * 3.4 - t * 0.34));
        float room = fbm(float2(uv.x * 1.15, uv.y * 0.85 + t * 0.035));

        float height = mix(0.42, 1.0, pow(saturate(1.0 - uv.y), 0.72));
        float heat = saturate((n * 0.72 + n2 * 0.38) * height * (0.55 + 0.55 * intensity));
        heat = pow(heat, 1.05);

        if (u.burstAge >= 0.0 && u.burstAge < 1.8) {
            float aspect = u.resolution.x / max(u.resolution.y, 1.0);
            float2 buv = u.burst / max(u.resolution, float2(1.0, 1.0));
            float dist = length(float2((uv.x - buv.x) * aspect, uv.y - buv.y));
            float radius = u.burstAge * 0.34;
            float ring = exp(-abs(dist - radius) * 28.0) * exp(-u.burstAge * 1.8);
            heat = saturate(heat + ring * 0.28);
        }

        float3 col = firePalette(heat);
        float3 furnace = mix(float3(0.05, 0.012, 0.014), float3(0.16, 0.03, 0.025), room);
        col = mix(furnace, col, 0.55 + 0.45 * heat);

        if (u.isLight > 0.5) {
            col = mix(col, col * float3(1.12, 1.04, 1.02) + float3(0.04, 0.01, 0.008), 0.22);
        }

        return float4(col, 1.0);
    }
    """
}
