(function(){'use strict';console.log('[Tauri Polyfill] Initializing...');const storage={files:new Map(),directories:new Set(['gp-next','gp-next/packs','gp-next/patches','gp-next/__gpn_edits']),init(){try{const saved=localStorage.getItem('__tauri_fs_mock');if(saved){const data=JSON.parse(saved);this.files=new Map(Object.entries(data))}}catch(e){console.warn('[Polyfill] Failed to restore files:',e)}this.ensureDefaultFiles()},ensureDefaultFiles(){const defaultSettings={version:1,packOrder:[],disabledPacks:[],scrollSensitivity:{enabled:true,wheel:1,discreteMinIntervalMs:0}};if(!this.files.has('gp-next/settings.json')){this.files.set('gp-next/settings.json',JSON.stringify(defaultSettings,null,2))}},save(){try{const data=Object.fromEntries(this.files);localStorage.setItem('__tauri_fs_mock',JSON.stringify(data))}catch(e){console.warn('[Polyfill] Failed to save files:',e)}},readFile(path){const normalized=this.normalizePath(path);const content=this.files.get(normalized);if(content===undefined){throw new Error(`File not found:${path}`)}return content},writeFile(path,content){const normalized=this.normalizePath(path);this.files.set(normalized,content);this.save()},deleteFile(path){const normalized=this.normalizePath(path);this.files.delete(normalized);this.save()},readDir(path){const normalized=this.normalizePath(path);const files=[];const prefix=normalized+(normalized.endsWith('/')?'':'/');for(const filePath of this.files.keys()){if(filePath.startsWith(prefix)){const relative=filePath.substring(prefix.length);const firstPart=relative.split('/')[0];if(!files.includes(firstPart)){files.push({name:firstPart,isFile:!relative.includes('/')&&!firstPart.includes('.')})}}}for(const dir of this.directories){if(dir.startsWith(prefix)){const name=dir.substring(prefix.length).split('/')[0];if(name&&!files.some(f=>f.name===name)){files.push({name,isFile:false})}}}return files},exists(path){const normalized=this.normalizePath(path);return this.files.has(normalized)||this.directories.has(normalized)},createDir(path,recursive=true){const normalized=this.normalizePath(path);this.directories.add(normalized);this.save()},normalizePath(path){let normalized=path.replace(/^gp-next[\\/]?/i,'');normalized=normalized.replace(/\\/g,'/');return normalized}};let callbackId=0;const callbacks=new Map();function transformCallback(callback,once=false){const id=++callbackId;callbacks.set(id,{callback,once});return id}function handleCallback(id,payload){const entry=callbacks.get(id);if(entry){entry.callback(payload);if(entry.once){callbacks.delete(id)}}}async function invokeTauriAPI(cmd,args){console.debug(`[Tauri API]${cmd}`,args);await new Promise(resolve=>setTimeout(resolve,10));try{switch(cmd){case'plugin:fs|read_text_file':return storage.readFile(args.path);case'plugin:fs|read_file':const content=storage.readFile(args.path);return new TextEncoder().encode(content).buffer;case'plugin:fs|write_text_file':storage.writeFile(args.headers.path,args.payload);return null;case'plugin:fs|read_dir':return storage.readDir(args.path);case'plugin:fs|exists':return storage.exists(args.path);case'plugin:fs|mkdir':storage.createDir(args.path,args.options?.recursive);return null;case'plugin:fs|remove':storage.deleteFile(args.path);return null;case'plugin:dialog|save':const defaultPath=args.options?.defaultPath||'download.json';const fileName=prompt('保存文件为:',defaultPath);if(fileName){return fileName}return null;case'plugin:window|get_all_windows':return[{label:'main'}];case'plugin:window|inner_size':return{width:window.innerWidth,height:window.innerHeight};case'plugin:window|outer_size':return{width:window.outerWidth,height:window.outerHeight};case'plugin:window|inner_position':return{x:window.screenX,y:window.screenY};case'plugin:window|outer_position':return{x:window.screenX,y:window.screenY};case'plugin:window|is_fullscreen':return!!document.fullscreenElement;case'plugin:window|is_maximized':return false;case'plugin:window|is_minimized':return false;case'plugin:window|is_focused':return document.hasFocus();case'plugin:window|scale_factor':return window.devicePixelRatio||1;case'plugin:window|set_fullscreen':if(args.value){}else{}return null;case'plugin:window|set_size':console.warn('[Polyfill] Cannot set window size in browser');return null;case'plugin:window|set_position':console.warn('[Polyfill] Cannot set window position in browser');return null;case'plugin:window|center':console.warn('[Polyfill] Cannot center window in browser');return null;case'plugin:window|close':window.close();return null;case'plugin:window|hide':console.warn('[Polyfill] Cannot hide window in browser');return null;case'plugin:window|show':console.warn('[Polyfill] Cannot show window in browser');return null;case'plugin:path|resolve_directory':if(args.directory===14){return'/gp-next'}return'/';case'plugin:path|basename':return args.path.split(/[/\\]/).pop();case'plugin:path|dirname':const parts=args.path.split(/[/\\]/);parts.pop();return parts.join('/');case'plugin:opener|open_url':window.open(args.url,'_blank');return null;case'plugin:opener|open_path':console.warn('[Polyfill] Cannot open system path:',args.path);return null;case'plugin:drpc|spawn_thread':console.log('[Polyfill] Discord RPC would spawn with ID:',args.id);return null;case'plugin:drpc|destroy_thread':console.log('[Polyfill] Discord RPC would destroy');return null;case'plugin:drpc|is_running':return false;case'plugin:drpc|set_activity':console.log('[Polyfill] Discord RPC would set activity:',args.activityJson);return null;case'plugin:image|from_bytes':case'plugin:image|from_path':return{rid:Date.now()};case'plugin:image|rgba':return new Uint8Array([0,0,0,0]);case'plugin:image|size':return{width:64,height:64};case'plugin:event|listen':const eventId=transformCallback(args.handler);return eventId;case'plugin:event|unlisten':callbacks.delete(args.eventId);return null;case'plugin:event|emit':console.log('[Polyfill] Event emitted:',args.event,args.payload);return null;default:console.warn(`[Polyfill]Unknown Tauri command:${cmd}`,args);return null}}catch(error){console.error(`[Polyfill]Error in ${cmd}:`,error);throw error;}}if(!window.__TAURI_INTERNALS__){window.__TAURI_INTERNALS__={metadata:{currentWindow:{label:'main'}},transformCallback:transformCallback,invoke:async function(cmd,args={}){try{return await invokeTauriAPI(cmd,args)}catch(error){console.warn(`[Polyfill]API call failed,returning default:${cmd}`,error);return getDefaultResponse(cmd)}}}}function getDefaultResponse(cmd){if(cmd.includes('read_text_file')||cmd.includes('read_file')){return'{}'}if(cmd.includes('read_dir')){return[]}if(cmd.includes('exists')){return false}if(cmd.includes('is_')){return false}return null}window.__TAURI_IPC_KEY__='__TAURI_IPC_KEY__';if(!window.__TAURI__){window.__TAURI__={window:{getCurrent:()=>({label:'main',listen:(event,handler)=>{console.log(`[Polyfill]Listening to event:${event}`);return()=>{}}})},fs:{readTextFile:(path)=>storage.readFile(path),writeTextFile:(path,content)=>storage.writeFile(path,content)}}}if(!window.electron){window.electron={shell:{openExternal:async(url)=>{window.open(url,'_blank');return true}},ipcRenderer:{send:(channel,...args)=>{console.log(`[Electron Mock]send:${channel}`,args)},sendSync:(channel,...args)=>{console.log(`[Electron Mock]sendSync:${channel}`,args);return null},on:(channel,handler)=>{console.log(`[Electron Mock]on:${channel}`)}}}}storage.init();window.__tauriPolyfillDebug={storage:storage,listFiles:()=>Array.from(storage.files.keys()),clearStorage:()=>{storage.files.clear();storage.save();console.log('[Polyfill] Storage cleared')},exportData:()=>{const data=Object.fromEntries(storage.files);console.log('[Polyfill] Exporting data:',data);return data}};console.log('[Tauri Polyfill] Initialized successfully');console.log('[Tauri Polyfill] Use window.__tauriPolyfillDebug for debugging')})();
const __vite__mapDeps=(i,m=__vite__mapDeps,d=(m.f||(m.f=["assets/scroll-sensitivity-YCzaXGXZ.js","assets/engine-ktIF7zII.js","assets/patcher-Cco04iXG.js","assets/restore-utils-0PbDRBZb.js","assets/data-store-DHLaXs3u.js","assets/tab-cheats-D_NOfoCI.js","assets/tab-settings-DaTsFm09.js"])))=>i.map(i=>d[i]);
(function(){const t=document.createElement("link").relList;if(t&&t.supports&&t.supports("modulepreload"))return;for(const r of document.querySelectorAll('link[rel="modulepreload"]'))a(r);new MutationObserver(r=>{for(const u of r)if(u.type==="childList")for(const i of u.addedNodes)i.tagName==="LINK"&&i.rel==="modulepreload"&&a(i)}).observe(document,{childList:!0,subtree:!0});function n(r){const u={};return r.integrity&&(u.integrity=r.integrity),r.referrerPolicy&&(u.referrerPolicy=r.referrerPolicy),r.crossOrigin==="use-credentials"?u.credentials="include":r.crossOrigin==="anonymous"?u.credentials="omit":u.credentials="same-origin",u}function a(r){if(r.ep)return;r.ep=!0;const u=n(r);fetch(r.href,u)}})();function sa(){const e=document.getElementById("GameCanvas");if(!e){console.error("[Cocos Bootstrap] GameCanvas not found");return}const t=e.parentElement;if(!t){console.error("[Cocos Bootstrap] canvas parent not found");return}const n=t.getBoundingClientRect();e.width=n.width,e.height=n.height,window.System.import("cc").then(a=>{const r={settingsPath:"src/settings.json",showFPS:!1};return a.game.onPostBaseInitDelegate.add(()=>{}),a.game.onPostSubsystemInitDelegate.add(()=>{}),a.game.init({debugMode:a.DebugMode.ERROR,settingsPath:r.settingsPath,overrideSettings:{profiling:{showFPS:r.showFPS}}}).then(()=>a.game.run())}).catch(a=>{console.error("[Cocos Bootstrap] failed to start game",a)})}sa();const la="modulepreload",ca=function(e){return"/"+e},sn={},G=function(t,n,a){let r=Promise.resolve();if(n&&n.length>0){let i=function(c){return Promise.all(c.map(D=>Promise.resolve(D).then(s=>({status:"fulfilled",value:s}),s=>({status:"rejected",reason:s}))))};document.getElementsByTagName("link");const o=document.querySelector("meta[property=csp-nonce]"),l=o?.nonce||o?.getAttribute("nonce");r=i(n.map(c=>{if(c=ca(c),c in sn)return;sn[c]=!0;const D=c.endsWith(".css"),s=D?'[rel="stylesheet"]':"";if(document.querySelector(`link[href="${c}"]${s}`))return;const f=document.createElement("link");if(f.rel=D?"stylesheet":la,D||(f.as="script"),f.crossOrigin="",f.href=c,l&&f.setAttribute("nonce",l),document.head.appendChild(f),D)return new Promise((A,x)=>{f.addEventListener("load",A),f.addEventListener("error",()=>x(new Error(`Unable to preload CSS for ${c}`)))})}))}function u(i){const o=new Event("vite:preloadError",{cancelable:!0});if(o.payload=i,window.dispatchEvent(o),!o.defaultPrevented)throw i}return r.then(i=>{for(const o of i||[])o.status==="rejected"&&u(o.reason);return t().catch(u)})},Ye=[],da=200;let kt=null;function bu(){return Ye}function wu(e){kt=e}function Je(e,t,n,a){const r=a.length?n+" "+a.map(i=>{try{return typeof i=="object"?JSON.stringify(i):String(i)}catch{return String(i)}}).join(" "):n,u={level:e,module:t,msg:r,time:Date.now()};Ye.push(u),Ye.length>da&&Ye.shift(),kt&&kt(u)}class $t{constructor(t){this.module=t,this._prefix=`[GP Next:${t}]`}info(t,...n){console.log(this._prefix,t,...n),Je("info",this.module,t,n)}warn(t,...n){console.warn(this._prefix,t,...n),Je("warn",this.module,t,n)}error(t,...n){console.error(this._prefix,t,...n),Je("error",this.module,t,n)}debug(t,...n){window.gpNext?.debug&&console.log(`${this._prefix} [DEBUG]`,t,...n),Je("debug",this.module,t,n)}}const yn="gp-next-settings",pa={version:1,locale:null,frameRate:"60",debug:!1,dynamicPlantRegistry:!0,scrollSensitivity:{enabled:!0,wheel:1,discreteMinIntervalMs:0},hpOverlay:{showPlant:!1,showZombie:!1,showTomb:!1}};let oe=null;function Pt(e){return JSON.parse(JSON.stringify(e))}function Da(e){const t=Number(e);return!Number.isFinite(t)||t<=0?1:Math.max(.05,Math.min(3,t))}function ga(e){const t=Number(e);return!Number.isFinite(t)||t<0?0:Math.round(Math.max(0,Math.min(400,t)))}function En(e){const t=e&&typeof e=="object"?e:{};return{version:1,locale:typeof t.locale=="string"?t.locale:null,frameRate:typeof t.frameRate=="string"?t.frameRate:String(Number(t.frameRate)||60),debug:t.debug===!0,dynamicPlantRegistry:t.dynamicPlantRegistry!==!1,scrollSensitivity:{enabled:t.scrollSensitivity?.enabled!==!1,wheel:Da(t.scrollSensitivity?.wheel),discreteMinIntervalMs:ga(t.scrollSensitivity?.discreteMinIntervalMs)},hpOverlay:{showPlant:t.hpOverlay?.showPlant===!0,showZombie:t.hpOverlay?.showZombie===!0,showTomb:typeof t.hpOverlay?.showTomb=="boolean"?t.hpOverlay.showTomb===!0:t.hpOverlay?.showZombie===!0}}}function fa(){const e={},t=localStorage.getItem("gp-next-locale");return t&&(e.locale=t),e}function An(){localStorage.setItem(yn,JSON.stringify(oe))}function jt(){if(oe)return Pt(oe);let e=null;try{e=JSON.parse(localStorage.getItem(yn)||"null")}catch{e=null}oe=En({...pa,...e||{}});const t=fa();return oe.locale==null&&t.locale&&(oe.locale=t.locale),An(),Pt(oe)}function ha(e){const t=jt(),n={...t,...e||{},scrollSensitivity:{...t.scrollSensitivity,...e?.scrollSensitivity||{}},hpOverlay:{...t.hpOverlay,...e?.hpOverlay||{}}};return oe=En(n),An(),Pt(oe)}const rt={en:{"header.status.waiting":"Waiting for engine...","header.status.ready":"Ready","header.status.engineReady":"Engine ready","header.status.patchesLoaded":"{0} pack(s), {1} type(s) applied","header.status.patchesLoadedWithEdits":"{0} pack(s), {1} type(s) applied, {2} manual edit(s)","header.status.timeout":"Engine not detected","header.f10Hint":"F10","footer.version":"GP-Next v{0}","footer.updateIdle":"Check updates","footer.updateChecking":"Checking...","footer.upToDate":"Up to date","footer.updateAvailable":"Update available: v{0}","footer.updateCheckFailed":"Update check failed","footer.checkNow":"Check for updates now","footer.openDownload":"Open download page","tab.patcher":"Patcher","tab.data":"Data","tab.cheats":"Trainer","tab.settings":"Settings","tab.cloud":"Cloud","tab.about":"About","tab.log":"Log","tab.guide":"Guide","patcher.title":"Patch Status","patcher.engineState":"Engine","patcher.assetCount":"Asset Count","patcher.patchList":"Loaded Patches","patcher.actions":"Actions","patcher.reloadAll":"Reload All Patches","patcher.restoreAll":"Restore All Originals","patcher.patchLog":"Patch Log","patcher.basePath":"Patch Files Directory","patcher.openDir":"Open Folder","patcher.loaded":"Loaded","patcher.skipped":"Skipped","patcher.error":"Error","patcher.noPatchesFound":"No patches found","patcher.reloading":"Reloading...","patcher.restoring":"Restoring...","patcher.restored":"Restored {0} types","patcher.active":"Active","patcher.inactive":"Inactive","patcher.packs":"Datapacks","patcher.noPacks":"No datapacks found in gp-next/packs/","patcher.singleFile":"Single-file patches","patcher.singleFileSection":"patches/","patcher.packPriority":"P:{0}","patcher.packItems":"{0} item(s)","patcher.packErrors":"{0} error(s)","patcher.errors":"Load Errors","patcher.moveUp":"Move Up","patcher.moveDown":"Move Down","patcher.saveOrder":"Save Order","patcher.orderSaved":"Order saved","patcher.packAuthor":"Author: {0}","patcher.packMeta":"Game: {0} · GP-Next: {1}","patcher.packMetaGameOnly":"Game: {0}","patcher.packMetaGpnOnly":"GP-Next: {0}","patcher.noUuid":"⚠ No uuid — order not saved","patcher.disabledPacks":"Disabled Packs","patcher.enablePack":"Enable","patcher.disablePack":"Disable","patcher.loadOrderHint":"Top → bottom: later packs override earlier ones on conflict.","patcher.saveAndReload":"Save & Reload","patcher.saveAndReloading":"Saving & Reloading...","patcher.gpnEdits":"Manual Edits","patcher.gpnEditsSection":"Manual Edits (GP-Next)","data.drawer.treeView":"Tree","data.drawer.rawJson":"JSON","data.drawer.comparison":"Comparison","data.drawer.edit":"Edit","data.drawer.save":"Save","data.drawer.restoreItem":"Restore This Entry","data.drawer.restoreType":"Restore Type","data.drawer.restoreNote":"Only removes GP-Next manual edits. For permanent changes, use a datapack.","data.drawer.restoreConfirm":"Remove manual edits for this entry? (Packs/Patches unchanged)","data.drawer.restoreTypeConfirm":"Remove ALL manual edits for this type? (Packs/Patches unchanged)","data.drawer.restoreAll":"Clear All","data.drawer.restoreAllConfirm":"Clear EVERY manual edit across all types? (Packs/Patches unchanged)","data.drawer.saveSuccess":"Edit saved. Reload patches to apply fully.","data.drawer.saveFail":"Failed to save to __gpn_edits.","data.drawer.restoreCount":"Restored {0} manual edits","data.drawer.editHint":"Tip: edits here are for quick tweaks or temporary debugging only — for permanent changes, use a proper datapack. Set a value to null to delete the field during merge.","data.drawer.noOriginal":"No backup found (may be newly added by a datapack).","data.drawer.noChanges":"Matches original exactly — no edits.","data.drawer.loadMore":"Load more (▾ {0} remaining)","header.status.compact":"P:{0} / I:{1}","header.status.compactWithEdits":"P:{0} / I:{1} / ✏{2}","common.confirm":"Confirm","common.cancel":"Cancel","guide.title":"Getting Started","guide.docs":"Online Documentation","guide.docsDesc":"View more detailed modding tutorials and API documentation:","guide.intro":"GP-Next allows loading modular JSON datapacks. Place your datapacks in the GP-Next packs directory. They will be loaded automatically.","guide.dirStructure":"Directory Structure","guide.packJson":"pack.json Info","guide.packJsonNote":`uuid: unique identifier used to persist load order.
priority: lower = applied first; default 100.
thumbnail.png at pack root is loaded as the cover image.
ZIP packs (.zip in packs/) are also supported with the same internal structure.

Metadata fields:
formatVersion: pack format version (currently 1).
gameVersion: target game version string (e.g. "0.7.X").
gpNextVersion: required GP-Next version range (e.g. ">=1.0.0").

Lang patch (jsons/lang/lang.json):
Deep-merged into MultiLanguage.lyrics. Supports partial updates — only provide fields you wish to override.

Optional "_languages" field declares extra language options shown in the game's Language switcher:
{ "_languages": [{ "code": "es", "name": "Español", "isCJK": false }] }
Each extra language adds a field (e.g. "es") to every {en, zh} text node. All existing lyrics sections and DirectQuote / LoadingTips entries support it.`,"guide.patchTypes":"Supported Patch Files","guide.priority":"Priority & Merge Order","guide.priorityDesc":`Packs and patches are applied in the following order (lowest to highest priority):

1. packs/: Datapacks, sorted by priority ascending.
2. patches/: Single-file compatibility layer.
3. Manual Edits: Values edited in the Data tab (always wins).

Each layer deep-merges on top of the previous. For levels, the last provider wins.`,"guide.manualEdits":"Manual Edits (Data Tab)","guide.manualEditsDesc":`You can browse and directly edit game data in the Data tab. These edits are saved separately and always override all packs and patches.

Recommended for quick tweaks or temporary debugging only. For stable, shareable, or complex changes, create a proper datapack instead.`,"data.title":"Data Browser","data.selectType":"Select Type","data.searchPlaceholder":"Search by CODENAME or alias...","data.exportCurrent":"Export Current","data.exportOriginal":"Export Original","data.noData":"No data available","data.entries":"{0} entries","cheats.title":"Trainer","cheats.requireInGame":"Only available in-game","cheats.sun":"Sun","cheats.setSun":"Set Sun","cheats.addSun":"+1000","cheats.addSun200":"+200","cheats.addSun500":"+500","cheats.addSun5000":"+5000","cheats.resetSpeed":"1×","cheats.gameSpeed":"Game Speed","cheats.gameSpeedDesc":"Speed ​​switching within the level","cheats.freePlant":"Free Planting","cheats.freePlantDesc":"Plant without spending sun","cheats.invincible":"Plant Invincible","cheats.invincibleDesc":"Plants cannot take damage","cheats.showPlantHp":"Show Plant HP","cheats.showPlantHpDesc":"Show real-time HP above plants","cheats.showZombieHp":"Show Zombie HP","cheats.showZombieHpDesc":"Show real-time HP above zombies","cheats.instantWin":"Instant Win","cheats.instantWinDesc":"Immediately trigger level victory","cheats.instantWinSandboxDisabled":"Instant Win is disabled in sandbox mode","cheats.restoreMowersSandboxDisabled":"Restore Lawnmowers is disabled in sandbox mode","cheats.noCooldown":"No Cooldown","cheats.noCooldownDesc":"Cards recharge instantly after planting","cheats.unsupportedScene":"No cheats available for the current scene.","cheats.normalLevel":"Normal Level","cheats.worldMap":"World Map","cheats.coins":"Coins","cheats.setCoins":"Set Coins","cheats.clearCoins":"Clear","cheats.gems":"Gems","cheats.setGems":"Set Gems","cheats.clearGems":"Clear","cheats.setSeeds":"Set Seeds","cheats.clearSeeds":"Clear","cheats.add50":"+50","cheats.add100":"+100","cheats.add1000":"+1000","cheats.add10000":"+10000","cheats.plantFood":"Plant Food","cheats.fillPlantFood":"Fill","cheats.clearPlantFood":"Clear","cheats.freePF":"Free Plant Food","cheats.freePFDesc":"Plant food is never consumed","cheats.resources":"Resources","cheats.plant":"Plant","cheats.zombie":"Zombie","cheats.killAllZombies":"Kill All Zombies","cheats.killAllZombiesDesc":"Clear all zombies currently on the board.","cheats.level":"Level","cheats.speed2x":"1.5×","cheats.restoreMowers":"Restore Lawnmowers","cheats.restoreMowersDesc":"Restore missing lawnmowers for all rows","cheats.autoCollect":"Auto Collect","cheats.autoCollectDesc":"Automatically collect sun and coins","cheats.allowCheatRequired":'Enable "Cheat" in the in-game Settings to use the Trainer',"cheats.misc":"Misc","cheats.timeStop":"Time Stop","cheats.timeStopDesc":"Pause all game logic (set scheduler timeScale to 0)","cheats.sandboxMode":"Sandbox Mode — synced with in-game settings","cheats.storeScene":"Store","cheats.zenGardenScene":"Zen Garden","cheats.freeBuy":"Buy Without Cost","cheats.freeBuyDesc":"Purchase any item without spending currency or meeting unlock conditions","cheats.refreshCostume":"Refresh Costume Shop","cheats.refreshCostumeDesc":"Randomly refresh today's costume daily rotation","cheats.seeds":"Seeds","cheats.quickGrow":"Quick Grow All","cheats.quickGrowDesc":"Instantly advance all plants to fully grown","cheats.add500":"+500","cheats.add5000":"+5000","cheats.add50000":"+50,000","cheats.add100000":"+100,000","cheats.add1":"+1","cheats.add5":"+5","cheats.add10":"+10","cheats.add50":"+50","log.title":"Runtime Logs","log.filterAll":"ALL","log.clear":"Clear Logs","log.empty":"No log entries","log.copyAll":"Copy All","settings.title":"Settings","settings.language":"Language","settings.frameRate":"Frame Rate","settings.scrollSensitivity":"Scroll Settings","settings.scrollSensitivityEnabled":"Scrolling Optimization","settings.scrollSensitivityEnabledDesc":"When enabled, GP-Next takes over wheel scrolling and selector switching behavior. Turn off to restore the game's original handling.","settings.scrollSensitivityWheel":"Wheel / Scroll","settings.scrollSensitivityWheelDesc":"100% = default game behavior.","settings.scrollSensitivityDiscreteInterval":"Selector Min Interval","settings.scrollSensitivityDiscreteIntervalDesc":"Minimum time between selector switches. Affects sandbox plant/zombie selectors and the world chooser.","settings.debugMode":"Debug Mode","settings.debugModeDesc":"Enable verbose console logging","settings.runtimeExtensions":"Runtime Extensions","settings.runtimeExtensionsReloadHint":"Takes effect after reloading patches / restarting the game.","settings.dynamicPlantRegistry":"Dynamic Plant Registry","settings.dynamicPlantRegistryDesc":"Let GP-Next replace the game's original plant identity logic so datapacks can add or clone plants.","settings.autoPatch":"Auto Patch","settings.autoPatchDesc":"Apply patches automatically on asset load","settings.hpOverlay":"HP Overlay","settings.showPlantHp":"Show Plant HP","settings.showPlantHpDesc":"Show real-time HP above plants","settings.showZombieHp":"Show Zombie HP","settings.showZombieHpDesc":"Show real-time HP above zombies","settings.showTombHp":"Show Tomb HP","settings.showTombHpDesc":"Show real-time HP above tomb-type ground objects","cloud.title":"Cloud Save","cloud.notLoggedIn":"Not logged in","cloud.loggedInAs":"Logged in as {0}","cloud.login":"Login","cloud.logout":"Logout","cloud.upload":"Upload Save","cloud.download":"Download Save","cloud.uploadConfirm":"Overwrite cloud save with local data?","cloud.downloadConfirm":"Overwrite local data with cloud save?","cloud.comparison":"Save Comparison","cloud.local":"Local","cloud.remote":"Cloud","about.title":"About GP-Next","about.gameVersion":"Game Version","about.patcherVersion":"Patcher Version","about.docs":"Documentation","about.consoleHelp":"Console Commands","about.consoleHelpDesc":"Type gpNext.help() in console for full command reference","about.createdBy":"GP-Next Created by","common.on":"ON","common.off":"OFF","common.cancel":"Cancel","common.confirm":"Confirm","common.close":"Close","common.loading":"Loading...","common.success":"Success","common.failed":"Failed","common.unlimited":"Unlimited","toast.saving":"Saving: {0}","toast.saved":"Saved: {0}","toast.saveFailed":"Save failed: {0}","toast.downloading":"Downloading: {0}","toast.exportSuccess":"{0} exported successfully","toast.exportCancelled":"Export cancelled","toast.restoreSuccess":"{0} restored","toast.patchReloaded":"Patches reloaded","toast.updateAvailable":"GP-Next update available: v{0}","toast.updateUpToDate":"GP-Next is up to date (v{0})","toast.updateCheckFailed":"Failed to check for GP-Next updates"},"zh-CN":{"header.status.waiting":"等待引擎加载...","header.status.ready":"就绪","header.status.engineReady":"引擎已就绪","header.status.patchesLoaded":"{0} 个数据包，{1} 项修改","header.status.patchesLoadedWithEdits":"{0} 个数据包，{1} 项修改，{2} 项手动编辑","header.status.timeout":"未检测到引擎","header.f10Hint":"F10","footer.version":"GP-Next v{0}","footer.updateIdle":"检查更新","footer.updateChecking":"检查中...","footer.upToDate":"已是最新版本","footer.updateAvailable":"发现更新: v{0}","footer.updateCheckFailed":"检查更新失败","footer.checkNow":"立即检查更新","footer.openDownload":"打开下载页面","tab.patcher":"补丁","tab.data":"数据","tab.cheats":"修改器","tab.settings":"设置","tab.cloud":"云存档","tab.about":"关于","tab.log":"日志","tab.guide":"指南","patcher.title":"补丁状态","patcher.engineState":"引擎","patcher.assetCount":"资源数量","patcher.patchList":"已加载补丁","patcher.actions":"操作","patcher.reloadAll":"重新加载所有补丁","patcher.restoreAll":"恢复所有原始数据","patcher.patchLog":"补丁日志","patcher.basePath":"补丁文件目录","patcher.openDir":"打开目录","patcher.loaded":"已加载","patcher.skipped":"已跳过","patcher.error":"错误","patcher.noPatchesFound":"未找到补丁文件","patcher.reloading":"正在重新加载...","patcher.restoring":"正在恢复...","patcher.restored":"已恢复 {0} 个类型","patcher.active":"活跃","patcher.inactive":"未激活","patcher.packs":"数据包","patcher.noPacks":"未在 gp-next/packs/ 中找到任何数据包","patcher.singleFile":"单文件补丁","patcher.singleFileSection":"patches/","patcher.packPriority":"优先级:{0}","patcher.packItems":"{0} 项","patcher.packErrors":"{0} 项错误","patcher.errors":"加载错误","patcher.moveUp":"上移","patcher.moveDown":"下移","patcher.saveOrder":"保存顺序","patcher.orderSaved":"顺序已保存","patcher.packAuthor":"作者：{0}","patcher.packMeta":"Game: {0} · GP-Next: {1}","patcher.packMetaGameOnly":"Game: {0}","patcher.packMetaGpnOnly":"GP-Next: {0}","patcher.noUuid":"⚠ 缺少 uuid — 顺序不会被保存","patcher.disabledPacks":"已禁用的数据包","patcher.enablePack":"激活","patcher.disablePack":"禁用","patcher.loadOrderHint":"上→下加载：同名条目中，下方数据包的内容会覆盖上方的。","patcher.saveAndReload":"保存并重载","patcher.saveAndReloading":"正在保存并重载...","patcher.gpnEdits":"手动编辑 (GP-Next)","patcher.gpnEditsSection":"__gpn_edits（手动编辑）","data.drawer.treeView":"树形视图","data.drawer.rawJson":"JSON","data.drawer.comparison":"对比","data.drawer.edit":"编辑","data.drawer.save":"保存","data.drawer.restoreItem":"还原此条目","data.drawer.restoreType":"还原此类型","data.drawer.restoreAll":"清除全部","data.drawer.restoreNote":"仅清除手动编辑，持久修改请使用数据包。","data.drawer.restoreConfirm":"确认清除此条目的手动编辑？（Packs/Patches 不受影响）","data.drawer.restoreTypeConfirm":"确认清除该类型的所有手动编辑？（Packs/Patches 不受影响）","data.drawer.restoreAllConfirm":"确认清除所有重载类型的手动编辑吗？（Packs/Patches 不受影响）","data.drawer.saveSuccess":"编辑已保存。重载补丁后完全生效。","data.drawer.saveFail":"保存失败。","data.drawer.restoreCount":"还原 {0} 项手动编辑","data.drawer.editHint":"提示：此处编辑仅建议用于快速微调或临时调试，正式/持久修改请使用数据包。将值设为 null 可在合并时删除该字段。","data.drawer.noOriginal":"未找到原始备份（可能由数据包新增）。","data.drawer.noChanges":"与原始数据完全一致 — 无编辑。","data.drawer.loadMore":"加载更多（▾ 剩余 {0} 项）","header.status.compact":"P:{0} / 项:{1}","header.status.compactWithEdits":"P:{0} / 项:{1} / ✏{2}","common.confirm":"确认","common.cancel":"取消","patcher.gpnEdits":"手动编辑","patcher.gpnEditsSection":"手动编辑（GP-Next）","guide.title":"入门指南","guide.docs":"在线文档","guide.docsDesc":"查看更详细的模组制作教程与指南：","guide.intro":"GP-Next 允许加载模块化的 JSON 数据包。将你的数据包放入 GP-Next 的 packs 目录中，它们将被自动加载。","guide.dirStructure":"目录结构","guide.packJson":"pack.json 说明","guide.packJsonNote":`uuid：用于记忆加载顺序的唯一标识符。
priority：越小越先应用，默认 100。
包目录下的 thumbnail.png 作为封面图。
支持将数据包以 ZIP 格式放入 packs/ 目录，ZIP 内部结构与文件夹格式相同。

元数据字段：
formatVersion：包格式版本（当前为 1）。
gameVersion：目标游戏版本（例如 "0.7.X"）。
gpNextVersion：所需 GP-Next 版本范围（例如 ">=1.0.0"）。

语言包 (jsons/lang/lang.json)：
深度合并到 MultiLanguage.lyrics，支持局部更新 — 只需提供要覆盖的字段。

可选的 '_languages' 字段用于在游戏设置的语言切换按钮中添加更多语言选项：
{ '_languages': [{ 'code': 'es', 'name': 'Español', 'isCJK': false }] }
每种额外语言在各 {en, zh} 文本节点中对应同名字段（如 'es'）。所有 lyrics 段落及 DirectQuote / LoadingTips 条目均支持。`,"guide.patchTypes":"支持的补丁文件","guide.priority":"优先级与合并顺序","guide.priorityDesc":`补丁与数据包按以下顺序依次应用（优先级从低到高）：

1. packs/ 目录：数据包，按 priority 升序排序应用。
2. patches/ 目录：单文件补丁层，用于向下兼容旧版。
3. 手动编辑：你在“数据”面板中进行的零散修改（优先级最高，始终覆盖）。

后续步骤的数据会深度合并覆盖前一步的数据。对于关卡文件，最后提供该文件的层优先。`,"guide.manualEdits":"关于手动编辑 (数据面板)","guide.manualEditsDesc":`可在工具的“数据”面板中浏览并直接修改游戏数值。这些编辑会被独立保存，且始终覆盖其他所有数据包和补丁。

建议仅用于快速微调或临时调试。需要稳定、可分享或较复杂的修改，请改为制作数据包。`,"data.title":"数据浏览","data.selectType":"选择类型","data.searchPlaceholder":"按 CODENAME 或 alias 搜索...","data.exportCurrent":"导出当前数据","data.exportOriginal":"导出原始数据","data.noData":"暂无数据","data.entries":"{0} 条记录","cheats.title":"修改器","cheats.requireInGame":"仅在游戏关卡内可用","cheats.sun":"阳光","cheats.setSun":"设置阳光","cheats.addSun":"+1000","cheats.addSun200":"+200","cheats.addSun500":"+500","cheats.addSun5000":"+5000","cheats.resetSpeed":"1×","cheats.gameSpeed":"游戏速度","cheats.gameSpeedDesc":"关卡内速度切换","cheats.freePlant":"免费种植","cheats.freePlantDesc":"种植不消耗阳光","cheats.invincible":"植物无敌","cheats.invincibleDesc":"植物不会受到伤害","cheats.showPlantHp":"显示植物血量","cheats.showPlantHpDesc":"在植物上方显示实时血量","cheats.showZombieHp":"显示僵尸血量","cheats.showZombieHpDesc":"在僵尸上方显示实时血量","cheats.instantWin":"立即胜利","cheats.instantWinDesc":"立即触发过关胜利","cheats.instantWinSandboxDisabled":"沙盒模式下禁用直接通关","cheats.noCooldown":"无冷却","cheats.noCooldownDesc":"种植后卡片无需冷却","cheats.unsupportedScene":"当前场景暂无可用修改项。","cheats.normalLevel":"普通关卡","cheats.worldMap":"世界地图","cheats.coins":"金币","cheats.setCoins":"设置金币","cheats.clearCoins":"清空","cheats.gems":"钻石","cheats.setGems":"设置钻石","cheats.clearGems":"清空","cheats.setSeeds":"设置种子数量","cheats.clearSeeds":"清空","cheats.add50":"+50","cheats.add100":"+100","cheats.add1000":"+1000","cheats.add10000":"+10000","cheats.plantFood":"叶绿素","cheats.fillPlantFood":"填满","cheats.clearPlantFood":"清空","cheats.freePF":"免费叶绿素","cheats.freePFDesc":"使用叶绿素不消耗","cheats.resources":"资源","cheats.plant":"植物","cheats.zombie":"僵尸","cheats.killAllZombies":"秒杀全部僵尸","cheats.killAllZombiesDesc":"清除当前场上所有僵尸","cheats.level":"关卡","cheats.speed2x":"1.5×","cheats.restoreMowers":"恢复割草机","cheats.restoreMowersDesc":"为所有行恢复已失去的割草机","cheats.restoreMowersSandboxDisabled":"沙盒模式中禁用恢复割草机","cheats.autoCollect":"自动收集","cheats.autoCollectDesc":"自动收集阳光和金币","cheats.allowCheatRequired":"请在游戏设置中开启「作弊」选项以使用修改器","cheats.misc":"其他","cheats.timeStop":"时间停滞","cheats.timeStopDesc":"暂停所有游戏逻辑（将调度器 timeScale 设为 0）","cheats.sandboxMode":"沙盒模式 — 已与游戏内设置同步","cheats.storeScene":"商店","cheats.zenGardenScene":"禅境花园","cheats.freeBuy":"无条件购买","cheats.freeBuyDesc":"购买任意物品，无需消耗货币或满足解锁条件","cheats.refreshCostume":"刷新服装商店","cheats.refreshCostumeDesc":"随机刷新今日服装每日活动","cheats.seeds":"种子","cheats.quickGrow":"立即成长","cheats.quickGrowDesc":"立即将所有植物提升至最大成长阶段","cheats.add500":"+500","cheats.add5000":"+5000","cheats.add50000":"+50,000","cheats.add100000":"+100,000","cheats.add1":"+1","cheats.add5":"+5","cheats.add10":"+10","cheats.add50":"+50","log.title":"运行日志","log.filterAll":"全部级别","log.clear":"清空日志","log.empty":"暂无日志记录","log.copyAll":"复制全部","settings.title":"设置","settings.language":"语言","settings.frameRate":"帧率","settings.scrollSensitivity":"滚动设置","settings.scrollSensitivityEnabled":"滚动优化","settings.scrollSensitivityEnabledDesc":"开启后由 GP-Next 接管滚轮滚动和选择栏切换逻辑。关闭后恢复为游戏本体的原始处理方式。","settings.scrollSensitivityWheel":"滚轮 / 滚动","settings.scrollSensitivityWheelDesc":"100% = 游戏默认行为。","settings.scrollSensitivityDiscreteInterval":"选择栏最小间隔","settings.scrollSensitivityDiscreteIntervalDesc":"选择栏切换的最小时间间隔。影响沙盒植物/僵尸栏和世界选择器等。","settings.debugMode":"调试模式","settings.debugModeDesc":"启用详细控制台日志输出","settings.runtimeExtensions":"运行时扩展","settings.runtimeExtensionsReloadHint":"重新加载补丁 / 重启游戏后生效。","settings.dynamicPlantRegistry":"动态植物注册","settings.dynamicPlantRegistryDesc":"允许 GP-Next 接管游戏原本的植物身份逻辑，让数据包可以新增或克隆植物。","settings.autoPatch":"自动补丁","settings.autoPatchDesc":"资源加载时自动应用补丁","settings.hpOverlay":"血量显示","settings.showPlantHp":"显示植物血量","settings.showPlantHpDesc":"在植物上方显示实时血量","settings.showZombieHp":"显示僵尸血量","settings.showZombieHpDesc":"在僵尸上方显示实时血量","settings.showTombHp":"显示地物血量","settings.showTombHpDesc":"在 Tomb 系地物上方显示实时血量","cloud.title":"云存档","cloud.notLoggedIn":"未登录","cloud.loggedInAs":"已登录: {0}","cloud.login":"登录","cloud.logout":"退出登录","cloud.upload":"上传存档","cloud.download":"下载存档","cloud.uploadConfirm":"确定用本地数据覆盖云端存档？","cloud.downloadConfirm":"确定用云端存档覆盖本地数据？","cloud.comparison":"存档对比","cloud.local":"本地","cloud.remote":"云端","about.title":"关于 GP-Next","about.gameVersion":"游戏版本","about.patcherVersion":"补丁器版本","about.docs":"文档","about.consoleHelp":"控制台命令","about.consoleHelpDesc":"在控制台输入 gpNext.help() 查看完整命令参考","about.createdBy":"GP-Next 作者","common.on":"开","common.off":"关","common.cancel":"取消","common.confirm":"确认","common.close":"关闭","common.loading":"加载中...","common.success":"成功","common.failed":"失败","common.unlimited":"不限制","toast.saving":"正在保存: {0}","toast.saved":"已保存: {0}","toast.saveFailed":"保存失败: {0}","toast.downloading":"正在下载: {0}","toast.exportSuccess":"{0} 导出成功","toast.exportCancelled":"导出已取消","toast.restoreSuccess":"{0} 已恢复","toast.patchReloaded":"补丁已重新加载","toast.updateAvailable":"发现 GP-Next 更新: v{0}","toast.updateUpToDate":"GP-Next 已是最新版本 (v{0})","toast.updateCheckFailed":"检查 GP-Next 更新失败"}};let Dt="en";const Qe=[];function ma(){const e=jt().locale;return e&&rt[e]?e:(navigator.language||"").startsWith("zh")?"zh-CN":"en"}function w(e,...t){const n=rt[Dt]?.[e]??rt.en?.[e]??e;return t.length===0?n:n.replace(/\{(\d+)\}/g,(a,r)=>t[r]??"")}function yu(e){rt[e]&&(Dt=e,ha({locale:e}),Qe.forEach(t=>t(e)))}function Ca(){return Dt}function Eu(){return[{id:"en",label:"English"},{id:"zh-CN",label:"简体中文"}]}function ba(e){return Qe.push(e),()=>{const t=Qe.indexOf(e);t!==-1&&Qe.splice(t,1)}}Dt=ma();const wa=`
.ge-toast{background:rgba(18,18,18,0.92);color:#e8e8e8;padding:10px 14px;border-radius:6px;font-size:13px;font-family:'Segoe UI',system-ui,sans-serif;
  box-shadow:0 4px 16px rgba(0,0,0,.5);opacity:0;transform:translateX(20px);transition:opacity .2s,transform .2s;border-left:3px solid #4a9eff;max-width:260px;word-break:break-all;line-height:1.4;cursor:pointer;}
.ge-toast.ge-show{opacity:1;transform:translateX(0);}
.ge-toast.ge-success{border-left-color:#4caf50;}
.ge-toast.ge-error{border-left-color:#f44336;}
`;let be=null,Nt=!1;function Fn(){if(Nt)return;Nt=!0;const e=document.createElement("style");e.id="gp-next-toast-styles",e.textContent=wa,document.head.appendChild(e),be=document.createElement("div"),be.id="ge-toast-wrap",be.style.cssText="position:fixed;top:16px;right:16px;z-index:2147483647;display:flex;flex-direction:column;gap:8px;pointer-events:none;",document.body.appendChild(be)}function V(e,t="",n=3500){Nt||Fn();const a=document.createElement("div");for(a.className=`ge-toast${t?" ge-"+t:""}`,a.textContent=e,a.style.pointerEvents="auto",a.addEventListener("click",()=>{a.classList.remove("ge-show"),setTimeout(()=>a.remove(),250)}),be.appendChild(a),requestAnimationFrame(()=>a.classList.add("ge-show")),setTimeout(()=>{a.classList.remove("ge-show"),setTimeout(()=>a.remove(),250)},n);be.children.length>5;)be.firstChild.remove()}function ya(e,t,n,a){if(typeof t=="function"?e!==t||!a:!t.has(e))throw new TypeError("Cannot read private member from an object whose class did not declare it");return n==="m"?a:n==="a"?a.call(e):a?a.value:t.get(e)}function Ea(e,t,n,a,r){if(typeof t=="function"?e!==t||!0:!t.has(e))throw new TypeError("Cannot write private member to an object whose class did not declare it");return t.set(e,n),n}var et;const K="__TAURI_TO_IPC_KEY__";function Aa(e,t=!1){return window.__TAURI_INTERNALS__.transformCallback(e,t)}async function p(e,t={},n){return window.__TAURI_INTERNALS__.invoke(e,t,n)}class Fa{get rid(){return ya(this,et,"f")}constructor(t){et.set(this,void 0),Ea(this,et,t)}async close(){return p("plugin:resources|close",{rid:this.rid})}}et=new WeakMap;async function xa(e={}){return typeof e=="object"&&Object.freeze(e),await p("plugin:dialog|save",{options:e})}var ut;(function(e){e[e.Audio=1]="Audio",e[e.Cache=2]="Cache",e[e.Config=3]="Config",e[e.Data=4]="Data",e[e.LocalData=5]="LocalData",e[e.Document=6]="Document",e[e.Download=7]="Download",e[e.Picture=8]="Picture",e[e.Public=9]="Public",e[e.Video=10]="Video",e[e.Resource=11]="Resource",e[e.Temp=12]="Temp",e[e.AppConfig=13]="AppConfig",e[e.AppData=14]="AppData",e[e.AppLocalData=15]="AppLocalData",e[e.AppCache=16]="AppCache",e[e.AppLog=17]="AppLog",e[e.Desktop=18]="Desktop",e[e.Executable=19]="Executable",e[e.Font=20]="Font",e[e.Home=21]="Home",e[e.Runtime=22]="Runtime",e[e.Template=23]="Template"})(ut||(ut={}));async function va(){return p("plugin:path|resolve_directory",{directory:ut.AppData})}var ln;(function(e){e[e.Start=0]="Start",e[e.Current=1]="Current",e[e.End=2]="End"})(ln||(ln={}));async function Sa(e,t){if(e instanceof URL&&e.protocol!=="file:")throw new TypeError("Must be a file URL.");await p("plugin:fs|mkdir",{path:e instanceof URL?e.toString():e,options:t})}async function Ba(e,t){if(e instanceof URL&&e.protocol!=="file:")throw new TypeError("Must be a file URL.");return await p("plugin:fs|read_dir",{path:e instanceof URL?e.toString():e,options:t})}async function _a(e,t){if(e instanceof URL&&e.protocol!=="file:")throw new TypeError("Must be a file URL.");const n=await p("plugin:fs|read_file",{path:e instanceof URL?e.toString():e,options:t});return n instanceof ArrayBuffer?new Uint8Array(n):Uint8Array.from(n)}async function ka(e,t){if(e instanceof URL&&e.protocol!=="file:")throw new TypeError("Must be a file URL.");const n=await p("plugin:fs|read_text_file",{path:e instanceof URL?e.toString():e,options:t}),a=n instanceof ArrayBuffer?n:Uint8Array.from(n);return new TextDecoder().decode(a)}async function Pa(e,t){if(e instanceof URL&&e.protocol!=="file:")throw new TypeError("Must be a file URL.");await p("plugin:fs|remove",{path:e instanceof URL?e.toString():e,options:t})}async function xn(e,t,n){if(e instanceof URL&&e.protocol!=="file:")throw new TypeError("Must be a file URL.");const a=new TextEncoder;await p("plugin:fs|write_text_file",a.encode(t),{headers:{path:encodeURIComponent(e instanceof URL?e.toString():e),options:JSON.stringify(n)}})}async function Na(e,t){if(e instanceof URL&&e.protocol!=="file:")throw new TypeError("Must be a file URL.");return await p("plugin:fs|exists",{path:e instanceof URL?e.toString():e,options:t})}let cn=!1;function Ta(){if(cn)return;cn=!0;const e=HTMLElement.prototype.click;HTMLElement.prototype.click=function(){if(this instanceof HTMLAnchorElement&&this.hasAttribute("download")&&this.href){const t=this.getAttribute("download")||"download",n=this.href;if(n.startsWith("blob:")){(async()=>{try{V(w("toast.saving",t),"",4e3);const a=t.includes(".")?t.split(".").pop():"*",r=await xa({defaultPath:t,filters:[{name:"File",extensions:[a]}]});if(r){const u=await(await fetch(n)).text();await xn(r,u),V(w("toast.saved",t),"success")}}catch(a){console.error("[GP Next] Download intercept failed:",a),V(w("toast.saveFailed",t),"error")}})();return}V(w("toast.downloading",t),"")}return e.call(this)}}const La=`
/* ===== Overlay Container ===== */
#gp-overlay {
    position: fixed;
    top: 0; left: 0;
    width: min(420px, 92vw);
    height: 100%;
    background: rgba(2, 6, 23, 0.96);
    color: #f1f5f9;
    z-index: 99999;
    transform: translateX(-100%);
    transition: transform 0.3s cubic-bezier(0.4, 0, 0.2, 1);
    font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
    font-size: 13px;
    display: flex;
    flex-direction: column;
    box-shadow: 4px 0 24px rgba(0,0,0,0.6);
    user-select: text;
    text-align: left;
}
#gp-overlay.gp-open {
    transform: translateX(0);
}

/* ===== Header ===== */
.gp-header {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 14px 16px;
    border-bottom: 1px solid rgba(255,255,255,0.08);
    flex-shrink: 0;
}
.gp-logo {
    font-weight: 700;
    font-size: 16px;
    color: #fff;
    letter-spacing: 0.5px;
}
.gp-status {
    margin-left: auto;
    font-size: 11px;
    color: #4a9eff;
    flex: 1;
    min-width: 0;
    max-width: 160px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    text-align: right;
}
.gp-close-btn {
    background: none;
    border: none;
    color: #888;
    font-size: 18px;
    cursor: pointer;
    padding: 0 4px;
    line-height: 1;
    transition: color 0.15s;
}
.gp-close-btn:hover {
    color: #fff;
}

/* ===== Tab Bar ===== */
.gp-tabs {
    display: flex;
    flex-wrap: nowrap;
    overflow-x: auto;
    overscroll-behavior-x: contain;
    border-bottom: 1px solid rgba(255,255,255,0.08);
    flex-shrink: 0;
    padding: 0 2px;
}
.gp-tab {
    background: none;
    border: none;
    color: #888;
    font-size: 12px;
    font-family: inherit;
    padding: 8px 12px;
    min-height: 36px;
    cursor: pointer;
    border-bottom: 2px solid transparent;
    white-space: nowrap;
    transition: color 0.15s, border-color 0.15s;
    flex: 0 0 auto;
}
.gp-tab:hover {
    color: #ccc;
}
.gp-tab.gp-tab-active {
    color: #fff;
    border-bottom-color: #4a9eff;
}

/* ===== Content Area ===== */
.gp-content {
    flex: 1;
    overflow-y: auto;
    padding: 14px 16px 16px;
    scroll-padding-bottom: 24px;
}

.gp-footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    padding: 9px 12px;
    border-top: 1px solid rgba(255,255,255,0.08);
    background: rgba(255,255,255,0.03);
    flex-shrink: 0;
}
.gp-footer-version {
    font-size: 11px;
    color: #80889b;
    white-space: nowrap;
}
.gp-footer-right {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
    flex-wrap: wrap;
    justify-content: flex-end;
}
.gp-footer-update,
.gp-footer-refresh {
    background: none;
    border: none;
    color: #8d97ab;
    font: inherit;
    padding: 0;
}
.gp-footer-update {
    font-size: 11px;
    max-width: 180px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    cursor: default;
}
.gp-footer-update:disabled {
    opacity: 1;
}
.gp-footer-update-hot {
    color: #4a9eff;
    cursor: pointer;
}
.gp-footer-update-hot:hover {
    color: #7cb9ff;
    text-decoration: underline;
}
.gp-footer-refresh {
    font-size: 14px;
    line-height: 1;
    cursor: pointer;
    transition: color 0.15s, transform 0.15s;
}
.gp-footer-refresh:hover:not(:disabled) {
    color: #d8e6ff;
    transform: rotate(20deg);
}
.gp-footer-refresh:disabled {
    cursor: default;
    opacity: 0.7;
}
.gp-spinning {
    animation: gp-next-spin 0.9s linear infinite;
}

@keyframes gp-next-spin {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
}

/* ===== Scrollbar ===== */
#gp-overlay ::-webkit-scrollbar { width: 5px; }
#gp-overlay ::-webkit-scrollbar-track { background: transparent; }
#gp-overlay ::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.15); border-radius: 3px; }
#gp-overlay ::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,0.25); }

/* ===== F1 Hint Badge ===== */
.gp-f1-hint {
    position: fixed;
    top: 8px; left: 8px;
    background: rgba(16,16,24,0.85);
    color: #888;
    font-family: 'Segoe UI', system-ui, sans-serif;
    font-size: 10px;
    padding: 3px 7px;
    border-radius: 4px;
    z-index: 99998;
    cursor: pointer;
    transition: opacity 0.2s, color 0.15s;
    pointer-events: auto;
}
.gp-f1-hint:hover {
    color: #ccc;
}
.gp-f1-hint.gp-hidden {
    opacity: 0;
    pointer-events: none;
}

/* ===== Components: Button ===== */
.gp-btn {
    background: rgba(74,158,255,0.15);
    color: #4a9eff;
    border: 1px solid rgba(74,158,255,0.3);
    border-radius: 4px;
    padding: 6px 12px;
    min-height: 32px;
    font-size: 12px;
    font-family: inherit;
    cursor: pointer;
    transition: background 0.15s, border-color 0.15s;
    line-height: 1.2;
}
.gp-btn:hover {
    background: rgba(74,158,255,0.25);
    border-color: rgba(74,158,255,0.5);
}
.gp-btn:active {
    background: rgba(74,158,255,0.35);
}
.gp-btn-danger {
    background: rgba(244,67,54,0.12);
    color: #f44336;
    border-color: rgba(244,67,54,0.3);
}
.gp-btn-danger:hover {
    background: rgba(244,67,54,0.22);
    border-color: rgba(244,67,54,0.5);
}
.gp-btn-success {
    background: rgba(76,175,80,0.12);
    color: #4caf50;
    border-color: rgba(76,175,80,0.3);
}
.gp-btn-success:hover {
    background: rgba(76,175,80,0.22);
    border-color: rgba(76,175,80,0.5);
}
.gp-btn-sm {
    padding: 4px 9px;
    font-size: 11px;
    min-height: 28px;
}
.gp-btn-row {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
}

/* ===== Components: Toggle ===== */
.gp-toggle-wrap {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 4px 0;
}
.gp-toggle-label {
    font-size: 12px;
    color: #ccc;
    line-height: 1.4;
}
.gp-toggle {
    position: relative;
    width: 36px; height: 18px;
    background: rgba(255,255,255,0.12);
    border-radius: 9px;
    cursor: pointer;
    transition: background 0.2s;
    flex-shrink: 0;
}
.gp-toggle.gp-toggle-on {
    background: rgba(74,158,255,0.5);
}
.gp-toggle-knob {
    position: absolute;
    top: 2px; left: 2px;
    width: 14px; height: 14px;
    background: #e0e0e0;
    border-radius: 50%;
    transition: transform 0.2s;
}
.gp-toggle.gp-toggle-on .gp-toggle-knob {
    transform: translateX(18px);
    background: #fff;
}

/* ===== Components: Slider ===== */
.gp-slider-wrap {
    padding: 4px 0;
}
.gp-slider-header {
    display: flex;
    justify-content: space-between;
    margin-bottom: 4px;
}
.gp-slider-label { font-size: 12px; color: #ccc; }
.gp-slider-value { font-size: 11px; color: #4a9eff; font-weight: 600; }
.gp-slider {
    -webkit-appearance: none;
    width: 100%; height: 4px;
    background: rgba(255,255,255,0.12);
    border-radius: 2px;
    outline: none;
}
.gp-slider::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: 14px; height: 14px;
    background: #4a9eff;
    border-radius: 50%;
    cursor: pointer;
}

/* ===== Components: Input ===== */
.gp-input-wrap {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 4px 0;
}
.gp-input-label {
    font-size: 12px;
    color: #ccc;
    white-space: nowrap;
    min-width: 92px;
}
.gp-input {
    background: rgba(255,255,255,0.06);
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 4px;
    color: #e0e0e0;
    padding: 4px 8px;
    font-size: 12px;
    font-family: inherit;
    outline: none;
    transition: border-color 0.15s;
    width: 100%;
    min-width: 0;
}
.gp-input:focus {
    border-color: rgba(74,158,255,0.5);
}

/* ===== Components: Select ===== */
.gp-select-wrap {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 4px 0;
}
.gp-select-label {
    font-size: 12px;
    color: #ccc;
    white-space: nowrap;
    min-width: 92px;
}
.gp-select {
    -webkit-appearance: none;
    appearance: none;
    background-color: rgba(30,30,45,0.95);
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='10' height='6' viewBox='0 0 10 6'%3E%3Cpath d='M0 0l5 6 5-6z' fill='%23888'/%3E%3C/svg%3E");
    background-repeat: no-repeat;
    background-position: right 8px center;
    background-size: 10px 6px;
    border: 1px solid rgba(255,255,255,0.18);
    border-radius: 4px;
    color: #e0e0e0;
    padding: 4px 26px 4px 8px;
    font-size: 12px;
    font-family: inherit;
    outline: none;
    cursor: pointer;
    width: 100%;
    min-width: 0;
}
.gp-select:focus {
    border-color: rgba(74,158,255,0.5);
}
.gp-select option {
    background-color: #1e1e2e;
    color: #e0e0e0;
}
.gp-select option:checked {
    background-color: #1a4a8a;
    color: #ffffff;
}

/* ===== Components: Section ===== */
.gp-section {
    margin-bottom: 12px;
    padding: 10px 12px;
    border-radius: 8px;
    background: rgba(255,255,255,0.03);
    border: 1px solid rgba(255,255,255,0.05);
}
.gp-section-title {
    width: 100%;
    font-size: 11px;
    font-weight: 600;
    color: #888;
    text-transform: uppercase;
    letter-spacing: 0.8px;
    margin-bottom: 8px;
    padding: 0 0 6px;
    border-bottom: 1px solid rgba(255,255,255,0.06);
    cursor: pointer;
    user-select: none;
    display: flex;
    align-items: center;
    gap: 6px;
    background: none;
    border-top: none;
    border-left: none;
    border-right: none;
    text-align: left;
}
.gp-section-arrow {
    font-size: 9px;
    transition: transform 0.15s;
}
.gp-section.gp-collapsed .gp-section-arrow {
    transform: rotate(-90deg);
}
.gp-section-body {
    display: flex;
    flex-direction: column;
    gap: 8px;
}
.gp-section.gp-collapsed .gp-section-body {
    display: none;
}

/* ===== Components: Badge ===== */
.gp-badge {
    display: inline-block;
    font-size: 10px;
    font-weight: 600;
    padding: 1px 6px;
    border-radius: 3px;
    line-height: 1.4;
}
.gp-badge-info { background: rgba(74,158,255,0.2); color: #4a9eff; }
.gp-badge-success { background: rgba(76,175,80,0.2); color: #4caf50; }
.gp-badge-warning { background: rgba(255,152,0,0.2); color: #ff9800; }
.gp-badge-error { background: rgba(244,67,54,0.2); color: #f44336; }

/* ===== Components: List ===== */
.gp-list {
    display: flex;
    flex-direction: column;
    gap: 2px;
}
.gp-list-item {
    padding: 8px 10px;
    border-radius: 6px;
    font-size: 12px;
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
}
.gp-list-item .gp-text-mono {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    min-width: 0;
    flex: 1;
}
.gp-list-item .gp-text-muted {
    flex-shrink: 0;
    white-space: nowrap;
}
.gp-list-item:hover {
    background: rgba(255,255,255,0.04);
}

/* ===== Components: Search ===== */
.gp-search-wrap {
    padding: 4px 0 8px;
}
.gp-search {
    width: 100%;
    background: rgba(255,255,255,0.06);
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 4px;
    color: #e0e0e0;
    padding: 6px 10px;
    font-size: 12px;
    font-family: inherit;
    outline: none;
    box-sizing: border-box;
}
.gp-search:focus {
    border-color: rgba(74,158,255,0.5);
}

/* ===== Utilities ===== */
.gp-text-muted { color: #666; font-size: 11px; }
.gp-text-mono { font-family: 'Consolas', 'Monaco', monospace; font-size: 11px; }
.gp-mt-8 { margin-top: 8px; }
.gp-mb-8 { margin-bottom: 8px; }
.gp-gap-4 { gap: 4px; }
.gp-code {
    font-family: 'Consolas', 'Monaco', monospace;
    font-size: 11px;
    background: rgba(0,0,0,0.35);
    border: 1px solid rgba(255,255,255,0.08);
    border-radius: 4px;
    padding: 8px 10px;
    margin: 4px 0;
    white-space: pre;
    overflow-x: auto;
    line-height: 1.5;
    color: #b0c9e0;
    display: block;
    text-align: left;
    user-select: text;
    cursor: text;
}

/* ===== Pack Card ===== */
.gp-pack-card {
    display: grid;
    grid-template-columns: 44px minmax(0, 1fr) auto;
    align-items: flex-start;
    gap: 8px;
    padding: 8px;
    border-radius: 8px;
    background: rgba(255,255,255,0.03);
    border: 1px solid rgba(255,255,255,0.06);
}
.gp-pack-card:hover {
    background: rgba(255,255,255,0.055);
}
.gp-pack-thumb {
    width: 44px;
    height: 44px;
    flex-shrink: 0;
    border-radius: 4px;
    background: rgba(255,255,255,0.06);
    overflow: hidden;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 20px;
    line-height: 1;
}
.gp-pack-thumb-fallback {
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 0.08em;
    color: #9cdcfe;
}
.gp-pack-info {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
}
.gp-pack-name-row {
    display: flex;
    align-items: center;
    gap: 4px;
    flex-wrap: wrap;
}
.gp-pack-name {
    font-weight: 600;
    font-size: 12px;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
}
.gp-pack-ctrl {
    display: flex;
    flex-direction: column;
    gap: 2px;
    flex-shrink: 0;
}

/* ===== Data Detail Drawer ===== */
.gp-drawer {
    position: absolute;
    top: 0;
    left: 100%;
    width: min(680px, calc(100vw - 460px));
    min-width: 360px;
    max-width: calc(100vw - 32px);
    height: 100%;
    background: rgba(16, 16, 24, 0.95);
    backdrop-filter: blur(10px);
    border: 1px solid rgba(255,255,255,0.08);
    border-left: none;
    border-radius: 0 8px 8px 0;
    display: flex;
    flex-direction: column;
    transform: translateX(-20px);
    opacity: 0;
    pointer-events: none;
    transition: transform 0.3s cubic-bezier(0.4, 0, 0.2, 1), opacity 0.3s;
    z-index: -1;
    box-shadow: 4px 0 24px rgba(0,0,0,0.6);
}
.gp-drawer.gp-drawer-open {
    transform: translateX(0);
    opacity: 1;
    pointer-events: auto;
}
.gp-drawer-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 12px 16px;
    border-bottom: 1px solid rgba(255,255,255,0.08);
    flex-shrink: 0;
}
.gp-drawer-title {
    font-weight: 600;
    font-size: 13px;
    color: #fff;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    font-family: 'Consolas', monospace;
}
.gp-drawer-close {
    background: none;
    border: none;
    color: #888;
    font-size: 18px;
    cursor: pointer;
    line-height: 1;
    padding: 0 4px;
}
.gp-drawer-close:hover {
    color: #fff;
}
.gp-drawer-body {
    flex: 1;
    overflow-y: auto;
    padding: 12px 16px;
    display: flex;
    flex-direction: column;
}

/* Data Detail Sub Tabs */
.gp-drawer-tabs {
    display: flex;
    overflow-x: auto;
    border-bottom: 1px solid rgba(255,255,255,0.08);
    padding: 0 16px;
    flex-shrink: 0;
}
.gp-drawer-tab {
    background: none;
    border: none;
    color: #888;
    font-size: 11px;
    padding: 8px 12px;
    cursor: pointer;
    border-bottom: 2px solid transparent;
}
.gp-drawer-tab:hover { color: #ccc; }
.gp-drawer-tab.gp-active { color: #fff; border-bottom-color: #4a9eff; }

/* Tree View */
.gp-tree {
    font-family: 'Consolas', monospace;
    font-size: 12px;
    line-height: 1.6;
    user-select: text;
}
.gp-tree-node {
    padding-left: 14px;
    position: relative;
}
.gp-tree-caret {
    cursor: pointer;
    user-select: none;
    color: #888;
    font-size: 10px;
    position: absolute;
    left: 0;
    top: 3px;
    transition: transform 0.1s;
}
.gp-tree-caret:hover { color: #ccc; }
.gp-tree-caret.gp-collapsed { transform: rotate(-90deg); }
.gp-tree-key { color: #9cdcfe; margin-right: 4px; }
.gp-tree-val-str { color: #ce9178; }
.gp-tree-val-num { color: #b5cea8; }
.gp-tree-val-bool { color: #569cd6; }
.gp-tree-val-null { color: #888; }
.gp-tree-collapsed-text { color: #666; font-style: italic; cursor: pointer; }
.gp-tree-edit-input {
    background: rgba(0,0,0,0.5);
    border: 1px solid #4a9eff;
    color: #fff;
    font-family: inherit;
    font-size: inherit;
    padding: 0 2px;
    outline: none;
    width: auto;
    min-width: 40px;
}
/* Diff View */
.gp-diff-container {
    display: flex;
    flex-direction: column;
    gap: 8px;
    font-family: 'Consolas', monospace;
    font-size: 11px;
}
.gp-diff-row {
    display: flex;
    gap: 8px;
}
.gp-diff-col {
    flex: 1;
    min-width: 0;
    background: rgba(0,0,0,0.3);
    border-radius: 4px;
    padding: 8px;
    overflow-x: auto;
}
.gp-diff-col-title {
    color: #888;
    font-size: 10px;
    margin-bottom: 4px;
    text-transform: uppercase;
}
.gp-diff-line { white-space: pre; line-height: 1.4; display: flex; }
.gp-diff-add { background: rgba(76,175,80,0.15); color: #81c784; }
.gp-diff-sub { background: rgba(244,67,54,0.15); color: #e57373; }
.gp-diff-mod { background: rgba(255,152,0,0.15); color: #ffb74d; }

.gp-textarea-edit {
    width: 100%;
    flex: 1;
    min-height: 200px;
    background: rgba(0,0,0,0.3);
    border: 1px solid rgba(255,255,255,0.1);
    color: #e0e0e0;
    font-family: 'Consolas', monospace;
    font-size: 12px;
    padding: 8px;
    outline: none;
    resize: vertical;
    white-space: pre;
    tab-size: 2;
}
.gp-textarea-edit:focus { border-color: rgba(74,158,255,0.5); }

.gp-toolbar {
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 10px 12px;
    margin-bottom: 12px;
    border-radius: 8px;
    background: rgba(255,255,255,0.03);
    border: 1px solid rgba(255,255,255,0.05);
}
.gp-toolbar-controls {
    display: flex;
    flex-direction: column;
    gap: 8px;
}
.gp-toolbar-actions {
    margin-top: 2px;
}
.gp-toolbar-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    align-items: center;
}
.gp-data-item {
    align-items: flex-start;
}
.gp-data-item-main {
    display: flex;
    flex-direction: column;
    gap: 3px;
    min-width: 0;
    flex: 1;
}
.gp-data-item-title {
    font-size: 12px;
}
.gp-data-item-meta {
    white-space: normal;
    overflow-wrap: anywhere;
}
.gp-data-item-modified {
    border-left: 3px solid rgba(255, 180, 60, 0.7);
    padding-left: 9px;
}
.gp-data-load-more {
    justify-content: center;
    cursor: pointer;
}
.gp-empty-state {
    padding: 16px;
}
.gp-log-toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    margin-bottom: 8px;
}
.gp-log-title-group {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
}
.gp-log-title {
    font-size: 11px;
    font-weight: 600;
    color: #888;
    text-transform: uppercase;
    letter-spacing: 0.8px;
}
.gp-inline-actions {
    display: flex;
    gap: 6px;
    flex-wrap: wrap;
}
.gp-log-list {
    max-height: clamp(280px, 58vh, 560px);
}
.gp-log-entry {
    flex-direction: column;
    align-items: flex-start;
    gap: 4px;
    border-bottom: 1px solid rgba(255,255,255,0.04);
}
.gp-log-entry-top {
    display: flex;
    align-items: center;
    gap: 6px;
    width: 100%;
    min-width: 0;
}
.gp-log-entry-time {
    margin-left: auto;
    font-size: 10px;
}
.gp-log-entry-message {
    font-size: 11px;
    word-break: break-word;
    padding-left: 4px;
    width: 100%;
}
.gp-cloud-compare {
    max-height: 240px;
    white-space: pre-wrap;
    word-break: break-word;
}

.gp-btn:focus-visible,
.gp-tab:focus-visible,
.gp-close-btn:focus-visible,
.gp-footer-update-hot:focus-visible,
.gp-footer-refresh:focus-visible,
.gp-section-title:focus-visible,
.gp-toggle:focus-visible,
.gp-select:focus-visible,
.gp-input:focus-visible,
.gp-search:focus-visible,
.gp-drawer-tab:focus-visible,
.gp-drawer-close:focus-visible,
.gp-textarea-edit:focus-visible {
    outline: 2px solid rgba(74,158,255,0.7);
    outline-offset: 2px;
}

@media (max-width: 1040px) {
    .gp-drawer {
        top: 8px;
        left: 8px;
        right: 8px;
        width: auto;
        min-width: 0;
        max-width: none;
        height: calc(100% - 16px);
        border-left: 1px solid rgba(255,255,255,0.08);
        border-radius: 8px;
        transform: translateY(12px);
    }
    .gp-drawer.gp-drawer-open {
        transform: translateY(0);
    }
    .gp-diff-row {
        flex-direction: column;
    }
}

@media (max-width: 760px) {
    #gp-overlay {
        width: 100vw;
    }
    .gp-header,
    .gp-content,
    .gp-drawer-header,
    .gp-drawer-body {
        padding-left: 12px;
        padding-right: 12px;
    }
    .gp-tab {
        padding: 8px 10px;
    }
    .gp-footer {
        flex-direction: column;
        align-items: flex-start;
    }
    .gp-footer-right {
        width: 100%;
        justify-content: space-between;
    }
    .gp-input-wrap,
    .gp-select-wrap {
        flex-direction: column;
        align-items: stretch;
        gap: 6px;
    }
    .gp-input-label,
    .gp-select-label {
        min-width: 0;
        white-space: normal;
    }
    .gp-btn-row .gp-btn {
        flex: 1 1 136px;
    }
    .gp-log-toolbar {
        flex-direction: column;
        align-items: stretch;
    }
    .gp-log-title-group {
        flex-wrap: wrap;
    }
    .gp-pack-card {
        grid-template-columns: 44px minmax(0, 1fr);
    }
    .gp-pack-ctrl {
        grid-column: 2;
        flex-direction: row;
        flex-wrap: wrap;
    }
}

@media (prefers-reduced-motion: reduce) {
    #gp-overlay,
    .gp-drawer,
    .gp-tab,
    .gp-btn,
    .gp-toggle,
    .gp-toggle-knob,
    .gp-section-arrow,
    .gp-footer-refresh {
        transition: none !important;
        animation: none !important;
    }
}

`;function it(e,t,n={}){const a=document.createElement("button");a.type="button";let r="gp-btn";return n.variant==="danger"?r+=" gp-btn-danger":n.variant==="success"&&(r+=" gp-btn-success"),n.small&&(r+=" gp-btn-sm"),n.className&&(r+=" "+n.className),a.className=r,a.textContent=e,a.addEventListener("click",t),a}function Au(e,t,n){const a=document.createElement("div");a.className="gp-toggle-wrap";const r=document.createElement("span");r.className="gp-toggle-label",r.textContent=e;const u=document.createElement("div");u.className="gp-toggle"+(t?" gp-toggle-on":""),u.tabIndex=0,u.setAttribute("role","switch"),u.setAttribute("aria-checked",t?"true":"false"),u.setAttribute("aria-label",e);const i=document.createElement("div");i.className="gp-toggle-knob",u.appendChild(i);let o=t;const l=()=>{o=!o,u.classList.toggle("gp-toggle-on",o),u.setAttribute("aria-checked",o?"true":"false"),n(o)};return u.addEventListener("click",l),u.addEventListener("keydown",c=>{(c.key===" "||c.key==="Enter")&&(c.preventDefault(),l())}),a.appendChild(r),a.appendChild(u),a._setValue=c=>{o=c,u.classList.toggle("gp-toggle-on",o)},a}function Fu(e,t,n,a,r,u={}){const i=document.createElement("div");i.className="gp-slider-wrap";const o=document.createElement("div");o.className="gp-slider-header";const l=document.createElement("span");l.className="gp-slider-label",l.textContent=e;const c=document.createElement("span");c.className="gp-slider-value";const D=u.formatValue||(f=>String(f));c.textContent=D(a),o.appendChild(l),o.appendChild(c);const s=document.createElement("input");return s.type="range",s.className="gp-slider",s.min=String(t),s.max=String(n),s.value=String(a),u.step&&(s.step=String(u.step)),s.addEventListener("input",()=>{const f=Number(s.value);c.textContent=D(f),r(f)}),i.appendChild(o),i.appendChild(s),i._setValue=f=>{s.value=String(f),c.textContent=D(f)},i}function xu(e,t,n,a={}){const r=document.createElement("div");r.className="gp-input-wrap";const u=document.createElement("span");u.className="gp-input-label",u.textContent=e;const i=document.createElement("input");return i.type="number",i.className="gp-input",i.value=String(t),i.inputMode="decimal",a.min!==void 0&&(i.min=String(a.min)),a.max!==void 0&&(i.max=String(a.max)),a.step!==void 0&&(i.step=String(a.step)),i.addEventListener("change",()=>{n(Number(i.value))}),r.appendChild(u),r.appendChild(i),r._setValue=o=>{i.value=String(o)},r._getInput=()=>i,r}function vu(e,t,n,a){const r=document.createElement("div");r.className="gp-select-wrap";const u=document.createElement("span");u.className="gp-select-label",u.textContent=e;const i=document.createElement("select");i.className="gp-select",i.title=e;for(const o of t){const l=document.createElement("option");l.value=o.value,l.textContent=o.label,o.value===n&&(l.selected=!0),i.appendChild(l)}return i.addEventListener("change",()=>{a(i.value)}),r.appendChild(u),r.appendChild(i),r._setValue=o=>{i.value=o},r}function Su(e,t=[],n=!1){const a=document.createElement("div");a.className="gp-section"+(n?" gp-collapsed":"");const r=document.createElement("button");r.type="button",r.className="gp-section-title",r.setAttribute("aria-expanded",n?"false":"true");const u=document.createElement("span");u.className="gp-section-arrow",u.textContent="▼";const i=document.createElement("span");i.textContent=e,r.appendChild(u),r.appendChild(i),r.addEventListener("click",()=>{a.classList.toggle("gp-collapsed"),r.setAttribute("aria-expanded",a.classList.contains("gp-collapsed")?"false":"true")});const o=document.createElement("div");o.className="gp-section-body";for(const l of t)o.appendChild(l);return a.appendChild(r),a.appendChild(o),a._body=o,a._setTitle=l=>{i.textContent=l},a}function Bu(e,t="info"){const n=document.createElement("span");return n.className=`gp-badge gp-badge-${t}`,n.textContent=e,n}function _u(e,t,n=200){const a=document.createElement("div");a.className="gp-search-wrap";const r=document.createElement("input");r.className="gp-search",r.type="text",r.placeholder=e,r.autocomplete="off",r.spellcheck=!1;let u=null;return r.addEventListener("input",()=>{clearTimeout(u),u=setTimeout(()=>t(r.value.trim()),n)}),a.appendChild(r),a._getInput=()=>r,a._setValue=i=>{r.value=i},a}function Oa(...e){const t=document.createElement("div");t.className="gp-btn-row";for(const n of e)t.appendChild(n);return t}function ku(e){const t=document.createElement("div");return t.className="gp-text-muted",t.textContent=e,t}const fe="1.2.3",Se=ut.AppData,te={ROOT:"gp-next",PACKS_ROOT:"gp-next\\packs",SINGLE_PATCHES:"gp-next\\patches",GPN_EDITS:"gp-next\\__gpn_edits"},vn="gp-next\\settings.json",Fe=[{type:"PlantFeatures",key:"PLANTS",extraKeys:[{key:"SEEDCHOOSERDEFAULTORDER"},{key:"ALMANACHIDDENORDER"},{key:"BASEUNLOCKLIST"},{key:"SANDBOX"}]},{type:"ZombieFeatures",key:"ZOMBIES",extraKeys:[{key:"ALMANAC"}]},{type:"ProjectileFeatures",key:"PROJECTILES"},{type:"TombstonesFeatures",key:"Tombstones"},{type:"UpgradeFeatures",key:"UPGRADES"},{type:"ArmorFeatures",key:"ARMORS"},{type:"DinosaurFeatures",key:"DINOSAURS"},{type:"LawnFeatures",key:"LAWNS"},{type:"TrophyFeatures",key:"TROPHIES"},{type:"TilesFeatures",key:"Tiles"},{type:"TileLiquidsFeatures",key:"Tiles"},{type:"MintObtainRoute",key:"ROUTES",idKey:"Family"},{type:"StoreCommodityFeatures",key:null,extraKeys:[{key:"Plants",idKey:"CommodityName",typeFilter:{field:"CommodityType",value:"plant"}},{key:"Upgrade",idKey:"CommodityName",typeFilter:{field:"CommodityType",value:"upgrade"}},{key:"Gem"},{key:"Coin"},{key:"Zen"}]},{type:"WorldmapFeatures",key:"WORLDMAPS"}],Sn=[{type:"PlantAlmanac"},{type:"PlantProps"},{type:"PlantTypes"},{type:"ZombieAlmanac"},{type:"ZombieProps"},{type:"ZombieTypes"},{type:"BoardGridMaps"},{type:"_GridItemProps",deprecated:!0},{type:"GridItemTypes",deprecated:!0},{type:"ProjectileProps"},{type:"ProjectileTypes"},{type:"TileProps"},{type:"TileLiquidProps"},{type:"TombstoneProps"},{type:"ArmorProps"},{type:"ArmorTypes"},{type:"LawnProps"},{type:"DinosaurTypes"},{type:"DinosaurProps"},{type:"RectangleProps"},{type:"PortalTypes"},{type:"PortalProps"},{type:"PropertySheets"},{type:"NarrativeList"},{type:"LevelModules"}],Pu=[...Fe.map(e=>e.type),...Sn.filter(e=>!e.deprecated).map(e=>e.type)];function Nu(e,t){if(!t)return[];if(e.key){const a=e.idKey||"CODENAME";return(t[e.key]||[]).map(r=>({id:r[a]!==void 0?String(r[a]):"?",label:r[a]!==void 0?String(r[a]):"?",name:r.NAME}))}const n=[];for(const a of e.extraKeys||[])if(!(!a.idKey||!t[a.key]))for(const r of t[a.key])n.push({id:r[a.idKey]!==void 0?String(r[a.idKey]):"?",label:r[a.idKey]!==void 0?String(r[a.idKey]):"?",name:r.NAME});return n}function Bn(e,t,n){if(!t)return null;if(e.key){const a=e.idKey||"CODENAME",r=(t[e.key]||[]).find(u=>String(u[a])===n);return r?{entry:r,section:e.key,idKey:a}:null}for(const a of e.extraKeys||[]){if(!a.idKey||!t[a.key])continue;const r=t[a.key].find(u=>String(u[a.idKey])===n);if(r)return{entry:r,section:a.key,idKey:a.idKey}}return null}var W=Uint8Array,Te=Uint16Array,Ra=Int32Array,_n=new W([0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0,0,0,0]),kn=new W([0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13,0,0]),Ia=new W([16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15]),Pn=function(e,t){for(var n=new Te(31),a=0;a<31;++a)n[a]=t+=1<<e[a-1];for(var r=new Ra(n[30]),a=1;a<30;++a)for(var u=n[a];u<n[a+1];++u)r[u]=u-n[a]<<5|a;return{b:n,r}},Nn=Pn(_n,2),Tn=Nn.b,za=Nn.r;Tn[28]=258,za[258]=28;var Ga=Pn(kn,0),Ma=Ga.b,Tt=new Te(32768);for(var P=0;P<32768;++P){var De=(P&43690)>>1|(P&21845)<<1;De=(De&52428)>>2|(De&13107)<<2,De=(De&61680)>>4|(De&3855)<<4,Tt[P]=((De&65280)>>8|(De&255)<<8)>>1}var ze=(function(e,t,n){for(var a=e.length,r=0,u=new Te(t);r<a;++r)e[r]&&++u[e[r]-1];var i=new Te(t);for(r=1;r<t;++r)i[r]=i[r-1]+u[r-1]<<1;var o;if(n){o=new Te(1<<t);var l=15-t;for(r=0;r<a;++r)if(e[r])for(var c=r<<4|e[r],D=t-e[r],s=i[e[r]-1]++<<D,f=s|(1<<D)-1;s<=f;++s)o[Tt[s]>>l]=c}else for(o=new Te(a),r=0;r<a;++r)e[r]&&(o[r]=Tt[i[e[r]-1]++]>>15-e[r]);return o}),Ue=new W(288);for(var P=0;P<144;++P)Ue[P]=8;for(var P=144;P<256;++P)Ue[P]=9;for(var P=256;P<280;++P)Ue[P]=7;for(var P=280;P<288;++P)Ue[P]=8;var Ln=new W(32);for(var P=0;P<32;++P)Ln[P]=5;var $a=ze(Ue,9,1),ja=ze(Ln,5,1),Et=function(e){for(var t=e[0],n=1;n<e.length;++n)e[n]>t&&(t=e[n]);return t},J=function(e,t,n){var a=t/8|0;return(e[a]|e[a+1]<<8)>>(t&7)&n},At=function(e,t){var n=t/8|0;return(e[n]|e[n+1]<<8|e[n+2]<<16)>>(t&7)},Wa=function(e){return(e+7)/8|0},Wt=function(e,t,n){return(t==null||t<0)&&(t=0),(n==null||n>e.length)&&(n=e.length),new W(e.subarray(t,n))},Ua=["unexpected EOF","invalid block type","invalid length/literal","invalid distance","stream finished","no stream handler",,"no callback","invalid UTF-8 data","extra field too long","date not in range 1980-2099","filename too long","stream finishing","invalid zip data"],H=function(e,t,n){var a=new Error(t||Ua[e]);if(a.code=e,Error.captureStackTrace&&Error.captureStackTrace(a,H),!n)throw a;return a},Ha=function(e,t,n,a){var r=e.length,u=a?a.length:0;if(!r||t.f&&!t.l)return n||new W(0);var i=!n,o=i||t.i!=2,l=t.i;i&&(n=new W(r*3));var c=function(rn){var un=n.length;if(rn>un){var on=new W(Math.max(un*2,rn));on.set(n),n=on}},D=t.f||0,s=t.p||0,f=t.b||0,A=t.l,x=t.d,h=t.m,E=t.n,m=r*8;do{if(!A){D=J(e,s,1);var N=J(e,s+1,3);if(s+=3,N)if(N==1)A=$a,x=ja,h=9,E=5;else if(N==2){var U=J(e,s,31)+257,Ve=J(e,s+10,15)+4,Le=U+J(e,s+5,31)+1;s+=14;for(var g=new W(Le),B=new W(19),I=0;I<Ve;++I)B[Ia[I]]=J(e,s+I*3,7);s+=Ve*3;for(var Yt=Et(B),aa=(1<<Yt)-1,ra=ze(B,Yt,1),I=0;I<Le;){var Qt=ra[J(e,s,aa)];s+=Qt&15;var F=Qt>>4;if(F<16)g[I++]=F;else{var _e=0,Ke=0;for(F==16?(Ke=3+J(e,s,3),s+=2,_e=g[I-1]):F==17?(Ke=3+J(e,s,7),s+=3):F==18&&(Ke=11+J(e,s,127),s+=7);Ke--;)g[I++]=_e}}var en=g.subarray(0,U),pe=g.subarray(U);h=Et(en),E=Et(pe),A=ze(en,h,1),x=ze(pe,E,1)}else H(1);else{var F=Wa(s)+4,S=e[F-4]|e[F-3]<<8,T=F+S;if(T>r){l&&H(0);break}o&&c(f+S),n.set(e.subarray(F,T),f),t.b=f+=S,t.p=s=T*8,t.f=D;continue}if(s>m){l&&H(0);break}}o&&c(f+131072);for(var ua=(1<<h)-1,ia=(1<<E)-1,bt=s;;bt=s){var _e=A[At(e,s)&ua],ke=_e>>4;if(s+=_e&15,s>m){l&&H(0);break}if(_e||H(2),ke<256)n[f++]=ke;else if(ke==256){bt=s,A=null;break}else{var tn=ke-254;if(ke>264){var I=ke-257,Oe=_n[I];tn=J(e,s,(1<<Oe)-1)+Tn[I],s+=Oe}var wt=x[At(e,s)&ia],yt=wt>>4;wt||H(3),s+=wt&15;var pe=Ma[yt];if(yt>3){var Oe=kn[yt];pe+=At(e,s)&(1<<Oe)-1,s+=Oe}if(s>m){l&&H(0);break}o&&c(f+131072);var nn=f+tn;if(f<pe){var an=u-pe,oa=Math.min(pe,nn);for(an+f<0&&H(3);f<oa;++f)n[f]=a[an+f]}for(;f<nn;++f)n[f]=n[f-pe]}}t.l=A,t.p=bt,t.b=f,t.f=D,A&&(D=1,t.m=h,t.d=x,t.n=E)}while(!D);return f!=n.length&&i?Wt(n,0,f):n.subarray(0,f)},Va=new W(0),ae=function(e,t){return e[t]|e[t+1]<<8},q=function(e,t){return(e[t]|e[t+1]<<8|e[t+2]<<16|e[t+3]<<24)>>>0},Ft=function(e,t){return q(e,t)+q(e,t+4)*4294967296};function Ka(e,t){return Ha(e,{i:2},t&&t.out,t&&t.dictionary)}var Lt=typeof TextDecoder<"u"&&new TextDecoder,Ja=0;try{Lt.decode(Va,{stream:!0}),Ja=1}catch{}var Za=function(e){for(var t="",n=0;;){var a=e[n++],r=(a>127)+(a>223)+(a>239);if(n+r>e.length)return{s:t,r:Wt(e,n-1)};r?r==3?(a=((a&15)<<18|(e[n++]&63)<<12|(e[n++]&63)<<6|e[n++]&63)-65536,t+=String.fromCharCode(55296|a>>10,56320|a&1023)):r&1?t+=String.fromCharCode((a&31)<<6|e[n++]&63):t+=String.fromCharCode((a&15)<<12|(e[n++]&63)<<6|e[n++]&63):t+=String.fromCharCode(a)}};function On(e,t){if(t){for(var n="",a=0;a<e.length;a+=16384)n+=String.fromCharCode.apply(null,e.subarray(a,a+16384));return n}else{if(Lt)return Lt.decode(e);var r=Za(e),u=r.s,n=r.r;return n.length&&H(8),u}}var qa=function(e,t){return t+30+ae(e,t+26)+ae(e,t+28)},Xa=function(e,t,n){var a=ae(e,t+28),r=On(e.subarray(t+46,t+46+a),!(ae(e,t+8)&2048)),u=t+46+a,i=q(e,t+20),o=n&&i==4294967295?Ya(e,u):[i,q(e,t+24),q(e,t+42)],l=o[0],c=o[1],D=o[2];return[ae(e,t+10),l,c,r,u+ae(e,t+30)+ae(e,t+32),D]},Ya=function(e,t){for(;ae(e,t)!=1;t+=4+ae(e,t+2));return[Ft(e,t+12),Ft(e,t+4),Ft(e,t+20)]};function Qa(e,t){for(var n={},a=e.length-22;q(e,a)!=101010256;--a)(!a||e.length-a>65558)&&H(13);var r=ae(e,a+8);if(!r)return{};var u=q(e,a+16),i=u==4294967295||r==65535;if(i){var o=q(e,a-12);i=q(e,o)==101075792,i&&(r=q(e,o+32),u=q(e,o+48))}for(var l=0;l<r;++l){var c=Xa(e,u,i),D=c[0],s=c[1],f=c[2],A=c[3],x=c[4],h=c[5],E=qa(e,h);u=x,D?D==8?n[A]=Ka(e.subarray(E,E+s),{out:new W(f)}):H(14,"unknown compression type "+D):n[A]=Wt(e,E,E+s)}return n}var er=/[\u1680\u2000-\u200A\u202F\u205F\u3000]/,tr=/[\xAA\xB5\xBA\xC0-\xD6\xD8-\xF6\xF8-\u02C1\u02C6-\u02D1\u02E0-\u02E4\u02EC\u02EE\u0370-\u0374\u0376\u0377\u037A-\u037D\u037F\u0386\u0388-\u038A\u038C\u038E-\u03A1\u03A3-\u03F5\u03F7-\u0481\u048A-\u052F\u0531-\u0556\u0559\u0561-\u0587\u05D0-\u05EA\u05F0-\u05F2\u0620-\u064A\u066E\u066F\u0671-\u06D3\u06D5\u06E5\u06E6\u06EE\u06EF\u06FA-\u06FC\u06FF\u0710\u0712-\u072F\u074D-\u07A5\u07B1\u07CA-\u07EA\u07F4\u07F5\u07FA\u0800-\u0815\u081A\u0824\u0828\u0840-\u0858\u0860-\u086A\u08A0-\u08B4\u08B6-\u08BD\u0904-\u0939\u093D\u0950\u0958-\u0961\u0971-\u0980\u0985-\u098C\u098F\u0990\u0993-\u09A8\u09AA-\u09B0\u09B2\u09B6-\u09B9\u09BD\u09CE\u09DC\u09DD\u09DF-\u09E1\u09F0\u09F1\u09FC\u0A05-\u0A0A\u0A0F\u0A10\u0A13-\u0A28\u0A2A-\u0A30\u0A32\u0A33\u0A35\u0A36\u0A38\u0A39\u0A59-\u0A5C\u0A5E\u0A72-\u0A74\u0A85-\u0A8D\u0A8F-\u0A91\u0A93-\u0AA8\u0AAA-\u0AB0\u0AB2\u0AB3\u0AB5-\u0AB9\u0ABD\u0AD0\u0AE0\u0AE1\u0AF9\u0B05-\u0B0C\u0B0F\u0B10\u0B13-\u0B28\u0B2A-\u0B30\u0B32\u0B33\u0B35-\u0B39\u0B3D\u0B5C\u0B5D\u0B5F-\u0B61\u0B71\u0B83\u0B85-\u0B8A\u0B8E-\u0B90\u0B92-\u0B95\u0B99\u0B9A\u0B9C\u0B9E\u0B9F\u0BA3\u0BA4\u0BA8-\u0BAA\u0BAE-\u0BB9\u0BD0\u0C05-\u0C0C\u0C0E-\u0C10\u0C12-\u0C28\u0C2A-\u0C39\u0C3D\u0C58-\u0C5A\u0C60\u0C61\u0C80\u0C85-\u0C8C\u0C8E-\u0C90\u0C92-\u0CA8\u0CAA-\u0CB3\u0CB5-\u0CB9\u0CBD\u0CDE\u0CE0\u0CE1\u0CF1\u0CF2\u0D05-\u0D0C\u0D0E-\u0D10\u0D12-\u0D3A\u0D3D\u0D4E\u0D54-\u0D56\u0D5F-\u0D61\u0D7A-\u0D7F\u0D85-\u0D96\u0D9A-\u0DB1\u0DB3-\u0DBB\u0DBD\u0DC0-\u0DC6\u0E01-\u0E30\u0E32\u0E33\u0E40-\u0E46\u0E81\u0E82\u0E84\u0E87\u0E88\u0E8A\u0E8D\u0E94-\u0E97\u0E99-\u0E9F\u0EA1-\u0EA3\u0EA5\u0EA7\u0EAA\u0EAB\u0EAD-\u0EB0\u0EB2\u0EB3\u0EBD\u0EC0-\u0EC4\u0EC6\u0EDC-\u0EDF\u0F00\u0F40-\u0F47\u0F49-\u0F6C\u0F88-\u0F8C\u1000-\u102A\u103F\u1050-\u1055\u105A-\u105D\u1061\u1065\u1066\u106E-\u1070\u1075-\u1081\u108E\u10A0-\u10C5\u10C7\u10CD\u10D0-\u10FA\u10FC-\u1248\u124A-\u124D\u1250-\u1256\u1258\u125A-\u125D\u1260-\u1288\u128A-\u128D\u1290-\u12B0\u12B2-\u12B5\u12B8-\u12BE\u12C0\u12C2-\u12C5\u12C8-\u12D6\u12D8-\u1310\u1312-\u1315\u1318-\u135A\u1380-\u138F\u13A0-\u13F5\u13F8-\u13FD\u1401-\u166C\u166F-\u167F\u1681-\u169A\u16A0-\u16EA\u16EE-\u16F8\u1700-\u170C\u170E-\u1711\u1720-\u1731\u1740-\u1751\u1760-\u176C\u176E-\u1770\u1780-\u17B3\u17D7\u17DC\u1820-\u1877\u1880-\u1884\u1887-\u18A8\u18AA\u18B0-\u18F5\u1900-\u191E\u1950-\u196D\u1970-\u1974\u1980-\u19AB\u19B0-\u19C9\u1A00-\u1A16\u1A20-\u1A54\u1AA7\u1B05-\u1B33\u1B45-\u1B4B\u1B83-\u1BA0\u1BAE\u1BAF\u1BBA-\u1BE5\u1C00-\u1C23\u1C4D-\u1C4F\u1C5A-\u1C7D\u1C80-\u1C88\u1CE9-\u1CEC\u1CEE-\u1CF1\u1CF5\u1CF6\u1D00-\u1DBF\u1E00-\u1F15\u1F18-\u1F1D\u1F20-\u1F45\u1F48-\u1F4D\u1F50-\u1F57\u1F59\u1F5B\u1F5D\u1F5F-\u1F7D\u1F80-\u1FB4\u1FB6-\u1FBC\u1FBE\u1FC2-\u1FC4\u1FC6-\u1FCC\u1FD0-\u1FD3\u1FD6-\u1FDB\u1FE0-\u1FEC\u1FF2-\u1FF4\u1FF6-\u1FFC\u2071\u207F\u2090-\u209C\u2102\u2107\u210A-\u2113\u2115\u2119-\u211D\u2124\u2126\u2128\u212A-\u212D\u212F-\u2139\u213C-\u213F\u2145-\u2149\u214E\u2160-\u2188\u2C00-\u2C2E\u2C30-\u2C5E\u2C60-\u2CE4\u2CEB-\u2CEE\u2CF2\u2CF3\u2D00-\u2D25\u2D27\u2D2D\u2D30-\u2D67\u2D6F\u2D80-\u2D96\u2DA0-\u2DA6\u2DA8-\u2DAE\u2DB0-\u2DB6\u2DB8-\u2DBE\u2DC0-\u2DC6\u2DC8-\u2DCE\u2DD0-\u2DD6\u2DD8-\u2DDE\u2E2F\u3005-\u3007\u3021-\u3029\u3031-\u3035\u3038-\u303C\u3041-\u3096\u309D-\u309F\u30A1-\u30FA\u30FC-\u30FF\u3105-\u312E\u3131-\u318E\u31A0-\u31BA\u31F0-\u31FF\u3400-\u4DB5\u4E00-\u9FEA\uA000-\uA48C\uA4D0-\uA4FD\uA500-\uA60C\uA610-\uA61F\uA62A\uA62B\uA640-\uA66E\uA67F-\uA69D\uA6A0-\uA6EF\uA717-\uA71F\uA722-\uA788\uA78B-\uA7AE\uA7B0-\uA7B7\uA7F7-\uA801\uA803-\uA805\uA807-\uA80A\uA80C-\uA822\uA840-\uA873\uA882-\uA8B3\uA8F2-\uA8F7\uA8FB\uA8FD\uA90A-\uA925\uA930-\uA946\uA960-\uA97C\uA984-\uA9B2\uA9CF\uA9E0-\uA9E4\uA9E6-\uA9EF\uA9FA-\uA9FE\uAA00-\uAA28\uAA40-\uAA42\uAA44-\uAA4B\uAA60-\uAA76\uAA7A\uAA7E-\uAAAF\uAAB1\uAAB5\uAAB6\uAAB9-\uAABD\uAAC0\uAAC2\uAADB-\uAADD\uAAE0-\uAAEA\uAAF2-\uAAF4\uAB01-\uAB06\uAB09-\uAB0E\uAB11-\uAB16\uAB20-\uAB26\uAB28-\uAB2E\uAB30-\uAB5A\uAB5C-\uAB65\uAB70-\uABE2\uAC00-\uD7A3\uD7B0-\uD7C6\uD7CB-\uD7FB\uF900-\uFA6D\uFA70-\uFAD9\uFB00-\uFB06\uFB13-\uFB17\uFB1D\uFB1F-\uFB28\uFB2A-\uFB36\uFB38-\uFB3C\uFB3E\uFB40\uFB41\uFB43\uFB44\uFB46-\uFBB1\uFBD3-\uFD3D\uFD50-\uFD8F\uFD92-\uFDC7\uFDF0-\uFDFB\uFE70-\uFE74\uFE76-\uFEFC\uFF21-\uFF3A\uFF41-\uFF5A\uFF66-\uFFBE\uFFC2-\uFFC7\uFFCA-\uFFCF\uFFD2-\uFFD7\uFFDA-\uFFDC]|\uD800[\uDC00-\uDC0B\uDC0D-\uDC26\uDC28-\uDC3A\uDC3C\uDC3D\uDC3F-\uDC4D\uDC50-\uDC5D\uDC80-\uDCFA\uDD40-\uDD74\uDE80-\uDE9C\uDEA0-\uDED0\uDF00-\uDF1F\uDF2D-\uDF4A\uDF50-\uDF75\uDF80-\uDF9D\uDFA0-\uDFC3\uDFC8-\uDFCF\uDFD1-\uDFD5]|\uD801[\uDC00-\uDC9D\uDCB0-\uDCD3\uDCD8-\uDCFB\uDD00-\uDD27\uDD30-\uDD63\uDE00-\uDF36\uDF40-\uDF55\uDF60-\uDF67]|\uD802[\uDC00-\uDC05\uDC08\uDC0A-\uDC35\uDC37\uDC38\uDC3C\uDC3F-\uDC55\uDC60-\uDC76\uDC80-\uDC9E\uDCE0-\uDCF2\uDCF4\uDCF5\uDD00-\uDD15\uDD20-\uDD39\uDD80-\uDDB7\uDDBE\uDDBF\uDE00\uDE10-\uDE13\uDE15-\uDE17\uDE19-\uDE33\uDE60-\uDE7C\uDE80-\uDE9C\uDEC0-\uDEC7\uDEC9-\uDEE4\uDF00-\uDF35\uDF40-\uDF55\uDF60-\uDF72\uDF80-\uDF91]|\uD803[\uDC00-\uDC48\uDC80-\uDCB2\uDCC0-\uDCF2]|\uD804[\uDC03-\uDC37\uDC83-\uDCAF\uDCD0-\uDCE8\uDD03-\uDD26\uDD50-\uDD72\uDD76\uDD83-\uDDB2\uDDC1-\uDDC4\uDDDA\uDDDC\uDE00-\uDE11\uDE13-\uDE2B\uDE80-\uDE86\uDE88\uDE8A-\uDE8D\uDE8F-\uDE9D\uDE9F-\uDEA8\uDEB0-\uDEDE\uDF05-\uDF0C\uDF0F\uDF10\uDF13-\uDF28\uDF2A-\uDF30\uDF32\uDF33\uDF35-\uDF39\uDF3D\uDF50\uDF5D-\uDF61]|\uD805[\uDC00-\uDC34\uDC47-\uDC4A\uDC80-\uDCAF\uDCC4\uDCC5\uDCC7\uDD80-\uDDAE\uDDD8-\uDDDB\uDE00-\uDE2F\uDE44\uDE80-\uDEAA\uDF00-\uDF19]|\uD806[\uDCA0-\uDCDF\uDCFF\uDE00\uDE0B-\uDE32\uDE3A\uDE50\uDE5C-\uDE83\uDE86-\uDE89\uDEC0-\uDEF8]|\uD807[\uDC00-\uDC08\uDC0A-\uDC2E\uDC40\uDC72-\uDC8F\uDD00-\uDD06\uDD08\uDD09\uDD0B-\uDD30\uDD46]|\uD808[\uDC00-\uDF99]|\uD809[\uDC00-\uDC6E\uDC80-\uDD43]|[\uD80C\uD81C-\uD820\uD840-\uD868\uD86A-\uD86C\uD86F-\uD872\uD874-\uD879][\uDC00-\uDFFF]|\uD80D[\uDC00-\uDC2E]|\uD811[\uDC00-\uDE46]|\uD81A[\uDC00-\uDE38\uDE40-\uDE5E\uDED0-\uDEED\uDF00-\uDF2F\uDF40-\uDF43\uDF63-\uDF77\uDF7D-\uDF8F]|\uD81B[\uDF00-\uDF44\uDF50\uDF93-\uDF9F\uDFE0\uDFE1]|\uD821[\uDC00-\uDFEC]|\uD822[\uDC00-\uDEF2]|\uD82C[\uDC00-\uDD1E\uDD70-\uDEFB]|\uD82F[\uDC00-\uDC6A\uDC70-\uDC7C\uDC80-\uDC88\uDC90-\uDC99]|\uD835[\uDC00-\uDC54\uDC56-\uDC9C\uDC9E\uDC9F\uDCA2\uDCA5\uDCA6\uDCA9-\uDCAC\uDCAE-\uDCB9\uDCBB\uDCBD-\uDCC3\uDCC5-\uDD05\uDD07-\uDD0A\uDD0D-\uDD14\uDD16-\uDD1C\uDD1E-\uDD39\uDD3B-\uDD3E\uDD40-\uDD44\uDD46\uDD4A-\uDD50\uDD52-\uDEA5\uDEA8-\uDEC0\uDEC2-\uDEDA\uDEDC-\uDEFA\uDEFC-\uDF14\uDF16-\uDF34\uDF36-\uDF4E\uDF50-\uDF6E\uDF70-\uDF88\uDF8A-\uDFA8\uDFAA-\uDFC2\uDFC4-\uDFCB]|\uD83A[\uDC00-\uDCC4\uDD00-\uDD43]|\uD83B[\uDE00-\uDE03\uDE05-\uDE1F\uDE21\uDE22\uDE24\uDE27\uDE29-\uDE32\uDE34-\uDE37\uDE39\uDE3B\uDE42\uDE47\uDE49\uDE4B\uDE4D-\uDE4F\uDE51\uDE52\uDE54\uDE57\uDE59\uDE5B\uDE5D\uDE5F\uDE61\uDE62\uDE64\uDE67-\uDE6A\uDE6C-\uDE72\uDE74-\uDE77\uDE79-\uDE7C\uDE7E\uDE80-\uDE89\uDE8B-\uDE9B\uDEA1-\uDEA3\uDEA5-\uDEA9\uDEAB-\uDEBB]|\uD869[\uDC00-\uDED6\uDF00-\uDFFF]|\uD86D[\uDC00-\uDF34\uDF40-\uDFFF]|\uD86E[\uDC00-\uDC1D\uDC20-\uDFFF]|\uD873[\uDC00-\uDEA1\uDEB0-\uDFFF]|\uD87A[\uDC00-\uDFE0]|\uD87E[\uDC00-\uDE1D]/,nr=/[\xAA\xB5\xBA\xC0-\xD6\xD8-\xF6\xF8-\u02C1\u02C6-\u02D1\u02E0-\u02E4\u02EC\u02EE\u0300-\u0374\u0376\u0377\u037A-\u037D\u037F\u0386\u0388-\u038A\u038C\u038E-\u03A1\u03A3-\u03F5\u03F7-\u0481\u0483-\u0487\u048A-\u052F\u0531-\u0556\u0559\u0561-\u0587\u0591-\u05BD\u05BF\u05C1\u05C2\u05C4\u05C5\u05C7\u05D0-\u05EA\u05F0-\u05F2\u0610-\u061A\u0620-\u0669\u066E-\u06D3\u06D5-\u06DC\u06DF-\u06E8\u06EA-\u06FC\u06FF\u0710-\u074A\u074D-\u07B1\u07C0-\u07F5\u07FA\u0800-\u082D\u0840-\u085B\u0860-\u086A\u08A0-\u08B4\u08B6-\u08BD\u08D4-\u08E1\u08E3-\u0963\u0966-\u096F\u0971-\u0983\u0985-\u098C\u098F\u0990\u0993-\u09A8\u09AA-\u09B0\u09B2\u09B6-\u09B9\u09BC-\u09C4\u09C7\u09C8\u09CB-\u09CE\u09D7\u09DC\u09DD\u09DF-\u09E3\u09E6-\u09F1\u09FC\u0A01-\u0A03\u0A05-\u0A0A\u0A0F\u0A10\u0A13-\u0A28\u0A2A-\u0A30\u0A32\u0A33\u0A35\u0A36\u0A38\u0A39\u0A3C\u0A3E-\u0A42\u0A47\u0A48\u0A4B-\u0A4D\u0A51\u0A59-\u0A5C\u0A5E\u0A66-\u0A75\u0A81-\u0A83\u0A85-\u0A8D\u0A8F-\u0A91\u0A93-\u0AA8\u0AAA-\u0AB0\u0AB2\u0AB3\u0AB5-\u0AB9\u0ABC-\u0AC5\u0AC7-\u0AC9\u0ACB-\u0ACD\u0AD0\u0AE0-\u0AE3\u0AE6-\u0AEF\u0AF9-\u0AFF\u0B01-\u0B03\u0B05-\u0B0C\u0B0F\u0B10\u0B13-\u0B28\u0B2A-\u0B30\u0B32\u0B33\u0B35-\u0B39\u0B3C-\u0B44\u0B47\u0B48\u0B4B-\u0B4D\u0B56\u0B57\u0B5C\u0B5D\u0B5F-\u0B63\u0B66-\u0B6F\u0B71\u0B82\u0B83\u0B85-\u0B8A\u0B8E-\u0B90\u0B92-\u0B95\u0B99\u0B9A\u0B9C\u0B9E\u0B9F\u0BA3\u0BA4\u0BA8-\u0BAA\u0BAE-\u0BB9\u0BBE-\u0BC2\u0BC6-\u0BC8\u0BCA-\u0BCD\u0BD0\u0BD7\u0BE6-\u0BEF\u0C00-\u0C03\u0C05-\u0C0C\u0C0E-\u0C10\u0C12-\u0C28\u0C2A-\u0C39\u0C3D-\u0C44\u0C46-\u0C48\u0C4A-\u0C4D\u0C55\u0C56\u0C58-\u0C5A\u0C60-\u0C63\u0C66-\u0C6F\u0C80-\u0C83\u0C85-\u0C8C\u0C8E-\u0C90\u0C92-\u0CA8\u0CAA-\u0CB3\u0CB5-\u0CB9\u0CBC-\u0CC4\u0CC6-\u0CC8\u0CCA-\u0CCD\u0CD5\u0CD6\u0CDE\u0CE0-\u0CE3\u0CE6-\u0CEF\u0CF1\u0CF2\u0D00-\u0D03\u0D05-\u0D0C\u0D0E-\u0D10\u0D12-\u0D44\u0D46-\u0D48\u0D4A-\u0D4E\u0D54-\u0D57\u0D5F-\u0D63\u0D66-\u0D6F\u0D7A-\u0D7F\u0D82\u0D83\u0D85-\u0D96\u0D9A-\u0DB1\u0DB3-\u0DBB\u0DBD\u0DC0-\u0DC6\u0DCA\u0DCF-\u0DD4\u0DD6\u0DD8-\u0DDF\u0DE6-\u0DEF\u0DF2\u0DF3\u0E01-\u0E3A\u0E40-\u0E4E\u0E50-\u0E59\u0E81\u0E82\u0E84\u0E87\u0E88\u0E8A\u0E8D\u0E94-\u0E97\u0E99-\u0E9F\u0EA1-\u0EA3\u0EA5\u0EA7\u0EAA\u0EAB\u0EAD-\u0EB9\u0EBB-\u0EBD\u0EC0-\u0EC4\u0EC6\u0EC8-\u0ECD\u0ED0-\u0ED9\u0EDC-\u0EDF\u0F00\u0F18\u0F19\u0F20-\u0F29\u0F35\u0F37\u0F39\u0F3E-\u0F47\u0F49-\u0F6C\u0F71-\u0F84\u0F86-\u0F97\u0F99-\u0FBC\u0FC6\u1000-\u1049\u1050-\u109D\u10A0-\u10C5\u10C7\u10CD\u10D0-\u10FA\u10FC-\u1248\u124A-\u124D\u1250-\u1256\u1258\u125A-\u125D\u1260-\u1288\u128A-\u128D\u1290-\u12B0\u12B2-\u12B5\u12B8-\u12BE\u12C0\u12C2-\u12C5\u12C8-\u12D6\u12D8-\u1310\u1312-\u1315\u1318-\u135A\u135D-\u135F\u1380-\u138F\u13A0-\u13F5\u13F8-\u13FD\u1401-\u166C\u166F-\u167F\u1681-\u169A\u16A0-\u16EA\u16EE-\u16F8\u1700-\u170C\u170E-\u1714\u1720-\u1734\u1740-\u1753\u1760-\u176C\u176E-\u1770\u1772\u1773\u1780-\u17D3\u17D7\u17DC\u17DD\u17E0-\u17E9\u180B-\u180D\u1810-\u1819\u1820-\u1877\u1880-\u18AA\u18B0-\u18F5\u1900-\u191E\u1920-\u192B\u1930-\u193B\u1946-\u196D\u1970-\u1974\u1980-\u19AB\u19B0-\u19C9\u19D0-\u19D9\u1A00-\u1A1B\u1A20-\u1A5E\u1A60-\u1A7C\u1A7F-\u1A89\u1A90-\u1A99\u1AA7\u1AB0-\u1ABD\u1B00-\u1B4B\u1B50-\u1B59\u1B6B-\u1B73\u1B80-\u1BF3\u1C00-\u1C37\u1C40-\u1C49\u1C4D-\u1C7D\u1C80-\u1C88\u1CD0-\u1CD2\u1CD4-\u1CF9\u1D00-\u1DF9\u1DFB-\u1F15\u1F18-\u1F1D\u1F20-\u1F45\u1F48-\u1F4D\u1F50-\u1F57\u1F59\u1F5B\u1F5D\u1F5F-\u1F7D\u1F80-\u1FB4\u1FB6-\u1FBC\u1FBE\u1FC2-\u1FC4\u1FC6-\u1FCC\u1FD0-\u1FD3\u1FD6-\u1FDB\u1FE0-\u1FEC\u1FF2-\u1FF4\u1FF6-\u1FFC\u203F\u2040\u2054\u2071\u207F\u2090-\u209C\u20D0-\u20DC\u20E1\u20E5-\u20F0\u2102\u2107\u210A-\u2113\u2115\u2119-\u211D\u2124\u2126\u2128\u212A-\u212D\u212F-\u2139\u213C-\u213F\u2145-\u2149\u214E\u2160-\u2188\u2C00-\u2C2E\u2C30-\u2C5E\u2C60-\u2CE4\u2CEB-\u2CF3\u2D00-\u2D25\u2D27\u2D2D\u2D30-\u2D67\u2D6F\u2D7F-\u2D96\u2DA0-\u2DA6\u2DA8-\u2DAE\u2DB0-\u2DB6\u2DB8-\u2DBE\u2DC0-\u2DC6\u2DC8-\u2DCE\u2DD0-\u2DD6\u2DD8-\u2DDE\u2DE0-\u2DFF\u2E2F\u3005-\u3007\u3021-\u302F\u3031-\u3035\u3038-\u303C\u3041-\u3096\u3099\u309A\u309D-\u309F\u30A1-\u30FA\u30FC-\u30FF\u3105-\u312E\u3131-\u318E\u31A0-\u31BA\u31F0-\u31FF\u3400-\u4DB5\u4E00-\u9FEA\uA000-\uA48C\uA4D0-\uA4FD\uA500-\uA60C\uA610-\uA62B\uA640-\uA66F\uA674-\uA67D\uA67F-\uA6F1\uA717-\uA71F\uA722-\uA788\uA78B-\uA7AE\uA7B0-\uA7B7\uA7F7-\uA827\uA840-\uA873\uA880-\uA8C5\uA8D0-\uA8D9\uA8E0-\uA8F7\uA8FB\uA8FD\uA900-\uA92D\uA930-\uA953\uA960-\uA97C\uA980-\uA9C0\uA9CF-\uA9D9\uA9E0-\uA9FE\uAA00-\uAA36\uAA40-\uAA4D\uAA50-\uAA59\uAA60-\uAA76\uAA7A-\uAAC2\uAADB-\uAADD\uAAE0-\uAAEF\uAAF2-\uAAF6\uAB01-\uAB06\uAB09-\uAB0E\uAB11-\uAB16\uAB20-\uAB26\uAB28-\uAB2E\uAB30-\uAB5A\uAB5C-\uAB65\uAB70-\uABEA\uABEC\uABED\uABF0-\uABF9\uAC00-\uD7A3\uD7B0-\uD7C6\uD7CB-\uD7FB\uF900-\uFA6D\uFA70-\uFAD9\uFB00-\uFB06\uFB13-\uFB17\uFB1D-\uFB28\uFB2A-\uFB36\uFB38-\uFB3C\uFB3E\uFB40\uFB41\uFB43\uFB44\uFB46-\uFBB1\uFBD3-\uFD3D\uFD50-\uFD8F\uFD92-\uFDC7\uFDF0-\uFDFB\uFE00-\uFE0F\uFE20-\uFE2F\uFE33\uFE34\uFE4D-\uFE4F\uFE70-\uFE74\uFE76-\uFEFC\uFF10-\uFF19\uFF21-\uFF3A\uFF3F\uFF41-\uFF5A\uFF66-\uFFBE\uFFC2-\uFFC7\uFFCA-\uFFCF\uFFD2-\uFFD7\uFFDA-\uFFDC]|\uD800[\uDC00-\uDC0B\uDC0D-\uDC26\uDC28-\uDC3A\uDC3C\uDC3D\uDC3F-\uDC4D\uDC50-\uDC5D\uDC80-\uDCFA\uDD40-\uDD74\uDDFD\uDE80-\uDE9C\uDEA0-\uDED0\uDEE0\uDF00-\uDF1F\uDF2D-\uDF4A\uDF50-\uDF7A\uDF80-\uDF9D\uDFA0-\uDFC3\uDFC8-\uDFCF\uDFD1-\uDFD5]|\uD801[\uDC00-\uDC9D\uDCA0-\uDCA9\uDCB0-\uDCD3\uDCD8-\uDCFB\uDD00-\uDD27\uDD30-\uDD63\uDE00-\uDF36\uDF40-\uDF55\uDF60-\uDF67]|\uD802[\uDC00-\uDC05\uDC08\uDC0A-\uDC35\uDC37\uDC38\uDC3C\uDC3F-\uDC55\uDC60-\uDC76\uDC80-\uDC9E\uDCE0-\uDCF2\uDCF4\uDCF5\uDD00-\uDD15\uDD20-\uDD39\uDD80-\uDDB7\uDDBE\uDDBF\uDE00-\uDE03\uDE05\uDE06\uDE0C-\uDE13\uDE15-\uDE17\uDE19-\uDE33\uDE38-\uDE3A\uDE3F\uDE60-\uDE7C\uDE80-\uDE9C\uDEC0-\uDEC7\uDEC9-\uDEE6\uDF00-\uDF35\uDF40-\uDF55\uDF60-\uDF72\uDF80-\uDF91]|\uD803[\uDC00-\uDC48\uDC80-\uDCB2\uDCC0-\uDCF2]|\uD804[\uDC00-\uDC46\uDC66-\uDC6F\uDC7F-\uDCBA\uDCD0-\uDCE8\uDCF0-\uDCF9\uDD00-\uDD34\uDD36-\uDD3F\uDD50-\uDD73\uDD76\uDD80-\uDDC4\uDDCA-\uDDCC\uDDD0-\uDDDA\uDDDC\uDE00-\uDE11\uDE13-\uDE37\uDE3E\uDE80-\uDE86\uDE88\uDE8A-\uDE8D\uDE8F-\uDE9D\uDE9F-\uDEA8\uDEB0-\uDEEA\uDEF0-\uDEF9\uDF00-\uDF03\uDF05-\uDF0C\uDF0F\uDF10\uDF13-\uDF28\uDF2A-\uDF30\uDF32\uDF33\uDF35-\uDF39\uDF3C-\uDF44\uDF47\uDF48\uDF4B-\uDF4D\uDF50\uDF57\uDF5D-\uDF63\uDF66-\uDF6C\uDF70-\uDF74]|\uD805[\uDC00-\uDC4A\uDC50-\uDC59\uDC80-\uDCC5\uDCC7\uDCD0-\uDCD9\uDD80-\uDDB5\uDDB8-\uDDC0\uDDD8-\uDDDD\uDE00-\uDE40\uDE44\uDE50-\uDE59\uDE80-\uDEB7\uDEC0-\uDEC9\uDF00-\uDF19\uDF1D-\uDF2B\uDF30-\uDF39]|\uD806[\uDCA0-\uDCE9\uDCFF\uDE00-\uDE3E\uDE47\uDE50-\uDE83\uDE86-\uDE99\uDEC0-\uDEF8]|\uD807[\uDC00-\uDC08\uDC0A-\uDC36\uDC38-\uDC40\uDC50-\uDC59\uDC72-\uDC8F\uDC92-\uDCA7\uDCA9-\uDCB6\uDD00-\uDD06\uDD08\uDD09\uDD0B-\uDD36\uDD3A\uDD3C\uDD3D\uDD3F-\uDD47\uDD50-\uDD59]|\uD808[\uDC00-\uDF99]|\uD809[\uDC00-\uDC6E\uDC80-\uDD43]|[\uD80C\uD81C-\uD820\uD840-\uD868\uD86A-\uD86C\uD86F-\uD872\uD874-\uD879][\uDC00-\uDFFF]|\uD80D[\uDC00-\uDC2E]|\uD811[\uDC00-\uDE46]|\uD81A[\uDC00-\uDE38\uDE40-\uDE5E\uDE60-\uDE69\uDED0-\uDEED\uDEF0-\uDEF4\uDF00-\uDF36\uDF40-\uDF43\uDF50-\uDF59\uDF63-\uDF77\uDF7D-\uDF8F]|\uD81B[\uDF00-\uDF44\uDF50-\uDF7E\uDF8F-\uDF9F\uDFE0\uDFE1]|\uD821[\uDC00-\uDFEC]|\uD822[\uDC00-\uDEF2]|\uD82C[\uDC00-\uDD1E\uDD70-\uDEFB]|\uD82F[\uDC00-\uDC6A\uDC70-\uDC7C\uDC80-\uDC88\uDC90-\uDC99\uDC9D\uDC9E]|\uD834[\uDD65-\uDD69\uDD6D-\uDD72\uDD7B-\uDD82\uDD85-\uDD8B\uDDAA-\uDDAD\uDE42-\uDE44]|\uD835[\uDC00-\uDC54\uDC56-\uDC9C\uDC9E\uDC9F\uDCA2\uDCA5\uDCA6\uDCA9-\uDCAC\uDCAE-\uDCB9\uDCBB\uDCBD-\uDCC3\uDCC5-\uDD05\uDD07-\uDD0A\uDD0D-\uDD14\uDD16-\uDD1C\uDD1E-\uDD39\uDD3B-\uDD3E\uDD40-\uDD44\uDD46\uDD4A-\uDD50\uDD52-\uDEA5\uDEA8-\uDEC0\uDEC2-\uDEDA\uDEDC-\uDEFA\uDEFC-\uDF14\uDF16-\uDF34\uDF36-\uDF4E\uDF50-\uDF6E\uDF70-\uDF88\uDF8A-\uDFA8\uDFAA-\uDFC2\uDFC4-\uDFCB\uDFCE-\uDFFF]|\uD836[\uDE00-\uDE36\uDE3B-\uDE6C\uDE75\uDE84\uDE9B-\uDE9F\uDEA1-\uDEAF]|\uD838[\uDC00-\uDC06\uDC08-\uDC18\uDC1B-\uDC21\uDC23\uDC24\uDC26-\uDC2A]|\uD83A[\uDC00-\uDCC4\uDCD0-\uDCD6\uDD00-\uDD4A\uDD50-\uDD59]|\uD83B[\uDE00-\uDE03\uDE05-\uDE1F\uDE21\uDE22\uDE24\uDE27\uDE29-\uDE32\uDE34-\uDE37\uDE39\uDE3B\uDE42\uDE47\uDE49\uDE4B\uDE4D-\uDE4F\uDE51\uDE52\uDE54\uDE57\uDE59\uDE5B\uDE5D\uDE5F\uDE61\uDE62\uDE64\uDE67-\uDE6A\uDE6C-\uDE72\uDE74-\uDE77\uDE79-\uDE7C\uDE7E\uDE80-\uDE89\uDE8B-\uDE9B\uDEA1-\uDEA3\uDEA5-\uDEA9\uDEAB-\uDEBB]|\uD869[\uDC00-\uDED6\uDF00-\uDFFF]|\uD86D[\uDC00-\uDF34\uDF40-\uDFFF]|\uD86E[\uDC00-\uDC1D\uDC20-\uDFFF]|\uD873[\uDC00-\uDEA1\uDEB0-\uDFFF]|\uD87A[\uDC00-\uDFE0]|\uD87E[\uDC00-\uDE1D]|\uDB40[\uDD00-\uDDEF]/,xt={Space_Separator:er,ID_Start:tr,ID_Continue:nr},O={isSpaceSeparator(e){return typeof e=="string"&&xt.Space_Separator.test(e)},isIdStartChar(e){return typeof e=="string"&&(e>="a"&&e<="z"||e>="A"&&e<="Z"||e==="$"||e==="_"||xt.ID_Start.test(e))},isIdContinueChar(e){return typeof e=="string"&&(e>="a"&&e<="z"||e>="A"&&e<="Z"||e>="0"&&e<="9"||e==="$"||e==="_"||e==="‌"||e==="‍"||xt.ID_Continue.test(e))},isDigit(e){return typeof e=="string"&&/[0-9]/.test(e)},isHexDigit(e){return typeof e=="string"&&/[0-9A-Fa-f]/.test(e)}};let Ot,$,se,ot,he,X,R,Ut,Ge;var ar=function(t,n){Ot=String(t),$="start",se=[],ot=0,he=1,X=0,R=void 0,Ut=void 0,Ge=void 0;do R=rr(),or[$]();while(R.type!=="eof");return typeof n=="function"?Rt({"":Ge},"",n):Ge};function Rt(e,t,n){const a=e[t];if(a!=null&&typeof a=="object")if(Array.isArray(a))for(let r=0;r<a.length;r++){const u=String(r),i=Rt(a,u,n);i===void 0?delete a[u]:Object.defineProperty(a,u,{value:i,writable:!0,enumerable:!0,configurable:!0})}else for(const r in a){const u=Rt(a,r,n);u===void 0?delete a[r]:Object.defineProperty(a,r,{value:u,writable:!0,enumerable:!0,configurable:!0})}return n.call(e,t,a)}let b,C,Re,ie,y;function rr(){for(b="default",C="",Re=!1,ie=1;;){y=ce();const e=Rn[b]();if(e)return e}}function ce(){if(Ot[ot])return String.fromCodePoint(Ot.codePointAt(ot))}function d(){const e=ce();return e===`
`?(he++,X=0):e?X+=e.length:X++,e&&(ot+=e.length),e}const Rn={default(){switch(y){case"	":case"\v":case"\f":case" ":case" ":case"\uFEFF":case`
`:case"\r":case"\u2028":case"\u2029":d();return;case"/":d(),b="comment";return;case void 0:return d(),_("eof")}if(O.isSpaceSeparator(y)){d();return}return Rn[$]()},comment(){switch(y){case"*":d(),b="multiLineComment";return;case"/":d(),b="singleLineComment";return}throw k(d())},multiLineComment(){switch(y){case"*":d(),b="multiLineCommentAsterisk";return;case void 0:throw k(d())}d()},multiLineCommentAsterisk(){switch(y){case"*":d();return;case"/":d(),b="default";return;case void 0:throw k(d())}d(),b="multiLineComment"},singleLineComment(){switch(y){case`
`:case"\r":case"\u2028":case"\u2029":d(),b="default";return;case void 0:return d(),_("eof")}d()},value(){switch(y){case"{":case"[":return _("punctuator",d());case"n":return d(),me("ull"),_("null",null);case"t":return d(),me("rue"),_("boolean",!0);case"f":return d(),me("alse"),_("boolean",!1);case"-":case"+":d()==="-"&&(ie=-1),b="sign";return;case".":C=d(),b="decimalPointLeading";return;case"0":C=d(),b="zero";return;case"1":case"2":case"3":case"4":case"5":case"6":case"7":case"8":case"9":C=d(),b="decimalInteger";return;case"I":return d(),me("nfinity"),_("numeric",1/0);case"N":return d(),me("aN"),_("numeric",NaN);case'"':case"'":Re=d()==='"',C="",b="string";return}throw k(d())},identifierNameStartEscape(){if(y!=="u")throw k(d());d();const e=It();switch(e){case"$":case"_":break;default:if(!O.isIdStartChar(e))throw dn();break}C+=e,b="identifierName"},identifierName(){switch(y){case"$":case"_":case"‌":case"‍":C+=d();return;case"\\":d(),b="identifierNameEscape";return}if(O.isIdContinueChar(y)){C+=d();return}return _("identifier",C)},identifierNameEscape(){if(y!=="u")throw k(d());d();const e=It();switch(e){case"$":case"_":case"‌":case"‍":break;default:if(!O.isIdContinueChar(e))throw dn();break}C+=e,b="identifierName"},sign(){switch(y){case".":C=d(),b="decimalPointLeading";return;case"0":C=d(),b="zero";return;case"1":case"2":case"3":case"4":case"5":case"6":case"7":case"8":case"9":C=d(),b="decimalInteger";return;case"I":return d(),me("nfinity"),_("numeric",ie*(1/0));case"N":return d(),me("aN"),_("numeric",NaN)}throw k(d())},zero(){switch(y){case".":C+=d(),b="decimalPoint";return;case"e":case"E":C+=d(),b="decimalExponent";return;case"x":case"X":C+=d(),b="hexadecimal";return}return _("numeric",ie*0)},decimalInteger(){switch(y){case".":C+=d(),b="decimalPoint";return;case"e":case"E":C+=d(),b="decimalExponent";return}if(O.isDigit(y)){C+=d();return}return _("numeric",ie*Number(C))},decimalPointLeading(){if(O.isDigit(y)){C+=d(),b="decimalFraction";return}throw k(d())},decimalPoint(){switch(y){case"e":case"E":C+=d(),b="decimalExponent";return}if(O.isDigit(y)){C+=d(),b="decimalFraction";return}return _("numeric",ie*Number(C))},decimalFraction(){switch(y){case"e":case"E":C+=d(),b="decimalExponent";return}if(O.isDigit(y)){C+=d();return}return _("numeric",ie*Number(C))},decimalExponent(){switch(y){case"+":case"-":C+=d(),b="decimalExponentSign";return}if(O.isDigit(y)){C+=d(),b="decimalExponentInteger";return}throw k(d())},decimalExponentSign(){if(O.isDigit(y)){C+=d(),b="decimalExponentInteger";return}throw k(d())},decimalExponentInteger(){if(O.isDigit(y)){C+=d();return}return _("numeric",ie*Number(C))},hexadecimal(){if(O.isHexDigit(y)){C+=d(),b="hexadecimalInteger";return}throw k(d())},hexadecimalInteger(){if(O.isHexDigit(y)){C+=d();return}return _("numeric",ie*Number(C))},string(){switch(y){case"\\":d(),C+=ur();return;case'"':if(Re)return d(),_("string",C);C+=d();return;case"'":if(!Re)return d(),_("string",C);C+=d();return;case`
`:case"\r":throw k(d());case"\u2028":case"\u2029":sr(y);break;case void 0:throw k(d())}C+=d()},start(){switch(y){case"{":case"[":return _("punctuator",d())}b="value"},beforePropertyName(){switch(y){case"$":case"_":C=d(),b="identifierName";return;case"\\":d(),b="identifierNameStartEscape";return;case"}":return _("punctuator",d());case'"':case"'":Re=d()==='"',b="string";return}if(O.isIdStartChar(y)){C+=d(),b="identifierName";return}throw k(d())},afterPropertyName(){if(y===":")return _("punctuator",d());throw k(d())},beforePropertyValue(){b="value"},afterPropertyValue(){switch(y){case",":case"}":return _("punctuator",d())}throw k(d())},beforeArrayValue(){if(y==="]")return _("punctuator",d());b="value"},afterArrayValue(){switch(y){case",":case"]":return _("punctuator",d())}throw k(d())},end(){throw k(d())}};function _(e,t){return{type:e,value:t,line:he,column:X}}function me(e){for(const t of e){if(ce()!==t)throw k(d());d()}}function ur(){switch(ce()){case"b":return d(),"\b";case"f":return d(),"\f";case"n":return d(),`
`;case"r":return d(),"\r";case"t":return d(),"	";case"v":return d(),"\v";case"0":if(d(),O.isDigit(ce()))throw k(d());return"\0";case"x":return d(),ir();case"u":return d(),It();case`
`:case"\u2028":case"\u2029":return d(),"";case"\r":return d(),ce()===`
`&&d(),"";case"1":case"2":case"3":case"4":case"5":case"6":case"7":case"8":case"9":throw k(d());case void 0:throw k(d())}return d()}function ir(){let e="",t=ce();if(!O.isHexDigit(t)||(e+=d(),t=ce(),!O.isHexDigit(t)))throw k(d());return e+=d(),String.fromCodePoint(parseInt(e,16))}function It(){let e="",t=4;for(;t-- >0;){const n=ce();if(!O.isHexDigit(n))throw k(d());e+=d()}return String.fromCodePoint(parseInt(e,16))}const or={start(){if(R.type==="eof")throw Ce();vt()},beforePropertyName(){switch(R.type){case"identifier":case"string":Ut=R.value,$="afterPropertyName";return;case"punctuator":Ze();return;case"eof":throw Ce()}},afterPropertyName(){if(R.type==="eof")throw Ce();$="beforePropertyValue"},beforePropertyValue(){if(R.type==="eof")throw Ce();vt()},beforeArrayValue(){if(R.type==="eof")throw Ce();if(R.type==="punctuator"&&R.value==="]"){Ze();return}vt()},afterPropertyValue(){if(R.type==="eof")throw Ce();switch(R.value){case",":$="beforePropertyName";return;case"}":Ze()}},afterArrayValue(){if(R.type==="eof")throw Ce();switch(R.value){case",":$="beforeArrayValue";return;case"]":Ze()}},end(){}};function vt(){let e;switch(R.type){case"punctuator":switch(R.value){case"{":e={};break;case"[":e=[];break}break;case"null":case"boolean":case"numeric":case"string":e=R.value;break}if(Ge===void 0)Ge=e;else{const t=se[se.length-1];Array.isArray(t)?t.push(e):Object.defineProperty(t,Ut,{value:e,writable:!0,enumerable:!0,configurable:!0})}if(e!==null&&typeof e=="object")se.push(e),Array.isArray(e)?$="beforeArrayValue":$="beforePropertyName";else{const t=se[se.length-1];t==null?$="end":Array.isArray(t)?$="afterArrayValue":$="afterPropertyValue"}}function Ze(){se.pop();const e=se[se.length-1];e==null?$="end":Array.isArray(e)?$="afterArrayValue":$="afterPropertyValue"}function k(e){return st(e===void 0?`JSON5: invalid end of input at ${he}:${X}`:`JSON5: invalid character '${In(e)}' at ${he}:${X}`)}function Ce(){return st(`JSON5: invalid end of input at ${he}:${X}`)}function dn(){return X-=5,st(`JSON5: invalid identifier character at ${he}:${X}`)}function sr(e){console.warn(`JSON5: '${In(e)}' in strings is not valid ECMAScript; consider escaping`)}function In(e){const t={"'":"\\'",'"':'\\"',"\\":"\\\\","\b":"\\b","\f":"\\f","\n":"\\n","\r":"\\r","	":"\\t","\v":"\\v","\0":"\\0","\u2028":"\\u2028","\u2029":"\\u2029"};if(t[e])return t[e];if(e<" "){const n=e.charCodeAt(0).toString(16);return"\\x"+("00"+n).substring(n.length)}return e}function st(e){const t=new SyntaxError(e);return t.lineNumber=he,t.columnNumber=X,t}var lr=function(t,n,a){const r=[];let u="",i,o,l="",c;if(n!=null&&typeof n=="object"&&!Array.isArray(n)&&(a=n.space,c=n.quote,n=n.replacer),typeof n=="function")o=n;else if(Array.isArray(n)){i=[];for(const h of n){let E;typeof h=="string"?E=h:(typeof h=="number"||h instanceof String||h instanceof Number)&&(E=String(h)),E!==void 0&&i.indexOf(E)<0&&i.push(E)}}return a instanceof Number?a=Number(a):a instanceof String&&(a=String(a)),typeof a=="number"?a>0&&(a=Math.min(10,Math.floor(a)),l="          ".substr(0,a)):typeof a=="string"&&(l=a.substr(0,10)),D("",{"":t});function D(h,E){let m=E[h];switch(m!=null&&(typeof m.toJSON5=="function"?m=m.toJSON5(h):typeof m.toJSON=="function"&&(m=m.toJSON(h))),o&&(m=o.call(E,h,m)),m instanceof Number?m=Number(m):m instanceof String?m=String(m):m instanceof Boolean&&(m=m.valueOf()),m){case null:return"null";case!0:return"true";case!1:return"false"}if(typeof m=="string")return s(m);if(typeof m=="number")return String(m);if(typeof m=="object")return Array.isArray(m)?x(m):f(m)}function s(h){const E={"'":.1,'"':.2},m={"'":"\\'",'"':'\\"',"\\":"\\\\","\b":"\\b","\f":"\\f","\n":"\\n","\r":"\\r","	":"\\t","\v":"\\v","\0":"\\0","\u2028":"\\u2028","\u2029":"\\u2029"};let N="";for(let S=0;S<h.length;S++){const T=h[S];switch(T){case"'":case'"':E[T]++,N+=T;continue;case"\0":if(O.isDigit(h[S+1])){N+="\\x00";continue}}if(m[T]){N+=m[T];continue}if(T<" "){let U=T.charCodeAt(0).toString(16);N+="\\x"+("00"+U).substring(U.length);continue}N+=T}const F=c||Object.keys(E).reduce((S,T)=>E[S]<E[T]?S:T);return N=N.replace(new RegExp(F,"g"),m[F]),F+N+F}function f(h){if(r.indexOf(h)>=0)throw TypeError("Converting circular structure to JSON5");r.push(h);let E=u;u=u+l;let m=i||Object.keys(h),N=[];for(const S of m){const T=D(S,h);if(T!==void 0){let U=A(S)+":";l!==""&&(U+=" "),U+=T,N.push(U)}}let F;if(N.length===0)F="{}";else{let S;if(l==="")S=N.join(","),F="{"+S+"}";else{let T=`,
`+u;S=N.join(T),F=`{
`+u+S+`,
`+E+"}"}}return r.pop(),u=E,F}function A(h){if(h.length===0)return s(h);const E=String.fromCodePoint(h.codePointAt(0));if(!O.isIdStartChar(E))return s(h);for(let m=E.length;m<h.length;m++)if(!O.isIdContinueChar(String.fromCodePoint(h.codePointAt(m))))return s(h);return h}function x(h){if(r.indexOf(h)>=0)throw TypeError("Converting circular structure to JSON5");r.push(h);let E=u;u=u+l;let m=[];for(let F=0;F<h.length;F++){const S=D(String(F),h);m.push(S!==void 0?S:"null")}let N;if(m.length===0)N="[]";else if(l==="")N="["+m.join(",")+"]";else{let F=`,
`+u,S=m.join(F);N=`[
`+u+S+`,
`+E+"]"}return r.pop(),u=E,N}};const cr={parse:ar,stringify:lr};var je=cr;const v=new $t("file-loader");function Be(e){return String(e||"").replace(/\\/g,"/").replace(/\/+/g,"/")}function Ht(e){return String(e||"").replace(/\//g,"\\")}async function zn(e){return _a(Be(e),{baseDir:Se})}async function Vt(e){return ka(Be(e),{baseDir:Se})}async function dr(e){return Ba(Be(e),{baseDir:Se})}async function gt(e,t){return xn(Be(e),t,{baseDir:Se})}async function ft(e){return Na(Be(e),{baseDir:Se})}async function we(e,t=!0){return Sa(Be(e),{baseDir:Se,recursive:t})}async function pr(e,t=!0){return Pa(Be(e),{baseDir:Se,recursive:t})}function Dr(e){let t="";for(let a=0;a<e.length;a+=8192)t+=String.fromCharCode(...e.subarray(a,a+8192));return btoa(t)}const ht=new Map;async function gr(e){try{const t=await zn(e),n=Qa(t),a=Object.keys(n).filter(l=>!l.endsWith("/")),r=a.some(l=>!l.includes("/"));let u="";if(!r&&a.length>0){const l=a.map(c=>c.split("/")[0]);l.every(c=>c===l[0])&&(u=l[0]+"/")}const i=new Map;for(const[l,c]of Object.entries(n)){if(l.endsWith("/"))continue;const s=(u?l.slice(u.length):l).replace(/\//g,"\\"),f=s.toLowerCase();!f.endsWith(".json")&&!f.endsWith(".json5")||i.set(s,On(c))}const o=Ht(e);return ht.set(o,i),v.info(`Loaded ZIP: ${o} (${i.size} JSON file(s))`),i}catch(t){return v.error(`Failed to load ZIP ${e}: ${t}`),null}}async function de(e){const t=Ht(e);for(const[a,r]of ht){const u=a+"\\";if(t.startsWith(u)){const i=t.slice(u.length),o=r.get(i);if(o===void 0)return null;try{return je.parse(o)}catch(l){throw v.error(`Failed to parse ${e}: ${l}`),new Error(`ParseError: ${e}`)}}}let n;try{n=await Vt(e)}catch{return null}try{return je.parse(n)}catch(a){throw v.error(`Failed to parse ${e}: ${a}`),new Error(`ParseError: ${e}`)}}async function Gn(e){const t=Ht(e);for(const[n,a]of ht){const r=n+"\\";if(t!==n&&!t.startsWith(r))continue;const u=t===n?"":t.slice(r.length)+"\\",i=new Map;for(const o of a.keys()){if(u&&!o.startsWith(u))continue;const l=o.slice(u.length),c=l.indexOf("\\");c===-1?i.set(l,!0):i.set(l.slice(0,c),!1)}return Array.from(i.entries()).map(([o,l])=>({name:o,isFile:l}))}try{return await dr(e)}catch{return[]}}function fr(){ht.clear(),v.debug("ZIP content cache cleared")}function hr(e,t){return new Promise(n=>{const a=new Image;a.onload=()=>n(a.width<=t&&a.height<=t),a.onerror=()=>n(!1),a.src=e})}async function mr(e=[],t=[]){try{await we(te.ROOT),await we(te.PACKS_ROOT),await we(te.SINGLE_PATCHES)}catch(r){v.error(`Failed to create base directories: ${r}`)}const n=await Gn(te.PACKS_ROOT),a=[];for(const r of n){if(r.isFile){if(!r.name.endsWith(".zip"))continue;const c=`${te.PACKS_ROOT}\\${r.name}`,D=await gr(c);if(!D)continue;const s={uuid:"",name:r.name.replace(/\.zip$/,""),version:"1.0.0",priority:100,description:"",author:"",thumbnailUrl:""},f=D.get("pack.json");let A=!1;if(f)try{Object.assign(s,je.parse(f)),A=!0}catch(x){v.error(`Pack ${r.name} pack.json parse error: ${x}`)}else v.error(`Pack ${r.name} is missing pack.json`);s.name=s.name||r.name.replace(/\.zip$/,""),A&&(s.uuid||v.warn(`ZIP pack '${r.name}' has no uuid in pack.json — order persistence disabled for this pack`),s.name===r.name.replace(/\.zip$/,"")&&v.warn(`ZIP pack '${r.name}' has no custom name in pack.json`)),a.push({dir:c,meta:s,enabled:!s.uuid||!t.includes(s.uuid)});continue}const u=`${te.PACKS_ROOT}\\${r.name}`,i={uuid:"",name:r.name,version:"1.0.0",priority:100,description:"",author:"",thumbnailUrl:""};let o=null,l=!1;try{o=await de(`${u}\\pack.json`),o?(Object.assign(i,o),l=!0):v.error(`Pack '${r.name}' is missing pack.json`)}catch(c){v.error(`Pack '${r.name}' pack.json parse error: ${c}`)}i.name=i.name||r.name,l&&(i.uuid||v.warn(`Pack '${r.name}' has no uuid in pack.json — order persistence disabled for this pack`),i.name===r.name&&v.warn(`Pack '${r.name}' has no custom name in pack.json`));for(const c of["png","ico"]){const D=`${u}\\thumbnail.${c}`;try{const s=await zn(D),A=`data:${c==="ico"?"image/x-icon":`image/${c}`};base64,${Dr(s)}`;await hr(A,128)?i.thumbnailUrl=A:v.warn(`Thumbnail ${D} ignored: dimensions exceed 128x128.`);break}catch{}}a.push({dir:u,meta:i,enabled:!i.uuid||!t.includes(i.uuid)})}return e.length>0?a.sort((r,u)=>{const i=r.meta.uuid?e.indexOf(r.meta.uuid):-1,o=u.meta.uuid?e.indexOf(u.meta.uuid):-1;return i!==-1&&o!==-1?i-o:i!==-1?-1:o!==-1?1:r.meta.priority-u.meta.priority||r.meta.name.localeCompare(u.meta.name)}):a.sort((r,u)=>r.meta.priority-u.meta.priority||r.meta.name.localeCompare(u.meta.name)),v.info(`Discovered ${a.length} datapack(s)`),a}async function Cr(e){const t=new Map,n=[],a=`${e}\\jsons\\features`;for(const r of Fe)try{let u=await de(`${a}\\${r.type}.json`);u||(u=await de(`${a}\\${r.type}.json5`)),u&&(t.set(r.type,{data:u,config:r}),v.debug(`[${e}] Loaded feature: ${r.type}`))}catch{n.push(r.type)}return{patches:t,errors:n}}async function br(e){const t=new Map,n=[],a=`${e}\\jsons\\objects`;for(const r of Sn)try{let u=await de(`${a}\\${r.type}.json`);u||(u=await de(`${a}\\${r.type}.json5`)),u&&t.set(r.type,{data:u,config:r})}catch{n.push(r.type)}return{patches:t,errors:n}}async function wr(e){try{let t=await de(`${e}\\jsons\\lang\\lang.json`);return t||(t=await de(`${e}\\jsons\\lang\\lang.json5`)),{data:t||null,error:!1}}catch{return{data:null,error:!0}}}async function yr(e){const t=new Map,n=[],a=`${e}\\jsons\\levels`,r=await Gn(a);for(const u of r){if(!u.isFile)continue;const i=u.name.toLowerCase();if(!(!i.endsWith(".json")&&!i.endsWith(".json5")))try{const o=await de(`${a}\\${u.name}`);o&&(t.set(u.name,o),v.debug(`[${e}] Loaded level: ${u.name}`))}catch{n.push(u.name)}}return{patches:t,errors:n}}async function Er(){try{return await va()}catch{return"(unknown)"}}async function Ar(){try{const e=await de(vn);return!e||typeof e!="object"?{packOrder:[],disabledPacks:[],version:1}:{packOrder:Array.isArray(e.packOrder)?e.packOrder:[],disabledPacks:Array.isArray(e.disabledPacks)?e.disabledPacks:[],version:e.version||1}}catch{return{packOrder:[],disabledPacks:[],version:1}}}async function Fr(e){try{return await gt(vn,JSON.stringify({version:1,...e},null,2)),v.info("Settings saved"),!0}catch(t){return v.error(`Failed to save settings: ${t}`),!1}}async function xr(){const e=te.GPN_EDITS;try{await we(e),await we(`${e}\\jsons\\features`),await we(`${e}\\jsons\\objects`),await we(`${e}\\jsons\\levels`)}catch(n){v.error(`Failed to create GPN edits directories: ${n}`)}const t=`${e}\\pack.json`;if(!await ft(t)){const n={uuid:"gpn_edits",name:"GP-Next Internal Edits",version:"1.0.0",priority:1e4,description:"Locally saved manual edits from GP-Next Data Viewer. DO NOT DELETE manually."};try{await gt(t,JSON.stringify(n,null,2))}catch(a){v.error(`Failed to create pack.json for GPN edits: ${a}`)}}}async function Mn(e,t,n){try{await xr();let a="objects",r=null,u="CODENAME";const i=Fe.find(c=>c.type===e);i?(a="features",r=i.key||null,u=i.idKey||"CODENAME"):e.startsWith("Level:")&&(a="levels");const o=`${te.GPN_EDITS}\\jsons\\${a}\\${e}.json`;let l={};if(await ft(o)){const c=await Vt(o);try{l=je.parse(c)}catch{}}if(a==="features")if(r){l[r]||(l[r]=[]);const c=l[r],D=c.findIndex(s=>s[u]===t);D!==-1?c[D]=n:c.push(n)}else{const c=Fe.find(s=>s.type===e),D=(c?.extraKeys||[]).find(s=>s.idKey?s.typeFilter?n?.[s.typeFilter.field]===s.typeFilter.value:l[s.key]?.some(f=>f[s.idKey]===t):!1)||(c?.extraKeys||[]).find(s=>s.idKey);if(D?.idKey){l[D.key]||(l[D.key]=[]);const s=l[D.key],f=s.findIndex(A=>A[D.idKey]===t);f!==-1?s[f]=n:s.push(n)}}else if(a==="objects"){l.objects||(l.objects=[]);const c=l.objects,D=c.findIndex(s=>s.aliases?.[0]===t);D!==-1?c[D]=n:c.push(n)}else l=n;return await gt(o,JSON.stringify(l,null,2)),v.info(`Saved manual edit for ${e} -> ${t}`),!0}catch(a){return v.error(`Failed to save GPN edit: ${a}`),!1}}async function $n(e,t){try{let n="objects",a=null,r="CODENAME";const u=Fe.find(D=>D.type===e);u&&(n="features",a=u.key||null,r=u.idKey||"CODENAME");const i=`${te.GPN_EDITS}\\jsons\\${n}\\${e}.json`;if(!await ft(i))return!0;const o=await Vt(i);let l={};try{l=je.parse(o)}catch{return!1}let c=!1;if(n==="features"&&a&&l[a]){const D=l[a],s=D.length;l[a]=D.filter(f=>f[r]!==t),c=l[a].length!==s}else if(n==="features"&&!a&&u?.extraKeys)for(const D of u.extraKeys){if(!D.idKey||!l[D.key])continue;const s=l[D.key],f=s.length;l[D.key]=s.filter(A=>A[D.idKey]!==t),l[D.key].length!==f&&(c=!0)}else if(n==="objects"&&l.objects){const D=l.objects,s=D.length;l.objects=D.filter(f=>f.aliases?.[0]!==t),c=l.objects.length!==s}return c&&(await gt(i,JSON.stringify(l,null,2)),v.info(`Removed manual edit for ${e} -> ${t}`)),!0}catch(n){return v.error(`Failed to remove GPN edit: ${n}`),!1}}async function vr(){try{const e=`${te.GPN_EDITS}\\jsons`;return await ft(e)&&await pr(e),v.info("Cleared all GPN manual edits"),!0}catch(e){return v.error(`Failed to clear GPN edits: ${e}`),!1}}const Sr=Object.freeze(Object.defineProperty({__proto__:null,clearAllGpnEdits:vr,clearCache:fr,discoverPacks:mr,getBasePath:Er,loadFeaturePatchesFrom:Cr,loadLangPatchFrom:wr,loadLevelPatchesFrom:yr,loadObjectsPatchesFrom:br,loadSettings:Ar,removeGpnEdit:$n,saveGpnEdit:Mn,saveSettings:Fr},Symbol.toStringTag,{value:"Module"}));let M=null,xe=null,ve=null,Kt=null,ye="tree";function Br(){if(M)return;M=document.createElement("div"),M.className="gp-drawer",M.setAttribute("role","dialog"),M.setAttribute("aria-hidden","true");const e=document.createElement("div");e.className="gp-drawer-header";const t=document.createElement("div");t.className="gp-drawer-title",t.id="gp-drawer-title";const n=document.createElement("button");n.type="button",n.className="gp-drawer-close",n.innerHTML="&#8249;&#8249;&#8249;",n.title="Close panel",n.onclick=Un,e.appendChild(n),e.appendChild(t);const a=document.createElement("div");a.className="gp-drawer-tabs",a.id="gp-drawer-tabs";const r=document.createElement("div");r.className="gp-drawer-body",r.id="gp-drawer-body";const u=document.createElement("div");u.className="gp-drawer-header",u.style.borderTop="1px solid rgba(255,255,255,0.08)",u.style.borderBottom="none",u.id="gp-drawer-footer",M.appendChild(e),M.appendChild(a),M.appendChild(r),M.appendChild(u),document.getElementById("gp-overlay").appendChild(M)}function _r(){const e=Kt?.getCurrent(xe);if(!e)return null;const t=Fe.find(n=>n.type===xe);return t?Bn(t,e,ve.id)?.entry||null:e?.objects&&e.objects.find(n=>n.aliases?.[0]===ve.id)||null}function jn(){const e=document.getElementById("gp-drawer-tabs");if(!e)return;e.innerHTML="",[{id:"tree",labelKey:"data.drawer.treeView"},{id:"json",labelKey:"data.drawer.rawJson"},{id:"diff",labelKey:"data.drawer.comparison"},{id:"edit",labelKey:"data.drawer.edit"}].forEach(n=>{const a=document.createElement("button");a.type="button",a.className=`gp-drawer-tab ${n.id===ye?"gp-active":""}`,a.textContent=w(n.labelKey),a.onclick=()=>{ye=n.id,jn(),Wn()},e.appendChild(a)})}function Wn(){const e=document.getElementById("gp-drawer-body");if(!e)return;e.innerHTML="";const t=_r();if(!t){e.innerHTML='<div class="gp-text-muted gp-empty-state">Data not found in current state.</div>',Me(!1);return}ye==="tree"?Pr(e,t):ye==="json"?Nr(e,t):ye==="diff"?Tr(e,t):ye==="edit"&&Lr(e,t),Me(!0)}function Me(e){const t=document.getElementById("gp-drawer-footer");if(!t||(t.innerHTML="",!e))return;const n=document.createElement("span");n.className="gp-text-muted",n.style.cssText="font-size:11px;flex:1;min-width:0;white-space:normal;line-height:1.5;",n.textContent=w("data.drawer.restoreNote");const a=it(w("data.drawer.restoreItem"),async()=>{if(!await kr(w("data.drawer.restoreConfirm"),5e3))return;const i=await $n(xe,ve.id);V(w(i?"data.drawer.saveSuccess":"data.drawer.saveFail"),i?"success":"error")},{variant:"danger",small:!0}),r=document.createElement("div");r.style.cssText="display:flex;gap:6px;align-items:center;flex-shrink:0;",r.appendChild(a),t.style.cssText="display:flex;align-items:center;gap:8px;padding:8px 12px;border-top:1px solid rgba(255,255,255,0.08);flex-shrink:0;",t.appendChild(n),t.appendChild(r)}function kr(e,t=5e3){return new Promise(n=>{const a=document.getElementById("gp-drawer-footer");if(!a){n(!1);return}a.innerHTML="",a.style.cssText="display:flex;align-items:center;gap:6px;padding:8px 12px;border-top:1px solid rgba(255,255,255,0.08);flex-shrink:0;";const r=document.createElement("span");r.className="gp-text-muted",r.style.cssText="font-size:11px;flex:1;min-width:0;line-height:1.5;",r.textContent=e;const u=it(w("common.confirm"),()=>{Me(!0),n(!0)},{variant:"danger",small:!0}),i=it(w("common.cancel"),()=>{Me(!0),n(!1)},{small:!0});a.appendChild(r),a.appendChild(i),a.appendChild(u);const o=setTimeout(()=>{a.contains(u)&&(Me(!0),n(!1))},t),l=n;n=c=>{clearTimeout(o),l(c)}})}function Pr(e,t){const n=document.createElement("div");n.className="gp-tree";function a(r,u,i){const o=document.createElement("div");o.className="gp-tree-node";const l=document.createElement("span");if(l.className="gp-tree-key",l.textContent=r!==null?`"${r}": `:"",u===null){const c=document.createElement("span");c.className="gp-tree-val-null",c.textContent="null",o.appendChild(l),o.appendChild(c)}else if(typeof u=="boolean"){const c=document.createElement("span");c.className="gp-tree-val-bool",c.textContent=u.toString(),o.appendChild(l),o.appendChild(c)}else if(typeof u=="number"){const c=document.createElement("span");c.className="gp-tree-val-num",c.textContent=u.toString(),o.appendChild(l),o.appendChild(c)}else if(typeof u=="string"){const c=document.createElement("span");c.className="gp-tree-val-str",c.textContent=`"${u}"`,o.appendChild(l),o.appendChild(c)}else if(Array.isArray(u)){const c=document.createElement("span");c.className="gp-tree-caret",c.textContent="▼",o.appendChild(c),o.appendChild(l),o.appendChild(document.createTextNode(`[  (${u.length})`));const D=document.createElement("div");let s=!1;c.onclick=()=>{s=!s,c.classList.toggle("gp-collapsed",s),D.style.display=s?"none":"block"},u.forEach(f=>a(null,f,D)),o.appendChild(D),o.appendChild(document.createTextNode("]"))}else if(typeof u=="object"){const c=document.createElement("span");c.className="gp-tree-caret",c.textContent="▼",o.appendChild(c),o.appendChild(l),o.appendChild(document.createTextNode("{"));const D=document.createElement("div");let s=!1;c.onclick=()=>{s=!s,c.classList.toggle("gp-collapsed",s),D.style.display=s?"none":"block"};for(const[f,A]of Object.entries(u))a(f,A,D);o.appendChild(D),o.appendChild(document.createTextNode("}"))}i.appendChild(o)}a(null,t,n),e.appendChild(n)}function Nr(e,t){const n=document.createElement("pre");n.className="gp-code",n.style.cssText="user-select:text;white-space:pre-wrap;word-break:break-word;",n.textContent=JSON.stringify(t,null,2),e.appendChild(n)}function Tr(e,t){const n=Kt?.getOriginal(xe);let a=null;if(n){const x=Fe.find(h=>h.type===xe);x?a=Bn(x,n,ve.id)?.entry||null:n?.objects&&(a=n.objects.find(h=>h.aliases?.[0]===ve.id))}if(!a){const x=document.createElement("div");x.className="gp-text-muted",x.style.padding="16px",x.textContent=w("data.drawer.noOriginal"),e.appendChild(x);return}const r=JSON.stringify(a,null,2),u=JSON.stringify(t,null,2);if(r===u){const x=document.createElement("div");x.className="gp-text-muted",x.style.padding="16px",x.textContent=w("data.drawer.noChanges"),e.appendChild(x);return}const i=document.createElement("div");i.className="gp-diff-container";const o=document.createElement("div");o.className="gp-diff-row";const l=document.createElement("div");l.className="gp-diff-col";const c=document.createElement("div");c.className="gp-diff-col-title",c.textContent="Original",l.appendChild(c);const D=document.createElement("pre");D.style.cssText="margin:0;user-select:text;white-space:pre-wrap;word-break:break-word;font-family:Consolas,monospace;font-size:11px;",D.textContent=r,l.appendChild(D);const s=document.createElement("div");s.className="gp-diff-col";const f=document.createElement("div");f.className="gp-diff-col-title",f.textContent="Current (Live)",s.appendChild(f);const A=document.createElement("pre");A.style.cssText="margin:0;user-select:text;white-space:pre-wrap;word-break:break-word;font-family:Consolas,monospace;font-size:11px;",A.textContent=u,s.appendChild(A),o.appendChild(l),o.appendChild(s),i.appendChild(o),e.appendChild(i)}function Lr(e,t){const n=document.createElement("div");n.className="gp-text-muted gp-mb-8",n.style.fontSize="11px",n.textContent=w("data.drawer.editHint");const a=document.createElement("textarea");a.className="gp-textarea-edit",a.value=JSON.stringify(t,null,2),a.spellcheck=!1;const r=it(w("data.drawer.save"),async()=>{try{const u=JSON.parse(a.value);await Mn(xe,ve.id,u)?V(w("data.drawer.saveSuccess"),"success"):V(w("data.drawer.saveFail"),"error")}catch(u){V("Invalid JSON: "+u.message,"error")}},{variant:"success"});e.appendChild(n),e.appendChild(a),e.appendChild(Oa(r))}function Tu(e,t,n,a){Kt=t,xe=n,ve=a,Br();const r=document.getElementById("gp-drawer-title");r&&(r.textContent=a.id),ye="tree",jn(),Wn(),M.setAttribute("aria-hidden","false"),M.classList.add("gp-drawer-open")}function Un(){M&&(M.setAttribute("aria-hidden","true"),M.classList.remove("gp-drawer-open"))}let Z=null,le=null,Ee=null,re=null,Ae=null,ne=null,He=!1,lt=null,Jt=[],Hn="",Q={status:"idle",latestVersion:"",error:""},Ie={onCheck:null,onOpen:null};const ue=[];let Y=null;function Or(){const e=document.createElement("style");e.id="gp-next-styles",e.textContent=La,document.head.appendChild(e)}function Rr(){Z=document.createElement("div"),Z.id="gp-overlay";const e=document.createElement("div");e.className="gp-header";const t=document.createElement("span");t.className="gp-logo",t.textContent="GP Next",re=document.createElement("span"),re.className="gp-status",re.textContent=w("header.status.waiting");const n=document.createElement("button");n.className="gp-close-btn",n.innerHTML="&times;",n.addEventListener("click",Ct),e.appendChild(t),e.appendChild(re),e.appendChild(n),le=document.createElement("div"),le.className="gp-tabs",le.id="gp-tab-bar",Ee=document.createElement("div"),Ee.className="gp-content",Ee.id="gp-content",Ae=document.createElement("div"),Ae.className="gp-footer",Z.appendChild(e),Z.appendChild(le),Z.appendChild(Ee),Z.appendChild(Ae),document.body.appendChild(Z),ne=document.createElement("div"),ne.className="gp-f1-hint",ne.textContent=w("header.f10Hint"),ne.title="Toggle GP Next Panel (F10)",ne.style.display="none",ne.addEventListener("click",Zt),document.body.appendChild(ne)}function We(){if(!Ae)return;Ae.innerHTML="";const e=document.createElement("span");e.className="gp-footer-version",e.textContent=w("footer.version",Hn||"?"),Ae.appendChild(e);const t=document.createElement("div");t.className="gp-footer-right";const n=document.createElement("button");n.type="button",n.className="gp-footer-update",n.disabled=Q.status!=="update-available",Q.status==="update-available"?(n.classList.add("gp-footer-update-hot"),n.textContent=w("footer.updateAvailable",Q.latestVersion||"?"),n.title=w("footer.openDownload"),n.addEventListener("click",()=>{Ie.onOpen&&Ie.onOpen()})):Q.status==="checking"?n.textContent=w("footer.updateChecking"):Q.status==="up-to-date"?n.textContent=w("footer.upToDate"):Q.status==="error"?(n.textContent=w("footer.updateCheckFailed"),n.title=Q.error||w("footer.updateCheckFailed")):n.textContent=w("footer.updateIdle"),t.appendChild(n);const a=document.createElement("button");a.type="button",a.className="gp-footer-refresh",a.textContent="↻",a.title=w("footer.checkNow"),Q.status==="checking"&&(a.disabled=!0,a.classList.add("gp-spinning")),a.addEventListener("click",()=>{Ie.onCheck&&Ie.onCheck()}),t.appendChild(a),Ae.appendChild(t)}function Ir(){document.addEventListener("keydown",e=>{e.key==="F10"&&(e.preventDefault(),e.stopPropagation(),Zt()),e.key==="Escape"&&He&&(e.preventDefault(),e.stopPropagation(),Ct())},!0)}function Vn(e){const t=document.getElementById("GameCanvas")||document.querySelector("canvas");t&&(t.style.pointerEvents=e?"none":"")}function Kn(){le.innerHTML="";for(const e of ue){const t=document.createElement("button");t.type="button",t.className="gp-tab"+(e.id===Y?" gp-tab-active":""),t.textContent=w(e.labelKey),t.dataset.tabId=e.id,t.addEventListener("click",()=>qt(e.id)),le.appendChild(t)}}function mt(){Ee.innerHTML="";const e=ue.find(t=>t.id===Y);e&&e.render&&e.render(Ee)}function Jn(){if(!Z)return;He=!0,Z.classList.add("gp-open"),ne.classList.add("gp-hidden"),Vn(!0),mt();const e=ue.find(t=>t.id===Y);e?.onActivate&&e.onActivate()}function Ct(){if(!Z)return;He=!1,Z.classList.remove("gp-open"),ne.classList.remove("gp-hidden"),Vn(!1);try{Un()}catch{}const e=ue.find(t=>t.id===Y);e?.onDeactivate&&e.onDeactivate()}function Zt(){He?Ct():Jn()}function zr(){return He}function Gr(e){lt=null,Jt=[],re&&(re.textContent=e)}function Mr(e,...t){lt=e,Jt=t,re&&(re.textContent=w(e,...t))}function $r(e){Hn=String(e||""),We()}function jr(e){Q={...Q,...e||{}},We()}function Wr(e={}){Ie={onCheck:typeof e.onCheck=="function"?e.onCheck:null,onOpen:typeof e.onOpen=="function"?e.onOpen:null},We()}function Ur(e){const t=ue.findIndex(a=>a.id===e.id),n=t!==-1&&Y===e.id;if(t!==-1?ue[t]=e:ue.push(e),le){if(Kn(),!Y)qt(e.id);else if(n){mt();const a=ue.find(r=>r.id===Y);a?.onActivate&&a.onActivate()}}}function qt(e){if(Y===e&&Ee.children.length>0)return;const t=ue.find(u=>u.id===Y);t?.onDeactivate&&t.onDeactivate(),Y=e,le.querySelectorAll(".gp-tab").forEach(u=>{u.classList.toggle("gp-tab-active",u.dataset.tabId===e)});const a=le.querySelector(`.gp-tab[data-tab-id="${e}"]`);a?.scrollIntoView&&a.scrollIntoView({block:"nearest",inline:"nearest"}),mt();const r=ue.find(u=>u.id===e);r?.onActivate&&r.onActivate()}function Hr(){return Or(),Rr(),Ir(),ba(()=>{Kn(),Y&&mt(),ne&&(ne.textContent=w("header.f10Hint")),lt&&re&&(re.textContent=w(lt,...Jt)),We()}),We(),{show:Jn,hide:Ct,toggle:Zt,isOpen:zr,updateStatus:Gr,updateStatusKey:Mr,setVersion:$r,setUpdateState:jr,bindUpdateActions:Wr,registerTab:Ur,switchTab:qt}}async function Zn(e,t){await p("plugin:opener|open_url",{url:e,with:t})}async function Lu(e,t){await p("plugin:opener|open_path",{path:e,with:t})}const ct=new $t("update-checker"),Vr="https://pvzge.com/jsons/gp-next-info.json",Kr="https://pvzge.com/download/",Jr="https://pvzge.com/en/download/",Zr=8e3,tt=[];let qe=null,pn=!1,zt={status:"idle",currentVersion:fe,latestVersion:"",checkedAt:0,error:""};function qr(){const e=dt();for(const t of tt.slice())try{t(e)}catch{}}function St(e){zt={...zt,...e},qr()}function Dn(e){return String(e||"").trim().match(/\d+/g)?.map(t=>Number(t))||[0]}function Xr(e,t){const n=Dn(e),a=Dn(t),r=Math.max(n.length,a.length);for(let u=0;u<r;u++){const i=n[u]??0,o=a[u]??0;if(i>o)return 1;if(i<o)return-1}return 0}function dt(){return{...zt}}function Yr(e){return typeof e!="function"?()=>{}:(tt.push(e),e(dt()),()=>{const t=tt.indexOf(e);t!==-1&&tt.splice(t,1)})}function Qr(e=Ca()){return e==="zh-CN"?Kr:Jr}async function eu(){const e=Qr();try{return await Zn(e),!0}catch(t){ct.warn(`Failed to open external browser via Tauri opener: ${t}`);try{if(window.electron?.shell?.openExternal)return await window.electron.shell.openExternal(e),!0}catch(n){ct.warn(`Fallback opener failed: ${n}`)}return window.open(e,"_blank","noopener,noreferrer"),!0}}async function qn(e={}){const t=e.manual===!0;if(qe)return qe;St({status:"checking",error:""});const n=(async()=>{const a=new AbortController,r=setTimeout(()=>a.abort(),Zr);try{const u=await fetch(`${Vr}?t=${Date.now()}`,{cache:"no-store",signal:a.signal});if(!u.ok)throw new Error(`HTTP ${u.status}`);const i=await u.json(),o=String(i?.version||"").trim();if(!o)throw new Error("Missing version field");const l=Xr(o,fe)>0;return St({status:l?"update-available":"up-to-date",latestVersion:o,checkedAt:Date.now(),error:""}),l?(!pn||t)&&(V(w("toast.updateAvailable",o),"",5e3),pn=!0):t&&V(w("toast.updateUpToDate",fe),"success"),ct.info(`Update check complete: local=${fe}, latest=${o}, newer=${l}`),dt()}catch(u){const i=u?.name==="AbortError"?"timeout":String(u?.message||u);return St({status:"error",checkedAt:Date.now(),error:i}),ct.warn(`Update check failed: ${i}`),t&&V(w("toast.updateCheckFailed"),"error"),dt()}finally{clearTimeout(r),qe=null}})();return qe=n,n}const ee=new $t("main"),gn="0.8.2";ee.info("GP-Next loading...");const Gt=jt();Fn();Ta();const L=Hr();L.setVersion(fe);L.bindUpdateActions({onCheck:()=>qn({manual:!0}),onOpen:()=>eu()});Yr(e=>L.setUpdateState(e));L.updateStatus(w("header.status.waiting"));qn().catch(e=>ee.debug("Startup update check skipped: "+e));const tu=[{id:"patcher",labelKey:"tab.patcher"},{id:"data",labelKey:"tab.data"},{id:"cheats",labelKey:"tab.cheats"},{id:"cloud",labelKey:"tab.cloud"},{id:"settings",labelKey:"tab.settings"},{id:"guide",labelKey:"tab.guide"},{id:"about",labelKey:"tab.about"},{id:"log",labelKey:"tab.log"}];for(const e of tu)L.registerTab({id:e.id,labelKey:e.labelKey,render(t){const n=document.createElement("div");n.className="gp-text-muted",n.textContent=w("common.loading"),t.appendChild(n)}});window.gpNext={version:fe,debug:Gt.debug===!0,toggle:L.toggle,show:L.show,hide:L.hide};ee.info("Phase 1 complete — overlay mounted. Press F10 to toggle.");(async()=>{const{waitForEngine:e}=await G(async()=>{const{waitForEngine:g}=await import("./engine-ktIF7zII.js");return{waitForEngine:g}},[]);let t;try{t=await e(3e4),L.updateStatus(w("header.status.engineReady"));const g=Number(Gt.frameRate);Number.isFinite(g)&&g>0?t.game.setFrameRate(g):Gt.frameRate==="0"&&t.game.setFrameRate(999),(await G(()=>import("./scroll-sensitivity-YCzaXGXZ.js"),__vite__mapDeps([0,1]))).install()}catch{L.updateStatus(w("header.status.timeout")),ee.error("Engine wait failed — patcher features unavailable");return}const{CorePatcher:n}=await G(async()=>{const{CorePatcher:g}=await import("./patcher-Cco04iXG.js");return{CorePatcher:g}},__vite__mapDeps([2,1,3])),{DataStore:a}=await G(async()=>{const{DataStore:g}=await import("./data-store-DHLaXs3u.js");return{DataStore:g}},__vite__mapDeps([4,1,3])),{getBasePath:r}=await G(async()=>{const{getBasePath:g}=await Promise.resolve().then(()=>Sr);return{getBasePath:g}},void 0),u=new n;u.initCacheScan(),u.installSceneHook(),u.installLoadHook();const i=await u.loadAllPatches(),o=new a(u.getOriginalData()),l=await r();i.editsCount>0?L.updateStatusKey("header.status.compactWithEdits",i.packs.length,i.loaded.length,i.editsCount):L.updateStatusKey("header.status.compact",i.packs.length,i.loaded.length),ee.info(`Phase 3 complete — ${i.packs.length} pack(s), ${i.loaded.length} type(s) applied`);const{render:c,bindPatcher:D}=await G(async()=>{const{render:g,bindPatcher:B}=await import("./tab-patcher-DXIdWwxR.js");return{render:g,bindPatcher:B}},[]),{render:s,bindData:f}=await G(async()=>{const{render:g,bindData:B}=await import("./tab-data-B1i8uO7r.js");return{render:g,bindData:B}},[]),{render:A,onActivate:x,onDeactivate:h}=await G(async()=>{const{render:g,onActivate:B,onDeactivate:I}=await import("./tab-cheats-D_NOfoCI.js");return{render:g,onActivate:B,onDeactivate:I}},__vite__mapDeps([5,1])),{render:E}=await G(async()=>{const{render:g}=await import("./tab-settings-DaTsFm09.js");return{render:g}},__vite__mapDeps([6,1,0])),{render:m,bindCloudSaver:N}=await G(async()=>{const{render:g,bindCloudSaver:B}=await import("./tab-cloud-CShTibIg.js");return{render:g,bindCloudSaver:B}},[]),{render:F}=await G(async()=>{const{render:g}=await import("./tab-about-ChNWG3TI.js");return{render:g}},[]),{render:S,onActivate:T,onDeactivate:U}=await G(async()=>{const{render:g,onActivate:B,onDeactivate:I}=await import("./tab-log-7xDEKp8p.js");return{render:g,onActivate:B,onDeactivate:I}},[]),{render:Ve,bindGuide:Le}=await G(async()=>{const{render:g,bindGuide:B}=await import("./tab-guide-BtLJn5bE.js");return{render:g,bindGuide:B}},[]);D(u,o,l,g=>{g.editsCount>0?L.updateStatusKey("header.status.compactWithEdits",g.packs.length,g.loaded.length,g.editsCount):L.updateStatusKey("header.status.compact",g.packs.length,g.loaded.length)}),f(u,o),Le&&Le(l),L.registerTab({id:"patcher",labelKey:"tab.patcher",render:c}),L.registerTab({id:"data",labelKey:"tab.data",render:s}),L.registerTab({id:"cheats",labelKey:"tab.cheats",render:A,onActivate:x,onDeactivate:h}),L.registerTab({id:"cloud",labelKey:"tab.cloud",render:m}),L.registerTab({id:"settings",labelKey:"tab.settings",render:E}),L.registerTab({id:"guide",labelKey:"tab.guide",render:Ve}),L.registerTab({id:"about",labelKey:"tab.about",render:F}),L.registerTab({id:"log",labelKey:"tab.log",render:S,onActivate:T,onDeactivate:U});try{const g=(await G(async()=>{const{default:B}=await import("./cloudSavePatcher-D7UJjYJU.js");return{default:B}},[])).default;await g.init(),window.cloudSaver=g,N(g),ee.info("Cloud save module ready")}catch(g){ee.warn("Cloud save init failed: "+g)}try{const{updateActivity:g}=await G(async()=>{const{updateActivity:B}=await Promise.resolve().then(()=>Cu);return{updateActivity:B}},void 0);await g("Using GP-Next "+fe,"Playing version "+gn),ee.info("Discord RPC updated")}catch(g){ee.debug("DRPC update skipped: "+g)}Object.assign(window.gpNext,{init:()=>u.loadAllPatches(),reload:()=>u.reloadPatches(),status:()=>u.getStatus(),setObjectsData:(...g)=>u.setObjectsData(...g),exportJson:(...g)=>o.exportJson(...g),exportLang:(...g)=>u.exportLang(...g),restoreOriginal:g=>o.restore(g),restoreAll:()=>o.restoreAll(),listOrigins:()=>o.listBackups(),hasOrigin:g=>o.hasBackup(g),setFrameRate:g=>t.game.setFrameRate(g),setGameSpeed:g=>{t.director._scheduler._timeScale=g},cheats:{setSun:g=>{const B=t.js.getClassByName("SunCount")?.component;B&&B.setSunCount(g)},addSun:g=>{const B=t.js.getClassByName("SunCount")?.component;B&&B.SunAdd(g||1e3)},winLevel:()=>{const g=t.js.getClassByName("LevelPlay")?.component;g&&g.victory()}},_toast:V,debug:{getPlantRegistry:()=>u.getPlantRegistryDebug()},help:()=>{console.log("[GP Next] ========================================"),console.log("[GP Next] GP-Next (Gardendless Patcher Next) v"+fe),console.log("[GP Next] Game Version: "+gn),console.log("[GP Next] ========================================"),console.log(""),console.log("[GP Next] UI:"),console.log("[GP Next]   .toggle()                   - Toggle overlay panel (F1)"),console.log(""),console.log("[GP Next] PATCHER:"),console.log("[GP Next]   .init()                     - Load all patches"),console.log("[GP Next]   .reload()                   - Reload all patches from disk"),console.log("[GP Next]   .status()                   - Show patcher status"),console.log("[GP Next]   .setObjectsData(Type, alias, key, val)"),console.log("[GP Next]   .setObjectsData(Type, alias, {key: val})"),console.log("[GP Next]   .debug.getPlantRegistry()   - Inspect dynamic plant registry"),console.log(""),console.log("[GP Next] DATA:"),console.log("[GP Next]   .exportJson(Type, useOriginal?, autoDownload?)"),console.log("[GP Next]   .exportLang(useOriginal?, autoDownload?)"),console.log("[GP Next]   .restoreOriginal(Type)      - Restore one type"),console.log("[GP Next]   .restoreAll()               - Restore all types"),console.log("[GP Next]   .listOrigins()              - List backed up types"),console.log("[GP Next]   .hasOrigin(Type)            - Check if backup exists"),console.log(""),console.log("[GP Next] GAME:"),console.log("[GP Next]   .setFrameRate(fps)          - Change frame rate"),console.log("[GP Next]   .setGameSpeed(multiplier)   - Change game speed"),console.log(""),console.log("[GP Next] CHEATS:"),console.log("[GP Next]   .cheats.setSun(value)       - Set sun count"),console.log("[GP Next]   .cheats.addSun(value)       - Add sun (default 1000)"),console.log("[GP Next]   .cheats.winLevel()          - Win current level"),console.log("");const g=String(l||"").replace(/[\\/]+$/,"");console.log("[GP Next] Patch files: "+g+"/patches"),console.log("[GP Next] Docs: https://pvzge.com/en/guide/mod/")}}),ee.info("Phase 4 complete — GP-Next fully initialized. Run gpNext.help() for commands.")})();class Xt{constructor(...t){this.type="Logical",t.length===1?"Logical"in t[0]?(this.width=t[0].Logical.width,this.height=t[0].Logical.height):(this.width=t[0].width,this.height=t[0].height):(this.width=t[0],this.height=t[1])}toPhysical(t){return new $e(this.width*t,this.height*t)}[K](){return{width:this.width,height:this.height}}toJSON(){return this[K]()}}class $e{constructor(...t){this.type="Physical",t.length===1?"Physical"in t[0]?(this.width=t[0].Physical.width,this.height=t[0].Physical.height):(this.width=t[0].width,this.height=t[0].height):(this.width=t[0],this.height=t[1])}toLogical(t){return new Xt(this.width/t,this.height/t)}[K](){return{width:this.width,height:this.height}}toJSON(){return this[K]()}}class Pe{constructor(t){this.size=t}toLogical(t){return this.size instanceof Xt?this.size:this.size.toLogical(t)}toPhysical(t){return this.size instanceof $e?this.size:this.size.toPhysical(t)}[K](){return{[`${this.size.type}`]:{width:this.size.width,height:this.size.height}}}toJSON(){return this[K]()}}class Xn{constructor(...t){this.type="Logical",t.length===1?"Logical"in t[0]?(this.x=t[0].Logical.x,this.y=t[0].Logical.y):(this.x=t[0].x,this.y=t[0].y):(this.x=t[0],this.y=t[1])}toPhysical(t){return new ge(this.x*t,this.y*t)}[K](){return{x:this.x,y:this.y}}toJSON(){return this[K]()}}class ge{constructor(...t){this.type="Physical",t.length===1?"Physical"in t[0]?(this.x=t[0].Physical.x,this.y=t[0].Physical.y):(this.x=t[0].x,this.y=t[0].y):(this.x=t[0],this.y=t[1])}toLogical(t){return new Xn(this.x/t,this.y/t)}[K](){return{x:this.x,y:this.y}}toJSON(){return this[K]()}}class Xe{constructor(t){this.position=t}toLogical(t){return this.position instanceof Xn?this.position:this.position.toLogical(t)}toPhysical(t){return this.position instanceof ge?this.position:this.position.toPhysical(t)}[K](){return{[`${this.position.type}`]:{x:this.position.x,y:this.position.y}}}toJSON(){return this[K]()}}var j;(function(e){e.WINDOW_RESIZED="tauri://resize",e.WINDOW_MOVED="tauri://move",e.WINDOW_CLOSE_REQUESTED="tauri://close-requested",e.WINDOW_DESTROYED="tauri://destroyed",e.WINDOW_FOCUS="tauri://focus",e.WINDOW_BLUR="tauri://blur",e.WINDOW_SCALE_FACTOR_CHANGED="tauri://scale-change",e.WINDOW_THEME_CHANGED="tauri://theme-changed",e.WINDOW_CREATED="tauri://window-created",e.WEBVIEW_CREATED="tauri://webview-created",e.DRAG_ENTER="tauri://drag-enter",e.DRAG_OVER="tauri://drag-over",e.DRAG_DROP="tauri://drag-drop",e.DRAG_LEAVE="tauri://drag-leave"})(j||(j={}));async function Yn(e,t){window.__TAURI_EVENT_PLUGIN_INTERNALS__.unregisterListener(e,t),await p("plugin:event|unlisten",{event:e,eventId:t})}async function Qn(e,t,n){var a;const r=typeof n?.target=="string"?{kind:"AnyLabel",label:n.target}:(a=n?.target)!==null&&a!==void 0?a:{kind:"Any"};return p("plugin:event|listen",{event:e,target:r,handler:Aa(t)}).then(u=>async()=>Yn(e,u))}async function nu(e,t,n){return Qn(e,a=>{Yn(e,a.id),t(a)},n)}async function au(e,t){await p("plugin:event|emit",{event:e,payload:t})}async function ru(e,t,n){await p("plugin:event|emit_to",{target:typeof e=="string"?{kind:"AnyLabel",label:e}:e,event:t,payload:n})}let uu=class nt extends Fa{constructor(t){super(t)}static async new(t,n,a){return p("plugin:image|new",{rgba:pt(t),width:n,height:a}).then(r=>new nt(r))}static async fromBytes(t){return p("plugin:image|from_bytes",{bytes:pt(t)}).then(n=>new nt(n))}static async fromPath(t){return p("plugin:image|from_path",{path:t}).then(n=>new nt(n))}async rgba(){return p("plugin:image|rgba",{rid:this.rid}).then(t=>new Uint8Array(t))}async size(){return p("plugin:image|size",{rid:this.rid})}};function pt(e){return e==null?null:typeof e=="string"?e:e instanceof uu?e.rid:e}var Mt;(function(e){e[e.Critical=1]="Critical",e[e.Informational=2]="Informational"})(Mt||(Mt={}));class iu{constructor(t){this._preventDefault=!1,this.event=t.event,this.id=t.id}preventDefault(){this._preventDefault=!0}isPreventDefault(){return this._preventDefault}}var fn;(function(e){e.None="none",e.Normal="normal",e.Indeterminate="indeterminate",e.Paused="paused",e.Error="error"})(fn||(fn={}));function ea(){return new ta(window.__TAURI_INTERNALS__.metadata.currentWindow.label,{skip:!0})}async function Bt(){return p("plugin:window|get_all_windows").then(e=>e.map(t=>new ta(t,{skip:!0})))}const _t=["tauri://created","tauri://error"];class ta{constructor(t,n={}){var a;this.label=t,this.listeners=Object.create(null),n?.skip||p("plugin:window|create",{options:{...n,parent:typeof n.parent=="string"?n.parent:(a=n.parent)===null||a===void 0?void 0:a.label,label:t}}).then(async()=>this.emit("tauri://created")).catch(async r=>this.emit("tauri://error",r))}static async getByLabel(t){var n;return(n=(await Bt()).find(a=>a.label===t))!==null&&n!==void 0?n:null}static getCurrent(){return ea()}static async getAll(){return Bt()}static async getFocusedWindow(){for(const t of await Bt())if(await t.isFocused())return t;return null}async listen(t,n){return this._handleTauriEvent(t,n)?()=>{const a=this.listeners[t];a.splice(a.indexOf(n),1)}:Qn(t,n,{target:{kind:"Window",label:this.label}})}async once(t,n){return this._handleTauriEvent(t,n)?()=>{const a=this.listeners[t];a.splice(a.indexOf(n),1)}:nu(t,n,{target:{kind:"Window",label:this.label}})}async emit(t,n){if(_t.includes(t)){for(const a of this.listeners[t]||[])a({event:t,id:-1,payload:n});return}return au(t,n)}async emitTo(t,n,a){if(_t.includes(n)){for(const r of this.listeners[n]||[])r({event:n,id:-1,payload:a});return}return ru(t,n,a)}_handleTauriEvent(t,n){return _t.includes(t)?(t in this.listeners?this.listeners[t].push(n):this.listeners[t]=[n],!0):!1}async scaleFactor(){return p("plugin:window|scale_factor",{label:this.label})}async innerPosition(){return p("plugin:window|inner_position",{label:this.label}).then(t=>new ge(t))}async outerPosition(){return p("plugin:window|outer_position",{label:this.label}).then(t=>new ge(t))}async innerSize(){return p("plugin:window|inner_size",{label:this.label}).then(t=>new $e(t))}async outerSize(){return p("plugin:window|outer_size",{label:this.label}).then(t=>new $e(t))}async isFullscreen(){return p("plugin:window|is_fullscreen",{label:this.label})}async isMinimized(){return p("plugin:window|is_minimized",{label:this.label})}async isMaximized(){return p("plugin:window|is_maximized",{label:this.label})}async isFocused(){return p("plugin:window|is_focused",{label:this.label})}async isDecorated(){return p("plugin:window|is_decorated",{label:this.label})}async isResizable(){return p("plugin:window|is_resizable",{label:this.label})}async isMaximizable(){return p("plugin:window|is_maximizable",{label:this.label})}async isMinimizable(){return p("plugin:window|is_minimizable",{label:this.label})}async isClosable(){return p("plugin:window|is_closable",{label:this.label})}async isVisible(){return p("plugin:window|is_visible",{label:this.label})}async title(){return p("plugin:window|title",{label:this.label})}async theme(){return p("plugin:window|theme",{label:this.label})}async isAlwaysOnTop(){return p("plugin:window|is_always_on_top",{label:this.label})}async center(){return p("plugin:window|center",{label:this.label})}async requestUserAttention(t){let n=null;return t&&(t===Mt.Critical?n={type:"Critical"}:n={type:"Informational"}),p("plugin:window|request_user_attention",{label:this.label,value:n})}async setResizable(t){return p("plugin:window|set_resizable",{label:this.label,value:t})}async setEnabled(t){return p("plugin:window|set_enabled",{label:this.label,value:t})}async isEnabled(){return p("plugin:window|is_enabled",{label:this.label})}async setMaximizable(t){return p("plugin:window|set_maximizable",{label:this.label,value:t})}async setMinimizable(t){return p("plugin:window|set_minimizable",{label:this.label,value:t})}async setClosable(t){return p("plugin:window|set_closable",{label:this.label,value:t})}async setTitle(t){return p("plugin:window|set_title",{label:this.label,value:t})}async maximize(){return p("plugin:window|maximize",{label:this.label})}async unmaximize(){return p("plugin:window|unmaximize",{label:this.label})}async toggleMaximize(){return p("plugin:window|toggle_maximize",{label:this.label})}async minimize(){return p("plugin:window|minimize",{label:this.label})}async unminimize(){return p("plugin:window|unminimize",{label:this.label})}async show(){return p("plugin:window|show",{label:this.label})}async hide(){return p("plugin:window|hide",{label:this.label})}async close(){return p("plugin:window|close",{label:this.label})}async destroy(){return p("plugin:window|destroy",{label:this.label})}async setDecorations(t){return p("plugin:window|set_decorations",{label:this.label,value:t})}async setShadow(t){return p("plugin:window|set_shadow",{label:this.label,value:t})}async setEffects(t){return p("plugin:window|set_effects",{label:this.label,value:t})}async clearEffects(){return p("plugin:window|set_effects",{label:this.label,value:null})}async setAlwaysOnTop(t){return p("plugin:window|set_always_on_top",{label:this.label,value:t})}async setAlwaysOnBottom(t){return p("plugin:window|set_always_on_bottom",{label:this.label,value:t})}async setContentProtected(t){return p("plugin:window|set_content_protected",{label:this.label,value:t})}async setSize(t){return p("plugin:window|set_size",{label:this.label,value:t instanceof Pe?t:new Pe(t)})}async setMinSize(t){return p("plugin:window|set_min_size",{label:this.label,value:t instanceof Pe?t:t?new Pe(t):null})}async setMaxSize(t){return p("plugin:window|set_max_size",{label:this.label,value:t instanceof Pe?t:t?new Pe(t):null})}async setSizeConstraints(t){function n(a){return a?{Logical:a}:null}return p("plugin:window|set_size_constraints",{label:this.label,value:{minWidth:n(t?.minWidth),minHeight:n(t?.minHeight),maxWidth:n(t?.maxWidth),maxHeight:n(t?.maxHeight)}})}async setPosition(t){return p("plugin:window|set_position",{label:this.label,value:t instanceof Xe?t:new Xe(t)})}async setFullscreen(t){return p("plugin:window|set_fullscreen",{label:this.label,value:t})}async setSimpleFullscreen(t){return p("plugin:window|set_simple_fullscreen",{label:this.label,value:t})}async setFocus(){return p("plugin:window|set_focus",{label:this.label})}async setFocusable(t){return p("plugin:window|set_focusable",{label:this.label,value:t})}async setIcon(t){return p("plugin:window|set_icon",{label:this.label,value:pt(t)})}async setSkipTaskbar(t){return p("plugin:window|set_skip_taskbar",{label:this.label,value:t})}async setCursorGrab(t){return p("plugin:window|set_cursor_grab",{label:this.label,value:t})}async setCursorVisible(t){return p("plugin:window|set_cursor_visible",{label:this.label,value:t})}async setCursorIcon(t){return p("plugin:window|set_cursor_icon",{label:this.label,value:t})}async setBackgroundColor(t){return p("plugin:window|set_background_color",{color:t})}async setCursorPosition(t){return p("plugin:window|set_cursor_position",{label:this.label,value:t instanceof Xe?t:new Xe(t)})}async setIgnoreCursorEvents(t){return p("plugin:window|set_ignore_cursor_events",{label:this.label,value:t})}async startDragging(){return p("plugin:window|start_dragging",{label:this.label})}async startResizeDragging(t){return p("plugin:window|start_resize_dragging",{label:this.label,value:t})}async setBadgeCount(t){return p("plugin:window|set_badge_count",{label:this.label,value:t})}async setBadgeLabel(t){return p("plugin:window|set_badge_label",{label:this.label,value:t})}async setOverlayIcon(t){return p("plugin:window|set_overlay_icon",{label:this.label,value:t?pt(t):void 0})}async setProgressBar(t){return p("plugin:window|set_progress_bar",{label:this.label,value:t})}async setVisibleOnAllWorkspaces(t){return p("plugin:window|set_visible_on_all_workspaces",{label:this.label,value:t})}async setTitleBarStyle(t){return p("plugin:window|set_title_bar_style",{label:this.label,value:t})}async setTheme(t){return p("plugin:window|set_theme",{label:this.label,value:t})}async onResized(t){return this.listen(j.WINDOW_RESIZED,n=>{n.payload=new $e(n.payload),t(n)})}async onMoved(t){return this.listen(j.WINDOW_MOVED,n=>{n.payload=new ge(n.payload),t(n)})}async onCloseRequested(t){return this.listen(j.WINDOW_CLOSE_REQUESTED,async n=>{const a=new iu(n);await t(a),a.isPreventDefault()||await this.destroy()})}async onDragDropEvent(t){const n=await this.listen(j.DRAG_ENTER,i=>{t({...i,payload:{type:"enter",paths:i.payload.paths,position:new ge(i.payload.position)}})}),a=await this.listen(j.DRAG_OVER,i=>{t({...i,payload:{type:"over",position:new ge(i.payload.position)}})}),r=await this.listen(j.DRAG_DROP,i=>{t({...i,payload:{type:"drop",paths:i.payload.paths,position:new ge(i.payload.position)}})}),u=await this.listen(j.DRAG_LEAVE,i=>{t({...i,payload:{type:"leave"}})});return()=>{n(),r(),a(),u()}}async onFocusChanged(t){const n=await this.listen(j.WINDOW_FOCUS,r=>{t({...r,payload:!0})}),a=await this.listen(j.WINDOW_BLUR,r=>{t({...r,payload:!1})});return()=>{n(),a()}}async onScaleChanged(t){return this.listen(j.WINDOW_SCALE_FACTOR_CHANGED,t)}async onThemeChanged(t){return this.listen(j.WINDOW_THEME_CHANGED,t)}}var hn;(function(e){e.Disabled="disabled",e.Throttle="throttle",e.Suspend="suspend"})(hn||(hn={}));var mn;(function(e){e.Default="default",e.FluentOverlay="fluentOverlay"})(mn||(mn={}));var Cn;(function(e){e.AppearanceBased="appearanceBased",e.Light="light",e.Dark="dark",e.MediumLight="mediumLight",e.UltraDark="ultraDark",e.Titlebar="titlebar",e.Selection="selection",e.Menu="menu",e.Popover="popover",e.Sidebar="sidebar",e.HeaderView="headerView",e.Sheet="sheet",e.WindowBackground="windowBackground",e.HudWindow="hudWindow",e.FullScreenUI="fullScreenUI",e.Tooltip="tooltip",e.ContentBackground="contentBackground",e.UnderWindowBackground="underWindowBackground",e.UnderPageBackground="underPageBackground",e.Mica="mica",e.Blur="blur",e.Acrylic="acrylic",e.Tabbed="tabbed",e.TabbedDark="tabbedDark",e.TabbedLight="tabbedLight"})(Cn||(Cn={}));var bn;(function(e){e.FollowsWindowActiveState="followsWindowActiveState",e.Active="active",e.Inactive="inactive"})(bn||(bn={}));async function ou(e){await p("plugin:drpc|spawn_thread",{id:e})}async function su(){await p("plugin:drpc|destroy_thread")}async function lu(){return await p("plugin:drpc|is_running")}async function cu(e){await du(),await ou(e)}async function du(){await lu()&&await su()}async function na(e){await p("plugin:drpc|set_activity",{activityJson:e.toString()})}class pu{constructor(t,n){this.start=t,this.end=n}}class Du{setLargeImage(t){return this.large_image=t,this}setLargeText(t){return this.large_text=t,this}setSmallImage(t){return this.small_image=t,this}setSmallText(t){return this.small_text=t,this}}class wn{constructor(t,n){this.label=t,this.url=n}}class gu{setState(t){return this.state=t,this}setDetails(t){return this.details=t,this}setTimestamps(t){return this.timestamps=t,this}setParty(t){return this.party=t,this}setAssets(t){return this.assets=t,this}setSecrets(t){return this.secrets=t,this}setButton(t){return this.buttons=t,this}setActivity(t){return this.activity_type=t,this}toString(){return JSON.stringify(this)}}const Ne=ea(),fu="0.8.2",z={fullScreenStatus:!1,fullScreen:async()=>await z.isFullscreen()?z.exitFullscreen():z.enterFullscreen(),isFullscreen:()=>z.fullScreenStatus,enterFullscreen:async()=>(z.fullScreenStatus=!0,Ne.setFullscreen(!0)),exitFullscreen:async()=>(z.fullScreenStatus=!1,Ne.setFullscreen(!1)),center:async()=>Ne.center(),setSize:async(e,t)=>await Ne.isMaximized()||await z.isFullscreen()?!1:Ne.setSize(new Xt(Number(e),Number(t))),openDevTools:async()=>p("open_devtools"),ipcRenderer:{send:async function(e,...t){switch(e){case"e_isFullScreen":return z.isFullscreen();case"e_fullScreen":return z.fullScreen();case"e_window":return z.exitFullscreen();case"e_quit":return Ne.close();case"e_center":return z.center();case"e_setSize":return z.setSize(t[0],t[1]);case"e_openDevTools":return z.openDevTools();case"e_openURL":return z.shell.openExternal(t[0])}},sendSync:function(e,t){switch(e){case"e_isFullScreen":return z.isFullscreen()}},on:function(e,t){}},shell:{openExternal:async function(e){return Zn(e)}}},hu=new Du().setLargeImage("pvzge_logo").setLargeText("PvZ2 Gardendless").setSmallImage("pvzge_logo").setSmallText("PvZ2 Gardendless"),at=new gu().setButton([new wn("Download","https://pvzge.com"),new wn("Join Server","https://discord.gg/ZEfb2tBQFW")]).setDetails("Playing version "+fu).setAssets(hu).setTimestamps(new pu(Date.now())),mu=async(e,t="")=>{at.setState(e),t&&at.setDetails(t),await na(at)};await cu("1354392876724785243");await na(at);window.electron=z;const Cu=Object.freeze(Object.defineProperty({__proto__:null,updateActivity:mu},Symbol.toStringTag,{value:"Module"}));export{Pu as A,Eu as B,yu as C,Ar as D,mr as E,Fe as F,te as G,Cr as H,br as I,wr as J,yr as K,$t as L,fr as M,Sn as O,fe as V,xa as a,Su as b,Bu as c,ku as d,it as e,Oa as f,Fr as g,vu as h,_u as i,vr as j,Nu as k,Tu as l,Bn as m,xu as n,Lu as o,Au as p,jt as q,$n as r,V as s,w as t,bu as u,wu as v,xn as w,Ca as x,ha as y,Fu as z};
