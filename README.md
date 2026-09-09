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

`make dist` writes the Release artifact to `dist/Borders.app`; `make clean`
removes local build and distribution artifacts.

The app is deliberately an accessory app (`LSUIElement`) when bundled. A
convenience bundle can be produced with `./Scripts/build-app.sh`.

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

The command-line client talks to the running app over a local Unix socket:

```text
borders on|off|status|reconcile
```

See [docs/plans/n-borders-menubar-ring-light.md](docs/plans/n-borders-menubar-ring-light.md)
for the repository boundary and implementation plan copied from `n-dotfiles`.
