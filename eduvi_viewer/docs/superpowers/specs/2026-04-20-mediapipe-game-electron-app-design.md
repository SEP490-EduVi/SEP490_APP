# MediaPipe Game Electron App + Flutter GAME Block Integration

## Date: 2026-04-20

## Problem Statement

1. **App chưa chia folder rõ ràng** cho game vs slide trong cả source code lẫn build output.
2. **Slide không chơi game MediaPipe được** — `BlockDispatcher` thiếu block type `GAME`.
3. **Electron game runtime chưa có** bộ game MediaPipe thực tế — chỉ có launcher infrastructure trống.

## Goals

1. Build Electron app chứa 10 file JS game MediaPipe từ web frontend (6 blueprints).
2. Thêm `GAME` block type vào Flutter slide viewer → launch Electron game từ block data.
3. Bundle offline hoàn toàn: MediaPipe WASM + model local, mock data sẵn, không cần internet.
4. Đóng gói 1 zip chứa cả Flutter viewer + Electron game runtime.

## Non-Goals

- Không cần editor/teacher game config UI trong desktop app (chỉ player mode).
- Không cần backend API calls — tất cả game data từ `.eduvi` file hoặc mock data.
- Không cần SignalR, polling, hay task creation flow.
- Không rebuild slide viewer — giữ nguyên Flutter.

---

## Architecture

### Build Output Structure (1 zip)

```
eduviviewer-windows-teacher-pack/
├── eduvi_viewer.exe                 # Flutter shell — slide viewer + game launcher
├── flutter_windows.dll
├── *.dll
├── data/
│   └── flutter_assets/
├── game-runtime/                    # Electron MediaPipe game player
│   ├── mediapipe-game.exe           # Electron packaged app
│   ├── *.dll                        # Chromium runtime
│   ├── resources/
│   │   └── app.asar                 # Or unpacked app/
│   │       ├── main.js
│   │       ├── preload.js
│   │       └── renderer/
│   │           ├── index.html
│   │           ├── renderer.js
│   │           ├── styles.css
│   │           └── game/            # 10 JS files (copy nguyên từ web FE)
│   │               ├── api-contracts.js
│   │               ├── mediapipe-engine.js
│   │               ├── keyboard-input.js
│   │               ├── dual-keyboard-input.js
│   │               ├── runner-quiz-game.js
│   │               ├── snake-quiz-game.js
│   │               ├── runner-race-game.js
│   │               ├── snake-duel-game.js
│   │               ├── editor.js         # Optional: teacher preview only
│   │               └── editor-ui.html    # Optional: teacher preview only
│   └── mediapipe-local/             # Offline MediaPipe assets
│       ├── wasm/                    # @mediapipe/tasks-vision WASM files
│       │   ├── vision_wasm_internal.js
│       │   ├── vision_wasm_internal.wasm
│       │   └── vision_wasm_nosimd_internal.*
│       └── models/
│           └── hand_landmarker.task  # ~12MB model file
```

### Source Code Structure

```
eduvi_viewer/
├── lib/
│   ├── features/
│   │   ├── game_player/             # NEW: Flutter-side game integration
│   │   │   ├── game_block_widget.dart        # Widget cho GAME block trong slide
│   │   │   └── mediapipe_game_launcher.dart  # Launch Electron với game payload
│   │   └── offline_core/            # Existing (unchanged)
│   ├── widgets/blocks/
│   │   └── block_dispatcher.dart    # Modified: thêm GAME case
│   └── ...
│
└── apps/
    └── mediapipe-game-desktop/      # NEW: Electron app
        ├── package.json
        ├── electron-builder.yml
        ├── src/
        │   ├── main/
        │   │   ├── main.js          # Electron main process
        │   │   └── preload.js       # Context bridge
        │   └── renderer/
        │       ├── index.html       # Game host page
        │       ├── renderer.js      # Game launcher + menu
        │       ├── styles.css       # UI styling
        │       └── game/            # Copy of mediapipe-game/ (10 files)
        └── assets/
            └── mediapipe/           # Downloaded WASM + model
                ├── wasm/
                └── models/
```

---

## Component Design

### 1. Electron Main Process (`main.js`)

**Responsibilities:**
- Create BrowserWindow: fullscreen-able, min 1024×768
- Security: `nodeIntegration: false`, `contextIsolation: true`
- Camera access: `setPermissionRequestHandler` for `media` type
- Menu: File > Quit, View > Fullscreen, Help > About
- **Launch modes:**
  - **Standalone mode**: Show game launcher UI (6 game cards)
  - **Contract mode**: `--launch-contract=<path>` → read JSON, auto-start game

```javascript
// Launch contract JSON structure (written by Flutter)
{
  "packagePath": "C:/Users/.../EduviOffline/packages/xyz",
  "sessionId": "xyz_1.0",
  "outputDir": "C:/Users/.../EduviOffline/sessions/xyz_1.0",
  "mode": "new",
  "gamePayload": {
    "gameId": "...",
    "templateId": "RUNNER_QUIZ",
    "version": "1.0",
    "settings": { ... },
    "scene": { ... },
    "payload": { ... }
  }
}
```

**CSP Configuration:**
```
Content-Security-Policy: 
  default-src 'self';
  script-src 'self' 'unsafe-inline';
  style-src 'self' 'unsafe-inline';
  media-src 'self' mediastream:;
  worker-src 'self' blob:;
```

### 2. Preload Script (`preload.js`)

```javascript
contextBridge.exposeInMainWorld('electronAPI', {
  getAppVersion: () => ipcRenderer.invoke('get-app-version'),
  toggleFullscreen: () => ipcRenderer.invoke('toggle-fullscreen'),
  getLaunchContract: () => ipcRenderer.invoke('get-launch-contract'),
  saveGameResult: (result) => ipcRenderer.invoke('save-game-result', result),
  saveProgressSnapshot: (data) => ipcRenderer.invoke('save-progress-snapshot', data),
  getLocalMediaPipePaths: () => ipcRenderer.invoke('get-mediapipe-paths'),
});
```

### 3. Renderer Entry (`renderer.js`)

**Standalone mode (no contract):**
- Render 6 game cards:
  | Game | Input | Players |
  |------|-------|---------|
  | Hover Select | Camera 🖐️ | 1 |
  | Drag & Drop | Camera 🖐️ | 1 |
  | Runner Quiz | Keyboard ⌨️ | 1 |
  | Snake Quiz | Keyboard ⌨️ | 1 |
  | Runner Race | Keyboard ⌨️⌨️ | 2 |
  | Snake Duel | Keyboard ⌨️⌨️ | 2 |
- Click → create `<video>` + `<canvas>` → init `GameEngine` with mock data
- "Quay lại" button → back to card menu

**Contract mode:**
- Read contract via `electronAPI.getLaunchContract()`
- Auto-init `GameEngine` with `contract.gamePayload`
- On finish → `electronAPI.saveGameResult(result)` → auto-close or show result

### 4. MediaPipe Offline Modification

**Current (CDN):**
```javascript
const TASKS_VISION_WASM_BASE_URL = 
  `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.18/wasm`;
const HAND_LANDMARKER_MODEL_URL = 
  'https://storage.googleapis.com/mediapipe-models/...';
```

**Modified (local):**
```javascript
// mediapipe-engine.js reads paths from electronAPI or uses relative path
let TASKS_VISION_WASM_BASE_URL;
let HAND_LANDMARKER_MODEL_URL;

if (typeof window !== 'undefined' && window.electronAPI) {
  const paths = await window.electronAPI.getLocalMediaPipePaths();
  TASKS_VISION_WASM_BASE_URL = paths.wasmBaseUrl;  // file:///... or app://...
  HAND_LANDMARKER_MODEL_URL = paths.modelUrl;
} else {
  // Fallback CDN
  TASKS_VISION_WASM_BASE_URL = `https://cdn.jsdelivr.net/npm/...`;
  HAND_LANDMARKER_MODEL_URL = `https://storage.googleapis.com/...`;
}
```

### 5. Flutter GAME Block Widget (`game_block_widget.dart`)

**When slide contains a block with `type: 'GAME'`:**

```dart
// block.content structure for GAME block:
// {
//   "templateId": "RUNNER_QUIZ",
//   "gamePayload": { ... PlayableGameResponse ... }
// }

class GameBlockWidget extends StatelessWidget {
  final EduViBlock block;

  Widget build(BuildContext context) {
    final templateId = block.content['templateId'] as String? ?? '';
    return Card(
      child: InkWell(
        onTap: () => _launchGame(context),
        child: Column(
          children: [
            Icon(_gameIcon(templateId), size: 48),
            Text('Chơi game: $templateId'),
            Text('Nhấn để mở game', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Future<void> _launchGame(BuildContext context) async {
    final launcher = MediaPipeGameLauncher();
    await launcher.launchFromBlockContent(block.content);
  }
}
```

### 6. MediaPipe Game Launcher (`mediapipe_game_launcher.dart`)

**Extends existing `ElectronProcessLauncher` pattern:**

```dart
class MediaPipeGameLauncher {
  final GameLaunchContractService _contractService;
  final ElectronProcessLauncher _launcher;

  Future<void> launchFromBlockContent(Map<String, dynamic> content) async {
    final contract = GameLaunchContract(
      packagePath: '', // not from package
      sessionId: 'inline_${DateTime.now().millisecondsSinceEpoch}',
      outputDir: await _paths.sessionOutputPath(sessionId),
      mode: GameLaunchMode.newSession,
    );
    // Extend contract with gamePayload
    final extendedContract = {
      ...contract.toJson(),
      'gamePayload': content['gamePayload'] ?? _mockPayloadFor(content['templateId']),
    };
    
    final contractPath = await _writeExtendedContract(extendedContract);
    await _launcher.launch(
      contractPath: contractPath,
      executablePath: _resolveGameRuntimePath(),
    );
  }
  
  String _resolveGameRuntimePath() {
    // Look for game-runtime/mediapipe-game.exe relative to app exe
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return p.join(exeDir, 'game-runtime', 'mediapipe-game.exe');
  }
}
```

### 7. BlockDispatcher Modification

```dart
// Add to switch in block_dispatcher.dart:
'GAME' => GameBlockWidget(
  block: block,
  runtimeSessionId: runtimeSessionId,
),
```

---

## Data Flow

### Flow 1: Standalone Game (teacher demo)

```
Giáo viên double-click mediapipe-game.exe
  → Electron opens → Game Launcher UI (6 cards)
  → Teacher picks "Runner Quiz"
  → GameEngine.init() with createMockRunnerQuiz()
  → Play game on keyboard
  → Game finish → show result screen
  → "Quay lại" → pick another game
```

### Flow 2: Game from .eduvi file (Flutter → Electron)

```
Giáo viên drop .eduvi file vào eduvi_viewer.exe
  → EduviPackageClassifier detects type=game
  → GameSessionManager writes launch contract JSON
  → Flutter spawns game-runtime/mediapipe-game.exe --launch-contract=<path>
  → Electron reads contract → auto-starts game
  → Game finish → writes game.result.json to outputDir
  → Flutter reads result → shows SnackBar
```

### Flow 3: GAME block inside slide (Flutter → Electron)

```
Giáo viên opens .eduvi slide → PresentationScreen
  → Slide contains GAME block
  → BlockDispatcher renders GameBlockWidget (card with "Chơi game" button)
  → Teacher clicks → MediaPipeGameLauncher
  → Writes contract with gamePayload from block.content
  → Spawns Electron → game plays
  → Result written → Flutter reads back
```

---

## Game JS Files — Zero Modification Strategy

**Principle: Copy 10 JS files NGUYÊN VẸN from web FE. Only modify 1 thing:**

1. `mediapipe-engine.js` — Change CDN URLs to local paths (or add conditional check)

**No other files need changes because:**
- All game logic uses Canvas 2D (works in Electron's Chromium)
- Keyboard events use `window.addEventListener` (works in Electron)
- Camera uses `navigator.mediaDevices.getUserMedia` (works in Electron with permission)
- All coordinates normalized (0..1) — resolution independent
- No React, no Next.js dependencies
- ES modules load via `<script type="module">` (works in Electron)

---

## Editor Components (Optional)

`editor.js` and `editor-ui.html` are **not needed** for player mode. They:
- Call `POST /api/Games/playable` (backend API, unavailable offline)
- Provide teacher config UI (template selection, settings)

**Decision:** Exclude from Phase 1-3. Can add later for offline game config editing if needed.

---

## Offline Asset Requirements

### MediaPipe WASM files (from npm @mediapipe/tasks-vision@0.10.18)
- `vision_wasm_internal.js` (~180KB)
- `vision_wasm_internal.wasm` (~8MB)
- `vision_wasm_nosimd_internal.js`
- `vision_wasm_nosimd_internal.wasm`
- `vision.js` (module entry)

### MediaPipe Model
- `hand_landmarker.task` (~12MB)
- Source: `https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task`

### Total offline bundle size estimate
- Game JS files: ~120KB
- MediaPipe WASM: ~16MB
- MediaPipe model: ~12MB
- Electron runtime: ~150MB
- **Total game-runtime folder: ~180MB**

---

## Testing Strategy

### Electron app tests
1. **Smoke test**: Launch standalone → select Runner Quiz → play → finish → result shown
2. **Contract mode**: Launch with `--launch-contract` → game auto-starts
3. **All 6 blueprints**: Each game starts and finishes correctly with mock data
4. **Camera games**: HOVER_SELECT and DRAG_DROP request camera permission → get landmarks
5. **Offline**: Disconnect internet → all games still work (WASM + model local)

### Flutter integration tests
1. **GAME block rendering**: Slide with GAME block → shows GameBlockWidget
2. **Launch game from block**: Click "Chơi game" → Electron process spawned
3. **Result collection**: Game finishes → result.json written → Flutter reads it

---

## Phased Implementation

### Phase 1: Skeleton Electron App + 1 Keyboard Game
- Create `apps/mediapipe-game-desktop/` project structure
- `main.js`, `preload.js`, `index.html`, `renderer.js`, `styles.css`
- Copy 8 game JS files (exclude editor.js, editor-ui.html)
- Standalone mode with game launcher UI
- Test: Runner Quiz plays and finishes with mock data

### Phase 2: All 6 Games + Contract Mode
- Wire all 6 blueprints in renderer.js
- Implement `--launch-contract` mode in main.js
- IPC for getLaunchContract, saveGameResult, saveProgressSnapshot
- Test: All games work standalone + contract mode

### Phase 3: Camera Games + MediaPipe Offline
- Download and bundle MediaPipe WASM + model
- Modify mediapipe-engine.js for local asset paths
- Camera permission handling in main.js
- Test: HOVER_SELECT and DRAG_DROP work with hand tracking, offline

### Phase 4: Flutter Integration + GAME Block
- Create `lib/features/game_player/` folder
- `game_block_widget.dart` + `mediapipe_game_launcher.dart`
- Modify `BlockDispatcher` to handle GAME blocks
- Modify `ElectronProcessLauncher` candidate paths to include game-runtime
- Test: GAME block in slide → launches Electron game

### Phase 5: Build + Bundle + Polish
- `electron-builder.yml` config for Windows NSIS/portable
- Build script: Flutter release + Electron package → zip
- App icon, window title, menu
- Zip as `eduviviewer-windows-teacher-pack.zip`
- Test: Unzip on clean Windows → everything works offline

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| MediaPipe WASM won't load from file:// | Serve via Electron custom protocol (app://) or use loadURL with proper CSP |
| Camera permission denied | Show clear VN prompt: "Cho phép camera để chơi game tay" |
| ES module import fails | Use Electron's `loadFile()` which supports modules natively |
| WebView2 runtime missing on old Windows | Game-runtime uses Electron (Chromium embedded), independent of WebView2 |
| Large bundle size (~180MB game-runtime) | Accept for offline-first; teacher installs once |

---

## Success Criteria

1. Giáo viên giải nén zip → double-click `eduvi_viewer.exe` → mở slide bình thường.
2. Slide có block GAME → hiện nút "Chơi game" → click → game chạy trong Electron.
3. Giáo viên double-click `game-runtime/mediapipe-game.exe` → chơi demo 6 game.
4. Tất cả hoạt động **offline** — không cần internet.
5. Keyboard games: chơi được bằng bàn phím (arrows, WASD, 1234).
6. Camera games: HOVER_SELECT, DRAG_DROP detect tay qua webcam.
