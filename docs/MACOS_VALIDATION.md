# Physical Mac validation

CI validates compilation, tests, scripts, plists, release binaries, and the Metal shader. WindowServer composition and TCC must also be exercised on a real Mac.

## Baseline

```bash
./install.sh
liquidglass doctor --prompt
liquidglass on
liquidglass status
```

Confirm:

- the current terminal and a newly opened terminal both show live refraction
- terminal glyphs and cursor remain fully opaque and interactive
- moving another window behind Terminal changes the refracted scene
- `liquidglass off` restores the exact prior Terminal profile

## Optics

Test `subtle`, `balanced`, and `vivid` against:

- a pure black wallpaper with no window behind Terminal
- a colorful wallpaper
- text, browser, and video windows behind Terminal
- light and dark appearance

Reject simple opacity/blur behavior: straight high-contrast edges behind Terminal must visibly bend, RGB separation must appear under the vivid preset, and caustic/rim energy must remain visible on the black-desktop case.

## Window lifecycle

- create and close multiple windows and tabs
- drag continuously and resize from every edge
- minimize and restore
- enter/leave full screen
- switch Spaces and Stage Manager groups
- hide/show Terminal
- quit/relaunch Terminal while enabled

No orphan panel may remain after its Terminal window disappears.

## Displays

- Retina internal display
- one external display with different scale
- displays left, right, above, and below the main display
- drag a Terminal window across the display seam
- change display arrangement while enabled
- disconnect/reconnect an external display

A spanning window should use the correct scene on each side without a coordinate inversion.

## Performance

Run for 30 minutes with one, four, and eight Terminal windows. Record:

```bash
liquidglass status --json
ps -o pid,%cpu,rss,command -p "$(pgrep -f 'LiquidGlass.app/Contents/MacOS/LiquidGlassAgent' | head -1)"
```

Expected behavior:

- capture count equals the number of displays containing Terminal segments
- dropped frames may increase under load, but interaction latency must not accumulate
- no unbounded RSS growth
- Terminal input remains responsive during window movement

## Failure and recovery

- deny Screen Recording, run `liquidglass on`, and confirm automatic profile rollback
- grant Screen Recording and rerun `liquidglass on`
- deny Automation and confirm no persistent managed-profile mutation
- kill the CLI during enable and rerun `liquidglass off`
- kill the agent while enabled and confirm launchd restarts it
- reboot while enabled and verify the persisted state resumes
- uninstall while enabled and verify restoration occurs before files are deleted
