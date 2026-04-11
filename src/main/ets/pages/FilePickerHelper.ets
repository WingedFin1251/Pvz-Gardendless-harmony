import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

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
    } catch (err) {
      console.error('FilePicker error:', err);

      // ✅ 友好提示用户权限问题
      if (err.code === 13900001) { // 权限被拒绝的错误码
        throw new Error('请授予文件访问权限');
      }
    }
    return null;
  }
}