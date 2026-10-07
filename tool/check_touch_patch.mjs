// touchPatch.js 的可执行契约测试（node:vm 载入真实文件 + 假时钟）
// 用法：node tool/check_touch_patch.mjs
// 目的：把 2026-10-06 修掉的四个回归固化成断言，防止改输入状态机时再次自己引入。
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const SRC = path.resolve(here, '../entry/src/main/resources/rawfile/touchPatch.js');
const source = fs.readFileSync(SRC, 'utf8');

const DELAY = 16;       // 与脚本里的 DELAY_TIME 对齐

/** 造一个"可接收事件"的元素桩（classes 用于模拟负载里的覆盖元素） */
function makeTarget(name, id, classes) {
  const cls = classes || [];
  const el = {
    name,
    id: id || '',
    tagName: 'DIV',
    isContentEditable: false,
    classList: { contains: (c) => cls.indexOf(c) >= 0 },
    parentElement: null,
    dispatched: [],
    dispatchEvent(ev) {
      el.dispatched.push(ev.type);
      rec.events.push({ type: ev.type, to: name });
      return true;
    },
  };
  return el;
}

/** 每次 loadMachine() 重建的记录器与假时钟 */
let rec = null;

function loadMachine() {
  const events = [];
  const timers = [];
  let now = 0;
  let seq = 1;

  const doc = {
    body: null,
    _handlers: {},
    addEventListener(type, fn) { (doc._handlers[type] ||= []).push(fn); },
    getElementById(id) { return id === 'GameCanvas' ? rec.canvas : null; },
  };
  const canvas = makeTarget('canvas', 'GameCanvas');
  const outside = makeTarget('outside');            // 非 canvas、非面板（模拟负载里的覆盖元素）
  const panel = makeTarget('panel', 'gp-overlay');  // GP 面板
  const f1hint = makeTarget('f1hint', '', ['gp-f1-hint']);       // 负载的提示条（pointer-events:auto + click）
  const recovery = makeTarget('recovery', '', ['gp-recovery-screen']); // 启动失败恢复界面（全屏）
  const body = makeTarget('body');
  doc.body = body;
  panel.parentElement = body;
  outside.parentElement = body;
  canvas.parentElement = body;
  f1hint.parentElement = body;
  recovery.parentElement = body;

  rec = { events, canvas, outside, panel, f1hint, recovery, body, doc };

  const nativeStorage = {
    saveToNative: () => Promise.resolve(),
    persistedKeys: () => Promise.resolve([]),
    loadFromNative: () => Promise.resolve(''),
    saveToNativeSync: () => 0,
  };

  const sandbox = {
    document: doc,
    window: { NativeStorage: nativeStorage },
    localStorage: { _m: new Map(), getItem(k) { return this._m.has(k) ? this._m.get(k) : null; }, setItem(k, v) { this._m.set(k, String(v)); }, removeItem(k) { this._m.delete(k); } },
    console: { log: () => {}, info: () => {}, warn: () => {}, error: () => {}, debug: () => {} },
    setTimeout(fn, ms) { const id = seq++; timers.push({ id, at: now + (ms || 0), fn }); return id; },
    clearTimeout(id) { const i = timers.findIndex((t) => t.id === id); if (i >= 0) timers.splice(i, 1); },
    setInterval() { return 0; },
    clearInterval() {},
    MouseEvent: class MouseEvent { constructor(type, init) { Object.assign(this, { type }, init); } },
    WheelEvent: class WheelEvent { constructor(type, init) { Object.assign(this, { type }, init); } },
  };
  sandbox.window.__proto__ = sandbox;
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);

  /** 推进假时钟（按到期顺序执行定时器） */
  function tick(ms) {
    const until = now + ms;
    for (let guard = 0; guard < 1000; guard++) {
      const due = timers.filter((t) => t.at <= until).sort((a, b) => a.at - b.at || a.id - b.id)[0];
      if (!due) break;
      timers.splice(timers.indexOf(due), 1);
      now = due.at;
      due.fn();
    }
    now = until;
  }

  /** 派发一个触摸事件到 document 上的处理器 */
  function fire(type, { target, points }) {
    const handler = (doc._handlers[type] || [])[0];
    if (!handler) throw new Error('没有 ' + type + ' 处理器');
    const touchList = points.map((p) => ({ identifier: p.id, screenX: p.x, screenY: p.y, clientX: p.x, clientY: p.y, target }));
    const ev = {
      type,
      target,
      touches: touchList,
      changedTouches: touchList.slice(0, 1),
      cancelable: true,
      preventDefault() {},
      stopPropagation() {},
    };
    handler(ev);
  }

  return { tick, fire, events, canvas, outside, panel, f1hint, recovery };
}

const results = [];
function test(name, fn) {
  try { fn(); results.push({ name, ok: true }); }
  catch (e) { results.push({ name, ok: false, err: e.message }); }
}
const p = (id, x, y) => ({ id, x, y });
const typesOf = (events) => events.map((e) => e.type);

// ---------- 契约 1：touchcancel 之后必须补出 mouseup ----------
test('① touchcancel 后必须有 mouseup（按下已派发的情况下）', () => {
  const m = loadMachine();
  m.fire('touchstart', { target: m.canvas, points: [p(1, 10, 10)] });
  m.tick(50);                       // 让延迟的 mousedown 落地
  assert.ok(typesOf(m.events).includes('mousedown'), '应先有 mousedown');
  m.fire('touchcancel', { target: m.canvas, points: [] });
  m.tick(50);
  assert.ok(typesOf(m.events).includes('mouseup'), 'touchcancel 后必须有 mouseup');
});

// ---------- 契约 2：短于 DELAY 的轻点必须合成完整点击 ----------
test('② 短于 16ms 的轻点必须有 mousedown + mouseup，且 down 在前', () => {
  const m = loadMachine();
  m.fire('touchstart', { target: m.canvas, points: [p(1, 20, 20)] });
  m.tick(5);                        // 早于 DELAY_TIME
  m.fire('touchend', { target: m.canvas, points: [] });
  m.tick(50);
  const t = typesOf(m.events);
  assert.ok(t.includes('mousedown'), '轻点也必须补出 mousedown');
  assert.ok(t.includes('mouseup'), '轻点必须有 mouseup');
  assert.ok(t.indexOf('mousedown') < t.lastIndexOf('mouseup'), 'down 必须先于 up');
});

// ---------- 契约 3：从游戏区拖到面板上松手，仍然要发 mouseup ----------
test('③ 拖到 GP 面板上松手仍须发 mouseup', () => {
  const m = loadMachine();
  m.fire('touchstart', { target: m.canvas, points: [p(1, 30, 30)] });
  m.tick(50);
  assert.ok(typesOf(m.events).includes('mousedown'));
  // 松手时 target 变成面板元素 —— 这正是当初漏发 up 的场景
  m.fire('touchend', { target: m.panel, points: [] });
  m.tick(50);
  assert.ok(typesOf(m.events).includes('mouseup'), '跨元素松手必须补上 mouseup');
});

// ---------- 契约 4：多指手势不得多发 down / up ----------
test('④ 第二根手指落下不得再发 mousedown，全指抬起只发一次 mouseup', () => {
  const m = loadMachine();
  m.fire('touchstart', { target: m.canvas, points: [p(1, 40, 40)] });
  m.tick(50);
  const downAfterFirst = typesOf(m.events).filter((x) => x === 'mousedown').length;
  assert.equal(downAfterFirst, 1, '第一根手指应恰好一个 mousedown');
  // 第二根手指落下（双指滚动的手势起点）
  m.fire('touchstart', { target: m.canvas, points: [p(1, 40, 40), p(2, 90, 140)] });
  m.tick(50);
  assert.equal(typesOf(m.events).filter((x) => x === 'mousedown').length, 1, '第二根手指不得再发 mousedown');
  // 抬起第一根（还剩一根）
  m.fire('touchend', { target: m.canvas, points: [p(2, 90, 140)] });
  m.tick(50);
  assert.equal(typesOf(m.events).filter((x) => x === 'mouseup').length, 0, '还剩手指时不得释放');
  // 全部抬起
  m.fire('touchend', { target: m.canvas, points: [] });
  m.tick(50);
  assert.equal(typesOf(m.events).filter((x) => x === 'mouseup').length, 1, '全指抬起恰好一次 mouseup');
});

// ---------- 契约 5：合成鼠标事件必须打在 #GameCanvas 上（B1，当前预期失败）----------
test('⑤ 落点不是 canvas 时，合成事件仍须派发到 #GameCanvas', () => {
  const m = loadMachine();
  m.fire('touchstart', { target: m.outside, points: [p(1, 50, 50)] });
  m.tick(50);
  m.fire('touchend', { target: m.outside, points: [] });
  m.tick(50);
  const bad = m.events.filter((e) => e.to === 'outside');
  assert.equal(bad.length, 0, '不应有任何合成事件打到非 canvas 元素（实际: ' + JSON.stringify(bad) + '）');
});

// ---------- 契约 6：负载的覆盖元素必须原样放行（不翻译、不 consume）----------
test('⑥ gp-f1-hint / gp-recovery-screen 上的触摸必须原样放行', () => {
  for (const [name, el] of [['gp-f1-hint', 'f1hint'], ['gp-recovery-screen', 'recovery']]) {
    const m = loadMachine();
    const target = m[el];
    m.fire('touchstart', { target, points: [p(1, 60, 60)] });
    m.tick(60);
    m.fire('touchmove', { target, points: [p(1, 70, 70)] });
    m.tick(60);
    m.fire('touchend', { target, points: [] });
    m.tick(60);
    assert.equal(m.events.length, 0, name + ' 上不应产生任何合成鼠标事件（实际: ' + JSON.stringify(m.events) + '）');
  }
});

// ---------- 汇总 ----------
let failed = 0;
for (const r of results) {
  if (r.ok) console.log('  PASS  ' + r.name);
  else { failed++; console.log('  FAIL  ' + r.name + '\n        → ' + r.err); }
}
console.log(`\n  ${results.length - failed}/${results.length} 通过`);
process.exit(failed === 0 ? 0 : 1);
