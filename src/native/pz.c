/*
 * pz.c: handle-based native front end for the puzzle midend. See pz.h.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <math.h>

#ifdef __ANDROID__
#include <android/log.h>
#endif

#include "puzzles.h"
#include "pz.h"

/* ---- game list (needed by COMBINED builds) --------------------------- */

#define GAME(x) &x,
const game *gamelist[] = {
#include "generated-games.h"
};
#undef GAME
const int gamecount = lenof(gamelist);

int pz_game_count(void) { return gamecount; }
const char *pz_game_name_at(int i)
{
    return (i >= 0 && i < gamecount) ? gamelist[i]->htmlhelp_topic : NULL;
}

/* ---- per-instance state --------------------------------------------- */

struct frontend { struct pz *p; };

struct pz {
    struct frontend fe;
    const game *g;
    midend *me;
    pz_callbacks cb;
    bool drawing;
    bool timer_active;
    int fe_scale;
    int next_blitter_id;
    char *outbuf;
    size_t outlen, outsize;
    char *held;
};

/* ---- functions the midend expects of a front end ------------------- */

void get_random_seed(void **randseed, int *randseedsize)
{
    unsigned *ret = snewn(4, unsigned);
#if defined(__APPLE__) || defined(__ANDROID__) || defined(__OpenBSD__)
    arc4random_buf(ret, 4 * sizeof(unsigned));
#else
    {
        FILE *f = fopen("/dev/urandom", "rb");
        if (!f || fread(ret, sizeof(unsigned), 4, f) != 4)
            fatal("no random source");
        fclose(f);
    }
#endif
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
#ifdef __ANDROID__
    __android_log_print(ANDROID_LOG_FATAL, "puzzles", "%s", buf);
#else
    fprintf(stderr, "puzzles: fatal: %s\n", buf);
#endif
    abort();
}

#ifdef DEBUGGING
void debug_printf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
#ifdef __ANDROID__
    __android_log_vprint(ANDROID_LOG_DEBUG, "puzzles", fmt, ap);
#else
    vfprintf(stderr, fmt, ap);
#endif
    va_end(ap);
}
#endif

void frontend_default_colour(frontend *fe, float *output)
{
    /* Light grey background; hosts remap the palette per theme. */
    output[0] = output[1] = output[2] = 0.9F;
}

void activate_timer(frontend *fe)
{
    pz *p = fe->p;
    if (!p->timer_active) {
        p->timer_active = true;
        if (p->cb.timer) p->cb.timer(p->cb.ctx, 1);
    }
}

void deactivate_timer(frontend *fe)
{
    pz *p = fe->p;
    if (p->timer_active) {
        p->timer_active = false;
        if (p->cb.timer) p->cb.timer(p->cb.ctx, 0);
    }
}

/* ---- drawing API ---------------------------------------------------- */

#define P(dr) GET_HANDLE_AS_TYPE(dr, pz)
#define CB(dr) (P(dr)->cb)

static void d_text(drawing *dr, int x, int y, int fonttype, int fontsize,
                   int align, int colour, const char *text)
{
    CB(dr).text(CB(dr).ctx, x, y, fonttype, fontsize, align, colour, text);
}
static void d_rect(drawing *dr, int x, int y, int w, int h, int colour)
{
    CB(dr).rect(CB(dr).ctx, x, y, w, h, colour);
}
static void d_line(drawing *dr, int x1, int y1, int x2, int y2, int colour)
{
    CB(dr).line(CB(dr).ctx, x1, y1, x2, y2, 1, colour);
}
static void d_thick_line(drawing *dr, float t, float x1, float y1,
                         float x2, float y2, int colour)
{
    CB(dr).line(CB(dr).ctx, x1, y1, x2, y2, t, colour);
}
static void d_poly(drawing *dr, const int *coords, int npoints,
                   int fill, int outline)
{
    CB(dr).poly(CB(dr).ctx, coords, npoints, fill, outline);
}
static void d_circle(drawing *dr, int cx, int cy, int r, int fill,
                     int outline)
{
    CB(dr).circle(CB(dr).ctx, cx, cy, r, fill, outline);
}
static void d_update(drawing *dr, int x, int y, int w, int h)
{
    CB(dr).draw_update(CB(dr).ctx, x, y, w, h);
}
static void d_clip(drawing *dr, int x, int y, int w, int h)
{
    CB(dr).clip(CB(dr).ctx, x, y, w, h);
}
static void d_unclip(drawing *dr) { CB(dr).unclip(CB(dr).ctx); }
static void d_start(drawing *dr) { CB(dr).start_draw(CB(dr).ctx); }
static void d_end(drawing *dr) { CB(dr).end_draw(CB(dr).ctx); }
static void d_status(drawing *dr, const char *text)
{
    CB(dr).status(CB(dr).ctx, text);
}

struct blitter { int id; };

static blitter *d_blitter_new(drawing *dr, int w, int h)
{
    blitter *bl = snew(blitter);
    bl->id = P(dr)->next_blitter_id++;
    CB(dr).blitter_new(CB(dr).ctx, bl->id, w, h);
    return bl;
}
static void d_blitter_free(drawing *dr, blitter *bl)
{
    CB(dr).blitter_free(CB(dr).ctx, bl->id);
    sfree(bl);
}
static void d_blitter_save(drawing *dr, blitter *bl, int x, int y)
{
    CB(dr).blitter_save(CB(dr).ctx, bl->id, x, y);
}
static void d_blitter_load(drawing *dr, blitter *bl, int x, int y)
{
    CB(dr).blitter_load(CB(dr).ctx, bl->id, x, y);
}
static char *d_text_fallback(drawing *dr, const char *const *strings,
                             int nstrings)
{
    return dupstr(strings[0]);   /* hosts render UTF-8 */
}

static const struct drawing_api native_drawing = {
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

static void out_reset(pz *p) { p->outlen = 0; if (p->outbuf) p->outbuf[0] = 0; }
static void out_add(pz *p, const void *s, size_t n)
{
    if (p->outlen + n + 1 > p->outsize) {
        p->outsize = (p->outlen + n + 1) * 2;
        p->outbuf = sresize(p->outbuf, p->outsize, char);
    }
    memcpy(p->outbuf + p->outlen, s, n);
    p->outlen += n;
    p->outbuf[p->outlen] = 0;
}
static void out_str(pz *p, const char *s) { out_add(p, s, strlen(s)); }
static void out_write(void *ctx, const void *buf, int len)
{
    out_add((pz *)ctx, buf, len);
}
static const char *out_get(pz *p) { return p->outbuf ? p->outbuf : ""; }

/* Keep a midend-allocated string until the next call on this handle. */
static const char *hold(pz *p, char *s)
{
    sfree(p->held);
    p->held = s;
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

/* ---- lifecycle ------------------------------------------------------ */

pz *pz_new(const char *name, const pz_callbacks *cb)
{
    int i;
    const game *g = NULL;
    pz *p;

    for (i = 0; i < gamecount; i++)
        if (!strcmp(gamelist[i]->htmlhelp_topic, name) ||
            !strcmp(gamelist[i]->name, name))
            g = gamelist[i];
    if (!g) return NULL;

    p = snew(pz);
    memset(p, 0, sizeof(*p));
    p->fe.p = p;
    p->g = g;
    p->fe_scale = 1;
    p->next_blitter_id = 1;
    if (cb) { p->cb = *cb; p->drawing = true; }
    p->me = midend_new(&p->fe, g, p->drawing ? &native_drawing : NULL, p);
    return p;
}

void pz_free(pz *p)
{
    if (!p) return;
    midend_free(p->me);
    sfree(p->outbuf);
    sfree(p->held);
    sfree(p);
}

/* ---- game API ------------------------------------------------------- */

int pz_can_solve(pz *p) { return p->g->can_solve; }
int pz_wants_statusbar(pz *p) { return midend_wants_statusbar(p->me); }

static void list_presets(pz *p, struct preset_menu *menu, const char *prefix)
{
    int i;
    for (i = 0; i < menu->n_entries; i++) {
        struct preset_menu_entry *e = &menu->entries[i];
        if (e->params) {
            char *s = p->g->encode_params(e->params, true);
            out_str(p, prefix); out_str(p, e->title); out_str(p, "\t");
            out_str(p, s); out_str(p, "\n");
            sfree(s);
        } else {
            char *np = snewn(strlen(prefix) + strlen(e->title) + 4, char);
            sprintf(np, "%s%s / ", prefix, e->title);
            list_presets(p, e->submenu, np);
            sfree(np);
        }
    }
}
const char *pz_presets(pz *p)
{
    int n;
    out_reset(p);
    list_presets(p, midend_get_presets(p->me, &n), "");
    return out_get(p);
}

const char *pz_set_id(pz *p, const char *id)
{
    const char *err = midend_game_id(p->me, id);
    return err ? err : "";
}

void pz_new_game(pz *p) { midend_new_game(p->me); }
const char *pz_get_id(pz *p) { return hold(p, midend_get_game_id(p->me)); }

const char *pz_generate(pz *p, const char *params)
{
    if (midend_game_id(p->me, params)) return hold(p, NULL);
    midend_new_game(p->me);
    return hold(p, midend_get_game_id(p->me));
}

const char *pz_get_params(pz *p)
{
    char *seed = midend_get_random_seed(p->me), *hash;
    if (seed && (hash = strchr(seed, '#')) != NULL) {
        *hash = 0;
        return hold(p, seed);
    }
    sfree(seed);
    {
        char *id = midend_get_game_id(p->me), *colon = strchr(id, ':');
        if (colon) *colon = 0;
        return hold(p, id);
    }
}

const char *pz_save(pz *p)
{
    out_reset(p);
    midend_serialise(p->me, out_write, p);
    return out_get(p);
}

const char *pz_load(pz *p, const char *data)
{
    struct read_ctx c;
    const char *err;
    c.p = data; c.pos = 0; c.len = strlen(data);
    err = midend_deserialise(p->me, str_read, &c);
    return err ? err : "";
}

void pz_size(pz *p, int w, int h, double dpr, int out[3])
{
    pz_size_weighted(p, w, h, dpr, 1.0, out);
}

void pz_size_weighted(pz *p, int w, int h, double dpr, double weight, int out[3])
{
    /* weight > 1 makes each puzzle unit span more device pixels, so the
     * puzzle is laid out at a smaller tile size and drawn magnified:
     * fixed-width lines and outlines come out proportionally heavier. */
    double units = dpr * (weight > 1 ? weight : 1);
    double scale = dpr;
    p->fe_scale = 1;
    if (units >= 2) {
        p->fe_scale = (int)floor(units);
        scale = dpr / p->fe_scale;
    }
    w = (int)(w * dpr / p->fe_scale);
    h = (int)(h * dpr / p->fe_scale);
    midend_size(p->me, &w, &h, true, scale);
    out[0] = w * p->fe_scale;
    out[1] = h * p->fe_scale;
    out[2] = p->fe_scale;
}

void pz_redraw(pz *p) { midend_force_redraw(p->me); }
int pz_tilesize(pz *p) { return midend_tilesize(p->me); }

int pz_input(pz *p, int x, int y, int button)
{
    return midend_process_key(p->me, x, y, button);
}

void pz_timer(pz *p, double tplus)
{
    if (p->timer_active) midend_timer(p->me, tplus);
}
int pz_timer_active(pz *p) { return p->timer_active; }

const char *pz_key_label(pz *p, int button)
{
    const char *l = midend_current_key_label(p->me, button);
    return l ? l : "";
}

void pz_restart(pz *p) { midend_restart_game(p->me); }
const char *pz_solve(pz *p)
{
    const char *msg = midend_solve(p->me);
    return msg ? msg : "";
}
int pz_can_undo(pz *p) { return midend_can_undo(p->me); }
int pz_can_redo(pz *p) { return midend_can_redo(p->me); }
int pz_status(pz *p) { return midend_status(p->me); }
int pz_which_preset(pz *p) { return midend_which_preset(p->me); }

const char *pz_colours(pz *p)
{
    int i, n;
    float *c = midend_colours(p->me, &n);
    char buf[64];
    out_reset(p);
    for (i = 0; i < n; i++) {
        sprintf(buf, "%.4f %.4f %.4f\n", c[i*3], c[i*3+1], c[i*3+2]);
        out_str(p, buf);
    }
    sfree(c);
    return out_get(p);
}

const char *pz_keys(pz *p)
{
    int i, n;
    key_label *keys = midend_request_keys(p->me, &n);
    char buf[32];
    out_reset(p);
    for (i = 0; i < n; i++) {
        out_str(p, keys[i].label ? keys[i].label : "?");
        sprintf(buf, "\t%d\n", keys[i].button);
        out_str(p, buf);
    }
    free_keys(keys, n);
    return out_get(p);
}

/* ---- config --------------------------------------------------------- */

static void config_out(pz *p, config_item *cfg)
{
    config_item *i;
    char buf[32];
    out_reset(p);
    for (i = cfg; i->type != C_END; i++) {
        switch (i->type) {
          case C_STRING:
            out_str(p, "s\t"); out_str(p, i->name); out_str(p, "\t");
            out_str(p, i->u.string.sval); out_str(p, "\t\n");
            break;
          case C_BOOLEAN:
            out_str(p, "b\t"); out_str(p, i->name);
            out_str(p, i->u.boolean.bval ? "\t1\t\n" : "\t0\t\n");
            break;
          case C_CHOICES:
            out_str(p, "c\t"); out_str(p, i->name);
            sprintf(buf, "\t%d\t", i->u.choices.selected);
            out_str(p, buf); out_str(p, i->u.choices.choicenames);
            out_str(p, "\n");
            break;
        }
    }
}

/* Apply newline-separated values to a config array, in order. */
static void config_apply(config_item *cfg, const char *values)
{
    config_item *i;
    const char *v = values;
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
}

const char *pz_get_config(pz *p, int which)
{
    char *title;
    config_item *cfg = midend_get_config(p->me, which, &title);
    config_out(p, cfg);
    free_cfg(cfg);
    sfree(title);
    return out_get(p);
}

const char *pz_set_config(pz *p, int which, const char *values)
{
    char *title;
    config_item *cfg = midend_get_config(p->me, which, &title);
    const char *err;
    config_apply(cfg, values);
    err = midend_set_config(p->me, which, cfg);
    free_cfg(cfg);
    sfree(title);
    return err ? err : "";
}

const char *pz_save_prefs(pz *p)
{
    out_reset(p);
    midend_save_prefs(p->me, out_write, p);
    return out_get(p);
}

const char *pz_load_prefs(pz *p, const char *data)
{
    struct read_ctx c;
    const char *err;
    c.p = data; c.pos = 0; c.len = strlen(data);
    err = midend_load_prefs(p->me, str_read, &c);
    return err ? err : "";
}

const char *pz_params_config(pz *p, const char *params)
{
    game_params *gp = p->g->default_params();
    config_item *cfg;
    p->g->decode_params(gp, params);
    cfg = p->g->configure(gp);
    config_out(p, cfg);
    free_cfg(cfg);
    p->g->free_params(gp);
    return out_get(p);
}

const char *pz_config_params(pz *p, const char *base, const char *values)
{
    game_params *gp = p->g->default_params(), *np;
    config_item *cfg;
    const char *err;
    char *enc;

    p->g->decode_params(gp, base);
    cfg = p->g->configure(gp);
    config_apply(cfg, values);
    np = p->g->custom_params(cfg);
    free_cfg(cfg);
    p->g->free_params(gp);
    err = p->g->validate_params(np, true);
    out_reset(p);
    if (err) {
        out_str(p, "!"); out_str(p, err);
    } else {
        enc = p->g->encode_params(np, true);
        out_str(p, "="); out_str(p, enc);
        sfree(enc);
    }
    p->g->free_params(np);
    return out_get(p);
}
