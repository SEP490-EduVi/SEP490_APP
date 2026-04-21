const { app, BrowserWindow, Menu, ipcMain, session, dialog } = require('electron');
const path = require('path');
const fs = require('fs');

let mainWindow = null;
let launchContract = null;

// Allow renderer loaded from file:// to fetch local MediaPipe wasm/model assets.
app.commandLine.appendSwitch('allow-file-access-from-files');

function readSourceEduviPayload() {
  if (!launchContract || !launchContract.packagePath) {
    return null;
  }

  const sourcePath = path.resolve(launchContract.packagePath, 'source.eduvi');
  if (!fs.existsSync(sourcePath)) {
    return null;
  }

  try {
    const raw = fs.readFileSync(sourcePath, 'utf-8');
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === 'object') {
      return parsed;
    }
    return null;
  } catch {
    return null;
  }
}

// ── CLI parsing ──────────────────────────────────────────────────────────────
function parseLaunchContract() {
  const args = process.argv.slice(1);
  for (const arg of args) {
    const match = arg.match(/^--launch-contract=(.+)$/);
    if (match) {
      const contractPath = path.resolve(match[1]);
      try {
        const raw = fs.readFileSync(contractPath, 'utf-8');
        launchContract = JSON.parse(raw);
        launchContract._contractPath = contractPath;
        console.log('[Main] Loaded launch contract:', contractPath);
      } catch (err) {
        console.error('[Main] Failed to read launch contract:', err.message);
      }
    }
  }
}

// ── Window creation ──────────────────────────────────────────────────────────
function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 1024,
    minHeight: 768,
    title: 'EduVi Game',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: false,
      preload: path.join(__dirname, 'preload.js'),
    },
  });

  mainWindow.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

// ── Camera permissions ───────────────────────────────────────────────────────
function setupPermissions() {
  session.defaultSession.setPermissionRequestHandler((webContents, permission, callback) => {
    const allowed = ['media', 'mediaKeySystem'];
    callback(allowed.includes(permission));
  });
}

// ── Menu ─────────────────────────────────────────────────────────────────────
function buildMenu() {
  const template = [
    {
      label: 'File',
      submenu: [
        {
          label: 'Thoát',
          accelerator: 'CmdOrCtrl+Q',
          click: () => app.quit(),
        },
      ],
    },
    {
      label: 'View',
      submenu: [
        {
          label: 'Toàn màn hình',
          accelerator: 'F11',
          click: () => {
            if (mainWindow) {
              mainWindow.setFullScreen(!mainWindow.isFullScreen());
            }
          },
        },
        { type: 'separator' },
        {
          label: 'DevTools',
          accelerator: 'CmdOrCtrl+Shift+I',
          click: () => {
            if (mainWindow) {
              mainWindow.webContents.toggleDevTools();
            }
          },
        },
      ],
    },
    {
      label: 'Help',
      submenu: [
        {
          label: 'About',
          click: () => {
            dialog.showMessageBox(mainWindow, {
              type: 'info',
              title: 'EduVi Game',
              message: `EduVi MediaPipe Game Player\nVersion ${app.getVersion()}`,
            });
          },
        },
      ],
    },
  ];

  const menu = Menu.buildFromTemplate(template);
  Menu.setApplicationMenu(menu);
}

// ── MediaPipe local paths ────────────────────────────────────────────────────
function getMediaPipePaths() {
  const isPackaged = app.isPackaged;
  let baseDir;

  if (isPackaged) {
    baseDir = path.join(process.resourcesPath, 'mediapipe');
  } else {
    baseDir = path.join(__dirname, '..', '..', 'assets', 'mediapipe');
  }

  const wasmDir = path.join(baseDir, 'wasm');
  const modelPath = path.join(baseDir, 'models', 'hand_landmarker.task');

  // Convert to file:// URLs
  const wasmBaseUrl = 'file:///' + wasmDir.replace(/\\/g, '/');
  const modelUrl = 'file:///' + modelPath.replace(/\\/g, '/');

  return { wasmBaseUrl, modelUrl };
}

// ── IPC handlers ─────────────────────────────────────────────────────────────
function registerIPC() {
  ipcMain.handle('get-app-version', () => app.getVersion());

  ipcMain.handle('toggle-fullscreen', () => {
    if (mainWindow) {
      mainWindow.setFullScreen(!mainWindow.isFullScreen());
      return mainWindow.isFullScreen();
    }
    return false;
  });

  ipcMain.handle('get-launch-contract', () => launchContract);
  ipcMain.handle('read-source-eduvi', () => readSourceEduviPayload());

  ipcMain.handle('save-game-result', async (_event, result) => {
    if (!launchContract || !launchContract.outputDir) {
      console.warn('[Main] No contract outputDir, skipping save-game-result');
      return false;
    }
    try {
      const outputDir = path.resolve(launchContract.outputDir);
      if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
      }
      const filePath = path.join(outputDir, 'game.result.json');
      fs.writeFileSync(filePath, JSON.stringify(result, null, 2), 'utf-8');
      console.log('[Main] Saved game result to:', filePath);
      return true;
    } catch (err) {
      console.error('[Main] Failed to save game result:', err.message);
      return false;
    }
  });

  ipcMain.handle('save-progress-snapshot', async (_event, data) => {
    if (!launchContract || !launchContract.outputDir) {
      console.warn('[Main] No contract outputDir, skipping save-progress-snapshot');
      return false;
    }
    try {
      const outputDir = path.resolve(launchContract.outputDir);
      if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
      }
      const filePath = path.join(outputDir, 'progress.snapshot.json');
      fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf-8');
      return true;
    } catch (err) {
      console.error('[Main] Failed to save progress snapshot:', err.message);
      return false;
    }
  });

  ipcMain.handle('get-mediapipe-paths', () => getMediaPipePaths());

  ipcMain.handle('close-app', () => {
    setTimeout(() => app.quit(), 0);
    return true;
  });
}

// ── App lifecycle ────────────────────────────────────────────────────────────
parseLaunchContract();

app.whenReady().then(() => {
  setupPermissions();
  buildMenu();
  registerIPC();
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on('window-all-closed', () => {
  app.quit();
});
