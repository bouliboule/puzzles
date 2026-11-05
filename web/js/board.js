// Board view: sizes the puzzle canvas to the viewport, handles zoom/pan,
// and turns pointer input (mouse, touch, pen) into midend button events.
import { BTN, DRAG_OF, UP_OF } from './engine.js';

const MAX_CANVAS_PX = 12e6;     // stay well under iOS's 16.7M canvas limit
const MAX_TILE_CSS = 96;        // don't zoom beyond this tile size
const PAD = 6;

export class Board {
  constructor(viewport, canvas, opts) {
    this.vp = viewport;
    this.canvas = canvas;
    this.opts = opts; // { primaryButton(), longPress(), stylus(), onInput(pkr), onLongPress(x,y) }
    this.engine = null;
    this.zoom = 1;
    this.maxZoom = 1;
    this.pan = { x: 0, y: 0 };
    this.cssW = 0; this.cssH = 0;
    this.pointers = new Map();
    this.g = null; // current gesture

    const vp = viewport;
    vp.addEventListener('pointerdown', e => this.down(e));
    vp.addEventListener('pointermove', e => this.move(e));
    vp.addEventListener('pointerup', e => this.up(e, false));
    vp.addEventListener('pointercancel', e => this.up(e, true));
    vp.addEventListener('contextmenu', e => e.preventDefault());
    vp.addEventListener('wheel', e => this.wheel(e), { passive: false });
    // iOS Safari: stop page gestures (pinch-zoom of the whole page).
    for (const t of ['gesturestart', 'gesturechange', 'gestureend'])
      vp.addEventListener(t, e => e.preventDefault());
    this.ro = new ResizeObserver(() => this.relayout());
    this.ro.observe(vp);
  }

  attach(engine) {
    this.engine = engine;
    this.canvas = engine.canvas;
    this.lastVw = this.lastVh = undefined;
    this.zoom = 1;
    this.layout();
  }

  // Render at current zoom; returns css size.
  render() {
    const e = this.engine;
    if (!e) return;
    const vw = this.vp.clientWidth, vh = this.vp.clientHeight;
    if (vw < 10 || vh < 10) return;
    const aw = Math.max(50, (vw - 2 * PAD) * this.zoom), ah = Math.max(50, (vh - 2 * PAD) * this.zoom);
    let dpr = window.devicePixelRatio || 1;
    if (aw * ah * dpr * dpr > MAX_CANVAS_PX) dpr = Math.max(1, Math.sqrt(MAX_CANVAS_PX / (aw * ah)));
    this.dpr = dpr;
    e.api.size(Math.floor(aw), Math.floor(ah), dpr);
    this.cssW = this.canvas.width / dpr;
    this.cssH = this.canvas.height / dpr;
    this.canvas.style.width = this.cssW + 'px';
    this.canvas.style.height = this.cssH + 'px';
    e.api.redraw();
  }

  // Full layout from scratch at zoom 1.
  layout() {
    if (!this.engine) return;
    this.zoom = 1;
    this.render();
    // Work out how far we may zoom: until a tile is MAX_TILE_CSS wide.
    const ts = this.engine.api.tilesize();
    const tileCss = ts * this.engine.feScale / this.dpr;
    this.maxZoom = tileCss > 0 ? Math.max(1, Math.min(6, MAX_TILE_CSS / tileCss)) : 3;
    if (this.maxZoom < 1.15) this.maxZoom = 1;
    this.centre();
    this.opts.onZoomChange?.();
  }

  relayout() {
    if (!this.engine) return;
    const vw = this.vp.clientWidth, vh = this.vp.clientHeight;
    if (this.lastVw === vw && this.lastVh === vh) return;
    this.lastVw = vw; this.lastVh = vh;
    if (this.zoom === 1) return this.layout();
    // Keep the centre point of the view stable.
    const fx = (vw / 2 - this.pan.x) / this.cssW, fy = (vh / 2 - this.pan.y) / this.cssH;
    this.render();
    this.pan.x = vw / 2 - fx * this.cssW;
    this.pan.y = vh / 2 - fy * this.cssH;
    this.clampPan();
    this.applyTransform();
  }

  centre() {
    this.pan.x = (this.vp.clientWidth - this.cssW) / 2;
    this.pan.y = (this.vp.clientHeight - this.cssH) / 2;
    this.applyTransform();
  }

  clampPan() {
    const vw = this.vp.clientWidth, vh = this.vp.clientHeight;
    const m = PAD;
    if (this.cssW + 2 * m <= vw) this.pan.x = (vw - this.cssW) / 2;
    else this.pan.x = Math.min(m, Math.max(vw - this.cssW - m, this.pan.x));
    if (this.cssH + 2 * m <= vh) this.pan.y = (vh - this.cssH) / 2;
    else this.pan.y = Math.min(m, Math.max(vh - this.cssH - m, this.pan.y));
  }

  applyTransform(scale = 1) {
    this.canvas.style.transform =
      `translate(${Math.round(this.pan.x)}px, ${Math.round(this.pan.y)}px)` + (scale !== 1 ? ` scale(${scale})` : '');
  }

  get canZoom() { return this.maxZoom > 1; }

  // Zoom to `z` keeping viewport point (fx, fy) fixed.
  setZoom(z, fx, fy) {
    z = Math.max(1, Math.min(this.maxZoom, z));
    const vw = this.vp.clientWidth, vh = this.vp.clientHeight;
    if (fx === undefined) { fx = vw / 2; fy = vh / 2; }
    const ux = (fx - this.pan.x) / this.cssW, uy = (fy - this.pan.y) / this.cssH;
    this.zoom = z;
    this.render();
    this.pan.x = fx - ux * this.cssW;
    this.pan.y = fy - uy * this.cssH;
    this.clampPan();
    this.applyTransform();
    this.opts.onZoomChange?.();
  }
  zoomIn() { this.setZoom(this.zoom * 1.6); }
  zoomOut() { this.setZoom(this.zoom / 1.6); }

  // ---- input ----------------------------------------------------------
  local(e) {
    const r = this.vp.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  }

  send(clientX, clientY, button) {
    const [x, y] = this.engine.toPuzzle(clientX, clientY);
    const r = this.engine.api.input(x, y, button);
    this.opts.onInput?.(r, button);
    return r;
  }

  capture(e) { try { this.vp.setPointerCapture(e.pointerId); } catch { /* synthetic */ } }

  mod() { return this.opts.stylus?.() ? BTN.stylus : 0; }

  down(e) {
    if (!this.engine) return;
    e.preventDefault();
    if (e.pointerType === 'mouse') {
      let b = e.button === 1 ? BTN.middle : e.button === 2 ? BTN.right : BTN.left;
      if (b === BTN.left) b = this.opts.primaryButton();
      this.g = { kind: 'mouse', btn: b, id: e.pointerId };
      this.capture(e);
      this.send(e.clientX, e.clientY, b | this.mod());
      return;
    }
    this.capture(e);
    this.pointers.set(e.pointerId, { cx: e.clientX, cy: e.clientY, ...this.local(e) });
    if (this.pointers.size === 1) {
      const g = this.g = {
        kind: 'pending', id: e.pointerId, x0: e.clientX, y0: e.clientY,
        btn: this.opts.primaryButton(), slop: e.pointerType === 'pen' ? 4 : 9,
      };
      if (this.opts.longPress()) {
        g.timer = setTimeout(() => {
          if (this.g !== g || g.kind !== 'pending') return;
          g.btn = g.btn === BTN.left ? BTN.right : BTN.left;
          g.kind = 'game';
          this.opts.onLongPress?.(g.x0, g.y0);
          this.send(g.x0, g.y0, g.btn | this.mod());
        }, 420);
      }
    } else if (this.pointers.size === 2 && this.g && (this.g.kind === 'pending' || this.g.kind === 'pinch-wait')) {
      clearTimeout(this.g.timer);
      this.startPinch();
    }
  }

  move(e) {
    if (!this.g) return;
    if (this.g.kind === 'mouse') {
      if (e.pointerId === this.g.id && e.buttons) this.send(e.clientX, e.clientY, DRAG_OF[this.g.btn] | this.mod());
      return;
    }
    const p = this.pointers.get(e.pointerId);
    if (!p) return;
    p.cx = e.clientX; p.cy = e.clientY;
    Object.assign(p, this.local(e));
    const g = this.g;
    if (g.kind === 'pending' && e.pointerId === g.id) {
      if (Math.hypot(e.clientX - g.x0, e.clientY - g.y0) > g.slop) {
        clearTimeout(g.timer);
        g.kind = 'game';
        this.send(g.x0, g.y0, g.btn | this.mod());
        this.send(e.clientX, e.clientY, DRAG_OF[g.btn] | this.mod());
      }
    } else if (g.kind === 'game' && e.pointerId === g.id) {
      this.send(e.clientX, e.clientY, DRAG_OF[g.btn] | this.mod());
    } else if (g.kind === 'pinch') {
      this.updatePinch();
    }
  }

  up(e, cancelled) {
    const g = this.g;
    if (g && g.kind === 'mouse') {
      if (e.pointerId === g.id) {
        this.send(e.clientX, e.clientY, UP_OF[g.btn] | this.mod());
        this.g = null;
      }
      return;
    }
    if (!this.pointers.has(e.pointerId)) return;
    this.pointers.delete(e.pointerId);
    if (g) {
      if (g.kind === 'pending' && e.pointerId === g.id) {
        clearTimeout(g.timer);
        if (!cancelled) {
          this.send(g.x0, g.y0, g.btn | this.mod());
          this.send(g.x0, g.y0, UP_OF[g.btn] | this.mod());
        }
        g.kind = 'done';
      } else if (g.kind === 'game' && e.pointerId === g.id) {
        this.send(e.clientX, e.clientY, UP_OF[g.btn] | this.mod());
        g.kind = 'done';
      } else if (g.kind === 'pinch') {
        this.endPinch();
        g.kind = 'done';
      }
    }
    if (this.pointers.size === 0) this.g = null;
  }

  startPinch() {
    const [a, b] = [...this.pointers.values()];
    this.g = {
      kind: 'pinch',
      d0: Math.max(20, Math.hypot(a.x - b.x, a.y - b.y)),
      m0: { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 },
      pan0: { ...this.pan }, zoom0: this.zoom, w0: this.cssW, s: 1,
    };
  }
  updatePinch() {
    const g = this.g, [a, b] = [...this.pointers.values()];
    if (!b) return;
    const d = Math.hypot(a.x - b.x, a.y - b.y);
    let s = this.canZoom ? d / g.d0 : 1;
    s = Math.max(1 / g.zoom0, Math.min(this.maxZoom / g.zoom0, s));
    const m = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
    g.s = s; g.m = m;
    this.pan.x = m.x - (g.m0.x - g.pan0.x) * s;
    this.pan.y = m.y - (g.m0.y - g.pan0.y) * s;
    if (Math.abs(s - 1) < 0.02) { this.clampPan(); this.applyTransform(); }
    else this.applyTransform(s);
  }
  endPinch() {
    const g = this.g;
    if (!g.m) return;
    if (Math.abs(g.s - 1) < 0.02) { this.clampPan(); this.applyTransform(); return; }
    this.zoom = Math.max(1, Math.min(this.maxZoom, g.zoom0 * g.s));
    this.render();
    const r = this.cssW / g.w0;
    this.pan.x = g.m.x - (g.m0.x - g.pan0.x) * r;
    this.pan.y = g.m.y - (g.m0.y - g.pan0.y) * r;
    this.clampPan();
    this.applyTransform();
    this.opts.onZoomChange?.();
  }

  wheel(e) {
    if (!this.engine) return;
    e.preventDefault();
    if (e.ctrlKey) {
      const p = this.local(e);
      this.setZoom(this.zoom * Math.exp(-e.deltaY * 0.01), p.x, p.y);
    } else {
      this.pan.x -= e.deltaX; this.pan.y -= e.deltaY;
      this.clampPan();
      this.applyTransform();
    }
  }
}
