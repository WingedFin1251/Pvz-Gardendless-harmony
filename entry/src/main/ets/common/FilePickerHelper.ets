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
      if (error.code === 13900001) {   // 权限被拒绝
        throw new Error('请授予文件访问权限');
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
}
