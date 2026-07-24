# LiquidGlass macOS Terminal

A real-time **ScreenCaptureKit + Metal** liquid-glass compositor for Apple's normal `Terminal.app`.

It does not replace Terminal, your shell, the PTY, text rendering, keyboard handling, tabs, scrollback, or command history. It creates a GPU-rendered glass surface immediately behind each Terminal window and temporarily gives Terminal a managed transparent-background profile so the surface is visible through the ordinary terminal window.

```bash
liquidglass on
liquidglass off
```

The setting persists across new Terminal windows and logins.

## What is actually rendered

This is not a Terminal opacity preset. The live path is:

```text
Desktop and windows behind Terminal
        │
        ├─ ScreenCaptureKit: one excluded-app stream per active display
        │      Terminal.app and LiquidGlass.app are excluded
        │
        ├─ Core Video → Metal texture without a CPU image conversion
        │
        ├─ private triple-buffered GPU frame pool
        │
        ├─ MPS Gaussian blur once per display frame
        │
        └─ custom Metal fragment shader per Terminal/display segment
               animated domain-warped refraction
               chromatic dispersion
               clear/blurred optical mixing
               rounded continuous edge lens
               Fresnel and specular response
               caustic energy
               saturation, tint, and micro-grain
```

A click-through `NSPanel` is ordered directly below every Terminal window. Windows spanning multiple displays are split into display-local render segments, so each part samples the correct display capture.

## Requirements

- macOS 15 or newer
- Apple Silicon or an Intel Mac with Metal support
- Xcode Command Line Tools or Xcode with Swift available
- Screen Recording permission for `LiquidGlass.app`
- one-time Automation permission for the LiquidGlass CLI to apply and restore Terminal profiles

No SIP changes, injection, private WindowServer hooks, or replacement terminal emulator are used.

## Install

```bash
git clone https://github.com/machi47/liquidglassmacosterminal.git
cd liquidglassmacosterminal
./install.sh
```

The installer builds release binaries, creates ad-hoc signed app bundles with stable macOS permission identities, installs a per-user LaunchAgent, and places `liquidglass` in `/usr/local/bin` by default.

Then perform the one-time permission setup and enable it:

```bash
liquidglass doctor --prompt
liquidglass on
```

macOS may require the agent to restart after Screen Recording is approved. When that happens, rerun `liquidglass on`; failed enables roll Terminal back to its prior profiles instead of leaving a transparent window without a renderer.

## Everyday use

```bash
liquidglass on
liquidglass off
liquidglass toggle
liquidglass status
liquidglass doctor --prompt
```

The requested aliases are also accepted:

```bash
liquidglass -on
liquidglass -off
```

`on` and `off` are idempotent. State-changing commands use an interprocess lock, and profile changes are backed up before Terminal is mutated.

## Appearance

Three complete optical presets are included:

```bash
liquidglass config preset subtle
liquidglass config preset balanced
liquidglass config preset vivid
```

Live shader tuning:

```bash
liquidglass config set \
  --refraction 20 \
  --dispersion 2.2 \
  --blur 18 \
  --edge 1.0 \
  --caustics 0.55 \
  --tint '#07101F35'
```

Useful controls:

| Option | Range | Meaning |
|---|---:|---|
| `--render-scale` | `0.25...1` | Per-display capture/render resolution multiplier |
| `--capture-fps` | `10...60` | ScreenCaptureKit frame rate |
| `--render-fps` | `15...120` | MTKView presentation target |
| `--blur` | `0...40` | Shared MPS Gaussian sigma |
| `--refraction` | `0...60` | Optical displacement in screen pixels |
| `--dispersion` | `0...8` | RGB channel separation |
| `--flow-scale` | `0.25...12` | Liquid field spatial scale |
| `--flow-speed` | `0...2` | Liquid animation speed |
| `--edge` | `0...3` | Rim-lens and highlight energy |
| `--caustics` | `0...2` | Moving caustic contribution |
| `--saturation` | `0...2` | Refracted-scene saturation |
| `--corner-radius` | `0...80` | Full-window rounded SDF radius |
| `--grain` | `0...0.15` | Fine optical micro-grain |
| `--terminal-opacity` | `0...0.20` | Terminal background aperture only |

A black desktop still shows the material through edge refraction, caustics, highlights, tint, and any windows behind Terminal; the effect does not rely exclusively on a colorful wallpaper.

## Performance design

- one ScreenCaptureKit stream per display, not per terminal window
- display output scaled before GPU preprocessing
- one MPS blur pass shared by every terminal segment on that display
- Core Video to `MTLTexture` without CPU image conversion
- private triple-buffered sharp and blurred textures
- frame leases prevent capture from overwriting a texture still used by a renderer
- bounded frame admission drops work instead of building latency
- one fullscreen triangle and no per-frame vertex allocation
- configuration changes apply live; capture streams restart only when capture-scale/FPS/blur parameters change
- no polling when LiquidGlass is disabled or Terminal is not running

## Restoration and failure behavior

Before enabling, the CLI records:

- Terminal's previous default and startup profiles
- any pre-existing profile using the managed profile name
- each open tab's current profile and TTY when available

`liquidglass off` restores those values and moves tabs created while enabled away from the managed profile. If renderer startup, permission, or profile application fails, the enable transaction attempts the same rollback automatically and retains recovery state when restoration is incomplete.

State and logs live under:

```text
~/Library/Application Support/LiquidGlass/
```

Agent errors:

```bash
tail -f "$HOME/Library/Application Support/LiquidGlass/Logs/agent-error.log"
```

## Uninstall

```bash
./uninstall.sh
```

Uninstall first runs `liquidglass off` and stops if Terminal restoration fails.

## Development

```bash
./Scripts/validate.sh
```

The validation gate runs unit tests, release builds both executables, validates shell/plist files, and compiles plus links the Metal shader with the selected macOS SDK.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/MACOS_VALIDATION.md](docs/MACOS_VALIDATION.md).
