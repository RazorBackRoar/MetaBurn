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
    var intensity: Float = 0.22
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
        for (int i = 0; i < 4; i++) {
            v += a * noise(p);
            p = p * 2.03 + float2(1.7, 9.2);
            a *= 0.5;
        }
        return v;
    }

    fragment float4 fire_fragment(VertexOut in [[stage_in]],
                                  constant FireUniforms &u [[buffer(0)]]) {
        float2 uv = in.uv;
        float t = u.time;
        float intensity = clamp(u.intensity, 0.0, 1.0);

        float2 nUV = float2(uv.x * 2.4, uv.y * 1.6 - t * 0.12);
        float n = fbm(nUV + fbm(nUV + float2(0.0, t * 0.05)) * 0.7);

        float bowl = pow(saturate(1.0 - abs(uv.x - 0.5) * 1.35), 1.25);
        float reach = (0.09 + 0.08 * intensity) * (0.55 + 0.45 * bowl);
        float shape = pow(saturate((reach - uv.y) / max(reach, 0.001)), 2.1);
        float heat = n * shape * (0.28 + 0.22 * intensity);

        if (u.burstAge >= 0.0 && u.burstAge < 1.6) {
            float aspect = u.resolution.x / max(u.resolution.y, 1.0);
            float2 buv = u.burst / max(u.resolution, float2(1.0, 1.0));
            float dist = length(float2((uv.x - buv.x) * aspect, uv.y - buv.y));
            float radius = u.burstAge * 0.28;
            float ring = exp(-abs(dist - radius) * 36.0) * exp(-u.burstAge * 2.2);
            heat = saturate(heat + ring * 0.18);
        }

        float3 darkBase = float3(0.090, 0.086, 0.090);
        float3 lightBase = float3(0.965, 0.958, 0.950);
        float3 base = mix(darkBase, lightBase, u.isLight);

        float glow = pow(saturate(1.0 - uv.y / 0.42), 2.4) * (0.10 + 0.16 * intensity);
        float3 ember = mix(float3(0.22, 0.04, 0.02), float3(0.55, 0.18, 0.06), n);
        float3 peach = float3(0.92, 0.72, 0.58);
        float3 wash = mix(ember, peach, u.isLight);
        float amount = glow * (u.isLight ? 0.22 : 0.34) + heat * (u.isLight ? 0.16 : 0.28);

        float3 col = mix(base, wash, saturate(amount));
        return float4(col, 1.0);
    }
    """
}
