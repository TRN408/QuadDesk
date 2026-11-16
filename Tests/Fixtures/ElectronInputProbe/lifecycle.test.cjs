const {test} = require('node:test');
const assert = require('node:assert/strict');
const {EventEmitter} = require('node:events');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

async function fixture() {
  const windows = [], records = [];
  class Window extends EventEmitter {
    constructor(options) {
      super(); this.options = options; this.destroyed = false; this.shown = false;
      this.sender = {isDestroyed: () => this.destroyed}; windows.push(this);
    }
    isDestroyed() { return this.destroyed; }
    get webContents() { assert.equal(this.destroyed, false, 'destroyed webContents must not be accessed'); return this.sender; }
    getTitle() { assert.equal(this.destroyed, false); return this.options.title; }
    isFocused() { assert.equal(this.destroyed, false); return true; }
    loadURL() {}
    show() { assert.equal(this.destroyed, false, 'destroyed window must not be shown'); this.shown = true; }
    close() { this.destroyed = true; this.emit('closed'); }
  }
  const app = new EventEmitter(), ipcMain = new EventEmitter();
  app.whenReady = () => Promise.resolve(); app.quit = () => {};
  const electron = {app, ipcMain, BrowserWindow: Window, Menu: {setApplicationMenu() {}, buildFromTemplate: x => x}};
  const source = fs.readFileSync(path.join(__dirname, 'main.cjs'), 'utf8');
  vm.runInNewContext(source, {
    require: name => name === 'electron' ? electron : name === 'node:fs'
      ? {appendFileSync: (_path, line) => records.push(JSON.parse(line))} : require(name),
    __dirname, process: {pid: 123},
  });
  await Promise.resolve();
  return {windows, records, app, send: (sender, kind = 'heartbeat', data = {}) => ipcMain.emit('probe-event', {sender}, kind, data)};
}

test('closing the first window does not break heartbeats from the second', async () => {
  const f = await fixture(); f.windows[0].close();
  for (let n = 0; n < 5; n++) f.send(f.windows[1].sender);
  assert.equal(f.records.length, 5);
  assert.ok(f.records.every(r => r.window === 'QuadDesk Electron Probe B'));
});
test('a destroyed entry is skipped even if closed cleanup has not run', async () => {
  const f = await fixture(); f.windows[0].destroyed = true;
  f.send(f.windows[1].sender); assert.equal(f.records.length, 1);
});
test('late IPC from a destroyed sender is ignored', async () => {
  const f = await fixture(); const sender = f.windows[0].sender;
  f.windows[0].close(); f.send(sender); assert.equal(f.records.length, 0);
});
test('unknown senders and invalid event kinds are ignored', async () => {
  const f = await fixture(); f.send({isDestroyed: () => false}); f.send(f.windows[0].sender, 42);
  assert.equal(f.records.length, 0);
});
test('closing before ready-to-show never shows a destroyed window', async () => {
  const f = await fixture(); f.windows[0].close(); f.windows[0].emit('ready-to-show');
  assert.equal(f.windows[0].shown, false);
  f.windows[1].emit('ready-to-show'); assert.equal(f.windows[1].shown, true);
});
test('shutdown ignores remaining IPC without writing private text', async () => {
  const f = await fixture();
  f.send(f.windows[0].sender, 'input', {length: 3, text: 'not recorded'});
  assert.equal(f.records[0].length, 3); assert.equal('text' in f.records[0], false);
  f.app.emit('before-quit'); f.send(f.windows[0].sender); assert.equal(f.records.length, 1);
});
