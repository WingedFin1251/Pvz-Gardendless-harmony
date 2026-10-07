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

  const styleTags = [];
  const nativeCalls = [];      // ⚠️ 必须在 rec = {...} 之前声明（否则 TDZ：Cannot access before initialization）
  const doc = {
    body: null,
    head: null,
    visibilityState: 'visible',
    _handlers: {},
    addEventListener(type, fn) { (doc._handlers[type] ||= []).push(fn); },
    getElementById(id) { return id === 'GameCanvas' ? rec.canvas : null; },
    createElement() { return { id: '', textContent: '', appendChild() {} }; },
  };
  const canvas = makeTarget('canvas', 'GameCanvas');
  const outside = makeTarget('outside');            // 非 canvas、非面板（模拟负载里的覆盖元素）
  const panel = makeTarget('panel', 'gp-overlay');  // GP 面板
  const f1hint = makeTarget('f1hint', '', ['gp-f1-hint']);       // 负载的提示条（pointer-events:auto + click）
  const recovery = makeTarget('recovery', '', ['gp-recovery-screen']); // 启动失败恢复界面（全屏）
  const body = makeTarget('body');
  body.appendChild = (node) => { styleTags.push(node); };
  doc.body = body;
  panel.parentElement = body;
  outside.parentElement = body;
  canvas.parentElement = body;
  f1hint.parentElement = body;
  recovery.parentElement = body;

  rec = { events, canvas, outside, panel, f1hint, recovery, body, doc, styleTags, nativeCalls, ls: null };

  const nativeStorage = {
    saveToNative: (k, v) => { nativeCalls.push({ k, v }); return Promise.resolve(); },
    persistedKeys: () => Promise.resolve([]),
    loadFromNative: () => Promise.resolve(''),
    saveToNativeSync: () => 0,
  };

  const win = {
    NativeStorage: nativeStorage,
    _handlers: {},
    addEventListener(type, fn) { (win._handlers[type] ||= []).push(fn); },
  };
  const sandbox = {
    document: doc,
    window: win,
    localStorage: { _m: new Map(), getItem(k) { return this._m.has(k) ? this._m.get(k) : null; }, setItem(k, v) { this._m.set(k, String(v)); }, removeItem(k) { this._m.delete(k); } },
    console: { log: () => {}, info: () => {}, warn: () => {}, error: () => {}, debug: () => {} },
    setTimeout(fn, ms) { const id = seq++; timers.push({ id, at: now + (ms || 0), fn }); return id; },
    clearTimeout(id) { const i = timers.findIndex((t) => t.id === id); if (i >= 0) timers.splice(i, 1); },
    // 假 rAF：挂在假时钟上（16ms），这样 tick() 能驱动它
    requestAnimationFrame(fn) { const id = seq++; timers.push({ id, at: now + 16, fn }); return id; },
    cancelAnimationFrame(id) { const i = timers.findIndex((t) => t.id === id); if (i >= 0) timers.splice(i, 1); },
    setInterval() { return 0; },
    clearInterval() {},
    MouseEvent: class MouseEvent { constructor(type, init) { Object.assign(this, { type }, init); } },
    WheelEvent: class WheelEvent { constructor(type, init) { Object.assign(this, { type }, init); } },
  };
  sandbox.window.__proto__ = sandbox;
  rec.ls = sandbox.localStorage;
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

  /** 触发 window 上的事件（如 blur） */
  function fireWindow(type) {
    for (const fn of (win._handlers[type] || [])) fn({ type });
  }

  return {
    tick, fire, fireWindow, events, canvas, outside, panel, f1hint, recovery, styleTags,
    ls: rec.ls,
    doc,
    fireDoc: (type) => { for (const fn of (doc._handlers[type] || [])) fn({ type }); },
    nativeSaveCount: () => rec.nativeCalls.length,
    lastNativeValue: (k) => {
      for (let i = rec.nativeCalls.length - 1; i >= 0; i--) {
        if (rec.nativeCalls[i].k === k) { return rec.nativeCalls[i].v; }
      }
      return undefined;
    },
  };
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

// ---------- 契约 7：touch-action 兜底样式必须被注入（幂等由 getElementById 保证）----------
test('⑦ 必须给游戏容器注入 touch-action:none 兜底样式', () => {
  const m = loadMachine();
  assert.equal(m.styleTags.length, 1, '应恰好注入一个 style 标签（实际 ' + m.styleTags.length + '）');
  const css = String(m.styleTags[0].textContent || '');
  assert.ok(css.indexOf('touch-action:none') >= 0, '样式内容应含 touch-action:none，实际: ' + css);
  assert.ok(css.indexOf('#GameCanvas') >= 0, '样式应命中 #GameCanvas，实际: ' + css);
});

// ---------- 契约 8：window blur 必须释放按下态 ----------
test('⑧ window blur 时必须释放按下态（补 mouseup）', () => {
  const m = loadMachine();
  m.fire('touchstart', { target: m.canvas, points: [p(1, 80, 80)] });
  m.tick(50);
  assert.ok(typesOf(m.events).includes('mousedown'), '应先有 mousedown');
  m.fireWindow('blur');
  m.tick(50);
  assert.ok(typesOf(m.events).includes('mouseup'), 'blur 后必须补 mouseup');
});

// ---------- 契约 9：同一个键写相同值，不得重复镜像到原生（P0 去重）----------
test('⑨ 同一键写入相同值只镜像一次，值变化后必须再镜像', () => {
  const m = loadMachine();
  m.ls.setItem('PvZ2_Settings', 'A');
  m.ls.setItem('PvZ2_Settings', 'A');
  m.ls.setItem('PvZ2_Settings', 'A');
  m.tick(300);
  assert.equal(m.nativeSaveCount(), 1, '相同值重复写只应镜像一次（实际 ' + m.nativeSaveCount() + ' 次）');
  m.ls.setItem('PvZ2_Settings', 'B');
  m.tick(300);
  assert.equal(m.nativeSaveCount(), 2, '值变化后必须再镜像一次（实际 ' + m.nativeSaveCount() + ' 次）');
  // 非白名单键不该镜像
  m.ls.setItem('__not_persisted__', 'X');
  m.tick(300);
  assert.equal(m.nativeSaveCount(), 2, '非白名单键不得镜像');
});

// ---------- 契约 10：节流窗口内同键连写不同值 ⇒ 只镜像一次（最新值）----------
test('⑩ 节流窗口内同键连写不同值只镜像一次，且是最新值', () => {
  const m = loadMachine();
  m.ls.setItem('PvZ2_PlayerProperties', 'v1');
  m.tick(5);
  m.ls.setItem('PvZ2_PlayerProperties', 'v2');
  m.tick(5);
  m.ls.setItem('PvZ2_PlayerProperties', 'v3');
  assert.equal(m.nativeSaveCount(), 0, '节流窗口内不应立刻镜像');
  m.tick(300);
  assert.equal(m.nativeSaveCount(), 1, '一个窗口内只应镜像一次（实际 ' + m.nativeSaveCount() + '）');
  assert.equal(m.lastNativeValue('PvZ2_PlayerProperties'), 'v3', '镜像的必须是最新值');
});

// ---------- 契约 11：页面隐藏时必须把待发的刷出去 ----------
test('⑪ visibilitychange(hidden) 必须把待发镜像刷出去', () => {
  const m = loadMachine();
  m.ls.setItem('PvZ2_PlayerProperties', 'pending');
  assert.equal(m.nativeSaveCount(), 0, '此时还应在待发状态');
  m.doc.visibilityState = 'hidden';
  m.fireDoc('visibilitychange');
  assert.equal(m.nativeSaveCount(), 1, '隐藏时必须补发（实际 ' + m.nativeSaveCount() + '）');
  assert.equal(m.lastNativeValue('PvZ2_PlayerProperties'), 'pending', '补发的必须是待发值');
});

// ---------- 汇总 ----------
let failed = 0;
for (const r of results) {
  if (r.ok) console.log('  PASS  ' + r.name);
  else { failed++; console.log('  FAIL  ' + r.name + '\n        → ' + r.err); }
}
console.log(`\n  ${results.length - failed}/${results.length} 通过`);
process.exit(failed === 0 ? 0 : 1);
