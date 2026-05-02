/**
 * 性能监控工具类
 * 用于监控应用性能指标，包括FPS、内存、加载时间等
 */

// 性能指标接口
export interface PerformanceMetrics {
  fps: number;
  memoryUsage: number;
  loadTime: number;
  cacheHitRate: number;
  renderTime: number;
  networkRequests: number;
  errors: number;
  timestamp: number;
}

// 性能事件类型
export enum PerformanceEventType {
  RENDER_START = 'render_start',
  RENDER_END = 'render_end',
  RESOURCE_LOAD_START = 'resource_load_start',
  RESOURCE_LOAD_END = 'resource_load_end',
  CACHE_HIT = 'cache_hit',
  CACHE_MISS = 'cache_miss',
  ERROR = 'error',
  MEMORY_WARNING = 'memory_warning'
}

// 性能事件数据接口
export interface RenderEndData {
  renderTime: number;
}

export interface ResourceLoadStartData {
  resourceId: string;
}

export interface ResourceLoadEndData {
  resourceId: string;
  loadTime: number;
}

export interface ErrorData {
  error: Error;
}

export interface MemoryWarningData {
  warnings: string[];
}

// 性能事件接口
export interface PerformanceEvent {
  type: PerformanceEventType;
  timestamp: number;
  data?: RenderEndData | ResourceLoadStartData | ResourceLoadEndData | ErrorData | MemoryWarningData;
}

// 警告阈值配置
interface WarningThresholds {
  fps: number; // FPS警告阈值
  memory: number; // 内存警告阈值(MB)
  renderTime: number; // 渲染时间警告阈值(ms)
}

// 缓存统计接口
interface CacheStats {
  hits: number;
  misses: number;
  hitRate: number;
}

// 渲染统计接口
interface RenderStats {
  averageRenderTime: number;
  totalRenders: number;
}

// 性能报告接口
interface PerformanceReport {
  summary: PerformanceMetrics;
  config: PerformanceMonitorConfig;
  eventsCount: number;
  cacheStats: CacheStats;
  renderStats: RenderStats;
  recentEvents: PerformanceEvent[];
}

// 性能监控配置
export interface PerformanceMonitorConfig {
  enabled: boolean;
  sampleInterval: number; // 采样间隔(ms)
  maxSamples: number; // 最大样本数
  warningThresholds: WarningThresholds;
}

export class PerformanceMonitor {
  private static instance: PerformanceMonitor;
  private metrics: PerformanceMetrics;
  private events: PerformanceEvent[] = [];
  private config: PerformanceMonitorConfig;
  private frameCount: number = 0;
  private lastSampleTime: number = 0;
  private sampleIntervalId?: number;
  private renderStartTime: number = 0;
  private totalRenderTime: number = 0;
  private renderCount: number = 0;
  private resourceLoads: Map<string, number> = new Map();
  private cacheHits: number = 0;
  private cacheMisses: number = 0;
  private networkRequestCount: number = 0;
  private errorCount: number = 0;

  private constructor(config?: Partial<PerformanceMonitorConfig>) {
    this.config = {
      enabled: true,
      sampleInterval: 5000, // 5秒采样一次
      maxSamples: 1000,
      warningThresholds: {
        fps: 30, // 低于30FPS警告
        memory: 200, // 超过200MB警告
        renderTime: 16 // 超过16ms/帧警告
      }
    };

    // 手动合并配置
    if (config) {
      if (config.enabled !== undefined) this.config.enabled = config.enabled;
      if (config.sampleInterval !== undefined) this.config.sampleInterval = config.sampleInterval;
      if (config.maxSamples !== undefined) this.config.maxSamples = config.maxSamples;
      if (config.warningThresholds) {
        if (config.warningThresholds.fps !== undefined) this.config.warningThresholds.fps = config.warningThresholds.fps;
        if (config.warningThresholds.memory !== undefined) this.config.warningThresholds.memory = config.warningThresholds.memory;
        if (config.warningThresholds.renderTime !== undefined) this.config.warningThresholds.renderTime = config.warningThresholds.renderTime;
      }
    }

    this.metrics = {
      fps: 0,
      memoryUsage: 0,
      loadTime: 0,
      cacheHitRate: 0,
      renderTime: 0,
      networkRequests: 0,
      errors: 0,
      timestamp: Date.now()
    };

    this.lastSampleTime = Date.now();
  }

  /**
   * 获取单例实例
   */
  public static getInstance(config?: Partial<PerformanceMonitorConfig>): PerformanceMonitor {
    if (!PerformanceMonitor.instance) {
      PerformanceMonitor.instance = new PerformanceMonitor(config);
    }
    return PerformanceMonitor.instance;
  }

  /**
   * 启动性能监控
   */
  public start(): void {
    if (!this.config.enabled || this.sampleIntervalId) {
      return;
    }

    console.info('性能监控已启动');
    
    // 开始采样
    this.sampleIntervalId = setInterval(() => {
      this.collectMetrics();
      this.checkWarnings();
    }, this.config.sampleInterval);
  }

  /**
   * 停止性能监控
   */
  public stop(): void {
    if (this.sampleIntervalId) {
      clearInterval(this.sampleIntervalId);
      this.sampleIntervalId = undefined;
      console.info('性能监控已停止');
    }
  }

  /**
   * 记录渲染开始
   */
  public recordRenderStart(): void {
    if (!this.config.enabled) return;
    this.renderStartTime = Date.now();
    this.recordEvent(PerformanceEventType.RENDER_START);
  }

  /**
   * 记录渲染结束
   */
  public recordRenderEnd(): void {
    if (!this.config.enabled || this.renderStartTime === 0) return;
    
    const renderTime = Date.now() - this.renderStartTime;
    this.totalRenderTime += renderTime;
    this.renderCount++;
    this.frameCount++;
    
    this.recordEvent(PerformanceEventType.RENDER_END, { renderTime } as RenderEndData);
    this.renderStartTime = 0;
  }

  /**
   * 记录资源加载开始
   */
  public recordResourceLoadStart(resourceId: string): void {
    if (!this.config.enabled) return;
    this.resourceLoads.set(resourceId, Date.now());
    this.recordEvent(PerformanceEventType.RESOURCE_LOAD_START, { resourceId } as ResourceLoadStartData);
  }

  /**
   * 记录资源加载结束
   */
  public recordResourceLoadEnd(resourceId: string): void {
    if (!this.config.enabled) return;
    
    const startTime = this.resourceLoads.get(resourceId);
    if (startTime) {
      const loadTime = Date.now() - startTime;
      this.resourceLoads.delete(resourceId);
      this.recordEvent(PerformanceEventType.RESOURCE_LOAD_END, { 
        resourceId, 
        loadTime 
      } as ResourceLoadEndData);
    }
  }

  /**
   * 记录缓存命中
   */
  public recordCacheHit(): void {
    if (!this.config.enabled) return;
    this.cacheHits++;
    this.recordEvent(PerformanceEventType.CACHE_HIT);
  }

  /**
   * 记录缓存未命中
   */
  public recordCacheMiss(): void {
    if (!this.config.enabled) return;
    this.cacheMisses++;
    this.recordEvent(PerformanceEventType.CACHE_MISS);
  }

  /**
   * 记录网络请求
   */
  public recordNetworkRequest(): void {
    if (!this.config.enabled) return;
    this.networkRequestCount++;
  }

  /**
   * 记录错误
   */
  public recordError(error: Error): void {
    if (!this.config.enabled) return;
    this.errorCount++;
    this.recordEvent(PerformanceEventType.ERROR, { error } as ErrorData);
  }

  /**
   * 获取当前性能指标
   */
  public getMetrics(): PerformanceMetrics {
    return {
      fps: this.metrics.fps,
      memoryUsage: this.metrics.memoryUsage,
      loadTime: this.metrics.loadTime,
      cacheHitRate: this.metrics.cacheHitRate,
      renderTime: this.metrics.renderTime,
      networkRequests: this.metrics.networkRequests,
      errors: this.metrics.errors,
      timestamp: this.metrics.timestamp
    };
  }

  /**
   * 获取性能事件历史
   */
  public getEventHistory(limit: number = 100): PerformanceEvent[] {
    return this.events.slice(-limit);
  }

  /**
   * 重置性能数据
   */
  public reset(): void {
    this.metrics = {
      fps: 0,
      memoryUsage: 0,
      loadTime: 0,
      cacheHitRate: 0,
      renderTime: 0,
      networkRequests: 0,
      errors: 0,
      timestamp: Date.now()
    };
    
    this.events = [];
    this.frameCount = 0;
    this.lastSampleTime = Date.now();
    this.totalRenderTime = 0;
    this.renderCount = 0;
    this.resourceLoads.clear();
    this.cacheHits = 0;
    this.cacheMisses = 0;
    this.networkRequestCount = 0;
    this.errorCount = 0;
    
    console.info('性能数据已重置');
  }

  /**
   * 导出性能报告
   */
  public exportReport(): string {
    const report: PerformanceReport = {
      summary: this.metrics,
      config: this.config,
      eventsCount: this.events.length,
      cacheStats: {
        hits: this.cacheHits,
        misses: this.cacheMisses,
        hitRate: this.cacheHits + this.cacheMisses > 0 
          ? Math.round((this.cacheHits / (this.cacheHits + this.cacheMisses)) * 100) 
          : 0
      } as CacheStats,
      renderStats: {
        averageRenderTime: this.renderCount > 0 
          ? Math.round(this.totalRenderTime / this.renderCount) 
          : 0,
        totalRenders: this.renderCount
      } as RenderStats,
      recentEvents: this.getEventHistory(50)
    };

    return JSON.stringify(report, null, 2);
  }

  // 私有方法
  private recordEvent(type: PerformanceEventType, data?: RenderEndData | ResourceLoadStartData | ResourceLoadEndData | ErrorData | MemoryWarningData): void {
    const event: PerformanceEvent = {
      type,
      timestamp: Date.now(),
      data
    };

    this.events.push(event);
    
    // 限制事件数量
    if (this.events.length > this.config.maxSamples) {
      this.events = this.events.slice(-this.config.maxSamples);
    }
  }

  private collectMetrics(): void {
    const now = Date.now();
    const elapsed = (now - this.lastSampleTime) / 1000;
    
    // 计算FPS
    this.metrics.fps = elapsed > 0 ? Math.round(this.frameCount / elapsed) : 0;
    this.frameCount = 0;
    
    // 计算平均渲染时间
    this.metrics.renderTime = this.renderCount > 0 
      ? Math.round(this.totalRenderTime / this.renderCount) 
      : 0;
    
    // 计算缓存命中率
    const totalCacheRequests = this.cacheHits + this.cacheMisses;
    this.metrics.cacheHitRate = totalCacheRequests > 0 
      ? Math.round((this.cacheHits / totalCacheRequests) * 100) 
      : 0;
    
    // 更新其他指标
    this.metrics.networkRequests = this.networkRequestCount;
    this.metrics.errors = this.errorCount;
    this.metrics.timestamp = now;
    
    // 尝试获取内存使用情况（在HarmonyOS中可能需要特定API）
    // this.metrics.memoryUsage = this.getMemoryUsage();
    
    this.lastSampleTime = now;
    
    // 记录指标采样
    console.debug('性能指标采样:', this.metrics);
  }

  private checkWarnings(): void {
    const warnings: string[] = [];
    
    if (this.metrics.fps > 0 && this.metrics.fps < this.config.warningThresholds.fps) {
      warnings.push(`低FPS警告: ${this.metrics.fps} FPS (阈值: ${this.config.warningThresholds.fps})`);
    }
    
    if (this.metrics.memoryUsage > this.config.warningThresholds.memory) {
      warnings.push(`高内存使用警告: ${this.metrics.memoryUsage} MB (阈值: ${this.config.warningThresholds.memory} MB)`);
    }
    
    if (this.metrics.renderTime > this.config.warningThresholds.renderTime) {
      warnings.push(`渲染时间过长警告: ${this.metrics.renderTime} ms/帧 (阈值: ${this.config.warningThresholds.renderTime} ms)`);
    }
    
    if (this.metrics.cacheHitRate < 50) {
      warnings.push(`缓存命中率低警告: ${this.metrics.cacheHitRate}%`);
    }
    
    if (warnings.length > 0) {
      console.warn('性能警告:', warnings.join('; '));
      this.recordEvent(PerformanceEventType.MEMORY_WARNING, { warnings } as MemoryWarningData);
    }
  }

  // 注意：HarmonyOS中获取内存使用可能需要特定API
  // 这里是一个示例实现，实际使用时需要根据HarmonyOS API调整
  private getMemoryUsage(): number {
    try {
      // 这里应该是调用HarmonyOS的内存统计API
      // 由于API限制，这里返回0作为占位符
      return 0;
    } catch (error) {
      console.warn('获取内存使用失败:', error);
      return 0;
    }
  }
}