import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class FilePickerHelper {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  /**
   * 打开系统文件选择器，让用户选择保存路径
   * @param defaultFileName 建议的文件名
   * @returns 用户选择的完整文件路径，取消时返回 null
   */
  async selectSavePath(defaultFileName: string): Promise<string | null> {
    const documentSaveOptions = new picker.DocumentSaveOptions();
    documentSaveOptions.newFileNames = [defaultFileName];

    // ✅ 移除强制Download模式，允许用户选择任意目录
    // documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;

    const documentPicker = new picker.DocumentViewPicker(this.context);
    try {
      const uris = await documentPicker.save(documentSaveOptions);
      if (uris && uris.length > 0) {
        return uris[0];
      }
      return null;   // 用户取消：唯一的"返回 null"来源
    } catch (err) {
      const error = err as BusinessError;
      console.error(`选择保存位置失败: code=${error.code}, message=${error.message}`);
      if (error.code === 13900001) {
        // 官方文案是 "Operation not permitted"（操作不允许）—— 不是专指"权限被拒绝"，
        // 所以提示不要断言用户没授权，只说明这次操作不被允许并给出可行动建议。
        throw new Error('无法访问所选位置（操作不允许），可换个目录再试');
      }
      // 其余错误原样抛出：调用方必须能区分"用户取消"和"选择失败"，否则会误报"已取消下载"
      throw new Error(`无法选择保存位置：${error.message}`);
    }
  }

  /**
   * 选择 GP-Next 数据包（.zip）或单文件补丁（.json/.json5），支持多选。
   * 桌面版是靠用户把文件丢进 gp-next/packs 目录，移动端只能由壳层代劳。
   * @returns 用户选中的文件 uri 列表，取消时返回空数组
   */
  async selectPackFiles(): Promise<string[]> {
    const documentSelectOptions = new picker.DocumentSelectOptions();
    documentSelectOptions.maxSelectNumber = 20;
    documentSelectOptions.fileSuffixFilters = ['数据包|.zip', '单文件补丁|.json,.json5'];

    const documentPicker = new picker.DocumentViewPicker(this.context);
    try {
      const uris = await documentPicker.select(documentSelectOptions);
      return uris ? uris : [];
    } catch (err) {
      const error = err as BusinessError;
      console.error(`选择数据包失败: code=${error.code}, message=${error.message}`);
      return [];
    }
  }

  /**
   * 选任意文件（payload 1.5.5 起新版模组导入用）：
   * 给了后缀就按后缀过滤；multiple 为真时最多 20 个。
   * @returns 用户选中的 uri 列表；取消时返回空数组
   */
  /**
   * 选一个文件夹（新版模组的「导入文件夹」用）。
   * @returns 用户选中的目录 uri；取消时返回 null
   */
  async selectFolder(): Promise<string | null> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.selectMode = picker.DocumentSelectMode.FOLDER;
    const documentPicker = new picker.DocumentViewPicker(this.context);
    try {
      // 实测：本机的"选文件夹"页面会崩（系统 filePicker 报 Observed/Navigation 未定义），
      // 此时 select() 可能**永不返回** ⇒ 必须带超时，否则调用方会一直等着。
      const uris = await this.withTimeout(documentPicker.select(options), 180000);
      if (uris && uris.length > 0) {
        return uris[0];
      }
      return null;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`选择文件夹失败或超时: code=${error.code}, message=${error.message}`);
      return null;
    }
  }

  /** 给可能永不返回的系统调用套一层超时；超时按"失败"处理（调用方会当成取消） */
  private withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
    return new Promise<T>((resolve: (value: T) => void, reject: (reason: Error) => void) => {
      let settled = false;
      const timer = setTimeout(() => {
        if (!settled) {
          settled = true;
          reject(new Error(`等待系统选择器超时（${timeoutMs} 毫秒；选择器仍开着的话请关掉重试）`));
        }
      }, timeoutMs);
      promise.then((value: T) => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          resolve(value);
        }
      }).catch((error: Object) => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          reject(error as Error);
        }
      });
    });
  }

  async selectFilesWithExtensions(extensions: string[], multiple: boolean): Promise<string[]> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = multiple ? 20 : 1;
    if (extensions.length > 0) {
      const suffixes = extensions.map((item: string) => `.${item}`).join(',');
      options.fileSuffixFilters = [`文件|${suffixes}`];
    }
    const documentPicker = new picker.DocumentViewPicker(this.context);
    try {
      // 同样带超时：系统选择器若异常退出，select() 可能永不返回
      const uris = await this.withTimeout(documentPicker.select(options), 180000);
      return uris ? uris : [];
    } catch (err) {
      const error = err as BusinessError;
      console.error(`选择文件失败或超时: code=${error.code}, message=${error.message}`);
      return [];
    }
  }
  /**
   * A6：选一个"数据备份文件"（.json）用于导入。
   * @returns 用户选中的 uri 列表（取消时为空数组）
   */
  async selectStorageFile(): Promise<string[]> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['数据备份|.json'];

    const documentPicker = new picker.DocumentViewPicker(this.context);
    try {
      const uris = await documentPicker.select(options);
      return uris ? uris : [];
    } catch (err) {
      const error = err as BusinessError;
      console.error(`选择备份文件失败: code=${error.code}, message=${error.message}`);
      throw new Error(`无法选择备份文件：${error.message}`);
    }
  }
}
