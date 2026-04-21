import { app, BrowserWindow, ipcMain, session } from 'electron';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

import {
  extractLaunchContractPath,
  readLaunchContract,
  LaunchContract,
} from './launch-contract-reader';
import { resolveRuntimeEntry } from './package-runtime-loader';
import { writeGameResult, writeProgressSnapshot } from './storage-writer';

let mainWindow: BrowserWindow | null = null;
let launchContractPath = '';
let launchContract: LaunchContract;

function readSourceEduviPayload(): Record<string, unknown> | null {
  const sourcePath = resolve(launchContract.packagePath, 'source.eduvi');
  if (!existsSync(sourcePath)) {
    return null;
  }

  try {
    const raw = readFileSync(sourcePath, 'utf8');
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === 'object') {
      return parsed as Record<string, unknown>;
    }
    return null;
  } catch {
    return null;
  }
}

function blockNetworkAccess(): void {
  session.defaultSession.webRequest.onBeforeRequest((details, callback) => {
    if (details.url.startsWith('http://') || details.url.startsWith('https://')) {
      callback({ cancel: true });
      return;
    }
    callback({});
  });
}

function createWindow(): BrowserWindow {
  const preloadPath = resolve(__dirname, '../electron-preload/index.js');

  const window = new BrowserWindow({
    width: 1280,
    height: 768,
    show: false,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      preload: preloadPath,
    },
  });

  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  window.webContents.on('will-navigate', (event, targetUrl) => {
    if (targetUrl.startsWith('http://') || targetUrl.startsWith('https://')) {
      event.preventDefault();
    }
  });

  const bundledRuntimeEntry = resolve(
    __dirname,
    '../../mediapipe-runtime/web-runtime/index.html',
  );

  const runtimeEntry = resolveRuntimeEntry(launchContract, bundledRuntimeEntry);
  const runtimeUrl = `${pathToFileURL(runtimeEntry).toString()}?contract=${encodeURIComponent(
    launchContractPath,
  )}`;

  void window.loadURL(runtimeUrl);
  window.once('ready-to-show', () => window.show());

  return window;
}

function wireIpcHandlers(): void {
  ipcMain.handle('eduvi:readLaunchContract', async () => launchContract);

  ipcMain.handle('eduvi:readSourceEduvi', async () => readSourceEduviPayload());

  ipcMain.handle('eduvi:saveProgressSnapshot', async (_event, payload: unknown) => {
    writeProgressSnapshot(launchContract.outputDir, payload);
    return { ok: true };
  });

  ipcMain.handle('eduvi:saveGameResult', async (_event, payload: unknown) => {
    writeGameResult(launchContract.outputDir, payload);
    return { ok: true };
  });
}

async function bootstrap(): Promise<void> {
  launchContractPath = extractLaunchContractPath(process.argv);
  launchContract = readLaunchContract(launchContractPath);

  await app.whenReady();
  blockNetworkAccess();
  wireIpcHandlers();
  mainWindow = createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      mainWindow = createWindow();
    }
  });
}

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

void bootstrap();
