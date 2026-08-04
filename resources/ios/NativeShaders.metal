#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>

using namespace metal;

// Every function here is [[stitchable]] so SwiftUI's ShaderLibrary can find
// it by name at runtime. The build compiles this file into the app's
// default.metallib — shader source is fixed at build time, it cannot be
// shipped over the air from PHP.
//
// This file reaches the Xcode project through the `assets` entry in
// nativephp.json, NOT through the plugin source copy (which only handles
// .swift). It lands in NativePHP/Resources/, inside the file-system-
// synchronized group, so Xcode compiles it with no project-file changes.
// Add new shaders here rather than in a new file.
//
// Argument order is the contract with Elements/Shader.php: the renderer
// always passes (size, time) first, then the element's uniforms in the
// order they were declared in Blade.

/// layer mode — radial ripple that samples the rendered children.
/// uniforms: amplitude, frequency
[[stitchable]] half4 ripple(float2 position,
                            SwiftUI::Layer layer,
                            float2 size,
                            float time,
                            float amplitude,
                            float frequency)
{
    float2 uv = position / size;
    float2 delta = uv - float2(0.5, 0.5);
    float dist = length(delta);

    // Fade the displacement out toward the edges so the effect doesn't tear
    // at the layer bounds (samples beyond maxSampleOffset return clear).
    float falloff = smoothstep(0.75, 0.0, dist);
    float wave = sin(dist * frequency - time) * amplitude * falloff;

    float2 direction = dist > 1e-4 ? delta / dist : float2(0.0);

    return layer.sample(position + direction * wave);
}

/// distortion mode — the same ripple, as a coordinate displacement.
/// uniforms: amplitude, frequency
///
/// Note the signature: a distortion shader returns the float2 position to
/// sample FROM and never sees the layer, where a layer shader returns a half4
/// and samples the layer itself. The two are not interchangeable — handing a
/// layer function to .distortionEffect() renders nothing at all, silently.
/// Hence the separate entry point over the identical math.
[[stitchable]] float2 rippleDistortion(float2 position,
                                       float2 size,
                                       float time,
                                       float amplitude,
                                       float frequency)
{
    float2 uv = position / size;
    float2 delta = uv - float2(0.5, 0.5);
    float dist = length(delta);

    float falloff = smoothstep(0.75, 0.0, dist);
    float wave = sin(dist * frequency - time) * amplitude * falloff;

    float2 direction = dist > 1e-4 ? delta / dist : float2(0.0);

    return position + direction * wave;
}

/// layer mode — mosaic. Snaps sample coordinates to a grid, then blends the
/// blocky result back over the original.
/// uniforms: cellSize, blend
///
/// The clearest proof that a layer shader samples REAL views: the text and
/// image below it are live SwiftUI, and they dissolve into blocks anyway.
[[stitchable]] half4 pixelate(float2 position,
                              SwiftUI::Layer layer,
                              float2 size,
                              float time,
                              float cellSize,
                              float blend)
{
    float cell = max(cellSize, 1.0);

    // Sample the CENTRE of the cell, not its corner — sampling the corner
    // biases every block up-left by half a cell and the grid visibly drifts.
    float2 snapped = floor(position / cell) * cell + cell * 0.5;

    half4 blocky = layer.sample(snapped);
    half4 original = layer.sample(position);

    return mix(original, blocky, half(clamp(blend, 0.0, 1.0)));
}

/// distortion mode — twists sample coordinates around the centre, unwinding
/// to zero at the edge of `radius` (in points).
/// uniforms: strength, radius
[[stitchable]] float2 swirl(float2 position,
                            float2 size,
                            float time,
                            float strength,
                            float radius)
{
    float2 centre = size * 0.5;
    float2 delta = position - centre;

    float r = max(radius, 1.0);
    float angle = strength * smoothstep(r, 0.0, length(delta));

    float s = sin(angle);
    float c = cos(angle);

    return centre + float2(
        delta.x * c - delta.y * s,
        delta.x * s + delta.y * c
    );
}

/// color mode — three drifting colour blobs. Recolours whatever it is given.
/// uniforms: spread, intensity
///
/// A colour shader can only recolour pixels that ALREADY EXIST — it must
/// preserve the incoming alpha. Returning a hardcoded 1.0 turns every
/// transparent pixel opaque, which paints filled boxes around each text run
/// and squares off rounded corners.
///
/// So this is a background, not a wrapper: hand it a plain opaque panel and
/// layer the real content over it as a sibling in a <stack>.
[[stitchable]] half4 aurora(float2 position,
                            half4 color,
                            float2 size,
                            float time,
                            float spread,
                            float intensity)
{
    float2 uv = position / size;
    float s = max(spread, 0.05);

    float2 a = float2(0.50 + 0.35 * sin(time * 0.50), 0.35 + 0.25 * cos(time * 0.40));
    float2 b = float2(0.30 + 0.30 * cos(time * 0.30), 0.70 + 0.20 * sin(time * 0.60));
    float2 c = float2(0.75 + 0.20 * sin(time * 0.70), 0.50 + 0.30 * cos(time * 0.50));

    float wa = exp(-dot(uv - a, uv - a) / (s * s));
    float wb = exp(-dot(uv - b, uv - b) / (s * s));
    float wc = exp(-dot(uv - c, uv - c) / (s * s));

    half3 gradient = half3(wa) * half3(0.30h, 0.42h, 0.95h)   // indigo
                   + half3(wb) * half3(0.95h, 0.35h, 0.65h)   // pink
                   + half3(wc) * half3(0.30h, 0.85h, 0.75h);  // teal

    gradient = clamp(gradient * half(intensity), 0.0h, 1.0h);

    // Premultiplied, and carrying the source alpha through unchanged.
    return half4(gradient * color.a, color.a);
}

static float galaxyHash(float2 p)
{
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float galaxyNoise(float2 p)
{
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);

    return mix(mix(galaxyHash(i),                    galaxyHash(i + float2(1.0, 0.0)), u.x),
               mix(galaxyHash(i + float2(0.0, 1.0)), galaxyHash(i + float2(1.0, 1.0)), u.x),
               u.y);
}

static float galaxyStars(float2 p, float cells, float time)
{
    float2 g = p * cells;
    float2 cell = floor(g);
    float2 f = fract(g) - 0.5;

    float h = galaxyHash(cell);
    float2 offset = float2(galaxyHash(cell + 19.19), galaxyHash(cell + 47.31)) - 0.5;

    float d = length(f - offset * 0.7);
    float twinkle = 0.6 + 0.4 * sin(time * (1.0 + h * 4.0) + h * 41.0);

    // Only ~1 cell in 5 holds a star; the rest stay empty space.
    return smoothstep(0.12, 0.0, d) * step(0.8, h) * twinkle;
}

/// color mode — a slowly turning spiral galaxy: two logarithmic nebula arms
/// wound around a warm core, over a two-layer twinkling starfield.
/// uniforms: twist, starDensity, intensity
///
/// A background in the `aurora` mould: hand it an opaque panel and stack the
/// real content over it as a sibling. It preserves the incoming alpha.
[[stitchable]] half4 galaxy(float2 position,
                            half4 color,
                            float2 size,
                            float time,
                            float twist,
                            float starDensity,
                            float intensity)
{
    // Centre and aspect-correct so the galaxy stays round on any panel.
    float2 p = (position - 0.5 * size) / min(size.x, size.y);

    float r = length(p);
    float theta = atan2(p.y, p.x);
    float spin = time * 0.05;

    // The log term winds the arms tighter toward the core.
    float arm = cos(2.0 * (theta + spin) - twist * log(r + 0.05));
    float band = pow(0.5 + 0.5 * arm, 2.5);

    // Drifting noise breaks the arms into wisps instead of clean sine bands.
    float cloud = galaxyNoise(p * 6.0 + float2(spin * 2.0, -spin));
    float nebula = band * exp(-r * 2.2) * (0.45 + 0.55 * cloud);

    float core = exp(-r * r * 34.0);

    // Two star layers at different scales read as parallax depth.
    float density = max(starDensity, 0.1);
    float stars = galaxyStars(p + 3.7, 16.0 * density, time)
                + galaxyStars(p * 1.9 + 7.3, 24.0 * density, time * 1.3) * 0.6;

    float3 col = float3(0.016, 0.014, 0.050)
               + mix(float3(0.44, 0.20, 0.86), float3(0.13, 0.62, 0.92), cloud) * nebula
               + float3(1.00, 0.90, 0.78) * core
               + float3(0.85, 0.90, 1.00) * stars;

    col = clamp(col * max(intensity, 0.0), 0.0, 1.0);

    // Premultiplied, and carrying the source alpha through unchanged.
    return half4(half3(col) * color.a, color.a);
}

/// color mode — diagonal specular sweep, the "loading shimmer" idiom.
/// uniforms: width, intensity, bounce
///
/// `bounce` >= 0.5 plays the sweep forward then backward (a triangle wave)
/// instead of restarting from the leading edge each pass (a sawtooth). The
/// rate halves with it so an individual pass travels at the same speed either
/// way — otherwise a round trip in one cycle would read as double speed.
[[stitchable]] half4 shimmer(float2 position,
                             half4 color,
                             float2 size,
                             float time,
                             float width,
                             float intensity,
                             float bounce)
{
    float2 uv = position / size;
    float band = uv.x + uv.y * 0.35;

    // 0.6 puts one pass at ~1.7s with speed=1, the range skeleton loaders
    // conventionally use; `speed` tunes from there.
    float pingPong = step(0.5, bounce);
    float saw = fract(time * mix(0.6, 0.3, pingPong));

    // Sweep the band head from off-screen leading to off-screen trailing.
    float phase = mix(saw, 1.0 - abs(saw * 2.0 - 1.0), pingPong);
    float head = phase * 2.0 - 0.5;

    float glow = smoothstep(width, 0.0, abs(band - head)) * intensity;

    // Colors arriving here are premultiplied, so scale the additive glow by
    // alpha to avoid haloing outside the shape.
    return color + half4(half3(glow), 0.0h) * color.a;
}
