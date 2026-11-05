# Cursor Halo

Cursor Pro style mouse highlighter for the Omarchy bar. A glowing shape
(Circle / Rhombus / Rounded) follows the cursor for demos and screencasts,
with a color flash + expanding ripple on click and an optional spotlight dim.

- **Bar icon (`◎`):** left-click toggles the halo, right-click opens settings.
- **Popup:** shape, color, size (S/M/L/XL), border weight, left/right click
  colors, show mode (Always / On move), spotlight dim, ripple.
- **Click flash:** needs the Hyprland click bridge (non-consuming binds, the
  click still reaches the app). Install it once:

```bash
bash ~/.config/omarchy/plugins/nickmdrummer.cursor-halo/setup.sh
```

Without the bridge the halo still follows the cursor; only the click flash
and ripple stay idle.

Settings persist to the widget entry in `~/.config/omarchy/shell.json`
(`omarchy bar set nickmdrummer.cursor-halo <key> <value>` edits the same keys,
`en.json`/`es.json` in `i18n/` follow Setup > Language live).

## Files

- `manifest.json` — plugin manifest + settings schema
- `BarWidget.qml` — bar pill, cursor polling, popup settings
- `Overlay.qml` — per-monitor fullscreen click-through overlay
- `HaloShape.qml` — the glowing shape
- `HaloModel.js` — pure helpers (unit-tested, runs under node)
- `cursor-halo.lua` + `setup.sh` — Hyprland click bridge hook
