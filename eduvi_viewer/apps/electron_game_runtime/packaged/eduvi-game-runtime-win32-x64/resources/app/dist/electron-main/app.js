"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const electron_1 = require("electron");
const node_fs_1 = require("node:fs");
const node_path_1 = require("node:path");
const node_url_1 = require("node:url");
const launch_contract_reader_1 = require("./launch-contract-reader");
const package_runtime_loader_1 = require("./package-runtime-loader");
const storage_writer_1 = require("./storage-writer");
let mainWindow = null;
let launchContractPath = '';
let launchContract;
function readSourceEduviPayload() {
    const sourcePath = (0, node_path_1.resolve)(launchContract.packagePath, 'source.eduvi');
    if (!(0, node_fs_1.existsSync)(sourcePath)) {
        return null;
    }
    try {
        const raw = (0, node_fs_1.readFileSync)(sourcePath, 'utf8');
        const parsed = JSON.parse(raw);
        if (parsed && typeof parsed === 'object') {
            return parsed;
        }
        return null;
    }
    catch {
        return null;
    }
}
function blockNetworkAccess() {
    electron_1.session.defaultSession.webRequest.onBeforeRequest((details, callback) => {
        if (details.url.startsWith('http://') || details.url.startsWith('https://')) {
            callback({ cancel: true });
            return;
        }
        callback({});
    });
}
function createWindow() {
    const preloadPath = (0, node_path_1.resolve)(__dirname, '../electron-preload/index.js');
    const window = new electron_1.BrowserWindow({
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
    const bundledRuntimeEntry = (0, node_path_1.resolve)(__dirname, '../../mediapipe-runtime/web-runtime/index.html');
    const runtimeEntry = (0, package_runtime_loader_1.resolveRuntimeEntry)(launchContract, bundledRuntimeEntry);
    const runtimeUrl = `${(0, node_url_1.pathToFileURL)(runtimeEntry).toString()}?contract=${encodeURIComponent(launchContractPath)}`;
    void window.loadURL(runtimeUrl);
    window.once('ready-to-show', () => window.show());
    return window;
}
function wireIpcHandlers() {
    electron_1.ipcMain.handle('eduvi:readLaunchContract', async () => launchContract);
    electron_1.ipcMain.handle('eduvi:readSourceEduvi', async () => readSourceEduviPayload());
    electron_1.ipcMain.handle('eduvi:saveProgressSnapshot', async (_event, payload) => {
        (0, storage_writer_1.writeProgressSnapshot)(launchContract.outputDir, payload);
        return { ok: true };
    });
    electron_1.ipcMain.handle('eduvi:saveGameResult', async (_event, payload) => {
        (0, storage_writer_1.writeGameResult)(launchContract.outputDir, payload);
        return { ok: true };
    });
}
async function bootstrap() {
    launchContractPath = (0, launch_contract_reader_1.extractLaunchContractPath)(process.argv);
    launchContract = (0, launch_contract_reader_1.readLaunchContract)(launchContractPath);
    await electron_1.app.whenReady();
    blockNetworkAccess();
    wireIpcHandlers();
    mainWindow = createWindow();
    electron_1.app.on('activate', () => {
        if (electron_1.BrowserWindow.getAllWindows().length === 0) {
            mainWindow = createWindow();
        }
    });
}
electron_1.app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') {
        electron_1.app.quit();
    }
});
void bootstrap();
