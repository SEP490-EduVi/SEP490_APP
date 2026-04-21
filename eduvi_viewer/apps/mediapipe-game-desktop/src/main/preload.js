const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  getAppVersion: () => ipcRenderer.invoke('get-app-version'),
  toggleFullscreen: () => ipcRenderer.invoke('toggle-fullscreen'),
  getLaunchContract: () => ipcRenderer.invoke('get-launch-contract'),
  readSourceEduvi: () => ipcRenderer.invoke('read-source-eduvi'),
  saveGameResult: (result) => ipcRenderer.invoke('save-game-result', result),
  saveProgressSnapshot: (data) => ipcRenderer.invoke('save-progress-snapshot', data),
  getLocalMediaPipePaths: () => ipcRenderer.invoke('get-mediapipe-paths'),
  closeApp: () => ipcRenderer.invoke('close-app'),
});
