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
    var intensity: Float = 0.45
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
        float3 c = float3(0.02, 0.008, 0.01);
        c = mix(c, float3(0.42, 0.02, 0.00), smoothstep(0.00, 0.22, t));
        c = mix(c, float3(0.90, 0.12, 0.04), smoothstep(0.18, 0.46, t));
        c = mix(c, float3(1.00, 0.48, 0.06), smoothstep(0.42, 0.70, t));
        c = mix(c, float3(1.00, 0.86, 0.32), smoothstep(0.66, 0.88, t));
        c = mix(c, float3(1.00, 0.97, 0.90), smoothstep(0.86, 1.00, t));
        return c;
    }

    fragment float4 fire_fragment(VertexOut in [[stage_in]],
                                  constant FireUniforms &u [[buffer(0)]]) {
        float2 uv = in.uv;
        float aspect = u.resolution.x / max(u.resolution.y, 1.0);
        float t = u.time;
        float intensity = clamp(u.intensity, 0.0, 1.35);

        float shimmer = fbm(float2(uv.x * 6.0, uv.y * 3.2 - t * 0.75));
        uv.x += (shimmer - 0.5) * 0.028 * (1.0 - uv.y) * intensity;

        float2 nUV = float2(uv.x * 3.8, uv.y * 2.35 - t * (0.32 + 0.58 * intensity));
        float warp = fbm(nUV + float2(0.0, t * 0.12));
        float n = fbm(nUV + warp * 1.35);
        float n2 = fbm(float2(uv.x * 7.2 + 11.0, uv.y * 3.1 - t * 0.92));

        float bowl = pow(saturate(1.0 - abs(uv.x - 0.5) * 1.65), 1.15);
        float reach = (0.42 + 0.68 * intensity) * (0.40 + 0.60 * bowl);
        float shape = saturate((reach - uv.y) / max(reach, 0.001));
        shape = pow(shape, 1.22);

        float heat = saturate(n * shape * (0.9 + 0.5 * intensity));
        heat = saturate(heat + n2 * shape * 0.22 * intensity);
        heat = pow(heat, 1.12);

        float2 ptr = u.pointer / max(u.resolution, float2(1.0, 1.0));
        float2 d = uv - ptr;
        d.x *= aspect;
        d.y -= 0.016;
        float flicker = 0.82 + 0.18 * fbm(float2(t * 8.5, ptr.x * 18.0));
        d.x /= 0.020 + 0.004 * sin(t * 16.0);
        d.y /= 0.052;
        float r = length(float2(d.x, d.y - 0.18 * d.x * d.x));
        float candle = pow(saturate((1.0 - r) * flicker), 1.35) * u.pointerStrength;
        heat = max(heat, candle * 1.18);

        if (u.burstAge >= 0.0 && u.burstAge < 2.2) {
            float2 buv = u.burst / max(u.resolution, float2(1.0, 1.0));
            float2 delta = float2((uv.x - buv.x) * aspect, uv.y - buv.y);
            float dist = length(delta);
            float radius = u.burstAge * 0.52;
            float ring = exp(-abs(dist - radius) * 30.0) * exp(-u.burstAge * 1.7);
            heat = saturate(heat + ring * 0.7);
        }

        float3 darkBase = float3(0.026, 0.010, 0.012);
        float3 lightBase = float3(0.94, 0.90, 0.85);
        float3 base = mix(darkBase, lightBase, u.isLight);
        float floorGlow = pow(saturate(1.0 - uv.y), 2.15) * (0.22 + 0.58 * intensity);
        base += float3(0.38, 0.05, 0.012) * floorGlow * (1.0 - 0.62 * u.isLight);

        float fireAmount = saturate(heat * (u.isLight ? 0.70 : 1.0));
        float3 col = mix(base, firePalette(heat), fireAmount);

        float vig = smoothstep(1.18, 0.32, length((uv - 0.5) * float2(1.18, 1.0)));
        col *= mix(0.80, 1.0, vig);

        return float4(col, 1.0);
    }
    """
}
