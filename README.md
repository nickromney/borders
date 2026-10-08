# Borders

A small native macOS menu-bar app for a low-footprint focused-window border and
display-edge ring light. It uses vector `CAShapeLayer` overlays, keeps optional
camera sampling local and opt-in, and does not require Accessibility permission.

The current toolchain target is macOS 14 or newer, matching DocCam and the
AVFoundation external-camera APIs used by the optional feedback feature.

## Build and run

```sh
make build       # strict Debug build
make dev         # build, install in ~/Applications, and launch
make install     # build and install the Release app
```

## Layout

`BordersCore` holds the decisions: configuration parsing, settings and their
clamps, colour and overlay geometry, focused-window selection, app binding, and
the control socket. It imports no AppKit and is covered by unit tests. The
`Borders` executable is the shell around it: windows, layers, the menu, and the
engine that drives them.

## Test and quality gates

```sh
make test              # unit tests, then the strict Swift build
make unit-test         # unit tests only
make complexity        # fail on any function above the complexity ratchet
make mutation          # plan mutation testing without running it
make mutation-execute  # run the mutation cycle; nonzero exit when mutants survive
make keylight-hardware-test ARGS="--host elgato-key-light-air-6389.local"
```

`make complexity` uses `lizard` through `uvx` and fails when any function in
`Sources` exceeds `COMPLEXITY_THRESHOLD` (7). The ratchet only moves down.

`Scripts/mutation-test.sh` mutates `Sources/BordersCore` one operator at a time
and runs the suite against each mutant, restoring the file after every run. A
mutant that survives means the suite accepts a behaviour change, so the fix is a
sharper assertion rather than a lower target. The suite records the generated
mutant count and every surviving mutation in `.run/mutation/`; the quality gate
is zero unjustified survivors.

A mutant that hangs is killed by the per-run timeout (`--timeout`, 90 to 180
seconds). A line carrying a `mutation:skip` comment is excluded; that is only
for a mutant that provably cannot change behaviour, such as a boundary check on
a file descriptor that is never zero, and the reason is written on the line.

`make dist` writes the Release artifact to `dist/Borders.app`. `make install`
copies that artifact into `~/Applications` and then runs `make clean`, so
installation does not leave a second searchable app bundle or local build
artifacts. `make clean` removes local build and distribution artifacts.

The app is deliberately an accessory app (`LSUIElement`) when bundled. A
convenience bundle can be produced with `./Scripts/build-app.sh`.

After `make install`, open the Borders menu and enable `Open at Login`. This
uses macOS `SMAppService` and appears under System Settings → General → Login
Items & Extensions. Developer builds keep this control hidden so a temporary
`.build` bundle is not registered as a login item.

The menu controls focused-window mode, ring light mode, display selection,
width, brightness, colour, and an optional ring-light app binding. Live settings are stored in
`~/Library/Preferences/com.nickromney.borders.plist`; the portable baseline
is read from `~/.config/borders/borders.conf` and is never written by the UI.

Ring light mode creates one click-through overlay per selected display, so
dual-monitor setups can use either the main display, the display containing
the active window, or all displays. The light uses a bright white core with a
coloured multi-layer bloom; the bloom is padded outside the display frame so
it is not clipped at the edge.

To bind the ring light to an app, leave that app active, open the menu, and
choose `Bind to <app>`. The ring light then appears only while that app is the
frontmost app. `Clear app binding` restores an unbound light. `Neon bloom`
controls the layered halo independently of the focused-window border. A
configuration baseline can also set `ring_app=<bundle identifier>`.

The command-line client talks to the running app over a local Unix socket at
`/tmp/borders.sock`. Each command prints the resulting status line and exits 0,
except `quit`, which prints `quitting`. With no app running the client prints
`borders: app is not running` and exits 1. The
client gives up after two seconds rather than hanging if the app is wedged.

| Command | Effect |
| --- | --- |
| `on`, `focused` | Draw the border around the focused window |
| `ring`, `ring-light` | Switch to display-edge ring light mode |
| `off` | Hide every overlay, leaving the app running |
| `reload`, `reconcile` | Re-read `~/.config/borders/borders.conf` |
| `status` | Print the current settings without changing them |
| `quit` | Exit the app |

Mode changes are saved, so the app comes back in the same mode after a restart.

### Quitting

```sh
borders quit
```

`quit` replies `quitting` and the app exits a moment later, once the reply has
been written. Because it is a normal termination rather than a signal, AppKit
tears the overlay windows down itself instead of leaving them for the window
server to reclaim.

`make dev` uses this before installing a new build, and falls back to a signal
if the running copy does not answer, which is the case for any build older than
the `quit` command. `off` is the one to use to stop the overlays but keep the
menu bar item; `quit` removes the menu bar item too, and the app must then be
launched again from `~/Applications`.

## Key Lights

The app also provides a second menu-bar item for Elgato Wi-Fi lights. It uses
Bonjour (`_elg._tcp`) for discovery and the light's local HTTP API on port
`9123`; it does not install or launch Control Center and makes no telemetry
requests.

The popover provides power, brightness, and colour-temperature sliders for
each discovered Key Light, plus two warm low-light presets, four brightness
presets, and a daylight preset:

- `On - 5% (warm)` and `On - 10% (warm)` turn every discovered
  Key Light on at the selected brightness and 2900 K.
- `On - 15%`, `On - 30%`, `On - 50%`, and `On - 70%`
  turn every discovered Key Light on at the selected brightness while keeping
  each light's current colour temperature.
- `On - SAD Lamp` turns every discovered Key Light on at 100% and 7000 K, the
  coldest/full-output combination within the published Key Light range.
- The full-width `Lights Off` control turns off every discovered physical Key
  Light and remains marked pressed while they are off; choose any `Lights On`
  preset to turn them back on.
- While a light is on, the visible brightness control runs from 5% to 100%.
  The hardware's API value of 0% still emits light on this unit, so a true
  zero-brightness request is treated as power off; use the power switch or
  `Lights Off` for that state.
- Camera feedback is collapsed by default in the popover and can be expanded
  when needed.

The main Borders menu provides `Key Lights On (comes on at 5% warm)` and `Key Lights
Off` shortcuts for the physical lights. The separate Key Lights status item's
emergency context control remains overlay-aware.

Pairing is repeatable rather than treated as a one-time installation step. The
popover's pairing instructions never change the Mac's Wi-Fi automatically. To
initialise or reinitialise this Key Light Air, power it on, hold the rear reset
button next to the power cord for 10 seconds until it flashes three times,
release the button, power the light off, wait 10 seconds, and power it back on.
Join the temporary `Key Light XXXX` network in macOS Wi-Fi settings, and use
the light's local setup page at `http://192.168.62.1:9123/` to select the home
network. The original Key Light and Key Light Air use 2.4 GHz Wi-Fi only,
so select the 2.4 GHz SSID (for example, `Downstairs`) rather than its
`Downstairs5GHz` counterpart. The Mac may then return to Ethernet or the 5 GHz
SSID, provided
the router bridges both networks and client isolation is disabled. Return to
the popover and refresh discovery after the light rejoins the LAN. This same
flow works after reinstalling the app or moving the light to another Mac.

Elgato documents the Air's [2.4 GHz wireless limitation](https://help.elgato.com/hc/en-us/articles/360038093012-Key-Light-Air-Technical-Specifications).
These hardware steps correspond to Elgato's [Key Light Air reset guide](https://help.elgato.com/hc/en-us/articles/360051802572-Key-Light-Air-Reset-Wifi-Configuration)
and its [manual local setup flow](https://help.elgato.com/hc/en-us/articles/4413643069197-Elgato-Control-Center-Manually-Pair-Wi-Fi-Product-Windows).

If the light is already paired, open the existing Borders menu and choose
`Key Lights options…`; the separate bulb status item provides the same popover.

### Camera brightness feedback

`Camera feedback` is deliberately off by default. It is designed for the
Gawervan KB-1300-style document camera used by DocCam, which
macOS exposes as `USB Camera`; the selection policy prefers that camera over a
Logitech fallback. Turn it on in the Key Lights popover, choose the target
camera luminance, and point the camera's central view at the light.

The feedback path is local and bounded: it samples a central region rather
than saving frames, optionally locks and restores the camera exposure, averages
three readings, waits 1.5 seconds between adjustments, and changes brightness
by at most four percentage points at a time. The target is relative camera
luminance, not calibrated lux, so it is a repeatable control aid rather than a
photometric instrument. The sampler accepts the BGRA and bi-planar YUV formats
reported by this UVC camera. macOS may ask for Camera permission the first time.

Brightness and warmth slider writes are also latest-value coalesced and delayed
by 300 ms after the last movement. This prevents a drag from sending every
intermediate value to the light and gives the hardware time to settle. The
pure luminance, feedback, camera-selection, and write-coalescing policies live
in `BordersCore` so they can be reused and mutation-tested without hardware;
AVFoundation is only the adapter around those policies.

### Automated hardware verification

The separate `keylight-hardware-test` command is the repeatable, no-observer
check for the physical control contract. It discovers or addresses one Key
Light, selects the preferred `USB Camera`, locks exposure, and runs this
sequence:

1. power off;
2. issue the user-facing 0% command (which must also power off);
3. 5% warm minimum on;
4. 50% midpoint;
5. 100% maximum on.

It waits for each light state to settle, averages configurable camera samples,
checks that 0% matches power off and that the on-state readings are monotonic,
then restores the exact state captured at the start. It writes no frames and
never changes Wi-Fi.

```sh
make keylight-hardware-test \
  ARGS="--host elgato-key-light-air-6389.local --settle 1 --samples 5 --interval 0.3"
```

Omit `--host` to use Bonjour discovery. Use `--camera-id` when more than one
camera is connected, and `--json /path/report.json` for a machine-readable
report. The first run may require Camera permission for Borders; macOS must
also be unlocked so AVFoundation can deliver frames. The pure command plan,
configuration clamps, and evaluator are unit- and mutation-tested; the runner
is only the local Key Light/AVFoundation adapter.

See [docs/plans/n-borders-menubar-ring-light.md](docs/plans/n-borders-menubar-ring-light.md)
for the repository boundary and implementation plan copied from `n-dotfiles`.
