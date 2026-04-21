/**
 * Teacher Game Config UI
 * ======================
 *
 * This module is intentionally DOM-driven (vanilla JS) to match the spec.
 * It expects a root element with child nodes marked by data-role attributes.
 */

import { GAME_BLUEPRINTS } from './api-contracts.js';
import { MediaPipeTracker, GameEngine } from './mediapipe-engine.js';

const GAME_STATUS_POLLING_MS = 3000;

function normalizePlayableResult(result) {
  if (!result || typeof result !== 'object') return null;
  if ('templateId' in result && 'payload' in result) return result;

  const keys = ['playable', 'game', 'data', 'payload'];
  for (const key of keys) {
    const value = result[key];
    if (value && typeof value === 'object' && 'templateId' in value && 'payload' in value) {
      return value;
    }
  }

  return null;
}

/**
 * @typedef {{
 *  rootEl: HTMLElement;
 * }} InitParams
 */

/**
 * @param {HTMLElement} rootEl
 * @param {string} role
 */
function q(rootEl, role) {
  const el = rootEl.querySelector(`[data-role="${role}"]`);
  if (!el) throw new Error(`Missing element [data-role="${role}"]`);
  return /** @type {HTMLElement} */ (el);
}

function show(el) {
  el.classList.remove('hidden');
}
function hide(el) {
  el.classList.add('hidden');
}

function normalizeGameStatusMessage(raw) {
  if (!raw || typeof raw !== 'string') return '';
  const msg = raw.trim();
  if (!msg) return '';

  const lower = msg.toLowerCase();
  if (lower.includes('generating game payload with gemini')) return 'Dang tao noi dung game bang Gemini...';
  if (lower.includes('starting game generation') || lower.includes('start game generation')) return 'Dang bat dau tao game...';
  if (lower.includes('validating') && lower.includes('input')) return 'Dang kiem tra du lieu dau vao...';
  if (lower.includes('fetching') && (lower.includes('slide') || lower.includes('document'))) {
    return 'Dang lay du lieu slide...';
  }
  if (lower.includes('building') && lower.includes('payload')) return 'Dang xay dung du lieu game...';
  if (lower.includes('queue')) return 'Dang xep hang xu ly...';
  if (lower.includes('processing')) return 'Dang xu ly...';
  if (lower.includes('completed') || lower.includes('success')) return 'Da hoan tat.';

  return msg;
}

/**
 * @param {InitParams} params
 * @returns {() => void} dispose
 */
export function initTeacherGameEditor({ rootEl }) {
  const createBtn = /** @type {HTMLButtonElement} */ (q(rootEl, 'create-game-btn'));
  const modalEl = q(rootEl, 'config-modal');
  const modalBackdrop = q(rootEl, 'config-backdrop');
  const closeBtn = /** @type {HTMLButtonElement} */ (q(rootEl, 'close-modal-btn'));
  const saveBtn = /** @type {HTMLButtonElement} */ (q(rootEl, 'save-game-btn'));

  const templateSelect = /** @type {HTMLSelectElement} */ (q(rootEl, 'template-select'));

  const statusEl = q(rootEl, 'engine-status');
  const videoEl = /** @type {HTMLVideoElement} */ (q(rootEl, 'video'));
  const canvasEl = /** @type {HTMLCanvasElement} */ (q(rootEl, 'canvas'));

  /** @type {GameEngine | null} */
  let engine = null;
  /** @type {MediaPipeTracker | null} */
  let tracker = null;
  /** @type {number | null} */
  let pollingTimer = null;

  const setStatus = (msg) => {
    statusEl.textContent = msg;
  };

  const stopPolling = () => {
    if (pollingTimer !== null) {
      window.clearInterval(pollingTimer);
      pollingTimer = null;
    }
  };

  const openModal = () => show(modalEl);
  const closeModal = () => hide(modalEl);

  const launchGame = async (playable) => {
    // dispose previous
    if (engine) {
      engine.dispose();
      engine = null;
    }

    if (tracker) {
      tracker.stop();
      tracker = null;
    }

    tracker = new MediaPipeTracker({
      videoEl,
      onFrame: () => {},
    });

    engine = new GameEngine({
      canvasEl,
      videoEl,
      playable,
      tracker,
      onStatus: setStatus,
    });

    await engine.init();
  };

  const handleSave = async () => {
    const templateId = /** @type {any} */ (templateSelect.value);

    const accessToken = localStorage.getItem('accessToken');
    const productCode = sessionStorage.getItem('eduvi_product_code') || '';
    let slideEditedDocumentUrl = sessionStorage.getItem('eduvi_last_edited_slide_gcs_url') || '';

    if (!slideEditedDocumentUrl && productCode) {
      try {
        const editedRes = await fetch(`/api/Product/${encodeURIComponent(productCode)}/slide/edited`, {
          method: 'GET',
          headers: {
            ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
          },
        });

        if (editedRes.ok) {
          const editedPayload = await editedRes.json();
          const ref = editedPayload?.result?.slideEditedDocument;
          if (typeof ref === 'string' && ref.startsWith('gs://')) {
            slideEditedDocumentUrl = ref;
            sessionStorage.setItem('eduvi_last_edited_slide_gcs_url', ref);
          }
        }
      } catch {
        // Ignore and let validation below handle missing URL.
      }
    }

    if (!slideEditedDocumentUrl) {
      setStatus('Thiếu slideEditedDocumentUrl. Hãy lưu slide trước hoặc đảm bảo API /slide/edited đã có dữ liệu.');
      return;
    }

    const roundCount = 1;

    /** @type {{ templateId: string; slideEditedDocumentUrl: string; roundCount: number; }} */
    const req = {
      templateId,
      slideEditedDocumentUrl,
      roundCount,
    };

    // Task requirement: console.log request payload
    // eslint-disable-next-line no-console
    console.log('[CreatePlayableGameTaskInput]', req);

    closeModal();
    stopPolling();

    try {
      setStatus('Đang gửi yêu cầu tạo game...');

      const res = await fetch('/api/Games/playable', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
        },
        body: JSON.stringify(req),
      });

      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err?.error || `BE error (${res.status})`);
      }

      const createResp = await res.json();
      const taskId = createResp?.result?.taskId;
      if (!taskId) {
        throw new Error('Không nhận được mã tác vụ từ API.');
      }

      setStatus(`Đã tạo mã tác vụ ${taskId}. Đang chờ xử lý...`);

      pollingTimer = window.setInterval(async () => {
        try {
          const statusRes = await fetch(`/api/Games/status/${taskId}`, {
            method: 'GET',
            headers: {
              ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
            },
          });

          if (!statusRes.ok) return;
          const statusPayload = await statusRes.json();
          const progress = statusPayload?.result;
          if (!progress) return;

          if (progress.detail) {
            setStatus(normalizeGameStatusMessage(progress.detail));
          } else if (progress.step) {
            setStatus(normalizeGameStatusMessage(`Dang xu ly: ${progress.step}`));
          }

          if (String(progress.status).toLowerCase() === 'failed') {
            stopPolling();
            setStatus(normalizeGameStatusMessage(progress.error || 'Tao game that bai'));
            return;
          }

          const playable = normalizePlayableResult(progress.result);
          if (playable) {
            stopPolling();
            setStatus('Đang khởi tạo...');
            await launchGame(playable);
          }
        } catch {
          // Keep polling and wait for the next cycle.
        }
      }, GAME_STATUS_POLLING_MS);
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error(e);
      stopPolling();
      setStatus(e instanceof Error ? e.message : 'Không thể khởi động game');
    }
  };

  const handleCreateClick = () => {
    // Defaults
    if (!templateSelect.value) templateSelect.value = GAME_BLUEPRINTS.HOVER_SELECT;
    openModal();
  };

  createBtn.addEventListener('click', handleCreateClick);
  closeBtn.addEventListener('click', closeModal);
  modalBackdrop.addEventListener('click', closeModal);
  saveBtn.addEventListener('click', handleSave);

  setStatus('Chưa có game. Bấm “Tạo game”.');

  return () => {
    createBtn.removeEventListener('click', handleCreateClick);
    closeBtn.removeEventListener('click', closeModal);
    modalBackdrop.removeEventListener('click', closeModal);
    saveBtn.removeEventListener('click', handleSave);

    stopPolling();

    if (engine) engine.dispose();
    if (tracker) tracker.stop();
  };
}
