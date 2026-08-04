<?php

namespace Native\Mobile\Shader\Commands;

use Illuminate\Support\Facades\Process;
use Native\Mobile\Plugins\Commands\NativePluginHookCommand;

/**
 * copy_assets hook — keeps a missing Metal toolchain from breaking the build.
 *
 * Xcode 26 moved the Metal compiler into an optional downloadable component.
 * Without it, `CompileMetalFile` fails the whole build with an error that says
 * nothing about this plugin, which is a miserable first run for anyone who just
 * ran `composer require`.
 *
 * A hook cannot abort a build — a non-zero exit only logs a warning — so this
 * does the opposite: it removes the shader source when it can't be compiled.
 * The app then builds and runs normally, and `<native:shader>` renders its
 * children unstyled (the Swift renderer falls back when no metallib exists).
 *
 * Set NATIVEPHP_SHADER_AUTO_DOWNLOAD_TOOLCHAIN=true to have this fetch the
 * toolchain instead (~690 MB). It is opt-in because a download that size is a
 * surprising thing for a build to start on its own.
 */
class EnsureMetalToolchainCommand extends NativePluginHookCommand
{
    protected $signature = 'nativephp:shader:ensure-metal-toolchain';

    protected $description = 'Verify the Metal toolchain is available before the shaders are compiled';

    public function handle(): int
    {
        // Android compiles AGSL from a string at runtime — nothing to check.
        if (! $this->isIos()) {
            return self::SUCCESS;
        }

        if ($this->metalToolchainAvailable()) {
            return self::SUCCESS;
        }

        $this->components->warn('Metal toolchain not installed — Xcode 26 ships it as a separate component.');

        if ($this->shouldAutoDownload() && $this->downloadToolchain()) {
            return self::SUCCESS;
        }

        $this->disableShaders();

        return self::SUCCESS;
    }

    /**
     * `xcrun metal` resolves to a stub when the component is absent, so probe
     * by running it rather than by checking that the binary exists.
     */
    protected function metalToolchainAvailable(): bool
    {
        if (PHP_OS_FAMILY !== 'Darwin') {
            return false;
        }

        return Process::run('xcrun metal --version')->successful();
    }

    protected function shouldAutoDownload(): bool
    {
        return filter_var(
            env('NATIVEPHP_SHADER_AUTO_DOWNLOAD_TOOLCHAIN', false),
            FILTER_VALIDATE_BOOLEAN
        );
    }

    protected function downloadToolchain(): bool
    {
        $this->components->info('Downloading the Metal toolchain (~690 MB), this only happens once…');

        Process::forever()
            ->run('xcodebuild -downloadComponent MetalToolchain', function (string $type, string $output) {
                $this->output->write($output);
            });

        if ($this->metalToolchainAvailable()) {
            $this->components->info('Metal toolchain installed.');

            return true;
        }

        $this->components->error('Metal toolchain download did not complete.');

        return false;
    }

    /**
     * Drop the copied shader source so the build doesn't die on
     * CompileMetalFile. Shaders stay inert until the toolchain is installed
     * and the app is rebuilt.
     */
    protected function disableShaders(): void
    {
        $metal = $this->buildPath().'/NativePHP/Resources/NativeShaders.metal';

        if (is_file($metal)) {
            unlink($metal);
        }

        $this->components->warn('Shader effects are disabled for this build; <native:shader> will render its children unchanged.');
        $this->components->info('To enable them: xcodebuild -downloadComponent MetalToolchain, then rebuild.');
    }
}
