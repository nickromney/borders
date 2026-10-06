# Borders menu-bar and ring-light plan

Status: implemented foundation; current ownership and remaining work are described below. Reviewed against local source on 2026-10-06.

## Repository boundary

The menu-bar app is now this standalone project. It owns the Swift source,
SwiftPM build, app bundle metadata, tests, signing, and releases. The repository
boundary below records the implemented split from dotfiles.

The dotfiles repository retains only any machine integration layer that may be
needed later. It does not own app bundles, UI code, or build artifacts.

## What exists today

The original `Borders` executable owns a click-through overlay window with a
`CAShapeLayer`, listens to WindowServer notifications, and draws the focused
window ring without Accessibility or camera permissions. The shell entrypoint
remains useful for automation and recovery:

```text
borders on|off|status|reconcile
```

The current `borders.conf` remains the portable default configuration. The
menu-bar UI must not write through a managed config symlink when a slider is
moved.

## Menu-bar conversion

The standalone project contains a native `Borders.app` with `LSUIElement`, one
`NSStatusItem`, a `BorderEngine`, and a thin Unix-socket CLI. Menu actions cover
focused window, ring light, off, display selection, configuration reload, and
opening the configuration file. Runtime overrides live in the app-owned
preferences plist; the dotfiles config remains a portable baseline.

## Ring-light mode

Ring light is a separate renderer. It creates one transparent, click-through
overlay per selected display, draws a rounded rectangle inset by half the
configured stroke width, and bypasses focused-window fullscreen suppression.
The default width is 24 display points with an 8–40 point range. Brightness
drives a bright core plus layered coloured bloom, matching the visual intent
of the Windows reference instead of relying on a single translucent stroke.
Overlay rendering needs no camera capture or permission. The separate, implemented Key Light feedback feature is opt-in, requests camera permission, samples frames locally, and bounds brightness adjustments through BordersCore policy.

The display choices are main display, the display containing the active window,
or all displays. Each display gets its own overlay, which keeps dual-monitor
layouts independent and avoids treating the desktop as one large rectangle.
An optional app binding tracks the frontmost non-Borders application and hides
ring-light overlays while another app is active. The binding is persisted in
app-owned preferences; `ring_app=<bundle identifier>` is also accepted as a
portable baseline setting. Neon bloom is independently toggleable; focused
window mode remains the simple configured yellow border.

Display changes rebuild overlays. Safe-area insets keep the ring clear of a
notch/camera cutout, and overlays are excluded from screen capture.

## Historical implementation order

Steps 1–5 describe the implemented foundation. Dotfiles integration remains a
separate machine-integration decision; no runtime refactor is implied by this list.

1. Standalone SwiftPM project and focused-ring source.
2. Proper menu-bar app target and CLI compatibility.
3. App-owned runtime preferences separate from Stow defaults.
4. Ring-light geometry for single, multi-display, and notched displays.
5. Width, brightness, and colour controls.
6. Dotfiles integration after the install contract is stable.

## Workflow and evidence contract

Reviewed 6 October 2026. Commands below select existing verification seams;
attended hardware and native lifecycle claims retain their own evidence requirements.

| Decision | Owner | Smallest verification | Evidence and effects |
| --- | --- | --- | --- |
| Overlay decisions | Sources/BordersCore; Tests/BordersCoreTests | swift test | Pure geometry/configuration proof |
| Running overlay settings | Sources/NBorders/SocketServer.swift | borders status | Observed app settings; not physical light state |
| Physical Key Light behavior | Sources/NBorders/KeyLightStore.swift | Explicit hardware test only | Attended device proof; do not infer illumination from request success |
