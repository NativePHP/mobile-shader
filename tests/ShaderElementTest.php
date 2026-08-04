<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\Elements\Image;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Edge\TailwindParser;
use Native\Mobile\Shader\Elements\Shader;

/**
 * Attribute → wire-prop behavior, driven through core's
 * NativeElementCollector exactly as compiled Blade drives it.
 */
beforeEach(function () {
    NativeElementCollector::reset();
    TailwindParser::clearCache();
    ElementRegistry::reset();
    ElementRegistry::register('shader', Shader::class);
    ElementRegistry::register('image', Image::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

function collectShader(array $attrs): array
{
    NativeElementCollector::leaf('shader', $attrs);

    return NativeElementCollector::collect()->toArray(new CallbackRegistry);
}

it('serializes the shader name and mode', function () {
    $tree = collectShader(['name' => 'ripple', 'mode' => 'layer']);

    expect($tree['type'])->toBe('shader');
    expect($tree['props']['name'])->toBe('ripple');
    expect($tree['props']['mode'])->toBe('layer');
});

it('flattens uniforms into an ordered name list plus float props', function () {
    // Order is the contract with the iOS renderer — shader arguments are
    // positional, so uniform_names must preserve declaration order.
    $tree = collectShader([
        'name' => 'ripple',
        'uniforms' => ['amplitude' => 14, 'frequency' => 28],
    ]);

    expect($tree['props']['uniform_names'])->toBe(['amplitude', 'frequency']);
    expect($tree['props']['u_amplitude'])->toBe(14.0);
    expect($tree['props']['u_frequency'])->toBe(28.0);
});

it('coerces integer uniforms to floats for the f32 wire type', function () {
    $tree = collectShader(['name' => 'ripple', 'uniforms' => ['amplitude' => 14]]);

    expect($tree['props']['u_amplitude'])->toBeFloat();
});

it('treats a bare animated attribute as enabled', function () {
    $tree = collectShader(['name' => 'ripple', 'animated' => true]);

    expect($tree['props']['animated'])->toBeTrue();
});

it('allows animation to be switched off', function () {
    $tree = collectShader(['name' => 'ripple', 'animated' => 'false']);

    expect($tree['props']['animated'])->toBeFalse();
});

it('carries speed as a float', function () {
    $tree = collectShader(['name' => 'ripple', 'speed' => '1.5']);

    expect($tree['props']['speed'])->toBe(1.5);
});

it('omits the uniform list entirely when none are declared', function () {
    $tree = collectShader(['name' => 'shimmer']);

    expect($tree['props'])->not->toHaveKey('uniform_names');
});

it('builds the same props fluently', function () {
    $props = Shader::make('ripple')
        ->mode('distortion')
        ->speed(2.0)
        ->uniform('amplitude', 8.0)
        ->toArray(new CallbackRegistry)['props'];

    expect($props['name'])->toBe('ripple');
    expect($props['mode'])->toBe('distortion');
    expect($props['speed'])->toBe(2.0);
    expect($props['uniform_names'])->toBe(['amplitude']);
    expect($props['u_amplitude'])->toBe(8.0);
});

it('wraps children so layer mode has something to sample', function () {
    NativeElementCollector::open('shader', ['name' => 'ripple']);
    NativeElementCollector::leaf('image', ['src' => 'cover.png']);
    NativeElementCollector::close();

    $tree = NativeElementCollector::collect()->toArray(new CallbackRegistry);

    expect($tree['type'])->toBe('shader');
    expect($tree['children'])->toHaveCount(1);
    expect($tree['children'][0]['type'])->toBe('image');
});
