/**
 * KeyboardInput — Keyboard state manager for keyboard-based game blueprints.
 *
 * Usage:
 *   const kb = new KeyboardInput();
 *   kb.attach(window);
 *   // in game loop:
 *   if (kb.justPressed('ArrowRight')) { ... }
 *   kb.resetFrame(); // call at END of each game frame
 *   // cleanup:
 *   kb.detach();
 *
 * justPressed(key) returns true only on the FIRST frame the key is held down.
 * isPressed(key) returns true for every frame the key is held.
 */

const KEY_ALIASES = {
  // Movement
  ArrowLeft:  'left',
  ArrowRight: 'right',
  ArrowUp:    'up',
  ArrowDown:  'down',
  a: 'left', A: 'left',
  d: 'right', D: 'right',
  w: 'up',   W: 'up',
  s: 'down', S: 'down',
  // Action
  ' ':     'jump',
  Enter:   'enter',
  Escape:  'escape',
  // Answer choices 1-4 (number row + numpad)
  '1': 'ans1', '2': 'ans2', '3': 'ans3', '4': 'ans4',
  Numpad1: 'ans1', Numpad2: 'ans2', Numpad3: 'ans3', Numpad4: 'ans4',
};

export class KeyboardInput {
  constructor() {
    /** @type {Set<string>} canonical keys currently held */
    this._held = new Set();
    /** @type {Set<string>} canonical keys pressed THIS frame only */
    this._justPressed = new Set();
    /** @type {Set<string>} raw keys held (to prevent repeat events re-adding to justPressed) */
    this._rawHeld = new Set();

    this._onKeyDown = this._onKeyDown.bind(this);
    this._onKeyUp   = this._onKeyUp.bind(this);
    this._target    = null;
  }

  /** Attach listeners to an EventTarget (window or canvas element). */
  attach(target) {
    if (this._target) this.detach();
    this._target = target;
    target.addEventListener('keydown', this._onKeyDown);
    target.addEventListener('keyup',   this._onKeyUp);
  }

  /** Remove listeners. */
  detach() {
    if (!this._target) return;
    this._target.removeEventListener('keydown', this._onKeyDown);
    this._target.removeEventListener('keyup',   this._onKeyUp);
    this._target = null;
    this._held.clear();
    this._justPressed.clear();
    this._rawHeld.clear();
  }

  /**
   * Call at the END of each game frame to clear justPressed.
   */
  resetFrame() {
    this._justPressed.clear();
  }

  /** True while the key is held down. */
  isPressed(action) {
    return this._held.has(action);
  }

  /** True only on the first frame the key went down. */
  justPressed(action) {
    return this._justPressed.has(action);
  }

  _onKeyDown(e) {
    const action = KEY_ALIASES[e.key];
    if (!action) return;

    // Prevent browser scroll / zoom on game keys
    if (['jump', 'up', 'down', 'left', 'right', 'enter'].includes(action)) {
      e.preventDefault();
    }

    this._held.add(action);

    // Only add to justPressed if not already held (avoids keyboard repeat events)
    if (!this._rawHeld.has(e.key)) {
      this._rawHeld.add(e.key);
      this._justPressed.add(action);
    }
  }

  _onKeyUp(e) {
    const action = KEY_ALIASES[e.key];
    if (action) this._held.delete(action);
    this._rawHeld.delete(e.key);
  }
}
