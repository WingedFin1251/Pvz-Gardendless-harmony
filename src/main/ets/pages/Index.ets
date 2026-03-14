import { webview } from '@kit.ArkWeb';

// 触摸 polyfill 脚本（请将完整脚本粘贴在此）
const TOUCH_POLYFILL_SCRIPT = `
(function() {
  // 存储当前活动的触摸点
  const activeTouches = new Map(); // identifier -> { clientX, clientY, target }
  let lastPinchDistance = null;     // 上次两指距离，用于计算滚轮 delta

  // 辅助函数：计算两指中心点
  function getTouchCenter(touches) {
    if (touches.length === 0) return null;
    let sumX = 0, sumY = 0;
    for (let t of touches) {
      sumX += t.clientX;
      sumY += t.clientY;
    }
    return { x: sumX / touches.length, y: sumY / touches.length };
  }

  // 辅助函数：计算两指距离
  function getDistance(t1, t2) {
    const dx = t1.clientX - t2.clientX;
    const dy = t1.clientY - t2.clientY;
    return Math.sqrt(dx * dx + dy * dy);
  }

  // 辅助函数：派发鼠标事件
  function dispatchMouseEvent(type, clientX, clientY, target, button = 0, buttons = 1) {
    const event = new MouseEvent(type, {
      view: window,
      bubbles: true,
      cancelable: true,
      clientX: clientX,
      clientY: clientY,
      button: button,
      buttons: buttons
    });
    target.dispatchEvent(event);
  }

  // 辅助函数：派发滚轮事件
  function dispatchWheelEvent(clientX, clientY, deltaY, target) {
    const event = new WheelEvent('wheel', {
      view: window,
      bubbles: true,
      cancelable: true,
      clientX: clientX,
      clientY: clientY,
      deltaY: deltaY
    });
    target.dispatchEvent(event);
  }

  // 阻止页面默认滚动/缩放，确保游戏独占触摸事件
  document.addEventListener('touchstart', (e) => {
    e.preventDefault();
    const touches = e.touches;

    if (touches.length === 1) {
      // 单指：模拟 mousedown
      const touch = touches[0];
      const target = touch.target;
      dispatchMouseEvent('mousedown', touch.clientX, touch.clientY, target, 0, 1);
      activeTouches.set(touch.identifier, { clientX: touch.clientX, clientY: touch.clientY, target });
    } else if (touches.length === 2) {
      // 双指：记录初始距离
      const t1 = touches[0], t2 = touches[1];
      lastPinchDistance = getDistance(t1, t2);
      activeTouches.set(t1.identifier, { clientX: t1.clientX, clientY: t1.clientY, target: t1.target });
      activeTouches.set(t2.identifier, { clientX: t2.clientX, clientY: t2.clientY, target: t2.target });
    }
  }, { passive: false });

  document.addEventListener('touchmove', (e) => {
    e.preventDefault();
    const touches = e.touches;

    if (touches.length === 1) {
      // 单指移动：模拟 mousemove
      const touch = touches[0];
      const target = touch.target;
      dispatchMouseEvent('mousemove', touch.clientX, touch.clientY, target, 0, 1);
      if (activeTouches.has(touch.identifier)) {
        activeTouches.set(touch.identifier, { clientX: touch.clientX, clientY: touch.clientY, target });
      }
    } else if (touches.length === 2) {
      // 双指移动：根据距离变化模拟滚轮
      const t1 = touches[0], t2 = touches[1];
      const currentDistance = getDistance(t1, t2);
      if (lastPinchDistance !== null) {
        const deltaDistance = currentDistance - lastPinchDistance;
        const center = getTouchCenter([t1, t2]);
        if (center) {
          // 使用第一个 touch 的目标作为事件目标（一般相同）
          const target = t1.target;
          // 系数 5 可调整滚轮灵敏度
          dispatchWheelEvent(center.x, center.y, deltaDistance * 5, target);
        }
      }
      lastPinchDistance = currentDistance;
      // 更新存储
      [t1, t2].forEach(t => {
        if (activeTouches.has(t.identifier)) {
          activeTouches.set(t.identifier, { clientX: t.clientX, clientY: t.clientY, target: t.target });
        }
      });
    }
  }, { passive: false });

  document.addEventListener('touchend', (e) => {
    e.preventDefault();
    const changedTouches = e.changedTouches;

    for (let i = 0; i < changedTouches.length; i++) {
      const touch = changedTouches[i];
      const target = touch.target;
      dispatchMouseEvent('mouseup', touch.clientX, touch.clientY, target, 0, 0);
      activeTouches.delete(touch.identifier);
    }

    // 如果剩余触摸少于2，重置 pinch 状态
    if (e.touches.length < 2) {
      lastPinchDistance = null;
    }
  }, { passive: false });

  document.addEventListener('touchcancel', (e) => {
    e.preventDefault();
    const changedTouches = e.changedTouches;

    for (let i = 0; i < changedTouches.length; i++) {
      const touch = changedTouches[i];
      const target = touch.target;
      dispatchMouseEvent('mouseup', touch.clientX, touch.clientY, target, 0, 0);
      activeTouches.delete(touch.identifier);
    }

    if (e.touches.length < 2) {
      lastPinchDistance = null;
    }
  }, { passive: false });
})();
`;

@Entry
@Component
struct CocosJSApp {
  private webController: webview.WebviewController = new webview.WebviewController();

  build() {
    Column() {
      Web({ src: "https://cocos.local/index.html", controller: this.webController })
        .width('100%')
        .height('100%')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onControllerAttached(() => {
          webview.WebviewController.setWebDebuggingAccess(true);
        })
        .onPageEnd(() => {
          // 注入触摸 polyfill
          if (this.webController) {
            this.webController.runJavaScript(TOUCH_POLYFILL_SCRIPT)
              .then(() => console.log('触摸 polyfill 注入成功'))
              .catch((err: Error) => console.error('注入失败:', err));
          }
        })
        .onInterceptRequest((event) => {
          if (!event) return null;
          const url = event.request.getRequestUrl();
          if (url.startsWith("https://cocos.local/")) {
            let rawFilePath = decodeURIComponent(url.replace("https://cocos.local/", ""));
            rawFilePath = rawFilePath.split('?')[0];
            try {
              const mimeType = this.getMimeType(rawFilePath);
              const response = new WebResourceResponse();
              response.setResponseData($rawfile(rawFilePath));
              response.setResponseEncoding('utf-8');
              response.setResponseMimeType(mimeType);
              response.setResponseCode(200);
              response.setReasonMessage('OK');
              response.setResponseIsReady(true);
              return response;
            } catch (error) {
              console.error(`拦截器读取文件失败: ${rawFilePath}`, error);
              return null;
            }
          }
          return null;
        })
    }
    .width('100%')
    .height('100%')
    .padding(0)
    .margin(0)
  }

  private getMimeType(fileName: string): string {
    const ext = fileName.split('.').pop()?.toLowerCase();
    switch (ext) {
      case 'html': return 'text/html';
      case 'js': return 'application/javascript';
      case 'wasm': return 'application/wasm';
      case 'json': return 'application/json';
      case 'css': return 'text/css';
      case 'png': return 'image/png';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'webp': return 'image/webp';
      case 'svg': return 'image/svg+xml';
      case 'data': return 'application/octet-stream';
      default: return 'text/plain';
    }
  }
}