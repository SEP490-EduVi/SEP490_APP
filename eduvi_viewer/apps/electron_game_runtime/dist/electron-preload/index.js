"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const electron_1 = require("electron");
const api = {
    readLaunchContract: () => electron_1.ipcRenderer.invoke('eduvi:readLaunchContract'),
    readSourceEduvi: () => electron_1.ipcRenderer.invoke('eduvi:readSourceEduvi'),
    saveProgressSnapshot: (payload) => electron_1.ipcRenderer.invoke('eduvi:saveProgressSnapshot', payload),
    saveGameResult: (payload) => electron_1.ipcRenderer.invoke('eduvi:saveGameResult', payload),
};
electron_1.contextBridge.exposeInMainWorld('eduviGameApi', api);
