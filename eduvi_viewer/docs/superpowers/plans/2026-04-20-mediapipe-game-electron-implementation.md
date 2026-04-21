# MediaPipe Game Electron App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Electron app hosting 6 MediaPipe game blueprints (10 vanilla JS files) and integrate GAME blocks into the Flutter slide viewer, all working offline.

**Architecture:** Flutter shell (slides) launches Electron process (games) via file-based launch contract. Electron app has standalone mode (game launcher UI) and contract mode (auto-start from Flutter). MediaPipe WASM + model bundled locally for offline camera games.

**Tech Stack:** Electron 28+, vanilla JS (ES Modules), Canvas 2D, MediaPipe tasks-vision, Flutter (existing), electron-builder (packaging)

---

## File Structure

### New files (Electron app)

| File | Responsibility |
|------|---------------|
| `apps/mediapipe-game-desktop/package.json` | Electron project config, dependencies, scripts |
| `apps/mediapipe-game-desktop/electron-builder.yml` | Build/packaging config for Windows |
| `apps/mediapipe-game-desktop/src/main/main.js` | Electron main process: window, permissions, IPC, contract reading |
| `apps/mediapipe-game-desktop/src/main/preload.js` | Context bridge: expose safe APIs to renderer |
| `apps/mediapipe-game-desktop/src/renderer/index.html` | Host HTML page |
| `apps/mediapipe-game-desktop/src/renderer/renderer.js` | Game launcher UI + engine initialization |
| `apps/mediapipe-game-desktop/src/renderer/styles.css` | Game launcher + game UI styling |
| `apps/mediapipe-game-desktop/src/renderer/game/*.js` | 8 game JS files copied from web FE |

### New files (Flutter integration)

| File | Responsibility |
|------|---------------|
| `lib/features/game_player/game_block_widget.dart` | Widget rendering GAME blocks in slides |
| `lib/features/game_player/mediapipe_game_launcher.dart` | Launch Electron game from block content or package |

### Modified files

| File | Change |
|------|--------|
| `lib/widgets/blocks/block_dispatcher.dart` | Add `GAME` case to switch |
| `lib/features/offline_core/services/electron_launcher_service.dart` | Add game-runtime path candidates |

---

## Task 1: Initialize Electron Project

**Files:**
- Create: `apps/mediapipe-game-desktop/package.json`
- Create: `apps/mediapipe-game-desktop/.gitignore`

- [ ] **Step 1: Create project directory and package.json**

```json
{
  "name": "mediapipe-game-desktop",
  "version": "1.0.0",
  "description": "EduVi MediaPipe Game Player - Offline Desktop",
  "main": "src/main/main.js",
  "scripts": {
    "start": "electron .",
    "start:contract": "electron . --launch-contract=test-contract.json",
    "package": "electron-builder --win portable",
    "dist": "electron-builder --win"
  },
  "devDependencies": {
    "electron": "^28.0.0",
    "electron-builder": "^24.0.0"
  },
  "build": {
    "appId": "com.eduvi.game",
    "productName": "EduVi Game",
    "directories": {
      "output": "dist"
    },
    "win": {
      "target": ["portable"],
      "icon": "assets/icon.ico"
    },
    "files": [
      "src/**/*",
      "assets/**/*"
    ],
    "extraResources": [
      {
        "from": "assets/mediapipe",
        "to": "mediapipe"
      }
    ]
  }
}
```

- [ ] **Step 2: Create .gitignore**

```
node_modules/
dist/
assets/mediapipe/wasm/
assets/mediapipe/models/
*.log
```

- [ ] **Step 3: Install dependencies**

Run: `cd apps/mediapipe-game-desktop && npm install`
Expected: `node_modules/` created with electron and electron-builder

- [ ] **Step 4: Commit**

```bash
git add apps/mediapipe-game-desktop/package.json apps/mediapipe-game-desktop/.gitignore
git commit -m "feat(game-desktop): initialize Electron project"
```

---

## Task 2: Electron Main Process

**Files:**
- Create: `apps/mediapipe-game-desktop/src/main/main.js`
- Create: `apps/mediapipe-game-desktop/src/main/preload.js`

- [ ] **Step 1: Create main.js**

```javascript
const { app, BrowserWindow, ipcMain, session, Menu } = require('electron');
const path = require('path');
const fs = require('fs');

let mainWindow = null;
let launchContract = null;

// Parse CLI for --launch-contract=<path>
function parseLaunchContract() {
  const contractArg = process.argv.find(a => a.startsWith('--launch-contract='));
  if (!contractArg) return null;

  const contractPath = contractArg.split('=')[1];
  if (!contractPath || !fs.existsSync(contractPath)) {
    console.error('Launch contract file not found:', contractPath);
    return null;
  }

  try {
    const raw = fs.readFileSync(contractPath, 'utf-8');
    return JSON.parse(raw);
  } catch (err) {
    console.error('Failed to parse launch contract:', err);
    return null;
  }
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 1024,
    minHeight: 768,
    title: 'EduVi Game',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));

  // Camera permission
  session.defaultSession.setPermissionRequestHandler((webContents, permission, callback) => {
    if (permission === 'media') {
      callback(true);
    } else {
      callback(false);
    }
  });

  // Menu
  const menuTemplate = [
    {
      label: 'File',
      submenu: [{ role: 'quit', label: 'Thoát' }],
    },
    {
      label: 'View',
      submenu: [
        { role: 'togglefullscreen', label: 'Toàn màn hình' },
        { role: 'toggleDevTools', label: 'Developer Tools' },
      ],
    },
    {
      label: 'Help',
      submenu: [
        {
          label: 'About EduVi Game',
          click: () => {
            const { dialog } = require('electron');
            dialog.showMessageBox(mainWindow, {
              type: 'info',
              title: 'EduVi Game',
              message: `EduVi Game Player v${app.getVersion()}`,
              detail: 'Game giáo dục tương tác - MediaPipe + Canvas 2D',
            });
          },
        },
      ],
    },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(menuTemplate));
}

// IPC handlers
ipcMain.handle('get-app-version', () => app.getVersion());

ipcMain.handle('toggle-fullscreen', () => {
  if (mainWindow) {
    mainWindow.setFullScreen(!mainWindow.isFullScreen());
  }
});

ipcMain.handle('get-launch-contract', () => launchContract);

ipcMain.handle('save-game-result', async (_event, result) => {
  if (!launchContract || !launchContract.outputDir) return false;
  try {
    const outputDir = launchContract.outputDir;
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }
    const resultPath = path.join(outputDir, 'game.result.json');
    fs.writeFileSync(resultPath, JSON.stringify(result, null, 2), 'utf-8');
    return true;
  } catch (err) {
    console.error('Failed to save game result:', err);
    return false;
  }
});

ipcMain.handle('save-progress-snapshot', async (_event, data) => {
  if (!launchContract || !launchContract.outputDir) return false;
  try {
    const outputDir = launchContract.outputDir;
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }
    const snapshotPath = path.join(outputDir, 'progress.snapshot.json');
    fs.writeFileSync(snapshotPath, JSON.stringify(data, null, 2), 'utf-8');
    return true;
  } catch (err) {
    console.error('Failed to save progress snapshot:', err);
    return false;
  }
});

ipcMain.handle('get-mediapipe-paths', () => {
  // In packaged app, extraResources are at process.resourcesPath/mediapipe/
  // In dev mode, at assets/mediapipe/
  const resourceBase = app.isPackaged
    ? path.join(process.resourcesPath, 'mediapipe')
    : path.join(__dirname, '..', '..', 'assets', 'mediapipe');

  return {
    wasmBaseUrl: `file:///${resourceBase.replace(/\\/g, '/')}/wasm`,
    modelUrl: `file:///${resourceBase.replace(/\\/g, '/')}/models/hand_landmarker.task`,
  };
});

app.whenReady().then(() => {
  launchContract = parseLaunchContract();
  createWindow();
});

app.on('window-all-closed', () => {
  app.quit();
});
```

- [ ] **Step 2: Create preload.js**

```javascript
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  getAppVersion: () => ipcRenderer.invoke('get-app-version'),
  toggleFullscreen: () => ipcRenderer.invoke('toggle-fullscreen'),
  getLaunchContract: () => ipcRenderer.invoke('get-launch-contract'),
  saveGameResult: (result) => ipcRenderer.invoke('save-game-result', result),
  saveProgressSnapshot: (data) => ipcRenderer.invoke('save-progress-snapshot', data),
  getLocalMediaPipePaths: () => ipcRenderer.invoke('get-mediapipe-paths'),
});
```

- [ ] **Step 3: Verify Electron launches**

Run: `cd apps/mediapipe-game-desktop && npx electron .`
Expected: Empty Electron window opens with title "EduVi Game", menu bar visible. Close it.

- [ ] **Step 4: Commit**

```bash
git add apps/mediapipe-game-desktop/src/main/
git commit -m "feat(game-desktop): Electron main process + preload bridge"
```

---

## Task 3: Copy Game JS Files

**Files:**
- Create: `apps/mediapipe-game-desktop/src/renderer/game/api-contracts.js`
- Create: `apps/mediapipe-game-desktop/src/renderer/game/mediapipe-engine.js`
- Create: `apps/mediapipe-game-desktop/src/renderer/game/keyboard-input.js`
- Create: `apps/mediapipe-game-desktop/src/renderer/game/dual-keyboard-input.js`
- Create: `apps/mediapipe-game-desktop/src/renderer/game/runner-quiz-game.js`
- Create: `apps/mediapipe-game-desktop/src/renderer/game/snake-quiz-game.js`
- Create: `apps/mediapipe-game-desktop/src/renderer/game/runner-race-game.js`
- Create: `apps/mediapipe-game-desktop/src/renderer/game/snake-duel-game.js`

- [ ] **Step 1: Copy 8 game JS files from web frontend**

Run the following commands to copy files:

```powershell
$src = "D:\2026\SEP490-FE\SEP490_FE\src\mediapipe-game"
$dst = "apps\mediapipe-game-desktop\src\renderer\game"
New-Item -ItemType Directory -Force -Path $dst

Copy-Item "$src\api-contracts.js" "$dst\"
Copy-Item "$src\mediapipe-engine.js" "$dst\"
Copy-Item "$src\keyboard-input.js" "$dst\"
Copy-Item "$src\dual-keyboard-input.js" "$dst\"
Copy-Item "$src\runner-quiz-game.js" "$dst\"
Copy-Item "$src\snake-quiz-game.js" "$dst\"
Copy-Item "$src\runner-race-game.js" "$dst\"
Copy-Item "$src\snake-duel-game.js" "$dst\"
```

Expected: 8 files copied to `apps/mediapipe-game-desktop/src/renderer/game/`

- [ ] **Step 2: Modify mediapipe-engine.js for local MediaPipe paths**

Find the CDN URL constants (around line 38-42) and replace:

```javascript
// BEFORE:
const TASKS_VISION_WASM_BASE_URL = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${TASKS_VISION_VERSION}/wasm`;
const HAND_LANDMARKER_MODEL_URL =
  'https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task';

// AFTER:
let TASKS_VISION_WASM_BASE_URL = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${TASKS_VISION_VERSION}/wasm`;
let HAND_LANDMARKER_MODEL_URL =
  'https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task';

// Override with local paths when running in Electron
if (typeof window !== 'undefined' && window.electronAPI) {
  window.electronAPI.getLocalMediaPipePaths().then(paths => {
    if (paths && paths.wasmBaseUrl) TASKS_VISION_WASM_BASE_URL = paths.wasmBaseUrl;
    if (paths && paths.modelUrl) HAND_LANDMARKER_MODEL_URL = paths.modelUrl;
  });
}
```

Note: The async initialization is fine because `importTasksVision()` is only called when a camera game starts, which happens after window load + user interaction.

- [ ] **Step 3: Commit**

```bash
git add apps/mediapipe-game-desktop/src/renderer/game/
git commit -m "feat(game-desktop): copy 8 game JS files, patch MediaPipe paths"
```

---

## Task 4: Game Launcher UI (Renderer)

**Files:**
- Create: `apps/mediapipe-game-desktop/src/renderer/index.html`
- Create: `apps/mediapipe-game-desktop/src/renderer/renderer.js`
- Create: `apps/mediapipe-game-desktop/src/renderer/styles.css`

- [ ] **Step 1: Create index.html**

```html
<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>EduVi Game</title>
  <link rel="stylesheet" href="styles.css">
  <meta http-equiv="Content-Security-Policy"
    content="default-src 'self';
             script-src 'self' 'unsafe-inline';
             style-src 'self' 'unsafe-inline';
             media-src 'self' mediastream:;
             worker-src 'self' blob:;
             img-src 'self' data:;
             connect-src 'self' https://cdn.jsdelivr.net https://storage.googleapis.com file:;">
</head>
<body>
  <div id="app">
    <!-- Game launcher menu -->
    <div id="launcher" class="launcher">
      <h1 class="launcher-title">🎮 EduVi Game</h1>
      <p class="launcher-subtitle">Chọn game để chơi</p>
      <div id="game-cards" class="game-cards"></div>
    </div>

    <!-- Game stage (hidden until game starts) -->
    <div id="stage" class="stage hidden">
      <div class="stage-header">
        <button id="btn-back" class="btn-back">← Quay lại</button>
        <span id="game-status" class="game-status"></span>
        <button id="btn-fullscreen" class="btn-fullscreen">⛶ Toàn màn hình</button>
      </div>
      <div class="stage-body">
        <video id="game-video" autoplay playsinline muted></video>
        <canvas id="game-canvas"></canvas>
      </div>
    </div>

    <!-- Result screen (hidden until game finishes) -->
    <div id="result" class="result hidden">
      <div class="result-card">
        <h2 id="result-title">Kết quả</h2>
        <div id="result-body"></div>
        <button id="btn-play-again" class="btn-primary">Chơi lại</button>
        <button id="btn-menu" class="btn-secondary">Về menu</button>
      </div>
    </div>
  </div>

  <script type="module" src="renderer.js"></script>
</body>
</html>
```

- [ ] **Step 2: Create styles.css**

```css
* { margin: 0; padding: 0; box-sizing: border-box; }

body {
  font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
  background: #0f172a;
  color: #e2e8f0;
  overflow: hidden;
  height: 100vh;
}

.hidden { display: none !important; }

/* ── Launcher ── */
.launcher {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 40px 20px;
  min-height: 100vh;
}

.launcher-title {
  font-size: 2.5rem;
  font-weight: 800;
  background: linear-gradient(135deg, #6366f1, #a855f7, #ec4899);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  margin-bottom: 8px;
}

.launcher-subtitle {
  color: #94a3b8;
  font-size: 1.1rem;
  margin-bottom: 32px;
}

.game-cards {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 20px;
  max-width: 900px;
  width: 100%;
}

.game-card {
  background: #1e293b;
  border-radius: 16px;
  padding: 24px;
  cursor: pointer;
  transition: all 0.2s ease;
  border: 2px solid transparent;
  text-align: center;
}

.game-card:hover {
  border-color: #6366f1;
  transform: translateY(-4px);
  box-shadow: 0 8px 25px rgba(99, 102, 241, 0.3);
}

.game-card .icon {
  font-size: 3rem;
  margin-bottom: 12px;
}

.game-card .name {
  font-size: 1.15rem;
  font-weight: 700;
  margin-bottom: 6px;
}

.game-card .desc {
  color: #94a3b8;
  font-size: 0.85rem;
}

.game-card .badge {
  display: inline-block;
  margin-top: 10px;
  padding: 3px 10px;
  border-radius: 999px;
  font-size: 0.75rem;
  font-weight: 600;
}

.badge-camera { background: #7c3aed22; color: #a78bfa; border: 1px solid #7c3aed44; }
.badge-keyboard { background: #05966922; color: #6ee7b7; border: 1px solid #05966944; }
.badge-2p { background: #d9770622; color: #fbbf24; border: 1px solid #d9770644; }

/* ── Stage ── */
.stage {
  display: flex;
  flex-direction: column;
  height: 100vh;
}

.stage-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 8px 16px;
  background: #1e293b;
  height: 44px;
  flex-shrink: 0;
}

.stage-body {
  flex: 1;
  position: relative;
  overflow: hidden;
  background: #000;
}

.stage-body video {
  position: absolute;
  top: 0; left: 0;
  width: 100%; height: 100%;
  object-fit: cover;
  transform: scaleX(-1);
}

.stage-body canvas {
  position: absolute;
  top: 0; left: 0;
  width: 100%; height: 100%;
  transform: scaleX(-1);
}

/* Keyboard-only games: hide video, no mirror on canvas */
.stage-body.keyboard-mode video { display: none; }
.stage-body.keyboard-mode canvas { transform: none; }

.btn-back, .btn-fullscreen {
  background: transparent;
  border: 1px solid #475569;
  color: #e2e8f0;
  padding: 4px 14px;
  border-radius: 8px;
  cursor: pointer;
  font-size: 0.85rem;
}

.btn-back:hover, .btn-fullscreen:hover { background: #334155; }

.game-status { color: #94a3b8; font-size: 0.85rem; }

/* ── Result ── */
.result {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100vh;
  background: rgba(15, 23, 42, 0.95);
}

.result-card {
  background: #1e293b;
  border-radius: 20px;
  padding: 40px 48px;
  text-align: center;
  max-width: 480px;
}

.result-card h2 { font-size: 1.8rem; margin-bottom: 20px; }

#result-body {
  font-size: 1.1rem;
  color: #94a3b8;
  margin-bottom: 24px;
  line-height: 1.6;
}

.btn-primary {
  background: linear-gradient(135deg, #6366f1, #8b5cf6);
  border: none;
  color: white;
  padding: 10px 28px;
  border-radius: 10px;
  font-size: 1rem;
  font-weight: 600;
  cursor: pointer;
  margin: 0 8px;
}

.btn-secondary {
  background: #334155;
  border: 1px solid #475569;
  color: #e2e8f0;
  padding: 10px 28px;
  border-radius: 10px;
  font-size: 1rem;
  cursor: pointer;
  margin: 0 8px;
}

.btn-primary:hover { filter: brightness(1.1); }
.btn-secondary:hover { background: #475569; }
```

- [ ] **Step 3: Create renderer.js**

```javascript
import { GAME_BLUEPRINTS, createMockRunnerQuiz, createMockSnakeQuiz } from './game/api-contracts.js';
import { MediaPipeTracker, GameEngine } from './game/mediapipe-engine.js';

// ── Game catalog ──
const GAME_CATALOG = [
  {
    id: GAME_BLUEPRINTS.HOVER_SELECT,
    name: 'Hover Select',
    desc: 'Di chuyển tay để chọn đáp án',
    icon: '🖐️',
    input: 'camera',
    players: 1,
  },
  {
    id: GAME_BLUEPRINTS.DRAG_DROP,
    name: 'Drag & Drop',
    desc: 'Kéo thả ghép cặp đúng',
    icon: '🤏',
    input: 'camera',
    players: 1,
  },
  {
    id: GAME_BLUEPRINTS.RUNNER_QUIZ,
    name: 'Runner Quiz',
    desc: 'Mario chạy trả lời câu hỏi',
    icon: '🏃',
    input: 'keyboard',
    players: 1,
  },
  {
    id: GAME_BLUEPRINTS.SNAKE_QUIZ,
    name: 'Snake Quiz',
    desc: 'Rắn ăn mồi + trả lời quiz',
    icon: '🐍',
    input: 'keyboard',
    players: 1,
  },
  {
    id: GAME_BLUEPRINTS.RUNNER_RACE,
    name: 'Runner Race',
    desc: '2 người đua chạy trả lời',
    icon: '🏁',
    input: 'keyboard',
    players: 2,
  },
  {
    id: GAME_BLUEPRINTS.SNAKE_DUEL,
    name: 'Snake Duel',
    desc: '2 rắn đối đầu giành mồi',
    icon: '⚔️',
    input: 'keyboard',
    players: 2,
  },
];

// ── DOM refs ──
const launcherEl = document.getElementById('launcher');
const stageEl = document.getElementById('stage');
const resultEl = document.getElementById('result');
const gameCardsEl = document.getElementById('game-cards');
const videoEl = document.getElementById('game-video');
const canvasEl = document.getElementById('game-canvas');
const statusEl = document.getElementById('game-status');
const btnBack = document.getElementById('btn-back');
const btnFullscreen = document.getElementById('btn-fullscreen');
const btnPlayAgain = document.getElementById('btn-play-again');
const btnMenu = document.getElementById('btn-menu');
const resultTitle = document.getElementById('result-title');
const resultBody = document.getElementById('result-body');

let currentEngine = null;
let currentTracker = null;
let currentGameId = null;

// ── Build game cards ──
function renderGameCards() {
  gameCardsEl.innerHTML = '';
  for (const game of GAME_CATALOG) {
    const card = document.createElement('div');
    card.className = 'game-card';
    card.dataset.gameId = game.id;

    let badgeClass = 'badge-keyboard';
    let badgeText = '⌨️ Bàn phím';
    if (game.input === 'camera') {
      badgeClass = 'badge-camera';
      badgeText = '🖐️ Camera';
    }
    if (game.players === 2) {
      badgeClass = 'badge-2p';
      badgeText = '⌨️⌨️ 2 người chơi';
    }

    card.innerHTML = `
      <div class="icon">${game.icon}</div>
      <div class="name">${game.name}</div>
      <div class="desc">${game.desc}</div>
      <span class="badge ${badgeClass}">${badgeText}</span>
    `;

    card.addEventListener('click', () => launchGame(game.id));
    gameCardsEl.appendChild(card);
  }
}

// ── Get mock playable data ──
function getMockPlayable(templateId) {
  switch (templateId) {
    case GAME_BLUEPRINTS.RUNNER_QUIZ: return createMockRunnerQuiz();
    case GAME_BLUEPRINTS.SNAKE_QUIZ:  return createMockSnakeQuiz();
    case GAME_BLUEPRINTS.HOVER_SELECT:
      return {
        gameId: 'mock-hover-001',
        templateId: 'HOVER_SELECT',
        version: '1.0',
        settings: { mirror: true, timeLimitSec: 30, hoverHoldMs: 2000, pinchThreshold: 0.045 },
        scene: { title: 'Chọn đáp án đúng!' },
        payload: [
          {
            prompt: 'Thủ đô của Việt Nam là gì?',
            choices: [
              { id: 'a', text: 'Hải Phòng', zone: { x: 0.05, y: 0.3, w: 0.4, h: 0.25 } },
              { id: 'b', text: 'Hà Nội', zone: { x: 0.55, y: 0.3, w: 0.4, h: 0.25 } },
              { id: 'c', text: 'Đà Nẵng', zone: { x: 0.05, y: 0.65, w: 0.4, h: 0.25 } },
              { id: 'd', text: 'TP HCM', zone: { x: 0.55, y: 0.65, w: 0.4, h: 0.25 } },
            ],
            correctChoiceId: 'b',
          },
        ],
      };
    case GAME_BLUEPRINTS.DRAG_DROP:
      return {
        gameId: 'mock-drag-001',
        templateId: 'DRAG_DROP',
        version: '1.0',
        settings: { mirror: true, timeLimitSec: 60, hoverHoldMs: 0, pinchThreshold: 0.045 },
        scene: { title: 'Ghép cặp đúng!' },
        payload: [
          {
            prompt: 'Nối thủ đô với quốc gia',
            items: [
              { id: 'i1', label: 'Hà Nội', start: { x: 0.1, y: 0.3 }, size: { w: 0.15, h: 0.08 } },
              { id: 'i2', label: 'Tokyo', start: { x: 0.1, y: 0.5 }, size: { w: 0.15, h: 0.08 } },
            ],
            dropZones: [
              { id: 'z1', label: 'Việt Nam', zone: { x: 0.7, y: 0.3, w: 0.2, h: 0.1 }, acceptsItemId: 'i1' },
              { id: 'z2', label: 'Nhật Bản', zone: { x: 0.7, y: 0.5, w: 0.2, h: 0.1 }, acceptsItemId: 'i2' },
            ],
          },
        ],
      };
    case GAME_BLUEPRINTS.RUNNER_RACE:
      return {
        gameId: 'mock-race-001',
        templateId: 'RUNNER_RACE',
        version: '1.0',
        settings: { mirror: false, timeLimitSec: 0, hoverHoldMs: 0, pinchThreshold: 0 },
        scene: { title: 'Đua chạy trả lời!' },
        payload: {
          theme: 'castle',
          questions: [
            {
              id: 'q1',
              prompt: '2 + 2 = ?',
              choices: [
                { id: 'a', text: '3' },
                { id: 'b', text: '4' },
                { id: 'c', text: '5' },
                { id: 'd', text: '6' },
              ],
              correctChoiceId: 'b',
            },
            {
              id: 'q2',
              prompt: '3 x 3 = ?',
              choices: [
                { id: 'a', text: '6' },
                { id: 'b', text: '9' },
                { id: 'c', text: '12' },
                { id: 'd', text: '15' },
              ],
              correctChoiceId: 'b',
            },
          ],
        },
      };
    case GAME_BLUEPRINTS.SNAKE_DUEL:
      return {
        gameId: 'mock-duel-001',
        templateId: 'SNAKE_DUEL',
        version: '1.0',
        settings: { mirror: false, timeLimitSec: 0, hoverHoldMs: 0, pinchThreshold: 0 },
        scene: { title: 'Rắn đối đầu!' },
        payload: {
          gridSize: 20,
          speed: 'normal',
          theme: 'neon',
          questions: [
            {
              id: 'q1',
              prompt: 'Số Pi xấp xỉ bằng?',
              choices: [
                { id: 'a', text: '2.14' },
                { id: 'b', text: '3.14' },
                { id: 'c', text: '4.14' },
                { id: 'd', text: '5.14' },
              ],
              correctChoiceId: 'b',
            },
          ],
        },
      };
    default:
      return null;
  }
}

// ── Launch a game ──
async function launchGame(templateId, playableOverride) {
  const playable = playableOverride || getMockPlayable(templateId);
  if (!playable) {
    alert(`Không có dữ liệu cho game ${templateId}`);
    return;
  }

  currentGameId = templateId;

  // Determine if camera or keyboard mode
  const isCamera = templateId === GAME_BLUEPRINTS.HOVER_SELECT || templateId === GAME_BLUEPRINTS.DRAG_DROP;
  const stageBody = document.querySelector('.stage-body');
  stageBody.classList.toggle('keyboard-mode', !isCamera);

  // Show stage
  launcherEl.classList.add('hidden');
  resultEl.classList.add('hidden');
  stageEl.classList.remove('hidden');

  // Resize canvas to fill stage
  const resizeCanvas = () => {
    canvasEl.width = stageBody.clientWidth;
    canvasEl.height = stageBody.clientHeight;
  };
  resizeCanvas();
  window.addEventListener('resize', resizeCanvas);

  // Init tracker (camera games only)
  let tracker = null;
  if (isCamera) {
    try {
      tracker = new MediaPipeTracker({
        videoEl,
        onFrame: () => {},
      });
    } catch (err) {
      console.warn('MediaPipe tracker init failed:', err);
    }
  }

  currentTracker = tracker;

  // Init engine
  const engine = new GameEngine({
    canvasEl,
    videoEl,
    playable,
    tracker,
    onStatus: (msg) => {
      statusEl.textContent = msg;
    },
    onFinish: (result) => {
      showResult(result, playable);
      cleanup();
    },
  });

  currentEngine = engine;

  try {
    await engine.init();
    statusEl.textContent = 'Đang chơi...';
  } catch (err) {
    console.error('Game init failed:', err);
    statusEl.textContent = `Lỗi: ${err.message}`;
  }
}

// ── Show result ──
function showResult(result, playable) {
  stageEl.classList.add('hidden');
  resultEl.classList.remove('hidden');

  resultTitle.textContent = '🎉 Kết quả!';

  let bodyHtml = '';
  if (result && typeof result.correct === 'number') {
    bodyHtml = `<p>Đúng: <strong>${result.correct}</strong> / ${result.total || '?'}</p>`;
    const pct = result.total ? Math.round((result.correct / result.total) * 100) : 0;
    bodyHtml += `<p>Tỷ lệ: <strong>${pct}%</strong></p>`;
  } else {
    bodyHtml = `<p>Hoàn thành!</p>`;
  }
  resultBody.innerHTML = bodyHtml;

  // Save result if in contract mode
  if (window.electronAPI) {
    window.electronAPI.saveGameResult({
      gameId: playable.gameId,
      templateId: playable.templateId,
      result,
      timestamp: new Date().toISOString(),
    });
  }
}

// ── Cleanup ──
function cleanup() {
  if (currentEngine && typeof currentEngine.dispose === 'function') {
    currentEngine.dispose();
  }
  if (currentTracker && typeof currentTracker.stop === 'function') {
    currentTracker.stop();
  }
  currentEngine = null;
  currentTracker = null;

  // Stop video stream
  if (videoEl.srcObject) {
    videoEl.srcObject.getTracks().forEach(t => t.stop());
    videoEl.srcObject = null;
  }
}

// ── Navigation ──
function showLauncher() {
  cleanup();
  stageEl.classList.add('hidden');
  resultEl.classList.add('hidden');
  launcherEl.classList.remove('hidden');
  currentGameId = null;
}

// ── Event listeners ──
btnBack.addEventListener('click', showLauncher);
btnMenu.addEventListener('click', showLauncher);

btnPlayAgain.addEventListener('click', () => {
  if (currentGameId) {
    resultEl.classList.add('hidden');
    launchGame(currentGameId);
  }
});

btnFullscreen.addEventListener('click', () => {
  if (window.electronAPI) {
    window.electronAPI.toggleFullscreen();
  }
});

// ── Contract mode: auto-start ──
async function checkContractMode() {
  if (!window.electronAPI) return;

  const contract = await window.electronAPI.getLaunchContract();
  if (!contract || !contract.gamePayload) return;

  const payload = contract.gamePayload;
  await launchGame(payload.templateId, payload);
}

// ── Init ──
renderGameCards();
checkContractMode();
```

- [ ] **Step 4: Run Electron and test game launcher UI**

Run: `cd apps/mediapipe-game-desktop && npx electron .`
Expected: Window shows 6 game cards with icons, names, descriptions. Cards have hover effects.

- [ ] **Step 5: Test Runner Quiz game**

Click "Runner Quiz" card → game should start on canvas → use arrow keys + 1/2/3/4 to play → game finishes → result screen shows.

- [ ] **Step 6: Test Snake Quiz game**

Click "← Quay lại" → menu → click "Snake Quiz" → game starts → use arrow keys + 1/2/3/4 → game finishes.

- [ ] **Step 7: Test all 4 keyboard games**

Also test Runner Race (WASD+Space for P1, Arrows+Enter for P2) and Snake Duel (same controls). All should play with mock data.

- [ ] **Step 8: Commit**

```bash
git add apps/mediapipe-game-desktop/src/renderer/
git commit -m "feat(game-desktop): game launcher UI + 6 games with mock data"
```

---

## Task 5: Contract Mode (Flutter Integration Protocol)

**Files:**
- Modify: `apps/mediapipe-game-desktop/src/main/main.js` (already handles --launch-contract)
- This task verifies the existing contract mode works.

- [ ] **Step 1: Create test launch contract file**

Create `apps/mediapipe-game-desktop/test-contract.json`:

```json
{
  "packagePath": "",
  "sessionId": "test-session-001",
  "outputDir": "./test-output",
  "mode": "new",
  "gamePayload": {
    "gameId": "contract-runner-001",
    "templateId": "RUNNER_QUIZ",
    "version": "1.0",
    "settings": {
      "mirror": false,
      "timeLimitSec": 0,
      "hoverHoldMs": 0,
      "pinchThreshold": 0
    },
    "scene": { "title": "Contract Mode Test" },
    "payload": {
      "theme": "castle",
      "characterName": "Mario",
      "questions": [
        {
          "id": "q1",
          "prompt": "Test question from contract",
          "choices": [
            { "id": "a", "text": "Wrong A" },
            { "id": "b", "text": "Correct B" },
            { "id": "c", "text": "Wrong C" },
            { "id": "d", "text": "Wrong D" }
          ],
          "correctChoiceId": "b"
        }
      ]
    }
  }
}
```

- [ ] **Step 2: Test contract mode launch**

Run: `cd apps/mediapipe-game-desktop && npx electron . --launch-contract=test-contract.json`
Expected: Game starts immediately (no launcher menu) with "Contract Mode Test" title.

- [ ] **Step 3: Verify result file written**

After finishing the game, check: `apps/mediapipe-game-desktop/test-output/game.result.json`
Expected: JSON file with `gameId`, `templateId`, `result`, `timestamp`.

- [ ] **Step 4: Commit**

```bash
git add apps/mediapipe-game-desktop/test-contract.json
git commit -m "test(game-desktop): verify contract mode launch + result output"
```

---

## Task 6: Download MediaPipe Offline Assets

**Files:**
- Create: `apps/mediapipe-game-desktop/scripts/download-mediapipe.js`
- Create: `apps/mediapipe-game-desktop/assets/mediapipe/` (downloaded files)

- [ ] **Step 1: Create download script**

```javascript
// scripts/download-mediapipe.js
const https = require('https');
const fs = require('fs');
const path = require('path');

const TASKS_VISION_VERSION = '0.10.18';
const BASE_CDN = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${TASKS_VISION_VERSION}/wasm`;
const MODEL_URL = 'https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task';

const WASM_FILES = [
  'vision_wasm_internal.js',
  'vision_wasm_internal.wasm',
  'vision_wasm_nosimd_internal.js',
  'vision_wasm_nosimd_internal.wasm',
];

const wasmDir = path.join(__dirname, '..', 'assets', 'mediapipe', 'wasm');
const modelDir = path.join(__dirname, '..', 'assets', 'mediapipe', 'models');

function downloadFile(url, dest) {
  return new Promise((resolve, reject) => {
    console.log(`Downloading: ${url}`);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    const file = fs.createWriteStream(dest);
    https.get(url, (response) => {
      if (response.statusCode === 301 || response.statusCode === 302) {
        downloadFile(response.headers.location, dest).then(resolve).catch(reject);
        return;
      }
      if (response.statusCode !== 200) {
        reject(new Error(`HTTP ${response.statusCode} for ${url}`));
        return;
      }
      response.pipe(file);
      file.on('finish', () => {
        file.close();
        const size = fs.statSync(dest).size;
        console.log(`  → ${dest} (${(size / 1024 / 1024).toFixed(2)} MB)`);
        resolve();
      });
    }).on('error', reject);
  });
}

async function main() {
  console.log('=== Downloading MediaPipe WASM files ===\n');
  for (const file of WASM_FILES) {
    await downloadFile(`${BASE_CDN}/${file}`, path.join(wasmDir, file));
  }

  console.log('\n=== Downloading MediaPipe Hand Landmarker model ===\n');
  await downloadFile(MODEL_URL, path.join(modelDir, 'hand_landmarker.task'));

  console.log('\n✅ All MediaPipe assets downloaded for offline use.');
}

main().catch(err => {
  console.error('Download failed:', err);
  process.exit(1);
});
```

- [ ] **Step 2: Run download script**

Run: `cd apps/mediapipe-game-desktop && node scripts/download-mediapipe.js`
Expected: Files downloaded to `assets/mediapipe/wasm/` and `assets/mediapipe/models/`

- [ ] **Step 3: Verify file sizes**

```powershell
Get-ChildItem -Recurse apps/mediapipe-game-desktop/assets/mediapipe | Select-Object FullName, Length
```

Expected:
- `vision_wasm_internal.wasm` ~8MB
- `hand_landmarker.task` ~12MB
- Total ~25-30MB

- [ ] **Step 4: Test camera game with local MediaPipe**

Run: `cd apps/mediapipe-game-desktop && npx electron .`
Click "Hover Select" → should request camera permission → if webcam available, hand tracking starts → game plays.

Note: If camera is not available (no webcam), the game will show an error but keyboard games should still work fine.

- [ ] **Step 5: Commit**

```bash
git add apps/mediapipe-game-desktop/scripts/download-mediapipe.js
git commit -m "feat(game-desktop): offline MediaPipe asset downloader"
```

---

## Task 7: Flutter GAME Block Widget

**Files:**
- Create: `lib/features/game_player/game_block_widget.dart`
- Create: `lib/features/game_player/mediapipe_game_launcher.dart`

- [ ] **Step 1: Create mediapipe_game_launcher.dart**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../offline_core/domain/game_launch_contract.dart';
import '../offline_core/services/offline_storage_paths.dart';

class MediaPipeGameLauncher {
  final OfflineStoragePaths _paths;

  MediaPipeGameLauncher({OfflineStoragePaths? paths})
      : _paths = paths ?? const OfflineStoragePaths();

  Future<int> launchFromBlockContent(Map<String, dynamic> content) async {
    final sessionId = 'inline_${DateTime.now().millisecondsSinceEpoch}';
    final outputDir = await _paths.sessionOutputPath(sessionId);
    await Directory(outputDir).create(recursive: true);

    final extendedContract = <String, dynamic>{
      'packagePath': '',
      'sessionId': sessionId,
      'outputDir': outputDir,
      'mode': GameLaunchMode.newSession.value,
      'gamePayload': content['gamePayload'] ?? content,
    };

    final contractPath = p.join(outputDir, 'launch.contract.json');
    final encoded = const JsonEncoder.withIndent('  ').convert(extendedContract);
    await File(contractPath).writeAsString(encoded);

    final exePath = _resolveGameRuntimePath();
    if (!await File(exePath).exists()) {
      throw FileSystemException(
        'Không tìm thấy MediaPipe game runtime',
        exePath,
      );
    }

    final process = await Process.start(exePath, [
      '--launch-contract=$contractPath',
    ]);
    return process.pid;
  }

  String _resolveGameRuntimePath() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;

    final candidates = [
      p.join(exeDir, 'game-runtime', 'mediapipe-game.exe'),
      p.join(exeDir, 'game-runtime', 'EduVi Game.exe'),
      p.join(Directory.current.path, 'apps', 'mediapipe-game-desktop', 'dist', 'win-unpacked', 'EduVi Game.exe'),
      p.join(Directory.current.path, 'apps', 'mediapipe-game-desktop', 'dist', 'mediapipe-game.exe'),
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }

    return candidates.first;
  }

  Future<Map<String, dynamic>?> readGameResult(String sessionId) async {
    final outputDir = await _paths.sessionOutputPath(sessionId);
    final resultFile = File(p.join(outputDir, 'game.result.json'));
    if (!await resultFile.exists()) return null;
    final raw = await resultFile.readAsString();
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}
```

- [ ] **Step 2: Create game_block_widget.dart**

```dart
import 'package:flutter/material.dart';

import '../../models/block_model.dart';
import 'mediapipe_game_launcher.dart';

class GameBlockWidget extends StatefulWidget {
  final EduViBlock block;
  final String? runtimeSessionId;

  const GameBlockWidget({
    super.key,
    required this.block,
    this.runtimeSessionId,
  });

  @override
  State<GameBlockWidget> createState() => _GameBlockWidgetState();
}

class _GameBlockWidgetState extends State<GameBlockWidget> {
  final MediaPipeGameLauncher _launcher = MediaPipeGameLauncher();
  bool _launching = false;

  String get _templateId =>
      widget.block.content['templateId'] as String? ?? 'GAME';

  String get _gameName {
    switch (_templateId) {
      case 'HOVER_SELECT':
        return 'Hover Select';
      case 'DRAG_DROP':
        return 'Drag & Drop';
      case 'RUNNER_QUIZ':
        return 'Runner Quiz';
      case 'SNAKE_QUIZ':
        return 'Snake Quiz';
      case 'RUNNER_RACE':
        return 'Runner Race (2P)';
      case 'SNAKE_DUEL':
        return 'Snake Duel (2P)';
      default:
        return 'Game';
    }
  }

  IconData get _gameIcon {
    switch (_templateId) {
      case 'HOVER_SELECT':
      case 'DRAG_DROP':
        return Icons.pan_tool;
      case 'RUNNER_QUIZ':
      case 'RUNNER_RACE':
        return Icons.directions_run;
      case 'SNAKE_QUIZ':
      case 'SNAKE_DUEL':
        return Icons.pest_control;
      default:
        return Icons.sports_esports;
    }
  }

  Future<void> _launchGame() async {
    if (_launching) return;
    setState(() => _launching = true);

    try {
      final pid = await _launcher.launchFromBlockContent(widget.block.content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã mở game $_gameName (PID: $pid)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi mở game: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _launching ? null : _launchGame,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Icon(_gameIcon, size: 40, color: Colors.white),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _gameName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Nhấn để mở game',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (_launching)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                const Icon(
                  Icons.play_circle_filled,
                  size: 36,
                  color: Colors.white,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/features/game_player/
git commit -m "feat(game-player): GameBlockWidget + MediaPipeGameLauncher"
```

---

## Task 8: Wire GAME Block into BlockDispatcher

**Files:**
- Modify: `lib/widgets/blocks/block_dispatcher.dart`

- [ ] **Step 1: Add import and GAME case to block_dispatcher.dart**

Add import at top:
```dart
import '../../features/game_player/game_block_widget.dart';
```

Add case to switch expression (after 'FILL_BLANK' case):
```dart
'GAME' => GameBlockWidget(
  block: block,
  runtimeSessionId: runtimeSessionId,
),
```

- [ ] **Step 2: Run flutter analyze**

Run: `flutter analyze`
Expected: No issues

- [ ] **Step 3: Run existing tests**

Run: `flutter test`
Expected: All existing tests still pass

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/blocks/block_dispatcher.dart
git commit -m "feat(block-dispatcher): wire GAME block type to GameBlockWidget"
```

---

## Task 9: Update Electron Launcher Paths

**Files:**
- Modify: `lib/features/offline_core/services/electron_launcher_service.dart`

- [ ] **Step 1: Add game-runtime path to candidate list**

In `_candidateCommands()` method, add a new candidate before the existing list:

```dart
// MediaPipe game runtime (separate from legacy Electron game runtime)
ResolvedElectronLaunchCommand(
  executablePath: p.join(runningExeDir, 'game-runtime', 'mediapipe-game.exe'),
),
ResolvedElectronLaunchCommand(
  executablePath: p.join(runningExeDir, 'game-runtime', 'EduVi Game.exe'),
),
```

- [ ] **Step 2: Run flutter analyze**

Run: `flutter analyze`
Expected: No issues

- [ ] **Step 3: Commit**

```bash
git add lib/features/offline_core/services/electron_launcher_service.dart
git commit -m "feat(electron-launcher): add game-runtime path candidates"
```

---

## Task 10: Package Electron App

**Files:**
- Modify: `apps/mediapipe-game-desktop/package.json` (verify build config)

- [ ] **Step 1: Build Electron app for Windows**

Run:
```powershell
cd apps/mediapipe-game-desktop
npx electron-builder --win portable --config.productName="mediapipe-game"
```

Expected: Build output in `apps/mediapipe-game-desktop/dist/` with `mediapipe-game.exe` or `win-unpacked/` folder.

- [ ] **Step 2: Verify built app launches standalone**

Run the built executable directly.
Expected: Game launcher UI shows, 6 games available, keyboard games work.

- [ ] **Step 3: Verify built app launches in contract mode**

Run with test contract.
Expected: Game auto-starts from contract data.

- [ ] **Step 4: Commit**

```bash
git commit -m "build(game-desktop): verify Electron packaging"
```

---

## Task 11: Build Flutter + Bundle Everything

**Files:**
- No new files; build and packaging commands

- [ ] **Step 1: Build Flutter Windows release**

Run: `flutter build windows --release`
Expected: Build succeeds at `build/windows/x64/runner/Release/`

- [ ] **Step 2: Copy Electron game runtime into Flutter build output**

```powershell
$flutterRelease = "build\windows\x64\runner\Release"
$gameRuntimeSrc = "apps\mediapipe-game-desktop\dist\win-unpacked"
$gameRuntimeDst = "$flutterRelease\game-runtime"

# Create game-runtime folder in Flutter build
New-Item -ItemType Directory -Force -Path $gameRuntimeDst

# Copy Electron app
Copy-Item -Recurse -Force "$gameRuntimeSrc\*" "$gameRuntimeDst\"
```

- [ ] **Step 3: Verify both executables exist**

```powershell
Test-Path "$flutterRelease\eduvi_viewer.exe"    # Flutter
Test-Path "$gameRuntimeDst\mediapipe-game.exe"   # Electron game
```

Expected: Both return True

- [ ] **Step 4: Create zip**

```powershell
$zipName = "eduviviewer-windows-teacher-pack.zip"
Compress-Archive -Path "$flutterRelease\*" -DestinationPath $zipName -Force
(Get-Item $zipName).Length / 1MB
```

Expected: Zip created, ~300MB (Flutter + Electron + MediaPipe assets)

- [ ] **Step 5: Verify zip contents**

```powershell
Expand-Archive $zipName -DestinationPath "verify-zip" -Force
Test-Path "verify-zip\eduvi_viewer.exe"
Test-Path "verify-zip\game-runtime\mediapipe-game.exe"
Remove-Item -Recurse "verify-zip"
```

Expected: Both executables found inside zip

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "build: bundle Flutter viewer + Electron game runtime as teacher pack"
```

---

## Verification Checklist

After all tasks complete:

- [ ] `npx electron .` in `apps/mediapipe-game-desktop/` → 6 game cards shown
- [ ] Runner Quiz plays with mock data (keyboard)
- [ ] Snake Quiz plays with mock data (keyboard)
- [ ] Runner Race plays with 2 players (WASD + Arrows)
- [ ] Snake Duel plays with 2 players
- [ ] Hover Select starts camera (if webcam available)
- [ ] Drag & Drop starts camera (if webcam available)
- [ ] Contract mode: `--launch-contract` auto-starts game
- [ ] Flutter `flutter test` → all tests pass
- [ ] Flutter `flutter analyze` → 0 issues
- [ ] GAME block in slide → renders GameBlockWidget
- [ ] Click GameBlockWidget → launches Electron game process
- [ ] Zip contains both `eduvi_viewer.exe` and `game-runtime/mediapipe-game.exe`
- [ ] Unzip on clean Windows → both apps run offline
