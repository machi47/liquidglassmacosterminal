# Continuous integration

The `CI` workflow runs on GitHub's macOS runner and executes `Scripts/validate.sh`.

The gate covers:

- shell syntax and property-list validation
- all Swift unit tests
- release builds for `liquidglass` and `LiquidGlassAgent`
- direct compilation of `LiquidGlass.metal` to AIR
- AIR linkage into a Metal library
- rejection of bootstrap payloads and generated build artifacts

WindowServer composition, TCC prompts, multi-display geometry, and visual quality still require the physical-Mac checklist in `MACOS_VALIDATION.md`.
