import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
/**
 * 资源管理器
 * 提供资源预加载、缓存管理和内存优化功能
 */

// 缓存统计接口
interface CacheStats {
  totalItems: number;
  totalSize: number;
  maxSize: number;
  usagePercentage: number;
  hitRate: number;
  evictedCount: number;
}

// 资源类型枚举
export enum ResourceType {
  JSON = 'json',
  JAVASCRIPT = 'javascript',
  IMAGE = 'image',
  AUDIO = 'audio',
  FONT = 'font',
  OTHER = 'other'
}

// 资源项接口
export interface ResourceItem {
  id: string;
  path: string;
  type: ResourceType;
  data: Uint8Array | null;
  size: number;
  timestamp: number;
  accessCount: number;
  lastAccessTime: number;
  priority: number; // 1-10，优先级越高越不容易被清理
}

// 缓存配置
export interface CacheConfig {
  maxSize: number; // 最大缓存大小(字节)
  maxItems: number; // 最大缓存项数
  defaultPriority: number; // 默认优先级

}

// 预加载配置
export interface PreloadConfig {
  enabled: boolean;
  concurrentDownloads: number; // 并发下载数
  timeout: number; // 超时时间(ms)
  retryCount: number; // 重试次数
}

export class ResourceManager {
  private static instance: ResourceManager;
  private cache: Map<string, ResourceItem> = new Map();
  private cacheSize: number = 0;
  private config: CacheConfig;
  private preloadConfig: PreloadConfig;
  private loadingQueue: Set<string> = new Set();
  private failedResources: Map<string, number> = new Map(); // 失败计数
  private readonly maxFailureCount: number = 3;   // M6a：实例字段不用全大写常量风格
  // M5：真实命中/未命中计数（原来用"总访问次数 - 条目数"当命中数，是错的）
  private cacheHitCount: number = 0;
  private cacheMissCount: number = 0;
  private evictedCount: number = 0;   // 因容量不足被淘汰（LRU）的条目数，供统计日志验证
  // M6b：单例生命周期很长，只留 resourceManager 对象，不长期持有 UIAbilityContext（那是泄漏面）
  private resMgr?: resourceManager.ResourceManager;

  private constructor(
    cacheConfig?: Partial<CacheConfig>,
    preloadConfig?: Partial<PreloadConfig>
  ) {
    // 合并配置
    this.config = {
      maxSize: 80 * 1024 * 1024, // 80MB（Cocos游戏资源量大，需更大缓存）
      maxItems: 300,
      defaultPriority: 5,

    };
    
    // 手动合并cacheConfig
    if (cacheConfig) {
      if (cacheConfig.maxSize !== undefined) this.config.maxSize = cacheConfig.maxSize;
      if (cacheConfig.maxItems !== undefined) this.config.maxItems = cacheConfig.maxItems;
      if (cacheConfig.defaultPriority !== undefined) this.config.defaultPriority = cacheConfig.defaultPriority;

    }

    this.preloadConfig = {
      enabled: true,
      concurrentDownloads: 3,
      timeout: 10000, // 10秒
      retryCount: 2
    };
    
    // 手动合并preloadConfig
    if (preloadConfig) {
      if (preloadConfig.enabled !== undefined) this.preloadConfig.enabled = preloadConfig.enabled;
      if (preloadConfig.concurrentDownloads !== undefined) this.preloadConfig.concurrentDownloads = preloadConfig.concurrentDownloads;
      if (preloadConfig.timeout !== undefined) this.preloadConfig.timeout = preloadConfig.timeout;
      if (preloadConfig.retryCount !== undefined) this.preloadConfig.retryCount = preloadConfig.retryCount;
    }
  }

  /**
   * 获取单例实例
   */
  public static getInstance(
    cacheConfig?: Partial<CacheConfig>,
    preloadConfig?: Partial<PreloadConfig>
  ): ResourceManager {
    if (!ResourceManager.instance) {
      ResourceManager.instance = new ResourceManager(cacheConfig, preloadConfig);
    }
    return ResourceManager.instance;
  }

  /**
   * 设置上下文
   */
  public setContext(context: common.UIAbilityContext): void {
    // 只取需要的 resourceManager；不把 context 本身存下来
    this.resMgr = context.resourceManager;
  }

  /**
   * 预加载资源列表
   */
  public async preloadResources(resourcePaths: string[]): Promise<void> {
    if (!this.preloadConfig.enabled || resourcePaths.length === 0) {
      return;
    }

    console.info(`开始预加载 ${resourcePaths.length} 个资源`);
    const startTime = Date.now();

    // 分组处理，控制并发数
    const groups = this.chunkArray(resourcePaths, this.preloadConfig.concurrentDownloads);
    
    for (const group of groups) {
      await Promise.allSettled(
        group.map(path => this.loadAndCacheResource(path))
      );
    }

    const duration = Date.now() - startTime;
    console.info(`资源预加载完成，耗时: ${duration}ms`);
  }

  /**
   * 同步获取缓存的资源（仅查询已缓存项，不触发异步加载）
   * 用于拦截器等需要同步返回的场景
   */
  public getCachedSync(path: string): Uint8Array | null {
    const item = this.cache.get(path);
    // ⚠️ `item.data` 非空判断不够：若底层 ArrayBuffer 被**转移（detach）**，视图对象仍然 truthy，
    //    但 byteLength 会变成 0 ⇒ 直接发出去就是"200 + 空体"（JS/JSON 会静默解析失败）。
    //    这里把它当 miss（会自动回磁盘重读 ⇒ 自愈）。
    if (item && item.data && item.data.byteLength > 0) {
      this.cacheHitCount++;
      item.accessCount++;
      item.lastAccessTime = Date.now();
      return item.data;
    }
    this.cacheMissCount++;
    return null;
  }

  /**
   * 将资源直接添加到缓存（同步入口，供外部在加载后立即缓存）
   * 内部会检查大小/数量限制，超出限制则跳过
   */
  public cacheResource(path: string, data: Uint8Array): void {
    this.addToCache(path, data);
  }

  /**
   * 获取资源（异步，缓存未命中时触发加载）
   */
  public async getResource(path: string): Promise<Uint8Array | null> {
    // 检查缓存
    const cached = this.cache.get(path);
    if (cached) {
      // 更新访问统计
      cached.accessCount++;
      cached.lastAccessTime = Date.now();
      console.debug(`缓存命中: ${path}`);
      return cached.data;
    }

    // 检查是否正在加载
    if (this.loadingQueue.has(path)) {
      console.debug(`资源正在加载中: ${path}`);
      return this.waitForResource(path);
    }

    // 加载资源
    return this.loadAndCacheResource(path);
  }

  /**
   * 预加载单个资源（不阻塞）
   */
  public preloadResource(path: string): void {
    if (!this.preloadConfig.enabled || this.cache.has(path) || this.loadingQueue.has(path)) {
      return;
    }

    // 异步加载
    setTimeout(async () => {
      try {
        await this.loadAndCacheResource(path);
      } catch (error) {
        console.warn(`预加载资源失败: ${path}`, error);
      }
    }, 0);
  }

  /**
   * 清理缓存
   */
  public clearCache(): void {
    const beforeSize = this.cacheSize;
    const beforeCount = this.cache.size;
    
    this.cache.clear();
    this.cacheSize = 0;
    
    console.info(`缓存已清理，释放 ${this.formatBytes(beforeSize)}，清理了 ${beforeCount} 个资源`);
  }



  /**
   * 获取缓存统计信息
   */
  public getCacheStats(): CacheStats {
    // M5：真实的查找命中率（命中次数 / 总查找次数），不再用"总访问次数 - 条目数"那种估算
    const totalLookups = this.cacheHitCount + this.cacheMissCount;
    const hitRate = totalLookups > 0 ? (this.cacheHitCount / totalLookups) * 100 : 0;

    return {
      totalItems: this.cache.size,
      totalSize: this.cacheSize,
      maxSize: this.config.maxSize,
      usagePercentage: Math.round((this.cacheSize / this.config.maxSize) * 100),
      hitRate: Math.round(hitRate),
    evictedCount: this.evictedCount
    };
  }

  /**
   * 设置资源优先级
   */
  public setResourcePriority(path: string, priority: number): void {
    const item = this.cache.get(path);
    if (item) {
      item.priority = Math.max(1, Math.min(10, priority));
    }
  }

  /**
   * 获取资源信息
   */
  public getResourceInfo(path: string): ResourceItem | null {
    return this.cache.get(path) || null;
  }

  // 私有方法
  private async loadAndCacheResource(path: string): Promise<Uint8Array | null> {
    // 检查失败次数
    const failureCount = this.failedResources.get(path) || 0;
    if (failureCount >= this.maxFailureCount) {
      console.warn(`资源加载失败次数过多，跳过: ${path}`);
      return null;
    }

    this.loadingQueue.add(path);
    const startTime = Date.now();

    try {
      const data = await this.loadResourceWithTimeout(path);
      const duration = Date.now() - startTime;
      
      if (data && data.byteLength > 0) {
        this.addToCache(path, data);
        console.debug(`资源加载成功: ${path} (${this.formatBytes(data.byteLength)}, ${duration}ms)`);
        
        // 清除失败记录
        this.failedResources.delete(path);
        return data;
      } else {
        throw new Error('加载的资源为空');
      }
    } catch (error) {
      const duration = Date.now() - startTime;
      const newFailureCount = failureCount + 1;
      this.failedResources.set(path, newFailureCount);
      
      console.error(`资源加载失败: ${path} (尝试 ${newFailureCount}/${this.maxFailureCount}, ${duration}ms)`, error);
      
      if (newFailureCount >= this.maxFailureCount) {
        console.error(`资源加载永久失败，已跳过: ${path}`);
      }
      
      return null;
    } finally {
      this.loadingQueue.delete(path);
    }
  }

  /**
   * 带超时地读取一个 rawfile。
   * M8：原来写成 `new Promise(async (resolve, reject) => ...)` —— async executor 里抛出的错
   * 不会自动变成 reject，只能靠外层 try/catch 兜住。改成普通 async 函数 + Promise.race。
   */
  private async loadResourceWithTimeout(path: string): Promise<Uint8Array> {
    const resMgr = this.resMgr;
    if (!resMgr) {
      throw new Error('Context not set. Please call setContext() before loading resources.');
    }
    let timeoutId: number = -1;
    const timeoutPromise = new Promise<Uint8Array>((_resolve, reject) => {
      timeoutId = setTimeout(() => {
        reject(new Error(`资源加载超时: ${path}`));
      }, this.preloadConfig.timeout);
    });
    // getRawFile 自 API 9 起废弃，官方建议使用 getRawFileContent 替代（返回类型同为 Uint8Array）
    let loadPromise: Promise<Uint8Array>;
    try {
      loadPromise = resMgr.getRawFileContent(path);
    } catch (err) {
      const readError = err as BusinessError;
      // 抛出 Error（arkts-limited-throw 限制）；调用方按"加载失败"处理，只看 message
      throw new Error(`发起资源读取失败: ${path}: code=${readError.code}, message=${readError.message}`);
    }
    try {
      return await Promise.race([loadPromise, timeoutPromise]);
    } finally {
      if (timeoutId !== -1) {
        clearTimeout(timeoutId);
      }
    }
  }

  private addToCache(path: string, data: Uint8Array): void {
    const resourceType = this.detectResourceType(path);

    // 跳过音频类型：浏览器音频引擎流式播放，不会重复请求，缓存无收益且挤占关键资源空间
    if (resourceType === ResourceType.AUDIO) {
      return;
    }

    const itemSize = data.byteLength;

    // 检查资源是否过大
    if (itemSize > this.config.maxSize * 0.1) { // 超过最大缓存的10%
      console.warn(`资源过大，跳过缓存: ${path} (${this.formatBytes(itemSize)})`);
      return;
    }

    // 容量不够时**淘汰最久未用的条目**，而不是拒绝新条目。
    // 原实现是"满了就 return"，而它依赖的 smartCleanup 只看**字节**占用率（0.8），
    // 300 个小资源的字节占用远低于该阈值 ⇒ smartCleanup 每次空转 ⇒ 条数上限一旦触到就永久拒收，
    // 于是"后来才被重复请求、最该进缓存"的 JS/JSON 反而永远进不来（实测日志刷屏即此）。
    // 现在按真正的 LRU 语义处理：淘汰 lastAccessTime 最早的那些，腾出位置再插入。
    //
    // ⚠️ 2026-10-07：已**移除** smartCleanup 调用。它有三处硬伤：
    //   · 评分 `calculateCacheScore` 的四个因子有三个方向是反的（越该留的越先被删）；
    //   · 出口是"删到 60% 字节 / 240 项"，属**过度清理**，让缓存长期偏空；
    //   · 它内部 `usageRatio < cleanupThreshold` 那道闸恒不成立（唯一调用方进来时必然 >90%）。
    // 下面两个循环已经用真正的 LRU 精确执行了"字节预算"与"条数上限"两个约束，语义更清晰也更正确。
    while (this.cacheSize + itemSize > this.config.maxSize && this.cache.size > 0) {
      if (!this.evictLeastRecentlyUsed()) {
        break;
      }
    }
    while (this.cache.size >= this.config.maxItems && this.cache.size > 0) {
      if (!this.evictLeastRecentlyUsed()) {
        break;
      }
    }

    // 极端情况（单条就超过总量预算）才会走到这里；正常不会发生，保留告警以便发现异常
    if (this.cacheSize + itemSize > this.config.maxSize && this.cache.size === 0) {
      console.warn(`缓存空间不足，无法缓存: ${path} (${this.formatBytes(itemSize)})`);
      return;
    }

    const resourceItem: ResourceItem = {
      id: path,
      path,
      type: resourceType,
      data,
      size: itemSize,
      timestamp: Date.now(),
      accessCount: 1,
      lastAccessTime: Date.now(),
      priority: this.getDefaultPriority(resourceType)
    };

    // 覆盖同一个 key 时必须先扣掉旧条目，否则 cacheSize 虚高，最终会拒收所有新项
    const previous = this.cache.get(path);
    if (previous !== undefined) {
      this.cacheSize -= previous.size;
    }
    this.cache.set(path, resourceItem);
    this.cacheSize += itemSize;
    if (this.cacheSize < 0) {
      this.cacheSize = 0;   // 计费兜底，避免历史漂移把上限判断带偏
    }
  }

  private async waitForResource(path: string): Promise<Uint8Array | null> {
    return new Promise((resolve) => {
      const checkInterval = 100; // 每100ms检查一次
      const maxWaitTime = 10000; // 最大等待10秒
      let elapsed = 0;

      const intervalId = setInterval(() => {
        elapsed += checkInterval;
        
        const cached = this.cache.get(path);
        if (cached) {
          clearInterval(intervalId);
          resolve(cached.data);
          return;
        }

        if (elapsed >= maxWaitTime || !this.loadingQueue.has(path)) {
          clearInterval(intervalId);
          console.warn(`等待资源超时: ${path}`);
          resolve(null);
        }
      }, checkInterval);
    });
  }

  /**
   * 淘汰一个"最久未被访问"的条目（LRU）。
   * 返回是否真的淘汰了东西，供调用方判断能否继续。
   * 只按 lastAccessTime 这一个明确、无歧义的维度排序 —— 不掺优先级，
   * 不与任何"综合评分"式的淘汰策略混用（2026-10-07：smartCleanup 已移除）。
   */
  private evictLeastRecentlyUsed(): boolean {
    if (this.cache.size === 0) {
      return false;
    }
    let oldest: ResourceItem | null = null;
    for (const item of this.cache.values()) {
      if (oldest === null || item.lastAccessTime < oldest.lastAccessTime) {
        oldest = item;
      }
    }
    if (oldest === null) {
      return false;
    }
    this.cache.delete(oldest.id);
    this.cacheSize -= oldest.size;
    if (this.cacheSize < 0) {
      this.cacheSize = 0;
    }
    this.evictedCount++;
    return true;
  }

  private detectResourceType(path: string): ResourceType {
    const extension = path.split('.').pop()?.toLowerCase() || '';
    
    switch (extension) {
      case 'json':
        return ResourceType.JSON;
      case 'js':
      case 'ts':
      case 'ets':
        return ResourceType.JAVASCRIPT;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
      case 'svg':
        return ResourceType.IMAGE;
      case 'mp3':
      case 'wav':
      case 'ogg':
      case 'm4a':
        return ResourceType.AUDIO;
      case 'ttf':
      case 'otf':
      case 'woff':
      case 'woff2':
        return ResourceType.FONT;
      default:
        return ResourceType.OTHER;
    }
  }

  private getDefaultPriority(type: ResourceType): number {
    switch (type) {
      case ResourceType.JAVASCRIPT:
        return 10; // JavaScript文件优先级最高
      case ResourceType.JSON:
        return 8; // 配置文件优先级高
      case ResourceType.IMAGE:
        return 6; // 图片资源
      case ResourceType.AUDIO:
        return 4; // 音频资源
      case ResourceType.FONT:
        return 7; // 字体文件
      default:
        return 5; // 其他资源
    }
  }
  private chunkArray<T>(array: T[], size: number): T[][] {
    const chunks: T[][] = [];
    for (let i = 0; i < array.length; i += size) {
      chunks.push(array.slice(i, i + size));
    }
    return chunks;
  }

  private formatBytes(bytes: number): string {
    if (bytes === 0) return '0 B';
    
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }
}