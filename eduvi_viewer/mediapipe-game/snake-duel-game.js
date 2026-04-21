/**
 * SnakeDuelGame — 2-Player educational snake duel on one shared grid.
 *
 * Player 1 (green snake): WASD to move, Z X C V to answer
 * Player 2 (cyan snake) : Arrows to move, 1 2 3 4 to answer
 *
 * Rules:
 *  - Shared 20×20 grid with a single "?" food cell
 *  - The snake that eats the food first gets the question
 *  - The other snake keeps moving freely while the question is shown
 *  - Correct answer: eating snake grows +2 segments, food respawns for next question
 *  - Wrong answer: no growth, food respawns immediately (no score penalty)
 *  - Snake–snake collision: pass-through (no death, edu-friendly)
 *  - Self-collision: snake resets to start position (no hard game over)
 *  - Game ends after all questions are answered → score comparison
 *
 * State machine:
 *   INTRO → MOVING → QUESTION(whoAte) → FEEDBACK → MOVING → … → COMPLETE
 */

// ── Constants ─────────────────────────────────────────────────────────────────
const TICK_MS      = 200;   // movement tick (ms per cell)
const GRID_SIZE    = 20;

const DIR = { UP: 'UP', DOWN: 'DOWN', LEFT: 'LEFT', RIGHT: 'RIGHT' };

// ── Player configs ─────────────────────────────────────────────────────────────
const PLAYER_CFGS = [
  { label: 'P1', headColor: '#22c55e', bodyColor: '#16a34a', glowColor: '#4ade80', nameColor: '#86efac', startCol: 5,  startRow: 10, startDir: DIR.RIGHT, ansHint: 'Z X C V / 1 2 3 4' },
  { label: 'P2', headColor: '#06b6d4', bodyColor: '#0891b2', glowColor: '#67e8f9', nameColor: '#a5f3fc', startCol: 14, startRow: 10, startDir: DIR.LEFT,  ansHint: '1 2 3 4' },
];

// ── Theme ─────────────────────────────────────────────────────────────────────
const THEME = {
  bg:        '#0f172a',
  gridLine:  'rgba(255,255,255,0.04)',
  food:      '#f59e0b',
  foodGlow:  '#fbbf24',
  text:      '#e2e8f0',
};

// ── Helpers ───────────────────────────────────────────────────────────────────
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

function makeSnake(cfg) {
  return [
    { col: cfg.startCol,     row: cfg.startRow },
    { col: cfg.startCol - (cfg.startDir === DIR.RIGHT ? 1 : -1), row: cfg.startRow },
    { col: cfg.startCol - (cfg.startDir === DIR.RIGHT ? 2 : -2), row: cfg.startRow },
  ];
}

// ── SnakeDuelGame ─────────────────────────────────────────────────────────────
export class SnakeDuelGame {
  /**
   * @param {{
   *   playable: any;
   *   settings: any;
   *   canvas: HTMLCanvasElement;
   *   keyboard: import('./dual-keyboard-input.js').DualKeyboardInput;
   * }} params
   */
  constructor({ playable, settings, canvas, keyboard }) {
    this.playable  = playable;
    this.canvas    = canvas;
    this.dual      = keyboard; // DualKeyboardInput

    this.gridSize  = GRID_SIZE;
    this.questions = [...(playable.questions ?? [])];
    this.tickMs    = TICK_MS;

    // State machine
    this.state      = 'INTRO';
    this.stateAtMs  = performance.now();

    // Per-player state
    this.snakes = PLAYER_CFGS.map(cfg => ({
      cfg,
      body:      makeSnake(cfg),
      dir:       cfg.startDir,
      nextDir:   cfg.startDir,
      growQueue: 0,
      score:     0,
      isAnswer:  false,   // currently answering this frame
    }));

    // Question state
    this.questionIndex   = 0;
    this.whichAte        = -1;   // player index who ate food this round
    this.selectedChoiceId = null;
    this.feedbackCorrect = null;

    // Food
    this.food  = null; // {col, row}
    this.foodPulse = 0;

    // Tick
    this._lastTickMs   = null;
    this._lastFrameMs  = null;

    // Effects
    this.particles = []; // confetti
    this.flashes   = []; // eating flash {col, row, life, color}

    this.completedAtMs = null;
  }

  isComplete()       { return this.completedAtMs != null; }
  getCompletedAtMs() { return this.completedAtMs; }
  getResult() {
    const total   = this.questions.length;
    const correct = this.snakes[0].score + this.snakes[1].score;
    return { correct, total };
  }

  // ── Update ────────────────────────────────────────────────────────────────
  update({ nowMs }) {
    const dt = Math.min(32, nowMs - (this._lastFrameMs ?? nowMs));
    this._lastFrameMs = nowMs;

    switch (this.state) {
      case 'INTRO':    this._updateIntro(nowMs);          break;
      case 'MOVING':   this._updateMoving(dt, nowMs);     break;
      case 'QUESTION': this._updateQuestion(dt, nowMs);   break;
      case 'FEEDBACK': this._updateFeedback(nowMs);       break;
      case 'COMPLETE': this._updateComplete(dt, nowMs);   break;
    }

    // Flash effects
    for (const f of this.flashes) f.life -= dt;
    this.flashes = this.flashes.filter(f => f.life > 0);

    this.dual.resetFrame();
  }

  _updateIntro(nowMs) {
    if (nowMs - this.stateAtMs >= 2800) {
      this._placeFood();
      this._lastTickMs = nowMs;
      this._setState('MOVING', nowMs);
    }
  }

  _updateMoving(dt, nowMs) {
    // Direction input for both snakes
    for (let pi = 0; pi < 2; pi++) {
      const sn = this.snakes[pi];
      const kb = pi === 0 ? this.dual.player1 : this.dual.player2;
      if (kb.justPressed('left')  && sn.dir !== DIR.RIGHT) sn.nextDir = DIR.LEFT;
      if (kb.justPressed('right') && sn.dir !== DIR.LEFT)  sn.nextDir = DIR.RIGHT;
      if (kb.justPressed('up')    && sn.dir !== DIR.DOWN)  sn.nextDir = DIR.UP;
      if (kb.justPressed('down')  && sn.dir !== DIR.UP)    sn.nextDir = DIR.DOWN;
    }

    this.foodPulse = (nowMs * 0.004) % (Math.PI * 2);

    // Tick
    if (this._lastTickMs == null) this._lastTickMs = nowMs;
    if (nowMs - this._lastTickMs >= this.tickMs) {
      this._lastTickMs = nowMs;
      this._tickMovement(nowMs);
    }
  }

  _tickMovement(nowMs) {
    // Move both snakes and check who eats food
    let eater = -1;

    for (let pi = 0; pi < 2; pi++) {
      const sn   = this.snakes[pi];
      sn.dir     = sn.nextDir;
      const head = sn.body[0];
      let nc = head.col, nr = head.row;

      if (sn.dir === DIR.LEFT)  nc--;
      if (sn.dir === DIR.RIGHT) nc++;
      if (sn.dir === DIR.UP)    nr--;
      if (sn.dir === DIR.DOWN)  nr++;

      // Wall wrap
      nc = ((nc % this.gridSize) + this.gridSize) % this.gridSize;
      nr = ((nr % this.gridSize) + this.gridSize) % this.gridSize;

      // Self-collision: reset this snake
      if (sn.body.some(s => s.col === nc && s.row === nr)) {
        this._resetSnake(pi);
        continue;
      }

      // Move
      sn.body.unshift({ col: nc, row: nr });
      if (sn.growQueue > 0) {
        sn.growQueue--;
      } else {
        sn.body.pop();
      }

      // Food eat check — first snake to reach the food wins the question
      if (this.food && nc === this.food.col && nr === this.food.row && eater === -1) {
        eater = pi;
        // flash
        this.flashes.push({ col: nc, row: nr, life: 400, color: PLAYER_CFGS[pi].glowColor });
      }
    }

    if (eater !== -1) {
      this.whichAte = eater;
      this._setState('QUESTION', nowMs);
    }
  }

  _updateQuestion(dt, nowMs) {
    // Non-answering snake keeps moving
    const otherPi = this.whichAte === 0 ? 1 : 0;
    const otherSn = this.snakes[otherPi];
    const otherKb = otherPi === 0 ? this.dual.player1 : this.dual.player2;

    if (otherKb.justPressed('left')  && otherSn.dir !== DIR.RIGHT) otherSn.nextDir = DIR.LEFT;
    if (otherKb.justPressed('right') && otherSn.dir !== DIR.LEFT)  otherSn.nextDir = DIR.RIGHT;
    if (otherKb.justPressed('up')    && otherSn.dir !== DIR.DOWN)  otherSn.nextDir = DIR.UP;
    if (otherKb.justPressed('down')  && otherSn.dir !== DIR.UP)    otherSn.nextDir = DIR.DOWN;

    if (this._lastTickMs == null) this._lastTickMs = nowMs;
    if (nowMs - this._lastTickMs >= this.tickMs) {
      this._lastTickMs = nowMs;
      this._tickSingleSnake(otherPi, nowMs);
    }

    // Answering snake processes keys
    const q  = this.questions[this.questionIndex];
    if (!q) {
      this.whichAte = -1;
      this._placeFood();
      this._setState('MOVING', nowMs);
      return;
    }
    const eatKb = this.whichAte === 0 ? this.dual.player1 : this.dual.player2;
    const eatKbAlt = this.whichAte === 0 ? this.dual.player2 : null;
    const KEYS  = ['ans1', 'ans2', 'ans3', 'ans4'];
    for (let ki = 0; ki < KEYS.length; ki++) {
      const pressedPrimary = eatKb.justPressed(KEYS[ki]);
      const pressedAlt = eatKbAlt ? eatKbAlt.justPressed(KEYS[ki]) : false;
      if (pressedPrimary || pressedAlt) {
        const choice = q.choices[ki];
        if (!choice) break;
        this.selectedChoiceId = choice.id;
        this.feedbackCorrect  = choice.id === q.correctChoiceId;
        if (this.feedbackCorrect) {
          this.snakes[this.whichAte].score++;
          this.snakes[this.whichAte].growQueue += 2;
        }
        this._setState('FEEDBACK', nowMs);
        break;
      }
    }

    // 8-second timeout
    if (nowMs - this.stateAtMs >= 8000 && !this.selectedChoiceId) {
      this.selectedChoiceId = null;
      this.feedbackCorrect  = false;
      this._setState('FEEDBACK', nowMs);
    }
  }

  _tickSingleSnake(pi, nowMs) {
    const sn   = this.snakes[pi];
    sn.dir     = sn.nextDir;
    const head = sn.body[0];
    let nc = head.col, nr = head.row;

    if (sn.dir === DIR.LEFT)  nc--;
    if (sn.dir === DIR.RIGHT) nc++;
    if (sn.dir === DIR.UP)    nr--;
    if (sn.dir === DIR.DOWN)  nr++;

    nc = ((nc % this.gridSize) + this.gridSize) % this.gridSize;
    nr = ((nr % this.gridSize) + this.gridSize) % this.gridSize;

    if (sn.body.some(s => s.col === nc && s.row === nr)) {
      this._resetSnake(pi); return;
    }

    sn.body.unshift({ col: nc, row: nr });
    if (sn.growQueue > 0) sn.growQueue--;
    else sn.body.pop();
  }

  _updateFeedback(nowMs) {
    if (nowMs - this.stateAtMs < 1500) return;
    this.questionIndex++;
    this.selectedChoiceId = null;
    this.feedbackCorrect  = null;
    this.whichAte         = -1;
    if (this.questionIndex >= this.questions.length) {
      this._setState('COMPLETE', nowMs);
      this._spawnConfetti();
    } else {
      this._placeFood();
      this._lastTickMs = nowMs;
      this._setState('MOVING', nowMs);
    }
  }

  _updateComplete(dt, nowMs) {
    for (const p of this.particles) {
      p.x += p.vx * dt; p.y += p.vy * dt;
      p.vy += 0.0005 * dt;
      p.rot += p.rotV * dt;
      p.life -= dt;
    }
    this.particles = this.particles.filter(p => p.life > 0);
    if (nowMs - this.stateAtMs >= 3500 && this.completedAtMs == null) {
      this.completedAtMs = nowMs;
    }
  }

  _setState(s, nowMs) { this.state = s; this.stateAtMs = nowMs; }

  _resetSnake(pi) {
    const cfg          = PLAYER_CFGS[pi];
    this.snakes[pi].body      = makeSnake(cfg);
    this.snakes[pi].dir       = cfg.startDir;
    this.snakes[pi].nextDir   = cfg.startDir;
    this.snakes[pi].growQueue = 0;
  }

  _placeFood() {
    const allBodies = this.snakes.flatMap(sn => sn.body);
    let col, row, attempts = 0;
    do {
      col = Math.floor(Math.random() * this.gridSize);
      row = Math.floor(Math.random() * this.gridSize);
      attempts++;
    } while (attempts < 300 && allBodies.some(s => s.col === col && s.row === row));
    this.food = { col, row };
  }

  _spawnConfetti() {
    const colors = ['#f59e0b','#ef4444','#3b82f6','#10b981','#8b5cf6','#ec4899','#fff'];
    for (let i = 0; i < 90; i++) {
      this.particles.push({
        x: Math.random(), y: Math.random() * 0.4,
        vx: (Math.random() - 0.5) * 0.0005,
        vy: Math.random() * 0.0003 + 0.0001,
        rot: Math.random() * Math.PI * 2,
        rotV: (Math.random() - 0.5) * 0.012,
        size: 0.008 + Math.random() * 0.010,
        color: colors[Math.floor(Math.random() * colors.length)],
        life: 2500 + Math.random() * 1500,
      });
    }
  }

  // ── Render ────────────────────────────────────────────────────────────────
  render({ ctx, nowMs }) {
    const W = this.canvas.width;
    const H = this.canvas.height;
    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);

    // Background
    ctx.fillStyle = THEME.bg;
    ctx.fillRect(0, 0, W, H);

    // Compute grid layout (centered square)
    const hud        = H * 0.10;
    const hint       = H * 0.05;
    const available  = Math.min(W, H - hud - hint) * 0.94;
    const cellSize   = available / this.gridSize;
    const gridW      = cellSize * this.gridSize;
    const gridH      = gridW;
    const gridX      = (W - gridW) / 2;
    const gridY      = hud + (H - hud - hint - gridH) / 2;

    const gCtx = { cellSize, gridX, gridY };

    this._drawGrid(ctx, gCtx, W, H);
    this._drawFlashes(ctx, gCtx, nowMs);
    this._drawFood(ctx, gCtx, nowMs);
    for (let pi = 0; pi < 2; pi++) this._drawSnake(ctx, gCtx, pi);
    this._drawHUD(ctx, W, H);

    if (this.state === 'INTRO')    this._drawIntro(ctx, W, H, nowMs);
    if (this.state === 'QUESTION') this._drawQuestion(ctx, W, H);
    if (this.state === 'FEEDBACK') this._drawFeedback(ctx, W, H);
    if (this.state === 'COMPLETE') this._drawComplete(ctx, W, H, nowMs);

    if (this.state === 'MOVING' || this.state === 'QUESTION') {
      this._drawControlsHint(ctx, W, H, gridY + gridH);
    }

    ctx.restore();
  }

  _drawGrid(ctx, { cellSize, gridX, gridY }, W, H) {
    const gW = cellSize * this.gridSize;
    const gH = cellSize * this.gridSize;
    ctx.strokeStyle = THEME.gridLine;
    ctx.lineWidth   = 1;
    for (let c = 0; c <= this.gridSize; c++) {
      ctx.beginPath(); ctx.moveTo(gridX + c * cellSize, gridY); ctx.lineTo(gridX + c * cellSize, gridY + gH); ctx.stroke();
    }
    for (let r = 0; r <= this.gridSize; r++) {
      ctx.beginPath(); ctx.moveTo(gridX, gridY + r * cellSize); ctx.lineTo(gridX + gW, gridY + r * cellSize); ctx.stroke();
    }
  }

  _drawFlashes(ctx, { cellSize, gridX, gridY }, nowMs) {
    for (const f of this.flashes) {
      const alpha = clamp(f.life / 400, 0, 1);
      ctx.save();
      ctx.globalAlpha = alpha;
      ctx.fillStyle   = f.color;
      ctx.shadowColor = f.color;
      ctx.shadowBlur  = 20;
      ctx.fillRect(gridX + f.col * cellSize, gridY + f.row * cellSize, cellSize, cellSize);
      ctx.restore();
    }
  }

  _drawFood(ctx, { cellSize, gridX, gridY }, nowMs) {
    if (!this.food) return;
    const fx = gridX + this.food.col * cellSize + cellSize / 2;
    const fy = gridY + this.food.row * cellSize + cellSize / 2;
    const pulse = 0.85 + 0.15 * Math.sin(this.foodPulse);
    const r = cellSize * 0.38 * pulse;

    ctx.save();
    ctx.shadowColor = THEME.foodGlow;
    ctx.shadowBlur  = 12;
    ctx.fillStyle   = THEME.food;
    ctx.beginPath(); ctx.arc(fx, fy, r, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle   = '#1e1b4b';
    ctx.font        = `700 ${r * 1.1}px system-ui`;
    ctx.textAlign   = 'center'; ctx.textBaseline = 'middle';
    ctx.shadowBlur  = 0;
    ctx.fillText('?', fx, fy);
    ctx.restore();
  }

  _drawSnake(ctx, { cellSize, gridX, gridY }, pi) {
    const sn  = this.snakes[pi];
    const cfg = PLAYER_CFGS[pi];
    const r   = Math.max(2, cellSize * 0.13);

    for (let i = sn.body.length - 1; i >= 0; i--) {
      const seg = sn.body[i];
      const sx  = gridX + seg.col * cellSize;
      const sy  = gridY + seg.row * cellSize;
      const pad = cellSize * 0.08;
      const isHead = i === 0;

      ctx.save();
      if (isHead) {
        ctx.shadowColor = cfg.glowColor;
        ctx.shadowBlur  = 10;
      }
      ctx.fillStyle = isHead ? cfg.headColor : cfg.bodyColor;
      roundRect(ctx, sx + pad, sy + pad, cellSize - pad * 2, cellSize - pad * 2, r);
      ctx.fill();

      // Eyes on head
      if (isHead) {
        ctx.shadowBlur = 0;
        const eyeR = cellSize * 0.08;
        const eyeOffX = cellSize * 0.22, eyeOffY = cellSize * 0.28;
        const hcX = sx + cellSize / 2, hcY = sy + cellSize / 2;
        ctx.fillStyle = '#fff';
        ctx.beginPath(); ctx.arc(hcX - eyeOffX, hcY - eyeOffY + cellSize * 0.05, eyeR, 0, Math.PI * 2); ctx.fill();
        ctx.beginPath(); ctx.arc(hcX + eyeOffX, hcY - eyeOffY + cellSize * 0.05, eyeR, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = '#1a1a1a';
        ctx.beginPath(); ctx.arc(hcX - eyeOffX + 1, hcY - eyeOffY + cellSize * 0.05, eyeR * 0.5, 0, Math.PI * 2); ctx.fill();
        ctx.beginPath(); ctx.arc(hcX + eyeOffX + 1, hcY - eyeOffY + cellSize * 0.05, eyeR * 0.5, 0, Math.PI * 2); ctx.fill();
      }
      ctx.restore();
    }
  }

  _drawHUD(ctx, W, H) {
    ctx.fillStyle = 'rgba(0,0,0,0.55)';
    ctx.fillRect(0, 0, W, H * 0.10);

    // P1 (left)
    ctx.fillStyle = PLAYER_CFGS[0].nameColor;
    ctx.font      = `700 ${W * 0.022}px system-ui`;
    ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
    ctx.fillText(`P1 🐍 ${this.snakes[0].score}pt`, W * 0.025, H * 0.05);

    // P2 (right)
    ctx.fillStyle = PLAYER_CFGS[1].nameColor;
    ctx.textAlign = 'right';
    ctx.fillText(`P2 🐍 ${this.snakes[1].score}pt`, W * 0.975, H * 0.05);

    // Progress (center)
    const tot = this.questions.length;
    const dotR = W * 0.010, dotY = H * 0.05, dotSp = dotR * 2.8;
    const startX = W / 2 - (tot - 1) * dotSp / 2;
    for (let i = 0; i < tot; i++) {
      ctx.beginPath(); ctx.arc(startX + i * dotSp, dotY, dotR, 0, Math.PI * 2);
      ctx.fillStyle = i < this.questionIndex ? '#10b981'
        : i === this.questionIndex ? THEME.food
        : 'rgba(255,255,255,0.3)';
      ctx.fill();
    }

    // Snake length indicators
    ctx.fillStyle = 'rgba(255,255,255,0.35)';
    ctx.font      = `400 ${W * 0.015}px system-ui`;
    ctx.textAlign = 'left';
    ctx.fillText(`len: ${this.snakes[0].body.length}`, W * 0.025, H * 0.082);
    ctx.textAlign = 'right';
    ctx.fillText(`len: ${this.snakes[1].body.length}`, W * 0.975, H * 0.082);
  }

  _drawControlsHint(ctx, W, H, bottomY) {
    ctx.fillStyle    = 'rgba(255,255,255,0.28)';
    ctx.font         = `400 ${W * 0.013}px system-ui`;
    ctx.textAlign    = 'center';
    ctx.textBaseline = 'top';
    const isQuestion = this.state === 'QUESTION';
    const eatCfg     = this.whichAte >= 0 ? PLAYER_CFGS[this.whichAte] : null;
    if (isQuestion && eatCfg) {
      ctx.fillStyle = eatCfg.nameColor;
      ctx.fillText(`${eatCfg.label} trả lời bằng [${eatCfg.ansHint}]  |  Rắn kia vẫn di chuyển!`, W / 2, bottomY + H * 0.012);
    } else {
      ctx.fillText('P1: WASD di chuyển   P2: Arrows di chuyển  |  Ai ăn ❓ trước được hỏi!', W / 2, bottomY + H * 0.012);
    }
  }

  _drawIntro(ctx, W, H, nowMs) {
    const progress = clamp((nowMs - this.stateAtMs) / 2800, 0, 1);
    ctx.fillStyle = `rgba(0,0,0,${0.75 * (1 - easeOut(progress))})`;
    ctx.fillRect(0, 0, W, H);
    const a   = Math.min(1, progress * 3);
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillStyle = `rgba(255,255,255,${a})`;
    ctx.font = `bold ${W * 0.046}px system-ui`;
    ctx.fillText('🐍 Snake Duel — 2 Người! 🐍', W / 2, H * 0.30);
    ctx.font = `${W * 0.019}px system-ui`;
    ctx.fillStyle = `rgba(255,255,255,${a * 0.85})`;
    ctx.fillText('P1 (xanh lá): WASD di chuyển  |  P2 (cyan): Arrows di chuyển', W / 2, H * 0.44);
    ctx.fillText('Rắn nào ăn ❓ trước sẽ được trả lời câu hỏi', W / 2, H * 0.52);
    ctx.fillText('Trả lời đúng → rắn dài thêm 2 ô & +1 điểm', W / 2, H * 0.60);
    ctx.fillText('Rắn đi xuyên nhau — không chết khi va nhau!', W / 2, H * 0.68);
  }

  _drawQuestion(ctx, W, H) {
    const q = this.questions[this.questionIndex];
    if (!q) return;
    this._drawQuestionCard(ctx, W, H, q, null, null);
  }

  _drawFeedback(ctx, W, H) {
    const q = this.questions[this.questionIndex] ?? this.questions[this.questionIndex - 1];
    if (!q) return;
    this._drawQuestionCard(ctx, W, H, q, this.selectedChoiceId, this.feedbackCorrect);
  }

  _drawQuestionCard(ctx, W, H, q, selectedId, isCorrect) {
    ctx.fillStyle = 'rgba(0,0,0,0.65)';
    ctx.fillRect(0, 0, W, H);

    const cW = W * 0.82, cH = H * 0.76, cX = (W - cW) / 2, cY = (H - cH) / 2;
    ctx.fillStyle = '#1e1b4b'; roundRect(ctx, cX, cY, cW, cH, 20); ctx.fill();
    ctx.strokeStyle = 'rgba(139,92,246,0.7)'; ctx.lineWidth = 2.5;
    roundRect(ctx, cX, cY, cW, cH, 20); ctx.stroke();

    // Who ate badge
    if (this.whichAte >= 0) {
      const eatCfg = PLAYER_CFGS[this.whichAte];
      ctx.fillStyle = eatCfg.nameColor;
      ctx.font = `700 ${W * 0.015}px system-ui`;
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(`🐍 ${eatCfg.label} ăn được food! Trả lời bằng [${eatCfg.ansHint}]`, W / 2, cY + cH * 0.052);
    }

    // Prompt
    ctx.fillStyle = '#e2e8f0';
    ctx.font = `600 ${W * 0.020}px system-ui`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    const lines = this._wrapText(ctx, q.prompt, cW * 0.86), lineH = W * 0.025;
    const ptY = cY + cH * 0.16;
    for (let i = 0; i < Math.min(lines.length, 4); i++) ctx.fillText(lines[i], W / 2, ptY + i * lineH);

    // Choices
    const cols = 2, choW = cW * 0.44, choH = cH * 0.15, gX = cW * 0.04, gY = cH * 0.025;
    const sX = cX + (cW - cols * choW - (cols - 1) * gX) / 2;
    const sY = cY + cH * 0.36;
    const labels = ['1', '2', '3', '4'];
    const choiceFontSize = W * 0.014;

    q.choices.forEach((c, idx) => {
      const col = idx % cols, row = Math.floor(idx / cols);
      const cx = sX + col * (choW + gX), cy = sY + row * (choH + gY);

      let bg = 'rgba(255,255,255,0.08)', border = 'rgba(255,255,255,0.25)';
      if (selectedId != null) {
        if (c.id === q.correctChoiceId) { bg = 'rgba(16,185,129,0.30)'; border = '#10b981'; }
        if (c.id === selectedId && !isCorrect) { bg = 'rgba(239,68,68,0.30)'; border = '#ef4444'; }
      }

      ctx.fillStyle = bg; roundRect(ctx, cx, cy, choW, choH, 10); ctx.fill();
      ctx.strokeStyle = border; ctx.lineWidth = 1.5; roundRect(ctx, cx, cy, choW, choH, 10); ctx.stroke();

      // Number badge
      const lS = Math.min(choH * 0.46, choW * 0.12);
      const badgeX = cx + 8, badgeY = cy + (choH - lS) / 2;
      ctx.fillStyle = 'rgba(139,92,246,0.8)'; roundRect(ctx, badgeX, badgeY, lS, lS, 5); ctx.fill();
      ctx.fillStyle = '#fff'; ctx.font = `700 ${lS * 0.52}px system-ui`;
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(labels[idx], badgeX + lS / 2, badgeY + lS / 2);

      // Choice text — wrapped to fit inside the box
      const textX = cx + lS + 14;
      const textAreaW = choW - lS - 22;
      ctx.fillStyle = '#e2e8f0'; ctx.font = `500 ${choiceFontSize}px system-ui`;
      ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
      const cLines = this._wrapText(ctx, c.text, textAreaW);
      const cLineH = choiceFontSize * 1.35;
      const totalTH = Math.min(cLines.length, 2) * cLineH;
      const startTY = cy + choH / 2 - totalTH / 2 + cLineH / 2;
      for (let li = 0; li < Math.min(cLines.length, 2); li++) {
        ctx.fillText(cLines[li], textX, startTY + li * cLineH);
      }
    });

    // Bottom feedback
    if (selectedId != null) {
      const msg = isCorrect ? '✓ Đúng rồi! Rắn dài thêm!' : '✗ Chưa đúng. Food respawn!';
      const color = isCorrect ? 'rgba(16,185,129,0.85)' : 'rgba(239,68,68,0.85)';
      ctx.fillStyle = color; roundRect(ctx, cX, cY + cH - 46, cW, 46, 16); ctx.fill();
      ctx.fillStyle = '#fff'; ctx.font = `700 ${W * 0.018}px system-ui`;
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(msg, W / 2, cY + cH - 23);
    } else {
      ctx.fillStyle = 'rgba(255,255,255,0.3)'; ctx.font = `${W * 0.013}px system-ui`;
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText('Rắn còn lại vẫn di chuyển trong lúc này!', W / 2, cY + cH - 23);
    }
  }

  _drawComplete(ctx, W, H, nowMs) {
    const elapsed = nowMs - this.stateAtMs;
    const alpha   = clamp(elapsed / 500, 0, 1);
    ctx.fillStyle = `rgba(0,0,0,${0.5 * alpha})`; ctx.fillRect(0, 0, W, H);

    for (const pt of this.particles) {
      ctx.save(); ctx.translate(pt.x * W, pt.y * H); ctx.rotate(pt.rot);
      const s = pt.size * W; ctx.fillStyle = pt.color; ctx.fillRect(-s / 2, -s / 2, s, s * 0.6); ctx.restore();
    }

    const t = easeOut(clamp(elapsed / 600, 0, 1));
    const vW = W * 0.68, vH = H * 0.58, vX = (W - vW) / 2;
    const vY = lerp(H, (H - vH) / 2, t);

    ctx.fillStyle = '#1e1b4b'; roundRect(ctx, vX, vY, vW, vH, 24); ctx.fill();
    ctx.strokeStyle = THEME.food; ctx.lineWidth = 3; roundRect(ctx, vX, vY, vW, vH, 24); ctx.stroke();

    ctx.fillStyle = '#f59e0b'; ctx.font = `bold ${W * 0.042}px system-ui`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText('🐍 Kết quả Snake Duel! 🐍', W / 2, vY + vH * 0.14);

    const drawScore = (x, pi) => {
      const sn  = this.snakes[pi];
      const cfg = PLAYER_CFGS[pi];
      ctx.fillStyle = cfg.nameColor; ctx.font = `700 ${W * 0.028}px system-ui`;
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(cfg.label, x, vY + vH * 0.30);
      ctx.fillStyle = '#e2e8f0'; ctx.font = `700 ${W * 0.054}px system-ui`;
      ctx.fillText(`${sn.score}`, x, vY + vH * 0.47);
      ctx.fillStyle = '#a5b4fc'; ctx.font = `${W * 0.020}px system-ui`;
      ctx.fillText(`/ ${this.questions.length} điểm`, x, vY + vH * 0.59);
      ctx.fillStyle = 'rgba(255,255,255,0.4)'; ctx.font = `${W * 0.016}px system-ui`;
      ctx.fillText(`len: ${sn.body.length}`, x, vY + vH * 0.68);
    };
    drawScore(vX + vW * 0.27, 0);
    drawScore(vX + vW * 0.73, 1);

    ctx.strokeStyle = 'rgba(255,255,255,0.2)'; ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.moveTo(W / 2, vY + vH * 0.22); ctx.lineTo(W / 2, vY + vH * 0.76); ctx.stroke();

    const p1s = this.snakes[0].score, p2s = this.snakes[1].score;
    const winner = p1s > p2s ? 'P1 chiến thắng! 🏆'
      : p2s > p1s ? 'P2 chiến thắng! 🏆'
      : 'Hòa nhau! 🤝';
    const wColor = p1s > p2s ? PLAYER_CFGS[0].nameColor
      : p2s > p1s ? PLAYER_CFGS[1].nameColor : '#fbbf24';
    ctx.fillStyle = wColor; ctx.font = `700 ${W * 0.030}px system-ui`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(winner, W / 2, vY + vH * 0.88);
  }

  // ── Util ──────────────────────────────────────────────────────────────────
  _wrapText(ctx, text, maxW) {
    const words = String(text || '').split(/\s+/); const lines = []; let line = '';
    for (const w of words) {
      const test = line ? `${line} ${w}` : w;
      if (ctx.measureText(test).width > maxW && line) { lines.push(line); line = w; } else line = test;
    }
    if (line) lines.push(line); return lines;
  }
}
