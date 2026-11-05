// HaloModel — pure helpers for the Cursor Halo plugin (no Qt imports,
// so node can run the unit tests in tests/).
var COLORS = ["#00FFC8", "#FF2D55", "#3B82F6", "#A855F7", "#FFB020", "#FFFFFF"];
var SHAPES = ["Circle", "Rhombus", "Rounded"];
var SIZES = ["S", "M", "L", "XL"];
var WEIGHTS = ["Thin", "Regular", "Bold"];
var MODES = ["Always", "On move"];

var DIAMETERS = { S: 84, M: 128, L: 176, XL: 232 };
var BORDERS = { Thin: 4, Regular: 8, Bold: 13 };

function cleanEnum(value, allowed, fallback) {
  var s = String(value === undefined || value === null ? "" : value);
  for (var i = 0; i < allowed.length; i++) {
    if (s === allowed[i]) return s;
  }
  return fallback;
}

function cleanColor(value, fallback) {
  var s = String(value === undefined || value === null ? "" : value).toUpperCase();
  for (var i = 0; i < COLORS.length; i++) {
    if (s === COLORS[i]) return COLORS[i];
  }
  // Accept any strict #RRGGBB as a forward-compatible fallback, else default.
  if (/^#[0-9A-F]{6}$/.test(s)) return s;
  return fallback;
}

function diameterForSize(size) {
  var s = cleanEnum(size, SIZES, "L");
  return DIAMETERS[s] || DIAMETERS.L;
}

function borderForWeight(weight) {
  var w = cleanEnum(weight, WEIGHTS, "Bold");
  return BORDERS[w] || BORDERS.Bold;
}

function clamp(n, lo, hi) {
  n = Number(n);
  if (!isFinite(n)) return lo;
  return Math.max(lo, Math.min(hi, n));
}

// Parse `hyprctl cursorpos -j` output ({x,y}) with hard bounds so a
// hostile or corrupt response can never move the halo off-planet.
function parseCursorPos(raw) {
  try {
    var o = JSON.parse(String(raw || ""));
    return { x: clamp(o.x, -100000, 100000), y: clamp(o.y, -100000, 100000) };
  } catch (e) {
    return null;
  }
}

// Parse `hyprctl monitors -j` into [{name,x,y,width,height}] with bounds.
function parseMonitors(raw) {
  try {
    var arr = JSON.parse(String(raw || ""));
    if (!Array.isArray(arr)) return [];
    var out = [];
    for (var i = 0; i < Math.min(arr.length, 16); i++) {
      var m = arr[i] || {};
      out.push({
        name: String(m.name || "").slice(0, 64),
        x: clamp(m.x, -100000, 100000),
        y: clamp(m.y, -100000, 100000),
        width: clamp(m.width, 1, 16000),
        height: clamp(m.height, 1, 16000)
      });
    }
    return out;
  } catch (e) {
    return [];
  }
}

// Click bridge file written by cursor-halo.lua:
// {button:"left"|"right"|"middle", at:number, down:boolean}.
// `at` is a monotonic counter (one higher per event); the widget ignores
// repeats of the same value so rapid clicks are never merged. `down` is false
// on release, which is how a held button keeps its color.
function parseClick(raw) {
  try {
    var o = JSON.parse(String(raw || ""));
    var b = String(o.button || "");
    if (b !== "left" && b !== "right" && b !== "middle") return null;
    var at = Number(o.at);
    if (!isFinite(at) || at < 0) return null;
    return { button: b, at: Math.min(at, 9007199254740991), down: o.down !== false };
  } catch (e) {
    return null;
  }
}

function clickColorFor(button, leftColor, rightColor, baseColor) {
  if (button === "left") return cleanColor(leftColor, "#FF2D55");
  if (button === "right") return cleanColor(rightColor, "#3B82F6");
  return cleanColor(baseColor, "#00FFC8");
}

// How long a click keeps the halo on screen in "On move" mode.
var MOVE_IDLE_MS = 1200;

// Whether the halo should be painted. Pure so the On-move rule (moving OR
// clicking counts, not just moving) is unit-tested instead of guessed.
// Times are epoch ms, hence doubles: a 32-bit int overflows at Date.now().
function shouldShow(o) {
  if (!o || o.enabled !== true) return false;
  if (o.onScreen !== true) return false;
  if (o.held === true) return true;
  if (String(o.mode || "") !== "On move") return true;
  var now = Number(o.now) || 0;
  var moved = now - (Number(o.lastMoveAt) || 0);
  var clicked = now - (Number(o.lastClickAt) || 0);
  return moved < MOVE_IDLE_MS || clicked < MOVE_IDLE_MS;
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    COLORS: COLORS, SHAPES: SHAPES, SIZES: SIZES, WEIGHTS: WEIGHTS, MODES: MODES,
    cleanEnum: cleanEnum, cleanColor: cleanColor,
    diameterForSize: diameterForSize, borderForWeight: borderForWeight,
    clamp: clamp, parseCursorPos: parseCursorPos,
    parseMonitors: parseMonitors, parseClick: parseClick,
    clickColorFor: clickColorFor,
    MOVE_IDLE_MS: MOVE_IDLE_MS, shouldShow: shouldShow
  };
}
