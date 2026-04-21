/**
 * RunnerRaceGame — 2-Player Mario-style side-scrolling quiz race.
 *
 * Two players share the same world and compete to reach the castle.
 * Player 1 (red Mario): WASD + Space (jump) + Z X C V (answer)
 * Player 2 (blue Luigi): Arrows + Enter (jump) + 1 2 3 4 (answer)
 *
 * Rules:
 *  - Shared world: same obstacles, same checkpoints
 *  - Camera follows the leading player (max scrollX)
 *  - If the trailing player drifts > CATCH_UP_LIMIT behind the camera, they are
 *    gently teleported forward to stay on-screen
 *  - Checkpoint: when EITHER player reaches it → question appears for BOTH
 *    Each player answers with their own keys independently
 *  - The player who answers correctly first gets bonus points (+2)
 *  - Answering correctly while the other already answered correctly: +1 point
 *  - Both players continue to move while the question overlay is shown (pressure!)
 *  - Victory: when all checkpoints are passed → score comparison screen
 *
 * State machine (shared):
 *   INTRO → RACING → QUESTION → FEEDBACK → RACING → … → VICTORY
 */

// ── Physics & layout ─────────────────────────────────────────────────────────
const GRAVITY      = 0.0000033;   // normalized units / ms²
const JUMP_POWER   = -0.001;      // normalized units / ms
const GROUND_Y     = 0.80;
const CHAR_W       = 0.050;
const CHAR_H       = 0.068;
const MOVE_SPEED   = 0.00038;     // per ms
const SCROLL_SPEED = 0.00022;     // world scroll per ms
const CATCH_UP_LIMIT = 0.82;      // max screen-normalized distance behind camera

const SPIKE_H      = 0.055;
const WALL_H       = 0.092;
const OB_W         = 0.030;
const HIT_PUSHBACK = 0.09;
const HIT_INVINCIBLE = 380;
const WARN_DIST    = 0.22;

// ── Theme palettes ────────────────────────────────────────────────────────────
const THEME_PALETTES = {
  castle: { skyTop:'#1a0a2e', skyBot:'#2d1b69', ground:'#5d4037', groundTop:'#8d6e63', cloud:'rgba(255,255,255,0.18)', accent:'#f59e0b' },
  forest: { skyTop:'#0f4c2a', skyBot:'#1b7340', ground:'#3e2723', groundTop:'#558b2f', cloud:'rgba(255,255,255,0.14)', accent:'#66bb6a' },
  sky:    { skyTop:'#0077cc', skyBot:'#29b6f6', ground:'#795548', groundTop:'#a5d6a7', cloud:'rgba(255,255,255,0.55)', accent:'#ffffff' },
};

// Player configs
const PLAYER_CONFIGS = [
  { label: 'P1', color: '#e53935', hatColor: '#c62828', pantsColor: '#1565c0', shoeColor: '#4e342e', nameColor: '#ff8a80', hint: 'WASD+Space di chuyển/nhảy   Z X C V trả lời' },
  { label: 'P2', color: '#1e88e5', hatColor: '#1565c0', pantsColor: '#558b2f', shoeColor: '#3e2723', nameColor: '#82b1ff', hint: '← → ↑ ↓ +Enter di chuyển/nhảy   1 2 3 4 trả lời' },
];

// ── Helpers ───────────────────────────────────────────────────────────────────
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
function lerp(a, b, t) { return a + (b - a) * t; }
function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }
function easeOut(t) { return 1 - (1 - t) * (1 - t); }

// ── RunnerRaceGame ─────────────────────────────────────────────────────────────
export class RunnerRaceGame {
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
    this.settings  = settings;
    this.canvas    = canvas;
    this.dual      = keyboard; // DualKeyboardInput

    this.questions     = playable.questions ?? [];
    this.theme         = THEME_PALETTES[playable.theme ?? 'castle'];
    this.questionIndex = 0;

    // Shared state
    this.state     = 'INTRO';
    this.stateAtMs = performance.now();

    // Camera
    this.cameraScrollX = 0;
    this.bgOffset      = 0;

    // Per-player physics state
    this.players = [0, 1].map(i => ({
      idx:      i,
      charX:    0.12 + i * 0.04,
      charY:    GROUND_Y - CHAR_H,
      velY:     0,
      onGround: true,
      facing:   1,
      scrollX:  0,        // individual world progress
      score:    0,
      legAngle: 0,
      hitTime:  -9999,
      answered: false,    // whether this player answered current question
      answeredCorrect: false,
    }));

    // Checkpoints (shared)
    this.checkpoints = this.questions.map((q, i) => ({
      id:        q.id,
      worldX:    0.55 + i * 0.55,
      triggered: false,
    }));

    // Shared obstacles
    this.obstacles = this._generateObstacles();

    // Question state
    this.questionTriggeredByPlayer = -1; // 0 or 1
    this.questionP1Selected = null;
    this.questionP2Selected = null;
    this.firstCorrectPlayer = -1;

    // Sparkles + confetti
    this.sparkles  = [];
    this.particles = [];

    this.completedAtMs = null;
    this._lastMs       = null;
  }

  isComplete()       { return this.completedAtMs != null; }
  getCompletedAtMs() { return this.completedAtMs; }
  getResult() {
    const total   = this.questions.length;
    const correct = Math.min(total, this.players[0].score + this.players[1].score);
    return { correct, total };
  }

  // ── Obstacle generation ───────────────────────────────────────────────────
  _generateObstacles() {
    const cpXs   = this.checkpoints.map(c => c.worldX);
    const margin = 0.08;
    const segments = [];

    if (cpXs.length > 0) segments.push({ from: 0.16, to: cpXs[0] - margin });
    for (let i = 0; i < cpXs.length - 1; i++) {
      segments.push({ from: cpXs[i] + margin, to: cpXs[i + 1] - margin });
    }

    const obs = [];
    for (const seg of segments) {
      const length = seg.to - seg.from;
      if (length < 0.12) continue;
      for (let i = 0; i < 2; i++) {
        const frac   = (i + 1) / 3;
        const worldX = seg.from + frac * length;
        obs.push({ worldX, type: i % 2 === 0 ? 'spike' : 'wall', height: i % 2 === 0 ? SPIKE_H : WALL_H, cleared: [false, false] });
      }
    }
    return obs;
  }

  // ── Update ────────────────────────────────────────────────────────────────
  update({ nowMs }) {
    const dt = Math.min(40, nowMs - (this._lastMs ?? nowMs));
    this._lastMs = nowMs;

    switch (this.state) {
      case 'INTRO':    this._updateIntro(nowMs);          break;
      case 'RACING':   this._updateRacing(dt, nowMs);     break;
      case 'QUESTION': this._updateQuestion(dt, nowMs);   break;
      case 'FEEDBACK': this._updateFeedback(nowMs);       break;
      case 'VICTORY':  this._updateVictory(dt, nowMs);    break;
    }

    // Sparkle physics
    for (const s of this.sparkles) {
      s.x  += s.vx * dt;
      s.y  += s.vy * dt;
      s.vy += 0.000005 * dt;
      s.life -= dt;
    }
    this.sparkles = this.sparkles.filter(s => s.life > 0);

    this.dual.resetFrame();
  }

  _updateIntro(nowMs) {
    if (nowMs - this.stateAtMs >= 2800) this._setState('RACING', nowMs);
  }

  _updateRacing(dt, nowMs) {
    // Update both players
    for (let pi = 0; pi < 2; pi++) {
      const p  = this.players[pi];
      const kb = pi === 0 ? this.dual.player1 : this.dual.player2;
      this._updatePlayer(p, kb, dt, nowMs, pi);
    }

    // Camera: follow the leading player
    const maxScroll = Math.max(this.players[0].scrollX, this.players[1].scrollX);
    this.cameraScrollX = maxScroll;
    this.bgOffset     += SCROLL_SPEED * dt * 0.4;

    // Catch-up: if trailing player's screen X < -CATCH_UP_LIMIT, nudge forward
    for (const p of this.players) {
      const screenX = p.charX - (p.scrollX - this.cameraScrollX);
      if (screenX < -0.05) {
        p.scrollX = this.cameraScrollX;
        p.charX   = Math.max(0.06, p.charX);
      }
    }

    // Checkpoint: triggered when EITHER player reaches it
    const cp = this.checkpoints[this.questionIndex];
    if (cp && !cp.triggered) {
      for (let pi = 0; pi < 2; pi++) {
        const p   = this.players[pi];
        const cpSx = cp.worldX - p.scrollX;
        if (cpSx - p.charX < 0.07 && cpSx - p.charX > -0.05) {
          cp.triggered = true;
          this.questionTriggeredByPlayer = pi;
          this._startQuestion(nowMs);
          break;
        }
      }
    }

    if (this.questionIndex >= this.questions.length) {
      this._setState('VICTORY', nowMs);
      this._spawnConfetti();
    }
  }

  _updatePlayer(p, kb, dt, nowMs, pi) {
    const movRight = kb.isPressed('right');
    const movLeft  = kb.isPressed('left');

    if (movRight) {
      p.charX    = Math.min(0.34, p.charX + MOVE_SPEED * dt);
      p.scrollX += SCROLL_SPEED * dt;
      p.facing   = 1;
    } else if (movLeft) {
      p.charX    = Math.max(0.06, p.charX - MOVE_SPEED * dt);
      p.scrollX  = Math.max(0, p.scrollX - SCROLL_SPEED * dt * 0.5);
      p.facing   = -1;
    }

    if ((kb.justPressed('jump') || kb.justPressed('up')) && p.onGround) {
      p.velY     = JUMP_POWER;
      p.onGround = false;
    }

    p.velY  += GRAVITY * dt;
    p.charY += p.velY * dt;
    if (p.charY >= GROUND_Y - CHAR_H) {
      p.charY    = GROUND_Y - CHAR_H;
      p.velY     = 0;
      p.onGround = true;
    }

    if ((movRight || movLeft) && p.onGround) {
      p.legAngle = Math.sin(nowMs * 0.012) * 0.45;
    } else {
      p.legAngle = 0;
    }

    // Obstacle collision for this player
    const invincible = nowMs - p.hitTime < HIT_INVINCIBLE;
    for (const ob of this.obstacles) {
      const sx = ob.worldX - p.scrollX;
      if (sx < -0.15 || sx > 1.15) continue;

      if (!ob.cleared[pi] && p.charX > sx + OB_W / 2 + 0.01) {
        ob.cleared[pi] = true;
        this._spawnSparkle(sx + OB_W / 2, GROUND_Y - ob.height);
      }

      if (!invincible && !ob.cleared[pi]) {
        const hitX = p.charX < sx + OB_W / 2 && p.charX + CHAR_W > sx - OB_W / 2;
        const hitY = p.charY + CHAR_H > GROUND_Y - ob.height;
        if (hitX && hitY) {
          p.scrollX  = Math.max(0, p.scrollX - HIT_PUSHBACK);
          p.hitTime  = nowMs;
          if (p.onGround) {
            p.velY     = JUMP_POWER * 0.35;
            p.onGround = false;
          }
          for (const o of this.obstacles) {
            if (o.cleared[pi] && (o.worldX - p.scrollX) > p.charX - 0.04) {
              o.cleared[pi] = false;
            }
          }
        }
      }
    }
  }

  _startQuestion(nowMs) {
    this.players[0].answered        = false;
    this.players[0].answeredCorrect = false;
    this.players[1].answered        = false;
    this.players[1].answeredCorrect = false;
    this.questionP1Selected         = null;
    this.questionP2Selected         = null;
    this.firstCorrectPlayer         = -1;
    this._setState('QUESTION', nowMs);
  }

  _updateQuestion(dt, nowMs) {
    // Both players can still move in QUESTION state (pressure mechanic)
    for (let pi = 0; pi < 2; pi++) {
      const p  = this.players[pi];
      const kb = pi === 0 ? this.dual.player1 : this.dual.player2;
      this._updatePlayer(p, kb, dt, nowMs, pi);
    }

    // Camera follow
    const maxScroll = Math.max(this.players[0].scrollX, this.players[1].scrollX);
    this.cameraScrollX = maxScroll;

    const q = this.questions[this.questionIndex];
    if (!q) {
      this._setState('RACING', nowMs);
      return;
    }

    const KEYS = ['ans1', 'ans2', 'ans3', 'ans4'];
    for (let pi = 0; pi < 2; pi++) {
      if (this.players[pi].answered) continue;
      const kb = pi === 0 ? this.dual.player1 : this.dual.player2;
      for (let ki = 0; ki < KEYS.length; ki++) {
        if (kb.justPressed(KEYS[ki])) {
          const choice = q.choices[ki];
          if (!choice) break;
          const correct = choice.id === q.correctChoiceId;
          this.players[pi].answered        = true;
          this.players[pi].answeredCorrect = correct;

          if (pi === 0) this.questionP1Selected = choice.id;
          else          this.questionP2Selected = choice.id;

          if (correct) {
            // First correct winner gets +2, second gets +1
            const bonus = this.firstCorrectPlayer === -1 ? 2 : 1;
            this.players[pi].score += bonus;
            if (this.firstCorrectPlayer === -1) this.firstCorrectPlayer = pi;
          }
          break;
        }
      }
    }

    // Move to FEEDBACK when BOTH answered, or after 8 seconds timeout
    const bothAnswered = this.players[0].answered && this.players[1].answered;
    const timedOut     = nowMs - this.stateAtMs >= 8000;
    if (bothAnswered || timedOut) {
      this._setState('FEEDBACK', nowMs);
    }
  }

  _updateFeedback(nowMs) {
    if (nowMs - this.stateAtMs < 2000) return;
    this.questionIndex++;
    if (this.questionIndex >= this.questions.length) {
      this._setState('VICTORY', nowMs);
      this._spawnConfetti();
    } else {
      this._setState('RACING', nowMs);
    }
  }

  _updateVictory(dt, nowMs) {
    for (const pt of this.particles) {
      pt.x  += pt.vx * dt;
      pt.y  += pt.vy * dt;
      pt.vy += 0.0005 * dt;
      pt.rot  += pt.rotV * dt;
      pt.life -= dt;
    }
    this.particles = this.particles.filter(p => p.life > 0);
    if (nowMs - this.stateAtMs >= 4000 && this.completedAtMs == null) {
      this.completedAtMs = nowMs;
    }
  }

  _setState(s, nowMs) { this.state = s; this.stateAtMs = nowMs; }

  _spawnSparkle(sx, sy) {
    const colors = ['#10b981','#34d399','#fbbf24','#60a5fa','#ffffff'];
    for (let i = 0; i < 8; i++) {
      const angle = (Math.PI * 2 * i) / 8 + Math.random() * 0.5;
      const speed = 0.00018 + Math.random() * 0.00025;
      this.sparkles.push({ x: sx, y: sy, vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed - 0.0003, size: 0.006 + Math.random() * 0.007, color: colors[Math.floor(Math.random() * colors.length)], life: 500 + Math.random() * 400 });
    }
  }

  _spawnConfetti() {
    const colors = ['#f59e0b','#ef4444','#3b82f6','#10b981','#8b5cf6','#ec4899','#fff'];
    for (let i = 0; i < 90; i++) {
      this.particles.push({ x: Math.random(), y: Math.random() * 0.4, vx: (Math.random() - 0.5) * 0.0005, vy: Math.random() * 0.0003 + 0.0001, rot: Math.random() * Math.PI * 2, rotV: (Math.random() - 0.5) * 0.012, size: 0.008 + Math.random() * 0.010, color: colors[Math.floor(Math.random() * colors.length)], life: 2500 + Math.random() * 1500 });
    }
  }

  // ── Render ────────────────────────────────────────────────────────────────
  render({ ctx, nowMs }) {
    const W = this.canvas.width;
    const H = this.canvas.height;
    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    this._drawBackground(ctx, W, H);
    this._drawGround(ctx, W, H);
    this._drawObstacles(ctx, W, H, nowMs);
    this._drawSparkles(ctx, W, H);
    this._drawCheckpoints(ctx, W, H, nowMs);
    // Draw players behind → P2 first, P1 on top
    for (let pi = 1; pi >= 0; pi--) this._drawPlayer(ctx, W, H, nowMs, pi);
    // Overlays
    if (this.state === 'INTRO')    this._drawIntro(ctx, W, H, nowMs);
    if (this.state === 'QUESTION') this._drawQuestion(ctx, W, H, nowMs);
    if (this.state === 'FEEDBACK') this._drawFeedback(ctx, W, H);
    if (this.state === 'VICTORY')  this._drawVictory(ctx, W, H, nowMs);
    this._drawHUD(ctx, W, H, nowMs);
    this._drawControlsHint(ctx, W, H);
    ctx.restore();
  }

  _drawBackground(ctx, W, H) {
    const grad = ctx.createLinearGradient(0, 0, 0, H * GROUND_Y);
    grad.addColorStop(0, this.theme.skyTop);
    grad.addColorStop(1, this.theme.skyBot);
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, W, H);
    const off = (this.bgOffset * W * 1.2) % W;
    const cps = [0.07, 0.29, 0.53, 0.77];
    ctx.fillStyle = this.theme.cloud;
    for (const cx of cps) {
      const x = ((cx * W + off) % W + W) % W;
      const y = H * 0.12 + Math.sin(cx * 7) * H * 0.05;
      this._drawCloud(ctx, x, y, W * 0.09);
    }
  }

  _drawCloud(ctx, cx, cy, r) {
    ctx.save();
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.arc(cx + r * 0.8, cy - r * 0.2, r * 0.7, 0, Math.PI * 2);
    ctx.arc(cx - r * 0.7, cy + r * 0.1, r * 0.6, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  _drawGround(ctx, W, H) {
    const gy = H * GROUND_Y;
    const gh = H * (1 - GROUND_Y);
    ctx.fillStyle = this.theme.ground;
    ctx.fillRect(0, gy, W, gh);
    ctx.fillStyle = this.theme.groundTop;
    ctx.fillRect(0, gy, W, H * 0.022);
    ctx.strokeStyle = 'rgba(0,0,0,0.12)';
    ctx.lineWidth = 1;
    const tileW = W * 0.08;
    const tileOff = (this.cameraScrollX * W * 1.4) % tileW;
    for (let x = -tileW + tileOff; x < W + tileW; x += tileW) {
      ctx.beginPath(); ctx.moveTo(x, gy); ctx.lineTo(x, H); ctx.stroke();
    }
  }

  _drawObstacles(ctx, W, H, nowMs) {
    // Use camera scroll for rendering
    for (const ob of this.obstacles) {
      if (ob.cleared[0] && ob.cleared[1]) continue;
      const sx = (ob.worldX - this.cameraScrollX) * W;
      if (sx < -W * 0.15 || sx > W * 1.15) continue;

      const gy = H * GROUND_Y;
      const oh = ob.height * H;
      const ow = OB_W * W;
      const ox = sx - ow / 2;
      const oy = gy - oh;

      if (ob.type === 'spike') this._drawSpike(ctx, ox, oy, ow, oh);
      else                     this._drawWall(ctx, ox, oy, ow, oh);
    }
  }

  _drawSpike(ctx, ox, oy, ow, oh) {
    const count = 3, sw = ow / count;
    ctx.save();
    for (let i = 0; i < count; i++) {
      const bx = ox + i * sw;
      ctx.fillStyle = i % 2 === 0 ? '#b71c1c' : '#c62828';
      ctx.beginPath();
      ctx.moveTo(bx, oy + oh);
      ctx.lineTo(bx + sw / 2, oy);
      ctx.lineTo(bx + sw, oy + oh);
      ctx.closePath(); ctx.fill();
    }
    ctx.restore();
  }

  _drawWall(ctx, ox, oy, ow, oh) {
    ctx.save();
    ctx.fillStyle = '#8b4513';
    ctx.fillRect(ox, oy, ow, oh);
    const brickH = Math.max(6, oh / 3);
    const brickW = ow * 0.48;
    ctx.strokeStyle = 'rgba(0,0,0,0.4)';
    ctx.lineWidth = 1.5;
    for (let row = 0; row * brickH < oh; row++) {
      const rowY = oy + row * brickH;
      const offX = row % 2 === 0 ? 0 : brickW * 0.5;
      ctx.beginPath(); ctx.moveTo(ox, rowY); ctx.lineTo(ox + ow, rowY); ctx.stroke();
      for (let col = offX; col < ow; col += brickW) {
        ctx.beginPath(); ctx.moveTo(ox + col, rowY); ctx.lineTo(ox + col, rowY + brickH); ctx.stroke();
      }
    }
    ctx.restore();
  }

  _drawSparkles(ctx, W, H) {
    for (const s of this.sparkles) {
      const age = clamp(1 - s.life / 900, 0, 1);
      ctx.save();
      ctx.globalAlpha = 1 - age;
      ctx.fillStyle   = s.color;
      ctx.shadowColor = s.color;
      ctx.shadowBlur  = 6;
      ctx.beginPath();
      ctx.arc(s.x * W, s.y * H, s.size * W, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }
  }

  _drawCheckpoints(ctx, W, H, nowMs) {
    for (let i = this.questionIndex; i < this.checkpoints.length; i++) {
      const cp  = this.checkpoints[i];
      const scX = (cp.worldX - this.cameraScrollX) * W;
      if (scX < -W * 0.1 || scX > W * 1.1) continue;
      const gy = H * GROUND_Y, pH = H * 0.22;
      ctx.strokeStyle = '#9e9e9e'; ctx.lineWidth = W * 0.006;
      ctx.beginPath(); ctx.moveTo(scX, gy); ctx.lineTo(scX, gy - pH); ctx.stroke();
      const wave = Math.sin(nowMs * 0.004 + i) * 0.28;
      ctx.fillStyle = i === this.questionIndex ? this.theme.accent : 'rgba(255,255,255,0.3)';
      ctx.beginPath();
      ctx.moveTo(scX, gy - pH);
      ctx.lineTo(scX + W * 0.055 * (1 + wave * 0.15), gy - pH + H * 0.036);
      ctx.lineTo(scX, gy - pH + H * 0.072);
      ctx.closePath(); ctx.fill();
    }
    const last = this.checkpoints.at(-1);
    if (last) {
      const cx = (last.worldX + 0.18 - this.cameraScrollX) * W;
      if (cx < W * 1.2) this._drawCastle(ctx, cx, H * GROUND_Y, W, H);
    }
  }

  _drawCastle(ctx, cx, gy, W, H) {
    const cw = W * 0.18, ch = H * 0.28, bx = cx - cw / 2, by = gy - ch;
    ctx.fillStyle = '#607d8b'; ctx.fillRect(bx, by, cw, ch);
    ctx.fillStyle = '#546e7a';
    const mw = cw / 5;
    for (let i = 0; i < 3; i++) ctx.fillRect(bx + i * mw * 1.42 + mw * 0.1, by - H * 0.04, mw, H * 0.04);
    const dw = cw * 0.32, dh = ch * 0.4;
    ctx.fillStyle = '#37474f'; roundRect(ctx, cx - dw / 2, gy - dh, dw, dh, dw * 0.5); ctx.fill();
  }

  _drawPlayer(ctx, W, H, nowMs, pi) {
    const p   = this.players[pi];
    const cfg = PLAYER_CONFIGS[pi];
    const isHit = nowMs - p.hitTime < HIT_INVINCIBLE;
    if (isHit && Math.floor(nowMs / 80) % 2 === 0) return;

    // Convert player's own world coords → camera-relative screen coords
    const camDiff = p.scrollX - this.cameraScrollX;
    const screenX = (p.charX + camDiff) * W;
    const screenY = p.charY * H;
    const cw = CHAR_W * W, ch = CHAR_H * H;

    ctx.save();
    ctx.translate(screenX + cw / 2, screenY + ch / 2);
    if (p.facing === -1) ctx.scale(-1, 1);

    const bx = -cw / 2, by = -ch / 2;
    // Body
    ctx.fillStyle = isHit ? '#ff8a80' : cfg.color;
    roundRect(ctx, bx, by, cw, ch * 0.55, cw * 0.25); ctx.fill();
    // Hat
    ctx.fillStyle = cfg.hatColor;
    roundRect(ctx, bx, by - ch * 0.18, cw, ch * 0.2, cw * 0.1); ctx.fill();
    // Pants
    ctx.fillStyle = cfg.pantsColor;
    roundRect(ctx, bx + cw * 0.08, by + ch * 0.32, cw * 0.84, ch * 0.42, cw * 0.12); ctx.fill();
    // Eye
    ctx.fillStyle = '#fff';
    ctx.beginPath(); ctx.arc(cw * 0.18, by + ch * 0.15, cw * 0.14, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#1a1a1a';
    ctx.beginPath(); ctx.arc(cw * 0.22, by + ch * 0.15, cw * 0.07, 0, Math.PI * 2); ctx.fill();

    // Legs
    const lW = cw * 0.28, lH = ch * 0.28, lY = ch / 2 - lH + lH * 0.1;
    ctx.fillStyle = cfg.pantsColor;
    ctx.save(); ctx.translate(-cw * 0.18, lY); ctx.rotate(p.legAngle);
    roundRect(ctx, -lW / 2, 0, lW, lH, lW * 0.3); ctx.fill(); ctx.restore();
    ctx.save(); ctx.translate(cw * 0.18, lY); ctx.rotate(-p.legAngle);
    roundRect(ctx, -lW / 2, 0, lW, lH, lW * 0.3); ctx.fill(); ctx.restore();
    // Shoes
    ctx.fillStyle = cfg.shoeColor;
    const so = p.legAngle * ch * 0.28;
    roundRect(ctx, -cw * 0.38, ch / 2 - lH * 0.3 + so, lW * 0.9, lH * 0.4, 4); ctx.fill();
    roundRect(ctx,  cw * 0.08, ch / 2 - lH * 0.3 - so, lW * 0.9, lH * 0.4, 4); ctx.fill();

    // Player label tag
    ctx.restore(); // back to screen coords
    ctx.save();
    ctx.fillStyle = cfg.nameColor;
    ctx.font = `700 ${cw * 0.55}px system-ui`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'bottom';
    ctx.fillText(cfg.label, screenX + cw / 2, screenY - 2);
    ctx.restore();
  }

  _drawHUD(ctx, W, H, nowMs) {
    ctx.fillStyle = 'rgba(0,0,0,0.5)'; ctx.fillRect(0, 0, W, H * 0.07);

    // P1 score (left)
    ctx.fillStyle = PLAYER_CONFIGS[0].nameColor;
    ctx.font = `700 ${W * 0.022}px system-ui`;
    ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
    ctx.fillText(`P1 ⭐${this.players[0].score}`, W * 0.025, H * 0.035);

    // P2 score (right)
    ctx.fillStyle = PLAYER_CONFIGS[1].nameColor;
    ctx.textAlign = 'right';
    ctx.fillText(`P2 ⭐${this.players[1].score}`, W * 0.975, H * 0.035);

    // Progress dots (center)
    const tot = this.questions.length;
    const dotR = W * 0.010, dotY = H * 0.035, dotSp = dotR * 2.8;
    const startX = W / 2 - (tot - 1) * dotSp / 2;
    for (let i = 0; i < tot; i++) {
      ctx.beginPath(); ctx.arc(startX + i * dotSp, dotY, dotR, 0, Math.PI * 2);
      ctx.fillStyle = i < this.questionIndex ? '#10b981'
        : (i === this.questionIndex && this.state !== 'VICTORY') ? this.theme.accent
        : 'rgba(255,255,255,0.3)';
      ctx.fill();
    }

    // Jump warnings per player
    for (let pi = 0; pi < 2; pi++) {
      const p = this.players[pi];
      const camDiff = p.scrollX - this.cameraScrollX;
      let warn = false;
      for (const ob of this.obstacles) {
        if (ob.cleared[pi]) continue;
        const sx = ob.worldX - p.scrollX;
        const gap = sx - (p.charX + CHAR_W);
        if (gap > 0 && gap < WARN_DIST) { warn = true; break; }
      }
      if (warn) {
        ctx.save();
        ctx.globalAlpha  = 0.85 + 0.15 * Math.sin(nowMs * 0.018);
        ctx.fillStyle    = PLAYER_CONFIGS[pi].nameColor;
        ctx.font         = `900 ${W * 0.019}px system-ui`;
        ctx.textAlign    = pi === 0 ? 'left' : 'right';
        ctx.textBaseline = 'top';
        ctx.fillText(`${PLAYER_CONFIGS[pi].label}: ↑ NHẢY!`, pi === 0 ? W * 0.025 : W * 0.975, H * 0.078);
        ctx.restore();
      }
    }
  }

  _drawControlsHint(ctx, W, H) {
    if (this.state !== 'RACING' && this.state !== 'INTRO') return;
    ctx.fillStyle    = 'rgba(255,255,255,0.35)';
    ctx.font         = `400 ${W * 0.014}px system-ui`;
    ctx.textAlign    = 'center';
    ctx.textBaseline = 'bottom';
    ctx.fillText('P1: WASD + Space + ZXCV  |  P2: Arrows + Enter + 1234', W / 2, H * 0.985);
  }

  _drawIntro(ctx, W, H, nowMs) {
    const progress = clamp((nowMs - this.stateAtMs) / 2800, 0, 1);
    ctx.fillStyle = `rgba(0,0,0,${0.7 * (1 - easeOut(progress))})`;
    ctx.fillRect(0, 0, W, H);
    const a = Math.min(1, progress * 3);
    ctx.fillStyle = `rgba(255,255,255,${a})`; ctx.font = `bold ${W * 0.048}px system-ui`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText('🏃 Cuộc Đua 2 Người! 🏃', W / 2, H * 0.32);
    ctx.font = `${W * 0.02}px system-ui`; ctx.fillStyle = `rgba(255,255,255,${a * 0.85})`;
    ctx.fillText(`P1 (đỏ): WASD + Space nhảy  |  P2 (xanh): Arrows + Enter nhảy`, W / 2, H * 0.46);
    ctx.fillText(`P1 trả lời: Z X C V  |  P2 trả lời: 1 2 3 4`, W / 2, H * 0.53);
    ctx.fillText('Ai đến cờ trước được trả lời câu hỏi cho cả đội. Trả lời đúng trước +2 điểm!', W / 2, H * 0.62);
    ctx.fillStyle = `rgba(${PLAYER_CONFIGS[0].nameColor.slice(1).match(/.{2}/g).map(h => parseInt(h,16)).join(',')},${a * 0.9})`;
    ctx.fillText('P1: Đỏ →', W / 2 - W * 0.18, H * 0.72);
    ctx.fillStyle = `rgba(${PLAYER_CONFIGS[1].nameColor.slice(1).match(/.{2}/g).map(h => parseInt(h,16)).join(',')},${a * 0.9})`;
    ctx.fillText('P2: Xanh →', W / 2 + W * 0.05, H * 0.72);
  }

  _drawQuestion(ctx, W, H, nowMs) {
    const q = this.questions[this.questionIndex];
    if (!q) return;
    this._drawQuestionCard(ctx, W, H, q, nowMs, false);
  }

  _drawFeedback(ctx, W, H) {
    const q = this.questions[this.questionIndex] ?? this.questions[this.questionIndex - 1];
    if (!q) return;
    this._drawQuestionCard(ctx, W, H, q, null, true);
  }

  _drawQuestionCard(ctx, W, H, q, nowMs, isFeedback) {
    ctx.fillStyle = 'rgba(0,0,0,0.60)';
    ctx.fillRect(0, 0, W, H);

    const cW = W * 0.82, cH = H * 0.76, cX = (W - cW) / 2, cY = (H - cH) / 2;
    ctx.fillStyle = '#1e1b4b'; roundRect(ctx, cX, cY, cW, cH, 20); ctx.fill();
    ctx.strokeStyle = 'rgba(139,92,246,0.7)'; ctx.lineWidth = 2.5;
    roundRect(ctx, cX, cY, cW, cH, 20); ctx.stroke();

    // Prompt
    ctx.fillStyle = '#e2e8f0';
    ctx.font = `600 ${W * 0.026}px system-ui`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    const lines = this._wrapText(ctx, q.prompt, cW * 0.84), lineH = W * 0.033;
    const ptY = cY + cH * 0.12;
    for (let i = 0; i < Math.min(lines.length, 3); i++) ctx.fillText(lines[i], W / 2, ptY + i * lineH);

    // Choice grid
    const cols = 2, choW = cW * 0.44, choH = cH * 0.14, gX = cW * 0.04, gY = cH * 0.03;
    const sX = cX + (cW - cols * choW - (cols - 1) * gX) / 2;
    const sY = cY + cH * 0.30;
    const labels = ['1', '2', '3', '4'];

    q.choices.forEach((c, idx) => {
      const col = idx % cols, row = Math.floor(idx / cols);
      const cx = sX + col * (choW + gX), cy = sY + row * (choH + gY);
      const correctId = q.correctChoiceId;
      const p1sel = this.questionP1Selected, p2sel = this.questionP2Selected;

      let bg = 'rgba(255,255,255,0.08)', border = 'rgba(255,255,255,0.25)';
      if (isFeedback) {
        if (c.id === correctId) { bg = 'rgba(16,185,129,0.30)'; border = '#10b981'; }
        if (p1sel === c.id && c.id !== correctId) { bg = 'rgba(239,68,68,0.30)'; border = '#ef4444'; }
        if (p2sel === c.id && c.id !== correctId) { bg = 'rgba(239,68,68,0.30)'; border = '#ef4444'; }
      } else {
        if (p1sel === c.id || p2sel === c.id) { bg = 'rgba(139,92,246,0.25)'; border = '#8b5cf6'; }
      }

      ctx.fillStyle = bg; roundRect(ctx, cx, cy, choW, choH, 12); ctx.fill();
      ctx.strokeStyle = border; ctx.lineWidth = 1.5; roundRect(ctx, cx, cy, choW, choH, 12); ctx.stroke();

      const lS = choH * 0.52;
      ctx.fillStyle = 'rgba(139,92,246,0.8)'; roundRect(ctx, cx + 8, cy + 8, lS, lS, 6); ctx.fill();
      ctx.fillStyle = '#fff'; ctx.font = `700 ${lS * 0.52}px system-ui`;
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(labels[idx], cx + 8 + lS / 2, cy + 8 + lS / 2);
      ctx.fillStyle = '#e2e8f0'; ctx.font = `500 ${W * 0.019}px system-ui`;
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(c.text, cx + lS + (choW - lS) / 2 + 4, cy + choH / 2);
    });

    // Per-player answer status
    const p1row = { answered: this.players[0].answered, correct: this.players[0].answeredCorrect };
    const p2row = { answered: this.players[1].answered, correct: this.players[1].answeredCorrect };

    const statusY = sY + 2 * (choH + gY) + gY;
    const renderPlayerStatus = (row, label, color, x) => {
      ctx.fillStyle = color; ctx.font = `600 ${W * 0.018}px system-ui`;
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      const txt = !row.answered ? `${label}: chờ...` : row.correct ? `${label}: ✓ Đúng!` : `${label}: ✗ Sai`;
      ctx.fillText(txt, x, statusY);
    };
    renderPlayerStatus(p1row, 'P1', PLAYER_CONFIGS[0].nameColor, W / 2 - cW * 0.22);
    renderPlayerStatus(p2row, 'P2', PLAYER_CONFIGS[1].nameColor, W / 2 + cW * 0.22);

    // Bottom bar
    if (isFeedback) {
      const msg = this.firstCorrectPlayer === 0 ? '🏆 P1 trả lời đúng trước! (+2 điểm)'
        : this.firstCorrectPlayer === 1 ? '🏆 P2 trả lời đúng trước! (+2 điểm)'
        : '⏱ Hết thời gian!';
      const cfg = this.firstCorrectPlayer >= 0 ? PLAYER_CONFIGS[this.firstCorrectPlayer] : null;
      ctx.fillStyle = cfg ? cfg.nameColor : '#fbbf24';
      roundRect(ctx, cX, cY + cH - 52, cW, 52, 16); ctx.fillStyle = 'rgba(0,0,0,0.4)';
      roundRect(ctx, cX, cY + cH - 52, cW, 52, 16); ctx.fill();
      ctx.fillStyle = cfg ? cfg.nameColor : '#fbbf24';
      ctx.font = `700 ${W * 0.022}px system-ui`;
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(msg, W / 2, cY + cH - 26);
    } else {
      ctx.fillStyle = 'rgba(255,255,255,0.35)'; ctx.font = `${W * 0.016}px system-ui`;
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText('Bạn vẫn có thể di chuyển! Hãy trả lời bằng phím của mình.', W / 2, cY + cH - 26);
    }
  }

  _drawVictory(ctx, W, H, nowMs) {
    const elapsed = nowMs - this.stateAtMs, alpha = clamp(elapsed / 500, 0, 1);
    ctx.fillStyle = `rgba(0,0,0,${0.5 * alpha})`; ctx.fillRect(0, 0, W, H);
    for (const pt of this.particles) {
      ctx.save(); ctx.translate(pt.x * W, pt.y * H); ctx.rotate(pt.rot);
      const s = pt.size * W; ctx.fillStyle = pt.color; ctx.fillRect(-s / 2, -s / 2, s, s * 0.6); ctx.restore();
    }

    const t = easeOut(clamp(elapsed / 600, 0, 1));
    const vW = W * 0.72, vH = H * 0.62, vX = (W - vW) / 2;
    const vY = lerp(H, (H - vH) / 2, t);

    ctx.fillStyle = '#1e1b4b'; roundRect(ctx, vX, vY, vW, vH, 24); ctx.fill();
    ctx.strokeStyle = '#f59e0b'; ctx.lineWidth = 3; roundRect(ctx, vX, vY, vW, vH, 24); ctx.stroke();

    ctx.fillStyle = '#f59e0b'; ctx.font = `bold ${W * 0.046}px system-ui`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText('🎉 Kết quả cuộc đua! 🎉', W / 2, vY + vH * 0.14);

    // Scores
    const p1 = this.players[0], p2 = this.players[1];
    const p1pct = this.questions.length > 0 ? Math.round(p1.score / (this.questions.length * 2) * 100) : 0;
    const p2pct = this.questions.length > 0 ? Math.round(p2.score / (this.questions.length * 2) * 100) : 0;
    const maxScore = this.questions.length * 2;

    const drawScore = (x, pi) => {
      const pp  = this.players[pi];
      const cfg = PLAYER_CONFIGS[pi];
      ctx.fillStyle = cfg.nameColor; ctx.font = `700 ${W * 0.028}px system-ui`;
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(cfg.label, x, vY + vH * 0.30);
      ctx.fillStyle = '#e2e8f0'; ctx.font = `700 ${W * 0.054}px system-ui`;
      ctx.fillText(`${pp.score}`, x, vY + vH * 0.46);
      ctx.fillStyle = '#a5b4fc'; ctx.font = `${W * 0.022}px system-ui`;
      ctx.fillText(`/ ${maxScore} điểm`, x, vY + vH * 0.59);
    };
    drawScore(vX + vW * 0.27, 0);
    drawScore(vX + vW * 0.73, 1);

    // Divider
    ctx.strokeStyle = 'rgba(255,255,255,0.2)'; ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.moveTo(W / 2, vY + vH * 0.22); ctx.lineTo(W / 2, vY + vH * 0.72); ctx.stroke();

    // Winner
    const winner = p1.score > p2.score ? 'P1 chiến thắng! 🏆'
      : p2.score > p1.score ? 'P2 chiến thắng! 🏆'
      : 'Hòa nhau! 🤝';
    const wColor = p1.score > p2.score ? PLAYER_CONFIGS[0].nameColor
      : p2.score > p1.score ? PLAYER_CONFIGS[1].nameColor
      : '#fbbf24';
    ctx.fillStyle = wColor; ctx.font = `700 ${W * 0.032}px system-ui`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(winner, W / 2, vY + vH * 0.85);
  }

  // ── Util ──────────────────────────────────────────────────────────────────
  _wrapText(ctx, text, maxW) {
    const words = String(text || '').split(/\s+/); const lines = []; let line = '';
    for (const w of words) {
      const test = line ? `${line} ${w}` : w;
      if (ctx.measureText(test).width > maxW && line) { lines.push(line); line = w; } else line = test;
    }
    if (line) lines.push(line);
    return lines;
  }
}
