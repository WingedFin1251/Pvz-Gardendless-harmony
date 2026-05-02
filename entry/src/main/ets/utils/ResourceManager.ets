import resourceManager from '@ohos.resourceManager';
import { common } from '@kit.AbilityKit';

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
  cleanupThreshold: number; // 清理阈值(0-1)
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
  private readonly MAX_FAILURE_COUNT: number = 3;
  private context?: common.UIAbilityContext;

  private constructor(
    cacheConfig?: Partial<CacheConfig>,
    preloadConfig?: Partial<PreloadConfig>
  ) {
    // 合并配置
    this.config = {
      maxSize: 50 * 1024 * 1024, // 50MB
      maxItems: 100,
      defaultPriority: 5,
      cleanupThreshold: 0.8 // 达到80%时开始清理
    };
    
    // 手动合并cacheConfig
    if (cacheConfig) {
      if (cacheConfig.maxSize !== undefined) this.config.maxSize = cacheConfig.maxSize;
      if (cacheConfig.maxItems !== undefined) this.config.maxItems = cacheConfig.maxItems;
      if (cacheConfig.defaultPriority !== undefined) this.config.defaultPriority = cacheConfig.defaultPriority;
      if (cacheConfig.cleanupThreshold !== undefined) this.config.cleanupThreshold = cacheConfig.cleanupThreshold;
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
    this.context = context;
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
   * 获取资源
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
   * 智能清理缓存（LRU + 优先级）
   */
  public smartCleanup(): void {
    const usageRatio = this.cacheSize / this.config.maxSize;
    if (usageRatio < this.config.cleanupThreshold) {
      return; // 未达到清理阈值
    }

    console.info(`开始智能清理缓存，当前使用率: ${Math.round(usageRatio * 100)}%`);
    
    // 将缓存项转换为数组并排序
    const items = Array.from(this.cache.values());
    items.sort((a, b) => {
      // 计算得分：访问频率 * 时间衰减 / 优先级
      const scoreA = this.calculateCacheScore(a);
      const scoreB = this.calculateCacheScore(b);
      return scoreA - scoreB; // 分数低的先清理
    });

    // 清理到阈值以下
    const targetSize = this.config.maxSize * (this.config.cleanupThreshold - 0.2); // 清理到60%
    let cleanedCount = 0;
    let cleanedSize = 0;

    for (const item of items) {
      if (this.cacheSize <= targetSize && this.cache.size <= this.config.maxItems * 0.8) {
        break;
      }

      this.cache.delete(item.id);
      this.cacheSize -= item.size;
      cleanedCount++;
      cleanedSize += item.size;
    }

    if (cleanedCount > 0) {
      console.info(`智能清理完成，清理了 ${cleanedCount} 个资源，释放 ${this.formatBytes(cleanedSize)}`);
    }
  }

  /**
   * 获取缓存统计信息
   */
  public getCacheStats(): CacheStats {
    const totalRequests = this.getTotalAccessCount();
    const hitCount = this.cache.size > 0 ? totalRequests - this.cache.size : 0; // 简化计算
    const hitRate = totalRequests > 0 ? (hitCount / totalRequests) * 100 : 0;

    return {
      totalItems: this.cache.size,
      totalSize: this.cacheSize,
      maxSize: this.config.maxSize,
      usagePercentage: Math.round((this.cacheSize / this.config.maxSize) * 100),
      hitRate: Math.round(hitRate)
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
    if (failureCount >= this.MAX_FAILURE_COUNT) {
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
      
      console.error(`资源加载失败: ${path} (尝试 ${newFailureCount}/${this.MAX_FAILURE_COUNT}, ${duration}ms)`, error);
      
      if (newFailureCount >= this.MAX_FAILURE_COUNT) {
        console.error(`资源加载永久失败，已跳过: ${path}`);
      }
      
      return null;
    } finally {
      this.loadingQueue.delete(path);
    }
  }

  private async loadResourceWithTimeout(path: string): Promise<Uint8Array> {
    return new Promise(async (resolve, reject) => {
      const timeoutId = setTimeout(() => {
        reject(new Error(`资源加载超时: ${path}`));
      }, this.preloadConfig.timeout);

      try {
        if (!this.context) {
          throw new Error('Context not set. Please call setContext() before loading resources.');
        }
        const data = await this.context.resourceManager.getRawFile(path);
        clearTimeout(timeoutId);
        resolve(data);
      } catch (error) {
        clearTimeout(timeoutId);
        reject(error);
      }
    });
  }

  private addToCache(path: string, data: Uint8Array): void {
    const resourceType = this.detectResourceType(path);
    const itemSize = data.byteLength;

    // 检查资源是否过大
    if (itemSize > this.config.maxSize * 0.1) { // 超过最大缓存的10%
      console.warn(`资源过大，跳过缓存: ${path} (${this.formatBytes(itemSize)})`);
      return;
    }

    // 检查缓存空间
    if (this.cacheSize + itemSize > this.config.maxSize) {
      this.smartCleanup();
      
      // 清理后再次检查
      if (this.cacheSize + itemSize > this.config.maxSize) {
        console.warn(`缓存空间不足，无法缓存: ${path}`);
        return;
      }
    }

    // 检查缓存项数量限制
    if (this.cache.size >= this.config.maxItems) {
      this.smartCleanup();
      
      if (this.cache.size >= this.config.maxItems) {
        console.warn(`缓存项数已达上限，无法缓存: ${path}`);
        return;
      }
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

    this.cache.set(path, resourceItem);
    this.cacheSize += itemSize;
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

  private calculateCacheScore(item: ResourceItem): number {
    const now = Date.now();
    const timeSinceLastAccess = now - item.lastAccessTime;
    const hoursSinceLastAccess = timeSinceLastAccess / (1000 * 60 * 60);
    
    // 时间衰减因子（最近访问的权重更高）
    const timeDecay = Math.max(0.1, 1 / (1 + hoursSinceLastAccess * 0.1));
    
    // 访问频率因子
    const frequencyFactor = Math.log1p(item.accessCount);
    
    // 优先级因子（优先级越高，分数越低）
    const priorityFactor = 1 / item.priority;
    
    // 大小因子（越大越容易被清理）
    const sizeFactor = item.size / (1024 * 1024); // MB
    
    // 综合得分
    return (sizeFactor * priorityFactor) / (frequencyFactor * timeDecay);
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

  private getTotalAccessCount(): number {
    let total = 0;
    for (const item of this.cache.values()) {
      total += item.accessCount;
    }
    return total;
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