/**
 * EduVi Game Launcher — Electron Renderer
 * ========================================
 * Contract-first runtime player for EduVi camera and keyboard games.
 */

import { GAME_BLUEPRINTS, createMockRunnerQuiz, createMockSnakeQuiz, createMockRunnerRace, createMockSnakeDuel } from './game/api-contracts.js';
import { MediaPipeTracker, GameEngine } from './game/mediapipe-engine.js';

// ── DOM references ───────────────────────────────────────────────────────────

const $launcher   = document.getElementById('launcher');
const $stage      = document.getElementById('stage');
const $result     = document.getElementById('result');
const $stageTitle = document.getElementById('stage-title');
const $stageBody  = document.getElementById('stage-body');
const $video      = document.getElementById('game-video');
const $canvas     = document.getElementById('game-canvas');
const $resultScore  = document.getElementById('result-score');
const $resultDetail = document.getElementById('result-detail');
const $btnFullscreen = document.getElementById('btn-fullscreen');
const $appVersion    = document.getElementById('app-version');

// ── State ────────────────────────────────────────────────────────────────────

let currentEngine = null;
let currentTracker = null;

async function closeRuntimeApp() {
  if (window.electronAPI && typeof window.electronAPI.closeApp === 'function') {
    await window.electronAPI.closeApp();
    return;
  }

  if (typeof window.close === 'function') {
    window.close();
  }
}

async function handleGameFinished(playable, result) {
  if (window.electronAPI) {
    try {
      await window.electronAPI.saveGameResult({
        templateId: playable.templateId,
        gameId: playable.gameId,
        result,
        finishedAt: new Date().toISOString(),
      });
    } catch (err) {
      console.warn('[Renderer] Failed to save result:', err);
    }
  }

  try {
    await closeRuntimeApp();
  } catch (err) {
    console.warn('[Renderer] Failed to close app:', err);
  }
}

// ── Mock data generators ─────────────────────────────────────────────────────

function getMockPlayable(templateId) {
  switch (templateId) {
    case GAME_BLUEPRINTS.RUNNER_QUIZ:
      return createMockRunnerQuiz();

    case GAME_BLUEPRINTS.SNAKE_QUIZ:
      return createMockSnakeQuiz();

    case GAME_BLUEPRINTS.HOVER_SELECT:
      return {
        gameId: 'mock-hover-001',
        templateId: 'HOVER_SELECT',
        version: '1.0',
        settings: { mirror: true, timeLimitSec: 60, hoverHoldMs: 2000, pinchThreshold: 0.045 },
        scene: { title: 'Địa lí Việt Nam' },
        payload: {
          prompt: 'Thủ đô của Việt Nam là thành phố nào?',
          choices: [
            { id: 'a', text: 'Đà Nẵng',        zone: { x: 0.08, y: 0.28, w: 0.38, h: 0.18 } },
            { id: 'b', text: 'Hà Nội',          zone: { x: 0.54, y: 0.28, w: 0.38, h: 0.18 } },
            { id: 'c', text: 'TP. Hồ Chí Minh', zone: { x: 0.08, y: 0.56, w: 0.38, h: 0.18 } },
            { id: 'd', text: 'Hải Phòng',       zone: { x: 0.54, y: 0.56, w: 0.38, h: 0.18 } },
          ],
          correctChoiceId: 'b',
        },
      };

    case GAME_BLUEPRINTS.DRAG_DROP:
      return {
        gameId: 'mock-dragdrop-001',
        templateId: 'DRAG_DROP',
        version: '1.0',
        settings: { mirror: true, timeLimitSec: 60, hoverHoldMs: 2000, pinchThreshold: 0.045 },
        scene: { title: 'Ghép thủ đô' },
        payload: {
          prompt: 'Kéo tên thủ đô vào đúng quốc gia',
          items: [
            { id: 'item-hanoi',  label: 'Hà Nội', start: { x: 0.15, y: 0.75 }, size: { w: 0.18, h: 0.12 } },
            { id: 'item-tokyo',  label: 'Tokyo',  start: { x: 0.55, y: 0.75 }, size: { w: 0.18, h: 0.12 } },
          ],
          dropZones: [
            { id: 'zone-vn', label: 'Việt Nam',  acceptsItemId: 'item-hanoi', zone: { x: 0.12, y: 0.2, w: 0.32, h: 0.22 } },
            { id: 'zone-jp', label: 'Nhật Bản',  acceptsItemId: 'item-tokyo', zone: { x: 0.56, y: 0.2, w: 0.32, h: 0.22 } },
          ],
        },
      };

    case GAME_BLUEPRINTS.RUNNER_RACE:
      return {
        gameId: 'mock-runner-race-001',
        templateId: 'RUNNER_RACE',
        version: '1.0',
        settings: { mirror: false, timeLimitSec: 0, hoverHoldMs: 0, pinchThreshold: 0 },
        scene: { title: 'Cuộc Đua 2 Người!' },
        payload: {
          theme: 'castle',
          characterName: 'P1 vs P2',
          questions: [
            {
              id: 'q1', prompt: '5 + 7 = ?',
              choices: [
                { id: 'a', text: '10' }, { id: 'b', text: '12' },
                { id: 'c', text: '11' }, { id: 'd', text: '13' },
              ],
              correctChoiceId: 'b',
            },
            {
              id: 'q2', prompt: '9 × 3 = ?',
              choices: [
                { id: 'a', text: '24' }, { id: 'b', text: '27' },
                { id: 'c', text: '30' }, { id: 'd', text: '21' },
              ],
              correctChoiceId: 'b',
            },
          ],
        },
      };

    case GAME_BLUEPRINTS.SNAKE_DUEL:
      return {
        gameId: 'mock-snake-duel-001',
        templateId: 'SNAKE_DUEL',
        version: '1.0',
        settings: { mirror: false, timeLimitSec: 0, hoverHoldMs: 0, pinchThreshold: 0 },
        scene: { title: 'Snake Duel 2 Người!' },
        payload: {
          gridSize: 20,
          speed: 'normal',
          theme: 'neon',
          questions: [
            {
              id: 'q1', prompt: '2 × 8 = ?',
              choices: [
                { id: 'a', text: '14' }, { id: 'b', text: '16' },
                { id: 'c', text: '18' }, { id: 'd', text: '12' },
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

function extractPlayableFromSourceEduvi(sourceEduvi) {
  if (!sourceEduvi || typeof sourceEduvi !== 'object') {
    return null;
  }

  const games = sourceEduvi.games;
  if (!Array.isArray(games) || games.length === 0) {
    return null;
  }

  const firstGame = games[0];
  if (!firstGame || typeof firstGame !== 'object') {
    return null;
  }

  const resultJson = firstGame.resultJson;
  if (!resultJson || typeof resultJson !== 'object') {
    return null;
  }

  const templateId =
    typeof resultJson.templateId === 'string' && resultJson.templateId.trim()
      ? resultJson.templateId.trim()
      : typeof firstGame.templateCode === 'string' && firstGame.templateCode.trim()
        ? firstGame.templateCode.trim()
        : '';

  if (!templateId) {
    return null;
  }

  return {
    gameId:
      (typeof resultJson.gameId === 'string' && resultJson.gameId) ||
      (typeof firstGame.gameCode === 'string' && firstGame.gameCode) ||
      `contract-${templateId.toLowerCase()}`,
    templateId,
    version: typeof resultJson.version === 'string' ? resultJson.version : '1.0',
    settings:
      resultJson.settings && typeof resultJson.settings === 'object'
        ? resultJson.settings
        : { mirror: true, timeLimitSec: 60, hoverHoldMs: 800, pinchThreshold: 0.045 },
    scene: resultJson.scene && typeof resultJson.scene === 'object' ? resultJson.scene : {},
    payload:
      resultJson.payload && typeof resultJson.payload === 'object' ? resultJson.payload : {},
  };
}

// ── Launch game ──────────────────────────────────────────────────────────────

async function launchGame(templateId, playableOverride) {
  const playable = playableOverride || getMockPlayable(templateId);
  if (!playable) {
    console.error('[Renderer] No playable data for', templateId);
    return;
  }

  const isCamera = templateId === GAME_BLUEPRINTS.HOVER_SELECT
    || templateId === GAME_BLUEPRINTS.DRAG_DROP;

  // Toggle keyboard mode
  if (!isCamera) {
    $stageBody.classList.add('keyboard-mode');
    $stageBody.classList.remove('camera-corner-mode');
  } else {
    $stageBody.classList.remove('keyboard-mode');
    $stageBody.classList.add('camera-corner-mode');
  }

  // Show stage
  if ($launcher) {
    $launcher.classList.add('hidden');
  }
  if ($result) {
    $result.classList.add('hidden');
  }
  if ($stage) {
    $stage.classList.remove('hidden');
  }
  if ($stageTitle) {
    $stageTitle.textContent = playable.scene?.title || templateId;
  }

  // Resize canvas to fill stage body
  resizeCanvas();

  // Init tracker for camera games
  let tracker = null;
  if (isCamera) {
    try {
      tracker = new MediaPipeTracker({
        videoEl: $video,
        onFrame: () => {},
      });
      currentTracker = tracker;
    } catch (err) {
      console.error('[Renderer] Failed to init MediaPipeTracker:', err);
    }
  }

  // Init engine
  const engine = new GameEngine({
    canvasEl: $canvas,
    videoEl: $video,
    playable,
    tracker: tracker || { onFrame: null, init: async () => {}, start: () => {}, stop: () => {} },
    onStatus: (msg) => console.log('[Game]', msg),
    onFinish: (result) => {
      void handleGameFinished(playable, result);
    },
  });

  currentEngine = engine;

  try {
    await engine.init();
  } catch (err) {
    console.error('[Renderer] Engine init failed:', err);
    cleanup();
    void closeRuntimeApp();
  }
}

// ── Show result ──────────────────────────────────────────────────────────────

function showResult(result, playable) {
  const total = result.total || 1;
  const correct = result.correct || 0;
  const pct = Math.round((correct / total) * 100);

  $resultScore.textContent = `${pct}%`;
  $resultScore.style.color = pct >= 70 ? '#22c55e' : pct >= 40 ? '#fbbf24' : '#ef4444';
  $resultDetail.textContent = `${correct} / ${total} câu đúng — ${playable.scene?.title || ''}`;

  $stage.classList.add('hidden');
  $result.classList.remove('hidden');
}

// ── Cleanup ──────────────────────────────────────────────────────────────────

function cleanup() {
  if (currentEngine) {
    try { currentEngine.dispose(); } catch (_) {}
    currentEngine = null;
  }
  if (currentTracker) {
    try { currentTracker.stop(); } catch (_) {}
    currentTracker = null;
  }
  // Stop any active video streams
  if ($video.srcObject) {
    $video.srcObject.getTracks().forEach(t => t.stop());
    $video.srcObject = null;
  }
}

function showLauncher() {
  cleanup();
  if ($stage) {
    $stage.classList.add('hidden');
  }
  if ($result) {
    $result.classList.add('hidden');
  }
  void closeRuntimeApp();
}

function resizeCanvas() {
  const rect = $stageBody.getBoundingClientRect();
  $canvas.style.width = rect.width + 'px';
  $canvas.style.height = rect.height + 'px';
}

// ── Contract mode ────────────────────────────────────────────────────────────

async function checkContractMode() {
  if (!window.electronAPI) return;

  try {
    const contract = await window.electronAPI.getLaunchContract();
    if (!contract) {
      if ($stageTitle) {
        $stageTitle.textContent = 'Chưa tìm thấy phiên game';
      }
      setTimeout(() => {
        void closeRuntimeApp();
      }, 1200);
      return;
    }

    let playable = contract.gamePayload || null;

    if (!playable && typeof window.electronAPI.readSourceEduvi === 'function') {
      const sourceEduvi = await window.electronAPI.readSourceEduvi();
      playable = extractPlayableFromSourceEduvi(sourceEduvi);
    }

    if (playable && playable.templateId) {
      console.log('[Renderer] Contract mode — auto-starting game', playable.templateId);
      launchGame(playable.templateId, playable);
    }
  } catch (err) {
    console.warn('[Renderer] Failed to read launch contract:', err);
  }
}

// ── Event listeners ──────────────────────────────────────────────────────────

if ($btnFullscreen) {
  $btnFullscreen.addEventListener('click', () => {
    if (window.electronAPI) {
      window.electronAPI.toggleFullscreen();
    }
  });
}

window.addEventListener('resize', () => {
  if (!$stage.classList.contains('hidden')) {
    resizeCanvas();
  }
});

// ── Init ─────────────────────────────────────────────────────────────────────

(async function init() {
  if (window.electronAPI) {
    try {
      const ver = await window.electronAPI.getAppVersion();
      if ($appVersion) {
        $appVersion.textContent = `v${ver}`;
      }
    } catch (_) {}
  }

  // Check for contract auto-launch
  checkContractMode();
})();
