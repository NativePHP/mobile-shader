<?php

namespace Native\Mobile\Shader\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

class Shader extends NativeBladeComponent
{
    /**
     * Not self-closing: the shader wraps its children, which is what makes
     * `layer` and `distortion` modes useful (they sample the rendered
     * children). A shader with no children still works in `color` mode —
     * it just paints over an empty rect.
     */
    protected bool $isSelfClosing = false;

    protected function elementType(): string
    {
        return 'shader';
    }
}
