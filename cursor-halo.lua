-- Cursor Halo (nickmdrummer.cursor-halo) — click bridge for the highlighter.
--
-- Hyprland does not emit mouse-button events on its IPC socket, so the shell
-- cannot see clicks from QML alone. These non-consuming binds write a tiny
-- JSON file on every press; the bar widget watches it and flashes the halo
-- with the left/right click color. Non-consuming means the click still
-- reaches the app below — the binds only observe.
--
-- Install with: bash ~/.config/omarchy/plugins/nickmdrummer.cursor-halo/setup.sh
-- then `hyprctl reload`.

local runtime = os.getenv("XDG_RUNTIME_DIR")
if runtime == nil or runtime == "" then
  runtime = (os.getenv("HOME") or "") .. "/.cache"
end
local dir = runtime .. "/nickmdrummer-cursor-halo"
os.execute("mkdir -p " .. dir)
local click_file = dir .. "/click.json"

local click_seq = 0
local function record_click(button)
  -- Monotonic counter (not wall-clock): the widget ignores repeats of the
  -- same value, so every press must produce a new one even within one second.
  click_seq = click_seq + 1
  local f = io.open(click_file, "w")
  if f then
    f:write(string.format('{"button":"%s","at":%d}', button, click_seq))
    f:close()
  end
end

o.bind("mouse:272", "Cursor Halo: click flash (left)", function() record_click("left") end, { mouse = true, non_consuming = true })
o.bind("mouse:273", "Cursor Halo: click flash (right)", function() record_click("right") end, { mouse = true, non_consuming = true })
o.bind("mouse:274", "Cursor Halo: click flash (middle)", function() record_click("middle") end, { mouse = true, non_consuming = true })
