// ==================== 缓存 DOM 引用 ====================
// 说明：本文件里的 touchstart / touchmove / touchend 监听必须显式声明
// `{ capture: true, passive: false }`。Chrome（含 ArkWeb）对 window/document/body 上的
// touch 监听默认按 passive 处理，此时内部调用的 preventDefault() 会被忽略，并在每次触摸时
// 打一条 Error 级日志（真机实测 1 分钟内 143 条，且每条都要跨 ArkWeb↔ArkTS 回传）。
var _gameCanvas = null;
function getGameCanvas() {
    // 负载重载 / 画布重建后，旧引用会指向游离节点 ⇒ 校验 isConnected，失效就重查
    if (_gameCanvas && _gameCanvas.isConnected === false) {
        _gameCanvas = null;
    }
    if (!_gameCanvas) _gameCanvas = document.getElementById("GameCanvas");
    return _gameCanvas;
}

/**
 * 合成鼠标事件的**目标**。
 *
 * ⚠️ 引擎（cocos-js）的注册方式是：
 *     window.addEventListener("mousedown", …只置 _isPressed=true…)
 *     canvas.addEventListener("mousedown" / "mousemove" / "mouseup" / "wheel", …真正的处理…)
 *     window.addEventListener("mouseup", …)   // up 从任何元素都能冒泡到 window
 *   ⇒ **down / move / wheel 只有派发在 #GameCanvas 上才收得到**，而 up 打在哪儿都能到。
 *   如果按 touch.target 派发，一旦落点不是 canvas（负载里有 gp-f1-hint / gp-recovery-screen /
 *   toast 等覆盖元素），引擎就会收到"孤立的 mouseup"⇒ 游戏侧 UI.onMouseUp 把
 *   MouseClickCoolingDown 置 2 ⇒ **把紧随其后的点击吃掉**（实测症状：暂停键要点好几下）。
 *   所以这里一律解析到 canvas；取不到 canvas 时才退回命中元素。
 */
function eventTarget(hitTarget) {
    var canvas = getGameCanvas();
    if (canvas && canvas.isConnected !== false) {
        return canvas;
    }
    return hitTarget;
}

// ==================== 检测 GP-Next 面板 ====================
/**
 * 这次触摸是否应该**原样放行**（不翻译成鼠标事件、不 consume）。
 *
 * ⚠️ 名单必须覆盖负载自己画在页面上的所有可交互覆盖元素，否则它们的触摸会被我们吃掉：
 *   · gp-overlay / gp-open —— GP-Next 面板本体；
 *   · .gp-f1-hint          —— fixed 定位、pointer-events:auto 且**带 click 监听**的提示条；
 *   · .gp-recovery-screen  —— 启动失败恢复界面（position:fixed;inset:0;z-index:2147483647，**全屏**）；
 *   · #ge-toast-wrap       —— 提示容器（当前是 pointer-events:none，防御性加入）；
 *   · 表单控件（INPUT/TEXTAREA/SELECT/contenteditable）—— 需要系统原生软键盘与选择行为。
 * 判定沿祖先链向上找，命中任一即放行。
 */
function isGpPanelElement(target) {
    var el = target;
    while (el && el !== document.body) {
        if (el.id === 'gp-overlay' || el.id === 'ge-toast-wrap') {
            return true;
        }
        if (el.classList && (el.classList.contains('gp-open') ||
            el.classList.contains('gp-f1-hint') ||
            el.classList.contains('gp-recovery-screen'))) {
            return true;
        }
        var tag = el.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || el.isContentEditable === true) {
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

// ==================== 按下态看门狗（修"游戏中途触摸失效"） ====================
// 症状：游戏一开始正常，中途突然点不动植物（种植失效），重启后恢复。
// 根因：本层把触摸翻译成合成鼠标事件，但 mousedown 与 mouseup **不对称**：
//   · 浏览器可以用 touchcancel 结束一次触摸（滚动/手势被系统接管等），原实现**没监听**它
//     ⇒ mousedown 发出去了、mouseup 永远不来 ⇒ 页面停在"鼠标按住"态，Cocos 以为一直在拖拽；
//   · mousedown 是延迟 16ms 派发的，极短点击会让 mouseup 先于 mousedown；
//   · touchend 里若命中 GP 面板会提前 return ⇒ 从游戏区拖到 GP 按钮上松手也不发 mouseup。
// 这里维护一个"当前按下的目标"，任何结束路径都走 releasePress 补发 mouseup；
// 并且**下一次 touchstart 时若发现残留按下态，先补发一次**（自愈，用户无需重启）。
var _pressedTarget = null;   // 已按下（或即将按下）的目标
var _pressTimer = -1;        // 尚未执行的 mousedown 定时器
var _lastTouch = null;       // 最近一次触摸对象（用于补发 mouseup 时的坐标）
// 本次手势的"归属"：touchstart 时判定一次，之后 move/end 都只看它，不再逐事件判 target。
//   · 命中 GP 面板 ⇒ 置 null（整段手势原样放行，不翻译、不拦截）
//   · 否则 ⇒ 解析成 canvas（见 eventTarget），本次手势所有合成事件都打到它
var _gestureTarget = null;

/** 结束一次按下：必要时**补发 mousedown**（保证轻点也算点击），再发 mouseup */
function releasePress(reason, delayMs) {
    // 本次手势到此为止：归属复位（up 用的是已经复制走的 _pressedTarget，不受影响）
    _gestureTarget = null;
    if (_pressTimer !== -1) {
        // ⚠️ 这里**不能只 clearTimeout**：mousedown 是延迟 DELAY_TIME(16ms) 派发的，
        // 若轻点比 16ms 还短，clearTimeout 就等于"这次触摸从未按下" ⇒ 游戏收不到点击
        // ⇒ 表现就是"轻轻一按种不下去、要稍微停留一下才行"。
        // 正解：补发一个 mousedown（合成一次完整点击），后续照常发 mouseup。
        clearTimeout(_pressTimer);
        _pressTimer = -1;
        if (_pressedTarget) {
            try {
                _pressedTarget.dispatchEvent(createMouseEvent("mousedown", _lastTouch, 0));
            } catch (e) {
                console.error('[TouchPatch] 补发 mousedown 失败: ' + (e && e.message ? e.message : String(e)));
            }
        }
    }
    if (!_pressedTarget) {
        return;
    }
    var target = _pressedTarget;
    _pressedTarget = null;
    var touch = _lastTouch;
    var fire = function() {
        try {
            target.dispatchEvent(createMouseEvent("mouseup", touch, 0));
        } catch (e) {
            console.error('[TouchPatch] 补发 mouseup 失败: ' + (e && e.message ? e.message : String(e)));
        }
    };
    if (delayMs && delayMs > 0) {
        setTimeout(fire, delayMs);
    } else {
        fire();
    }
    if (reason) {
        // 用 warn 级：页面的 console.log/info 不进 hilog，warn 才进 —— 便于真机排查
        console.warn('[TouchPatch] 已释放残留按下态（' + reason + '）');
    }
}

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
    // ⚠️ 按下态只认"第一根手指"（touches.length === 1）。
    //    上一版在**每次** touchstart 都自愈并重新登记按下态，导致双指/三指手势
    //    （滚动、右键）也被当成"新的一次按下" ⇒ 手势中途补发 mouseup + 多发一个 mousedown
    //    ⇒ 表现为"手感变钝、点不动"。这里修掉这个回归。
    var isFirstFinger = (event.touches.length === 1);
    if (isFirstFinger) {
        // 自愈：上一次按下若没正常抬起（touchcancel / 拖到 GP 面板松手 / 极短点击），
        // 先补发一次 mouseup，再开始这次触摸 —— 用户不必重启应用。
        releasePress('新的 touchstart 到来时仍有残留按下态', 0);
    }

    if (isGpPanelElement(event.target)) {
        _gestureTarget = null;   // 面板手势：整段放行，不翻译
        return;
    }

    var touch = event.changedTouches[0];
    _lastTouch = touch;
    // 归属只判一次：本次手势之后所有合成事件都打到它（B3）
    var gestureTarget = eventTarget(touch.target);
    _gestureTarget = gestureTarget;

    if (event.touches.length === 3) {
        var downEv = createMouseEvent("mousedown", touch, 2);
        var upEv = createMouseEvent("mouseup", touch, 2);
        setTimeout(function() { gestureTarget.dispatchEvent(downEv); }, DELAY_TIME);
        setTimeout(function() { gestureTarget.dispatchEvent(upEv); }, DELAY_TIME * 2);
    }

    if (event.touches.length === 2) {
        var t1 = event.touches[0], t2 = event.touches[1];
        _lastYScroll = (t1.clientY + t2.clientY) / 2;
    }

    // 首次 MOVE 无条件分发（光标定位到触摸点）
    gestureTarget.dispatchEvent(createMouseEvent("mousemove", touch, 0));
    _lastX = touch.clientX;
    _lastY = touch.clientY;

    // 多指手势不是"新的一次按下"：只处理上面的滚动/右键分支，绝不碰按下态
    if (!isFirstFinger) {
        event.preventDefault();
        event.stopPropagation();
        return;
    }

    // DOWN 延迟执行，防止误触；同时登记"按下态"，供任何结束路径补发 mouseup
    var downTouch = touch;
    _pressedTarget = gestureTarget;   // 释放时按这个目标补发 mouseup（releasePress 里用）
    _pressTimer = setTimeout(function() {
        _pressTimer = -1;
        try {
            gestureTarget.dispatchEvent(createMouseEvent("mousedown", downTouch, 0));
        } catch (e) {
            console.error('[TouchPatch] 派发 mousedown 失败: ' + (e && e.message ? e.message : String(e)));
            _pressedTarget = null;
        }
    }, DELAY_TIME);
    event.preventDefault();
    event.stopPropagation();
}, { capture: true, passive: false });

// ==================== touchmove ====================
// ==================== MOVE 按帧合并（报告 P2⑫）====================
// 一帧内可能收到多个 touchmove。以前每个都 setTimeout 派发一次 ⇒ 同一帧里重复的 mousemove
// 让引擎做无用的命中测试、也让页内 GC 更频繁。
// 这里只保留"该帧最后一个点"，用 requestAnimationFrame 合并成一次派发；
// 没有 rAF 时（后台/受限环境）退回 16ms 定时器。
// ⚠️ 只丢中间点、保留终点 ⇒ 拖拽的最终落点不受影响。
var _pendingMove = null;
var _moveScheduled = false;
function scheduleMove(touch) {
    _pendingMove = touch;
    if (_moveScheduled) { return; }
    _moveScheduled = true;
    var flush = function() {
        _moveScheduled = false;
        var pending = _pendingMove;
        _pendingMove = null;
        if (pending && _gestureTarget) {
            _gestureTarget.dispatchEvent(createMouseEvent("mousemove", pending, 0));
        }
    };
    if (typeof requestAnimationFrame === 'function') {
        requestAnimationFrame(flush);
    } else {
        setTimeout(flush, DELAY_TIME);
    }
}

document.addEventListener("touchmove", function(event) {
    // ⚠️ 只看 touchstart 定下的归属（B3）：命中面板的手势整段放行；
    //    从游戏区拖到面板上方时**必须继续发 move**（旧实现按 event.target 提前 return ⇒ 光标/植物卡在边界）
    if (_gestureTarget === null) return;

    var touch = event.changedTouches[0];
    if (touch) { _lastTouch = touch; }   // 记住最新坐标：中断复位时用它补 up 比用陈旧坐标安全

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

    // MOVE：阈值过滤（少发）＋ 按帧合并（同帧只发最后一个点）
    var dx = touch.clientX - _lastX;
    var dy = touch.clientY - _lastY;
    if (dx * dx + dy * dy >= MOVE_THRESHOLD * MOVE_THRESHOLD) {
        _lastX = touch.clientX;
        _lastY = touch.clientY;
        scheduleMove(touch);
    }
    event.preventDefault();
    event.stopPropagation();
}, { capture: true, passive: false });

// ==================== touchend / touchcancel ====================
// ⚠️ 顺序很关键：**先**释放按下态（releasePress），**再**放行 GP 面板。
//    · 以前把"命中面板就 return"放在最前面 ⇒ 从游戏区拖到 GP 按钮上松手时永远不发 mouseup
//      （按下态卡死 ⇒ 中途点不动植物）；
//    · 但完全不 return 也不行 ⇒ 这里是 capture 阶段，preventDefault/stopPropagation 会让
//      面板自己的触摸处理收不到事件（症状：整个 GP-Next 面板点不动）。
document.addEventListener("touchend", function(event) {
    var gestureOwned = (_gestureTarget !== null);   // 先记下归属：releasePress 会把它复位
    var touch = event.changedTouches[0];
    if (touch) { _lastTouch = touch; }
    // 多指手势里"抬起一根"不等于结束按下：等所有手指都离开再释放，
    // 否则一次双指手势会中途丢掉 mouseup（上一版的另一个回归）。
    if (event.touches.length === 0) {
        _lastYScroll = null;
        releasePress(null, DELAY_TIME);   // 保持原有的 16ms 延迟，行为与改动前一致
    }
    // ⚠️ 是否 consume 也按**手势归属**判（不再看 event.target）：
    //    · 面板手势（归属为 null）⇒ 原样放行 —— 这里是 capture 阶段，一旦 preventDefault/stopPropagation，
    //      面板自己的触摸处理就再也收不到事件（症状：GP-Next 面板整个点不动）；
    //    · 游戏手势 ⇒ consume。即使松手时手指移到了面板元素上，也仍然要 consume 并补 mouseup
    //      （旧实现按 target 提前 return ⇒ 这条路径漏发 up ⇒ 按下态卡死）。
    //    顺序：释放已在上面做完（releasePress 会把 _gestureTarget 复位，所以先用局部变量记住）。
    if (gestureOwned) {
        if (event.cancelable) event.preventDefault();
        event.stopPropagation();
    }
}, { capture: true, passive: false });

// A7：touchcancel —— 浏览器/系统接管手势时用它结束触摸（不会有 touchend）。
// 原实现没监听它，导致 mousedown 之后永远没有 mouseup ⇒ 中途触摸失效、重启才恢复。
document.addEventListener("touchcancel", function(event) {
    var gestureOwned = (_gestureTarget !== null);
    _lastYScroll = null;
    var touch = event.changedTouches[0];
    if (touch) { _lastTouch = touch; }
    releasePress('touchcancel', 0);   // cancel 说明这次触摸已经作废 ⇒ 立即释放
    if (!gestureOwned) return;        // 面板手势放行（同上：释放已做，这里只管不拦）
    event.stopPropagation();
}, { capture: true, passive: false });

// ==================== 中断复位：失焦 / 切后台 / 画布消失 ====================
// 这三条路径都不会有 touchend/touchcancel，若停在"按下"态就会表现成"点不动"。
window.addEventListener('blur', function() {
    releasePress('window blur', 0);
});
document.addEventListener('visibilitychange', function() {
    if (document.visibilityState === 'hidden') {
        releasePress('page hidden', 0);
    }
});

// ==================== touch-action 兜底 ====================
// 我们靠 {capture:true,passive:false} + preventDefault 拦触摸；再补一层 CSS 兜底，
// 防止某些路径漏拦时浏览器自己去滚动/缩放。幂等：重复注入不会叠加。
(function installTouchActionStyle() {
    try {
        if (document.getElementById('touchpatch-touch-action')) { return; }
        var style = document.createElement('style');
        style.id = 'touchpatch-touch-action';
        style.textContent = '#GameDiv,#Cocos3dGameContainer,#GameCanvas{touch-action:none !important;}';
        var host = document.head || document.body;
        if (host && host.appendChild) { host.appendChild(style); }
    } catch (e) {
        console.warn('[TouchPatch] 注入 touch-action 失败: ' + (e && e.message ? e.message : String(e)));
    }
})();

console.log('[TouchPatch] 触摸转鼠标事件已启用（优化版：MOVE阈值过滤+Wheel去抖），GP面板自动放行');

// ==================== localStorage 持久化桥接 ====================
(function() {
    // 需要持久化到 Preferences 的 localStorage 键。
    //   · PvZ2_PlayerProperties / PvZ2_Settings：游戏存档与游戏设置（payload 自己读写）
    //   · gp-next-settings：GP-Next 面板自己的设置（帧率上限 / 实验开关 / overlayHotkey），
    //     由壳层的 GpNextShim 在 document-start 写入 jsModding 开关，PanelActions 也会改写它。
    // 原生侧不设第二个白名单（PreferenceStore.save/load 直接存取），所以只要这里加上即可。
    var PERSIST_KEYS = ['PvZ2_PlayerProperties', 'PvZ2_Settings', 'gp-next-settings'];

    // A1：除固定键外，**前缀匹配**的键也要持久化。
    // 原因：第三方模组的键名由它自己定义、而且是动态的（例如「植物等级扩展」全部落在 gpn_ 下：
    //   gpn_killlevel_plantkills_v3 / gpn_killlevel_plantproduces_v3 / gpn_level_log_db …），
    // 固定白名单永远列不全 —— 结果是"清一次系统缓存，模组的游玩数据就归零"。
    var PERSIST_PREFIXES = ['gpn_'];
    // 护栏：避免异常键名/超大值把 Preferences 撑坏。
    // 注意 gpn_killlevel_pvbackup_v1 是"玩家档备份"，实测可能到约 175KB，故单值上限取 256KB。
    var PERSIST_MAX_VALUE_BYTES = 256 * 1024;
    var PERSIST_MAX_KEYS = 64;
    var PERSIST_MAX_KEY_LEN = 128;
    // 取证用：每个键只上报一次（键名 + 长度），便于确认"模组到底写了哪些键、有多大"
    var reportedKeys = {};

    function shouldPersist(key) {
        if (typeof key !== 'string' || key.length === 0 || key.length > PERSIST_MAX_KEY_LEN) { return false; }
        if (PERSIST_KEYS.indexOf(key) !== -1) { return true; }
        for (var i = 0; i < PERSIST_PREFIXES.length; i++) {
            if (key.indexOf(PERSIST_PREFIXES[i]) === 0) { return true; }
        }
        return false;
    }

    function reportKeyOnce(key, value) {
        if (reportedKeys[key]) { return; }
        reportedKeys[key] = true;
        var bytes = (typeof value === 'string') ? value.length : -1;
        console.info('[localStorage][persist] ' + key + ' (' + bytes + ' 字符)');
    }

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

    // ⭐ 值未变则跳过（性能审查报告附录 A 认定的掉帧主因）。
    //   花园格子 / 骆驼关的 update() 会**逐帧**写同一个键 ⇒ 旧实现每帧都：
    //     ① 把整个 value 跨进程 JSB 搬一遍（存档实测可达 175KB），
    //     ② 在 JS 侧新建一个 Promise + catch 闭包（喂 GC）。
    //   这里记下"上次真正镜像出去的值"，相同就直接返回。
    //   注意：ArkTS 侧本来就有 flush 去抖（400ms/1500ms），真正贵的是这次**跨进程搬运**，
    //   所以去重必须做在 JS 侧、且必须在调用 saveToNative 之前。
    //   ⚠️ 用 === 比较字符串是正确的：JS 按内容比较，长度不同会立刻短路；
    //      比"每帧算一次哈希"便宜得多（后者要遍历整个 175KB）。
    var lastMirrored = {};

    localStorage.setItem = function(key, value) {
        originalSetItem.call(localStorage, key, value);
        if (shouldPersist(key) && window.NativeStorage) {
            if (typeof value === 'string' && value.length > PERSIST_MAX_VALUE_BYTES) {
                console.warn('[localStorage] 跳过持久化（值过大）: ' + key + ' ' + value.length + ' 字符');
                return;
            }
            if (lastMirrored[key] === value) {
                return;   // 值未变：不跨进程、不建 Promise
            }
            lastMirrored[key] = value;
            reportKeyOnce(key, value);
            window.NativeStorage.saveToNative(key, value).catch(function(e) {
                console.error('[localStorage] 保存 ' + key + ' 失败', e);
            });
        }
    };

    waitForNativeStorage(function() {
        console.log('[localStorage] 开始恢复存档');
        // A1 关键：清缓存后页面侧一个键都不知道，**必须由原生侧枚举**出"曾被持久化的键"。
        // 原生侧未实现该接口时退回固定白名单（保证兼容）。
        var keyListPromise;
        if (typeof window.NativeStorage.persistedKeys === 'function') {
            // ⚠️ 必须先用 Promise.resolve() 归一：JavaScriptProxy 返回的是**原生 JSPromise**，
            // 它的 .then() 不是标准 Promise 链 —— **回调的返回值会被直接丢弃**（恒定解析成 null）。
            // 少了这一层，下面的 keys.map(...) 就会拿到 null 而抛
            // "Cannot read properties of null (reading 'map')"（真机实测的正是这个错）。
            // 这与 shim 里 invoke() 的处理是同一个坑，别再踩第三遍。
            keyListPromise = Promise.resolve(window.NativeStorage.persistedKeys()).then(function(text) {
                var list = JSON.parse(text);
                if (Object.prototype.toString.call(list) !== '[object Array]' || list.length === 0) {
                    return PERSIST_KEYS;
                }
                // 与固定白名单合并去重
                var merged = PERSIST_KEYS.slice();
                for (var i = 0; i < list.length; i++) {
                    if (merged.indexOf(list[i]) === -1) { merged.push(list[i]); }
                    if (merged.length >= PERSIST_MAX_KEYS) { break; }
                }
                console.info('[localStorage] 原生侧已持久化 ' + list.length + ' 个键（含模组键）');
                return merged;
            }).catch(function(e) {
                console.warn('[localStorage] 取键列表失败，退回固定白名单', e);
                return PERSIST_KEYS;
            });
        } else {
            keyListPromise = Promise.resolve(PERSIST_KEYS);
        }
        keyListPromise.then(function(keys) {
        Promise.all(keys.map(function(key) {
            return window.NativeStorage.loadFromNative(key).then(function(nativeValue) {
                // 只要原生侧有值就覆盖：原生副本是「最后一次写入」的权威版本。
                // 原来这里还要求 !originalGetItem(key)（页面侧没有值才恢复）—— 但 gp-next-settings
                // 会被 GpNextShim 在 document-start 写入 jsModding 开关，于是它永远恢复不了；
                // 去掉该条件后，jsModding 也会随之进入持久化副本（shim 的写入同样走 setItem 覆写）。
                if (nativeValue) {
                    originalSetItem.call(localStorage, key, nativeValue);
                    console.log('[localStorage] 恢复 ' + key + ' 成功');
                }
            }).catch(function(e) { console.error('恢复 ' + key + ' 失败', e); });
        })).then(function() { console.log('[localStorage] 存档恢复完成'); });
        });
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

// ==================== A6：手动导出 / 导入（供原生侧经 runJavaScript 调用）====================
// 与上面的 A1 自动镜像**互不干扰**：A1 是 setItem 钩子被动触发，这里是原生主动调用。
// 手动导出按"求全"设计：全收，一个不落（含模组日志键）。
window.__pvzStorageExport = function () {
    try {
        var out = {};
        for (var i = 0; i < localStorage.length; i++) {
            var k = localStorage.key(i);
            out[k] = localStorage.getItem(k);
        }
        return JSON.stringify(out);
    } catch (e) {
        return '__PVZ_ERR__' + (e && e.message ? e.message : String(e));
    }
};

// 导入的**同步**应用（A6.2）：
//   · 由原生侧把待应用 JSON **内联进 document-start 的注入脚本**后调用，
//     因此这一步发生在**负载任何代码之前** → 游戏启动时读到的就是导入后的数据。
//   · 之所以必须同步：若在游戏运行中写 localStorage，游戏内存里的旧存档会被定期/退出时写回，
//     把导入结果覆盖掉（实测游戏会周期性回写存档）。
window.__pvzApplyImportSync = function (jsonText) {
    try {
        var obj = JSON.parse(jsonText);
        if (!obj || typeof obj !== 'object') { return -1; }
        var n = 0;
        for (var k in obj) {
            if (Object.prototype.hasOwnProperty.call(obj, k) && typeof obj[k] === 'string') {
                // 只覆盖、从不删除：文件里没有的键一律保留
                localStorage.setItem(k, obj[k]);
                n++;
            }
        }
        console.info('[A6] 已在文档开头同步应用导入数据: ' + n + ' 个键');
        // 应用成功即清掉暂存位（写空串；读取侧把空串视为"没有待应用数据"），保证只应用一次。
        // 复用既有的 saveToNative：PreferenceStore.save 不做键名白名单校验，只限值大小。
        if (window.NativeStorage && typeof window.NativeStorage.saveToNative === 'function') {
            Promise.resolve(window.NativeStorage.saveToNative('__a6_pending_import', '')).catch(function () {});
        }
        return n;
    } catch (e) {
        console.error('[A6] 同步应用导入数据失败: ' + (e && e.message ? e.message : String(e)));
        return -1;
    }
};
