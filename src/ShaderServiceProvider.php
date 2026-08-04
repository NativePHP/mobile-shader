<?php

namespace Native\Mobile\Shader;

use Illuminate\Support\ServiceProvider;
use Native\Mobile\Shader\Commands\EnsureMetalToolchainCommand;

class ShaderServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        if ($this->app->runningInConsole()) {
            // Invoked by the plugin compiler's copy_assets stage, by name.
            $this->commands([
                EnsureMetalToolchainCommand::class,
            ]);
        }
    }
}
