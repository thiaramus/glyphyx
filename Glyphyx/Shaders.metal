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
    float  _pad0;
    float  _pad1;
    float  _pad2;
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
    int    totalRows = int(pane.gridSize.y);

    // Per-column seed combining column index and pane identity
    float seedOffset = float(pane.layerSeed) * 137.0;
    float colSeed    = float(col) + seedOffset;

    // Per-column random properties
    float speed       = frame.fallSpeedMultiplier * (4.0 + hash(float2(colSeed, 0.0)) * 8.0);
    float offset      = hash(float2(colSeed, 1.0)) * float(totalRows);
    int   trailLength = 10 + int(hash(float2(colSeed, 2.0)) * 20.0);

    // Falling head position
    float cycleLen = float(totalRows + trailLength + 10);
    float headF    = fmod(frame.time * speed + offset * cycleLen, cycleLen);
    int   head     = int(headF);

    // Only render cells within the trail behind the head
    int dist = head - row;
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
    float2 atlasUV   = (float2(float(atlasCol), float(atlasRow)) + cellUV) / frame.atlasGridSize;
    float4 glyph     = atlas.sample(s, atlasUV);
    float  alpha     = glyph.r;

    if (alpha < 0.05) {
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

    return float4(color * brightness * fogFactor * pane.brightness * alpha, 1.0);
}
