/*
 * jni.c: binds src/native/pz.h to io.ricca.puzzles.Native. Drawing
 * callbacks are forwarded to an io.ricca.puzzles.Renderer object.
 *
 * Every Native method takes the handle returned by create(). Drawing
 * only ever happens inside a call into native code on the same thread,
 * so the JNIEnv of the current call is stashed in the handle.
 */
#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include "pz.h"

typedef struct {
    pz *p;
    JNIEnv *env;
    jobject renderer;   /* global ref, or NULL */
    jintArray polybuf;  /* global ref, grown as needed */
    int polylen;
} jpz;

static struct {
    jmethodID start, end, update, rect, line, poly, circle, text, clip,
        unclip, status, bnew, bfree, bsave, bload, timer;
} M;

#define J(ctx) ((jpz *)(ctx))
#define CALL(ctx, m, ...) \
    (*J(ctx)->env)->CallVoidMethod(J(ctx)->env, J(ctx)->renderer, M.m, ##__VA_ARGS__)

static void cb_start(void *c) { CALL(c, start); }
static void cb_end(void *c) { CALL(c, end); }
static void cb_update(void *c, int x, int y, int w, int h) { CALL(c, update, x, y, w, h); }
static void cb_rect(void *c, int x, int y, int w, int h, int col) { CALL(c, rect, x, y, w, h, col); }
static void cb_line(void *c, float x1, float y1, float x2, float y2, float w, int col)
{
    CALL(c, line, x1, y1, x2, y2, w, col);
}
static void cb_poly(void *c, const int *pts, int n, int fill, int outline)
{
    jpz *j = J(c);
    JNIEnv *env = j->env;
    if (j->polylen < 2 * n) {
        if (j->polybuf) (*env)->DeleteGlobalRef(env, j->polybuf);
        j->polylen = 2 * n < 64 ? 64 : 2 * n;
        jintArray a = (*env)->NewIntArray(env, j->polylen);
        j->polybuf = (*env)->NewGlobalRef(env, a);
        (*env)->DeleteLocalRef(env, a);
    }
    (*env)->SetIntArrayRegion(env, j->polybuf, 0, 2 * n, pts);
    CALL(c, poly, j->polybuf, n, fill, outline);
}
static void cb_circle(void *c, int x, int y, int r, int fill, int outline)
{
    CALL(c, circle, x, y, r, fill, outline);
}
static void cb_text(void *c, int x, int y, int ft, int fs, int al, int col, const char *t)
{
    JNIEnv *env = J(c)->env;
    jstring s = (*env)->NewStringUTF(env, t);
    CALL(c, text, x, y, ft, fs, al, col, s);
    (*env)->DeleteLocalRef(env, s);
}
static void cb_clip(void *c, int x, int y, int w, int h) { CALL(c, clip, x, y, w, h); }
static void cb_unclip(void *c) { CALL(c, unclip); }
static void cb_status(void *c, const char *t)
{
    JNIEnv *env = J(c)->env;
    jstring s = (*env)->NewStringUTF(env, t);
    CALL(c, status, s);
    (*env)->DeleteLocalRef(env, s);
}
static void cb_bnew(void *c, int id, int w, int h) { CALL(c, bnew, id, w, h); }
static void cb_bfree(void *c, int id) { CALL(c, bfree, id); }
static void cb_bsave(void *c, int id, int x, int y) { CALL(c, bsave, id, x, y); }
static void cb_bload(void *c, int id, int x, int y) { CALL(c, bload, id, x, y); }
static void cb_timer(void *c, int on) { CALL(c, timer, (jboolean)(on != 0)); }

static void cache_methods(JNIEnv *env, jclass cls)
{
    M.start = (*env)->GetMethodID(env, cls, "startDraw", "()V");
    M.end = (*env)->GetMethodID(env, cls, "endDraw", "()V");
    M.update = (*env)->GetMethodID(env, cls, "drawUpdate", "(IIII)V");
    M.rect = (*env)->GetMethodID(env, cls, "rect", "(IIIII)V");
    M.line = (*env)->GetMethodID(env, cls, "line", "(FFFFFI)V");
    M.poly = (*env)->GetMethodID(env, cls, "poly", "([IIII)V");
    M.circle = (*env)->GetMethodID(env, cls, "circle", "(IIIII)V");
    M.text = (*env)->GetMethodID(env, cls, "text", "(IIIIIILjava/lang/String;)V");
    M.clip = (*env)->GetMethodID(env, cls, "clip", "(IIII)V");
    M.unclip = (*env)->GetMethodID(env, cls, "unclip", "()V");
    M.status = (*env)->GetMethodID(env, cls, "status", "(Ljava/lang/String;)V");
    M.bnew = (*env)->GetMethodID(env, cls, "blitterNew", "(III)V");
    M.bfree = (*env)->GetMethodID(env, cls, "blitterFree", "(I)V");
    M.bsave = (*env)->GetMethodID(env, cls, "blitterSave", "(III)V");
    M.bload = (*env)->GetMethodID(env, cls, "blitterLoad", "(III)V");
    M.timer = (*env)->GetMethodID(env, cls, "timer", "(Z)V");
}

/* ---- helpers -------------------------------------------------------- */

#define FN(name) Java_io_ricca_puzzles_Native_##name
#define H(h) ((jpz *)(intptr_t)(h))
#define ENTER(h) jpz *j = H(h); j->env = env

static jstring S(JNIEnv *env, const char *s) { return (*env)->NewStringUTF(env, s ? s : ""); }

/* Call f(p, cstr) with a Java string argument. */
#define WITH_STR(js, cs, body) do { \
    const char *cs = (*env)->GetStringUTFChars(env, js, NULL); \
    body; \
    (*env)->ReleaseStringUTFChars(env, js, cs); \
} while (0)

/* ---- lifecycle ------------------------------------------------------ */

JNIEXPORT jlong JNICALL FN(create)(JNIEnv *env, jclass cls, jstring jname, jobject renderer)
{
    jpz *j = calloc(1, sizeof(jpz));
    pz_callbacks cb = {
        j, cb_start, cb_end, cb_update, cb_rect, cb_line, cb_poly,
        cb_circle, cb_text, cb_clip, cb_unclip, cb_status, cb_bnew,
        cb_bfree, cb_bsave, cb_bload, cb_timer,
    };
    j->env = env;
    if (renderer) {
        jclass rc = (*env)->GetObjectClass(env, renderer);
        if (!M.start) cache_methods(env, rc);
        (*env)->DeleteLocalRef(env, rc);
        j->renderer = (*env)->NewGlobalRef(env, renderer);
    }
    WITH_STR(jname, name, j->p = pz_new(name, renderer ? &cb : NULL));
    if (!j->p) {
        if (j->renderer) (*env)->DeleteGlobalRef(env, j->renderer);
        free(j);
        return 0;
    }
    return (jlong)(intptr_t)j;
}

JNIEXPORT void JNICALL FN(destroy)(JNIEnv *env, jclass cls, jlong h)
{
    ENTER(h);
    pz_free(j->p);
    if (j->renderer) (*env)->DeleteGlobalRef(env, j->renderer);
    if (j->polybuf) (*env)->DeleteGlobalRef(env, j->polybuf);
    free(j);
}

/* ---- simple wrappers ------------------------------------------------ */

#define STR0(jname, cname) \
    JNIEXPORT jstring JNICALL FN(jname)(JNIEnv *env, jclass cls, jlong h) \
    { ENTER(h); return S(env, cname(j->p)); }
#define STR1(jname, cname) \
    JNIEXPORT jstring JNICALL FN(jname)(JNIEnv *env, jclass cls, jlong h, jstring a) \
    { ENTER(h); jstring r; WITH_STR(a, s, r = S(env, cname(j->p, s))); return r; }
#define INT0(jname, cname) \
    JNIEXPORT jint JNICALL FN(jname)(JNIEnv *env, jclass cls, jlong h) \
    { ENTER(h); return cname(j->p); }
#define VOID0(jname, cname) \
    JNIEXPORT void JNICALL FN(jname)(JNIEnv *env, jclass cls, jlong h) \
    { ENTER(h); cname(j->p); }

INT0(canSolve, pz_can_solve)
INT0(wantsStatusbar, pz_wants_statusbar)
STR0(presets, pz_presets)
STR1(setId, pz_set_id)
VOID0(newGame, pz_new_game)
STR0(getId, pz_get_id)
STR1(generate, pz_generate)
STR0(getParams, pz_get_params)
STR0(save, pz_save)
STR1(load, pz_load)
VOID0(redraw, pz_redraw)
INT0(tilesize, pz_tilesize)
INT0(timerActive, pz_timer_active)
VOID0(restart, pz_restart)
STR0(solve, pz_solve)
INT0(canUndo, pz_can_undo)
INT0(canRedo, pz_can_redo)
INT0(status, pz_status)
INT0(whichPreset, pz_which_preset)
STR0(colours, pz_colours)
STR0(keys, pz_keys)
STR0(savePrefs, pz_save_prefs)
STR1(loadPrefs, pz_load_prefs)
STR1(paramsConfig, pz_params_config)

JNIEXPORT jintArray JNICALL FN(size)(JNIEnv *env, jclass cls, jlong h, jint w, jint hh, jdouble dpr)
{
    ENTER(h);
    int out[3];
    jintArray a;
    pz_size(j->p, w, hh, dpr, out);
    a = (*env)->NewIntArray(env, 3);
    (*env)->SetIntArrayRegion(env, a, 0, 3, out);
    return a;
}

JNIEXPORT jint JNICALL FN(input)(JNIEnv *env, jclass cls, jlong h, jint x, jint y, jint b)
{
    ENTER(h);
    return pz_input(j->p, x, y, b);
}

JNIEXPORT void JNICALL FN(timer)(JNIEnv *env, jclass cls, jlong h, jdouble t)
{
    ENTER(h);
    pz_timer(j->p, t);
}

JNIEXPORT jstring JNICALL FN(keyLabel)(JNIEnv *env, jclass cls, jlong h, jint b)
{
    ENTER(h);
    return S(env, pz_key_label(j->p, b));
}

JNIEXPORT jstring JNICALL FN(getConfig)(JNIEnv *env, jclass cls, jlong h, jint which)
{
    ENTER(h);
    return S(env, pz_get_config(j->p, which));
}

JNIEXPORT jstring JNICALL FN(setConfig)(JNIEnv *env, jclass cls, jlong h, jint which, jstring v)
{
    ENTER(h);
    jstring r;
    WITH_STR(v, s, r = S(env, pz_set_config(j->p, which, s)));
    return r;
}

JNIEXPORT jstring JNICALL FN(configParams)(JNIEnv *env, jclass cls, jlong h, jstring base, jstring v)
{
    ENTER(h);
    jstring r;
    WITH_STR(base, b, WITH_STR(v, s, r = S(env, pz_config_params(j->p, b, s))));
    return r;
}
