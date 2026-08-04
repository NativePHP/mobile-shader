# NativePHP Mobile — Shader

GPU shader effects as a native EDGE element. Metal on iOS, AGSL on Android.

```blade
<native:shader name="ripple" animated speed="1.2"
               :uniforms="['amplitude' => 14, 'frequency' => 28]"
               class="w-full h-64">
    <native:image src="{{ $cover }}" />
</native:shader>
```

PHP never touches a pixel. It names a shader function and supplies its
uniforms; the GPU runs the effect at display refresh rate. Time is generated
natively — nothing about animation crosses the bridge.

## Installation

```bash
composer require nativephp/mobile-shader
php artisan vendor:publish --tag=nativephp-plugins-provider   # once, before the first plugin
php artisan native:plugin:register nativephp/mobile-shader
php artisan native:plugin:list                                # verify
```

Then rebuild (`php artisan native:run ios` / `android`) — native code only
compiles in at build time.

### The Metal toolchain (iOS, Xcode 26+)

Xcode 26 ships the Metal compiler as a separate downloadable component. Without
it, `CompileMetalFile` would fail the whole build with an error that never
mentions this plugin.

A `copy_assets` hook handles that: if the toolchain is missing it removes the
shader source, so **the build still succeeds and the app still runs** —
`<native:shader>` just renders its children unchanged. You get a clear warning
telling you what to run:

```bash
xcodebuild -downloadComponent MetalToolchain   # ~690 MB, once per machine
```

Set `NATIVEPHP_SHADER_AUTO_DOWNLOAD_TOOLCHAIN=true` to have the hook download it
for you instead. That's opt-in — a build shouldn't start a 690 MB download
without being asked.

## Attributes

| Attribute  | Type   | Default | Notes |
|---|---|---|---|
| `name`     | string | —       | Shader function name. Unknown names render the children unmodified. |
| `mode`     | string | `layer` | `layer`, `distortion`, or `color`. |
| `animated` | bool   | `true`  | `false` freezes the shader at `time = 0` without unmounting it. |
| `speed`    | float  | `1.0`   | Multiplier applied to elapsed time. |
| `uniforms` | array  | `[]`    | Ordered map of uniform name → float. |

Modes map to the SwiftUI effect family and their AGSL equivalents:

- **layer** — samples the rendered children (warp, melt, refract)
- **distortion** — displaces sample coordinates only
- **color** — recolors per pixel, ignoring child geometry

## Bundled shaders

| Name               | Mode       | Uniforms (in order) | |
|---|---|---|---|
| `ripple`           | layer      | `amplitude`, `frequency` | Radial wave |
| `rippleDistortion` | distortion | `amplitude`, `frequency` | The same wave as a displacement |
| `pixelate`         | layer      | `cellSize`, `blend`      | Mosaic; `blend` fades back to the original |
| `swirl`            | distortion | `strength`, `radius`     | Twist, unwinding at `radius` points |
| `aurora`           | color      | `spread`, `intensity`    | Drifting colour blobs — a background panel |
| `galaxy`           | color      | `twist`, `starDensity`, `intensity`, `spin` | Spiral nebula, twinkling starfield — a full-bleed backdrop |
| `shimmer`          | color      | `width`, `intensity`, `bounce` | Sweeping band — the skeleton-loading idiom |

`shimmer`'s `bounce` plays the sweep forward then backward (`>= 0.5`) instead of
restarting from the leading edge each pass. Its rate halves to match, so a single
pass travels at the same speed either way.

`pixelate` ignores `time` — a shader doesn't have to animate.

### Skeleton shimmer: wrap the bars, not the panel

Because `shimmer` scales its glow by the incoming alpha, it self-masks — put
*only* the placeholder shapes inside it and the transparent gaps between them
stay untouched, so each bar shimmers rather than the whole card:

```blade
<native:row class="w-full h-32 items-center rounded-2xl bg-theme-surface p-5">
    <native:shader name="shimmer" mode="color" animated
                   :uniforms="['width' => 0.16, 'intensity' => 0.7]" class="w-full h-full">
        <native:row class="w-full h-full items-center gap-4">
            <native:column class="w-14 h-14 rounded-full bg-theme-outline" />
            <native:column class="flex-1 h-3 rounded-full bg-theme-outline" />
        </native:row>
    </native:shader>
</native:row>
```

Move `bg-theme-surface` inside the shader and every pixel becomes opaque, so the
entire panel lights up like a spotlight instead. Keeping one shader over the
whole row (rather than one per bar) also gives the band a single coordinate
space, so it crosses the bars in sequence instead of pulsing them in lockstep.

**Colour shaders must preserve the incoming alpha.** They recolour pixels that
already exist; they cannot paint behind them. Returning a hardcoded `1.0` alpha
turns every transparent pixel opaque, which paints filled boxes around each text
run and squares off rounded corners. So a background like `aurora` wraps a plain
opaque panel, with the real content layered over it as a sibling:

```blade
<native:stack class="w-full h-64">
    <native:shader name="aurora" mode="color" animated :uniforms="['spread' => 0.45, 'intensity' => 1.0]" class="w-full h-full">
        <native:column class="w-full h-full rounded-2xl bg-theme-surface" />
    </native:shader>

    <native:column class="w-full h-full items-center justify-center p-6">
        <native:text>Readable, on top of the gradient</native:text>
    </native:column>
</native:stack>
```

**A shader belongs to exactly one mode.** On iOS the three effect families take
different Metal signatures — `half4 f(float2, SwiftUI::Layer, …)` for layer,
`float2 f(float2, …)` for distortion, `half4 f(float2, half4, …)` for color — and
a mismatch renders nothing at all rather than erroring. That's why `ripple` and
`rippleDistortion` exist as separate entry points over identical math. AGSL has
no such split, so both names map to one source on Android.

## Adding a shader

Shaders are authored twice — once per platform. They are close enough that
porting is mechanical, but it is two files:

1. **iOS** — add a `[[stitchable]]` function to `resources/ios/NativeShaders.metal`.
   The renderer always passes `(size, time)` first, then the element's uniforms
   **in declaration order**; Metal shader arguments are positional.

   Keep everything in that one file. The plugin compiler copies `.swift` sources
   automatically but not `.metal`, so the shader file ships through an explicit
   `assets` entry in `nativephp.json` — a second `.metal` file would need its own
   entry, and silently renders nothing if you forget.
2. **Android** — add the AGSL source to `ShaderCatalog` in
   `resources/android/ShaderRenderer.kt`. AGSL uniforms are set **by name**, so
   the `uniform float …` declarations must match the names used in Blade.

Keeping both in sync is the maintenance cost of the element. The names-and-order
overlap means a Blade snippet that is correct on one platform is correct on both.

## Constraints worth knowing

- **A blank box means the shader function wasn't found.** SwiftUI has no way to
  probe `ShaderLibrary` for a name, so a missing or misspelled function makes the
  effect draw nothing rather than error. If the element reserves its space but
  renders empty, check that `NativeShaders.metal` reached
  `nativephp/ios/NativePHP/Resources/`.
- **Metal is compiled at build time.** Shader source cannot be shipped over the
  air from PHP, and editing a `.metal` file does not hot-reload — it needs a full
  `native:run`. (AGSL compiles from a string at runtime, so Android could accept
  source from PHP; the element deliberately does not, to keep one contract.)
- **Android requires API 33+** (`RuntimeShader`). Below Tiramisu the element
  renders its children unmodified.
- **iOS requires 17+** for SwiftUI shader effects. Below that, likewise unmodified.
- **Hit-testing does not follow the distortion.** Displaced pixels move; touch
  geometry does not. Fine for decoration, wrong for controls.
- **Do not put an animated shader inside a scrolling list.** `layerEffect` forces
  an offscreen pass per frame.
- **Battery.** A full-screen animated shader pins the GPU. Bind `animated` to
  screen state and switch it off when the effect isn't visible.

## Requirements

- `nativephp/mobile` ^4.0
- iOS 17+ / Android 13+ for the effect itself (older versions degrade gracefully)
