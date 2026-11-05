// HaloModel — pure helpers for the Cursor Halo plugin (no Qt imports,
// so node can run the unit tests in tests/).
var COLORS = ["#00FFC8", "#FF2D55", "#3B82F6", "#A855F7", "#FFB020", "#FFFFFF"];
var SHAPES = ["Circle", "Rhombus", "Rounded"];
var SIZES = ["S", "M", "L", "XL"];
var WEIGHTS = ["Thin", "Regular", "Bold"];
var MODES = ["Always", "On move"];
var TRAIL_STYLES = ["Off", "Pixels", "Feather", "Ribbon"];

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
// Trail color: follow the halo (so it also picks up the click flash) unless
// the user pinned a custom color.
function trailColorFor(mode, customColor, haloColor) {
  if (String(mode || "") === "Custom") return cleanColor(customColor, "#00FFC8");
  return cleanColor(haloColor, "#00FFC8");
}

// Trail points older than this are dropped; shared by host and tests.
function trimTrail(points, now, lengthMs, cap) {
  var cutoff = now - Math.max(1, Number(lengthMs) || 600);
  var out = [];
  for (var i = 0; i < points.length; i++) {
    var p = points[i];
    if (p && Number(p.t) >= cutoff) out.push(p);
  }
  var limit = Math.max(1, Number(cap) || 90);
  return out.length > limit ? out.slice(out.length - limit) : out;
}

// Progress 0 (fresh) .. 1 (expired) of one trail point.
function trailAge(point, now, lengthMs) {
  var span = Math.max(1, Number(lengthMs) || 600);
  var age = (Number(now) - Number(point && point.t)) / span;
  return Math.max(0, Math.min(1, isFinite(age) ? age : 1));
}

function unitVector(dx, dy) {
  var len = Math.sqrt(dx * dx + dy * dy);
  if (!(len > 0)) return [0, 0];
  return [dx / len, dy / len];
}

// Tangent at one end of the stroke, taken from the circle through the three
// nearest samples. For a circular motion this is exact, whereas extrapolating
// from the neighbouring tangents in vector space drifted by a third of the
// arc (and bent the stroke at the tips).
function tangentFromCircle(a, b, c, atLast) {
  var d = 2 * (a.gx * (b.gy - c.gy) + b.gx * (c.gy - a.gy) + c.gx * (a.gy - b.gy));
  if (Math.abs(d) < 1e-6) return null;
  var a2 = a.gx * a.gx + a.gy * a.gy;
  var b2 = b.gx * b.gx + b.gy * b.gy;
  var c2 = c.gx * c.gx + c.gy * c.gy;
  var cx = (a2 * (b.gy - c.gy) + b2 * (c.gy - a.gy) + c2 * (a.gy - b.gy)) / d;
  var cy = (a2 * (c.gx - b.gx) + b2 * (a.gx - c.gx) + c2 * (b.gx - a.gx)) / d;
  var p = atLast ? c : a;
  var rx = p.gx - cx;
  var ry = p.gy - cy;
  var tx = -ry;
  var ty = rx;
  // Orient it along the direction of travel: away from b at the start, and
  // past b at the end.
  var dx = atLast ? (p.gx - b.gx) : (b.gx - p.gx);
  var dy = atLast ? (p.gy - b.gy) : (b.gy - p.gy);
  if (tx * dx + ty * dy < 0) { tx = -tx; ty = -ty; }
  var t = unitVector(tx, ty);
  return (t[0] === 0 && t[1] === 0) ? null : t;
}

// Unit tangent at every sample.
//
// Interior samples use the central difference, which for points on a circle is
// exactly the circle's tangent. The ends have no neighbour on one side, so
// they take the tangent of the circle through the three samples they do have.
function sampleTangents(points) {
  var n = points ? points.length : 0;
  var t = [];
  for (var i = 0; i < n; i++) {
    if (i === 0) {
      t.push(tangentFromCircle(points[0], points[1], points[Math.min(2, n - 1)], false)
        || unitVector(points[1].gx - points[0].gx, points[1].gy - points[0].gy));
    } else if (i === n - 1) {
      t.push(tangentFromCircle(points[Math.max(0, n - 3)], points[n - 2], points[n - 1], true)
        || unitVector(points[n - 1].gx - points[n - 2].gx, points[n - 1].gy - points[n - 2].gy));
    } else {
      t.push(unitVector(points[i + 1].gx - points[i - 1].gx, points[i + 1].gy - points[i - 1].gy));
    }
  }
  return t;
}

function bezierAt(p0, c1, c2, p3, u) {
  var v = 1 - u;
  var vv = v * v;
  var uu = u * u;
  return [
    vv * v * p0[0] + 3 * vv * u * c1[0] + 3 * v * uu * c2[0] + uu * u * p3[0],
    vv * v * p0[1] + 3 * vv * u * c1[1] + 3 * v * uu * c2[1] + uu * u * p3[1]
  ];
}

// Resample the samples as a smooth curve, roughly every 2px.
//
// Samples arrive at ~30Hz, so a fast circle only produces a handful of them.
// Joining those with straight lines literally draws a hexagon. Each gap is
// bridged with a cubic Bezier whose end tangents are shared with the
// neighbouring gaps: that keeps circles round AND removes the tiny kink the
// eye caught where two independently fitted arcs met.
function smoothPath(points, maxPoints) {
  var n = points ? points.length : 0;
  if (n === 0) return [];
  if (n === 1) return [{ x: points[0].gx, y: points[0].gy, t: points[0].t }];
  var limit = Math.max(16, Number(maxPoints) || 600);
  var out = [];
  var tangents = sampleTangents(points);
  for (var i = 0; i < n - 1; i++) {
    var p1 = points[i];
    var p2 = points[i + 1];
    var dx = p2.gx - p1.gx;
    var dy = p2.gy - p1.gy;
    var chord = Math.sqrt(dx * dx + dy * dy);
    if (!(chord > 0)) {
      out.push({ x: p1.gx, y: p1.gy, t: p1.t });
      continue;
    }
    var steps = Math.max(2, Math.min(48, Math.ceil(chord / 2)));
    var t1 = tangents[i];
    var t2 = tangents[i + 1];
    // A cusp (the pointer doubling back) leaves a zero-length central
    // difference; fall back to the chord so the control arm stays valid.
    var chordDir = [dx / chord, dy / chord];
    if (t1[0] === 0 && t1[1] === 0) t1 = chordDir;
    if (t2[0] === 0 && t2[1] === 0) t2 = chordDir;
    // Turn between the two shared tangents: 0 on a straight run, larger the
    // tighter the curve. The control-arm length that makes a cubic match a
    // circular arc of that turn is (4/3)·tan(turn/4)·R, with R = chord/(2·sin(turn/2)).
    var dot = t1[0] * t2[0] + t1[1] * t2[1];
    dot = Math.max(-1, Math.min(1, dot));
    var turn = Math.acos(dot);
    var arm;
    if (turn < 1e-3) {
      arm = chord / 3;
    } else {
      var sinHalf = Math.sin(turn / 2);
      arm = sinHalf < 1e-4
        ? chord / 3
        : (4 / 3) * Math.tan(turn / 4) * chord / (2 * sinHalf);
    }
    // Sharp, noisy turns must not loop back on themselves.
    arm = Math.max(chord / 6, Math.min(arm, chord * 0.42));
    var c1 = [p1.gx + t1[0] * arm, p1.gy + t1[1] * arm];
    var c2 = [p2.gx - t2[0] * arm, p2.gy - t2[1] * arm];
    for (var s = 0; s < steps; s++) {
      var u = s / steps;
      var pt = bezierAt([p1.gx, p1.gy], c1, c2, [p2.gx, p2.gy], u);
      out.push({ x: pt[0], y: pt[1], t: p1.t + (p2.t - p1.t) * u });
      if (out.length >= limit) break;
    }
    if (out.length >= limit) break;
  }
  var last = points[n - 1];
  out.push({ x: last.gx, y: last.gy, t: last.t });
  return out;
}

// Width share of the brush at a given age (0 = fresh head, 1 = oldest tail).
// Full width along the body and a collapse only near the tail: an even taper
// made every tiny segment a visible trapezoid (thin at one end, thick at the
// other), which read as faceting on circles.
function widthFactor(age, feather) {
  var a = Math.max(0, Math.min(1, Number(age) || 0));
  var collapseStart = feather ? 0.55 : 0.78;
  var floorShare = feather ? 0 : 0.45;
  if (a <= collapseStart) return 1;
  var k = (a - collapseStart) / (1 - collapseStart);
  var eased = k * k * (3 - 2 * k);
  return 1 - (1 - floorShare) * eased;
}

// Closed outline for a brush stroke through the samples, in LOCAL coordinates.
//
// Drawing the stroke as overlapping circles left visible gaps whenever the
// pointer accelerated (samples spread further apart than their own radius).
// One filled polygon built from both edges of the smoothed path is continuous
// at any speed.
function strokeOutline(points, now, lengthMs, width, mode, originX, originY) {
  var dense = smoothPath(points, 600);
  var n = dense.length;
  if (n < 2) return [];
  var baseWidth = Math.max(1, Number(width) || 6);
  var feather = String(mode || "") === "Feather";
  var ox = Number(originX) || 0;
  var oy = Number(originY) || 0;
  var left = [];
  var right = [];
  for (var i = 0; i < n; i++) {
    var p = dense[i];
    var age = trailAge({ t: p.t }, now, lengthMs);
    var w = Math.max(0.5, baseWidth * widthFactor(age, feather));
    var half = w / 2;
    var prev = dense[Math.max(0, i - 1)];
    var next = dense[Math.min(n - 1, i + 1)];
    var dx = next.x - prev.x;
    var dy = next.y - prev.y;
    var len = Math.sqrt(dx * dx + dy * dy);
    if (!(len > 0)) { dx = 1; dy = 0; len = 1; }
    var nx = -dy / len;
    var ny = dx / len;
    var cx = p.x - ox;
    var cy = p.y - oy;
    left.push([cx + nx * half, cy + ny * half]);
    right.push([cx - nx * half, cy - ny * half]);
  }
  var out = left;
  for (var j = right.length - 1; j >= 0; j--) out.push(right[j]);
  return out;
}

// Wrap-around stepper for enum settings: -1/+1 walks the list.
function cycleEnum(current, allowed, delta) {
  var list = allowed || [];
  if (list.length === 0) return String(current);
  var idx = list.indexOf(String(current));
  if (idx < 0) idx = 0;
  var next = (idx + (Number(delta) || 0)) % list.length;
  if (next < 0) next += list.length;
  return list[next];
}

// Wrap-around stepper for bounded numbers. `range` is {min, max}.
function stepNumber(current, range, step, delta) {
  var min = Number(range && range.min) || 0;
  var max = Number(range && range.max) || 100;
  var inc = Math.abs(Number(step) || 1);
  var v = Number(current);
  if (!isFinite(v)) v = min;
  v = v + (Number(delta) || 0) * inc;
  if (v < min) v = max;
  if (v > max) v = min;
  return Math.round(v * 1000) / 1000;
}

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
    trailColorFor: trailColorFor, trimTrail: trimTrail, trailAge: trailAge,
    strokeOutline: strokeOutline, cycleEnum: cycleEnum, stepNumber: stepNumber,
    smoothPath: smoothPath, widthFactor: widthFactor,
    TRAIL_STYLES: TRAIL_STYLES,
    MOVE_IDLE_MS: MOVE_IDLE_MS, shouldShow: shouldShow
  };
}
