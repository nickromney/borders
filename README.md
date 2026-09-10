# Borders

A small native macOS menu-bar app for a low-footprint focused-window border and
display-edge ring light. It uses vector `CAShapeLayer` overlays, has no camera
integration, and does not require Accessibility permission.

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
```

`make complexity` uses `lizard` through `uvx` and fails when any function in
`Sources` exceeds `COMPLEXITY_THRESHOLD` (7). The ratchet only moves down.

`Scripts/mutation-test.sh` mutates `Sources/BordersCore` one operator at a time
and runs the suite against each mutant, restoring the file after every run. A
mutant that survives means the suite accepts a behaviour change, so the fix is a
sharper assertion rather than a lower target. The current suite kills all 73
generated mutants. Reports land in `.run/mutation/`.

A mutant that hangs is killed by the per-run timeout (`--timeout`, 90 to 180
seconds). A line carrying a `mutation:skip` comment is excluded; that is only
for a mutant that provably cannot change behaviour, such as a boundary check on
a file descriptor that is never zero, and the reason is written on the line.

`make dist` writes the Release artifact to `dist/Borders.app`; `make clean`
removes local build and distribution artifacts.

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

See [docs/plans/n-borders-menubar-ring-light.md](docs/plans/n-borders-menubar-ring-light.md)
for the repository boundary and implementation plan copied from `n-dotfiles`.
