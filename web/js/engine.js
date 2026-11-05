// Wraps one compiled puzzle (web/wasm/<name>.js) and draws it onto a canvas.

export const BTN = {
  left: 0x200, middle: 0x201, right: 0x202,
  leftDrag: 0x203, middleDrag: 0x204, rightDrag: 0x205,
  leftUp: 0x206, middleUp: 0x207, rightUp: 0x208,
  up: 0x209, down: 0x20a, leftKey: 0x20b, rightKey: 0x20c,
  select: 0x20d, select2: 0x20e,
  uiNewGame: 0x211, uiSolve: 0x212, uiUndo: 0x213, uiRedo: 0x214,
  stylus: 0x0800, ctrl: 0x1000, shift: 0x2000, numpad: 0x4000,
};
export const DRAG_OF = { [BTN.left]: BTN.leftDrag, [BTN.middle]: BTN.middleDrag, [BTN.right]: BTN.rightDrag };
export const UP_OF = { [BTN.left]: BTN.leftUp, [BTN.middle]: BTN.middleUp, [BTN.right]: BTN.rightUp };
export const CFG = { settings: 0, prefs: 3 };

function parseConfig(text) {
  return text.split('\n').filter(Boolean).map(l => {
    const [type, name, value, choices] = l.split('\t');
    const item = { type, name, value };
    if (type === 'c') {
      item.choices = choices.slice(1).split(choices[0]);
      item.value = Number(value);
    } else if (type === 'b') item.value = value === '1';
    return item;
  });
}
function configValues(items) {
  return items.map(i => i.type === 'b' ? (i.value ? '1' : '0') : String(i.value)).join('\n');
}

const MIDPOINT_TEST = 'ABCDEFGHIKLMNOPRSTUVWXYZ0123456789';

export async function loadModule(name, fe) {
  const mod = await import(`../wasm/${name}.js`);
  return mod.default({ fe });
}

export class Engine {
  constructor(name, M, canvas, hooks) {
    this.name = name;
    this.M = M;
    this.canvas = canvas;
    this.hooks = hooks; // { onStatus(text), onTimerChange() }
    this.colours = [];
    this.rawColours = [];
    this.feScale = 1;
    this.blitters = new Map();
    this.midpoints = new Map();
    this.timerActive = false;
    this.instantAnim = false;
    this.font = 'system-ui, -apple-system, "Segoe UI", Roboto, sans-serif';
    this.fontWeight = '500';

    this.off = document.createElement('canvas');
    this.ctx = this.off.getContext('2d', { alpha: false });
    this.onctx = canvas.getContext('2d', { alpha: false });

    const c = (n, r, a = []) => M.cwrap(n, r, a);
    this.api = {
      init: c('pz_init', null, ['number']),
      presets: c('pz_presets', 'string'),
      setId: c('pz_set_id', 'string', ['string']),
      newGame: c('pz_new_game', null),
      getId: c('pz_get_id', 'string'),
      getParams: c('pz_get_params', 'string'),
      save: c('pz_save', 'string'),
      load: c('pz_load', 'string', ['string']),
      size: c('pz_size', null, ['number', 'number', 'number']),
      redraw: c('pz_redraw', null),
      tilesize: c('pz_tilesize', 'number'),
      input: c('pz_input', 'number', ['number', 'number', 'number']),
      timer: c('pz_timer', null, ['number']),
      restart: c('pz_restart', null),
      solve: c('pz_solve', 'string'),
      canUndo: c('pz_can_undo', 'number'),
      canRedo: c('pz_can_redo', 'number'),
      status: c('pz_status', 'number'),
      whichPreset: c('pz_which_preset', 'number'),
      colours: c('pz_colours', 'string'),
      keys: c('pz_keys', 'string'),
      getConfig: c('pz_get_config', 'string', ['number']),
      setConfig: c('pz_set_config', 'string', ['number', 'string']),
      savePrefs: c('pz_save_prefs', 'string'),
      loadPrefs: c('pz_load_prefs', 'string', ['string']),
      canSolve: c('pz_can_solve', 'number'),
      wantsStatusbar: c('pz_wants_statusbar', 'number'),
      paramsConfig: c('pz_params_config', 'string', ['string']),
      configParams: c('pz_config_params', 'string', ['string', 'string']),
      keyLabel: c('pz_key_label', 'string', ['number']),
    };
    M.fe = this;
    this.api.init(1);
  }

  // ---- palette ---------------------------------------------------------
  loadColours(mapper) {
    this.rawColours = this.api.colours().trim().split('\n').map(l => l.split(' ').map(Number));
    this.applyPalette(mapper);
  }
  applyPalette(mapper) {
    this.colours = this.rawColours.map((rgb, i) => {
      const [r, g, b] = mapper(rgb, i);
      const h = v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, '0');
      return '#' + h(r) + h(g) + h(b);
    });
  }

  // ---- callbacks from C (Module.fe) -----------------------------------
  fatal(msg) { console.error(msg); alert(msg); }
  activateTimer() {
    this.timerActive = true;
    this.lastTick = performance.now();
    const tick = () => {
      if (!this.timerActive) return;
      const now = performance.now();
      const dt = this.instantAnim ? 60 : (now - this.lastTick) / 1000;
      this.lastTick = now;
      this.api.timer(dt);
      if (this.timerActive) {
        if (this.instantAnim) setTimeout(tick, 0);
        else requestAnimationFrame(tick);
      }
    };
    if (this.instantAnim) setTimeout(tick, 0);
    else requestAnimationFrame(tick);
  }
  deactivateTimer() { this.timerActive = false; }

  setSize(w, h, feScale) {
    this.feScale = feScale;
    for (const cv of [this.canvas, this.off]) { cv.width = w; cv.height = h; }
    this.ctx.setTransform(feScale, 0, 0, feScale, 0, 0);
    this.midpoints.clear();
  }
  startDraw() { this.upd = null; }
  drawUpdate(x, y, w, h) {
    const s = this.feScale;
    x *= s; y *= s; w *= s; h *= s;
    const u = this.upd;
    if (!u) this.upd = { x0: x, y0: y, x1: x + w, y1: y + h };
    else {
      u.x0 = Math.min(u.x0, x); u.y0 = Math.min(u.y0, y);
      u.x1 = Math.max(u.x1, x + w); u.y1 = Math.max(u.y1, y + h);
    }
  }
  endDraw() {
    const u = this.upd;
    if (!u) return;
    const x0 = Math.max(0, Math.floor(u.x0)), y0 = Math.max(0, Math.floor(u.y0));
    const x1 = Math.min(this.off.width, Math.ceil(u.x1)), y1 = Math.min(this.off.height, Math.ceil(u.y1));
    if (x1 > x0 && y1 > y0)
      this.onctx.drawImage(this.off, x0, y0, x1 - x0, y1 - y0, x0, y0, x1 - x0, y1 - y0);
    this.upd = null;
  }
  rect(x, y, w, h, c) {
    this.ctx.fillStyle = this.colours[c];
    this.ctx.fillRect(x, y, w, h);
  }
  line(x1, y1, x2, y2, width, c) {
    const ctx = this.ctx, col = this.colours[c];
    ctx.beginPath();
    ctx.moveTo(x1 + 0.5, y1 + 0.5);
    ctx.lineTo(x2 + 0.5, y2 + 0.5);
    ctx.lineWidth = width;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = col;
    ctx.stroke();
    ctx.fillStyle = col;
    ctx.fillRect(x1, y1, 1, 1);
    ctx.fillRect(x2, y2, 1, 1);
  }
  poly(pts, n, fill, outline) {
    const ctx = this.ctx;
    ctx.beginPath();
    ctx.moveTo(pts[0] + 0.5, pts[1] + 0.5);
    for (let i = 1; i < n; i++) ctx.lineTo(pts[2 * i] + 0.5, pts[2 * i + 1] + 0.5);
    ctx.closePath();
    if (fill >= 0) { ctx.fillStyle = this.colours[fill]; ctx.fill(); }
    ctx.lineWidth = 1;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = this.colours[outline];
    ctx.stroke();
  }
  circle(x, y, r, fill, outline) {
    const ctx = this.ctx;
    ctx.beginPath();
    ctx.arc(x + 0.5, y + 0.5, r, 0, 2 * Math.PI);
    if (fill >= 0) { ctx.fillStyle = this.colours[fill]; ctx.fill(); }
    ctx.lineWidth = 1;
    ctx.strokeStyle = this.colours[outline];
    ctx.stroke();
  }
  fontString(size, mono) {
    return `${mono ? 'normal' : this.fontWeight} ${size}px ${mono ? 'ui-monospace, Menlo, monospace' : this.font}`;
  }
  midpoint(size, mono) {
    if (size <= 0) return 0;
    const key = size + (mono ? 'm' : 's');
    let v = this.midpoints.get(key);
    if (v !== undefined) return v;
    const c = document.createElement('canvas');
    const x = c.getContext('2d', { alpha: false, willReadFrequently: true });
    x.font = this.fontString(size, mono);
    const w = Math.ceil(x.measureText(MIDPOINT_TEST).width) + 1;
    c.width = w; c.height = 2 * size;
    x.fillStyle = '#000'; x.fillRect(0, 0, w, 2 * size);
    x.fillStyle = '#fff'; x.font = this.fontString(size, mono);
    const base = Math.floor(1.5 * size);
    x.fillText(MIDPOINT_TEST, 0, base);
    const px = x.getImageData(0, 0, w, 2 * size).data;
    let ymin = 2 * size, ymax = -1;
    for (let yy = 0; yy < 2 * size; yy++)
      for (let xx = 0; xx < w; xx++)
        if (px[4 * (yy * w + xx)]) { ymin = Math.min(ymin, yy); ymax = Math.max(ymax, yy); break; }
    v = Math.floor(base - (ymin + ymax) / 2);
    this.midpoints.set(key, v);
    return v;
  }
  text(x, y, fonttype, size, align, c, str) {
    const mono = fonttype === 0; // FONT_FIXED
    if (align & 0x100) y += this.midpoint(size, mono); // ALIGN_VCENTRE
    const ctx = this.ctx;
    ctx.font = this.fontString(size, mono);
    ctx.fillStyle = this.colours[c];
    ctx.textAlign = (align & 0x001) ? 'center' : (align & 0x002) ? 'right' : 'left';
    ctx.textBaseline = 'alphabetic';
    ctx.fillText(str, x, y);
  }
  clip(x, y, w, h) {
    this.ctx.save();
    this.ctx.beginPath();
    this.ctx.rect(x, y, w, h);
    this.ctx.clip();
  }
  unclip() { this.ctx.restore(); }
  status(text) { this.hooks.onStatus?.(text); }
  blitterNew(id, w, h) {
    const c = document.createElement('canvas');
    c.width = w * this.feScale; c.height = h * this.feScale;
    this.blitters.set(id, c);
  }
  blitterFree(id) { this.blitters.delete(id); }
  blitterSave(id, x, y) {
    const b = this.blitters.get(id), s = this.feScale;
    b.getContext('2d').drawImage(this.off, -x * s, -y * s);
  }
  blitterLoad(id, x, y) {
    const b = this.blitters.get(id), s = this.feScale;
    this.ctx.save();
    this.ctx.setTransform(1, 0, 0, 1, 0, 0);
    this.ctx.drawImage(b, x * s, y * s);
    this.ctx.restore();
  }

  // ---- helpers for the app --------------------------------------------
  presets() {
    return this.api.presets().split('\n').filter(Boolean).map(l => {
      const [title, params] = l.split('\t');
      return { title, params };
    });
  }
  keys() {
    return this.api.keys().split('\n').filter(Boolean).map(l => {
      const [label, button] = l.split('\t');
      return { label, button: Number(button) };
    });
  }
  getConfig(which) { return parseConfig(this.api.getConfig(which)); }
  paramsConfig(params) { return parseConfig(this.api.paramsConfig(params)); }
  // Returns { params } or { error }.
  configToParams(base, items) {
    const r = this.api.configParams(base, configValues(items));
    return r[0] === '=' ? { params: r.slice(1) } : { error: r.slice(1) };
  }
  setConfig(which, items) { return this.api.setConfig(which, configValues(items)); }
  // Puzzle coordinates of a client point.
  toPuzzle(clientX, clientY) {
    const r = this.canvas.getBoundingClientRect();
    const sx = this.canvas.width / r.width / this.feScale;
    const sy = this.canvas.height / r.height / this.feScale;
    return [Math.round((clientX - r.left) * sx), Math.round((clientY - r.top) * sy)];
  }
}
