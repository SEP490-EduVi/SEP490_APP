import { contextBridge, ipcRenderer } from 'electron';

import { EduviGameApi } from './game-api';

const api: EduviGameApi = {
  readLaunchContract: () => ipcRenderer.invoke('eduvi:readLaunchContract'),
  readSourceEduvi: () => ipcRenderer.invoke('eduvi:readSourceEduvi'),
  saveProgressSnapshot: (payload: unknown) =>
    ipcRenderer.invoke('eduvi:saveProgressSnapshot', payload),
  saveGameResult: (payload: unknown) =>
    ipcRenderer.invoke('eduvi:saveGameResult', payload),
};

contextBridge.exposeInMainWorld('eduviGameApi', api);
