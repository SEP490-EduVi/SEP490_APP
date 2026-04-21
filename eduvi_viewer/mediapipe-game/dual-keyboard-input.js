/**
 * DualKeyboardInput — Two-player keyboard input manager.
 *
 * Splits keyboard into two independent player controllers on one window.
 *
 * Player 1 controls:
 *   Movement : A (left) D (right) W (up) S (down)
 *   Jump     : Space
 *   Answers  : Z (ans1)  X (ans2)  C (ans3)  V (ans4)
 *
 * Player 2 controls:
 *   Movement : ArrowLeft  ArrowRight  ArrowUp  ArrowDown
 *   Jump     : Enter
 *   Answers  : 1 (ans1)  2 (ans2)  3 (ans3)  4 (ans4)
 *
 * Usage:
 *   const dual = new DualKeyboardInput();
 *   dual.attach(window);
 *   // in game loop:
 *   if (dual.player1.justPressed('jump')) { ... }
 *   if (dual.player2.isPressed('right'))  { ... }
 *   dual.resetFrame(); // call at END of each frame
 *   // cleanup:
 *   dual.detach();
 */

// ─── Key → action maps ───────────────────────────────────────────────────────

const P1_ALIASES = {
  a: 'left',  A: 'left',
  d: 'right', D: 'right',
  w: 'up',    W: 'up',
  s: 'down',  S: 'down',
  ' ':   'jump',
  z: 'ans1', Z: 'ans1',
  x: 'ans2', X: 'ans2',
  c: 'ans3', C: 'ans3',
  v: 'ans4', V: 'ans4',
};

const P2_ALIASES = {
  ArrowLeft:  'left',
  ArrowRight: 'right',
  ArrowUp:    'up',
  ArrowDown:  'down',
  Enter: 'jump',
  '1': 'ans1', '2': 'ans2', '3': 'ans3', '4': 'ans4',
  Numpad1: 'ans1', Numpad2: 'ans2', Numpad3: 'ans3', Numpad4: 'ans4',
};

// ─── Single-player state object (used internally for each player) ─────────────

class PlayerInput {
  constructor() {
    /** @type {Set<string>} */
    this._held = new Set();
    /** @type {Set<string>} */
    this._justPressed = new Set();
    /** @type {Set<string>} raw keys currently held (prevents keydown repeats) */
    this._rawHeld = new Set();
  }

  /** Called by DualKeyboardInput on keydown for this player's key. */
  _keyDown(rawKey, action) {
    if (this._rawHeld.has(rawKey)) return; // ignore auto-repeat
    this._rawHeld.add(rawKey);
    this._held.add(action);
    this._justPressed.add(action);
  }

  /** Called by DualKeyboardInput on keyup for this player's key. */
  _keyUp(rawKey, action) {
    this._rawHeld.delete(rawKey);
    this._held.delete(action);
  }

  /** True for every frame the action is held. */
  isPressed(action) {
    return this._held.has(action);
  }

  /** True only on the FIRST frame the action is pressed. */
  justPressed(action) {
    return this._justPressed.has(action);
  }

  /** Clear justPressed — call at END of each game frame. */
  resetFrame() {
    this._justPressed.clear();
  }

  /** Full reset (on detach). */
  _clear() {
    this._held.clear();
    this._justPressed.clear();
    this._rawHeld.clear();
  }
}

// ─── DualKeyboardInput ────────────────────────────────────────────────────────

export class DualKeyboardInput {
  constructor() {
    /** @type {PlayerInput} Player 1: WASD + Space + ZXCV */
    this.player1 = new PlayerInput();
    /** @type {PlayerInput} Player 2: Arrows + Enter + 1234 */
    this.player2 = new PlayerInput();

    this._target = null;
    this._onKeyDown = this._onKeyDown.bind(this);
    this._onKeyUp   = this._onKeyUp.bind(this);
  }

  /** Attach listeners to an EventTarget (window). */
  attach(target) {
    if (this._target) this.detach();
    this._target = target;
    target.addEventListener('keydown', this._onKeyDown);
    target.addEventListener('keyup',   this._onKeyUp);
  }

  /** Remove listeners and clear state. */
  detach() {
    if (!this._target) return;
    this._target.removeEventListener('keydown', this._onKeyDown);
    this._target.removeEventListener('keyup',   this._onKeyUp);
    this._target = null;
    this.player1._clear();
    this.player2._clear();
  }

  /**
   * Call at the END of each game frame to clear justPressed for both players.
   */
  resetFrame() {
    this.player1.resetFrame();
    this.player2.resetFrame();
  }

  _onKeyDown(e) {
    const key = e.key;
    const p1action = P1_ALIASES[key];
    const p2action = P2_ALIASES[key];

    if (p1action) {
      e.preventDefault();
      this.player1._keyDown(key, p1action);
    }
    if (p2action) {
      e.preventDefault();
      this.player2._keyDown(key, p2action);
    }
  }

  _onKeyUp(e) {
    const key = e.key;
    const p1action = P1_ALIASES[key];
    const p2action = P2_ALIASES[key];

    if (p1action) this.player1._keyUp(key, p1action);
    if (p2action) this.player2._keyUp(key, p2action);
  }
}
