# Architecture

## Process model

`liquidglass` is a short-lived signed CLI bundle. It owns configuration, Terminal profile transactions, status, and diagnostics.

`LiquidGlass.app` is an `LSUIElement` LaunchAgent. It owns window tracking, display capture, GPU preprocessing, Metal rendering, and heartbeats. It remains loaded but does no capture or rendering while disabled.

## Data plane

### Window discovery

The agent reads ordinary Core Graphics window metadata and filters layer-zero windows by Terminal's PID. Quartz coordinates are retained for capture mapping; a corresponding AppKit rectangle is produced for panel placement.

### Display segmentation

Each Terminal window is intersected with every active display. A spanning window therefore receives one render panel per intersected display. The shader receives the full window size and each segment's origin so rounded-corner and edge optics remain continuous across display boundaries.

### Capture

`SCShareableContent` supplies `SCDisplay` and `SCRunningApplication` objects. Each required display gets one `SCStream` using an application-exclusion filter. Terminal, the agent, and the CLI are excluded to prevent feedback and to capture the scene that would exist behind Terminal.

The stream is configured at `renderScale` and emits BGRA `CVPixelBuffer` frames. A `CVMetalTextureCache` exposes each buffer as a Metal texture. A blit copies the frame into a private sharp texture, then `MPSImageGaussianBlur` produces a private blurred texture.

### Frame ownership

Each display has three sharp/blurred texture pairs. Capture only acquires a slot that is neither current, in flight, nor leased by a renderer. Render command buffers release leases in their completion handlers. When every slot is busy, the incoming capture frame is dropped instead of queued, preventing latency growth.

### Rendering

Each panel hosts an `MTKView`. A single fullscreen triangle invokes `LiquidGlass.metal`, which maps the panel segment to its display capture and evaluates:

- four-octave value-noise domain warping
- animated displacement gradients
- edge-directed lens displacement
- RGB-separated refraction
- clear/blurred optical mixing
- rounded-box signed-distance clipping
- Fresnel, specular, and caustic terms
- tint, saturation, and micro-grain

The shader emits premultiplied alpha. Panels are click-through, nonactivating, excluded from sharing, and repeatedly ordered directly beneath their corresponding Terminal window.

## Control plane

Configuration and state are atomically encoded as JSON. A distributed notification asks the agent to reload. Capture streams rebuild only when render scale, capture FPS, blur sigma, or active-display membership changes; other shader parameters update the renderer in place.

## Terminal aperture

The CLI clones the current default Terminal profile and changes only its background color alpha and background blur. Fonts, ANSI colors, shell commands, keyboard mappings, scrollback, and text opacity remain inherited from the source profile. Apple Events apply the managed profile to open tabs and later restore their previous profiles.

## Permission identities

The installer creates two ad-hoc signed app bundles:

- `com.machi47.LiquidGlassAgent` for Screen Recording
- `com.machi47.LiquidGlassCLI` for Terminal Automation

Stable bundle identities prevent every source rebuild from appearing as a completely unrelated executable to TCC, although ad-hoc signing is still intended for local installation rather than public notarized distribution.

## Application packaging

The Metal source is deliberately packaged by `Scripts/build-app-bundles.sh` as `LiquidGlass.app/Contents/Resources/LiquidGlass.metal` rather than relying on SwiftPM's development-time resource-bundle location. `ShaderSourceLocator` resolves that installed path and exposes a non-UI `--validate-resources` probe, which CI executes from inside the signed app bundle before installation is considered valid.
