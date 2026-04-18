import{b as s,d as r,t,x as v}from"./index-Dou5Aj4b.js";let f="";function D(a){f=a}function F(a){const e=v()==="zh-CN";a.appendChild(s(t("guide.title"),[r(t("guide.intro"))]));const g=e?"https://pvzge.com/guide/mod/":"https://pvzge.com/en/guide/mod/",i=document.createElement("a");i.href=g,i.textContent=g,i.style.cssText="display:inline-block;margin-top:8px;color:#4a9eff;font-size:13px;text-decoration:none;font-weight:bold;",i.target="_blank",a.appendChild(s(t("guide.docs")||(e?"在线文档":"Online Documentation"),[r(t("guide.docsDesc")||(e?"查看更详细的模组制作教程与指南：":"View more detailed modding tutorials and guides:")),i]));const c=document.createElement("pre");c.className="gp-code",c.style.cssText="text-align:left;user-select:text;cursor:text;";const y=f||"AppData";c.textContent=e?`${y}/
└── gp-next/
    ├── packs/
    │   ├── MyPack/         ← 文件夹格式的数据包
    │   │   ├── pack.json   ← 必须存在的清单文件
    │   │   └── jsons/
    │   │       ├── features/  ← Features 类型（PlantFeatures, ZombieFeatures...）
    │   │       ├── objects/   ← Objects 类型（PlantProps, ZombieProps...）
    │   │       ├── lang/      ← 语言包（lang.json）
    │   │       └── levels/    ← 关卡 JSON
    │   └── MyPack.zip      ← ZIP 格式的数据包（内部结构相同）
    └── patches/             ← 单文件补丁（最高优先级）
        └── jsons/
            ├── features/
            ├── objects/
            ├── lang/
            └── levels/`:`${y}/
└── gp-next/
    ├── packs/
    │   ├── MyPack/         ← Folder-based datapack
    │   │   ├── pack.json   ← Required manifest
    │   │   └── jsons/
    │   │       ├── features/  ← Features (PlantFeatures, ZombieFeatures...)
    │   │       ├── objects/   ← Objects (PlantProps, ZombieProps...)
    │   │       ├── lang/      ← Language patch (lang.json)
    │   │       └── levels/    ← Level JSONs
    │   └── MyPack.zip      ← ZIP-based datapack (same internal structure)
    └── patches/             ← Single-file (highest priority)
        └── jsons/
            ├── features/
            ├── objects/
            ├── lang/
            └── levels/`,a.appendChild(s(t("guide.dirStructure"),[c]));const l=document.createElement("pre");l.className="gp-code",l.style.cssText="text-align:left;user-select:text;cursor:text;",l.textContent=`{
  "uuid": "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx",
  "name": "My Datapack",
  "version": "1.0.0",
  "priority": 100,
  "description": "${e?"补丁描述（可选）":"Optional description"}",
  "author": "${e?"作者名":"Author Name"}",
  "formatVersion": 1,
  "gameVersion": "0.7.X",
  "gpNextVersion": ">=1.0.0"
}`;const b=r(t("guide.packJsonNote"));b.style.whiteSpace="pre-wrap",a.appendChild(s(t("guide.packJson"),[l,b]));const p=document.createElement("div");p.style.cssText="display:flex;gap:6px;align-items:center;flex-wrap:wrap;";const n=document.createElement("input");n.type="text",n.readOnly=!0,n.placeholder=e?"点击生成按钮...":"Click Generate...",n.style.cssText=["flex:1;min-width:220px;padding:4px 8px;border-radius:4px;border:1px solid #444;","background:#1a1a2e;color:#e0e0e0;font-family:monospace;font-size:12px;","cursor:text;user-select:all;outline:none;"].join("");const d=document.createElement("button");d.textContent=e?"生成":"Generate",d.className="gp-btn gp-btn-sm",d.onclick=()=>{n.value=crypto.randomUUID(),o.textContent=e?"复制":"Copy"};const o=document.createElement("button");o.textContent=e?"复制":"Copy",o.className="gp-btn gp-btn-sm",o.onclick=()=>{n.value&&navigator.clipboard.writeText(n.value).then(()=>{o.textContent=e?"已复制!":"Copied!",setTimeout(()=>{o.textContent=e?"复制":"Copy"},1500)})},p.appendChild(n),p.appendChild(d),p.appendChild(o),a.appendChild(s(e?"UUID 生成器":"UUID Generator",[r(e?"为你的 datapack 生成一个唯一 UUID（填入 pack.json 的 uuid 字段）。":"Generate a unique UUID for your datapack's pack.json uuid field."),p]));const P=[["features/PlantFeatures.json",e?"植物 Features":"Plant Features"],["features/ZombieFeatures.json",e?"僵尸 Features":"Zombie Features"],["objects/PlantProps.json",e?"植物 Props (别名匹配)":"Plant Props (alias match)"],["objects/ZombieProps.json",e?"僵尸 Props (别名匹配)":"Zombie Props (alias match)"],["features/StoreCommodityFeatures.json",e?"商店数据 (Plants/Upgrade 按 CommodityName 合并；Gem/Coin/Zen 整体替换)":"Store data (Plants/Upgrade merged by CommodityName; Gem/Coin/Zen replaced)"],["lang/lang.json",e?"语言包 (深度合并到 MultiLanguage.lyrics)":"Language patch (deep-merged into MultiLanguage.lyrics)"],["levels/arena_day1.json",e?"关卡（按文件名匹配）":"Level (matched by filename)"]].map(([k,j])=>{const u=document.createElement("div");u.style.marginBottom="6px";const m=document.createElement("code");m.className="gp-text-mono",m.style.cssText="color: #7ec8e3; display: block; margin-bottom: 1px;",m.textContent=k;const x=document.createElement("div");return x.className="gp-text-muted",x.textContent=j,u.appendChild(m),u.appendChild(x),u});a.appendChild(s(t("guide.patchTypes"),P));const h=r(t("guide.priorityDesc"));h.style.whiteSpace="pre-wrap",a.appendChild(s(t("guide.priority"),[h]));const C=r(t("guide.manualEditsDesc"));C.style.whiteSpace="pre-wrap",a.appendChild(s(t("guide.manualEdits"),[C]))}export{D as bindGuide,F as render};
