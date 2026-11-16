// Receives events only inside two test windows; never generates native input.
const {app, BrowserWindow, ipcMain, Menu} = require('electron');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
let sequence = 0;
const windows = new Set();
const logPath = path.join(os.tmpdir(), 'quaddesk-electron-probe.jsonl');
function record(window, kind, fields = {}) {
  if (!window || window.isDestroyed()) return;
  fs.appendFileSync(logPath, JSON.stringify({sequence: ++sequence, time: Date.now(), pid: process.pid,
    window: window.getTitle(), active: window.isFocused(), kind, ...fields}) + '\n');
}
ipcMain.on('probe-event', (event, kind, data) => {
  if (!event.sender || event.sender.isDestroyed()) return;
  const window = [...windows].find(w => !w.isDestroyed() && w.webContents === event.sender);
  if (!window || typeof kind !== 'string') return;
  const fields = {};
  for (const key of ['trusted','x','y','clicks','length','scrollY','focused']) {
    if (['number','boolean','string'].includes(typeof data?.[key])) fields[key] = data[key];
  }
  record(window, kind, fields);
});
app.whenReady().then(() => {
  Menu.setApplicationMenu(Menu.buildFromTemplate([{label:'Input Probe', submenu:[{role:'quit'}]}]));
  for (const [index, name] of ['A', 'B'].entries()) {
    const window = new BrowserWindow({title:`QuadDesk Electron Probe ${name}`, x:160+index*40,
      y:140+index*40, width:840, height:608, show:false,
      titleBarStyle:index ? 'hiddenInset' : 'default',
      webPreferences:{preload:path.join(__dirname,'preload.cjs'), contextIsolation:true, sandbox:true}});
    windows.add(window);
    window.once('closed', () => windows.delete(window));
    const html = `<!doctype html><meta charset="utf-8"><title>QuadDesk Electron Probe ${name}</title>
<style>body{margin:0;font:20px system-ui;background:#eff7ff;color:#182331}header{position:sticky;top:0;background:#cee5ff;padding:16px 16px 16px 84px;display:flex;gap:20px;align-items:center}button,input{font:inherit;padding:10px}#space{padding:20px}p{height:40px}</style>
<header><b id="beat">Heartbeat 0</b><button id="toggle">Clicks: 0</button><input id="edit" placeholder="Click here, then type"></header>
<div id="space"></div><script>
let beat=0, clicks=0;
const snapshot=()=>({clicks,length:edit.value.length,scrollY:window.scrollY,focused:document.activeElement?.id||''});
const send=(kind,fields={})=>window.probe.record(kind,{...snapshot(),...fields});
space.innerHTML=Array.from({length:150},(_,i)=>'<p>Independent Electron scroll line '+(i+1)+'</p>').join('');
setInterval(()=>{document.getElementById('beat').textContent='Heartbeat '+(++beat);if(beat%4===0)send('heartbeat')},500);
for(const type of ['mousemove','mousedown','mouseup','click','wheel']) document.addEventListener(type,e=>send(type,{trusted:e.isTrusted,x:e.clientX,y:e.clientY}),true);
toggle.onclick=()=>{toggle.textContent='Clicks: '+(++clicks);send('toggle')};
edit.oninput=e=>send('input',{trusted:e.isTrusted});
window.addEventListener('scroll',()=>send('scroll'));
window.addEventListener('focus',()=>send('focus'));
window.addEventListener('blur',()=>send('blur'));
</script>`;
    window.loadURL('data:text/html;charset=utf-8,'+encodeURIComponent(html));
    window.once('ready-to-show',()=>{ if (!window.isDestroyed()) window.show(); });
  }
});
app.on('window-all-closed',()=>app.quit());
app.on('before-quit',()=>windows.clear());
