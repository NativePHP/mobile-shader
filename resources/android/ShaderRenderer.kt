package com.nativephp.plugins.shader.ui

import android.os.Build
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.IntSize
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.NodeView

/**
 * Renderer for `<native:shader>` on Android.
 *
 * The counterpart to iOS's Metal path is AGSL via [android.graphics.RuntimeShader],
 * which is API 33+. Below Tiramisu — and for any shader name not in the
 * catalog — this falls through to the plain children, so a screen using a
 * shader for decoration still renders correctly on older devices.
 *
 * Two deliberate differences from iOS:
 *  - AGSL compiles from a string at runtime, so shaders live in [ShaderCatalog]
 *    rather than in a compiled library.
 *  - AGSL uniforms are set BY NAME, so the uniform names declared in Blade
 *    must match the `uniform float ...` declarations below. (On iOS only the
 *    order matters.) Keep both in sync.
 */
object ShaderRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val props = node.props
        val name = props.getString("name", "")
        val animated = props.getBool("animated", true)
        val speed = props.getFloat("speed", 1f)
        val uniformNames = props.getStringList("uniform_names")

        val source = ShaderCatalog.agsl(name)

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || source == null) {
            Children(node, modifier)
            return
        }

        val shader = remember(source) { android.graphics.RuntimeShader(source) }
        var size by remember { mutableStateOf(IntSize.Zero) }
        var time by remember { mutableFloatStateOf(0f) }

        // Drive time off the Compose frame clock, not off PHP. Restarts
        // whenever `animated` flips so parking an effect costs one recompose.
        LaunchedEffect(animated, speed) {
            if (!animated) {
                time = 0f
                return@LaunchedEffect
            }

            val start = withFrameNanos { it }
            while (true) {
                withFrameNanos { now ->
                    time = (now - start) / 1_000_000_000f * speed
                }
            }
        }

        shader.setFloatUniform("size", size.width.toFloat(), size.height.toFloat())
        shader.setFloatUniform("time", time)
        uniformNames.forEach { uniform ->
            shader.setFloatUniform(uniform, props.getFloat("u_$uniform", 0f))
        }

        Box(
            modifier = modifier
                .onSizeChanged { size = it }
                .graphicsLayer {
                    renderEffect = android.graphics.RenderEffect
                        .createRuntimeShaderEffect(shader, "content")
                        .asComposeRenderEffect()
                }
        ) {
            node.children.forEach { child ->
                NodeView(node = child)
            }
        }
    }

    @Composable
    private fun Children(node: NativeUINode, modifier: Modifier) {
        Box(modifier = modifier.fillMaxSize()) {
            node.children.forEach { child ->
                NodeView(node = child)
            }
        }
    }
}

/**
 * AGSL ports of the Metal shaders in `resources/ios/NativeShaders.metal`.
 * Every shader takes the `content` sampler that
 * `createRuntimeShaderEffect(shader, "content")` binds to the composed
 * children, so the same Blade markup works on both platforms.
 */
object ShaderCatalog {
    fun agsl(name: String): String? = when (name) {
        // AGSL has a single mechanism — every shader gets the `content`
        // sampler and returns a color — so the layer/distortion split that
        // Metal enforces collapses to one source here. Both names are kept
        // so the same Blade markup resolves on both platforms.
        "ripple", "rippleDistortion" -> RIPPLE
        "pixelate" -> PIXELATE
        "swirl" -> SWIRL
        "aurora" -> AURORA
        "galaxy" -> GALAXY
        "shimmer" -> SHIMMER
        else -> null
    }

    private val RIPPLE = """
        uniform shader content;
        uniform float2 size;
        uniform float time;
        uniform float amplitude;
        uniform float frequency;

        half4 main(float2 position) {
            float2 uv = position / size;
            float2 delta = uv - float2(0.5, 0.5);
            float dist = length(delta);

            float falloff = smoothstep(0.75, 0.0, dist);
            float wave = sin(dist * frequency - time) * amplitude * falloff;

            float2 direction = dist > 1e-4 ? delta / dist : float2(0.0);

            return content.eval(position + direction * wave);
        }
    """.trimIndent()

    private val PIXELATE = """
        uniform shader content;
        uniform float2 size;
        uniform float time;
        uniform float cellSize;
        uniform float blend;

        half4 main(float2 position) {
            float cell = max(cellSize, 1.0);
            float2 snapped = floor(position / cell) * cell + cell * 0.5;

            half4 blocky = content.eval(snapped);
            half4 original = content.eval(position);

            return mix(original, blocky, half(clamp(blend, 0.0, 1.0)));
        }
    """.trimIndent()

    private val SWIRL = """
        uniform shader content;
        uniform float2 size;
        uniform float time;
        uniform float strength;
        uniform float radius;

        half4 main(float2 position) {
            float2 centre = size * 0.5;
            float2 delta = position - centre;

            float r = max(radius, 1.0);
            float angle = strength * smoothstep(r, 0.0, length(delta));

            float s = sin(angle);
            float c = cos(angle);

            float2 rotated = float2(
                delta.x * c - delta.y * s,
                delta.x * s + delta.y * c
            );

            return content.eval(centre + rotated);
        }
    """.trimIndent()

    private val AURORA = """
        uniform shader content;
        uniform float2 size;
        uniform float time;
        uniform float spread;
        uniform float intensity;

        half4 main(float2 position) {
            half4 color = content.eval(position);

            float2 uv = position / size;
            float s = max(spread, 0.05);

            float2 a = float2(0.50 + 0.35 * sin(time * 0.50), 0.35 + 0.25 * cos(time * 0.40));
            float2 b = float2(0.30 + 0.30 * cos(time * 0.30), 0.70 + 0.20 * sin(time * 0.60));
            float2 c = float2(0.75 + 0.20 * sin(time * 0.70), 0.50 + 0.30 * cos(time * 0.50));

            float wa = exp(-dot(uv - a, uv - a) / (s * s));
            float wb = exp(-dot(uv - b, uv - b) / (s * s));
            float wc = exp(-dot(uv - c, uv - c) / (s * s));

            half3 gradient = half3(wa) * half3(0.30, 0.42, 0.95)
                           + half3(wb) * half3(0.95, 0.35, 0.65)
                           + half3(wc) * half3(0.30, 0.85, 0.75);

            gradient = clamp(gradient * half(intensity), 0.0, 1.0);

            // Preserve the source alpha — forcing it to 1 paints opaque boxes
            // around every text run and squares off rounded corners.
            return half4(gradient * color.a, color.a);
        }
    """.trimIndent()

    private val GALAXY = """
        uniform shader content;
        uniform float2 size;
        uniform float time;
        uniform float twist;
        uniform float starDensity;
        uniform float intensity;

        float galaxyHash(float2 p) {
            return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
        }

        float galaxyNoise(float2 p) {
            float2 i = floor(p);
            float2 f = fract(p);
            float2 u = f * f * (3.0 - 2.0 * f);

            return mix(mix(galaxyHash(i),                    galaxyHash(i + float2(1.0, 0.0)), u.x),
                       mix(galaxyHash(i + float2(0.0, 1.0)), galaxyHash(i + float2(1.0, 1.0)), u.x),
                       u.y);
        }

        float galaxyStars(float2 p, float cells, float t) {
            float2 g = p * cells;
            float2 cell = floor(g);
            float2 f = fract(g) - 0.5;

            float h = galaxyHash(cell);
            float2 offset = float2(galaxyHash(cell + 19.19), galaxyHash(cell + 47.31)) - 0.5;

            float d = length(f - offset * 0.7);
            float twinkle = 0.6 + 0.4 * sin(t * (1.0 + h * 4.0) + h * 41.0);

            return smoothstep(0.12, 0.0, d) * step(0.8, h) * twinkle;
        }

        half4 main(float2 position) {
            half4 color = content.eval(position);

            float2 p = (position - 0.5 * size) / min(size.x, size.y);

            float r = length(p);
            // AGSL is GLSL-flavoured: two-argument atan(), not atan2().
            float theta = atan(p.y, p.x);
            float spin = time * 0.05;

            float arm = cos(2.0 * (theta + spin) - twist * log(r + 0.05));
            float band = pow(0.5 + 0.5 * arm, 2.5);

            float cloud = galaxyNoise(p * 6.0 + float2(spin * 2.0, -spin));
            float nebula = band * exp(-r * 2.2) * (0.45 + 0.55 * cloud);

            float core = exp(-r * r * 34.0);

            float density = max(starDensity, 0.1);
            float stars = galaxyStars(p + 3.7, 16.0 * density, time)
                        + galaxyStars(p * 1.9 + 7.3, 24.0 * density, time * 1.3) * 0.6;

            float3 col = float3(0.016, 0.014, 0.050)
                       + mix(float3(0.44, 0.20, 0.86), float3(0.13, 0.62, 0.92), cloud) * nebula
                       + float3(1.00, 0.90, 0.78) * core
                       + float3(0.85, 0.90, 1.00) * stars;

            col = clamp(col * max(intensity, 0.0), 0.0, 1.0);

            // Preserve the source alpha — see AURORA.
            return half4(half3(col) * color.a, color.a);
        }
    """.trimIndent()

    private val SHIMMER = """
        uniform shader content;
        uniform float2 size;
        uniform float time;
        uniform float width;
        uniform float intensity;
        uniform float bounce;

        half4 main(float2 position) {
            half4 color = content.eval(position);

            float2 uv = position / size;
            float band = uv.x + uv.y * 0.35;

            float pingPong = step(0.5, bounce);
            float saw = fract(time * mix(0.6, 0.3, pingPong));
            float phase = mix(saw, 1.0 - abs(saw * 2.0 - 1.0), pingPong);
            float head = phase * 2.0 - 0.5;

            float glow = smoothstep(width, 0.0, abs(band - head)) * intensity;

            return color + half4(half3(glow), 0.0) * color.a;
        }
    """.trimIndent()
}
