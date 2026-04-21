/**
 * RunnerQuizGame — Mario-style side-scrolling quiz blueprint.
 *
 * v2 changes vs v1:
 *  - Fixed physics (GRAVITY & JUMP_POWER expressed in normalized-units/ms)
 *  - Added obstacles (spikes + walls) that REQUIRE jumping over
 *  - "↑ NHẢY!" warning when obstacle is approaching
 *  - Hit flash + scroll-pushback on collision
 *  - Green sparkle when clearing an obstacle successfully
 *
 * Controls: ← → move  |  Space / ↑ jump  |  1 2 3 4 answer choices
 *
 * State machine:
 *   INTRO → RUNNING → QUESTION → FEEDBACK → RUNNING → … → VICTORY
 */

// ── Physics & layout ────────────────────────────────────────────────────────
const GRAVITY        = 0.0000033;  // normalized units / ms²  (300ms to peak, ~0.15 canvas height)
const JUMP_POWER     = -0.001;     // normalized units / ms
const GROUND_Y       = 0.80;
const CHAR_W         = 0.052;
const CHAR_H         = 0.072;
const MOVE_SPEED     = 0.00038;    // per ms
const SCROLL_SPEED   = 0.00022;    // world scroll per ms

const SPIKE_H        = 0.055;      // spike cluster height (normalized)
const WALL_H         = 0.092;      // brick wall height
const OB_W           = 0.030;      // obstacle width
const HIT_PUSHBACK   = 0.09;       // scroll units pushed back on collision
const HIT_INVINCIBLE = 380;        // ms invincibility after a hit
const WARN_DIST      = 0.22;       // screen units ahead to show JUMP warning

// ── Theme palettes ───────────────────────────────────────────────────────────
const THEME_PALETTES = {
  castle: { skyTop:'#1a0a2e', skyBot:'#2d1b69', ground:'#5d4037', groundTop:'#8d6e63', cloud:'rgba(255,255,255,0.18)', accent:'#f59e0b' },
  forest: { skyTop:'#0f4c2a', skyBot:'#1b7340', ground:'#3e2723', groundTop:'#558b2f', cloud:'rgba(255,255,255,0.14)', accent:'#66bb6a' },
  sky:    { skyTop:'#0077cc', skyBot:'#29b6f6', ground:'#795548', groundTop:'#a5d6a7', cloud:'rgba(255,255,255,0.55)', accent:'#ffffff' },
};

// ── Helpers ──────────────────────────────────────────────────────────────────
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
function lerp(a, b, t){ return a + (b - a) * t; }
function clamp(v, lo, hi){ return Math.max(lo, Math.min(hi, v)); }
function easeOut(t){ return 1 - (1 - t) * (1 - t); }

// ── RunnerQuizGame ────────────────────────────────────────────────────────────
export class RunnerQuizGame {
  constructor({ playable, settings, canvas, keyboard }) {
    this.playable   = playable;
    this.settings   = settings;
    this.canvas     = canvas;
    this.kb         = keyboard;

    this.questions     = playable.questions ?? [];
    this.theme         = THEME_PALETTES[playable.theme ?? 'castle'];
    this.questionIndex = 0;
    this.score         = 0;
    this.wrongCount    = 0;

    // State: 'INTRO' | 'RUNNING' | 'QUESTION' | 'FEEDBACK' | 'VICTORY'
    this.state     = 'INTRO';
    this.stateAtMs = performance.now();

    // Character
    this.charX    = 0.12;
    this.charY    = GROUND_Y - CHAR_H;
    this.velY     = 0;
    this.onGround = true;
    this.facing   = 1;

    // World
    this.scrollX  = 0;
    this.bgOffset = 0;

    // Checkpoints (one per question)
    this.checkpoints = this.questions.map((q, i) => ({
      id:        q.id,
      worldX:    0.55 + i * 0.55,
      triggered: false,
    }));

    // Obstacles: generated between start and each checkpoint
    this.obstacles = this._generateObstacles();

    // Sparkles emitted on successful obstacle clear
    this.sparkles  = [];
    this.particles = [];  // confetti

    // Hit feedback
    this._hitTime   = -9999;
    this._jumpWarn  = false;

    // Animation
    this.legAngle = 0;

    // Answer feedback
    this.feedbackCorrect  = null;
    this.selectedChoiceId = null;

    this.completedAtMs = null;
  }

  isComplete()       { return this.completedAtMs != null; }
  getCompletedAtMs() { return this.completedAtMs; }
  getResult() {
    return { correct: this.score, total: this.questions.length };
  }

  // ── Obstacle generation ────────────────────────────────────────────────────
  _generateObstacles() {
    const segments = [];
    const cpXs   = this.checkpoints.map(c => c.worldX);
    const margin = 0.08;

    if (cpXs.length > 0) {
      segments.push({ from: 0.16, to: cpXs[0] - margin });
    }
    for (let i = 0; i < cpXs.length - 1; i++) {
      segments.push({ from: cpXs[i] + margin, to: cpXs[i + 1] - margin });
    }

    const obs = [];
    for (const seg of segments) {
      const length = seg.to - seg.from;
      if (length < 0.12) continue;
      const count = 2;
      for (let i = 0; i < count; i++) {
        const frac   = (i + 1) / (count + 1);
        const worldX = seg.from + frac * length;
        const type   = i % 2 === 0 ? 'spike' : 'wall';
        obs.push({
          worldX,
          type,
          height:  type === 'spike' ? SPIKE_H : WALL_H,
          cleared: false,
        });
      }
    }
    return obs;
  }

  // ── Update ─────────────────────────────────────────────────────────────────
  update({ nowMs }) {
    const dt = Math.min(40, nowMs - (this._lastMs ?? nowMs));
    this._lastMs = nowMs;

    switch (this.state) {
      case 'INTRO':    this._updateIntro(nowMs);              break;
      case 'RUNNING':  this._updateRunning(dt, nowMs);        break;
      case 'QUESTION': this._updateQuestion(nowMs);           break;
      case 'FEEDBACK': this._updateFeedback(nowMs);           break;
      case 'VICTORY':  this._updateVictory(dt, nowMs);        break;
    }

    // Sparkle physics
    for (const s of this.sparkles) {
      s.x  += s.vx * dt;
      s.y  += s.vy * dt;
      s.vy += 0.000005 * dt;
      s.life -= dt;
    }
    this.sparkles = this.sparkles.filter(s => s.life > 0);

    this.kb.resetFrame();
  }

  _updateIntro(nowMs) {
    if (nowMs - this.stateAtMs >= 2400) this._setState('RUNNING', nowMs);
  }

  _updateRunning(dt, nowMs) {
    const movRight = this.kb.isPressed('right');
    const movLeft  = this.kb.isPressed('left');

    if (movRight) {
      this.charX    = Math.min(0.34, this.charX + MOVE_SPEED * dt);
      this.scrollX += SCROLL_SPEED * dt;
      this.bgOffset += SCROLL_SPEED * dt * 0.4;
      this.facing   = 1;
    } else if (movLeft) {
      this.charX    = Math.max(0.06, this.charX - MOVE_SPEED * dt);
      this.scrollX  = Math.max(0, this.scrollX - SCROLL_SPEED * dt * 0.5);
      this.facing   = -1;
    }

    if ((this.kb.justPressed('jump') || this.kb.justPressed('up')) && this.onGround) {
      this.velY     = JUMP_POWER;
      this.onGround = false;
    }

    this.velY  += GRAVITY * dt;
    this.charY += this.velY * dt;
    if (this.charY >= GROUND_Y - CHAR_H) {
      this.charY    = GROUND_Y - CHAR_H;
      this.velY     = 0;
      this.onGround = true;
    }

    if ((movRight || movLeft) && this.onGround) {
      this.legAngle = Math.sin(nowMs * 0.012) * 0.45;
    } else {
      this.legAngle = 0;
    }

    // ── Obstacle logic ─────────────────────────────────────────────────────
    const invincible = nowMs - this._hitTime < HIT_INVINCIBLE;
    this._jumpWarn   = false;

    for (const ob of this.obstacles) {
      const sx = ob.worldX - this.scrollX;
      if (sx < -0.15 || sx > 1.15) continue;

      // Approaching warning
      const gap = sx - (this.charX + CHAR_W);
      if (!ob.cleared && gap > 0 && gap < WARN_DIST) this._jumpWarn = true;

      // Clear detection: character's right edge passed obstacle's right edge
      if (!ob.cleared && this.charX > sx + OB_W / 2 + 0.01) {
        ob.cleared = true;
        this._spawnSparkle(sx + OB_W / 2, GROUND_Y - ob.height);
      }

      // Collision
      if (!invincible && !ob.cleared) {
        const hitX = this.charX < sx + OB_W / 2 && this.charX + CHAR_W > sx - OB_W / 2;
        const hitY = this.charY + CHAR_H > GROUND_Y - ob.height;
        if (hitX && hitY) {
          this.scrollX  = Math.max(0, this.scrollX - HIT_PUSHBACK);
          this._hitTime = nowMs;
          if (this.onGround) {
            this.velY     = JUMP_POWER * 0.35;
            this.onGround = false;
          }
          // Restore cleared state for obstacles that scrolled back into play
          for (const o of this.obstacles) {
            if (o.cleared && (o.worldX - this.scrollX) > this.charX - 0.04) {
              o.cleared = false;
            }
          }
        }
      }
    }

    // ── Checkpoint trigger ─────────────────────────────────────────────────
    const cp = this.checkpoints[this.questionIndex];
    if (cp && !cp.triggered) {
      const cpSx = cp.worldX - this.scrollX;
      if (cpSx - this.charX < 0.07 && cpSx - this.charX > -0.05) {
        cp.triggered = true;
        this._setState('QUESTION', nowMs);
      }
    }

    if (this.questionIndex >= this.questions.length) {
      this._setState('VICTORY', nowMs);
      this._spawnConfetti();
    }
  }

  _updateQuestion(nowMs) {
    const currentQuestion = this.questions[this.questionIndex];
    if (!currentQuestion) {
      this.questionIndex++;
      this.selectedChoiceId = null;
      this.feedbackCorrect = null;
      this.wrongCount = 0;
      if (this.questionIndex >= this.questions.length) {
        this._setState('VICTORY', nowMs);
        this._spawnConfetti();
      } else {
        this._setState('RUNNING', nowMs);
      }
      return;
    }

    const KEYS = ['ans1', 'ans2', 'ans3', 'ans4'];
    for (let i = 0; i < KEYS.length; i++) {
      if (this.kb.justPressed(KEYS[i])) {
        const choice = currentQuestion.choices[i];
        if (!choice) break;
        this.selectedChoiceId = choice.id;
        this.feedbackCorrect  = choice.id === currentQuestion.correctChoiceId;
        if (this.feedbackCorrect) this.score++;
        else this.wrongCount++;
        this._setState('FEEDBACK', nowMs);
        break;
      }
    }
  }

  _updateFeedback(nowMs) {
    const delay = this.feedbackCorrect ? 1200 : 900;
    if (nowMs - this.stateAtMs < delay) return;

    if (this.feedbackCorrect || this.wrongCount >= 3) {
      this.questionIndex++;
      this.wrongCount = 0;
    }
    this.selectedChoiceId = null;
    this.feedbackCorrect  = null;

    if (this.questionIndex >= this.questions.length) {
      this._setState('VICTORY', nowMs);
      this._spawnConfetti();
    } else {
      this._setState('RUNNING', nowMs);
    }
  }

  _updateVictory(dt, nowMs) {
    for (const p of this.particles) {
      p.x  += p.vx * dt;
      p.y  += p.vy * dt;
      p.vy += 0.0005 * dt;
      p.rot  += p.rotV * dt;
      p.life -= dt;
    }
    this.particles = this.particles.filter(p => p.life > 0);
    if (nowMs - this.stateAtMs >= 3500 && this.completedAtMs == null) {
      this.completedAtMs = nowMs;
    }
  }

  _setState(s, nowMs) { this.state = s; this.stateAtMs = nowMs; }

  _spawnSparkle(screenX, screenY) {
    const colors = ['#10b981','#34d399','#6ee7b7','#fbbf24','#ffffff'];
    for (let i = 0; i < 10; i++) {
      const angle = (Math.PI * 2 * i) / 10 + Math.random() * 0.5;
      const speed = 0.00018 + Math.random() * 0.00025;
      this.sparkles.push({
        x: screenX, y: screenY,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed - 0.0003,
        size: 0.006 + Math.random() * 0.007,
        color: colors[Math.floor(Math.random() * colors.length)],
        life: 500 + Math.random() * 400,
      });
    }
  }

  _spawnConfetti() {
    const colors = ['#f59e0b','#ef4444','#3b82f6','#10b981','#8b5cf6','#ec4899','#fff'];
    for (let i = 0; i < 80; i++) {
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

  // ── Render ─────────────────────────────────────────────────────────────────
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
    this._drawCharacter(ctx, W, H, nowMs);
    if (this.state === 'INTRO')    this._drawIntro(ctx, W, H, nowMs);
    if (this.state === 'QUESTION') this._drawQuestion(ctx, W, H);
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
    ctx.arc(cx + r*0.8, cy - r*0.2, r*0.7, 0, Math.PI * 2);
    ctx.arc(cx - r*0.7, cy + r*0.1, r*0.6, 0, Math.PI * 2);
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
    ctx.lineWidth   = 1;
    const tileW  = W * 0.08;
    const tileOff = (this.scrollX * W * 1.4) % tileW;
    for (let x = -tileW + tileOff; x < W + tileW; x += tileW) {
      ctx.beginPath(); ctx.moveTo(x, gy); ctx.lineTo(x, H); ctx.stroke();
    }
  }

  // ── Obstacles ─────────────────────────────────────────────────────────────
  _drawObstacles(ctx, W, H, nowMs) {
    for (const ob of this.obstacles) {
      if (ob.cleared) continue;
      const sx = (ob.worldX - this.scrollX) * W;
      if (sx < -W*0.15 || sx > W*1.15) continue;

      const gy = H * GROUND_Y;
      const oh = ob.height * H;
      const ow = OB_W * W;
      const ox = sx - ow / 2;
      const oy = gy - oh;

      if (ob.type === 'spike') this._drawSpike(ctx, ox, oy, ow, oh);
      else                     this._drawWall(ctx, ox, oy, ow, oh);

      // JUMP warning label
      const gap = sx - (this.charX + CHAR_W) * W;
      if (gap > 0 && gap < WARN_DIST * W) {
        const fade  = clamp(1 - gap / (WARN_DIST * W), 0, 1);
        const pulse = 0.80 + 0.20 * Math.sin(nowMs * 0.018);
        ctx.save();
        ctx.globalAlpha  = fade * pulse;
        ctx.fillStyle    = '#fbbf24';
        ctx.font         = `900 ${W * 0.022}px system-ui`;
        ctx.textAlign    = 'center';
        ctx.textBaseline = 'middle';
        ctx.shadowColor  = '#f59e0b';
        ctx.shadowBlur   = 8;
        ctx.fillText('↑ NHẢY!', sx, oy - H * 0.045);
        ctx.restore();
      }
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
      ctx.closePath();
      ctx.fill();
      ctx.fillStyle = 'rgba(255,255,255,0.22)';
      ctx.beginPath();
      ctx.moveTo(bx + sw*0.22, oy + oh*0.58);
      ctx.lineTo(bx + sw*0.50, oy + oh*0.08);
      ctx.lineTo(bx + sw*0.36, oy + oh*0.58);
      ctx.closePath();
      ctx.fill();
    }
    const grd = ctx.createLinearGradient(ox, oy+oh-4, ox, oy+oh+3);
    grd.addColorStop(0, 'rgba(183,28,28,0.8)'); grd.addColorStop(1, 'rgba(183,28,28,0)');
    ctx.fillStyle = grd; ctx.fillRect(ox, oy+oh-6, ow, 6);
    ctx.restore();
  }

  _drawWall(ctx, ox, oy, ow, oh) {
    ctx.save();
    ctx.fillStyle = '#8b4513';
    ctx.fillRect(ox, oy, ow, oh);
    const brickH = Math.max(6, oh / 3);
    const brickW = ow * 0.48;
    ctx.strokeStyle = 'rgba(0,0,0,0.4)';
    ctx.lineWidth   = 1.5;
    for (let row = 0; row * brickH < oh; row++) {
      const rowY = oy + row * brickH;
      const offX = row % 2 === 0 ? 0 : brickW * 0.5;
      ctx.beginPath(); ctx.moveTo(ox, rowY); ctx.lineTo(ox+ow, rowY); ctx.stroke();
      for (let col = offX; col < ow; col += brickW) {
        ctx.beginPath(); ctx.moveTo(ox+col, rowY); ctx.lineTo(ox+col, rowY+brickH); ctx.stroke();
      }
    }
    const hl = ctx.createLinearGradient(ox, 0, ox+ow*0.3, 0);
    hl.addColorStop(0, 'rgba(255,255,255,0.15)'); hl.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = hl; ctx.fillRect(ox, oy, ow*0.3, oh);
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

  // ── Checkpoints & castle ──────────────────────────────────────────────────
  _drawCheckpoints(ctx, W, H, nowMs) {
    for (let i = this.questionIndex; i < this.checkpoints.length; i++) {
      const cp  = this.checkpoints[i];
      const scX = (cp.worldX - this.scrollX) * W;
      if (scX < -W*0.1 || scX > W*1.1) continue;
      const gy = H * GROUND_Y, pH = H * 0.22;
      ctx.strokeStyle = '#9e9e9e'; ctx.lineWidth = W * 0.006;
      ctx.beginPath(); ctx.moveTo(scX, gy); ctx.lineTo(scX, gy-pH); ctx.stroke();
      const wave = Math.sin(nowMs * 0.004 + i) * 0.28;
      ctx.fillStyle = i === this.questionIndex ? this.theme.accent : 'rgba(255,255,255,0.3)';
      ctx.beginPath();
      ctx.moveTo(scX, gy-pH);
      ctx.lineTo(scX + W*0.055*(1+wave*0.15), gy-pH + H*0.036);
      ctx.lineTo(scX, gy-pH + H*0.072);
      ctx.closePath(); ctx.fill();
      ctx.fillStyle = 'rgba(0,0,0,0.55)';
      ctx.font = `bold ${W*0.024}px system-ui`; ctx.textAlign='center'; ctx.textBaseline='middle';
      ctx.fillText('?', scX + W*0.024, gy-pH + H*0.038);
    }
    const last = this.checkpoints.at(-1);
    if (last) {
      const cx = (last.worldX + 0.18 - this.scrollX) * W;
      if (cx < W * 1.2) this._drawCastle(ctx, cx, H * GROUND_Y, W, H);
    }
  }

  _drawCastle(ctx, cx, gy, W, H) {
    const cw=W*0.18, ch=H*0.28, bx=cx-cw/2, by=gy-ch;
    ctx.fillStyle='#607d8b'; ctx.fillRect(bx,by,cw,ch);
    ctx.fillStyle='#546e7a';
    const mw=cw/5;
    for (let i=0;i<3;i++) ctx.fillRect(bx+i*mw*1.42+mw*0.1, by-H*0.04, mw, H*0.04);
    const dw=cw*0.32, dh=ch*0.4;
    ctx.fillStyle='#37474f'; roundRect(ctx,cx-dw/2,gy-dh,dw,dh,dw*0.5); ctx.fill();
    ctx.fillStyle='#fff9c4'; ctx.beginPath();
    ctx.arc(cx-cw*0.25,by+ch*0.25,W*0.018,0,Math.PI*2);
    ctx.arc(cx+cw*0.25,by+ch*0.25,W*0.018,0,Math.PI*2); ctx.fill();
    if (this.questionIndex >= this.questions.length) {
      this._drawPrincess(ctx,cx,gy-ch*0.7-H*0.05,W,H);
    }
  }

  _drawPrincess(ctx, cx, cy, W, H) {
    const r=W*0.025;
    ctx.fillStyle='#f59e0b';
    ctx.beginPath();
    ctx.moveTo(cx-r*0.8,cy-r*1.4); ctx.lineTo(cx-r*0.8,cy-r*2);
    ctx.lineTo(cx,cy-r*2.5); ctx.lineTo(cx+r*0.8,cy-r*2); ctx.lineTo(cx+r*0.8,cy-r*1.4);
    ctx.closePath(); ctx.fill();
    ctx.fillStyle='#ffccbc'; ctx.beginPath(); ctx.arc(cx,cy-r*1.5,r,0,Math.PI*2); ctx.fill();
    ctx.fillStyle='#e91e8c';
    ctx.beginPath(); ctx.moveTo(cx,cy-r*0.8);
    ctx.lineTo(cx-r*1.6,cy+r*1.8); ctx.lineTo(cx+r*1.6,cy+r*1.8);
    ctx.closePath(); ctx.fill();
    const wt=Math.sin(performance.now()*0.005)*0.4;
    ctx.strokeStyle='#ffccbc'; ctx.lineWidth=r*0.4;
    ctx.beginPath(); ctx.moveTo(cx,cy-r*0.5);
    ctx.quadraticCurveTo(cx+r*1.6,cy-r*0.5+wt*r,cx+r*1.8,cy-r*1.2+wt*r*2); ctx.stroke();
    ctx.fillStyle='#ff6090'; ctx.font=`${r*1.4}px serif`;
    ctx.textAlign='center'; ctx.textBaseline='middle';
    ctx.fillText('♥',cx+r*2.6,cy-r*1.5+Math.sin(performance.now()*0.003)*r*0.4);
  }

  // ── Character ─────────────────────────────────────────────────────────────
  _drawCharacter(ctx, W, H, nowMs) {
    const isHit = nowMs - this._hitTime < HIT_INVINCIBLE;
    if (isHit && Math.floor(nowMs / 80) % 2 === 0) return; // flicker

    const cx=this.charX*W, cy=this.charY*H, cw=CHAR_W*W, ch=CHAR_H*H;
    ctx.save();
    ctx.translate(cx + cw/2, cy + ch/2);
    if (this.facing === -1) ctx.scale(-1, 1);

    const bx=-cw/2, by=-ch/2;
    ctx.fillStyle = isHit ? '#ff6b6b' : '#e53935';
    roundRect(ctx,bx,by,cw,ch*0.55,cw*0.25); ctx.fill();
    ctx.fillStyle = isHit ? '#d32f2f' : '#c62828';
    roundRect(ctx,bx,by-ch*0.18,cw,ch*0.2,cw*0.1); ctx.fill();
    ctx.fillStyle='#1565c0';
    roundRect(ctx,bx+cw*0.08,by+ch*0.32,cw*0.84,ch*0.42,cw*0.12); ctx.fill();
    ctx.fillStyle='#fff'; ctx.beginPath(); ctx.arc(cw*0.18,by+ch*0.15,cw*0.14,0,Math.PI*2); ctx.fill();
    ctx.fillStyle='#1a1a1a'; ctx.beginPath(); ctx.arc(cw*0.22,by+ch*0.15,cw*0.07,0,Math.PI*2); ctx.fill();
    ctx.fillStyle='#5d4037'; ctx.beginPath();
    ctx.ellipse(cw*0.1,by+ch*0.35,cw*0.22,ch*0.07,-0.3,0,Math.PI); ctx.fill();

    const lW=cw*0.28,lH=ch*0.28,lY=ch/2-lH+lH*0.1;
    ctx.fillStyle='#1565c0';
    ctx.save(); ctx.translate(-cw*0.18,lY); ctx.rotate(this.legAngle);
    roundRect(ctx,-lW/2,0,lW,lH,lW*0.3); ctx.fill(); ctx.restore();
    ctx.save(); ctx.translate(cw*0.18,lY); ctx.rotate(-this.legAngle);
    roundRect(ctx,-lW/2,0,lW,lH,lW*0.3); ctx.fill(); ctx.restore();
    ctx.fillStyle='#4e342e';
    const so=this.legAngle*ch*0.28;
    roundRect(ctx,-cw*0.38,ch/2-lH*0.3+so,lW*0.9,lH*0.4,4); ctx.fill();
    roundRect(ctx, cw*0.08,ch/2-lH*0.3-so,lW*0.9,lH*0.4,4); ctx.fill();

    if (!this.onGround) {
      ctx.fillStyle='rgba(255,235,59,0.9)';
      ctx.font=`900 ${cw*0.6}px system-ui`; ctx.textAlign='center'; ctx.textBaseline='bottom';
      ctx.fillText('↑', 0, by - 4);
    }
    ctx.restore();
  }

  // ── HUD ───────────────────────────────────────────────────────────────────
  _drawHUD(ctx, W, H, nowMs) {
    ctx.fillStyle='rgba(0,0,0,0.45)'; ctx.fillRect(0,0,W,H*0.065);
    ctx.fillStyle='#fff'; ctx.font=`600 ${W*0.022}px system-ui`;
    ctx.textAlign='left'; ctx.textBaseline='middle';
    ctx.fillText(`⭐ ${this.score} / ${this.questions.length}`, W*0.025, H*0.032);
    ctx.textAlign='right';
    ctx.fillText(this.playable.characterName ?? 'Runner Quiz', W*0.975, H*0.032);

    const tot=this.questions.length, dotR=W*0.011, dotY=H*0.032, dotSp=dotR*2.8;
    const startX=W/2-(tot-1)*dotSp/2;
    for (let i=0;i<tot;i++) {
      ctx.beginPath(); ctx.arc(startX+i*dotSp,dotY,dotR,0,Math.PI*2);
      ctx.fillStyle = i<this.questionIndex ? '#10b981'
        : (i===this.questionIndex&&this.state!=='VICTORY') ? this.theme.accent
        : 'rgba(255,255,255,0.3)';
      ctx.fill();
    }

    // Red vignette on hit
    const hitAge = nowMs - this._hitTime;
    if (hitAge < 300) {
      const a = (1 - hitAge/300) * 0.35;
      const vg = ctx.createRadialGradient(W/2,H/2,H*0.1,W/2,H/2,H*0.75);
      vg.addColorStop(0,`rgba(239,68,68,0)`); vg.addColorStop(1,`rgba(239,68,68,${a})`);
      ctx.fillStyle=vg; ctx.fillRect(0,0,W,H);
    }
  }

  _drawControlsHint(ctx, W, H) {
    if (this.state !== 'RUNNING' && this.state !== 'INTRO') return;
    const warn = this._jumpWarn;
    ctx.fillStyle    = warn ? '#fbbf24' : 'rgba(255,255,255,0.45)';
    ctx.font         = `${warn ? 600 : 400} ${W*0.017}px system-ui`;
    ctx.textAlign    = 'center';
    ctx.textBaseline = 'bottom';
    ctx.fillText(
      warn ? '↑  NHẢY QUA CHƯỚNG NGẠI VẬT!'
           : '← → Di chuyển   Space / ↑ Nhảy   1-4 Trả lời',
      W/2, H*0.985
    );
  }

  // ── Intro ─────────────────────────────────────────────────────────────────
  _drawIntro(ctx, W, H, nowMs) {
    const progress = clamp((nowMs-this.stateAtMs)/2400, 0, 1);
    ctx.fillStyle=`rgba(0,0,0,${0.7*(1-easeOut(progress))})`; ctx.fillRect(0,0,W,H);
    const a=Math.min(1,progress*3);
    ctx.fillStyle=`rgba(255,255,255,${a})`; ctx.font=`bold ${W*0.05}px system-ui`;
    ctx.textAlign='center'; ctx.textBaseline='middle';
    ctx.fillText('Giải cứu Công chúa! 🏰', W/2, H*0.35);
    ctx.font=`${W*0.022}px system-ui`; ctx.fillStyle=`rgba(255,255,255,${a*0.8})`;
    ctx.fillText('← → di chuyển  |  Space / ↑ nhảy', W/2, H*0.47);
    ctx.fillText('Nhảy qua ▲ chướng ngại vật để tiến về phía trước', W/2, H*0.545);
    ctx.fillText('Đến cờ ❓ và nhấn 1 2 3 4 để trả lời', W/2, H*0.615);
  }

  // ── Question overlay ──────────────────────────────────────────────────────
  _drawQuestion(ctx, W, H) {
    const q = this.questions[this.questionIndex]; if (!q) return;
    this._drawQuestionCard(ctx, W, H, q, null, null);
  }
  _drawFeedback(ctx, W, H) {
    const q = this.questions[this.questionIndex] ?? this.questions[this.questionIndex-1];
    if (!q) return;
    this._drawQuestionCard(ctx, W, H, q, this.selectedChoiceId, this.feedbackCorrect);
  }

  _drawQuestionCard(ctx, W, H, q, selectedId, isCorrect) {
    ctx.fillStyle='rgba(0,0,0,0.65)'; ctx.fillRect(0,0,W,H);
    const cW=W*0.82,cH=H*0.72,cX=(W-cW)/2,cY=(H-cH)/2;
    ctx.fillStyle='#1e1b4b'; roundRect(ctx,cX,cY,cW,cH,20); ctx.fill();
    ctx.strokeStyle='rgba(139,92,246,0.7)'; ctx.lineWidth=2.5;
    roundRect(ctx,cX,cY,cW,cH,20); ctx.stroke();

    ctx.fillStyle='#e2e8f0'; ctx.font=`600 ${W*0.027}px system-ui`;
    ctx.textAlign='center'; ctx.textBaseline='middle';
    const lines=this._wrapText(ctx,q.prompt,cW*0.84), lineH=W*0.034, ptY=cY+cH*0.14;
    for (let i=0;i<Math.min(lines.length,3);i++) ctx.fillText(lines[i],W/2,ptY+i*lineH);

    const cols=2,choW=cW*0.44,choH=cH*0.16,gX=cW*0.04,gY=cH*0.04;
    const sX=cX+(cW-cols*choW-(cols-1)*gX)/2, sY=cY+cH*0.32;
    const labels=['1','2','3','4'];

    q.choices.forEach((c,idx)=>{
      const col=idx%cols,row=Math.floor(idx/cols);
      const cx=sX+col*(choW+gX), cy=sY+row*(choH+gY);
      const isSel=selectedId===c.id, isCrct=c.id===q.correctChoiceId;
      let bg='rgba(255,255,255,0.08)',border='rgba(255,255,255,0.25)';
      if(isSel&&isCorrect)            {bg='rgba(16,185,129,0.35)';border='#10b981';}
      if(isSel&&!isCorrect)           {bg='rgba(239,68,68,0.35)'; border='#ef4444';}
      if(selectedId&&isCrct&&!isCorrect){bg='rgba(16,185,129,0.2)';border='#10b981';}
      ctx.fillStyle=bg; roundRect(ctx,cx,cy,choW,choH,12); ctx.fill();
      ctx.strokeStyle=border; ctx.lineWidth=1.5; roundRect(ctx,cx,cy,choW,choH,12); ctx.stroke();
      const lS=choH*0.52;
      ctx.fillStyle='rgba(139,92,246,0.8)'; roundRect(ctx,cx+8,cy+8,lS,lS,6); ctx.fill();
      ctx.fillStyle='#fff'; ctx.font=`700 ${lS*0.52}px system-ui`;
      ctx.textAlign='center'; ctx.textBaseline='middle';
      ctx.fillText(labels[idx],cx+8+lS/2,cy+8+lS/2);
      ctx.fillStyle='#e2e8f0'; ctx.font=`500 ${W*0.02}px system-ui`;
      ctx.textAlign='center'; ctx.textBaseline='middle';
      const cLines=this._wrapText(ctx,c.text,choW-lS-20);
      ctx.fillText(cLines[0]??c.text, cx+lS+(choW-lS)/2+4, cy+choH/2);
    });

    if (!selectedId) {
      ctx.fillStyle='rgba(255,255,255,0.4)'; ctx.font=`${W*0.018}px system-ui`;
      ctx.textAlign='center'; ctx.textBaseline='middle';
      ctx.fillText('Nhấn  1  2  3  4  để chọn đáp án',W/2,cY+cH*0.9);
    } else {
      const msg=isCorrect?'✓  Tuyệt vời! Đúng rồi!':'✗  Chưa đúng, thử lại nhé!';
      ctx.fillStyle=isCorrect?'rgba(16,185,129,0.9)':'rgba(239,68,68,0.9)';
      roundRect(ctx,cX,cY+cH-52,cW,52,16); ctx.fill();
      ctx.fillStyle='#fff'; ctx.font=`700 ${W*0.025}px system-ui`;
      ctx.textAlign='center'; ctx.textBaseline='middle';
      ctx.fillText(msg,W/2,cY+cH-26);
    }
  }

  // ── Victory ───────────────────────────────────────────────────────────────
  _drawVictory(ctx, W, H, nowMs) {
    const elapsed=nowMs-this.stateAtMs, alpha=clamp(elapsed/500,0,1);
    ctx.fillStyle=`rgba(0,0,0,${0.5*alpha})`; ctx.fillRect(0,0,W,H);
    for (const pt of this.particles) {
      ctx.save(); ctx.translate(pt.x*W,pt.y*H); ctx.rotate(pt.rot);
      const s=pt.size*W; ctx.fillStyle=pt.color; ctx.fillRect(-s/2,-s/2,s,s*0.6); ctx.restore();
    }
    const t=easeOut(clamp(elapsed/600,0,1)), vW=W*0.7,vH=H*0.5;
    const vX=(W-vW)/2, vY=lerp(H,(H-vH)/2,t);
    ctx.fillStyle='#1e1b4b'; roundRect(ctx,vX,vY,vW,vH,24); ctx.fill();
    ctx.strokeStyle='#f59e0b'; ctx.lineWidth=3; roundRect(ctx,vX,vY,vW,vH,24); ctx.stroke();
    ctx.fillStyle='#f59e0b'; ctx.font=`bold ${W*0.05}px system-ui`;
    ctx.textAlign='center'; ctx.textBaseline='middle';
    ctx.fillText('🎉  Hoàn thành!  🎉',W/2,vY+vH*0.22);
    ctx.fillStyle='#a5b4fc'; ctx.font=`${W*0.03}px system-ui`;
    ctx.fillText(`Đúng ${this.score} / ${this.questions.length} câu`,W/2,vY+vH*0.45);
    const pct=this.questions.length>0?Math.round((this.score/this.questions.length)*100):0;
    ctx.fillStyle='#e2e8f0'; ctx.font=`600 ${W*0.027}px system-ui`;
    ctx.fillText(pct===100?'⭐ Xuất sắc!':pct>=60?'👍 Khá tốt!':'📚 Cần ôn thêm!',W/2,vY+vH*0.7);
  }

  // ── Util ──────────────────────────────────────────────────────────────────
  _wrapText(ctx, text, maxW) {
    const words=String(text||'').split(/\s+/); const lines=[]; let line='';
    for (const w of words) {
      const test=line?`${line} ${w}`:w;
      if (ctx.measureText(test).width>maxW&&line){lines.push(line);line=w;} else line=test;
    }
    if (line) lines.push(line); return lines;
  }
}
