import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import { FileUtil, HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import * as fs from 'fs';
import * as path from 'path';

/**
 * 构建产物自动命名。
 *
 * 产物名规则：pvzge[-变体]-<versionName>[-signed].hap
 *   - 变体取 bundleName 后缀：`.lite` → `-lite`，`.gpnext` → `-gpnext`，其它（基础版）不带
 *   - 版本取 AppScope/app.json5 的 versionName 完整值（构建时读取，改版本号即改产物名）
 *   - **未签名包为主产物**：`pvzge-0.14.0.hap`
 *   - 若工程配置了签名（存在 signed 产物），额外输出 `pvzge-0.14.0-signed.hap`
 *   - 例：pvzge-0.14.0.hap、pvzge-lite-0.14.0.hap、pvzge-lite-0.14.0-signed.hap
 *
 * 输出位置：<工程根>/dist/（硬链接指向 build 里的 HAP，不额外占用磁盘；
 * 硬链接不可用时退化为复制）。每次构建会先清理 dist 下的旧 HAP。
 *
 * 说明：hvigor 不提供配置产物文件名的能力，这里通过自定义任务在 SignHap 之后、
 * assembleHap 结束之前完成命名。
 */
function hapNamePlugin(): HvigorPlugin {
  return {
    pluginId: 'hapName',
    apply(node: HvigorNode) {
      node.registerTask({
        name: 'hapName',
        dependencies: ['default@SignHap'],
        postDependencies: ['assembleHap'],
        run(taskContext) {
          const modulePath: string = taskContext?.modulePath ?? node.getNodePath();
          const moduleName: string = taskContext?.moduleName ?? node.getNodeName();
          const projectPath: string = node.getParentNode()?.getNodePath() ?? path.dirname(modulePath);

          // 版本与变体从应用级配置读取，避免手工维护
          let versionName = '0.0.0';
          let bundleName = '';
          const appJsonPath = path.join(projectPath, 'AppScope', 'app.json5');
          if (FileUtil.exist(appJsonPath)) {
            try {
              const appJson = FileUtil.readJson5(appJsonPath);
              versionName = appJson?.app?.versionName ?? versionName;
              bundleName = appJson?.app?.bundleName ?? bundleName;
            } catch (err) {
              console.warn(`[hapName] 读取 AppScope/app.json5 失败，使用默认版本号: ${err}`);
            }
          }
          let variant = '';
          if (bundleName.endsWith('.lite')) {
            variant = '-lite';
          } else if (bundleName.endsWith('.gpnext')) {
            variant = '-gpnext';
          }
          const baseName = `pvzge${variant}-${versionName}`;

          const outDir = path.join(modulePath, 'build', 'default', 'outputs', 'default');
          const unsignedHap = path.join(outDir, `${moduleName}-default-unsigned.hap`);
          const signedHap = path.join(outDir, `${moduleName}-default-signed.hap`);

          // 未签名包为主产物；签名包（若存在）另存为 -signed
          const outputs: Array<[string, string]> = [];
          const distDir = path.join(projectPath, 'dist');
          if (FileUtil.exist(unsignedHap)) {
            outputs.push([unsignedHap, path.join(distDir, `${baseName}.hap`)]);
          }
          if (FileUtil.exist(signedHap)) {
            outputs.push([signedHap, path.join(distDir, `${baseName}-signed.hap`)]);
          }
          if (outputs.length === 0) {
            console.warn(`[hapName] 未找到 HAP 产物，跳过命名（查找路径: ${outDir}）`);
            return;
          }

          FileUtil.ensureDirSync(distDir);
          for (const entry of fs.readdirSync(distDir)) {   // 清理历史产物
            if (entry.endsWith('.hap')) {
              try {
                fs.unlinkSync(path.join(distDir, entry));
              } catch (err) {
                console.warn(`[hapName] 清理旧产物失败 ${entry}: ${err}`);
              }
            }
          }

          for (const pair of outputs) {
            const source = pair[0];
            const target = pair[1];
            try {
              fs.linkSync(source, target);   // 硬链接：同一份数据，不复制
            } catch (err) {
              console.warn(`[hapName] 硬链接失败，改为复制: ${err}`);
              FileUtil.copyFileSync(source, target);
            }
            console.log(`[hapName] ${path.basename(source)} -> dist/${path.basename(target)}`);
          }
        }
      });
    }
  };
}

export default {
  system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: [hapNamePlugin()]       /* Custom plugin to extend the functionality of Hvigor. */
}
