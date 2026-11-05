import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const Halo = require("../HaloModel.js");

test("diameters and borders stay in range", () => {
  assert.equal(Halo.diameterForSize("S"), 84);
  assert.equal(Halo.diameterForSize("XL"), 232);
  assert.equal(Halo.diameterForSize("bogus"), 176);
  assert.equal(Halo.borderForWeight("Thin"), 4);
  assert.equal(Halo.borderForWeight("nope"), 13);
});

test("colors are allowlisted", () => {
  assert.equal(Halo.cleanColor("#ff2d55", "#00FFC8"), "#FF2D55");
  assert.equal(Halo.cleanColor("#123456", "#00FFC8"), "#123456");
  assert.equal(Halo.cleanColor("red; rm -rf", "#00FFC8"), "#00FFC8");
  assert.equal(Halo.cleanColor("<img src=x>", "#00FFC8"), "#00FFC8");
});

test("cursor and monitor parsing is bounded", () => {
  assert.deepEqual(Halo.parseCursorPos('{"x":100,"y":200}'), { x: 100, y: 200 });
  assert.equal(Halo.parseCursorPos("nope"), null);
  const mons = Halo.parseMonitors('[{"name":"DP-1","x":1920,"y":0,"width":1920,"height":1080}]');
  assert.equal(mons.length, 1);
  assert.equal(mons[0].name, "DP-1");
  assert.deepEqual(Halo.parseMonitors("garbage"), []);
});

test("click parsing rejects markup", () => {
  assert.deepEqual(Halo.parseClick('{"button":"left","at":123}'), { button: "left", at: 123, down: true });
  assert.equal(Halo.parseClick('{"button":"<img>","at":1}'), null);
  assert.equal(Halo.clickColorFor("left", "#FF2D55", "#3B82F6", "#00FFC8"), "#FF2D55");
  assert.equal(Halo.clickColorFor("right", "#FF2D55", "#3B82F6", "#00FFC8"), "#3B82F6");
});

test("release events parse with down:false", () => {
  assert.deepEqual(Halo.parseClick('{"button":"right","at":7,"down":false}'), { button: "right", at: 7, down: false });
  assert.equal(Halo.parseClick('{"button":"left","at":8,"down":true}').down, true);
});

test("a held button keeps the halo visible on move mode", () => {
  const still = { enabled: true, onScreen: true, mode: "On move", now: 1000000, lastMoveAt: 0, lastClickAt: 0 };
  assert.equal(Halo.shouldShow({ ...still, held: false }), false);
  assert.equal(Halo.shouldShow({ ...still, held: true }), true);
});

test("trail color follows the halo unless custom is picked", () => {
  assert.equal(Halo.trailColorFor("Halo", "#FF2D55", "#3b82f6"), "#3B82F6");
  assert.equal(Halo.trailColorFor("Custom", "#ff2d55", "#3B82F6"), "#FF2D55");
  // Junk falls back instead of leaking markup into a color sink.
  assert.equal(Halo.trailColorFor("Custom", "<img src=x>", "#3B82F6"), "#00FFC8");
});

test("trail points expire by age and stay under the cap", () => {
  const now = 10000;
  const pts = [
    { gx: 0, gy: 0, t: 8000 },   // too old for a 600ms trail
    { gx: 1, gy: 1, t: 9900 },
    { gx: 2, gy: 2, t: 10000 }
  ];
  const kept = Halo.trimTrail(pts, now, 600, 90);
  assert.equal(kept.length, 2);
  assert.equal(kept[1].gx, 2);
  // Cap keeps the newest samples.
  const many = [];
  for (let i = 0; i < 200; i++) many.push({ gx: i, gy: 0, t: now });
  const capped = Halo.trimTrail(many, now, 600, 90);
  assert.equal(capped.length, 90);
  assert.equal(capped[89].gx, 199);
});

test("trail age is clamped between 0 and 1", () => {
  assert.equal(Halo.trailAge({ t: 1000 }, 1000, 600), 0);
  assert.equal(Halo.trailAge({ t: 0 }, 10000, 600), 1);
  assert.equal(Math.round(Halo.trailAge({ t: 700 }, 1000, 600) * 100) / 100, 0.5);
});

test("stroke outline spans the whole path as one band", () => {
  // Two samples far apart (fast flick): both edges must cover the full path
  // instead of one blob per sample.
  const pts = [
    { gx: 0, gy: 0, t: 1000 },
    { gx: 100, gy: 0, t: 1100 }
  ];
  const poly = Halo.strokeOutline(pts, 1100, 600, 10, "Ribbon", 0, 0);
  // The spline resamples densely, so the polygon has many vertices.
  assert.ok(poly.length > 40, "expected a dense outline, got " + poly.length);
  const xs = poly.map((p) => p[0]);
  assert.ok(Math.min.apply(null, xs) <= 0.5);
  assert.ok(Math.max.apply(null, xs) >= 99.5);
});

test("a fast circle is drawn round, not as a polygon", () => {
  // Regression for the reported bug: six samples around a circle used to be
  // joined with straight lines, so the stroke literally looked like a hexagon.
  const radius = 100;
  const samples = [];
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * Math.PI * 2;
    samples.push({ gx: radius + radius * Math.cos(a), gy: radius + radius * Math.sin(a), t: 1000 + i * 40 });
  }
  const dense = Halo.smoothPath(samples, 600);
  assert.ok(dense.length > 60, "expected the spline to densify");
  let worst = 0;
  for (const p of dense) {
    const r = Math.sqrt(Math.pow(p.x - radius, 2) + Math.pow(p.y - radius, 2));
    worst = Math.max(worst, Math.abs(r - radius));
  }
  // A hexagon dips ~13.4px (r*cos(30 deg)); the rebuilt curve must stay round.
  assert.ok(worst < 0.5, "circle deviated " + worst.toFixed(3) + "px from round");
});

test("the stroke has no kink at the joints between samples", () => {
  // Each gap used to be fitted as an independent arc, so two neighbouring
  // arcs met at a slightly different tangent: a micro-corner on every sample.
  const radius = 100;
  const samples = [];
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * Math.PI * 2;
    samples.push({ gx: radius + radius * Math.cos(a), gy: radius + radius * Math.sin(a), t: 1000 + i * 40 });
  }
  const dense = Halo.smoothPath(samples, 600);
  let worstTurn = 0;
  for (let i = 1; i < dense.length - 1; i++) {
    const ax = dense[i].x - dense[i - 1].x;
    const ay = dense[i].y - dense[i - 1].y;
    const bx = dense[i + 1].x - dense[i].x;
    const by = dense[i + 1].y - dense[i].y;
    const la = Math.sqrt(ax * ax + ay * ay);
    const lb = Math.sqrt(bx * bx + by * by);
    if (la < 1e-9 || lb < 1e-9) continue;
    const cos = Math.max(-1, Math.min(1, (ax * bx + ay * by) / (la * lb)));
    worstTurn = Math.max(worstTurn, (Math.acos(cos) * 180) / Math.PI);
  }
  // Dense 2px steps on a 100px circle bend ~1.1 deg per step; a seam between
  // two mismatched arcs showed up as a much larger single-step jump.
  assert.ok(worstTurn < 6, "kink of " + worstTurn.toFixed(2) + " deg at a joint");
});

test("a straight run stays perfectly straight", () => {
  const pts = [];
  for (let i = 0; i < 5; i++) pts.push({ gx: i * 40, gy: 100, t: 1000 + i * 40 });
  const dense = Halo.smoothPath(pts, 600);
  let worst = 0;
  for (const p of dense) worst = Math.max(worst, Math.abs(p.y - 100));
  assert.ok(worst < 1e-6, "straight run bowed by " + worst);
});

test("brush keeps full width along the body and collapses at the tail", () => {
  assert.equal(Halo.widthFactor(0, true), 1);
  assert.equal(Halo.widthFactor(0.4, true), 1);   // uniform body: no facets
  assert.equal(Halo.widthFactor(1, true), 0);     // tail vanishes
  assert.ok(Halo.widthFactor(0.85, true) < 0.5);
  assert.ok(Math.abs(Halo.widthFactor(1, false) - 0.45) < 1e-9); // ribbon keeps body width
  assert.equal(Halo.widthFactor(0.5, false), 1);
});

test("fewer than two samples draws nothing", () => {
  assert.deepEqual(Halo.strokeOutline([], 1000, 600, 8, "Feather", 0, 0), []);
  assert.deepEqual(Halo.strokeOutline([{ gx: 1, gy: 1, t: 1000 }], 1000, 600, 8, "Feather", 0, 0), []);
});

test("enum stepper wraps in both directions", () => {
  assert.equal(Halo.cycleEnum("Circle", Halo.SHAPES, 1), "Rhombus");
  assert.equal(Halo.cycleEnum("Rounded", Halo.SHAPES, 1), "Circle");
  assert.equal(Halo.cycleEnum("Circle", Halo.SHAPES, -1), "Rounded");
  assert.equal(Halo.cycleEnum("bogus", Halo.SHAPES, 0), "Circle");
});

test("number stepper clamps by wrapping at the range ends", () => {
  const range = { min: 200, max: 2000 };
  assert.equal(Halo.stepNumber(1900, range, 100, 1), 2000);
  assert.equal(Halo.stepNumber(2000, range, 100, 1), 200);
  assert.equal(Halo.stepNumber(200, range, 100, -1), 2000);
  assert.equal(Halo.stepNumber("garbage", { min: 2, max: 16 }, 1, 1), 3);
});

test("on-move mode shows on movement OR click, hides when still", () => {
  const base = { enabled: true, onScreen: true, mode: "On move", now: 1000000 };
  // Just moved: visible even if the last click was long ago.
  assert.equal(Halo.shouldShow({ ...base, lastMoveAt: 999900, lastClickAt: 0 }), true);
  // Still, but a click just landed: visible (clicking alone must show it).
  assert.equal(Halo.shouldShow({ ...base, lastMoveAt: 0, lastClickAt: 999900 }), true);
  // Still and no recent click: hidden.
  assert.equal(Halo.shouldShow({ ...base, lastMoveAt: 0, lastClickAt: 0 }), false);
  // Past the idle window on both: hidden.
  assert.equal(Halo.shouldShow({ ...base, lastMoveAt: 900000, lastClickAt: 900000 }), false);
});

test("always mode ignores movement, and disabled/off-screen wins", () => {
  const still = { now: 1000000, lastMoveAt: 0, lastClickAt: 0, onScreen: true };
  assert.equal(Halo.shouldShow({ ...still, enabled: true, mode: "Always" }), true);
  assert.equal(Halo.shouldShow({ ...still, enabled: false, mode: "Always" }), false);
  assert.equal(Halo.shouldShow({ ...still, enabled: true, mode: "On move", onScreen: false }), false);
});

test("hex parsing, rounding and normalization", () => {
  assert.deepEqual(Halo.parseHexColor("#000000"), { r: 0, g: 0, b: 0 });
  assert.deepEqual(Halo.parseHexColor("ff2d55"), { r: 255, g: 45, b: 85 });
  assert.deepEqual(Halo.parseHexColor("#abc"), { r: 170, g: 187, b: 204 });
  assert.equal(Halo.parseHexColor("#12345"), null);
  assert.equal(Halo.parseHexColor("<img src=x>"), null);
  assert.equal(Halo.normalizeHex(" #ff2d55 "), "#FF2D55");
  assert.equal(Halo.normalizeHex("nope"), null);
});

test("HSV round-trips without losing the color", () => {
  const samples = ["#FF2D55", "#00FFC8", "#3B82F6", "#A855F7", "#FFB020", "#FFFFFF", "#000000", "#7F3F1F"];
  for (const hex of samples) {
    const c = Halo.parseHexColor(hex);
    const hsv = Halo.rgbToHsv(c.r, c.g, c.b);
    assert.equal(Halo.hsvToHex(hsv.h, hsv.s, hsv.v), hex, hex + " did not round-trip");
  }
  // Out-of-range inputs clamp instead of producing garbage.
  assert.equal(Halo.hsvToHex(360, 0, 1), "#FFFFFF");
  assert.equal(Halo.hsvToHex(-30, 2, 0.5), Halo.hsvToHex(330, 1, 0.5));
});

test("custom hex values survive the allowlist used by the settings", () => {
  // The picker can produce any color; cleanColor must keep it rather than
  // falling back to a preset.
  assert.equal(Halo.cleanColor("#7F3F1F", "#00FFC8"), "#7F3F1F");
  assert.equal(Halo.cleanColor("#7f3f1f", "#00FFC8"), "#7F3F1F");
});
