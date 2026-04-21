/**
 * MediaPipe Game Engine (ES Modules)
 * =================================
 *
 * Separation of concerns:
 * - MediaPipeTracker: camera + hand landmark detection
 * - GameEngine: render loop + blueprint selection
 * - Blueprint logic: HoverSelectGame, DragDropGame
 *
 * Mirroring requirement:
 * - UI should mirror both video and canvas (CSS transform scaleX(-1)).
 * - Landmark x must be flipped when mapping to canvas:
 *   xCanvas = (1 - landmark.x) * canvas.width
 */

import { GAME_BLUEPRINTS } from './api-contracts.js';
import { KeyboardInput } from './keyboard-input.js';
import { DualKeyboardInput } from './dual-keyboard-input.js';
import { RunnerQuizGame } from './runner-quiz-game.js';
import { SnakeQuizGame } from './snake-quiz-game.js';
import { RunnerRaceGame } from './runner-race-game.js';
import { SnakeDuelGame } from './snake-duel-game.js';

const KEYBOARD_BLUEPRINTS = new Set([
  GAME_BLUEPRINTS.RUNNER_QUIZ,
  GAME_BLUEPRINTS.SNAKE_QUIZ,
  GAME_BLUEPRINTS.RUNNER_RACE,
  GAME_BLUEPRINTS.SNAKE_DUEL,
]);

const DUAL_KEYBOARD_BLUEPRINTS = new Set([
  GAME_BLUEPRINTS.RUNNER_RACE,
  GAME_BLUEPRINTS.SNAKE_DUEL,
]);

const TASKS_VISION_VERSION = '0.10.18';
const DEFAULT_TASKS_VISION_WASM_BASE_URL =
  `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${TASKS_VISION_VERSION}/wasm`;
const DEFAULT_HAND_LANDMARKER_MODEL_URL =
  'https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task';
let TASKS_VISION_WASM_BASE_URL = DEFAULT_TASKS_VISION_WASM_BASE_URL;
let HAND_LANDMARKER_MODEL_URL = DEFAULT_HAND_LANDMARKER_MODEL_URL;

// Override with local paths when running in Electron
if (typeof window !== 'undefined' && window.electronAPI) {
  window.electronAPI.getLocalMediaPipePaths().then(paths => {
    if (paths && paths.wasmBaseUrl) TASKS_VISION_WASM_BASE_URL = paths.wasmBaseUrl;
    if (paths && paths.modelUrl) HAND_LANDMARKER_MODEL_URL = paths.modelUrl;
  });
}

const PERFORMANCE_PROFILE = (() => {
  if (typeof globalThis === 'undefined' || !globalThis.navigator) {
    return { detectFps: 14, renderFps: 24, canvasScale: 0.66 };
  }

  const nav = globalThis.navigator;
  const cores = Number(nav.hardwareConcurrency || 4);
  const memory = Number(nav.deviceMemory || 4);
  const isLowEndDevice = cores <= 4 || memory <= 4;

  if (isLowEndDevice) {
    return { detectFps: 20, renderFps: 40, canvasScale: 0.75 };
  }

  return { detectFps: 30, renderFps: 60, canvasScale: 1.0 };
})();

const TARGET_DETECTION_FPS = PERFORMANCE_PROFILE.detectFps;
const TARGET_RENDER_FPS = PERFORMANCE_PROFILE.renderFps;
const CANVAS_RENDER_SCALE = PERFORMANCE_PROFILE.canvasScale;
const MAX_TEXT_LAYOUT_CACHE_SIZE = 300;
const textLayoutCache = new Map();
const HAND_SMOOTHING_ALPHA = 0.55;

const CHOICE_BADGE_LABELS = ['A', 'B', 'C', 'D'];
const CHOICE_BADGE_COLORS = [
  'rgba(59,130,246,0.9)',
  'rgba(139,92,246,0.9)',
  'rgba(16,185,129,0.9)',
  'rgba(245,158,11,0.9)',
];

// Kahoot-style fixed zones used when htmlMode=true for HoverSelectGame.
// Four quadrants: A(top-left), B(top-right), C(bottom-left), D(bottom-right).
// These MUST match the CSS absolute positions in HoverSelectGamePlayer.
const HOVER_SELECT_HTML_ZONES = [
  { x: 0,     y: 0.44,  w: 0.495, h: 0.27  }, // A – top-left
  { x: 0.505, y: 0.44,  w: 0.495, h: 0.27  }, // B – top-right
  { x: 0,     y: 0.725, w: 0.495, h: 0.27  }, // C – bottom-left
  { x: 0.505, y: 0.725, w: 0.495, h: 0.27  }, // D – bottom-right
];

/**
 * @typedef {{x:number,y:number,z?:number}} Landmark
 */

/**
 * @typedef {{
 *   landmarks: Landmark[] | null;
 *   hasHand: boolean;
 *   isPinching: boolean;
 *   isPointing: boolean;
 *   palmCenter?: {x:number,y:number};
 *   indexTip?: {x:number,y:number};
 *   nowMs: number;
 * }} InputFrame
 */

function clamp01(v) {
  return Math.max(0, Math.min(1, v));
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function smoothPoint(prev, next, alpha) {
  if (!prev) return next;
  return {
    x: lerp(prev.x, next.x, alpha),
    y: lerp(prev.y, next.y, alpha),
  };
}

function dist2(a, b) {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return Math.sqrt(dx * dx + dy * dy);
}

/**
 * Detects a closed-fist gesture from MediaPipe hand landmarks.
 * Returns true when ≥3 of the 4 fingers are curled inward toward the palm.
 * Uses tip-to-wrist vs PIP-to-wrist distance so it works at any hand orientation.
 * @param {Landmark[]} landmarks
 */
/**
 * Detects a single-index-finger pointing gesture (☝️).
 * Index finger is extended; at least 2 of the other 3 fingers are curled.
 * Used as the "grab" gesture in DragDropGame.
 * @param {Landmark[]} landmarks
 */
function detectIndexPointing(landmarks) {
  if (!landmarks || landmarks.length < 21) return false;
  const wrist     = landmarks[0];
  const handScale = dist2(wrist, landmarks[9]); // wrist → middle MCP
  if (handScale < 0.01) return false;

  // Index finger must be clearly extended (tip much further from wrist than PIP)
  const indexExtended = dist2(landmarks[8], wrist) > dist2(landmarks[6], wrist) + handScale * 0.10;

  // At least 2 of the other 3 fingers must be curled
  const others = [
    { tip: 12, pip: 10 }, // middle
    { tip: 16, pip: 14 }, // ring
    { tip: 20, pip: 18 }, // pinky
  ];
  let curled = 0;
  for (const { tip, pip } of others) {
    if (dist2(landmarks[tip], wrist) <= dist2(landmarks[pip], wrist) + handScale * 0.30) curled++;
  }
  return indexExtended && curled >= 2;
}

function mapLandmarkToCanvas(landmark, canvas) {
  return {
    x: (1 - landmark.x) * canvas.width,
    y: landmark.y * canvas.height,
  };
}

function rectToCanvas(normRect, canvas) {
  return {
    x: normRect.x * canvas.width,
    y: normRect.y * canvas.height,
    w: normRect.w * canvas.width,
    h: normRect.h * canvas.height,
  };
}

function pointInRect(pt, rect) {
  return pt.x >= rect.x && pt.x <= rect.x + rect.w && pt.y >= rect.y && pt.y <= rect.y + rect.h;
}

function drawRoundedRect(ctx, x, y, w, h, r) {
  const radius = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.arcTo(x + w, y, x + w, y + h, radius);
  ctx.arcTo(x + w, y + h, x, y + h, radius);
  ctx.arcTo(x, y + h, x, y, radius);
  ctx.arcTo(x, y, x + w, y, radius);
  ctx.closePath();
}

function drawGameContentPanel(ctx, canvas, options = {}) {
  const { width, height } = canvas;
  const x = options.x ?? width * 0.035;
  const y = options.y ?? height * 0.06;
  const w = options.w ?? width * 0.93;
  const h = options.h ?? height * 0.8;
  const radius = options.radius ?? 24;

  ctx.save();
  drawRoundedRect(ctx, x, y, w, h, radius);
  ctx.fillStyle = 'rgba(15,23,42,0.55)';
  ctx.fill();
  ctx.lineWidth = 2;
  ctx.strokeStyle = 'rgba(255,255,255,0.24)';
  ctx.stroke();
  ctx.restore();
}

function wrapTextLines(ctx, text, maxWidth, maxLines, enableEllipsis = true) {
  const raw = String(text ?? '').trim();
  if (!raw) return [''];

  const words = raw.split(/\s+/);
  const lines = [];
  let current = '';

  const pushLine = (line) => {
    if (lines.length < maxLines) lines.push(line);
  };

  for (const word of words) {
    const candidate = current ? `${current} ${word}` : word;
    if (ctx.measureText(candidate).width <= maxWidth) {
      current = candidate;
      continue;
    }

    if (!current) {
      // Fallback for a very long token without spaces.
      let partial = '';
      for (const ch of word) {
        const next = partial + ch;
        if (ctx.measureText(next).width <= maxWidth) {
          partial = next;
        } else {
          break;
        }
      }
      pushLine(partial || word.slice(0, 1));
      current = word.slice((partial || word.slice(0, 1)).length).trim();
    } else {
      pushLine(current);
      current = word;
    }

    if (lines.length >= maxLines) break;
  }

  if (lines.length < maxLines && current) {
    pushLine(current);
  }

  // Ellipsis when truncated.
  const consumedWordCount = lines.join(' ').split(/\s+/).filter(Boolean).length;
  const truncated = consumedWordCount < words.length;
  if (enableEllipsis && truncated && lines.length > 0) {
    const lastIdx = lines.length - 1;
    let last = lines[lastIdx];
    const ellipsis = '...';
    while (last && ctx.measureText(last + ellipsis).width > maxWidth) {
      last = last.slice(0, -1);
    }
    lines[lastIdx] = (last || '').trimEnd() + ellipsis;
  }

  return lines.slice(0, maxLines);
}

function drawCenteredMultilineText(ctx, text, centerX, centerY, maxWidth, lineHeight, maxLines) {
  const lines = wrapTextLines(ctx, text, maxWidth, maxLines);
  const blockHeight = lines.length * lineHeight;
  let y = centerY - blockHeight / 2 + lineHeight / 2;

  for (const line of lines) {
    ctx.fillText(line, centerX, y);
    y += lineHeight;
  }
}

function drawAutoFitTextInRect(ctx, text, rect, options = {}) {
  const {
    paddingX = 12,
    paddingY = 8,
    minFontPx = 10,
    maxFontPx = 18,
    maxLines = 3,
    fontWeight = 600,
    ellipsis = true,
  } = options;

  const availableWidth = Math.max(12, rect.w - paddingX * 2);
  const availableHeight = Math.max(12, rect.h - paddingY * 2);

  const cacheKey = [
    String(text ?? ''),
    Math.round(rect.w),
    Math.round(rect.h),
    paddingX,
    paddingY,
    minFontPx,
    maxFontPx,
    maxLines,
    fontWeight,
    ellipsis,
  ].join('|');

  const cached = textLayoutCache.get(cacheKey);
  if (cached) {
    ctx.font = cached.font;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    const blockHeight = cached.lines.length * cached.lineHeight;
    let y = rect.y + rect.h / 2 - blockHeight / 2 + cached.lineHeight / 2;
    const x = rect.x + rect.w / 2;

    for (const line of cached.lines) {
      ctx.fillText(line, x, y);
      y += cached.lineHeight;
    }
    return;
  }

  let chosenFont = minFontPx;
  let chosenLineHeight = Math.max(12, Math.round(minFontPx * 1.25));
  let chosenLines = [''];

  for (let fontPx = maxFontPx; fontPx >= minFontPx; fontPx -= 1) {
    const lineHeight = Math.max(12, Math.round(fontPx * 1.25));
    const allowedLines = Math.max(1, Math.min(maxLines, Math.floor(availableHeight / lineHeight)));
    if (allowedLines <= 0) continue;

    ctx.font = `${fontWeight} ${fontPx}px system-ui, -apple-system, Segoe UI, Roboto, Arial`;
    const lines = wrapTextLines(ctx, text, availableWidth, allowedLines, ellipsis);
    const blockHeight = lines.length * lineHeight;

    if (blockHeight <= availableHeight) {
      chosenFont = fontPx;
      chosenLineHeight = lineHeight;
      chosenLines = lines;
      break;
    }
  }

  const resolvedFont = `${fontWeight} ${chosenFont}px system-ui, -apple-system, Segoe UI, Roboto, Arial`;
  ctx.font = resolvedFont;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';

  const blockHeight = chosenLines.length * chosenLineHeight;
  let y = rect.y + rect.h / 2 - blockHeight / 2 + chosenLineHeight / 2;
  const x = rect.x + rect.w / 2;

  for (const line of chosenLines) {
    ctx.fillText(line, x, y);
    y += chosenLineHeight;
  }

  if (textLayoutCache.size >= MAX_TEXT_LAYOUT_CACHE_SIZE) {
    const oldestKey = textLayoutCache.keys().next().value;
    if (oldestKey) textLayoutCache.delete(oldestKey);
  }
  textLayoutCache.set(cacheKey, {
    font: resolvedFont,
    lineHeight: chosenLineHeight,
    lines: chosenLines,
  });
}

function isQuestionLike(item) {
  return Boolean(
    item
      && typeof item === 'object'
      && typeof item.prompt === 'string'
      && Array.isArray(item.choices)
      && item.choices.length > 0,
  );
}

function normalizeQuestionBasedPayload(payload) {
  if (Array.isArray(payload)) {
    return isQuestionLike(payload[0]) ? { questions: payload } : payload;
  }

  if (!payload || typeof payload !== 'object') return payload;

  if (Array.isArray(payload.questions)) return payload;

  const nestedKeys = ['payload', 'data', 'result', 'playable', 'game'];
  for (const key of nestedKeys) {
    const nested = payload[key];
    if (nested && typeof nested === 'object' && Array.isArray(nested.questions)) {
      return {
        ...nested,
        ...payload,
        questions: nested.questions,
      };
    }
  }

  if (Array.isArray(payload.rounds) && isQuestionLike(payload.rounds[0])) {
    return { ...payload, questions: payload.rounds };
  }

  if (Array.isArray(payload.items) && isQuestionLike(payload.items[0])) {
    return { ...payload, questions: payload.items };
  }

  if (isQuestionLike(payload)) {
    return { questions: [payload] };
  }

  return payload;
}

async function importTasksVision() {
  // Runtime ESM import from CDN (do not bundle).
  const mod = await import(
    /* webpackIgnore: true */ 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.18'
  );
  return {
    HandLandmarker: mod.HandLandmarker,
    FilesetResolver: mod.FilesetResolver,
  };
}

export class MediaPipeTracker {
  /**
   * @param {{
   *  videoEl: HTMLVideoElement;
   *  onFrame: (results: any) => void;
   *  options?: {
   *    numHands?: number;
   *    minHandDetectionConfidence?: number;
   *    minHandPresenceConfidence?: number;
   *    minTrackingConfidence?: number;
   *  }
   * }} params
   */
  constructor({ videoEl, onFrame, options = {} }) {
    this.videoEl = videoEl;
    this.onFrame = onFrame;
    this.options = options;

    this.handLandmarker = null;
    this.stream = null;
    this.rafId = null;
    this.lastVideoTime = -1;
    this.lastDetectAtMs = 0;
    this.isReady = false;
    this._cancelled = false;
  }

  async init() {
    const { HandLandmarker, FilesetResolver } = await importTasksVision();
    if (this._cancelled) return;

    const wasmBaseCandidates = [
      DEFAULT_TASKS_VISION_WASM_BASE_URL,
      TASKS_VISION_WASM_BASE_URL,
    ].filter((value, index, arr) => value && arr.indexOf(value) === index);

    const modelCandidates = [
      DEFAULT_HAND_LANDMARKER_MODEL_URL,
      HAND_LANDMARKER_MODEL_URL,
    ].filter((value, index, arr) => value && arr.indexOf(value) === index);

    let lastInitError = null;

    for (const wasmBaseUrl of wasmBaseCandidates) {
      if (this._cancelled) return;

      try {
        const vision = await FilesetResolver.forVisionTasks(wasmBaseUrl);
        if (this._cancelled) return;

        const createLandmarker = async (delegate, modelAssetPath) =>
          HandLandmarker.createFromOptions(vision, {
            baseOptions: {
              modelAssetPath,
              delegate,
            },
            runningMode: 'VIDEO',
            numHands: this.options.numHands ?? 1,
            minHandDetectionConfidence:
              this.options.minHandDetectionConfidence ?? 0.5,
            minHandPresenceConfidence:
              this.options.minHandPresenceConfidence ?? 0.5,
            minTrackingConfidence: this.options.minTrackingConfidence ?? 0.5,
          });

        for (const modelAssetPath of modelCandidates) {
          if (this._cancelled) return;

          try {
            this.handLandmarker = await createLandmarker('GPU', modelAssetPath);
            break;
          } catch (gpuErr) {
            // eslint-disable-next-line no-console
            console.warn(
              `[MediaPipe] GPU delegate unavailable (wasm=${wasmBaseUrl}, model=${modelAssetPath}), falling back to CPU.`,
              gpuErr,
            );
            try {
              this.handLandmarker = await createLandmarker('CPU', modelAssetPath);
              break;
            } catch (cpuErr) {
              lastInitError = cpuErr;
              // eslint-disable-next-line no-console
              console.warn(
                `[MediaPipe] CPU delegate failed (wasm=${wasmBaseUrl}, model=${modelAssetPath}).`,
                cpuErr,
              );
            }
          }
        }

        if (this.handLandmarker) {
          break;
        }
      } catch (visionErr) {
        lastInitError = visionErr;
        // eslint-disable-next-line no-console
        console.warn(
          `[MediaPipe] Failed to initialize vision with wasm base: ${wasmBaseUrl}`,
          visionErr,
        );
      }
    }

    if (!this.handLandmarker) {
      throw (lastInitError ?? new Error('Unable to initialize MediaPipe hand landmarker.'));
    }

    if (this._cancelled) return;

    this.stream = await navigator.mediaDevices.getUserMedia({
      video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: 'user', frameRate: { ideal: 30 } },
      audio: false,
    });

    // If stop() was called while we were awaiting getUserMedia, release the
    // tracks we just acquired and bail out silently.
    if (this._cancelled) {
      this.stream.getTracks().forEach((t) => t.stop());
      this.stream = null;
      return;
    }

    this.videoEl.srcObject = this.stream;
    await this.videoEl.play();

    this.isReady = true;
  }

  start() {
    if (!this.handLandmarker) {
      throw new Error('MediaPipeTracker.start() called before init()');
    }

    const tick = () => {
      if (this.handLandmarker && this.videoEl.readyState >= 2) {
        const nowMs = performance.now();
        const minDetectInterval = 1000 / TARGET_DETECTION_FPS;
        const currentTime = this.videoEl.currentTime;
        if (currentTime !== this.lastVideoTime && nowMs - this.lastDetectAtMs >= minDetectInterval) {
          this.lastVideoTime = currentTime;
          this.lastDetectAtMs = nowMs;
          const results = this.handLandmarker.detectForVideo(this.videoEl, nowMs);
          this.onFrame(results);
        }
      }
      this.rafId = requestAnimationFrame(tick);
    };

    this.rafId = requestAnimationFrame(tick);
  }

  stop() {
    this._cancelled = true;

    if (this.rafId) cancelAnimationFrame(this.rafId);
    this.rafId = null;

    // Pause and detach the video element BEFORE stopping tracks.
    // This prevents a pending play() from a previous init() from
    // interrupting a new init() that starts immediately after.
    try { this.videoEl.pause(); } catch (_) {}
    try { this.videoEl.srcObject = null; } catch (_) {}

    if (this.stream) {
      this.stream.getTracks().forEach((t) => t.stop());
      this.stream = null;
    }
  }
}

class HoverSelectGame {
  /**
   * @param {{ playable: any; settings: any; canvas: HTMLCanvasElement }} params
   */
  constructor({ playable, settings, canvas, htmlMode = false }) {
    this.playable = playable;
    this.settings = settings;
    this.canvas = canvas;
    this.htmlMode = htmlMode;

    this.hoveringChoiceId = null;
    this.hoverStartMs = 0;
    this.selectedChoiceId = null;
    this.isCorrect = null;

    this.correctCompletedAtMs = null;
    this.wrongSelectedAtMs = null;
    this.wrongAttempts = 0;
    this._pendingWarning = null;
    this.promptFontPx = 24;
  }

  /** @param {InputFrame} frame */
  update(frame) {
    if (!frame.hasHand || !frame.indexTip) {
      this.hoveringChoiceId = null;
      this.hoverStartMs = 0;
      return;
    }

    if (this.selectedChoiceId) {
      // Allow retry if wrong selection.
      if (this.isCorrect === false && this.wrongSelectedAtMs != null) {
        if (frame.nowMs - this.wrongSelectedAtMs >= 900) {
          this.selectedChoiceId = null;
          this.isCorrect = null;
          this.wrongSelectedAtMs = null;
          this.hoveringChoiceId = null;
          this.hoverStartMs = 0;
        }
      }
      return;
    }

    const tip = frame.indexTip;
    let hit = null;

    for (let ci = 0; ci < this.playable.choices.length; ci++) {
      const c = this.playable.choices[ci];
      const zone = this.htmlMode ? (HOVER_SELECT_HTML_ZONES[ci] ?? c.zone) : c.zone;
      const rect = rectToCanvas(zone, this.canvas);
      if (pointInRect(tip, rect)) {
        hit = c.id;
        break;
      }
    }

    if (!hit) {
      this.hoveringChoiceId = null;
      this.hoverStartMs = 0;
      return;
    }

    if (hit !== this.hoveringChoiceId) {
      this.hoveringChoiceId = hit;
      this.hoverStartMs = frame.nowMs;
      // When already pointing (1 finger), skip the early return so select logic runs
      if (!frame.isPointing) return;
    }

    const elapsed = frame.nowMs - this.hoverStartMs;
    // 1-finger point = instant confirm (150 ms debounce); open hand = normal dwell timer
    const shouldSelect = frame.isPointing
      ? elapsed >= 150
      : elapsed >= this.settings.hoverHoldMs;
    if (shouldSelect) {
      this.selectedChoiceId = hit;
      this.isCorrect = hit === this.playable.correctChoiceId;

      if (this.isCorrect) {
        if (this.correctCompletedAtMs == null) this.correctCompletedAtMs = frame.nowMs;
      } else {
        this.wrongAttempts += 1;
        if (this.wrongAttempts >= 2) {
          // Max attempts reached — force complete this round as failed
          this.correctCompletedAtMs = frame.nowMs;
        } else {
          // First wrong attempt — allow retry after brief feedback
          this._pendingWarning = 'Còn 1 lần thử! Hãy chọn lại.';
          this.wrongSelectedAtMs = frame.nowMs;
        }
      }
    }
  }

  isComplete() {
    return this.correctCompletedAtMs != null;
  }

  getCompletedAtMs() {
    return this.correctCompletedAtMs;
  }

  getResult() {
    return { correct: this.isCorrect ? 1 : 0, total: 1 };
  }

  getPendingWarning() {
    if (this._pendingWarning) {
      const msg = this._pendingWarning;
      this._pendingWarning = null;
      return msg;
    }
    return null;
  }

  /** @param {{ctx: CanvasRenderingContext2D; frame: InputFrame}} params */
  render({ ctx, frame }) {
    const { width, height } = this.canvas;

    // Background (clear with identity transform, then restore current transform)
    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, width, height);
    if (!this.htmlMode) {
      ctx.fillStyle = 'rgba(0,0,0,0.35)';
      ctx.fillRect(0, 0, width, height);
    }
    ctx.restore();

    if (this.htmlMode) {
      // HTML mode: only draw the finger cursor + hover arc — UI is rendered by React
      if (frame.hasHand && frame.indexTip) {
        const p = frame.indexTip;
        ctx.save();
        ctx.beginPath();
        ctx.arc(p.x, p.y, 10, 0, Math.PI * 2);
        ctx.fillStyle = 'rgba(255,255,255,0.92)';
        ctx.fill();
        ctx.strokeStyle = 'rgba(255,255,255,0.45)';
        ctx.lineWidth = 2;
        ctx.stroke();

        if (this.hoveringChoiceId && !this.selectedChoiceId) {
          const elapsed = frame.nowMs - this.hoverStartMs;
          const t = clamp01(elapsed / this.settings.hoverHoldMs);
          ctx.beginPath();
          ctx.arc(p.x, p.y, 24, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * t);
          ctx.strokeStyle = 'rgba(255,255,255,0.9)';
          ctx.lineWidth = 5;
          ctx.stroke();
        }
        ctx.restore();
      }
      return;
    }

    drawGameContentPanel(ctx, this.canvas, {
      y: height * 0.05,
      h: height * 0.82,
    });

    const promptRect = {
      x: width * 0.16,
      y: height * 0.036,
      w: width * 0.68,
      h: Math.max(66, height * 0.094),
    };
    ctx.save();
    drawRoundedRect(ctx, promptRect.x, promptRect.y, promptRect.w, promptRect.h, 18);
    const promptGradient = ctx.createLinearGradient(
      promptRect.x,
      promptRect.y,
      promptRect.x,
      promptRect.y + promptRect.h,
    );
    promptGradient.addColorStop(0, 'rgba(15,23,42,0.78)');
    promptGradient.addColorStop(1, 'rgba(15,23,42,0.52)');
    ctx.fillStyle = promptGradient;
    ctx.fill();
    ctx.lineWidth = 1.5;
    ctx.strokeStyle = 'rgba(148,163,184,0.36)';
    ctx.stroke();
    ctx.restore();

    // Prompt
    ctx.fillStyle = '#ffffff';
    ctx.font = `700 ${this.promptFontPx}px system-ui, -apple-system, Segoe UI, Roboto, Arial`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    drawCenteredMultilineText(
      ctx,
      this.playable.prompt,
      promptRect.x + promptRect.w / 2,
      promptRect.y + promptRect.h / 2,
      promptRect.w * 0.92,
      34,
      2,
    );

    // Choices
    for (let ci = 0; ci < this.playable.choices.length; ci++) {
      const c = this.playable.choices[ci];
      const rawRect = rectToCanvas(c.zone, this.canvas);
      const capH = Math.max(128, Math.min(rawRect.h * 1.32, 164));
      const rect = { ...rawRect, y: rawRect.y + (rawRect.h - capH) / 2, h: capH };
      const isHover = this.hoveringChoiceId === c.id;
      const isSelected = this.selectedChoiceId === c.id;
      const badgeColor = CHOICE_BADGE_COLORS[ci] ?? 'rgba(255,255,255,0.5)';

      ctx.save();
      drawRoundedRect(ctx, rect.x, rect.y, rect.w, rect.h, 16);

      if (isSelected) {
        ctx.fillStyle = this.isCorrect ? 'rgba(16,185,129,0.35)' : 'rgba(239,68,68,0.35)';
      } else {
        const cardGradient = ctx.createLinearGradient(
          rect.x,
          rect.y,
          rect.x + rect.w,
          rect.y + rect.h,
        );
        if (isHover) {
          cardGradient.addColorStop(0, 'rgba(30,58,138,0.40)');
          cardGradient.addColorStop(1, 'rgba(30,41,59,0.46)');
        } else {
          cardGradient.addColorStop(0, 'rgba(51,65,85,0.56)');
          cardGradient.addColorStop(1, 'rgba(30,41,59,0.64)');
        }
        ctx.fillStyle = cardGradient;
      }
      ctx.shadowBlur = isHover ? 20 : 12;
      ctx.shadowColor = isHover ? 'rgba(37,99,235,0.34)' : 'rgba(15,23,42,0.52)';
      ctx.fill();
      ctx.shadowBlur = 0;

      ctx.lineWidth = isHover ? 3.2 : 2.2;
      ctx.strokeStyle = isHover ? badgeColor : 'rgba(148,163,184,0.56)';
      ctx.stroke();

      // Clip to box
      drawRoundedRect(ctx, rect.x, rect.y, rect.w, rect.h, 16);
      ctx.clip();

      // A/B/C/D badge
      const bSize = Math.max(24, Math.min(rect.h * 0.48, 34));
      const bX = rect.x + 8;
      const bY = rect.y + (rect.h - bSize) / 2;
      drawRoundedRect(ctx, bX, bY, bSize, bSize, 6);
      ctx.fillStyle = badgeColor;
      ctx.fill();
      ctx.fillStyle = '#ffffff';
      ctx.font = `800 ${Math.round(bSize * 0.56)}px system-ui, -apple-system`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(CHOICE_BADGE_LABELS[ci] ?? '', bX + bSize / 2, bY + bSize / 2);

      // Choice text (shifted right to not overlap badge)
      const textRect = { x: rect.x + bSize + 14, y: rect.y, w: rect.w - bSize - 22, h: rect.h };
      ctx.fillStyle = 'rgba(255,255,255,0.88)';
      drawAutoFitTextInRect(ctx, c.text, textRect, {
        minFontPx: 13,
        maxFontPx: 21,
        maxLines: 3,
        paddingX: 6,
        paddingY: 10,
        fontWeight: 500,
      });
      ctx.restore();
    }

    // Finger cursor + hover progress arc
    if (frame.hasHand && frame.indexTip) {
      const p = frame.indexTip;
      ctx.save();
      ctx.beginPath();
      ctx.arc(p.x, p.y, 8, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(255,255,255,0.85)';
      ctx.fill();

      if (this.hoveringChoiceId && !this.selectedChoiceId) {
        const elapsed = frame.nowMs - this.hoverStartMs;
        const t = clamp01(elapsed / this.settings.hoverHoldMs);

        ctx.beginPath();
        ctx.arc(p.x, p.y, 18, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * t);
        ctx.strokeStyle = 'rgba(255,255,255,0.85)';
        ctx.lineWidth = 4;
        ctx.stroke();
      }

      ctx.restore();
    }

    // Result
    if (this.selectedChoiceId) {
      ctx.save();
      ctx.fillStyle = 'rgba(0,0,0,0.55)';
      ctx.fillRect(0, height - 56, width, 56);
      ctx.fillStyle = '#ffffff';
      ctx.font = '600 18px system-ui, -apple-system, Segoe UI, Roboto, Arial';
      ctx.textAlign = 'center';
      const msg = this.isCorrect
        ? 'Đúng rồi!'
        : this.wrongAttempts >= 2
        ? 'Hết lượt! Chuyển câu tiếp...'
        : 'Chưa đúng! Còn 1 lần thử.';
      ctx.fillText(msg, width / 2, height - 22);
      ctx.restore();
    }
  }
}

class DragDropGame {
  /**
   * Matching-pairs game: user pinches a left-column item and draws a bezier
   * line to the matching right-column zone. Replaces the old drag-to-box mechanic.
   *
   * @param {{ playable: any; settings: any; canvas: HTMLCanvasElement }} params
   */
  constructor({ playable, settings, canvas }) {
    this.playable = {
      ...playable,
      items:     (playable.items     ?? []).map((it) => ({ ...it })),
      dropZones: (playable.dropZones ?? []).map((z)  => ({ ...z  })),
    };
    this.settings = settings;
    this.canvas   = canvas;

    // Limit to 4 pairs per round for legibility
    const MAX_PAIRS = 4;
    const allItems = this.playable.items.slice(0, MAX_PAIRS);
    const validZoneIds = new Set(allItems.map((it) => it.id));
    const allZones = this.playable.dropZones.filter((z) => validZoneIds.has(z.acceptsItemId)).slice(0, MAX_PAIRS);
    this.playable.items = allItems;
    this.playable.dropZones = allZones;

    // Shuffle zones visually so position alone can't solve the puzzle (Fisher-Yates)
    const _sz = [...this.playable.dropZones];
    for (let _i = _sz.length - 1; _i > 0; _i--) {
      const _j = Math.floor(Math.random() * (_i + 1));
      [_sz[_i], _sz[_j]] = [_sz[_j], _sz[_i]];
    }
    this._shuffledZones = _sz;

    // Per-pair accent colors (cycle if more pairs than colors)
    this._pairColors = [
      { line: '#60a5fa', glow: 'rgba(96,165,250,0.55)', card: 'rgba(59,130,246,0.22)', border: 'rgba(96,165,250,0.75)' },
      { line: '#a78bfa', glow: 'rgba(167,139,250,0.55)', card: 'rgba(139,92,246,0.22)', border: 'rgba(167,139,250,0.75)' },
      { line: '#34d399', glow: 'rgba(52,211,153,0.55)', card: 'rgba(16,185,129,0.22)', border: 'rgba(52,211,153,0.75)' },
      { line: '#fb923c', glow: 'rgba(251,146,60,0.55)', card: 'rgba(234,88,12,0.22)', border: 'rgba(251,146,60,0.75)' },
    ];

    // connections[itemId] = zoneId  (finalized pairings)
    this.connections = {};

    // item currently being connected (rubber-band line follows cursor)
    this.activeItemId   = null;
    this.wasPinching    = false;
    this._noHandFrames  = 0;

    // Flash-red feedback: { itemId, expiresMs }
    this._wrongFlash = null;

    this.completedAtMs = null;
    this.promptFontPx  = 20;

    // Animated dot pulse phase (seconds)
    this._pulsePhase = 0;
    this._lastPulseMs = 0;
  }

  // ── Layout helpers ──────────────────────────────────────────────────────────

  /**
   * Returns canvas-pixel rect for a cell in one of the two columns.
   * colIdx 0 = left (items), 1 = right (zones).
   */
  _columnRect(colIdx, rowIdx, n) {
    const c = this.canvas;
    // Keep in sync with the panel bounds computed in render()
    const PANEL_TOP  = 0.14;   // fraction of canvas height
    const HINT_BAR_H = 38;     // px — must match hint bar in render()
    const panelY  = PANEL_TOP * c.height;
    const panelH  = c.height - HINT_BAR_H - 10 - panelY;  // 10px gap above hint bar
    const topY    = panelY + 34;   // space for column header text
    const bottomY = panelY + panelH - 14;  // generous bottom padding
    const availH  = bottomY - topY;
    const gap     = Math.max(8, Math.min(14, availH * 0.02));
    // No hard minimum — let height shrink so cards never overflow panel
    const rowH    = Math.max(32, (availH - gap * (n - 1)) / n);
    const y       = topY + rowIdx * (rowH + gap);
    // Column left edges chosen so right edges align with panel right border
    const colW    = 0.41 * c.width;
    const colX    = colIdx === 0 ? 0.02 * c.width : 0.56 * c.width;
    return { x: colX, y, w: colW, h: rowH };
  }

  _itemConnectionPoint(idx, n) {
    const r = this._columnRect(0, idx, n);
    return { x: r.x + r.w, y: r.y + r.h / 2 };
  }

  _zoneConnectionPoint(idx, n) {
    const r = this._columnRect(1, idx, n);
    return { x: r.x, y: r.y + r.h / 2 };
  }

  // ── Update ──────────────────────────────────────────────────────────────────

  /** @param {InputFrame} frame */
  update(frame) {
    const items = this.playable.items;
    const zones = this._shuffledZones;
    const n     = items.length;
    const zn    = zones.length;

    if (!frame.hasHand) {
      this._noHandFrames += 1;
      // Tolerate up to 6 missed frames (~100 ms at 60fps) before releasing grab
      if (this._noHandFrames > 6) {
        this.activeItemId  = null;
        this.wasPinching   = false;
        this._lastPointPos = null;
      }
      return;
    }
    this._noHandFrames = 0;

    // Cursor always tracks palm center whenever hand is visible
    if (!frame.palmCenter) return;
    const px = frame.palmCenter.x;
    const py = frame.palmCenter.y;

    // ── While pointing (1 finger): freeze position for release snap ──────────
    if (frame.isPointing) {
      this._lastPointPos = { x: px, y: py };
    }

    // Tight grab padding — avoids accidentally hitting adjacent items.
    // Generous release padding — easier to snap to a zone.
    const grabPad = 4;
    const snapPad = Math.max(10, this.canvas.width * 0.025);

    // ── Pointing START: grab left-column item ────────────────────────────────
    if (frame.isPointing && !this.wasPinching) {
      this.activeItemId = null;
      for (let i = 0; i < n; i++) {
        const r = this._columnRect(0, i, n);
        if (
          px >= r.x - grabPad && px <= r.x + r.w + grabPad &&
          py >= r.y - grabPad && py <= r.y + r.h + grabPad
        ) {
          delete this.connections[items[i].id]; // allow re-draw
          this.activeItemId = items[i].id;
          break;
        }
      }
    }

    // ── Hand open RELEASE: snap using the FROZEN pointing position ────────────
    // Use the last known pointing position so the snap point doesn't drift
    // as fingers spread open during the gesture transition.
    if (!frame.isPointing && this.wasPinching && this.activeItemId) {
      const snapPos = this._lastPointPos ?? { x: px, y: py };
      const sx = snapPos.x;
      const sy = snapPos.y;
      let matched = false;
      for (let i = 0; i < zn; i++) {
        const r = this._columnRect(1, i, zn);
        if (
          sx >= r.x - snapPad && sx <= r.x + r.w + snapPad &&
          sy >= r.y - snapPad && sy <= r.y + r.h + snapPad
        ) {
          this.connections[this.activeItemId] = zones[i].id;
          // Flash red if wrong pair
          const zone = this.playable.dropZones.find((z) => z.id === zones[i].id);
          if (zone && zone.acceptsItemId !== this.activeItemId) {
            this._wrongFlash = { itemId: this.activeItemId, expiresMs: frame.nowMs + 500 };
            // Remove the wrong connection after the flash
            const wrongItemId = this.activeItemId;
            setTimeout(() => { delete this.connections[wrongItemId]; }, 500);
          }
          matched = true;
          break;
        }
      }
      this.activeItemId  = null;
      this._lastPointPos = null;
    }

    this.wasPinching = frame.isPointing;

    // All items connected → game complete
    if (this.completedAtMs == null) {
      const allConnected = n > 0 && items.every((it) => Boolean(this.connections[it.id]));
      if (allConnected) this.completedAtMs = frame.nowMs;
    }
  }

  isComplete()       { return this.completedAtMs != null; }
  getCompletedAtMs() { return this.completedAtMs; }

  getResult() {
    let correct = 0;
    for (const it of this.playable.items) {
      const connectedZoneId = this.connections[it.id];
      if (!connectedZoneId) continue;
      const zone = this.playable.dropZones.find((z) => z.id === connectedZoneId);
      if (zone && zone.acceptsItemId === it.id) correct += 1;
    }
    return { correct, total: this.playable.items.length };
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  /** @param {{ctx: CanvasRenderingContext2D; frame: InputFrame}} params */
  render({ ctx, frame }) {
    const { width, height } = this.canvas;
    const items = this.playable.items;
    const zones = this._shuffledZones;
    const n     = items.length;
    const zn    = zones.length;
    const nowMs = frame.nowMs;

    // Advance dot pulse animation
    const dtMs = this._lastPulseMs ? Math.min(nowMs - this._lastPulseMs, 50) : 0;
    this._pulsePhase = (this._pulsePhase + dtMs / 1200) % 1;
    this._lastPulseMs = nowMs;
    const pulseSin = Math.sin(this._pulsePhase * Math.PI * 2); // -1 to 1

    // Expire wrong flash
    if (this._wrongFlash && nowMs > this._wrongFlash.expiresMs) this._wrongFlash = null;

    // Clear
    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, width, height);
    ctx.fillStyle = 'rgba(0,0,0,0.35)';
    ctx.fillRect(0, 0, width, height);
    ctx.restore();

    // Content panel — keep in sync with _columnRect constants
    const PANEL_TOP  = 0.14;
    const HINT_BAR_H = 38;
    const panelY = height * PANEL_TOP;
    const panelH = height - HINT_BAR_H - 10 - panelY;
    // Panel is wide enough to fully contain both columns (left col x=2%, right col right edge=97%)
    drawGameContentPanel(ctx, this.canvas, { x: width * 0.01, y: panelY, w: width * 0.98, h: panelH });

    // ── Prompt (centered, above panel) ───────────────────────────────────────
    ctx.fillStyle = '#ffffff';
    ctx.font = `600 ${this.promptFontPx}px system-ui, -apple-system, Segoe UI, Roboto, Arial`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    // Reserve right side for timer — constrain text to left 80% of width
    drawCenteredMultilineText(ctx, this.playable.prompt, width * 0.43, panelY / 2, width * 0.72, 24, 2);

    // ── Column headers ────────────────────────────────────────────────────────
    const col1CenterX = width * 0.02 + width * 0.41 / 2;
    const col2CenterX = width * 0.56 + width * 0.41 / 2;
    const headerY = panelY + 14;
    ctx.font = '700 11px system-ui, -apple-system, Segoe UI, Roboto, Arial';
    ctx.fillStyle = 'rgba(255,255,255,0.35)';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('KHÁI NIỆM', col1CenterX, headerY);
    ctx.fillText('NỐI VỚI', col2CenterX, headerY);

    // Compute layout bounds used by both columns
    const COL_TOP_Y  = panelY + 28;
    const COL_BOT_Y  = panelY + panelH - 8;

    // ── Finalized connection lines (draw BEHIND cards) ────────────────────────
    for (let ii = 0; ii < n; ii++) {
      const it           = items[ii];
      const connectedZId = this.connections[it.id];
      if (!connectedZId) continue;
      const zi = zones.findIndex((z) => z.id === connectedZId);
      if (zi < 0) continue;

      const from = this._itemConnectionPoint(ii, n);
      const to   = this._zoneConnectionPoint(zi, zn);
      const zone = this.playable.dropZones.find((z) => z.id === connectedZId);
      const ok   = zone?.acceptsItemId === it.id;
      const color = this._pairColors[ii % this._pairColors.length];
      const isFlashing = this._wrongFlash && this._wrongFlash.itemId === it.id;

      ctx.save();
      ctx.beginPath();
      ctx.moveTo(from.x, from.y);
      const cx = (from.x + to.x) / 2;
      ctx.bezierCurveTo(cx, from.y, cx, to.y, to.x, to.y);
      ctx.strokeStyle  = isFlashing ? '#f87171' : ok ? color.line : '#f87171';
      ctx.lineWidth    = 4;
      ctx.shadowBlur   = 8;
      ctx.shadowColor  = isFlashing ? 'rgba(248,113,113,0.6)' : ok ? color.glow : 'rgba(248,113,113,0.6)';
      ctx.stroke();
      ctx.restore();

      // Checkmark or X near midpoint of line
      if (ok) {
        const mx = (from.x + to.x) / 2;
        const my = (from.y + to.y) / 2;
        ctx.save();
        ctx.font = 'bold 13px system-ui';
        ctx.fillStyle = color.line;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.shadowBlur = 6;
        ctx.shadowColor = color.glow;
        ctx.fillText('✓', mx, my - 10);
        ctx.restore();
      }
    }

    // ── Rubber-band line while dragging ──────────────────────────────────────
    if (this.activeItemId) {
      const ii = items.findIndex((i) => i.id === this.activeItemId);
      if (ii >= 0) {
        const from = this._itemConnectionPoint(ii, n);
        const endPos = this._lastPointPos ?? frame.palmCenter;
        if (endPos) {
          const tx = endPos.x;
          const ty = endPos.y;
          const color = this._pairColors[ii % this._pairColors.length];
          ctx.save();
          ctx.beginPath();
          ctx.moveTo(from.x, from.y);
          const cx = (from.x + tx) / 2;
          ctx.bezierCurveTo(cx, from.y, cx, ty, tx, ty);
          ctx.strokeStyle = color.line;
          ctx.lineWidth   = 3;
          ctx.globalAlpha = 0.80;
          ctx.setLineDash([10, 6]);
          ctx.shadowBlur  = 6;
          ctx.shadowColor = color.glow;
          ctx.stroke();
          ctx.setLineDash([]);
          ctx.restore();
        }
      }
    }

    // ── Left column: items ────────────────────────────────────────────────────
    for (let i = 0; i < n; i++) {
      const it           = items[i];
      const rect         = this._columnRect(0, i, n);
      const isActive     = this.activeItemId === it.id;
      const connectedZId = this.connections[it.id];
      const isFlashing   = this._wrongFlash && this._wrongFlash.itemId === it.id;
      let placedCorrect  = null;
      if (connectedZId) {
        const zone    = this.playable.dropZones.find((z) => z.id === connectedZId);
        placedCorrect = zone?.acceptsItemId === it.id;
      }
      const color = this._pairColors[i % this._pairColors.length];

      ctx.save();
      drawRoundedRect(ctx, rect.x, rect.y, rect.w, rect.h, 10);

      // Fill
      if (isFlashing)             ctx.fillStyle = 'rgba(239,68,68,0.35)';
      else if (placedCorrect === true)  ctx.fillStyle = color.card;
      else if (isActive)          ctx.fillStyle = 'rgba(255,255,255,0.20)';
      else                        ctx.fillStyle = 'rgba(255,255,255,0.09)';
      ctx.fill();

      // Border
      if (isFlashing)             ctx.strokeStyle = '#f87171';
      else if (placedCorrect === true)  ctx.strokeStyle = color.border;
      else if (isActive)          ctx.strokeStyle = 'rgba(255,255,255,0.90)';
      else                        ctx.strokeStyle = 'rgba(255,255,255,0.30)';
      ctx.lineWidth = (isActive || placedCorrect === true || isFlashing) ? 2.5 : 1.5;
      if (isActive) {
        ctx.shadowBlur  = 10;
        ctx.shadowColor = 'rgba(255,255,255,0.40)';
      }
      ctx.stroke();
      ctx.shadowBlur = 0;

      // "Drag handle" chevron on left edge when not yet connected
      if (!connectedZId && !isActive) {
        ctx.font = '10px system-ui';
        ctx.fillStyle = 'rgba(255,255,255,0.28)';
        ctx.textAlign = 'left';
        ctx.textBaseline = 'middle';
        ctx.fillText('〉', rect.x + rect.w - 16, rect.y + rect.h / 2);
      }

      drawRoundedRect(ctx, rect.x, rect.y, rect.w, rect.h, 10);
      ctx.clip();
      ctx.fillStyle = '#ffffff';
      drawAutoFitTextInRect(ctx, it.label, rect, {
        minFontPx: 11, maxFontPx: 17, maxLines: 2,
        paddingX: 12, paddingY: 6, fontWeight: 700, ellipsis: true,
      });
      ctx.restore();

      // ── Port dot — right edge (larger, colored, pulsing when unconnected) ──
      const dotX  = rect.x + rect.w;
      const dotY  = rect.y + rect.h / 2;
      let dotR, dotColor;
      if (isActive) {
        dotR = 9; dotColor = '#ffffff';
      } else if (placedCorrect === true) {
        dotR = 8; dotColor = color.line;
      } else if (isFlashing) {
        dotR = 8; dotColor = '#f87171';
      } else {
        // Pulse: animate between 7 and 9
        dotR = 7 + pulseSin * 2; dotColor = color.line;
      }
      ctx.save();
      // Outer ring for unconnected dots (no shadow — keeps render fast)
      if (!connectedZId) {
        ctx.beginPath();
        ctx.arc(dotX, dotY, dotR + 3, 0, Math.PI * 2);
        ctx.strokeStyle = dotColor;
        ctx.lineWidth = 1;
        ctx.globalAlpha = 0.30 + pulseSin * 0.15;
        ctx.stroke();
        ctx.globalAlpha = 1;
      }
      ctx.beginPath();
      ctx.arc(dotX, dotY, dotR, 0, Math.PI * 2);
      ctx.fillStyle = dotColor;
      ctx.fill();
      ctx.restore();
    }

    // ── Right column: zones ───────────────────────────────────────────────────
    for (let i = 0; i < zn; i++) {
      const zone           = zones[i];
      const rect           = this._columnRect(1, i, zn);
      const incomingItemId = Object.keys(this.connections).find((id) => this.connections[id] === zone.id) ?? null;
      let placedCorrect    = null;
      let pairIdx          = -1;
      if (incomingItemId) {
        placedCorrect = zone.acceptsItemId === incomingItemId;
        pairIdx       = items.findIndex((it) => it.id === incomingItemId);
      }
      const isFlashing = this._wrongFlash && this._wrongFlash.itemId === incomingItemId;
      const color = pairIdx >= 0 ? this._pairColors[pairIdx % this._pairColors.length] : null;

      ctx.save();
      drawRoundedRect(ctx, rect.x, rect.y, rect.w, rect.h, 10);
      if (isFlashing)                  ctx.fillStyle = 'rgba(239,68,68,0.30)';
      else if (placedCorrect === true)  ctx.fillStyle = color.card;
      else                             ctx.fillStyle = 'rgba(255,255,255,0.06)';
      ctx.fill();

      ctx.strokeStyle =
        isFlashing          ? '#f87171' :
        placedCorrect === true ? color.border :
        'rgba(255,255,255,0.25)';
      ctx.lineWidth = (placedCorrect === true || isFlashing) ? 2.5 : 1.5;
      ctx.stroke();

      drawRoundedRect(ctx, rect.x, rect.y, rect.w, rect.h, 10);
      ctx.clip();
      ctx.fillStyle = placedCorrect === true ? '#ffffff' : 'rgba(255,255,255,0.80)';
      drawAutoFitTextInRect(ctx, zone.label, rect, {
        minFontPx: 11, maxFontPx: 17, maxLines: 2,
        paddingX: 12, paddingY: 6, fontWeight: 600, ellipsis: true,
      });
      ctx.restore();

      // ── Port dot — left edge ──────────────────────────────────────────────
      const dotX = rect.x;
      const dotY = rect.y + rect.h / 2;
      let dotR, dotColor;
      if (isFlashing) {
        dotR = 8; dotColor = '#f87171';
      } else if (placedCorrect === true) {
        dotR = 8; dotColor = color.line;
      } else {
        dotR = 7 + pulseSin * 1.5; dotColor = 'rgba(255,255,255,0.60)';
      }
      ctx.save();
      if (!incomingItemId) {
        ctx.beginPath();
        ctx.arc(dotX, dotY, dotR + 3, 0, Math.PI * 2);
        ctx.strokeStyle = dotColor;
        ctx.lineWidth = 1;
        ctx.globalAlpha = 0.25 + pulseSin * 0.1;
        ctx.stroke();
        ctx.globalAlpha = 1;
      }
      ctx.beginPath();
      ctx.arc(dotX, dotY, dotR, 0, Math.PI * 2);
      ctx.fillStyle = dotColor;
      ctx.fill();
      ctx.restore();
    }

    // ── Cursor ────────────────────────────────────────────────────────────────
    if (frame.hasHand && frame.palmCenter) {
      const p = frame.palmCenter;
      ctx.save();
      if (frame.isPointing) {
        // 1-finger pointing = grab mode — blue filled circle with glow ring
        ctx.beginPath();
        ctx.arc(p.x, p.y, 20, 0, Math.PI * 2);
        ctx.strokeStyle = 'rgba(96,165,250,0.30)';
        ctx.lineWidth = 4;
        ctx.stroke();
        ctx.beginPath();
        ctx.arc(p.x, p.y, 12, 0, Math.PI * 2);
        ctx.fillStyle = 'rgba(96,165,250,0.95)';
        ctx.fill();
      } else {
        // Hand visible, no grab gesture = move mode — white dot with ring
        ctx.beginPath();
        ctx.arc(p.x, p.y, 10, 0, Math.PI * 2);
        ctx.fillStyle = 'rgba(255,255,255,0.85)';
        ctx.fill();
        ctx.beginPath();
        ctx.arc(p.x, p.y, 18, 0, Math.PI * 2);
        ctx.strokeStyle = 'rgba(255,255,255,0.30)';
        ctx.lineWidth = 2;
        ctx.stroke();
      }
      ctx.restore();
    }

    // ── Hint bar ──────────────────────────────────────────────────────────────
    ctx.save();
    ctx.fillStyle = 'rgba(0,0,0,0.55)';
    ctx.fillRect(0, height - 38, width, 38);
    ctx.fillStyle = 'rgba(255,255,255,0.65)';
    ctx.font = '500 12px system-ui, -apple-system, Segoe UI, Roboto, Arial';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('☝️ Giơ 1 ngón trỏ vào ô trái để chọn  •  Kéo sang ô phải  •  Xòe tay để nối', width / 2, height - 19);
    ctx.restore();
  }
}

export class GameEngine {
  /**
   * @param {{
   *  canvasEl: HTMLCanvasElement;
   *  videoEl: HTMLVideoElement;
   *  playable: any;
   *  tracker: MediaPipeTracker;
   *  onStatus?: (msg: string) => void;
   *  onFinish?: (result: { correct: number; total: number }) => void;
   *  onRoundChange?: (roundIndex: number, totalRounds: number, lastResult: { correct: number; total: number } | null) => void;
   *  onAttemptWarning?: (msg: string) => void;
   *  onHoverChange?: (choiceId: string | null) => void;
   *  onChoiceSelected?: (choiceId: string, isCorrect: boolean) => void;
   *  htmlMode?: boolean;
   * }} params
   */
  constructor({ canvasEl, videoEl, playable, tracker, onStatus, onFinish, onRoundChange, onAttemptWarning, onHoverChange, onChoiceSelected, htmlMode = false }) {
    this.canvasEl = canvasEl;
    this.videoEl = videoEl;
    this.playable = playable;
    this.tracker = tracker;
    this.onStatus = onStatus ?? (() => {});
    this.onFinish = onFinish ?? (() => {});
    this.onRoundChange = onRoundChange ?? (() => {});
    this.onAttemptWarning = onAttemptWarning ?? (() => {});
    this.onHoverChange = onHoverChange ?? null;
    this.onChoiceSelected = onChoiceSelected ?? null;
    this.htmlMode = htmlMode;

    this.ctx = canvasEl.getContext('2d');
    this.rafId = null;
    this.lastResults = null;
    this.blueprint = null;
    this.lastRenderAtMs = 0;
    this.lastIndexTip = null;
    this.lastPinchMid = null;

    // Keyboard input for non-camera blueprints
    this._keyboard     = new KeyboardInput();
    this._dualKeyboard = new DualKeyboardInput();

    this.rounds = null;
    this.roundIndex = 0;
    this.isFinished = false;
    this._roundResults = [];
    this.totalRounds = 0;
    this._lastHoverChoiceId = undefined;
    this._lastSelectedChoiceId = undefined;

    this._handleResize = this._handleResize.bind(this);
  }

  async init() {
    if (!this.ctx) throw new Error('Canvas 2D context not available');

    this._handleResize();
    window.addEventListener('resize', this._handleResize);

    const isKeyboardGame = KEYBOARD_BLUEPRINTS.has(this.playable.templateId);

    if (!isKeyboardGame) {
      // Bind tracker callback to store results
      this.tracker.onFrame = (results) => {
        this.lastResults = results;
      };
    }

    if (isKeyboardGame) {
      // No camera needed — just attach keyboard and start
      const win = this.canvasEl.ownerDocument.defaultView ?? window;
      this._keyboard.attach(win);
      if (DUAL_KEYBOARD_BLUEPRINTS.has(this.playable.templateId)) {
        this._dualKeyboard.attach(win);
      }
      this.onStatus('Đang chạy game...');
    } else {
      this.onStatus('Đang khởi tạo camera...');
      await this.tracker.init();
      this.tracker.start();
      this.onStatus('Đang chạy game...');
    }

    const payload = this.playable.payload;

    // RUNNER_QUIZ / SNAKE_QUIZ / RUNNER_RACE / SNAKE_DUEL expect playable.questions.
    // BE may return payload as a flat array of question objects — wrap into one round.
    const QUESTIONS_BASED_BLUEPRINTS = new Set([
      GAME_BLUEPRINTS.RUNNER_QUIZ,
      GAME_BLUEPRINTS.SNAKE_QUIZ,
      GAME_BLUEPRINTS.RUNNER_RACE,
      GAME_BLUEPRINTS.SNAKE_DUEL,
    ]);
    let normalizedPayload = payload;
    if (QUESTIONS_BASED_BLUEPRINTS.has(this.playable.templateId)) {
      normalizedPayload = normalizeQuestionBasedPayload(payload);
    }

    this.rounds = Array.isArray(normalizedPayload) ? normalizedPayload : [normalizedPayload];
    this.roundIndex = 0;
    this.isFinished = false;
    this._roundResults = [];
    this.totalRounds = this.rounds.length;
    this._createBlueprintForRound();

    this._tick();
  }

  _createBlueprintForRound() {
    const templateId = this.playable.templateId;
    const roundPayload = this.rounds?.[this.roundIndex];

    if (!roundPayload) {
      this.blueprint = null;
      this.isFinished = true;
      return;
    }

    if (templateId === GAME_BLUEPRINTS.HOVER_SELECT) {
      this.blueprint = new HoverSelectGame({
        playable: roundPayload,
        settings: this.playable.settings,
        canvas: this.canvasEl,
        htmlMode: this.htmlMode,
      });
    } else if (templateId === GAME_BLUEPRINTS.DRAG_DROP) {
      this.blueprint = new DragDropGame({
        playable: roundPayload,
        settings: this.playable.settings,
        canvas: this.canvasEl,
      });
    } else if (templateId === GAME_BLUEPRINTS.RUNNER_QUIZ) {
      this.blueprint = new RunnerQuizGame({
        playable: roundPayload,
        settings: this.playable.settings,
        canvas: this.canvasEl,
        keyboard: this._keyboard,
      });
    } else if (templateId === GAME_BLUEPRINTS.SNAKE_QUIZ) {
      this.blueprint = new SnakeQuizGame({
        playable: roundPayload,
        settings: this.playable.settings,
        canvas: this.canvasEl,
        keyboard: this._keyboard,
      });
    } else if (templateId === GAME_BLUEPRINTS.RUNNER_RACE) {
      this.blueprint = new RunnerRaceGame({
        playable: roundPayload,
        settings: this.playable.settings,
        canvas: this.canvasEl,
        keyboard: this._dualKeyboard,
      });
    } else if (templateId === GAME_BLUEPRINTS.SNAKE_DUEL) {
      this.blueprint = new SnakeDuelGame({
        playable: roundPayload,
        settings: this.playable.settings,
        canvas: this.canvasEl,
        keyboard: this._dualKeyboard,
      });
    } else {
      throw new Error(`Unsupported templateId: ${templateId}`);
    }

    const lastResult = this._roundResults.length > 0
      ? this._roundResults[this._roundResults.length - 1]
      : null;
    this._lastHoverChoiceId = undefined;
    this._lastSelectedChoiceId = undefined;
    this.onRoundChange(this.roundIndex, this.totalRounds, lastResult);
  }

  dispose() {
    if (this.rafId) cancelAnimationFrame(this.rafId);
    this.rafId = null;

    window.removeEventListener('resize', this._handleResize);
    this._keyboard.detach();
    this._dualKeyboard.detach();
    if (this.tracker) this.tracker.stop();

    this.lastResults = null;
    this.blueprint = null;

    this.rounds = null;
    this.roundIndex = 0;
    this.isFinished = false;

    if (this.onHoverChange) this.onHoverChange(null);

    if (this.ctx) this.ctx.clearRect(0, 0, this.canvasEl.width, this.canvasEl.height);
  }

  skipCurrentRound() {
    if (this.isFinished || !this.blueprint) return;

    const result = typeof this.blueprint.getResult === 'function'
      ? this.blueprint.getResult()
      : { correct: 0, total: 1 };
    this._roundResults.push(result);

    this.roundIndex += 1;
    if (this.rounds && this.roundIndex < this.rounds.length) {
      this._createBlueprintForRound();
    } else {
      this.blueprint = null;
      this.isFinished = true;
      const totalCorrect = this._roundResults.reduce((s, r) => s + r.correct, 0);
      const totalItems = this._roundResults.reduce((s, r) => s + r.total, 0);
      this.onFinish({ correct: totalCorrect, total: totalItems, rounds: [...this._roundResults] });
    }
  }

  _handleResize() {
    // Match canvas size to rendered size to keep hit-testing consistent.
    const rect = this.canvasEl.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    this.canvasEl.width = Math.max(2, Math.floor(rect.width * dpr * CANVAS_RENDER_SCALE));
    this.canvasEl.height = Math.max(2, Math.floor(rect.height * dpr * CANVAS_RENDER_SCALE));
  }

  _buildInputFrame(nowMs) {
    const landmarks = this.lastResults?.landmarks?.[0] ?? null;
    const hasHand = Boolean(landmarks && landmarks.length);

    /** @type {InputFrame} */
    const frame = {
      landmarks,
      hasHand,
      isPinching:  false,
      isPointing:  false,
      palmCenter:  null,
      nowMs,
    };

    if (!hasHand) {
      this._pinchHysteresisActive    = false;
      this._pointingHysteresisActive = false;
      return frame;
    }

    // index tip (8)
    const indexLm = landmarks[8];
    const rawIndexTip = mapLandmarkToCanvas(indexLm, this.canvasEl);
    const smoothedIndexTip = smoothPoint(this.lastIndexTip, rawIndexTip, HAND_SMOOTHING_ALPHA);
    this.lastIndexTip = smoothedIndexTip;
    frame.indexTip = smoothedIndexTip;

    // pinch (4, 8)
    const thumbLm = landmarks[4];
    const indexNorm = { x: indexLm.x, y: indexLm.y };
    const thumbNorm = { x: thumbLm.x, y: thumbLm.y };

    const pinchDistance = dist2(indexNorm, thumbNorm);
    // Hysteresis: larger threshold to release than to start, prevents flickering
    const pinchThreshold = this.playable.settings?.pinchThreshold ?? 0.065;
    const releaseThreshold = pinchThreshold * 1.4;
    const wasPinching = this._pinchHysteresisActive ?? false;
    frame.isPinching = wasPinching ? pinchDistance < releaseThreshold : pinchDistance < pinchThreshold;
    this._pinchHysteresisActive = frame.isPinching;

    const midNorm = {
      x: (indexNorm.x + thumbNorm.x) / 2,
      y: (indexNorm.y + thumbNorm.y) / 2,
    };

    const rawPinchMid = {
      x: clamp01(1 - midNorm.x), // flip for mirrored canvas
      y: clamp01(midNorm.y),
    };
    const smoothedPinchMid = smoothPoint(this.lastPinchMid, rawPinchMid, HAND_SMOOTHING_ALPHA);
    this.lastPinchMid = smoothedPinchMid;
    frame.pinchMid = smoothedPinchMid;

    // ── Palm center cursor (always computed when hand is present) ─────────────
    // Centroid of wrist + 4 MCPs gives a stable position that doesn't jump
    // when individual fingers move. Used as the cursor for DragDropGame.
    const palmNorm = {
      x: (landmarks[0].x + landmarks[5].x + landmarks[9].x + landmarks[13].x + landmarks[17].x) / 5,
      y: (landmarks[0].y + landmarks[5].y + landmarks[9].y + landmarks[13].y + landmarks[17].y) / 5,
    };
    frame.palmCenter = {
      x: (1 - palmNorm.x) * this.canvasEl.width,
      y: palmNorm.y * this.canvasEl.height,
    };

    // ── Index-pointing gesture (1 finger = grab) ─────────────────────────────
    const rawIsPointing = detectIndexPointing(landmarks);
    const wasPointing   = this._pointingHysteresisActive ?? false;
    // 2-frame persistence to smooth out momentary detection drops
    this._pointingMissedFrames = rawIsPointing ? 0 : (this._pointingMissedFrames ?? 0) + 1;
    frame.isPointing = rawIsPointing || (wasPointing && this._pointingMissedFrames <= 2);
    this._pointingHysteresisActive = frame.isPointing;

    return frame;
  }

  _tick() {
    const nowMs = performance.now();
    const minRenderInterval = 1000 / TARGET_RENDER_FPS;
    if (nowMs - this.lastRenderAtMs < minRenderInterval) {
      this.rafId = requestAnimationFrame(() => this._tick());
      return;
    }
    this.lastRenderAtMs = nowMs;

    const isKeyboardGame = KEYBOARD_BLUEPRINTS.has(this.playable.templateId);
    const frame = isKeyboardGame
      ? { nowMs, hasHand: false, isPinching: false, landmarks: null }
      : this._buildInputFrame(nowMs);

    if (!isKeyboardGame) {
      // Canvas element is mirrored via CSS. Mirror the drawing context too to avoid
      // mirrored (reversed) text, while still drawing with flipped X coordinates.
      // Net effect: UI looks normal, but interaction aligns with mirrored video.
      this.ctx.setTransform(-1, 0, 0, 1, this.canvasEl.width, 0);
    } else {
      this.ctx.setTransform(1, 0, 0, 1, 0, 0);
    }

    if (this.blueprint) {
      this.blueprint.update(frame);

      const _warning = typeof this.blueprint.getPendingWarning === 'function'
        ? this.blueprint.getPendingWarning()
        : null;
      if (_warning) this.onAttemptWarning(_warning);

      // Fire hover/selection callbacks (used by HoverSelectGamePlayer in htmlMode)
      if (this.htmlMode) {
        const hId = this.blueprint.hoveringChoiceId ?? null;
        if (hId !== this._lastHoverChoiceId) {
          this._lastHoverChoiceId = hId;
          if (this.onHoverChange) this.onHoverChange(hId);
        }
        const sId = this.blueprint.selectedChoiceId ?? null;
        if (sId && sId !== this._lastSelectedChoiceId) {
          this._lastSelectedChoiceId = sId;
          if (this.onChoiceSelected) this.onChoiceSelected(sId, this.blueprint.isCorrect === true);
        }
      }

      this.blueprint.render({ ctx: this.ctx, frame, nowMs });

      const isComplete = typeof this.blueprint.isComplete === 'function' ? this.blueprint.isComplete() : false;
      const completedAtMs =
        typeof this.blueprint.getCompletedAtMs === 'function' ? this.blueprint.getCompletedAtMs() : null;

      if (isComplete && completedAtMs != null && nowMs - completedAtMs >= 700) {
        const roundResult = typeof this.blueprint.getResult === 'function'
          ? this.blueprint.getResult()
          : { correct: 0, total: 0 };
        this._roundResults.push(roundResult);

        this.roundIndex += 1;
        if (this.rounds && this.roundIndex < this.rounds.length) {
          this._createBlueprintForRound();
        } else {
          this.blueprint = null;
          this.isFinished = true;
          const totalCorrect = this._roundResults.reduce((s, r) => s + r.correct, 0);
          const totalItems = this._roundResults.reduce((s, r) => s + r.total, 0);
          this.onFinish({ correct: totalCorrect, total: totalItems, rounds: [...this._roundResults] });
          return; // Stop the render loop — React will show the result overlay
        }
      }
    }

    this.rafId = requestAnimationFrame(() => this._tick());
  }
}
