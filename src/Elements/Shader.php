<?php

namespace Native\Mobile\Shader\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Shader — wraps its children in a GPU fragment shader.
 *
 * PHP never touches a pixel. It names a shader function that was compiled
 * into the app at build time (`.metal` on iOS, AGSL source on Android) and
 * supplies its uniforms; the GPU runs the effect at display refresh rate
 * without a bridge round-trip per frame.
 *
 * ```blade
 * <native:shader name="ripple" mode="layer" animated speed="1.2"
 *                :uniforms="['amplitude' => 14, 'frequency' => 28]"
 *                class="w-full h-64">
 *     <native:image src="{{ $cover }}" />
 * </native:shader>
 * ```
 *
 * Modes map to the SwiftUI effect family (and their AGSL equivalents):
 *   layer      — samples the rendered children (warp, blur, melt). Default.
 *   distortion — displaces sample coordinates only.
 *   color      — recolors per pixel; ignores child geometry.
 *
 * IMPORTANT — uniform ORDER is the contract. Shader arguments are
 * positional, so the `uniforms` array must be declared in the same order
 * the shader function signature expects, after its implicit
 * `(size, time)` pair. Names are carried over the wire only so the
 * renderer can look each value back up; they are not matched by name
 * against the shader source.
 *
 * @phpstan-type UniformMap array<string, float|int>
 */
class Shader extends Element
{
    protected string $type = 'shader';

    /** @var array<string, mixed> */
    protected array $shaderProps = [];

    /** @var array<string, float> */
    protected array $uniforms = [];

    public static function make(string $name): static
    {
        return (new static)->name($name);
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['name'])) {
            $this->name((string) $attrs['name']);
        }

        if (isset($attrs['mode'])) {
            $this->mode((string) $attrs['mode']);
        }

        if (array_key_exists('animated', $attrs)) {
            $this->animated(filter_var($attrs['animated'], FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE) ?? true);
        }

        if (isset($attrs['speed'])) {
            $this->speed((float) $attrs['speed']);
        }

        if (isset($attrs['uniforms']) && is_array($attrs['uniforms'])) {
            $this->uniforms($attrs['uniforms']);
        }

        $this->applyA11yAttributes($attrs);
    }

    public function name(string $name): static
    {
        $this->shaderProps['name'] = $name;

        return $this;
    }

    /**
     * @param  'layer'|'distortion'|'color'  $mode
     */
    public function mode(string $mode): static
    {
        $this->shaderProps['mode'] = $mode;

        return $this;
    }

    /**
     * Drive the shader's `time` uniform natively. When false the shader
     * still renders, frozen at t=0 — the cheap way to park an effect
     * while its screen is backgrounded without unmounting it.
     */
    public function animated(bool $animated = true): static
    {
        $this->shaderProps['animated'] = $animated;

        return $this;
    }

    /**
     * Multiplier applied to elapsed time before it reaches the shader.
     */
    public function speed(float $speed): static
    {
        $this->shaderProps['speed'] = $speed;

        return $this;
    }

    /**
     * @param  UniformMap  $uniforms  Ordered; see the class docblock.
     */
    public function uniforms(array $uniforms): static
    {
        foreach ($uniforms as $key => $value) {
            $this->uniforms[(string) $key] = (float) $value;
        }

        return $this;
    }

    public function uniform(string $key, float $value): static
    {
        $this->uniforms[$key] = $value;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->shaderProps;

        // The wire format has no map type, so uniforms travel as an ordered
        // string list of names plus one f32 prop each. Arbitrary prop keys
        // are fine — unknown keys serialize with an inline string key.
        if ($this->uniforms !== []) {
            $props['uniform_names'] = array_keys($this->uniforms);

            foreach ($this->uniforms as $key => $value) {
                $props['u_'.$key] = $value;
            }
        }

        return $props;
    }
}
