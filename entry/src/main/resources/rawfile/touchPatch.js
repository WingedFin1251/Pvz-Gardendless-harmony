function createEvent(event, type, button) {
    let touches = event.changedTouches,
        first = touches[0];
    return new MouseEvent(type, {
        bubbles: true,
        cancelable: true,
        view: window,
        detail: 1,
        screenX: first.screenX,
        screenY: first.screenY,
        clientX: first.clientX,
        clientY: first.clientY,
        ctrlKey: false,
        altKey: false,
        shiftKey: false,
        metaKey: false,
        button: button || 0,
        relatedTarget: null
    });
}

let delay_time = 16;
let lastY = null;

document.addEventListener("touchstart", (event) => {
    if (event.touches.length === 3) {
        const touch1 = event.touches[0];
        const touch2 = event.touches[1];
        const touch3 = event.touches[2];
        setTimeout(() => {
            event.changedTouches[0].target.dispatchEvent(createEvent(event, "mousedown", 2));
        }, delay_time);
        setTimeout(() => {
            event.changedTouches[0].target.dispatchEvent(createEvent(event, "mouseup", 2));
        }, delay_time * 2);
    }

    if (event.touches.length === 2) {
        const touch1 = event.touches[0];
        const touch2 = event.touches[1];
        lastY = (touch1.clientY + touch2.clientY) / 2;
    }

    event.changedTouches[0].target.dispatchEvent(createEvent(event, "mousemove"));
    setTimeout(() => {
        event.changedTouches[0].target.dispatchEvent(createEvent(event, "mousedown"));
    }, delay_time);
    event.preventDefault();
    event.stopPropagation();
}, true);
document.addEventListener("touchmove", (event) => {

    if (event.touches.length === 2) {
        const touch1 = event.touches[0];
        const touch2 = event.touches[1];
        const currentY = (touch1.clientY + touch2.clientY) / 2;

        if (lastY !== null) {
            const deltaY = currentY - lastY;
            const wheelDelta = deltaY * -3;

            const wheelEvent = new WheelEvent('wheel', {
                deltaY: wheelDelta,
                deltaMode: 0,
                bubbles: true,
                screenX: (touch1.screenX + touch2.screenX) / 2,
                screenY: (touch1.screenY + touch2.screenY) / 2,
                clientX: (touch1.clientX + touch2.clientX) / 2,
                clientY: currentY,
                relatedTarget: null
            });
            document.getElementById("GameCanvas").dispatchEvent(wheelEvent);
        }
        lastY = currentY;
    }

    setTimeout(() => {
        event.changedTouches[0].target.dispatchEvent(createEvent(event, "mousemove"));
    }, delay_time);
    event.preventDefault();
    event.stopPropagation();
}, true);
document.addEventListener("touchend", (event) => {
    lastY = null;

    setTimeout(() => {
        event.changedTouches[0].target.dispatchEvent(createEvent(event, "mouseup"));
    }, delay_time);
    event.preventDefault();
    event.stopPropagation();
}, true);

console.log('[TouchPatch] 触摸转鼠标事件已启用，导出功能由鸿蒙下载委托处理');

// ==================== localStorage 持久化（同步到鸿蒙） ====================
(function() {
    // 需要持久化的 key 列表（根据游戏实际使用的 key 填写）
    const PERSIST_KEYS = [
        'PvZ2_PlayerProperties',
        'PvZ2_Settings'
        // 如果还有其他存档 key，请添加
    ];

    // 等待 NativeStorage 就绪
    function waitForNativeStorage(callback, maxAttempts = 50) {
        let attempts = 0;
        const check = () => {
            if (window.NativeStorage && typeof window.NativeStorage.saveToNative === 'function') {
                callback();
            } else if (attempts++ < maxAttempts) {
                setTimeout(check, 100);
            } else {
                console.warn('[localStorage] NativeStorage 未就绪，存档将不会持久化');
            }
        };
        check();
    }

    // 保存原始方法
    const originalSetItem = localStorage.setItem;
    const originalGetItem = localStorage.getItem;

    // 劫持 setItem
    localStorage.setItem = function(key, value) {
        // 先调用原始方法
        originalSetItem.call(localStorage, key, value);
        // 如果是需要持久化的 key，同步到 Native
        if (PERSIST_KEYS.includes(key) && window.NativeStorage) {
            window.NativeStorage.saveToNative(key, value).catch(e => {
                console.error(`[localStorage] 保存 ${key} 失败`, e);
            });
        }
    };

    // 启动时从 Native 恢复数据
    waitForNativeStorage(() => {
        console.log('[localStorage] 开始恢复存档');
        Promise.all(PERSIST_KEYS.map(key =>
        window.NativeStorage.loadFromNative(key).then(nativeValue => {
            // 仅当本地没有该 key 且 Native 有值时才恢复（避免覆盖用户主动保存的数据）
            if (nativeValue && !originalGetItem.call(localStorage, key)) {
                originalSetItem.call(localStorage, key, nativeValue);
                console.log(`[localStorage] 恢复 ${key} 成功`);
            }
        }).catch(e => console.error(`恢复 ${key} 失败`, e))
        )).then(() => {
            console.log('[localStorage] 存档恢复完成');
        });
    });
})();