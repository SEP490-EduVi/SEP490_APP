/**
 * SnakeQuizGame — Educational snake game blueprint.
 *
 * Controls:  ← → ↑ ↓ to change direction  |  1 2 3 4 to answer
 * State machine:
 *   INTRO → MOVING → QUESTION → FEEDBACK → MOVING → COMPLETE
 *
 * The snake eats food cells.  Each food has a quiz question attached.
 * Answering correctly grows the snake; wrong still relocates food.
 * All questions answered → COMPLETE.
 */

// ── Constants ─────────────────────────────────────────────────────────────────

const SPEED_MS = { slow: 320, normal: 190, fast: 130 };
const DIR = { UP: 'UP', DOWN: 'DOWN', LEFT: 'LEFT', RIGHT: 'RIGHT' };

const THEME_PALETTES = {
  classic: {
    bg:          '#0f172a',
    gridLine:    'rgba(255,255,255,0.04)',
    snakeHead:   '#22c55e',
    snakeBody:   '#16a34a',
    snakeGlow:   '#4ade80',
    food:        '#f59e0b',
    foodGlow:    '#fbbf24',
    text:        '#e2e8f0',
  },
  neon: {
    bg:          '#0d0d0d',
    gridLine:    'rgba(0,255,255,0.06)',
    snakeHead:   '#00ffcc',
    snakeBody:   '#00cc99',
    snakeGlow:   '#00ffcc',
    food:        '#ff007a',
    foodGlow:    '#ff66b2',
    text:        '#e0f2fe',
  },
  candy: {
    bg:          '#1e1b4b',
    gridLine:    'rgba(255,255,255,0.05)',
    snakeHead:   '#e879f9',
    snakeBody:   '#a855f7',
    snakeGlow:   '#f0abfc',
    food:        '#fbbf24',
    foodGlow:    '#fde68a',
    text:        '#f1f5f9',
  },
};

function lerp(a, b, t) { return a + (b - a) * t; }
function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }
function easeOut(t) { return 1 - (1 - t) * (1 - t); }

function roundRect(ctx, x, y, w, h, r) {
  r = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

// ── SnakeQuizGame ─────────────────────────────────────────────────────────────

export class SnakeQuizGame {
  /**
   * @param {{
   *   playable: import('./api-contracts.js').SnakeQuizPlayable;
   *   settings: any;
   *   canvas: HTMLCanvasElement;
   *   keyboard: import('./keyboard-input.js').KeyboardInput;
   * }} params
   */
  constructor({ playable, settings, canvas, keyboard }) {
    this.playable  = playable;
    this.canvas    = canvas;
    this.kb        = keyboard;

    this.gridSize  = playable.gridSize ?? 20;
    this.questions = [...(playable.questions ?? [])];
    this.theme     = THEME_PALETTES[playable.theme ?? 'neon'];
    this.tickMs    = SPEED_MS[playable.speed ?? 'normal'];

    // State: 'INTRO' | 'MOVING' | 'QUESTION' | 'FEEDBACK' | 'COMPLETE'
    this.state      = 'INTRO';
    this.stateAtMs  = performance.now();

    this.score         = 0;
    this.questionIndex = 0;           // which question is current food

    // Snake: array of {col,row}, head first
    const midC = Math.floor(this.gridSize / 2);
    const midR = Math.floor(this.gridSize / 2);
    this.snake = [
      { col: midC, row: midR },
      { col: midC - 1, row: midR },
      { col: midC - 2, row: midR },
    ];

    this.dir      = DIR.RIGHT;
    this.nextDir  = DIR.RIGHT;         // buffer one direction change per tick

    // Food
    this.food      = null;             // {col, row, questionId}
    this.foodPulse = 0;               // 0-1 animation

    // Tick
    this._lastTickMs = null;

    // Feedback
    this.feedbackCorrect  = null;
    this.selectedChoiceId = null;

    // Grow queue: number of segments to add after eating
    this.growQueue = 0;

    // Completed
    this.completedAtMs = null;

    // Confetti
    this.particles = [];
  }

  isComplete()       { return this.completedAtMs != null; }
  getCompletedAtMs() { return this.completedAtMs; }
  getResult() {
    return { correct: this.score, total: this.questions.length };
  }

  // ── Update ─────────────────────────────────────────────────────────────────

  /** @param {{ nowMs: number }} frame */
  update({ nowMs }) {
    const dt = Math.min(32, nowMs - (this._lastFrameMs ?? nowMs));
    this._lastFrameMs = nowMs;

    switch (this.state) {
      case 'INTRO':    this._updateIntro(nowMs);          break;
      case 'MOVING':   this._updateMoving(dt, nowMs);     break;
      case 'QUESTION': this._updateQuestion(nowMs);       break;
      case 'FEEDBACK': this._updateFeedback(nowMs);       break;
      case 'COMPLETE': this._updateComplete(dt, nowMs);   break;
    }

    this.kb.resetFrame();
  }

  _updateIntro(nowMs) {
    if (nowMs - this.stateAtMs >= 2500) {
      this._placeFood();
      this._lastTickMs = nowMs;
      this._setState('MOVING', nowMs);
    }
  }

  _updateMoving(dt, nowMs) {
    // Direction input
    const { left, right, up, down } = {
      left:  this.kb.justPressed('left'),
      right: this.kb.justPressed('right'),
      up:    this.kb.justPressed('up'),
      down:  this.kb.justPressed('down'),
    };
    if (left  && this.dir !== DIR.RIGHT) this.nextDir = DIR.LEFT;
    if (right && this.dir !== DIR.LEFT)  this.nextDir = DIR.RIGHT;
    if (up    && this.dir !== DIR.DOWN)  this.nextDir = DIR.UP;
    if (down  && this.dir !== DIR.UP)    this.nextDir = DIR.DOWN;

    // Food pulse
    this.foodPulse = (nowMs * 0.004) % (Math.PI * 2);

    // Tick
    if (this._lastTickMs == null) this._lastTickMs = nowMs;
    if (nowMs - this._lastTickMs >= this.tickMs) {
      this._lastTickMs = nowMs;
      this._tick(nowMs);
    }
  }

  _tick(nowMs) {
    this.dir = this.nextDir;

    // Compute new head
    const head = this.snake[0];
    let nc = head.col, nr = head.row;
    if (this.dir === DIR.LEFT)  nc--;
    if (this.dir === DIR.RIGHT) nc++;
    if (this.dir === DIR.UP)    nr--;
    if (this.dir === DIR.DOWN)  nr++;

    // Wall wrap
    nc = ((nc % this.gridSize) + this.gridSize) % this.gridSize;
    nr = ((nr % this.gridSize) + this.gridSize) % this.gridSize;

    // Self-collision check (edu-mode: only instant game-over skip, just reset position)
    const selfHit = this.snake.some(s => s.col === nc && s.row === nr);

    if (selfHit) {
      // Restart snake in middle without losing progress
      const mid = Math.floor(this.gridSize / 2);
      this.snake = [
        { col: mid, row: mid },
        { col: mid - 1, row: mid },
        { col: mid - 2, row: mid },
      ];
      this.dir     = DIR.RIGHT;
      this.nextDir = DIR.RIGHT;
      this.growQueue = 0;
      return;
    }

    // Move snake
    this.snake.unshift({ col: nc, row: nr });
    if (this.growQueue > 0) {
      this.growQueue--;
    } else {
      this.snake.pop();
    }

    // Check food eat
    if (this.food && nc === this.food.col && nr === this.food.row) {
      this._setState('QUESTION', nowMs);
    }
  }

  _updateQuestion(nowMs) {
    const currentQuestion = this.questions[this.questionIndex];
    if (!currentQuestion) {
      this.questionIndex++;
      if (this.questionIndex >= this.questions.length) {
        this._setState('COMPLETE', nowMs);
        this._spawnConfetti();
      } else {
        this._placeFood();
        this._lastTickMs = nowMs;
        this._setState('MOVING', nowMs);
      }
      return;
    }

    const CHOICE_KEYS = ['ans1', 'ans2', 'ans3', 'ans4'];
    for (let i = 0; i < CHOICE_KEYS.length; i++) {
      if (this.kb.justPressed(CHOICE_KEYS[i])) {
        const choice = currentQuestion.choices[i];
        if (!choice) break;
        this.selectedChoiceId = choice.id;
        this.feedbackCorrect  = choice.id === currentQuestion.correctChoiceId;
        if (this.feedbackCorrect) {
          this.score++;
          this.growQueue += 2;         // reward: grow snake
        }
        this._setState('FEEDBACK', nowMs);
        break;
      }
    }
  }

  _updateFeedback(nowMs) {
    const delay = this.feedbackCorrect ? 1100 : 900;
    if (nowMs - this.stateAtMs >= delay) {
      this.questionIndex++;
      this.selectedChoiceId = null;
      this.feedbackCorrect  = null;
      if (this.questionIndex >= this.questions.length) {
        this._setState('COMPLETE', nowMs);
        this._spawnConfetti();
      } else {
        this._placeFood();
        this._lastTickMs = nowMs;
        this._setState('MOVING', nowMs);
      }
    }
  }

  _updateComplete(dt, nowMs) {
    for (const p of this.particles) {
      p.x  += p.vx * dt;
      p.y  += p.vy * dt;
      p.vy += 0.0005 * dt;
      p.rot += p.rotV * dt;
      p.life -= dt;
    }
    this.particles = this.particles.filter(p => p.life > 0);

    if (nowMs - this.stateAtMs >= 3200 && this.completedAtMs == null) {
      this.completedAtMs = nowMs;
    }
  }

  _setState(s, nowMs) {
    this.state     = s;
    this.stateAtMs = nowMs;
  }

  _placeFood() {
    const q = this.questions[this.questionIndex];
    if (!q) return;
    // Place food in a cell not occupied by snake
    let col, row;
    let attempts = 0;
    do {
      col = Math.floor(Math.random() * this.gridSize);
      row = Math.floor(Math.random() * this.gridSize);
      attempts++;
    } while (
      attempts < 200 &&
      this.snake.some(s => s.col === col && s.row === row)
    );
    this.food = { col, row, questionId: q.id };
  }

  _spawnConfetti() {
    const colors = ['#f59e0b','#06b6d4','#10b981','#8b5cf6','#ef4444','#ec4899','#fff'];
    for (let i = 0; i < 70; i++) {
      this.particles.push({
        x:    Math.random(),
        y:    Math.random() * 0.5,
        vx:   (Math.random() - 0.5) * 0.0005,
        vy:   Math.random() * 0.0003 + 0.00005,
        rot:  Math.random() * Math.PI * 2,
        rotV: (Math.random() - 0.5) * 0.01,
        size: 0.007 + Math.random() * 0.012,
        color: colors[Math.floor(Math.random() * colors.length)],
        life: 2000 + Math.random() * 1500,
      });
    }
  }

  // ── Render ─────────────────────────────────────────────────────────────────

  /** @param {{ ctx: CanvasRenderingContext2D; nowMs: number }} params */
  render({ ctx, nowMs }) {
    const W = this.canvas.width;
    const H = this.canvas.height;

    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);

    this._drawGrid(ctx, W, H);
    this._drawBorder(ctx, W, H);
    this._drawHUD(ctx, W, H);

    if (this.state === 'INTRO') {
      this._drawIntro(ctx, W, H, nowMs);
      ctx.restore();
      return;
    }

    if (this.state !== 'COMPLETE') {
      this._drawFood(ctx, W, H, nowMs);
      this._drawSnake(ctx, W, H);
    }

    if (this.state === 'QUESTION') this._drawQuestion(ctx, W, H);
    if (this.state === 'FEEDBACK') this._drawFeedback(ctx, W, H);
    if (this.state === 'MOVING')   this._drawDirectionHint(ctx, W, H);
    if (this.state === 'COMPLETE') this._drawComplete(ctx, W, H, nowMs);

    ctx.restore();
  }

  _cellSize(W, H) {
    const gridPad   = 0.12;               // fraction of canvas for HUD at top
    const available = H * (1 - gridPad);
    return {
      cs: Math.floor(Math.min(W, available) / this.gridSize),
      ox: Math.floor((W - Math.floor(Math.min(W, available) / this.gridSize) * this.gridSize) / 2),
      oy: Math.floor(H * gridPad),
    };
  }

  _toPixel(col, row, W, H) {
    const { cs, ox, oy } = this._cellSize(W, H);
    return { x: ox + col * cs, y: oy + row * cs, cs };
  }

  _drawGrid(ctx, W, H) {
    ctx.fillStyle = this.theme.bg;
    ctx.fillRect(0, 0, W, H);

    const { cs, ox, oy } = this._cellSize(W, H);
    ctx.strokeStyle = this.theme.gridLine;
    ctx.lineWidth   = 1;

    for (let c = 0; c <= this.gridSize; c++) {
      const x = ox + c * cs;
      ctx.beginPath();
      ctx.moveTo(x, oy);
      ctx.lineTo(x, oy + this.gridSize * cs);
      ctx.stroke();
    }
    for (let r = 0; r <= this.gridSize; r++) {
      const y = oy + r * cs;
      ctx.beginPath();
      ctx.moveTo(ox, y);
      ctx.lineTo(ox + this.gridSize * cs, y);
      ctx.stroke();
    }
  }

  _drawBorder(ctx, W, H) {
    const { cs, ox, oy } = this._cellSize(W, H);
    ctx.strokeStyle = `rgba(${this._hexToRgb(this.theme.snakeGlow)},0.4)`;
    ctx.lineWidth   = 2;
    ctx.strokeRect(ox - 1, oy - 1, this.gridSize * cs + 2, this.gridSize * cs + 2);
  }

  _hexToRgb(hex) {
    const r = parseInt(hex.slice(1,3), 16);
    const g = parseInt(hex.slice(3,5), 16);
    const b = parseInt(hex.slice(5,7), 16);
    return `${r},${g},${b}`;
  }

  _drawFood(ctx, W, H, nowMs) {
    if (!this.food) return;
    const { x, y, cs } = this._toPixel(this.food.col, this.food.row, W, H);
    const pulse  = Math.sin(nowMs * 0.005) * 0.12;
    const radius = cs * (0.38 + pulse);

    // Glow
    const grd = ctx.createRadialGradient(x + cs / 2, y + cs / 2, 0, x + cs / 2, y + cs / 2, cs);
    grd.addColorStop(0,   this.theme.foodGlow);
    grd.addColorStop(0.5, this.theme.food);
    grd.addColorStop(1,   'transparent');
    ctx.fillStyle = grd;
    ctx.fillRect(x, y, cs, cs);

    // Food circle
    ctx.fillStyle = this.theme.food;
    ctx.beginPath();
    ctx.arc(x + cs / 2, y + cs / 2, radius, 0, Math.PI * 2);
    ctx.fill();

    // '?' symbol
    ctx.fillStyle = '#0d0d0d';
    ctx.font = `900 ${cs * 0.55}px system-ui`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('?', x + cs / 2, y + cs / 2);
  }

  _drawSnake(ctx, W, H) {
    const snakeLen = this.snake.length;
    for (let i = snakeLen - 1; i >= 0; i--) {
      const seg = this.snake[i];
      const { x, y, cs } = this._toPixel(seg.col, seg.row, W, H);
      const isHead = i === 0;
      const t      = 1 - i / snakeLen;

      if (isHead) {
        // Glow effect
        ctx.shadowColor = this.theme.snakeGlow;
        ctx.shadowBlur  = cs * 0.8;
      }

      ctx.fillStyle = isHead ? this.theme.snakeHead : this.theme.snakeBody;
      // Slightly smaller to show grid gap
      const pad = cs * 0.08;
      roundRect(ctx, x + pad, y + pad, cs - pad * 2, cs - pad * 2, cs * 0.25);
      ctx.fill();

      if (isHead) {
        ctx.shadowBlur = 0;
        ctx.shadowColor = 'transparent';

        // Eyes
        const eyeR = cs * 0.1;
        const eyeOff = cs * 0.2;
        let e1x, e1y, e2x, e2y;
        switch (this.dir) {
          case DIR.RIGHT: e1x = x + cs * 0.7; e1y = y + cs * 0.28; e2x = x + cs * 0.7; e2y = y + cs * 0.72; break;
          case DIR.LEFT:  e1x = x + cs * 0.3; e1y = y + cs * 0.28; e2x = x + cs * 0.3; e2y = y + cs * 0.72; break;
          case DIR.UP:    e1x = x + cs * 0.28; e1y = y + cs * 0.3; e2x = x + cs * 0.72; e2y = y + cs * 0.3; break;
          case DIR.DOWN:  e1x = x + cs * 0.28; e1y = y + cs * 0.7; e2x = x + cs * 0.72; e2y = y + cs * 0.7; break;
        }
        ctx.fillStyle = '#fff';
        ctx.beginPath();
        ctx.arc(e1x, e1y, eyeR, 0, Math.PI * 2);
        ctx.arc(e2x, e2y, eyeR, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = '#222';
        ctx.beginPath();
        ctx.arc(e1x + eyeR * 0.3, e1y + eyeR * 0.3, eyeR * 0.55, 0, Math.PI * 2);
        ctx.arc(e2x + eyeR * 0.3, e2y + eyeR * 0.3, eyeR * 0.55, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }

  _drawHUD(ctx, W, H) {
    ctx.fillStyle = `rgba(0,0,0,0.5)`;
    ctx.fillRect(0, 0, W, H * 0.1);

    ctx.fillStyle = this.theme.text;
    ctx.font = `600 ${W * 0.022}px system-ui`;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.fillText(`⭐ ${this.score} / ${this.questions.length}`, W * 0.025, H * 0.05);

    // Progress bar
    const barW  = W * 0.35;
    const barX  = (W - barW) / 2;
    const barY  = H * 0.03;
    const barH  = H * 0.035;
    const pct   = this.questions.length > 0 ? this.questionIndex / this.questions.length : 0;

    ctx.fillStyle = 'rgba(255,255,255,0.1)';
    roundRect(ctx, barX, barY, barW, barH, barH / 2);
    ctx.fill();

    ctx.fillStyle = this.theme.snakeHead;
    roundRect(ctx, barX, barY, barW * pct, barH, barH / 2);
    ctx.fill();

    ctx.fillStyle = this.theme.text;
    ctx.font = `${W * 0.016}px system-ui`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(`Câu ${Math.min(this.questionIndex + 1, this.questions.length)} / ${this.questions.length}`, W / 2, barY + barH / 2);

    ctx.textAlign = 'right';
    ctx.font = `${W * 0.02}px system-ui`;
    ctx.fillText(`Snake Quiz`, W * 0.975, H * 0.05);
  }

  _drawDirectionHint(ctx, W, H) {
    ctx.fillStyle = 'rgba(255,255,255,0.35)';
    ctx.font = `${W * 0.016}px system-ui`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'bottom';
    ctx.fillText('← ↑ ↓ → Di chuyển', W / 2, H * 0.99);
  }

  _drawIntro(ctx, W, H, nowMs) {
    const elapsed  = nowMs - this.stateAtMs;
    const alpha    = clamp(elapsed / 800, 0, 1);

    ctx.fillStyle = `rgba(0,0,0,${0.82 * alpha})`;
    ctx.fillRect(0, 0, W, H);

    ctx.fillStyle = `rgba(${this._hexToRgb(this.theme.snakeHead)}, ${alpha})`;
    ctx.font = `bold ${W * 0.055}px system-ui`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('🐍  Rắn Học Tập', W / 2, H * 0.35);

    ctx.fillStyle = `rgba(255,255,255,${alpha * 0.8})`;
    ctx.font = `${W * 0.024}px system-ui`;
    ctx.fillText('Điều khiển rắn đến ô ❓', W / 2, H * 0.48);
    ctx.fillText('rồi chọn đáp án đúng', W / 2, H * 0.545);
    ctx.fillText('Dùng phím  ← ↑ ↓ →  để di chuyển', W / 2, H * 0.63);
    ctx.fillText('Nhấn  1 2 3 4  để trả lời', W / 2, H * 0.695);
  }

  _drawQuestion(ctx, W, H) {
    const q = this.questions[this.questionIndex];
    if (!q) return;
    this._drawQuestionOverlay(ctx, W, H, q, null, null);
  }

  _drawFeedback(ctx, W, H) {
    const q = this.questions[this.questionIndex];
    if (!q) return;
    this._drawQuestionOverlay(ctx, W, H, q, this.selectedChoiceId, this.feedbackCorrect);
  }

  _drawQuestionOverlay(ctx, W, H, q, selectedId, isCorrect) {
    ctx.fillStyle = 'rgba(0,0,0,0.70)';
    ctx.fillRect(0, 0, W, H);

    const cardW = W * 0.84;
    const cardH = H * 0.72;
    const cardX = (W - cardW) / 2;
    const cardY = (H - cardH) / 2;

    ctx.fillStyle = '#0f172a';
    roundRect(ctx, cardX, cardY, cardW, cardH, 18);
    ctx.fill();
    ctx.strokeStyle = this.theme.snakeHead;
    ctx.lineWidth = 2.5;
    roundRect(ctx, cardX, cardY, cardW, cardH, 18);
    ctx.stroke();

    // Prompt
    ctx.fillStyle = this.theme.text;
    ctx.font = `600 ${W * 0.027}px system-ui`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const lines  = this._wrapText(ctx, q.prompt, cardW * 0.84);
    const lineH  = W * 0.034;
    const ptY    = cardY + cardH * 0.14;
    for (let i = 0; i < Math.min(lines.length, 3); i++) {
      ctx.fillText(lines[i], W / 2, ptY + i * lineH);
    }

    // Choices 2×2
    const cols = 2, rows = 2;
    const choiceW = cardW * 0.44;
    const choiceH = cardH * 0.16;
    const gapX = cardW * 0.04;
    const gapY = cardH * 0.04;
    const startX = cardX + (cardW - cols * choiceW - (cols - 1) * gapX) / 2;
    const startY = cardY + cardH * 0.33;
    const labels = ['1', '2', '3', '4'];

    q.choices.forEach((c, idx) => {
      const col = idx % cols;
      const row = Math.floor(idx / cols);
      const cx  = startX + col * (choiceW + gapX);
      const cy  = startY + row * (choiceH + gapY);

      const isSel  = selectedId === c.id;
      const isCrct = c.id === q.correctChoiceId;

      let bg     = 'rgba(255,255,255,0.06)';
      let border = 'rgba(255,255,255,0.2)';
      if (isSel && isCorrect)   { bg = 'rgba(16,185,129,0.35)';  border = '#10b981'; }
      if (isSel && !isCorrect)  { bg = 'rgba(239,68,68,0.35)';   border = '#ef4444'; }
      if (selectedId && isCrct && !isCorrect) { bg = 'rgba(16,185,129,0.18)'; border = '#10b981'; }

      ctx.fillStyle = bg;
      roundRect(ctx, cx, cy, choiceW, choiceH, 10);
      ctx.fill();
      ctx.strokeStyle = border;
      ctx.lineWidth   = 1.5;
      roundRect(ctx, cx, cy, choiceW, choiceH, 10);
      ctx.stroke();

      // Label
      const lbSize = choiceH * 0.52;
      ctx.fillStyle = `rgba(${this._hexToRgb(this.theme.snakeHead)}, 0.85)`;
      roundRect(ctx, cx + 8, cy + (choiceH - lbSize) / 2, lbSize, lbSize, 6);
      ctx.fill();
      ctx.fillStyle = '#000';
      ctx.font = `700 ${lbSize * 0.52}px system-ui`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(labels[idx], cx + 8 + lbSize / 2, cy + choiceH / 2);

      // Choice text
      ctx.fillStyle = this.theme.text;
      ctx.font = `${W * 0.019}px system-ui`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      const cLines = this._wrapText(ctx, c.text, choiceW - lbSize - 20);
      const textX  = cx + lbSize + (choiceW - lbSize) / 2 + 4;
      ctx.fillText(cLines[0] ?? c.text, textX, cy + choiceH / 2);
    });

    // Hint / feedback
    if (!selectedId) {
      ctx.fillStyle = 'rgba(255,255,255,0.35)';
      ctx.font = `${W * 0.018}px system-ui`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('Nhấn  1  2  3  4  để chọn đáp án', W / 2, cardY + cardH * 0.9);
    } else {
      const msg   = isCorrect ? '✓  Đúng rồi! Rắn của bạn lớn hơn!' : '✗  Sai rồi!';
      const bgCol = isCorrect ? 'rgba(16,185,129,0.9)' : 'rgba(239,68,68,0.9)';
      ctx.fillStyle = bgCol;
      roundRect(ctx, cardX, cardY + cardH - 52, cardW, 52, 14);
      ctx.fill();
      ctx.fillStyle = '#fff';
      ctx.font = `700 ${W * 0.024}px system-ui`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(msg, W / 2, cardY + cardH - 26);
    }
  }

  _drawComplete(ctx, W, H, nowMs) {
    const elapsed = nowMs - this.stateAtMs;
    const alpha   = clamp(elapsed / 600, 0, 1);

    ctx.fillStyle = `rgba(0,0,0,${0.5 * alpha})`;
    ctx.fillRect(0, 0, W, H);

    for (const pt of this.particles) {
      ctx.save();
      ctx.translate(pt.x * W, pt.y * H);
      ctx.rotate(pt.rot);
      const s = pt.size * W;
      ctx.fillStyle = pt.color;
      ctx.fillRect(-s / 2, -s / 2, s, s * 0.6);
      ctx.restore();
    }

    const t     = easeOut(clamp(elapsed / 700, 0, 1));
    const cardW = W * 0.7;
    const cardH = H * 0.48;
    const cardX = (W - cardW) / 2;
    const cardY = lerp(H, (H - cardH) / 2, t);

    ctx.fillStyle = '#0f172a';
    roundRect(ctx, cardX, cardY, cardW, cardH, 22);
    ctx.fill();
    ctx.strokeStyle = this.theme.snakeGlow;
    ctx.lineWidth = 3;
    roundRect(ctx, cardX, cardY, cardW, cardH, 22);
    ctx.stroke();

    ctx.fillStyle = this.theme.snakeHead;
    ctx.font = `bold ${W * 0.052}px system-ui`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('🎉  Hoàn thành!  🎉', W / 2, cardY + cardH * 0.22);

    ctx.fillStyle = this.theme.text;
    ctx.font = `${W * 0.03}px system-ui`;
    ctx.fillText(`Đúng ${this.score} / ${this.questions.length} câu`, W / 2, cardY + cardH * 0.46);

    const pct = this.questions.length > 0 ? Math.round((this.score / this.questions.length) * 100) : 0;
    const msg = pct === 100 ? '⭐ Xuất sắc!' : pct >= 60 ? '👍 Khá tốt!' : '📚 Cần ôn thêm!';
    ctx.fillStyle = '#94a3b8';
    ctx.font = `600 ${W * 0.026}px system-ui`;
    ctx.fillText(msg, W / 2, cardY + cardH * 0.7);
  }

  _wrapText(ctx, text, maxW) {
    const words = String(text || '').split(/\s+/);
    const lines = [];
    let line = '';
    for (const w of words) {
      const test = line ? `${line} ${w}` : w;
      if (ctx.measureText(test).width > maxW && line) {
        lines.push(line);
        line = w;
      } else {
        line = test;
      }
    }
    if (line) lines.push(line);
    return lines;
  }
}
