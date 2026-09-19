// ==================== 缓存 DOM 引用 ====================
// 说明：本文件里的 touchstart / touchmove / touchend 监听必须显式声明
// `{ capture: true, passive: false }`。Chrome（含 ArkWeb）对 window/document/body 上的
// touch 监听默认按 passive 处理，此时内部调用的 preventDefault() 会被忽略，并在每次触摸时
// 打一条 Error 级日志（真机实测 1 分钟内 143 条，且每条都要跨 ArkWeb↔ArkTS 回传）。
var _gameCanvas = null;
function getGameCanvas() {
    if (!_gameCanvas) _gameCanvas = document.getElementById("GameCanvas");
    return _gameCanvas;
}

// ==================== 检测 GP-Next 面板 ====================
function isGpPanelElement(target) {
    var el = target;
    while (el && el !== document.body) {
        if (el.id === 'gp-overlay' || (el.classList && el.classList.contains('gp-open'))) {
            return true;
        }
        el = el.parentElement;
    }
    return false;
}

// ==================== 触摸转鼠标事件（优化版） ====================
var DELAY_TIME = 16;
var MOVE_THRESHOLD = 3; // 像素移动阈值：参考Android版 moveThreshold=20f/density≈7物理px，折半为3CSSpx
var _lastX = 0, _lastY = 0, _lastYScroll = null;

function createMouseEvent(type, touch, button) {
    return new MouseEvent(type, {
        bubbles: true,
        cancelable: true,
        view: window,
        screenX: touch.screenX,
        screenY: touch.screenY,
        clientX: touch.clientX,
        clientY: touch.clientY,
        button: button || 0,
        ctrlKey: false,
        altKey: false,
        shiftKey: false,
        metaKey: false,
        relatedTarget: null
    });
}

// ==================== touchstart ====================
document.addEventListener("touchstart", function(event) {
    if (isGpPanelElement(event.target)) return;

    var touch = event.changedTouches[0];

    if (event.touches.length === 3) {
        var downEv = createMouseEvent("mousedown", touch, 2);
        var upEv = createMouseEvent("mouseup", touch, 2);
        setTimeout(function() { touch.target.dispatchEvent(downEv); }, DELAY_TIME);
        setTimeout(function() { touch.target.dispatchEvent(upEv); }, DELAY_TIME * 2);
    }

    if (event.touches.length === 2) {
        var t1 = event.touches[0], t2 = event.touches[1];
        _lastYScroll = (t1.clientY + t2.clientY) / 2;
    }

    // 首次 MOVE 无条件分发（光标定位到触摸点）
    touch.target.dispatchEvent(createMouseEvent("mousemove", touch, 0));
    _lastX = touch.clientX;
    _lastY = touch.clientY;

    // DOWN 延迟执行，防止误触
    var downTouch = touch;
    setTimeout(function() {
        downTouch.target.dispatchEvent(createMouseEvent("mousedown", downTouch, 0));
    }, DELAY_TIME);
    event.preventDefault();
    event.stopPropagation();
}, { capture: true, passive: false });

// ==================== touchmove ====================
document.addEventListener("touchmove", function(event) {
    if (isGpPanelElement(event.target)) return;

    var touch = event.changedTouches[0];

    if (event.touches.length === 2) {
        var t1 = event.touches[0], t2 = event.touches[1];
        var currentY = (t1.clientY + t2.clientY) / 2;

        if (_lastYScroll !== null) {
            var deltaY = currentY - _lastYScroll;
            if (Math.abs(deltaY) > 2) { // 去抖动：微小滚动不创建WheelEvent
                var canvas = getGameCanvas();
                if (canvas) {
                    canvas.dispatchEvent(new WheelEvent('wheel', {
                        deltaY: deltaY * -3,
                        deltaMode: 0,
                        bubbles: true,
                        screenX: (t1.screenX + t2.screenX) / 2,
                        screenY: (t1.screenY + t2.screenY) / 2,
                        clientX: (t1.clientX + t2.clientX) / 2,
                        clientY: currentY,
                        relatedTarget: null
                    }));
                }
            }
        }
        _lastYScroll = currentY;
    }

    // MOVE：保留原异步时序，增加阈值过滤减少GC
    var dx = touch.clientX - _lastX;
    var dy = touch.clientY - _lastY;
    if (dx * dx + dy * dy >= MOVE_THRESHOLD * MOVE_THRESHOLD) {
        _lastX = touch.clientX;
        _lastY = touch.clientY;
        var moveTouch = touch;
        setTimeout(function() {
            moveTouch.target.dispatchEvent(createMouseEvent("mousemove", moveTouch, 0));
        }, DELAY_TIME);
    }
    event.preventDefault();
    event.stopPropagation();
}, { capture: true, passive: false });

// ==================== touchend ====================
document.addEventListener("touchend", function(event) {
    if (isGpPanelElement(event.target)) return;

    _lastYScroll = null;
    var touch = event.changedTouches[0];
    setTimeout(function() {
        touch.target.dispatchEvent(createMouseEvent("mouseup", touch, 0));
    }, DELAY_TIME);
    if (event.cancelable) event.preventDefault();
    event.stopPropagation();
}, { capture: true, passive: false });

console.log('[TouchPatch] 触摸转鼠标事件已启用（优化版：MOVE阈值过滤+Wheel去抖），GP面板自动放行');

// ==================== localStorage 持久化桥接 ====================
(function() {
    var PERSIST_KEYS = ['PvZ2_PlayerProperties', 'PvZ2_Settings'];

    function waitForNativeStorage(callback, maxAttempts) {
        maxAttempts = maxAttempts || 50;
        var attempts = 0;
        var check = function() {
            if (window.NativeStorage && typeof window.NativeStorage.saveToNative === 'function') {
                callback();
            } else if (++attempts < maxAttempts) {
                setTimeout(check, 100);
            } else {
                console.warn('[localStorage] NativeStorage 未就绪，存档将不会持久化');
            }
        };
        check();
    }

    var originalSetItem = localStorage.setItem;
    var originalGetItem = localStorage.getItem;

    localStorage.setItem = function(key, value) {
        originalSetItem.call(localStorage, key, value);
        if (PERSIST_KEYS.indexOf(key) !== -1 && window.NativeStorage) {
            window.NativeStorage.saveToNative(key, value).catch(function(e) {
                console.error('[localStorage] 保存 ' + key + ' 失败', e);
            });
        }
    };

    waitForNativeStorage(function() {
        console.log('[localStorage] 开始恢复存档');
        Promise.all(PERSIST_KEYS.map(function(key) {
            return window.NativeStorage.loadFromNative(key).then(function(nativeValue) {
                if (nativeValue && !originalGetItem.call(localStorage, key)) {
                    originalSetItem.call(localStorage, key, nativeValue);
                    console.log('[localStorage] 恢复 ' + key + ' 成功');
                }
            }).catch(function(e) { console.error('恢复 ' + key + ' 失败', e); });
        })).then(function() { console.log('[localStorage] 存档恢复完成'); });
    });
})();

// ==================== 性能档位（可调常量） ====================
// 真机实测（MatePad 11.5"S / DMG-W00，ArkWeb 6.1.0.120）：逐帧成本的 73~85% 是页内 JS 执行
// （CDP Profiler + Performance 指标实测），其中组件 update 仅约 11%，其余在引擎内部的
// 渲染数据更新（约 24%）与 DragonBones 骨骼推进（约 16%）以及 GC（约 9~10%）。
// 因此下面这些开关对本工程的帧率都没有正向收益，默认全部关闭；保留它们是为了后续按机型实验。
//   FRAME_RATE_CAP : 0 = 不改（payload 自身会设成 999，即不限帧）；>0 = 上限该帧率。
//                    注意：实测在重载场景把上限设为 60 反而更慢（交替 A/B：999 三轮 16.44/16.10/17.04 fps
//                    vs 60 三轮 12.77/14.82/15.14 fps，每帧 JS 从 45.6 ms 升到 51.1 ms），故默认 0。
//   RENDER_SCALE   : 0 = 不改（原生后备缓冲为 2.0 倍像素比）；例如 1.25 = 降低渲染分辨率
//   DISABLE_MSAA   : true = 创建 WebGL 上下文时关闭 MSAA
// 详见 docs/SHELL_PERF_2026-09-19.md。
(function () {
    var FRAME_RATE_CAP = 0;
    var RENDER_SCALE = 0;
    var DISABLE_MSAA = false;

    // 1) 渲染分辨率 / MSAA：必须在引擎创建 canvas 与 WebGL 上下文之前生效
    try {
        if (RENDER_SCALE > 0) {
            Object.defineProperty(window, 'devicePixelRatio', {
                configurable: true,
                get: function () { return RENDER_SCALE; }
            });
        }
        if (DISABLE_MSAA) {
            var origGetContext = HTMLCanvasElement.prototype.getContext;
            HTMLCanvasElement.prototype.getContext = function (type, attrs) {
                if (type === 'webgl2' || type === 'webgl' || type === 'experimental-webgl') {
                    attrs = Object.assign({}, attrs || {}, { antialias: false });
                }
                return origGetContext.call(this, type, attrs);
            };
        }
    } catch (e) {
        console.warn('[perf] 渲染档位注入失败', e);
    }

    // 2) 帧率上限：必须反复纠正，一次赋值会被 payload 覆盖
    //    实测：payload 在引擎就绪后会把 frameRate 设为 999，一次性赋值随即失效
    //    （发布版运行时读到的就是 999），因此在启动后 30 秒内持续纠正。
    if (FRAME_RATE_CAP > 0) {
        var tries = 0;
        var timer = setInterval(function () {
            tries++;
            try {
                if (window.cc && window.cc.game && window.cc.game.frameRate !== FRAME_RATE_CAP) {
                    window.cc.game.frameRate = FRAME_RATE_CAP;
                    console.log('[perf] 帧率上限设为 ' + FRAME_RATE_CAP);
                }
            } catch (e) { /* ignore */ }
            if (tries > 300) { clearInterval(timer); }   // 100ms × 300 = 30s
        }, 100);
    }
})();

// ==================== GP-Next 血条覆盖层降频（默认关闭） ====================
// 真机实测（MatePad 11.5"S / DMG-W00，inGameScene，2026-09-19）：
//   hp-overlay 用 setInterval 每 200 ms 跑一次，每次约 16 ms，占用主线程 81.4 ms/s（约 8% 墙钟）；
//   但其中只有约 1.7 ms/次 是 JS 执行，其余是 Label 文本重绘 + 纹理上传（原生侧，不计入 ScriptDuration）。
//   机制：它每次都对 primaryLabel.string / secondaryLabel.string 无条件赋值，触发 Cocos 重新栅格化文本。
//   实测把周期放宽到 1/3：81.4 → 26.4 ms/s，主线程「非脚本」占比 16.6% → 10.9%（−5.7 点）。
//   HP_OVERLAY_INTERVAL_MULTIPLIER = 0 关闭（默认，不安装任何钩子）；3 = 每 3 个周期执行一次。
// 注意：这是**缓解**，不是根因修复——
//   ① 根因上游修一行即可：赋值前比较字符串是否变化（并在 active 未变时不重复赋值）；
//   ② GP-Next 设置里把「血条显示」的植物/僵尸/墓碑三项全关，该定时器会自行空转，效果比降频更彻底；
//   ③ 识别方式是注册栈里匹配 'hp-overlay-'，负载更新后若模块改名会失效（失效时行为不变，安全）。
// 详见 docs/GAME_SIDE_OPTIMIZATION.md。
(function () {
    var HP_OVERLAY_INTERVAL_MULTIPLIER = 0;
    if (HP_OVERLAY_INTERVAL_MULTIPLIER <= 1) { return; }   // 关闭时不安装钩子，零行为变化
    try {
        var origSetInterval = window.setInterval;
        window.setInterval = function (fn, ms) {
            var args = Array.prototype.slice.call(arguments, 2);
            if (typeof fn !== 'function') { return origSetInterval.apply(window, arguments); }
            var stack = '';
            try { stack = new Error().stack || ''; } catch (e) { /* ignore */ }
            if (stack.indexOf('hp-overlay-') === -1) { return origSetInterval.apply(window, arguments); }
            var n = 0;
            var wrapped = function () {
                if ((n++ % HP_OVERLAY_INTERVAL_MULTIPLIER) !== 0) { return; }
                return fn.apply(this, arguments);
            };
            console.log('[perf] hp-overlay 定时器降频 x' + HP_OVERLAY_INTERVAL_MULTIPLIER + '（原周期 ' + ms + ' ms）');
            return origSetInterval.apply(window, [wrapped, ms].concat(args));
        };
    } catch (e) {
        console.warn('[perf] hp-overlay 降频注入失败', e);
    }
})();
