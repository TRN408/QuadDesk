const {contextBridge, ipcRenderer} = require('electron');
contextBridge.exposeInMainWorld('probe', {record:(kind, fields)=>ipcRenderer.send('probe-event',kind,fields)});
