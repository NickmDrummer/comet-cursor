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
