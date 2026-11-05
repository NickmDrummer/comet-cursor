# Comet Cursor

A cursor highlighter for the Omarchy bar, made for demos and screencasts: a
glowing shape follows the pointer, flashes its color on click, ripples, can dim
the rest of the screen, and can leave one of three animated trails behind.

## Requirements

- Omarchy (the Quickshell shell) running on Hyprland.
- Nothing else: no network access, no extra packages, no background services.

## Install

```bash
omarchy plugin add https://github.com/NickmDrummer/comet-cursor.git --enable --yes
bash ~/.config/omarchy/plugins/nickmdrummer.comet-cursor/setup.sh
```

- The first command clones, validates and enables the plugin. Omarchy installs
  it under `~/.config/omarchy/plugins/<plugin id>`, which is why the path in the
  second command is fixed, and places the widget in the bar's `right` section
  (its manifest default).
- The second command is **optional**: it installs the click bridge, which is what
  makes the halo flash on left/right click. Without it, the halo, spotlight and
  trails all work; only the click colors and the ripple stay idle.

The click bridge installer:

- backs up `~/.config/hypr/hyprland.lua` with a timestamp,
- appends one marked block that loads `comet-cursor.lua`,
- reloads Hyprland.

It is idempotent: running it again never duplicates the block.

## Uninstall

Order matters. Remove the hook **before** deleting the plugin folder, because
`omarchy plugin remove` deletes the folder and would take `setup.sh` with it.

```bash
bash ~/.config/omarchy/plugins/nickmdrummer.comet-cursor/setup.sh --remove
omarchy plugin remove nickmdrummer.comet-cursor --yes
```

- `setup.sh --remove` deletes only its own marked block from `hyprland.lua`
  (after a timestamped backup) and reloads Hyprland. It needs nothing beyond a
  stock system: the rewrite uses `awk`.
- `omarchy plugin remove` disables the widget (removing its entry from the bar
  layout) and deletes the plugin folder.

Nothing else is left behind. The plugin only ever writes its own entry in
`~/.config/omarchy/shell.json` and a `click.json` inside `$XDG_RUNTIME_DIR`,
which the session clears on logout. The timestamped `hyprland.lua.bak.*` copies
are yours to delete by hand whenever you like.

## Usage

- **Bar pill `☄ COMET`** — left-click toggles the effect, right-click opens the
  settings window. The label stays in the bar's foreground (white when on, dimmed
  when off); it never changes hue. The comet is monochrome and drawn from a symbol
  font bundled in `assets/`, so it does not fall back to a color emoji.
- **APPEARANCE** — shape (Circle / Rhombus / Rounded), size, border weight, halo
  color and the left/right click flash colors. Each palette has six presets, up
  to three saved custom colors of your own, and a `+` swatch that opens an HSV
  picker for another one. Clicking a saved custom color applies it and opens it
  for editing; typing a preset closes the picker. The picker also takes typed hex
  values (Enter, or clicking outside the field, applies them).
- **BEHAVIOR** — enable, show (Always / On move), spotlight, ripple. Holding a
  click keeps its color until you release it.
- **TRAILS** — style (Off / Pixels / Feather / Ribbon), length, width, opacity,
  and color (follow the halo, which also picks up the click flash, or a custom
  color).

Trails are independent of the halo: with the halo off, a trail still draws.

## Settings

Everything lives in the widget entry of `~/.config/omarchy/shell.json`. The same
keys can be changed from the command line:

```bash
omarchy bar set nickmdrummer.comet-cursor <key> <value>
```

| key | values |
| --- | --- |
| `enabled` | `true`, `false` |
| `shape` | `Circle`, `Rhombus`, `Rounded` |
| `size` | `S`, `M`, `L`, `XL` |
| `borderWeight` | `Thin`, `Regular`, `Bold` |
| `color` | `#RRGGBB` (halo) |
| `leftClickColor` | `#RRGGBB` |
| `rightClickColor` | `#RRGGBB` |
| `mode` | `Always`, `On move` |
| `spotlight` | `true`, `false` |
| `ripple` | `true`, `false` |
| `trailStyle` | `Off`, `Pixels`, `Feather`, `Ribbon` |
| `trailLength` | `200`–`2000` (ms) |
| `trailWidth` | `2`–`16` |
| `trailOpacity` | `10`–`100` (%) |
| `trailColorMode` | `Halo`, `Custom` |
| `trailColor` | `#RRGGBB` |

## How it works

- **Overlay** — one fullscreen, click-through layer surface per monitor
  (`Overlay.qml`). It only paints; the bar widget owns all the state.
- **Click bridge** — Hyprland does not report mouse buttons over its IPC socket,
  so `comet-cursor.lua` adds three *non-consuming* binds that write a tiny JSON
  file under `$XDG_RUNTIME_DIR`. Non-consuming means the click still reaches the
  app underneath: the binds only observe.
- **Sampling** — the pointer is sampled through `hyprctl cursorpos` at roughly
  30 Hz. The trail rebuilds those samples as tangent-continuous cubic curves, so
  a fast circle stays round instead of turning into a hexagon.

## Troubleshooting

- **Nothing appears** — run `omarchy restart shell`. The shell's hot reload
  re-instantiates widgets but keeps the previously compiled QML.
- **A change did not apply** — `omarchy-shell shell rescanPlugins`.
- **No click flash** — re-run `bash ~/.config/omarchy/plugins/nickmdrummer.comet-cursor/setup.sh`,
  then check `hyprctl binds | grep "Comet Cursor"` lists six binds.
- **The comet glyph looks odd** — `☄` is not part of the bar's font
  (`Obel Mono`), so it is drawn by font fallback. Edit `text` in `BarWidget.qml`
  if you prefer another glyph.

## Third-party

- **Noto Sans Symbols 2** (`assets/NotoSansSymbols2-Regular.ttf`) — Copyright 2022
  The Noto Project Authors. Bundled so the comet glyph renders monochrome instead
  of falling back to a color emoji font. Licensed under the SIL Open Font License
  1.1, reproduced in `assets/OFL.txt`.

## License

MIT — see [LICENSE](LICENSE).
