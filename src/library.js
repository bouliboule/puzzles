// Emscripten JS library: imports for src/frontend.c. Everything is
// forwarded to Module.fe, an object supplied by web/js/engine.js.
addToLibrary({
  js_get_seed: function (p) {
    var a = new Uint32Array(4);
    if (globalThis.crypto && crypto.getRandomValues) crypto.getRandomValues(a);
    else for (var i = 0; i < 4; i++) a[i] = (Math.random() * 4294967296) >>> 0;
    for (var j = 0; j < 4; j++) HEAPU32[(p >> 2) + j] = a[j];
  },
  js_fatal__deps: ['$UTF8ToString'],
  js_fatal: function (msg) {
    var s = UTF8ToString(msg);
    if (Module.fe && Module.fe.fatal) Module.fe.fatal(s);
    else console.error(s);
  },
  js_activate_timer: function () { Module.fe && Module.fe.activateTimer(); },
  js_deactivate_timer: function () { Module.fe && Module.fe.deactivateTimer(); },
  js_set_size: function (w, h, s) { Module.fe.setSize(w, h, s); },
  js_start_draw: function () { Module.fe.startDraw(); },
  js_end_draw: function () { Module.fe.endDraw(); },
  js_draw_update: function (x, y, w, h) { Module.fe.drawUpdate(x, y, w, h); },
  js_draw_rect: function (x, y, w, h, c) { Module.fe.rect(x, y, w, h, c); },
  js_draw_line: function (x1, y1, x2, y2, w, c) { Module.fe.line(x1, y1, x2, y2, w, c); },
  js_draw_poly: function (p, n, fill, outline) {
    var pts = HEAP32.subarray(p >> 2, (p >> 2) + 2 * n);
    Module.fe.poly(pts, n, fill, outline);
  },
  js_draw_circle: function (x, y, r, f, o) { Module.fe.circle(x, y, r, f, o); },
  js_draw_text__deps: ['$UTF8ToString'],
  js_draw_text: function (x, y, ft, fs, al, c, t) {
    Module.fe.text(x, y, ft, fs, al, c, UTF8ToString(t));
  },
  js_clip: function (x, y, w, h) { Module.fe.clip(x, y, w, h); },
  js_unclip: function () { Module.fe.unclip(); },
  js_status_bar__deps: ['$UTF8ToString'],
  js_status_bar: function (t) { Module.fe.status(UTF8ToString(t)); },
  js_blitter_new: function (id, w, h) { Module.fe.blitterNew(id, w, h); },
  js_blitter_free: function (id) { Module.fe.blitterFree(id); },
  js_blitter_save: function (id, x, y) { Module.fe.blitterSave(id, x, y); },
  js_blitter_load: function (id, x, y) { Module.fe.blitterLoad(id, x, y); },
});
