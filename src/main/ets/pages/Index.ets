import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { FilePickerHelper } from './FilePickerHelper';  // 复用 FilePickerHelper

@Entry
@Component
struct CocosJSApp {
  private webController: webview.WebviewController = new webview.WebviewController();
  private downloadDelegate: webview.WebDownloadDelegate = new webview.WebDownloadDelegate();
  private filePickerHelper?: FilePickerHelper;
  private tempDownloadPath: string = '';
  private finalSaveUri: string = '';
  private isDownloading: boolean = false;
  private timeoutId?: number;

  @State downloadStatus: string = '';
  @State statusOpacity: number = 1;
  @State isLoading: boolean = true;
  @State progress: number = 0;
  @State webReady: boolean = false;

  aboutToAppear() {
    const context = getContext(this) as common.UIAbilityContext;
    this.filePickerHelper = new FilePickerHelper(context);
    // 可选：请求文件读写权限（如果需要）
    // this.requestStoragePermission();
  }

  aboutToDisappear() {
    if (this.timeoutId) clearTimeout(this.timeoutId);
  }

  private showStatusMessage(message: string, duration: number = 3000) {
    if (this.timeoutId) clearTimeout(this.timeoutId);
    this.statusOpacity = 1;
    this.downloadStatus = message;
    this.timeoutId = setTimeout(() => {
      animateTo({ duration: 300 }, () => { this.statusOpacity = 0; });
      setTimeout(() => {
        this.downloadStatus = '';
        this.statusOpacity = 1;
      }, 300);
      this.timeoutId = undefined;
    }, duration);
  }

  build() {
    Column() {
      if (this.downloadStatus) {
        Text(this.downloadStatus)
          .fontSize(14)
          .padding(8)
          .backgroundColor('#f0f0f0')
          .width('100%')
          .textAlign(TextAlign.Center)
          .opacity(this.statusOpacity)
          .animation({ duration: 300, curve: Curve.Linear })
      }

      if (this.isLoading && this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%').height(4).color('#0A59F7')
      }

      Web({ src: "https://cocos.local/index.html", controller: this.webController })
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .enableWebAVSession(false)
        .onPageBegin(() => {
          this.isLoading = true;
          this.webReady = false;
        })
        .onProgressChange((event) => { this.progress = event.newProgress; })
        .onPageEnd(() => {
          this.isLoading = false;
          this.webReady = true;
          // 注册下载委托
          this.setupDownloadDelegate();
          try {
            this.webController.setDownloadDelegate(this.downloadDelegate);
            console.log('下载委托已注册');
          } catch (err) {
            console.error('注册下载委托失败:', err);
          }
          // Cookie 持久化（可选）
          try {
            webview.WebCookieManager.saveCookieAsync(() => console.log('Cookie 已保存'));
          } catch (err) { console.error('保存 Cookie 失败', err); }
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

  private setupDownloadDelegate() {
    this.downloadDelegate.onBeforeDownload(async (webDownloadItem: webview.WebDownloadItem) => {
      if (this.isDownloading) {
        console.log('已有下载任务在处理中');
        return;
      }
      this.isDownloading = true;
      this.showStatusMessage('正在准备下载...', 5000);

      try {
        let fileName = webDownloadItem.getSuggestedFileName();
        if (!fileName || fileName.includes(' ')) {
          const url = webDownloadItem.getUrl();
          fileName = this.extractFileNameFromUrl(url) || `download_${Date.now()}`;
          fileName = fileName.replace(/[\\/:*?"<>|]/g, '_');
        }

        const saveUri = await this.filePickerHelper?.selectSavePath(fileName);
        if (!saveUri) {
          this.showStatusMessage('已取消下载', 2000);
          webDownloadItem.cancel();
          this.isDownloading = false;
          return;
        }
        this.finalSaveUri = saveUri;

        const context = getContext(this) as common.UIAbilityContext;
        const tempPath = `${context.cacheDir}/${fileName}`;
        this.tempDownloadPath = tempPath;

        this.showStatusMessage(`下载中: ${fileName}`, 10000);
        webDownloadItem.start(tempPath);
      } catch (err) {
        console.error('处理下载任务失败:', err);
        this.showStatusMessage('下载失败', 3000);
        this.isDownloading = false;
      }
    });

    this.downloadDelegate.onDownloadUpdated((webDownloadItem: webview.WebDownloadItem) => {
      const percent = webDownloadItem.getPercentComplete();
      if (this.downloadStatus.startsWith('下载中')) {
        this.downloadStatus = `下载中: ${percent}%`;
      }
    });

    this.downloadDelegate.onDownloadFailed(() => {
      this.showStatusMessage('下载失败', 3000);
      this.isDownloading = false;
      if (this.tempDownloadPath) {
        try { fs.unlinkSync(this.tempDownloadPath); } catch (e) {}
      }
    });

    this.downloadDelegate.onDownloadFinish(async () => {
      console.log('下载完成，开始复制到公共目录');
      if (!this.tempDownloadPath || !this.finalSaveUri) {
        this.showStatusMessage('下载失败，保存路径无效', 3000);
        this.isDownloading = false;
        return;
      }

      const getFileNameFromPath = (path: string): string => path.split('/').pop() || 'file';

      const createDirectoryIfNotExists = (uri: string): boolean => {
        try {
          try { if (fs.statSync(uri).isDirectory()) return true; } catch (e) {}
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
        if (lastSlash <= 0) return true;
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
          if (!ensureParentDirectoryExists(destUri)) break;
          const destFile = fs.openSync(destUri, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC | fs.OpenMode.CREATE);
          const srcFile = fs.openSync(this.tempDownloadPath, fs.OpenMode.READ_ONLY);
          fs.copyFileSync(srcFile.fd, destFile.fd);
          fs.closeSync(srcFile);
          fs.closeSync(destFile);
          fs.unlinkSync(this.tempDownloadPath);
          const stat = fs.statSync(destUri);
          this.showStatusMessage(`下载完成，大小: ${(stat.size / 1024).toFixed(1)} KB`, 2000);
          success = true;
          break;
        } catch (err) {
          if (!retry && err.message.includes('Is a directory')) {
            const fileName = getFileNameFromPath(this.tempDownloadPath);
            destUri = `${this.finalSaveUri}/${fileName}`;
            destUri = cleanPath(destUri);
            retry = true;
            continue;
          }
          console.error('复制文件失败:', err);
          // 备选：保存到应用私有目录
          const context = getContext(this) as common.UIAbilityContext;
          const backupPath = `${context.filesDir}/${getFileNameFromPath(this.tempDownloadPath)}`;
          try {
            fs.copyFileSync(this.tempDownloadPath, backupPath);
            fs.unlinkSync(this.tempDownloadPath);
            this.showStatusMessage(`已保存到应用目录: ${backupPath}`, 3000);
            success = true;
          } catch (backupErr) {
            this.showStatusMessage('保存失败，请重试', 3000);
          }
          break;
        }
      } while (true);

      if (!success && this.tempDownloadPath) {
        try { fs.unlinkSync(this.tempDownloadPath); } catch (e) {}
      }
      this.isDownloading = false;
      this.tempDownloadPath = '';
      this.finalSaveUri = '';
    });
  }

  private extractFileNameFromUrl(url: string): string | null {
    try {
      const segments = url.split('/');
      const fileName = segments[segments.length - 1].split('?')[0];
      if (fileName && fileName.includes('.')) return decodeURIComponent(fileName);
      return null;
    } catch { return null; }
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
