#!/usr/bin/env bash
# Install (or remove) the Hyprland click-bridge hook for Comet Cursor.
#
# The halo overlay is click-through, so Hyprland mouse binds are the only way
# to see global clicks. This script appends a managed dofile block to
# ~/.config/hypr/hyprland.lua (idempotent, with timestamped backup).
#
# Usage:
#   bash setup.sh          # install the hook
#   bash setup.sh --remove # remove it (run before uninstalling the plugin)
set -u

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HYPR_LUA="$HOME/.config/hypr/hyprland.lua"
MARKER="nickmdrummer.comet-cursor/comet-cursor.lua"
MODE="${1:-install}"

if [[ "$MODE" != "install" && "$MODE" != "--remove" ]]; then
  echo "usage: bash setup.sh [--remove]" >&2
  exit 2
fi

reload_hyprland() {
  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 && echo "setup: Hyprland reloaded." \
      || echo "setup: config changed but 'hyprctl reload' failed; run it manually." >&2
  else
    echo "setup: config changed; run 'hyprctl reload' inside your Hyprland session." >&2
  fi
}

backup() {
  local path="$1"
  local dest="$path.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$path" "$dest" || { echo "setup: backup failed, aborting." >&2; exit 1; }
  echo "setup: backup at $dest"
}

if [[ ! -f "$HYPR_LUA" ]]; then
  echo "setup: $HYPR_LUA not found." >&2
  exit 1
fi

if [[ "$MODE" == "--remove" ]]; then
  if ! grep -qF "$MARKER" "$HYPR_LUA"; then
    echo "setup: click-bridge hook not present, nothing to remove."
    exit 0
  fi
  backup "$HYPR_LUA"
  # awk, not python: uninstalling must not depend on anything beyond a stock
  # Omarchy system. Only the marked block is dropped; the rest of the file is
  # written back byte for byte.
  awk -v marker="-- [nickmdrummer.comet-cursor]" '
    index($0, marker) == 1 { skipping = 1; next }
    skipping && $0 ~ /^[[:space:]]*end[[:space:]]*$/ { skipping = 0; next }
    skipping { next }
    { print }
  ' "$HYPR_LUA" > "$HYPR_LUA.comet-cursor.tmp" \
    && mv "$HYPR_LUA.comet-cursor.tmp" "$HYPR_LUA" \
    || { echo "setup: could not rewrite $HYPR_LUA" >&2; exit 1; }
  echo "setup: click-bridge hook removed."
  reload_hyprland
  echo "setup: finish the uninstall with: omarchy plugin remove nickmdrummer.comet-cursor --yes"
  exit 0
fi

if [[ ! -f "$PLUGIN_DIR/comet-cursor.lua" ]]; then
  echo "setup: comet-cursor.lua not found in $PLUGIN_DIR" >&2
  exit 1
fi

if grep -qF "$MARKER" "$HYPR_LUA"; then
  echo "setup: click-bridge hook already present, nothing to do."
else
  backup "$HYPR_LUA"
  cat >> "$HYPR_LUA" <<'EOF'
-- [nickmdrummer.comet-cursor] click bridge for the cursor highlighter (managed by the plugin; safe to remove)
local comet_path = os.getenv("HOME") .. "/.config/omarchy/plugins/nickmdrummer.comet-cursor/comet-cursor.lua"
local comet_file = io.open(comet_path, "r")
if comet_file then
	comet_file:close()
	dofile(comet_path)
end
EOF
  echo "setup: click-bridge hook added."
fi

reload_hyprland
