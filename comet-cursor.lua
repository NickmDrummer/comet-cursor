-- Comet Cursor (nickmdrummer.comet-cursor) — click bridge for the highlighter.
--
-- Hyprland does not emit mouse-button events on its IPC socket, so the shell
-- cannot see clicks from QML alone. These non-consuming binds write a tiny
-- JSON file on every press; the bar widget watches it and flashes the halo
-- with the left/right click color. Non-consuming means the click still
-- reaches the app below — the binds only observe.
--
-- Install with: bash ~/.config/omarchy/plugins/nickmdrummer.comet-cursor/setup.sh
-- then `hyprctl reload`.

local runtime = os.getenv("XDG_RUNTIME_DIR")
if runtime == nil or runtime == "" then
  runtime = (os.getenv("HOME") or "") .. "/.cache"
end
local dir = runtime .. "/nickmdrummer-comet-cursor"
os.execute("mkdir -p " .. dir)
local click_file = dir .. "/click.json"

local click_seq = 0
local function record_event(button, down)
  -- Monotonic counter (not wall-clock): the widget ignores repeats of the
  -- same value, so every event must produce a new one even within one second.
  -- `down` lets the widget keep the click color while the button is held,
  -- which is how a long press stays colored instead of flashing 200ms.
  click_seq = click_seq + 1
  local f = io.open(click_file, "w")
  if f then
    f:write(string.format('{"button":"%s","at":%d,"down":%s}',
      button, click_seq, down and "true" or "false"))
    f:close()
  end
end

-- Press and release halves. The release bind ignores modifiers and is
-- transparent so letting go always reaches the app, whatever else is held.
local function bind_button(code, button, label)
  o.bind(code, "Comet Cursor: " .. label .. " flash", function() record_event(button, true) end,
    { mouse = true, non_consuming = true })
  o.bind(code, "Comet Cursor: " .. label .. " release", function() record_event(button, false) end,
    { mouse = true, release = true, non_consuming = true, transparent = true, ignore_mods = true })
end

bind_button("mouse:272", "left", "left-click")
bind_button("mouse:273", "right", "right-click")
bind_button("mouse:274", "middle", "middle-click")
