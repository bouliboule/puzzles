/*
 * frontend.c: a small WebAssembly front end for Simon Tatham's
 * Portable Puzzle Collection, designed to be driven entirely from
 * JavaScript (see web/js/engine.js). Every exported function is
 * prefixed pz_. Drawing calls go out through the js_* imports defined
 * in src/library.js, which forward them to Module.fe (a JS object
 * supplied by the page). Without Module.fe (e.g. in the generator
 * worker) the module can still generate puzzles.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <math.h>
#include <emscripten.h>

#include "puzzles.h"

#define EXPORT EMSCRIPTEN_KEEPALIVE

/* ---- imports from library.js ---------------------------------------- */
extern void js_get_seed(unsigned *p);
extern void js_fatal(const char *msg);
extern void js_activate_timer(void);
extern void js_deactivate_timer(void);
extern void js_set_size(int w, int h, int fe_scale);
extern void js_start_draw(void);
extern void js_end_draw(void);
extern void js_draw_update(int x, int y, int w, int h);
extern void js_draw_rect(int x, int y, int w, int h, int colour);
extern void js_draw_line(float x1, float y1, float x2, float y2,
                         float width, int colour);
extern void js_draw_poly(const int *points, int npoints, int fill,
                         int outline);
extern void js_draw_circle(int x, int y, int r, int fill, int outline);
extern void js_draw_text(int x, int y, int fonttype, int fontsize,
                         int align, int colour, const char *text);
extern void js_clip(int x, int y, int w, int h);
extern void js_unclip(void);
extern void js_status_bar(const char *text);
extern void js_blitter_new(int id, int w, int h);
extern void js_blitter_free(int id);
extern void js_blitter_save(int id, int x, int y);
extern void js_blitter_load(int id, int x, int y);

static midend *me;
static bool timer_active;
static int fe_scale = 1;

/* ---- functions the midend expects of a front end ------------------- */

void get_random_seed(void **randseed, int *randseedsize)
{
    unsigned *ret = snewn(4, unsigned);
    js_get_seed(ret);
    *randseed = ret;
    *randseedsize = 4 * sizeof(unsigned);
}

void fatal(const char *fmt, ...)
{
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    js_fatal(buf);
    abort();
}

#ifdef DEBUGGING
void debug_printf(const char *fmt, ...)
{
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    emscripten_log(EM_LOG_CONSOLE, "%s", buf);
}
#endif

void frontend_default_colour(frontend *fe, float *output)
{
    /* Light grey background, as on the desktop versions. The JS side
     * remaps the palette for e-ink / dark themes. */
    output[0] = output[1] = output[2] = 0.9F;
}

void activate_timer(frontend *fe)
{
    if (!timer_active) {
        timer_active = true;
        js_activate_timer();
    }
}

void deactivate_timer(frontend *fe)
{
    if (timer_active) {
        timer_active = false;
        js_deactivate_timer();
    }
}

/* ---- drawing API ---------------------------------------------------- */

static void d_text(drawing *dr, int x, int y, int fonttype, int fontsize,
                   int align, int colour, const char *text)
{
    js_draw_text(x, y, fonttype, fontsize, align, colour, text);
}
static void d_rect(drawing *dr, int x, int y, int w, int h, int colour)
{
    js_draw_rect(x, y, w, h, colour);
}
static void d_line(drawing *dr, int x1, int y1, int x2, int y2, int colour)
{
    js_draw_line(x1, y1, x2, y2, 1, colour);
}
static void d_thick_line(drawing *dr, float t, float x1, float y1,
                         float x2, float y2, int colour)
{
    js_draw_line(x1, y1, x2, y2, t, colour);
}
static void d_poly(drawing *dr, const int *coords, int npoints,
                   int fill, int outline)
{
    js_draw_poly(coords, npoints, fill, outline);
}
static void d_circle(drawing *dr, int cx, int cy, int r, int fill,
                     int outline)
{
    js_draw_circle(cx, cy, r, fill, outline);
}
static void d_update(drawing *dr, int x, int y, int w, int h)
{
    js_draw_update(x, y, w, h);
}
static void d_clip(drawing *dr, int x, int y, int w, int h)
{
    js_clip(x, y, w, h);
}
static void d_unclip(drawing *dr) { js_unclip(); }
static void d_start(drawing *dr) { js_start_draw(); }
static void d_end(drawing *dr) { js_end_draw(); }
static void d_status(drawing *dr, const char *text) { js_status_bar(text); }

struct blitter { int id; };
static int next_blitter_id = 1;

static blitter *d_blitter_new(drawing *dr, int w, int h)
{
    blitter *bl = snew(blitter);
    bl->id = next_blitter_id++;
    js_blitter_new(bl->id, w, h);
    return bl;
}
static void d_blitter_free(drawing *dr, blitter *bl)
{
    js_blitter_free(bl->id);
    sfree(bl);
}
static void d_blitter_save(drawing *dr, blitter *bl, int x, int y)
{
    js_blitter_save(bl->id, x, y);
}
static void d_blitter_load(drawing *dr, blitter *bl, int x, int y)
{
    js_blitter_load(bl->id, x, y);
}
static char *d_text_fallback(drawing *dr, const char *const *strings,
                             int nstrings)
{
    return dupstr(strings[0]);
}

static const struct drawing_api js_drawing = {
    1,
    d_text, d_rect, d_line, d_poly, d_circle, d_update, d_clip, d_unclip,
    d_start, d_end, d_status,
    d_blitter_new, d_blitter_free, d_blitter_save, d_blitter_load,
    NULL, NULL, NULL, NULL, NULL, NULL, /* {begin,end}_{doc,page,puzzle} */
    NULL, NULL,                         /* line_width, line_dotted */
    d_text_fallback,
    d_thick_line,
};

/* ---- string helpers ------------------------------------------------- */

/* Growable string buffer for returning text to JS. */
static char *outbuf;
static size_t outlen, outsize;

static void out_reset(void) { outlen = 0; if (outbuf) outbuf[0] = 0; }
static void out_add(const void *p, size_t n)
{
    if (outlen + n + 1 > outsize) {
        outsize = (outlen + n + 1) * 2;
        outbuf = sresize(outbuf, outsize, char);
    }
    memcpy(outbuf + outlen, p, n);
    outlen += n;
    outbuf[outlen] = 0;
}
static void out_str(const char *s) { out_add(s, strlen(s)); }
static void out_write(void *ctx, const void *buf, int len)
{
    out_add(buf, len);
}
static const char *out_get(void) { return outbuf ? outbuf : ""; }

/* Replace a temporary string held for JS (freed on next call). */
static char *held;
static const char *hold(char *s)
{
    sfree(held);
    held = s;
    return s ? s : "";
}

struct read_ctx { const char *p; size_t pos, len; };
static bool str_read(void *vctx, void *buf, int len)
{
    struct read_ctx *c = (struct read_ctx *)vctx;
    if (len < 0 || c->len - c->pos < (size_t)len) return false;
    memcpy(buf, c->p + c->pos, len);
    c->pos += len;
    return true;
}

/* ---- exported API --------------------------------------------------- */

EXPORT void pz_init(int with_drawing)
{
    me = midend_new(NULL, &thegame, with_drawing ? &js_drawing : NULL, NULL);
}

EXPORT const char *pz_game_name(void) { return thegame.name; }
EXPORT int pz_can_solve(void) { return thegame.can_solve; }
EXPORT int pz_wants_statusbar(void) { return midend_wants_statusbar(me); }

/* Presets, flattened, as "title\tparams\n" lines. */
static void list_presets(struct preset_menu *menu, const char *prefix)
{
    int i;
    for (i = 0; i < menu->n_entries; i++) {
        struct preset_menu_entry *e = &menu->entries[i];
        if (e->params) {
            char *p = thegame.encode_params(e->params, true);
            out_str(prefix); out_str(e->title); out_str("\t");
            out_str(p); out_str("\n");
            sfree(p);
        } else {
            char *np = snewn(strlen(prefix) + strlen(e->title) + 4, char);
            sprintf(np, "%s%s / ", prefix, e->title);
            list_presets(e->submenu, np);
            sfree(np);
        }
    }
}
EXPORT const char *pz_presets(void)
{
    int n;
    out_reset();
    list_presets(midend_get_presets(me, &n), "");
    return out_get();
}

/* Set params or a full game ID ("params", "params:desc" or
 * "params#seed"). Returns an error string or "". Does not start the
 * game: call pz_new_game() afterwards. */
EXPORT const char *pz_set_id(const char *id)
{
    const char *err = midend_game_id(me, id);
    return err ? err : "";
}

EXPORT void pz_new_game(void) { midend_new_game(me); }

EXPORT const char *pz_get_id(void) { return hold(midend_get_game_id(me)); }

/* Generate a game for the given full params; returns "params:desc".
 * Used by the background worker. */
EXPORT const char *pz_generate(const char *params)
{
    const char *err = midend_game_id(me, params);
    if (err) { hold(NULL); return ""; }
    midend_new_game(me);
    return hold(midend_get_game_id(me));
}

/* Encode the current parameters in full (including difficulty). */
EXPORT const char *pz_get_params(void)
{
    char *seed = midend_get_random_seed(me), *hash;
    if (seed && (hash = strchr(seed, '#')) != NULL) {
        *hash = 0;
        return hold(seed);
    }
    sfree(seed);
    {
        char *id = midend_get_game_id(me), *colon = strchr(id, ':');
        if (colon) *colon = 0;
        return hold(id);
    }
}

EXPORT const char *pz_save(void)
{
    out_reset();
    midend_serialise(me, out_write, NULL);
    return out_get();
}

EXPORT const char *pz_load(const char *data)
{
    struct read_ctx c;
    const char *err;
    c.p = data; c.pos = 0; c.len = strlen(data);
    err = midend_deserialise(me, str_read, &c);
    return err ? err : "";
}

/* Size the puzzle to fit (w,h) CSS pixels at the given device pixel
 * ratio. Calls js_set_size with the device-pixel canvas size. */
EXPORT void pz_size(int w, int h, double dpr)
{
    double scale = dpr;
    fe_scale = 1;
    if (dpr >= 2) {
        fe_scale = (int)floor(dpr);
        scale = dpr / fe_scale;
    }
    w = (int)(w * dpr / fe_scale);
    h = (int)(h * dpr / fe_scale);
    midend_size(me, &w, &h, true, scale);
    js_set_size(w * fe_scale, h * fe_scale, fe_scale);
}

EXPORT void pz_redraw(void) { midend_force_redraw(me); }
EXPORT int pz_tilesize(void) { return midend_tilesize(me); }

EXPORT int pz_input(int x, int y, int button)
{
    return midend_process_key(me, x, y, button);
}

EXPORT void pz_timer(double tplus)
{
    if (timer_active) midend_timer(me, tplus);
}
EXPORT const char *pz_key_label(int button)
{
    const char *l = midend_current_key_label(me, button);
    return l ? l : "";
}

EXPORT int pz_timer_active(void) { return timer_active; }

EXPORT void pz_restart(void) { midend_restart_game(me); }
EXPORT const char *pz_solve(void)
{
    const char *msg = midend_solve(me);
    return msg ? msg : "";
}
EXPORT int pz_can_undo(void) { return midend_can_undo(me); }
EXPORT int pz_can_redo(void) { return midend_can_redo(me); }
EXPORT int pz_status(void) { return midend_status(me); }
EXPORT int pz_which_preset(void) { return midend_which_preset(me); }

/* Colours as "r g b\n" floats. */
EXPORT const char *pz_colours(void)
{
    int i, n;
    float *c = midend_colours(me, &n);
    char buf[64];
    out_reset();
    for (i = 0; i < n; i++) {
        sprintf(buf, "%.4f %.4f %.4f\n", c[i*3], c[i*3+1], c[i*3+2]);
        out_str(buf);
    }
    sfree(c);
    return out_get();
}

/* On-screen keys the game wants, "label\tbutton\n". */
EXPORT const char *pz_keys(void)
{
    int i, n;
    key_label *keys = midend_request_keys(me, &n);
    char buf[32];
    out_reset();
    for (i = 0; i < n; i++) {
        out_str(keys[i].label ? keys[i].label : "?");
        sprintf(buf, "\t%d\n", keys[i].button);
        out_str(buf);
    }
    free_keys(keys, n);
    return out_get();
}

/*
 * Config dialogs (which = CFG_SETTINGS or CFG_PREFS). Serialised as
 * lines "type\tname\tvalue\tchoices" with type s/b/c; choices use
 * the puzzle's own ":a:b:c" syntax.
 */
static void config_out(config_item *cfg);
EXPORT const char *pz_get_config(int which)
{
    char *title;
    config_item *cfg = midend_get_config(me, which, &title);
    config_out(cfg);
    free_cfg(cfg);
    sfree(title);
    return out_get();
}

/* values: one per line, in the same order as pz_get_config. */
EXPORT const char *pz_set_config(int which, const char *values)
{
    char *title;
    config_item *cfg = midend_get_config(me, which, &title), *i;
    const char *p = values, *err;
    for (i = cfg; i->type != C_END && *p; i++) {
        const char *nl = strchr(p, '\n');
        size_t len = nl ? (size_t)(nl - p) : strlen(p);
        char *v = snewn(len + 1, char);
        memcpy(v, p, len); v[len] = 0;
        switch (i->type) {
          case C_STRING:
            sfree(i->u.string.sval);
            i->u.string.sval = v; v = NULL;
            break;
          case C_BOOLEAN: i->u.boolean.bval = atoi(v) != 0; break;
          case C_CHOICES: i->u.choices.selected = atoi(v); break;
        }
        sfree(v);
        p = nl ? nl + 1 : p + len;
    }
    err = midend_set_config(me, which, cfg);
    free_cfg(cfg);
    sfree(title);
    return err ? err : "";
}

EXPORT const char *pz_save_prefs(void)
{
    out_reset();
    midend_save_prefs(me, out_write, NULL);
    return out_get();
}

EXPORT const char *pz_load_prefs(const char *data)
{
    struct read_ctx c;
    const char *err;
    c.p = data; c.pos = 0; c.len = strlen(data);
    err = midend_load_prefs(me, str_read, &c);
    return err ? err : "";
}

EXPORT const char *pz_text_format(void)
{
    return hold(thegame.can_format_as_text_ever ?
                midend_text_format(me) : NULL);
}

/* Serialise the configuration of an arbitrary (full) params string,
 * in the same format as pz_get_config. */
static void config_out(config_item *cfg)
{
    config_item *i;
    char buf[32];
    out_reset();
    for (i = cfg; i->type != C_END; i++) {
        switch (i->type) {
          case C_STRING:
            out_str("s\t"); out_str(i->name); out_str("\t");
            out_str(i->u.string.sval); out_str("\t\n");
            break;
          case C_BOOLEAN:
            out_str("b\t"); out_str(i->name);
            out_str(i->u.boolean.bval ? "\t1\t\n" : "\t0\t\n");
            break;
          case C_CHOICES:
            out_str("c\t"); out_str(i->name);
            sprintf(buf, "\t%d\t", i->u.choices.selected);
            out_str(buf); out_str(i->u.choices.choicenames);
            out_str("\n");
            break;
        }
    }
}

EXPORT const char *pz_params_config(const char *params)
{
    game_params *p = thegame.default_params();
    config_item *cfg;
    thegame.decode_params(p, params);
    cfg = thegame.configure(p);
    config_out(cfg);
    free_cfg(cfg);
    thegame.free_params(p);
    return out_get();
}

/* Convert config values (as for pz_set_config) into a full params
 * string. Returns "=params" on success or "!error". */
EXPORT const char *pz_config_params(const char *base, const char *values)
{
    game_params *p = thegame.default_params(), *np;
    config_item *cfg, *i;
    const char *v = values, *err;
    char *enc;

    thegame.decode_params(p, base);
    cfg = thegame.configure(p);
    for (i = cfg; i->type != C_END && *v; i++) {
        const char *nl = strchr(v, '\n');
        size_t len = nl ? (size_t)(nl - v) : strlen(v);
        char *s = snewn(len + 1, char);
        memcpy(s, v, len); s[len] = 0;
        switch (i->type) {
          case C_STRING:
            sfree(i->u.string.sval);
            i->u.string.sval = s; s = NULL;
            break;
          case C_BOOLEAN: i->u.boolean.bval = atoi(s) != 0; break;
          case C_CHOICES: i->u.choices.selected = atoi(s); break;
        }
        sfree(s);
        v = nl ? nl + 1 : v + len;
    }
    np = thegame.custom_params(cfg);
    free_cfg(cfg);
    thegame.free_params(p);
    err = thegame.validate_params(np, true);
    out_reset();
    if (err) {
        out_str("!"); out_str(err);
    } else {
        enc = thegame.encode_params(np, true);
        out_str("="); out_str(enc);
        sfree(enc);
    }
    thegame.free_params(np);
    return out_get();
}
