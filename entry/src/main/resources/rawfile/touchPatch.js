// ==================== 缓存 DOM 引用 ====================
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
}, true);

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
}, true);

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
}, true);

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
