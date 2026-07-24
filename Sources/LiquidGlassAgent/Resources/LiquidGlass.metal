#include <metal_stdlib>
using namespace metal;

struct VertexOutput {
    float4 position [[position]];
};

struct GlassUniforms {
    float4 viewportTimeRadius;
    float4 sourceOriginSize;
    float4 windowSizeSegmentOrigin;
    float4 opticalPrimary;
    float4 opticalSecondary;
    float4 tint;
    float4 flags;
};

vertex VertexOutput liquidGlassVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(-1.0,  3.0),
        float2( 3.0, -1.0)
    };
    VertexOutput output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    return output;
}

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

static float fbm(float2 p) {
    float result = 0.0;
    float amplitude = 0.52;
    float2 shift = float2(19.7, 7.3);
    float2x2 rotation = float2x2(
        float2(0.80, -0.60),
        float2(0.60,  0.80)
    );
    for (uint octave = 0; octave < 4; ++octave) {
        result += amplitude * valueNoise(p);
        p = rotation * p * 2.03 + shift;
        amplitude *= 0.48;
    }
    return result;
}

static float liquidField(float2 p, float time) {
    float2 driftA = float2(time * 0.17, -time * 0.11);
    float2 driftB = float2(-time * 0.09, time * 0.14);
    float warpA = fbm(p * 0.82 + driftA);
    float warpB = fbm(p * 1.23 + driftB + warpA * 1.8);
    float waves = sin(p.x * 2.7 + p.y * 1.5 + time * 0.8) * 0.08;
    waves += sin(p.y * 3.4 - p.x * 1.2 - time * 0.55) * 0.055;
    return warpA * 0.56 + warpB * 0.44 + waves;
}

static float roundedBoxSDF(float2 point, float2 halfSize, float radius) {
    float2 q = abs(point) - max(halfSize - radius, float2(0.0));
    return length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

static float3 applySaturation(float3 color, float saturation) {
    float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
    return mix(float3(luminance), color, saturation);
}

fragment float4 liquidGlassFragment(
    VertexOutput input [[stage_in]],
    constant GlassUniforms &uniforms [[buffer(0)]],
    texture2d<float> sharpTexture [[texture(0)]],
    texture2d<float> blurredTexture [[texture(1)]],
    sampler linearSampler [[sampler(0)]]
) {
    float2 viewport = max(uniforms.viewportTimeRadius.xy, float2(1.0));
    float time = uniforms.viewportTimeRadius.z;
    float radius = uniforms.viewportTimeRadius.w;
    float2 segmentUV = input.position.xy / viewport;

    float2 fullWindowSize = max(uniforms.windowSizeSegmentOrigin.xy, float2(1.0));
    float2 fullWindowPixel = uniforms.windowSizeSegmentOrigin.zw + input.position.xy;
    float2 centeredPixel = fullWindowPixel - fullWindowSize * 0.5;
    float signedDistance = roundedBoxSDF(centeredPixel, fullWindowSize * 0.5, radius);
    float antialiasWidth = max(fwidth(signedDistance), 0.85);
    float shapeAlpha = 1.0 - smoothstep(-antialiasWidth, antialiasWidth, signedDistance);
    if (shapeAlpha <= 0.001) {
        return float4(0.0);
    }

    float insideDistance = max(-signedDistance, 0.0);
    float edgeBand = exp(-insideDistance / max(10.0, radius * 0.65 + 2.0));
    float borderLine = 1.0 - smoothstep(0.0, 1.8 + antialiasWidth, abs(signedDistance));

    float2 normalizedWindow = (fullWindowPixel / fullWindowSize - 0.5) * 2.0;
    float aspect = fullWindowSize.x / max(fullWindowSize.y, 1.0);
    float2 fieldPosition = float2(normalizedWindow.x * aspect, normalizedWindow.y)
        * uniforms.opticalPrimary.z;
    float flowTime = time * uniforms.opticalPrimary.w;
    float epsilon = 0.018;
    float heightCenter = liquidField(fieldPosition, flowTime);
    float heightX = liquidField(fieldPosition + float2(epsilon, 0.0), flowTime);
    float heightY = liquidField(fieldPosition + float2(0.0, epsilon), flowTime);
    float2 surfaceGradient = float2(heightX - heightCenter, heightY - heightCenter) / epsilon;

    float2 edgeDirection = centeredPixel / max(fullWindowSize * 0.5, float2(1.0));
    float edgeLength = max(length(edgeDirection), 0.0001);
    edgeDirection /= edgeLength;
    float edgeLens = edgeBand * edgeBand;

    float refractionPixels = uniforms.opticalPrimary.x;
    float2 displacementPixels = surfaceGradient * refractionPixels * 0.42;
    displacementPixels += edgeDirection * edgeLens * refractionPixels * 0.82;

    float2 sourceOrigin = uniforms.sourceOriginSize.xy;
    float2 sourceSize = uniforms.sourceOriginSize.zw;
    float2 baseUV = sourceOrigin + segmentUV * sourceSize;
    float2 displacementUV = displacementPixels / viewport * sourceSize;

    float dispersionPixels = uniforms.opticalPrimary.y;
    float2 dispersionUV = normalize(displacementUV + float2(0.000001))
        * (dispersionPixels / viewport) * sourceSize;

    float red = sharpTexture.sample(linearSampler, baseUV + displacementUV + dispersionUV).r;
    float green = sharpTexture.sample(linearSampler, baseUV + displacementUV).g;
    float blue = sharpTexture.sample(linearSampler, baseUV + displacementUV - dispersionUV).b;
    float3 refracted = float3(red, green, blue);
    float3 blurred = blurredTexture.sample(
        linearSampler,
        baseUV + displacementUV * 0.34
    ).rgb;

    float clarity = 0.50 + 0.24 * (1.0 - edgeBand);
    float3 color = mix(blurred, refracted, clarity);
    color = applySaturation(color, uniforms.opticalSecondary.z);
    color = mix(color, uniforms.tint.rgb, uniforms.tint.a);

    float3 pseudoNormal = normalize(float3(-surfaceGradient * 0.55, 1.0));
    float3 lightDirection = normalize(float3(-0.42, -0.55, 0.72));
    float specular = pow(saturate(dot(pseudoNormal, lightDirection)), 24.0);
    float fresnel = pow(1.0 - saturate(pseudoNormal.z), 2.4);

    float causticPattern = sin(
        fieldPosition.x * 8.0
        + fieldPosition.y * 5.7
        + heightCenter * 12.0
        + flowTime * 2.3
    );
    causticPattern = pow(saturate(causticPattern * 0.5 + 0.5), 5.0);
    float caustics = causticPattern
        * uniforms.opticalSecondary.y
        * (0.24 + edgeBand * 0.76);

    float edgeEnergy = uniforms.opticalSecondary.x * (borderLine * 0.72 + edgeBand * 0.18);
    float3 coolHighlight = float3(0.62, 0.78, 1.0);
    float3 warmHighlight = float3(1.0, 0.83, 0.68);
    color += mix(coolHighlight, warmHighlight, heightCenter) * edgeEnergy;
    color += float3(specular * 0.18 + fresnel * 0.10 + caustics * 0.14);

    float grain = hash21(input.position.xy + float2(time * 29.0, time * 13.0)) - 0.5;
    color += grain * uniforms.opticalSecondary.w;
    color = max(color, float3(0.0));

    float interiorAlpha = 0.985 - edgeBand * 0.025;
    float alpha = shapeAlpha * interiorAlpha;
    return float4(color * alpha, alpha);
}
