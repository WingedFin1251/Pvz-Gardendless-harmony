// 防呆：检查两个仓库的"共享文件"是否逐字节一致
// 用法：node tool/check_shared_files.mjs [另一个仓库路径]
// 背景：lite 与 gpnext 共用同一套壳层源码，只有 6 个"身份/签名"文件允许不同。
//       2026-10-07 因为漏同步导致 lite 的 HAP 空跑（构建"成功"但产物是旧的）。
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..');

// 允许不同的身份/签名文件（见 docs/REPOS.md）
const ALLOW_DIFFER = new Set([
  'AppScope/app.json5',
  'AppScope/resources/base/element/string.json',
  'entry/src/main/resources/base/element/string.json',
  'README.md',
  'docs/BUILD.md',
  'build-profile.json5',
]);

const other = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.resolve(repo, '..', path.basename(repo) === 'Gardendless-gpnext' ? 'Gardendless-lite' : 'Gardendless-gpnext');

if (!fs.existsSync(other)) {
  console.error(`找不到对照仓库: ${other}\n用法: node tool/check_shared_files.mjs <另一个仓库的路径>`);
  process.exit(2);
}

// 需要逐字节一致的目录/文件
// ⚠️ 只列**共享源码**：绝不要把 entry/src/main/resources 整个装进来 ——
//    那下面是 gitignore 的游戏负载（几千个文件），两边本来就可能不同，会刷一堆假警报。
const TARGETS = [
  'entry/src/main/ets',                                   // 壳层源码
  'entry/src/main/resources/rawfile/touchPatch.js',       // 注入脚本（纳入 Git）
  'entry/src/main/resources/base/element/color.json',     // 颜色资源（分层参数）
  'entry/src/main/resources/dark/element/color.json',
  'tool',                                                 // 自检脚本
];
const EXT = ['.ets', '.ts', '.js', '.mjs', '.json'];

function walk(root, out = []) {
  if (!fs.existsSync(root)) return out;
  const st = fs.statSync(root);
  if (st.isFile()) { out.push(root); return out; }
  for (const name of fs.readdirSync(root)) {
    const p = path.join(root, name);
    const s = fs.statSync(p);
    if (s.isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

const files = new Set();
for (const t of TARGETS) {
  const abs = path.join(repo, t);
  if (!fs.existsSync(abs)) continue;
  for (const f of walk(abs)) {
    const rel = path.relative(repo, f).replace(/\\/g, '/');
    if (EXT.some((e) => rel.endsWith(e)) && !ALLOW_DIFFER.has(rel)) files.add(rel);
  }
}

const md5 = (p) => crypto.createHash('md5').update(fs.readFileSync(p)).digest('hex');
const missing = [];
const differing = [];
for (const rel of [...files].sort()) {
  const a = path.join(repo, rel);
  const b = path.join(other, rel);
  if (!fs.existsSync(b)) { missing.push(rel); continue; }
  if (md5(a) !== md5(b)) differing.push(rel);
}

console.log(`  本仓: ${repo}`);
console.log(`  对照: ${other}`);
console.log(`  比对 ${files.size} 个共享文件`);
if (missing.length) { console.log(`  ❌ 对照仓缺失 ${missing.length} 个:`); missing.forEach((r) => console.log('     ' + r)); }
if (differing.length) { console.log(`  ❌ 内容不一致 ${differing.length} 个:`); differing.forEach((r) => console.log('     ' + r)); }
if (!missing.length && !differing.length) { console.log('  ✅ 全部一致'); process.exit(0); }
process.exit(1);
