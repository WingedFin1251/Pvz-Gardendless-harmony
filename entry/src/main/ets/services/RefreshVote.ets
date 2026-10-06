import { displaySync } from '@kit.ArkGraphics2D';
import { display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

/** 一次屏幕刷新率读取的结果 */
export interface DisplaySnapshot {
  refreshRate: number;
  supported: number[];
}

/** 读取当前屏幕刷新率与支持的档位（只读，用于面板显示） */
export function readDisplayInfo(): DisplaySnapshot {
  try {
    const d = display.getDefaultDisplaySync();
    const sup = d.supportedRefreshRates;
    const supported: number[] = (sup !== undefined && sup.length > 0) ? sup : [d.refreshRate];
    return { refreshRate: d.refreshRate, supported: supported };
  } catch (err) {
    // 该函数只用于面板显示，且调用方没有 try ⇒ 这里兜底返回 60 档，绝不让面板因读显示信息而崩
    const error = err as BusinessError;
    console.warn(`读取显示信息失败，按 60Hz 兜底: code=${error.code}, message=${error.message}`);
    return { refreshRate: 60, supported: [60] };
  }
}

/**
 * 期望刷新率投票：向系统的控帧系统声明"本页面期望的帧率范围"。
 *
 * 注意这是**偏好声明、不是锁帧**：是否采纳由系统决定
 * （实测：平板把系统刷新率设为"高"时有效；手机 BRA-AL00 不被采纳）。详见 docs/MODULES.md。
 *
 * 该类只负责持有/释放 displaySync 实例，不持有任何 UI 状态。
 */
export class RefreshVote {
  private sync: displaySync.DisplaySync | undefined = undefined;

  /** 是否正在投票 */
  isRunning(): boolean {
    return this.sync !== undefined;
  }

  /**
   * 开始投票并替换上一次的实例。
   * @param expected 期望帧率（fps）
   * @param minFloor 范围下限（当前传 60：范围保持 [60, expected]，这是已验证过的写法）
   * @returns 是否已成功向系统声明
   */
  start(expected: number, minFloor: number): boolean {
    this.stop();
    const max = Math.max(expected, minFloor);
    try {
      const vote = displaySync.create();
      vote.setExpectedFrameRateRange({
        expected: expected,
        min: minFloor,
        max: max
      });
      vote.on('frame', () => {
        // 刻意留空：只为投票，不做任何绘制 / 计算
      });
      vote.start();
      this.sync = vote;
      console.info(`期望帧率投票已开启: expected=${expected} min=${minFloor} max=${max}`);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`期望帧率投票失败: code=${error.code}, message=${error.message}`);
      this.sync = undefined;
      return false;
    }
  }

  /** 停止投票并释放实例（页面不可见 / 退出时调用） */
  stop(): void {
    const sync = this.sync;
    if (sync === undefined) {
      return;
    }
    this.sync = undefined;
    try {
      sync.stop();
      sync.off('frame');
      console.info('期望帧率投票已停止');
    } catch (err) {
      const error = err as BusinessError;
      console.error(`停止期望帧率投票失败: code=${error.code}, message=${error.message}`);
    }
  }
}
