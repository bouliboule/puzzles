import { Engine, loadModule, BTN, CFG } from './engine.js';
import { Board } from './board.js';
import { PUZZLES, ORDER, ICONS } from './puzzles.js';

const $ = (id) => document.getElementById(id);
const store = {
  get(k, d) { try { const v = localStorage.getItem('pz:' + k); return v === null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem('pz:' + k, JSON.stringify(v)); } catch { /* full or blocked */ } },
  del(k) { try { localStorage.removeItem('pz:' + k); } catch { } },
};

// ---- settings & theme ---------------------------------------------------
const settings = Object.assign({ theme: 'auto', longPress: true, showTimer: true }, store.get('settings', {}));
function resolvedTheme() {
  let t = settings.theme;
  if (t === 'auto') {
    t = matchMedia('(update: slow), (monochrome)').matches ? 'eink'
      : matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }
  return t;
}
function applyTheme() {
  const t = resolvedTheme();
  document.documentElement.dataset.theme = t;
  const meta = document.querySelectorAll('meta[name="theme-color"]');
  const bg = getComputedStyle(document.documentElement).getPropertyValue('--bg').trim();
  meta.forEach(m => { m.content = bg; m.removeAttribute('media'); });
  if (cur) {
    cur.engine.instantAnim = t === 'eink';
    cur.engine.fontWeight = t === 'eink' ? '700' : '500';
    cur.engine.applyPalette(paletteFor(t));
    $('viewport').style.background = cur.engine.colours[0];
    cur.engine.midpoints.clear();
    cur.engine.api.redraw();
  }
}
matchMedia('(prefers-color-scheme: dark)').addEventListener?.('change', () => settings.theme === 'auto' && applyTheme());

function rgb2hsl([r, g, b]) {
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2;
  if (mx === mn) return [0, 0, l];
  const d = mx - mn, s = l > .5 ? d / (2 - mx - mn) : d / (mx + mn);
  const h = mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [h / 6, s, l];
}
function hsl2rgb([h, s, l]) {
  if (!s) return [l, l, l];
  const q = l < .5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
  const f = t => { t = (t + 1) % 1; return t < 1 / 6 ? p + (q - p) * 6 * t : t < .5 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p; };
  return [f(h + 1 / 3), f(h), f(h - 1 / 3)];
}
function paletteFor(theme) {
  if (theme === 'dark') return (c) => {
    const [h, s, l] = rgb2hsl(c);
    return hsl2rgb([h, s * 0.85, 0.11 + (1 - l) * 0.8]);
  };
  if (theme === 'eink') return ([r, g, b]) => {
    const y = 0.299 * r + 0.587 * g + 0.114 * b;
    const v = y >= 0.86 ? 1 : Math.pow(Math.min(1, y / 0.86), 1.35);
    return [v, v, v];
  };
  return (c) => c.map(v => Math.min(1, v * 1.066));
}

// ---- generator (web worker, with main-thread fallback) ------------------
const gen = {
  worker: null, seq: 0, waiting: new Map(),
  init() {
    try {
      this.worker = new Worker(new URL('./gen-worker.js', import.meta.url), { type: 'module' });
      this.worker.onmessage = (e) => {
        const w = this.waiting.get(e.data.id);
        if (!w) return;
        this.waiting.delete(e.data.id);
        e.data.error ? w.reject(new Error(e.data.error)) : w.resolve(e.data.gameId);
      };
      this.worker.onerror = () => { this.worker = null; for (const w of this.waiting.values()) w.reject(new Error('worker failed')); this.waiting.clear(); };
    } catch { this.worker = null; }
  },
  request(name, params) {
    if (!this.worker) return Promise.reject(new Error('no worker'));
    const id = ++this.seq;
    return new Promise((resolve, reject) => {
      this.waiting.set(id, { resolve, reject });
      this.worker.postMessage({ id, name, params });
    });
  },
  // A ready game for name/params: uses the prefetched one if it matches.
  async take(name, params, engine) {
    const next = store.get(name + ':next');
    if (next && next.params === params && next.gameId) { store.del(name + ':next'); return next.gameId; }
    try { return await this.request(name, params); }
    catch {
      // Fallback: generate on the main thread with the display midend.
      const err = engine.api.setId(params);
      if (err) throw new Error(err);
      engine.api.newGame();
      return engine.api.getId();
    }
  },
  prefetch(name, params) {
    const next = store.get(name + ':next');
    if (next && next.params === params) return;
    this.request(name, params).then(gameId => store.set(name + ':next', { params, gameId })).catch(() => { });
  },
};
gen.init();

// ---- state ----------------------------------------------------------------
const engines = new Map();   // name -> Engine (one per puzzle, kept alive)
let cur = null;              // { name, def, engine, meta }
let board;

function metaDefaults(name) {
  return { params: PUZZLES[name].defaultParams, label: '', elapsed: 0, solved: false, helped: false, started: Date.now() };
}

// ---- home ---------------------------------------------------------------
function renderHome() {
  const list = $('puzzle-list');
  list.innerHTML = '';
  const stats = store.get('stats', {});
  for (const name of ORDER) {
    const def = PUZZLES[name];
    const meta = store.get(name + ':meta');
    const hasSave = !!store.get(name + ':save');
    let state = 'New puzzle', cls = '';
    if (meta && hasSave && !meta.solved) { state = `Continue · ${meta.label || ''}`.replace(/ · $/, ''); cls = 'progress'; }
    else if (stats[name]?.solved) state = `${stats[name].solved} solved`;
    const li = document.createElement('li');
    li.innerHTML = `<button class="card" data-name="${name}">
      <span class="icon">${ICONS[name]}</span>
      <span class="name">${def.title}</span>
      <span class="tag">${def.tagline}</span>
      <span class="state ${cls}">${state}</span></button>`;
    li.firstElementChild.addEventListener('click', () => go(name));
    list.appendChild(li);
  }
}

// ---- routing --------------------------------------------------------------
function go(name) { location.hash = name ? '#' + name : ''; }
async function route() {
  const name = location.hash.slice(1);
  if (PUZZLES[name]) await openGame(name);
  else showHome();
}
window.addEventListener('hashchange', route);

function showHome() {
  if (cur) { saveNow(); stopClock(); }
  cur = null;
  $('game').hidden = true;
  $('home').hidden = false;
  renderHome();
}

// ---- game -----------------------------------------------------------------
async function getEngine(name) {
  if (engines.has(name)) return engines.get(name);
  const canvas = document.createElement('canvas');
  const hooks = { onStatus: (t) => { const s = $('statusline'); s.textContent = t; s.hidden = !t; } };
  // The engine object must exist before the module so Module.fe is set early.
  let engine;
  const M = await loadModule(name, null);
  engine = new Engine(name, M, canvas, hooks);
  const prefs = store.get(name + ':prefs');
  if (prefs) engine.api.loadPrefs(prefs);
  else if (PUZZLES[name].defaultPrefs) {
    const items = engine.getConfig(CFG.prefs);
    for (const it of items) if (it.name in PUZZLES[name].defaultPrefs) it.value = PUZZLES[name].defaultPrefs[it.name];
    engine.setConfig(CFG.prefs, items);
  }
  engines.set(name, engine);
  return engine;
}

async function openGame(name) {
  const def = PUZZLES[name];
  $('home').hidden = true;
  $('game').hidden = false;
  $('game-title').textContent = def.title;
  $('game-sub').textContent = '';
  $('banner').hidden = true;
  $('statusline').hidden = true;
  setBusy('Loading…');

  const engine = await getEngine(name);
  if (location.hash.slice(1) !== name) return;
  // Swap the engine's canvas into the viewport.
  const old = $('board');
  if (old !== engine.canvas) { engine.canvas.id = 'board'; old.replaceWith(engine.canvas); }

  cur = { name, def, engine, meta: Object.assign(metaDefaults(name), store.get(name + ':meta', {})) };
  cur.mode = 0;
  applyTheme();

  const save = store.get(name + ':save');
  let loaded = false;
  if (save) {
    const err = engine.api.load(save);
    loaded = !err;
    if (err) console.warn('load failed', err);
  }
  if (!loaded) await newGame(cur.meta.params, true);
  else afterGameStart(false);
  setBusy(null);
}

function setBusy(text) {
  $('busy').hidden = !text;
  if (text) $('busy-text').textContent = text;
}

async function newGame(params, initial = false) {
  const c = cur;
  params = params || c.meta.params;
  setBusy('Generating…');
  $('banner').hidden = true;
  let gameId;
  try {
    gameId = await gen.take(c.name, params, c.engine);
  } catch (e) {
    setBusy(null);
    toast('Could not create puzzle: ' + e.message);
    if (params !== c.def.defaultParams && initial) return newGame(c.def.defaultParams, true);
    return;
  }
  if (cur !== c) return;
  const e = c.engine;
  e.api.setId(params);
  const err = e.api.setId(gameId);
  if (err) { setBusy(null); toast(err); return; }
  e.api.newGame();
  c.meta = Object.assign(metaDefaults(c.name), { params, label: paramsLabel(e, params) });
  afterGameStart(true);
  setBusy(null);
  saveNow();
  gen.prefetch(c.name, params);
}

function afterGameStart(fresh) {
  const c = cur, e = c.engine;
  if (!c.meta.label) c.meta.label = paramsLabel(e, c.meta.params);
  e.loadColours(paletteFor(resolvedTheme()));
  $('viewport').style.background = e.colours[0];
  $('game-sub').textContent = c.meta.label;
  buildModes();
  buildKeypad();
  board.attach(e);
  updateUI();
  c.lastStatus = e.api.status();
  if (c.meta.solved) showSolved(false);
  startClock();
  if (!fresh) gen.prefetch(c.name, c.meta.params);
}

function paramsLabel(engine, params) {
  const p = engine.presets().find(p => p.params === params);
  if (p) return p.title.replace(/^.*\/ /, '');
  const cfg = engine.paramsConfig(params);
  const get = (n) => cfg.find(i => i.name === n);
  const parts = [];
  const w = get('Width'), h = get('Height'), g = get('Grid size');
  if (w && h) parts.push(`${w.value}×${h.value}`);
  else if (g) parts.push(`${g.value}×${g.value}`);
  const t = get('Grid type');
  if (t && t.value !== 0) parts.push(t.choices[t.value]);
  const d = get('Difficulty');
  if (d) parts.push(d.choices[d.value]);
  return parts.join(' ');
}

// ---- input modes & keypad -------------------------------------------------
function buildModes() {
  const seg = $('modes');
  seg.innerHTML = '';
  const modes = cur.def.modes || [];
  seg.hidden = modes.length < 2;
  modes.forEach((m, i) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.textContent = m.label;
    b.setAttribute('role', 'radio');
    b.addEventListener('click', () => { cur.mode = i; updateModes(); });
    seg.appendChild(b);
  });
  updateModes();
}
function updateModes() {
  [...$('modes').children].forEach((b, i) => b.setAttribute('aria-checked', String(i === cur.mode)));
  $('keypad').classList.toggle('notes', cur.def.keypad && cur.def.modes[cur.mode]?.button === 'right');
}
function primaryButton() {
  const m = cur?.def.modes?.[cur.mode];
  return m ? BTN[m.button] : BTN.left;
}

function buildKeypad() {
  const kp = $('keypad');
  kp.innerHTML = '';
  if (!cur.def.keypad) { kp.hidden = true; return; }
  const keys = cur.engine.keys();
  kp.hidden = false;
  kp.style.setProperty('--n', keys.length);
  for (const k of keys) {
    const b = document.createElement('button');
    b.type = 'button';
    if (k.button === 8 || k.button === 127) {
      b.innerHTML = '<svg viewBox="0 0 24 24"><path d="M9 5h11v14H9l-6-7z"/><path d="M12 9l5 6M17 9l-5 6"/></svg>';
      b.setAttribute('aria-label', 'Clear');
    } else b.textContent = k.label;
    b.addEventListener('click', () => {
      // In notes mode, make sure the highlighted cell is in pencil mode.
      sendKey(k.button);
    });
    kp.appendChild(b);
  }
}

function sendKey(button) {
  if (!cur) return;
  const r = cur.engine.api.input(0, 0, button);
  afterInput(r);
  return r;
}

// ---- after every move -------------------------------------------------------
let saveTimer = null;
function afterInput(pkr) {
  if (!cur) return;
  updateUI();
  const st = cur.engine.api.status();
  if (st === 1 && cur.lastStatus !== 1 && !cur.meta.solved) onSolved();
  cur.lastStatus = st;
  if (pkr === 1) {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveNow, 400);
  }
}
function updateUI() {
  const e = cur.engine;
  $('undo').disabled = !e.api.canUndo();
  $('redo').disabled = !e.api.canRedo();
  const z = board.canZoom;
  $('zoom-in').hidden = !z;
  $('zoom-out').hidden = !z;
  $('zoom-in').disabled = board.zoom >= board.maxZoom - 0.01;
  $('zoom-out').disabled = board.zoom <= 1.001;
}
function saveNow() {
  if (!cur) return;
  clearTimeout(saveTimer);
  tickClock();
  store.set(cur.name + ':save', cur.engine.api.save());
  store.set(cur.name + ':meta', cur.meta);
}

function onSolved() {
  const m = cur.meta;
  tickClock();
  m.solved = true;
  if (!m.helped) {
    const stats = store.get('stats', {});
    const s = stats[cur.name] || (stats[cur.name] = { solved: 0, best: {} });
    s.solved++;
    if (!s.best[m.params] || m.elapsed < s.best[m.params]) s.best[m.params] = m.elapsed;
    store.set('stats', stats);
  }
  stopClock();
  saveNow();
  showSolved(true);
}
function showSolved() {
  const m = cur.meta;
  $('banner-text').textContent = m.helped ? 'Solved (with help)' : `Solved in ${fmtTime(m.elapsed)}`;
  $('banner').hidden = false;
  updateClock();
}

// ---- clock ------------------------------------------------------------------
let clockInterval = null, clockFrom = 0;
function fmtTime(s) {
  s = Math.floor(s);
  const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, ss = s % 60;
  return (h ? h + ':' + String(m).padStart(2, '0') : m) + ':' + String(ss).padStart(2, '0');
}
function startClock() {
  stopClock();
  if (!cur || cur.meta.solved || document.hidden) { updateClock(); return; }
  clockFrom = performance.now();
  clockInterval = setInterval(() => { tickClock(); updateClock(); }, 1000);
  updateClock();
}
function tickClock() {
  if (!clockInterval || !cur) return;
  const now = performance.now();
  cur.meta.elapsed += (now - clockFrom) / 1000;
  clockFrom = now;
}
function stopClock() {
  tickClock();
  clearInterval(clockInterval);
  clockInterval = null;
}
function updateClock() {
  const el = $('timer');
  el.hidden = !settings.showTimer || !cur;
  if (cur) el.textContent = fmtTime(cur.meta.elapsed);
}
document.addEventListener('visibilitychange', () => {
  if (!cur) return;
  if (document.hidden) { saveNow(); stopClock(); }
  else startClock();
});
window.addEventListener('pagehide', saveNow);

// ---- sheets -----------------------------------------------------------------
function openSheet(title, build) {
  const dlg = $('sheet');
  $('sheet-title').textContent = title;
  const body = $('sheet-body');
  body.innerHTML = '';
  build(body, () => dlg.close());
  if (!dlg.open) dlg.showModal();
  body.scrollTop = 0;
}
$('sheet').addEventListener('click', (e) => { if (e.target === $('sheet')) $('sheet').close(); });

function menuItem(parent, label, onClick, extra = '') {
  const b = document.createElement('button');
  b.type = 'button';
  b.className = 'menu-item';
  b.innerHTML = `<span>${label}</span>${extra}`;
  b.addEventListener('click', onClick);
  parent.appendChild(b);
  return b;
}
function menuSep(parent) { const d = document.createElement('div'); d.className = 'menu-sep'; parent.appendChild(d); }

function openMenu() {
  const c = cur, e = c.engine;
  openSheet(c.def.title, (body, close) => {
    const m = document.createElement('div'); m.className = 'menu'; body.appendChild(m);
    menuItem(m, 'New game', () => { close(); newGame(); });
    menuItem(m, 'Restart', () => { close(); e.api.restart(); afterInput(1); });
    if (e.api.canSolve()) menuItem(m, 'Solve', () => {
      close();
      const msg = e.api.solve();
      if (msg) toast(msg); else { c.meta.helped = true; afterInput(1); }
    });
    for (const x of c.def.extraMenu || []) menuItem(m, x.label, () => {
      close();
      if (x.key === 'h') c.meta.helped = true;
      sendKey(x.key.charCodeAt(0));
    });
    menuSep(m);
    menuItem(m, 'Puzzle type', () => openTypes(), `<span class="hint">${c.meta.label}</span>`);
    menuItem(m, 'Puzzle settings', () => openPrefs());
    menuItem(m, 'Game ID', () => openGameId());
    menuItem(m, 'How to play', () => openHelp());
    menuSep(m);
    menuItem(m, 'App settings', () => openSettings());
  });
}

function openTypes() {
  const c = cur, e = c.engine;
  openSheet('Puzzle type', (body, close) => {
    const m = document.createElement('div'); m.className = 'menu'; body.appendChild(m);
    const presets = e.presets();
    const isDefault = c.meta.params === c.def.defaultParams;
    const defInPresets = presets.some(p => p.params === c.def.defaultParams);
    if (!defInPresets) {
      menuItem(m, `${paramsLabel(e, c.def.defaultParams)} <span style="color:var(--text-2)">(default)</span>`,
        () => { close(); newGame(c.def.defaultParams); }, isDefault ? '<span class="check">✓</span>' : '');
    }
    let group = null;
    for (const p of presets) {
      const parts = p.title.split(' / ');
      if (parts.length > 1 && parts[0] !== group) {
        group = parts[0];
        const l = document.createElement('div'); l.className = 'menu-label'; l.textContent = group.replace(/\.\.\.$/, '');
        m.appendChild(l);
      }
      menuItem(m, parts[parts.length - 1], () => { close(); newGame(p.params); },
        p.params === c.meta.params ? '<span class="check">✓</span>' : '');
    }
    menuSep(m);
    menuItem(m, 'Custom…', () => openCustom());
  });
}

function buildForm(body, items) {
  const form = document.createElement('div'); form.className = 'form'; body.appendChild(form);
  items.forEach((it) => {
    const f = document.createElement('label');
    f.className = 'field' + (it.type === 'b' ? ' inline' : '');
    const span = document.createElement('span'); span.textContent = it.name;
    f.appendChild(span);
    let input;
    if (it.type === 's') {
      input = document.createElement('input');
      input.type = 'text';
      input.inputMode = /^\d+$/.test(it.value) ? 'numeric' : 'text';
      input.value = it.value;
      input.addEventListener('input', () => { it.value = input.value; });
    } else if (it.type === 'b') {
      input = document.createElement('input');
      input.type = 'checkbox';
      input.checked = it.value;
      input.addEventListener('change', () => { it.value = input.checked; });
    } else {
      input = document.createElement('select');
      it.choices.forEach((ch, j) => { const o = document.createElement('option'); o.value = j; o.textContent = ch; input.appendChild(o); });
      input.value = it.value;
      input.addEventListener('change', () => { it.value = Number(input.value); });
    }
    f.appendChild(input);
    form.appendChild(f);
  });
  const err = document.createElement('div'); err.className = 'error'; err.hidden = true; form.appendChild(err);
  const actions = document.createElement('div'); actions.className = 'form-actions'; form.appendChild(actions);
  return { form, err, actions };
}

function openCustom() {
  const c = cur, e = c.engine;
  const items = e.paramsConfig(c.meta.params);
  openSheet('Custom puzzle', (body, close) => {
    const { err, actions } = buildForm(body, items);
    const ok = document.createElement('button');
    ok.type = 'button'; ok.className = 'btn primary'; ok.textContent = 'Start';
    ok.addEventListener('click', () => {
      const r = e.configToParams(c.meta.params, items);
      if (r.error) { err.textContent = r.error; err.hidden = false; return; }
      close();
      newGame(r.params);
    });
    actions.appendChild(ok);
  });
}

function openPrefs() {
  const c = cur, e = c.engine;
  // Hide the midend's keyboard-shortcut option: not relevant on touch.
  const items = e.getConfig(CFG.prefs);
  openSheet(`${c.def.title} settings`, (body, close) => {
    const { err, actions } = buildForm(body, items);
    const ok = document.createElement('button');
    ok.type = 'button'; ok.className = 'btn primary'; ok.textContent = 'Save';
    ok.addEventListener('click', () => {
      const msg = e.setConfig(CFG.prefs, items);
      if (msg) { err.textContent = msg; err.hidden = false; return; }
      store.set(c.name + ':prefs', e.api.savePrefs());
      close();
      board.layout();
      updateUI();
    });
    actions.appendChild(ok);
  });
}

function openGameId() {
  const c = cur, e = c.engine;
  openSheet('Game ID', (body, close) => {
    body.insertAdjacentHTML('beforeend', `<p>Share this ID to play the same puzzle on another device.</p>
      <p class="idbox" id="gid"></p>
      <div class="form-actions" style="justify-content:flex-start"><button type="button" class="btn" id="gid-copy">Copy</button></div>
      <div class="form"><label class="field"><span>Load a game ID</span><input type="text" id="gid-in" autocapitalize="off" autocomplete="off" spellcheck="false" placeholder="paste ID here"></label>
      <div class="error" id="gid-err" hidden></div>
      <div class="form-actions"><button type="button" class="btn primary" id="gid-load">Load</button></div></div>`);
    const id = e.api.getId();
    body.querySelector('#gid').textContent = id;
    body.querySelector('#gid-copy').addEventListener('click', async () => {
      try { await navigator.clipboard.writeText(id); toast('Copied'); } catch { toast('Copy failed'); }
    });
    body.querySelector('#gid-load').addEventListener('click', () => {
      const v = body.querySelector('#gid-in').value.trim();
      const errEl = body.querySelector('#gid-err');
      if (!v.includes(':') && !v.includes('#')) { errEl.textContent = 'That does not look like a game ID.'; errEl.hidden = false; return; }
      const err = e.api.setId(v);
      if (err) { errEl.textContent = err; errEl.hidden = false; return; }
      e.api.newGame();
      const params = v.split(/[:#]/)[0];
      c.meta = Object.assign(metaDefaults(c.name), { params: e.api.getParams() || params });
      c.meta.label = paramsLabel(e, c.meta.params);
      close();
      afterGameStart(true);
      saveNow();
    });
  });
}

function openHelp() {
  openSheet(`How to play ${cur.def.title}`, (body) => {
    body.insertAdjacentHTML('beforeend', cur.def.help + `<h3>Everywhere</h3><ul>
      <li><b>Pinch</b> or use the magnifier buttons to zoom; drag with <b>two fingers</b> to move around.</li>
      <li><b>Long press</b> does the opposite action (e.g. cross instead of line) — can be turned off in App settings.</li>
      <li>Your game is saved automatically.</li></ul>`);
  });
}

function openSettings() {
  openSheet('App settings', (body, close) => {
    body.insertAdjacentHTML('beforeend', `<div class="form">
      <label class="field"><span>Theme</span><select id="s-theme">
        <option value="auto">Automatic</option><option value="light">Light</option>
        <option value="dark">Dark</option><option value="eink">E-ink (high contrast, no animation)</option></select></label>
      <label class="field inline"><span>Long press for secondary action</span><input type="checkbox" id="s-long"></label>
      <label class="field inline"><span>Show timer</span><input type="checkbox" id="s-timer"></label>
      </div><p style="color:var(--text-2);font-size:13px;margin-top:22px">Puzzle engine: Simon Tatham's Portable Puzzle Collection, compiled to WebAssembly. MIT licence.</p>`);
    const th = body.querySelector('#s-theme'), lp = body.querySelector('#s-long'), tm = body.querySelector('#s-timer');
    th.value = settings.theme; lp.checked = settings.longPress; tm.checked = settings.showTimer;
    const save = () => {
      settings.theme = th.value; settings.longPress = lp.checked; settings.showTimer = tm.checked;
      store.set('settings', settings);
      applyTheme();
      updateClock();
    };
    th.addEventListener('change', save); lp.addEventListener('change', save); tm.addEventListener('change', save);
  });
}

let toastTimer;
function toast(msg) {
  const t = $('toast');
  t.textContent = msg;
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, 2600);
}

// ---- keyboard ---------------------------------------------------------------
const KEYMAP = {
  ArrowUp: BTN.up, ArrowDown: BTN.down, ArrowLeft: BTN.leftKey, ArrowRight: BTN.rightKey,
  Enter: BTN.select, ' ': BTN.select2, Backspace: 127, Delete: 127, Escape: 27,
};
window.addEventListener('keydown', (ev) => {
  if (!cur || $('sheet').open || ev.metaKey || ev.altKey) return;
  const k = ev.key;
  if (ev.ctrlKey && (k === 'z' || k === 'Z')) { ev.preventDefault(); sendKey(ev.shiftKey ? BTN.uiRedo : BTN.uiUndo); return; }
  if (ev.ctrlKey && (k === 'y' || k === 'Y')) { ev.preventDefault(); sendKey(BTN.uiRedo); return; }
  if (ev.ctrlKey) return;
  if (k === 'n' || k === 'N') { ev.preventDefault(); newGame(); return; }
  if (k === 'q' || k === 'Q') return;
  let code = KEYMAP[k];
  if (code === undefined && k.length === 1 && k.charCodeAt(0) < 128) code = k.charCodeAt(0);
  if (code === undefined) return;
  if (ev.shiftKey && KEYMAP[k] && k.startsWith('Arrow')) code |= BTN.shift;
  ev.preventDefault();
  sendKey(code);
});

// ---- service worker / updates ----------------------------------------------
async function registerSW() {
  try {
    const reg = await navigator.serviceWorker.register('sw.js');
    const offer = (w) => {
      const t = $('toast');
      t.innerHTML = 'Update available — <u>tap to reload</u>';
      t.hidden = false;
      t.style.pointerEvents = 'auto';
      t.onclick = () => { saveNow(); w.postMessage('skipWaiting'); };
    };
    if (reg.waiting && navigator.serviceWorker.controller) offer(reg.waiting);
    reg.addEventListener('updatefound', () => {
      const w = reg.installing;
      w?.addEventListener('statechange', () => {
        if (w.state === 'installed' && navigator.serviceWorker.controller) offer(w);
      });
    });
    let reloading = false;
    navigator.serviceWorker.addEventListener('controllerchange', () => {
      if (reloading) return;
      reloading = true;
      location.reload();
    });
    // Check for updates when the app comes back to the foreground.
    document.addEventListener('visibilitychange', () => { if (!document.hidden) reg.update().catch(() => { }); });
  } catch { /* offline support unavailable */ }
}

// ---- wiring -----------------------------------------------------------------
function init() {
  board = new Board($('viewport'), $('board'), {
    primaryButton,
    longPress: () => settings.longPress,
    stylus: () => !!cur?.def.stylus,
    onInput: (r) => afterInput(r),
    onZoomChange: () => cur && updateUI(),
    onLongPress: (x, y) => {
      const ring = $('press-ring'), r = $('viewport').getBoundingClientRect();
      ring.style.left = (x - r.left) + 'px'; ring.style.top = (y - r.top) + 'px';
      ring.hidden = false;
      setTimeout(() => { ring.hidden = true; }, 350);
      navigator.vibrate?.(12);
    },
  });
  $('back').addEventListener('click', () => go(''));
  $('home-settings').addEventListener('click', openSettings);
  $('menu-btn').addEventListener('click', openMenu);
  $('title-btn').addEventListener('click', openTypes);
  $('undo').addEventListener('click', () => sendKey(BTN.uiUndo));
  $('redo').addEventListener('click', () => sendKey(BTN.uiRedo));
  $('zoom-in').addEventListener('click', () => { board.zoomIn(); updateUI(); });
  $('zoom-out').addEventListener('click', () => { board.zoomOut(); updateUI(); });
  $('banner-new').addEventListener('click', () => newGame());
  window.pzDebug = { board, get cur() { return cur; } };
  applyTheme();
  route();
  if ('serviceWorker' in navigator && location.protocol !== 'file:' && !['localhost', '127.0.0.1'].includes(location.hostname))
    registerSW();
}
init();
