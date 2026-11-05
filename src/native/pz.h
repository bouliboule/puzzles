/*
 * pz.h: a small, handle-based C API over the puzzle midend, for native
 * front ends (Android via JNI, iOS via Swift). The same idea as
 * src/frontend.c (the WebAssembly build), but with any number of
 * independent puzzle instances and drawing done through a callback
 * table supplied by the host.
 *
 * Build with -DCOMBINED and all the game sources linked in.
 *
 * Strings returned as `const char *` belong to the handle and stay
 * valid until the next call on the same handle. A handle must only be
 * used from one thread at a time; different handles may be used from
 * different threads concurrently.
 */
#ifndef PZ_H
#define PZ_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct pz pz;

/* Drawing callbacks. Coordinates are in puzzle units; the host scales
 * them by fe_scale (see pz_size). Colours are palette indices. */
typedef struct pz_callbacks {
    void *ctx;
    void (*start_draw)(void *ctx);
    void (*end_draw)(void *ctx);
    void (*draw_update)(void *ctx, int x, int y, int w, int h);
    void (*rect)(void *ctx, int x, int y, int w, int h, int colour);
    void (*line)(void *ctx, float x1, float y1, float x2, float y2,
                 float width, int colour);
    void (*poly)(void *ctx, const int *coords, int npoints, int fill,
                 int outline);
    void (*circle)(void *ctx, int x, int y, int r, int fill, int outline);
    void (*text)(void *ctx, int x, int y, int fonttype, int fontsize,
                 int align, int colour, const char *text);
    void (*clip)(void *ctx, int x, int y, int w, int h);
    void (*unclip)(void *ctx);
    void (*status)(void *ctx, const char *text);
    void (*blitter_new)(void *ctx, int id, int w, int h);
    void (*blitter_free)(void *ctx, int id);
    void (*blitter_save)(void *ctx, int id, int x, int y);
    void (*blitter_load)(void *ctx, int id, int x, int y);
    /* Animation/flash timer wanted (1) or no longer wanted (0). The
     * host calls pz_timer(elapsed seconds) every frame while on. */
    void (*timer)(void *ctx, int active);
} pz_callbacks;

/* Game names: "loopy", "bridges", ... Returns NULL if unknown.
 * cb == NULL makes a drawing-less instance (for generating puzzles). */
pz *pz_new(const char *name, const pz_callbacks *cb);
void pz_free(pz *p);

int pz_game_count(void);
const char *pz_game_name_at(int i);

int pz_can_solve(pz *p);
int pz_wants_statusbar(pz *p);
const char *pz_presets(pz *p);             /* "title\tparams\n" lines */
const char *pz_set_id(pz *p, const char *id);  /* error or "" */
void pz_new_game(pz *p);
const char *pz_get_id(pz *p);
const char *pz_generate(pz *p, const char *params); /* "" on error */
const char *pz_get_params(pz *p);
const char *pz_save(pz *p);
const char *pz_load(pz *p, const char *data);  /* error or "" */

/* Fit the puzzle into w x h logical pixels at device pixel ratio dpr.
 * out[0], out[1]: bitmap size in device pixels; out[2]: fe_scale
 * (device pixels per puzzle unit). */
void pz_size(pz *p, int w, int h, double dpr, int out[3]);
void pz_redraw(pz *p);
int pz_tilesize(pz *p);
int pz_input(pz *p, int x, int y, int button);
void pz_timer(pz *p, double tplus);
int pz_timer_active(pz *p);
const char *pz_key_label(pz *p, int button);
void pz_restart(pz *p);
const char *pz_solve(pz *p);               /* error or "" */
int pz_can_undo(pz *p);
int pz_can_redo(pz *p);
int pz_status(pz *p);
int pz_which_preset(pz *p);
const char *pz_colours(pz *p);             /* "r g b\n" floats */
const char *pz_keys(pz *p);                /* "label\tbutton\n" */

/* Config dialogs: which = 0 (CFG_SETTINGS) or 3 (CFG_PREFS). Lines
 * "type\tname\tvalue\tchoices"; values are set one per line. */
const char *pz_get_config(pz *p, int which);
const char *pz_set_config(pz *p, int which, const char *values);
const char *pz_save_prefs(pz *p);
const char *pz_load_prefs(pz *p, const char *data);
const char *pz_params_config(pz *p, const char *params);
/* "=params" on success or "!error". */
const char *pz_config_params(pz *p, const char *base, const char *values);

#ifdef __cplusplus
}
#endif
#endif
