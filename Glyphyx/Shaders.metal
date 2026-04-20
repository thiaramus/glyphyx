#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 uv       [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Must match FrameUniforms in Renderer.swift (field order and padding are intentional)
struct FrameUniforms {
    float4 headColor;
    float4 trailColor;
    float4 glowColor;
    float  time;
    int    totalChars;
    float2 atlasGridSize;
    float  fallSpeedMultiplier;
    float  characterBlur;
    int    flowDirection;
    int    bidirectionalLayout;
};

struct PaneUniforms {
    float4x4 mvp;
    float2   gridSize;
    int      layerSeed;
    float    brightness;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant PaneUniforms &pane [[buffer(1)]]) {
    VertexOut out;
    out.position = pane.mvp * float4(in.position, 0.0, 1.0);
    out.uv = in.uv;
    return out;
}

float hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              constant FrameUniforms  &frame [[buffer(0)]],
                              constant PaneUniforms   &pane  [[buffer(1)]],
                              texture2d<float>         atlas [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    // Map UV to grid cell coordinates
    float2 cellPos   = in.uv * pane.gridSize;
    int    col       = int(cellPos.x);
    int    row       = int(cellPos.y);
    int    totalCols = int(pane.gridSize.x);
    int    totalRows = int(pane.gridSize.y);

    // Per-column seed combining column index and pane identity
    float seedOffset = float(pane.layerSeed) * 137.0;
    float colSeed    = float(col) + seedOffset;

    // Per-column random properties
    float speed       = frame.fallSpeedMultiplier * (4.0 + hash(float2(colSeed, 0.0)) * 8.0);
    float offset      = hash(float2(colSeed, 1.0)) * float(totalRows);
    int   trailLength = 10 + int(hash(float2(colSeed, 2.0)) * 20.0);

    int direction = 1;
    if (frame.flowDirection == 1) {
        direction = -1;
    } else if (frame.flowDirection == 2) {
        if (frame.bidirectionalLayout == 1) {
            direction = (col % 2 == 0) ? 1 : -1;
        } else {
            int splitColumn = totalCols / 2;
            direction = col < splitColumn ? 1 : -1;
        }
    }

    // Head position
    float cycleLen = float(totalRows + trailLength + 10);
    float headF    = fmod(frame.time * speed + offset * cycleLen, cycleLen);
    int   head     = int(headF);

    int orientedRow = direction > 0 ? row : (totalRows - 1 - row);

    // Only render cells within the trail behind the head
    int dist = head - orientedRow;
    if (dist < 0 || dist > trailLength) {
        discard_fragment();
    }

    // Brightness falloff along the trail
    float brightness;
    if (dist <= 1) {
        brightness = 1.0;
    } else {
        float t = float(dist) / float(trailLength);
        brightness = (1.0 - t) * (1.0 - t);
    }

    // Subtle depth fog: slightly dims distant geometry
    float fogFactor = 1.0 - smoothstep(0.5, 0.98, in.position.z) * 0.35;

    // Character selection — changes over time per cell
    float charSeed = hash(float2(colSeed, float(row) + floor(frame.time * 8.0 + hash(float2(colSeed, float(row))))));
    int   charIdx  = int(charSeed * float(frame.totalChars)) % frame.totalChars;

    // Sample glyph from atlas
    int    atlasCol  = charIdx % int(frame.atlasGridSize.x);
    int    atlasRow  = charIdx / int(frame.atlasGridSize.x);
    float2 cellUV    = fract(cellPos);
    float2 atlasCellMin = float2(float(atlasCol), float(atlasRow)) / frame.atlasGridSize;
    float2 atlasCellMax = float2(float(atlasCol + 1), float(atlasRow + 1)) / frame.atlasGridSize;
    float2 atlasUV      = (float2(float(atlasCol), float(atlasRow)) + cellUV) / frame.atlasGridSize;
    float2 texelSize    = 1.0 / float2(float(atlas.get_width()), float(atlas.get_height()));
    float2 clampedMin   = atlasCellMin + texelSize * 0.5;
    float2 clampedMax   = atlasCellMax - texelSize * 0.5;

    float baseAlpha = atlas.sample(s, atlasUV).r;
    float haloAlpha = 0.0;
    if (frame.characterBlur <= 0.001) {
        haloAlpha = 0.0;
    } else {
        float2 blurOffset = texelSize * frame.characterBlur;
        float blurredAlpha =
            atlas.sample(s, clamp(atlasUV, clampedMin, clampedMax)).r * 0.227027f +
            atlas.sample(s, clamp(atlasUV + float2( blurOffset.x, 0.0), clampedMin, clampedMax)).r * 0.1945946f +
            atlas.sample(s, clamp(atlasUV + float2(-blurOffset.x, 0.0), clampedMin, clampedMax)).r * 0.1945946f +
            atlas.sample(s, clamp(atlasUV + float2(0.0,  blurOffset.y), clampedMin, clampedMax)).r * 0.1216216f +
            atlas.sample(s, clamp(atlasUV + float2(0.0, -blurOffset.y), clampedMin, clampedMax)).r * 0.1216216f +
            atlas.sample(s, clamp(atlasUV + blurOffset, clampedMin, clampedMax)).r * 0.07027f +
            atlas.sample(s, clamp(atlasUV - blurOffset, clampedMin, clampedMax)).r * 0.07027f;
        haloAlpha = max(0.0, blurredAlpha - baseAlpha) * min(frame.characterBlur, 1.5);
    }

    if (baseAlpha < 0.05 && haloAlpha < 0.01) {
        discard_fragment();
    }

    // Pick color based on position in trail
    float3 color;
    if (dist <= 1) {
        color = frame.headColor.rgb;
    } else {
        color = frame.trailColor.rgb;
    }

    // Glow: blend glow color into head characters based on proximity to cell center
    if (dist <= 1) {
        float2 cellCenter  = floor(cellPos) + 0.5;
        float  cellDist    = length(cellPos - cellCenter);
        float  glowWeight  = max(0.0, 1.0 - cellDist * 2.5) * frame.glowColor.a;
        color = color + frame.glowColor.rgb * glowWeight;
    }

    float3 glowColor = color * 0.35 + frame.glowColor.rgb * 0.65;
    float3 finalColor =
        color * baseAlpha +
        glowColor * haloAlpha * (0.8 + frame.glowColor.a * 0.6);

    return float4(finalColor * brightness * fogFactor * pane.brightness, 1.0);
}
