import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';

/**
 * 下载保存器：接住 Web 的下载事件，把文件落到用户选择的位置。
 *
 * 从页面里搬出来的东西（逐字未改）：
 *   · 四个回调：onBeforeDownload / onDownloadUpdated / onDownloadFailed / onDownloadFinish
 *   · 下载临时文件、`Is a directory` 重试、失败兜底到 filesDir 的整套落盘逻辑
 *   · `extractFileNameFromUrl`
 *   · 三个内部状态（是否在下载 / 临时路径 / 目标路径）—— 它们原本就是页面上的普通字段，
 *     不参与 UI，所以整体搬进服务，页面不再持有"第二份真相"。
 *
 * 留在页面（必须）：
 *   · `downloadStatus`（`@State`，UI 用）⇒ 服务通过 `setStatus` 回调更新
 *   · `showStatusMessage`（顶部提示）⇒ 通过 `notify` 回调
 *   · 保存位置选择（`FilePickerHelper`）与 `UIAbilityContext` ⇒ 通过回调注入
 */
export interface DownloadSaverCallbacks {
  /** 下载进度百分比（页面自己决定是否采纳 —— 原文有"仅当文案是下载中才更新"的守卫） */
  updateProgress: (percent: number) => void;
  /** 弹一条限时提示（页面的 showStatusMessage） */
  notify: (message: string, duration: number) => void;
  /** 让用户选保存位置；返回 null / 空串表示取消 */
  pickSavePath: (fileName: string) => Promise<string | null>;
  /** 取 UIAbilityContext（页面用 getUIContext().getHostContext()） */
  getContext: () => common.UIAbilityContext | undefined;
}

export class DownloadSaver {
  private readonly webDelegate: webview.WebDownloadDelegate = new webview.WebDownloadDelegate();
  private callbacks: DownloadSaverCallbacks | undefined = undefined;
  /** 是否已有下载任务在处理中 */
  private isDownloading: boolean = false;
  /** 下载中的临时文件路径（落在 cacheDir） */
  private tempDownloadPath: string = '';
  /** 用户选择的最终保存路径 */
  private finalSaveUri: string = '';

  /**
   * 注册四个回调并返回底层委托；页面把返回值交给 `webController.setDownloadDelegate`。
   */
  install(callbacks: DownloadSaverCallbacks): webview.WebDownloadDelegate {
    this.callbacks = callbacks;

    this.webDelegate.onBeforeDownload(async (webDownloadItem: webview.WebDownloadItem) => {
      if (this.isDownloading) {
        console.log('已有下载任务在处理中');
        return;
      }
      this.isDownloading = true;
      callbacks.notify('正在准备下载...', 5000);

      try {
        let fileName = webDownloadItem.getSuggestedFileName();
        if (!fileName || fileName.includes('�')) {
          const url = webDownloadItem.getUrl();
          fileName = this.extractFileNameFromUrl(url) || `download_${Date.now()}`;
          fileName = fileName.replace(/[\\/:*?"<>|]/g, '_');
        }

        const saveUri = await callbacks.pickSavePath(fileName);
        if (!saveUri) {
          callbacks.notify('已取消下载', 2000);
          webDownloadItem.cancel();
          this.isDownloading = false;
          return;
        }
        this.finalSaveUri = saveUri;

        const context = callbacks.getContext();
        if (!context) {
          console.error('下载失败：拿不到 UIAbilityContext');
          this.resetState();
          return;
        }
        const tempPath = `${context.cacheDir}/${fileName}`;
        this.tempDownloadPath = tempPath;

        callbacks.notify(`下载中: ${fileName}`, 10000);
        webDownloadItem.start(tempPath);
      } catch (err) {
        const error = err as BusinessError;
        console.error(`处理下载任务失败: ${error.message}`);
        // 带上原因：这样"权限被拒"就不会再显示成"已取消下载"
        callbacks.notify(`下载失败：${error.message}`, 4000);
        this.resetState();
      }
    });

    this.webDelegate.onDownloadUpdated((webDownloadItem: webview.WebDownloadItem) => {
      const percent = webDownloadItem.getPercentComplete();
      // 是否采纳由页面决定（原文的守卫：仅当当前文案是"下载中"才刷新百分比）
      callbacks.updateProgress(percent);
    });

    this.webDelegate.onDownloadFailed(() => {
      callbacks.notify('下载失败', 3000);
      this.removeTempFile();
      this.resetState();
    });

    this.webDelegate.onDownloadFinish(async () => {
      console.log('下载完成，开始复制到公共目录');
      if (!this.tempDownloadPath || !this.finalSaveUri) {
        callbacks.notify('下载失败，保存路径无效', 3000);
        this.resetState();
        return;
      }
      this.saveFinishedFile(callbacks);
    });

    return this.webDelegate;
  }

  /** 统一收尾：复位"是否在下载"与两个路径 —— 任何早退路径都必须走这里，否则下载功能会被永久卡死 */
  private resetState(): void {
    this.isDownloading = false;
    this.tempDownloadPath = '';
    this.finalSaveUri = '';
  }

  /** 下载完成后的落盘：复制到用户选的位置；目录异常时重试；再失败兜底到应用目录 */
  private saveFinishedFile(callbacks: DownloadSaverCallbacks): void {
    const getFileNameFromPath = (path: string): string => path.split('/').pop() || 'file';

    const createDirectoryIfNotExists = (uri: string): boolean => {
      try {
        try {
          if (fs.statSync(uri).isDirectory()) {
            return true;
          }
        } catch (e) {
        }
        fs.mkdirSync(uri, true);
        console.info(`目录创建成功: ${uri}`);
        return true;
      } catch (err) {
        console.error(`创建目录失败: ${uri}`, err);
        return false;
      }
    };

    const ensureParentDirectoryExists = (fileUri: string): boolean => {
      const lastSlash = fileUri.lastIndexOf('/');
      if (lastSlash <= 0) {
        return true;
      }
      const parentDir = fileUri.substring(0, lastSlash);
      return createDirectoryIfNotExists(parentDir);
    };

    const cleanPath = (path: string): string =>
      path.replace(/\/com\.example\.doubao\/com\.example\.doubao\//g, '/com.example.doubao/')
        .replace(/\/com\.example\.doubao\/\//g, '/com.example.doubao/');

    let destUri = cleanPath(this.finalSaveUri);
    let retry = false;
    let success = false;

    do {
      try {
        if (!ensureParentDirectoryExists(destUri)) {
          break;
        }
        const destFile = fs.openSync(destUri, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC | fs.OpenMode.CREATE);
        let srcFile: fs.File | undefined = undefined;
        try {
          srcFile = fs.openSync(this.tempDownloadPath, fs.OpenMode.READ_ONLY);
          fs.copyFileSync(srcFile.fd, destFile.fd);
        } finally {
          // 任一步抛错也必须关掉已打开的 fd（否则反复失败会耗尽 fd 配额）
          if (srcFile !== undefined) {
            try {
              fs.closeSync(srcFile);
            } catch (closeErr) {
            }
          }
          try {
            fs.closeSync(destFile);
          } catch (closeErr) {
          }
        }
        fs.unlinkSync(this.tempDownloadPath);
        const stat = fs.statSync(destUri);
        callbacks.notify(`下载完成，大小: ${(stat.size / 1024).toFixed(1)} KB`, 2000);
        success = true;
        break;
      } catch (err) {
        if (!retry && err.message.includes('Is a directory')) {
          const retryFileName = getFileNameFromPath(this.tempDownloadPath);
          destUri = `${this.finalSaveUri}/${retryFileName}`;
          destUri = cleanPath(destUri);
          retry = true;
          continue;
        }
        console.error('复制文件失败:', err);
        // 备选：保存到应用私有目录
        const context = callbacks.getContext();
        if (!context) {
          callbacks.notify('保存失败，上下文无效', 3000);
          break;
        }
        const backupPath = `${context.filesDir}/${getFileNameFromPath(this.tempDownloadPath)}`;
        try {
          fs.copyFileSync(this.tempDownloadPath, backupPath);
          fs.unlinkSync(this.tempDownloadPath);
          callbacks.notify(`已保存到应用目录: ${backupPath}`, 3000);
          success = true;
        } catch (backupErr) {
          callbacks.notify('保存失败，请重试', 3000);
        }
        break;
      }
    } while (true);

    if (!success) {
      this.removeTempFile();
    }
    this.resetState();
  }

  private removeTempFile(): void {
    if (this.tempDownloadPath) {
      try {
        fs.unlinkSync(this.tempDownloadPath);
      } catch (e) {
      }
    }
  }

  /** 从 URL 里猜文件名（后缀必须有点像扩展名）；猜不出返回 null */
  private extractFileNameFromUrl(url: string): string | null {
    try {
      const segments = url.split('/');
      const fileName = segments[segments.length - 1].split('?')[0];
      if (fileName && fileName.includes('.')) {
        return decodeURIComponent(fileName);
      }
      return null;
    } catch (err) {
      return null;
    }
  }
}
