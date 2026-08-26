/*
 * mali_egl_shim.c
 *
 * LD_PRELOAD shim to make Qt5 eglfs work with Mali fbdev EGL.
 *
 * Mali fbdev EGL (libmali.so) uses a proprietary fbdev_window struct
 * as the native window, and does not support EGL configs with
 * depth/stencil buffers when using the fbdev display.
 *
 * This shim:
 *   1. Intercepts eglCreateWindowSurface() and replaces the native
 *      window handle with a Mali fbdev_window struct.
 *   2. Intercepts eglChooseConfig() and strips unsupported attributes,
 *      with fallback to a minimal attrib list when Mali returns 0 configs.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <signal.h>
#include <execinfo.h>
#include <ucontext.h>
#include <unistd.h>
#include <EGL/egl.h>

static void segv_handler(int sig, siginfo_t *si, void *ctx) {
    ucontext_t *uc = (ucontext_t *)ctx;
    void *pc = NULL;
#ifdef __aarch64__
    pc = (void *)uc->uc_mcontext.pc;
#elif defined(__arm__)
    pc = (void *)uc->uc_mcontext.arm_pc;
#endif
    void *bt[32];
    int n = backtrace(bt, 32);
    fprintf(stderr, "\n[mali_egl_shim] SIGSEGV fault_addr=%p pc=%p\n",
            si->si_addr, pc);
    backtrace_symbols_fd(bt, n, 2);
    _exit(139);
}

/* Mali fbdev native window type */
typedef struct {
    unsigned short width;
    unsigned short height;
} fbdev_window;

static fbdev_window g_mali_window = { 720, 480 };

/* EGL function pointers — resolved lazily on first use */
static void *g_libegl = NULL;

static EGLSurface (*real_eglCreateWindowSurface)(EGLDisplay, EGLConfig,
        EGLNativeWindowType, const EGLint *) = NULL;
static EGLBoolean (*real_eglChooseConfig)(EGLDisplay, const EGLint *,
        EGLConfig *, EGLint, EGLint *) = NULL;
static EGLDisplay (*real_eglGetDisplay)(EGLNativeDisplayType) = NULL;
static EGLBoolean (*real_eglInitialize)(EGLDisplay, EGLint *, EGLint *) = NULL;
static EGLBoolean (*real_eglGetConfigAttrib)(EGLDisplay, EGLConfig,
        EGLint, EGLint *) = NULL;
static EGLBoolean (*real_eglGetConfigs)(EGLDisplay, EGLConfig *,
        EGLint, EGLint *) = NULL;
static EGLBoolean (*real_eglBindAPI)(EGLenum) = NULL;
static EGLContext (*real_eglCreateContext)(EGLDisplay, EGLConfig,
        EGLContext, const EGLint *) = NULL;
static EGLBoolean (*real_eglMakeCurrent)(EGLDisplay, EGLSurface,
        EGLSurface, EGLContext) = NULL;
static EGLBoolean (*real_eglSwapBuffers)(EGLDisplay, EGLSurface) = NULL;
static EGLint (*real_eglGetError)(void) = NULL;
static void (*real_glClearColor)(float, float, float, float) = NULL;
static void (*real_glClear)(unsigned int) = NULL;
static void (*real_glColorMask)(unsigned char, unsigned char,
        unsigned char, unsigned char) = NULL;
static void (*real_glReadPixels)(int, int, int, int,
        unsigned int, unsigned int, void *) = NULL;
static unsigned int (*real_glGetError)(void) = NULL;

/* Resolve all real EGL functions via explicit dlopen of libmali */
static void resolve_egl(void) {
    if (real_eglGetDisplay) return;  /* already done */

    /* Try RTLD_NEXT first (works if libmali is loaded before us) */
    real_eglGetDisplay          = dlsym(RTLD_NEXT, "eglGetDisplay");
    real_eglInitialize          = dlsym(RTLD_NEXT, "eglInitialize");
    real_eglCreateWindowSurface = dlsym(RTLD_NEXT, "eglCreateWindowSurface");
    real_eglChooseConfig        = dlsym(RTLD_NEXT, "eglChooseConfig");
    real_eglGetConfigAttrib     = dlsym(RTLD_NEXT, "eglGetConfigAttrib");
    real_eglGetConfigs          = dlsym(RTLD_NEXT, "eglGetConfigs");
    real_eglBindAPI             = dlsym(RTLD_NEXT, "eglBindAPI");
    real_eglCreateContext       = dlsym(RTLD_NEXT, "eglCreateContext");
    real_eglMakeCurrent         = dlsym(RTLD_NEXT, "eglMakeCurrent");
    real_eglSwapBuffers         = dlsym(RTLD_NEXT, "eglSwapBuffers");
    real_eglGetError            = dlsym(RTLD_NEXT, "eglGetError");
    real_glClearColor           = dlsym(RTLD_NEXT, "glClearColor");
    real_glClear                = dlsym(RTLD_NEXT, "glClear");
    real_glColorMask            = dlsym(RTLD_NEXT, "glColorMask");
    real_glReadPixels           = dlsym(RTLD_NEXT, "glReadPixels");
    real_glGetError             = dlsym(RTLD_NEXT, "glGetError");

    if (!real_eglGetDisplay) {
        /* Fall back: explicitly open libmali */
        const char *libs[] = {
            "/usr/lib/libmali.so",
            "libmali.so",
            "libEGL.so.1",
            "libEGL.so",
            NULL
        };
        for (int i = 0; libs[i] && !g_libegl; i++) {
            g_libegl = dlopen(libs[i], RTLD_NOW | RTLD_GLOBAL);
            if (g_libegl)
                fprintf(stderr, "[mali_egl_shim] opened %s\n", libs[i]);
        }
        if (g_libegl) {
            real_eglGetDisplay          = dlsym(g_libegl, "eglGetDisplay");
            real_eglInitialize          = dlsym(g_libegl, "eglInitialize");
            real_eglCreateWindowSurface = dlsym(g_libegl, "eglCreateWindowSurface");
            real_eglChooseConfig        = dlsym(g_libegl, "eglChooseConfig");
            real_eglGetConfigAttrib     = dlsym(g_libegl, "eglGetConfigAttrib");
            real_eglGetConfigs          = dlsym(g_libegl, "eglGetConfigs");
            real_eglBindAPI             = dlsym(g_libegl, "eglBindAPI");
            real_eglCreateContext       = dlsym(g_libegl, "eglCreateContext");
            real_eglMakeCurrent         = dlsym(g_libegl, "eglMakeCurrent");
            real_eglSwapBuffers         = dlsym(g_libegl, "eglSwapBuffers");
            real_eglGetError            = dlsym(g_libegl, "eglGetError");
            real_glClearColor           = dlsym(g_libegl, "glClearColor");
            real_glClear                = dlsym(g_libegl, "glClear");
            real_glColorMask            = dlsym(g_libegl, "glColorMask");
            real_glReadPixels           = dlsym(g_libegl, "glReadPixels");
            real_glGetError             = dlsym(g_libegl, "glGetError");
        }
    }

    if (!real_eglBindAPI)
        real_eglBindAPI = dlsym(RTLD_NEXT, "eglBindAPI");

    fprintf(stderr, "[mali_egl_shim] EGL resolved: GetDisplay=%p Initialize=%p"
            " ChooseConfig=%p CreateWindowSurface=%p CreateContext=%p"
            " MakeCurrent=%p SwapBuffers=%p\n",
            (void*)real_eglGetDisplay, (void*)real_eglInitialize,
            (void*)real_eglChooseConfig, (void*)real_eglCreateWindowSurface,
            (void*)real_eglCreateContext, (void*)real_eglMakeCurrent,
            (void*)real_eglSwapBuffers);
}

static void init_shim(void) __attribute__((constructor));
static void init_shim(void) {
    const char *w = getenv("MALI_WINDOW_WIDTH");
    const char *h = getenv("MALI_WINDOW_HEIGHT");
    if (w) g_mali_window.width  = (unsigned short)atoi(w);
    if (h) g_mali_window.height = (unsigned short)atoi(h);

    fprintf(stderr, "[mali_egl_shim] loaded. window=%dx%d\n",
            g_mali_window.width, g_mali_window.height);

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = segv_handler;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGSEGV, &sa, NULL);

    /* Attempt early resolution — may be NULL if libmali not yet loaded */
    resolve_egl();
}

/* Log all available EGL configs after initialization */
static void dump_egl_configs(EGLDisplay dpy) {
    if (!real_eglGetConfigs || !real_eglGetConfigAttrib) return;
    EGLConfig cfgs[64];
    EGLint n = 0;
    real_eglGetConfigs(dpy, cfgs, 64, &n);
    fprintf(stderr, "[mali_egl_shim] Available EGL configs: %d\n", n);
    for (int i = 0; i < n && i < 16; i++) {
        EGLint r, g, b, a, d, s, surf, rend, id;
        real_eglGetConfigAttrib(dpy, cfgs[i], EGL_RED_SIZE,       &r);
        real_eglGetConfigAttrib(dpy, cfgs[i], EGL_GREEN_SIZE,     &g);
        real_eglGetConfigAttrib(dpy, cfgs[i], EGL_BLUE_SIZE,      &b);
        real_eglGetConfigAttrib(dpy, cfgs[i], EGL_ALPHA_SIZE,     &a);
        real_eglGetConfigAttrib(dpy, cfgs[i], EGL_DEPTH_SIZE,     &d);
        real_eglGetConfigAttrib(dpy, cfgs[i], EGL_STENCIL_SIZE,   &s);
        real_eglGetConfigAttrib(dpy, cfgs[i], EGL_SURFACE_TYPE,   &surf);
        real_eglGetConfigAttrib(dpy, cfgs[i], EGL_RENDERABLE_TYPE,&rend);
        real_eglGetConfigAttrib(dpy, cfgs[i], EGL_CONFIG_ID,      &id);
        fprintf(stderr, "[mali_egl_shim]   cfg[%d] id=%d RGBA=%d%d%d%d d=%d s=%d surf=0x%x rend=0x%x\n",
                i, id, r, g, b, a, d, s, surf, rend);
    }
}

EGLDisplay eglGetDisplay(EGLNativeDisplayType native) {
    resolve_egl();
    if (!real_eglGetDisplay) {
        fprintf(stderr, "[mali_egl_shim] ERROR: real_eglGetDisplay is NULL!\n");
        return EGL_NO_DISPLAY;
    }
    /* Force EGL_DEFAULT_DISPLAY for Mali fbdev */
    EGLDisplay d = real_eglGetDisplay(EGL_DEFAULT_DISPLAY);
    fprintf(stderr, "[mali_egl_shim] eglGetDisplay(native=%p) -> %p\n", (void*)native, d);
    return d;
}

EGLBoolean eglInitialize(EGLDisplay dpy, EGLint *major, EGLint *minor) {
    resolve_egl();
    if (!real_eglInitialize) {
        fprintf(stderr, "[mali_egl_shim] ERROR: real_eglInitialize is NULL!\n");
        return EGL_FALSE;
    }
    EGLBoolean r = real_eglInitialize(dpy, major, minor);
    fprintf(stderr, "[mali_egl_shim] eglInitialize -> %d (EGL %d.%d)\n",
            r, major ? *major : -1, minor ? *minor : -1);
    if (r) dump_egl_configs(dpy);
    return r;
}

/* Force GLES API regardless of what Qt requests */
EGLBoolean eglBindAPI(EGLenum api) {
    static unsigned long call_count = 0;
    resolve_egl();
    call_count++;
    /* Always bind GLES — Mali doesn't support desktop EGL_OPENGL_API */
    if (api == EGL_OPENGL_API) {
        fprintf(stderr, "[mali_egl_shim] eglBindAPI: replacing EGL_OPENGL_API with EGL_OPENGL_ES_API\n");
        api = EGL_OPENGL_ES_API;
    } else if (call_count <= 3) {
        fprintf(stderr, "[mali_egl_shim] eglBindAPI: api=0x%x\n", api);
    }
    if (!real_eglBindAPI) return EGL_TRUE;  /* assume ES already default */
    return real_eglBindAPI(api);
}

/* Attribute name for logging */
static const char *egl_attr_name(EGLint attr) {
    switch (attr) {
        case 0x3020: return "BUFFER_SIZE";
        case 0x3021: return "ALPHA_SIZE";
        case 0x3022: return "BLUE_SIZE";
        case 0x3023: return "GREEN_SIZE";
        case 0x3024: return "RED_SIZE";
        case 0x3025: return "DEPTH_SIZE";
        case 0x3026: return "STENCIL_SIZE";
        case 0x3031: return "SAMPLE_BUFFERS";
        case 0x3032: return "SAMPLES";
        case 0x3033: return "SURFACE_TYPE";
        case 0x3034: return "TRANSPARENT_TYPE";
        case 0x3040: return "RENDERABLE_TYPE";
        case 0x3042: return "CONFORMANT";
        default: { static char buf[16]; snprintf(buf,16,"0x%x",attr); return buf; }
    }
}

/* Strip depth/stencil/samples from attrib list to get a config Mali accepts */
EGLBoolean eglChooseConfig(EGLDisplay dpy, const EGLint *attrib_list,
                            EGLConfig *configs, EGLint config_size,
                            EGLint *num_config)
{
    resolve_egl();
    EGLint filtered[128];
    int fi = 0;

    fprintf(stderr, "[mali_egl_shim] eglChooseConfig attribs:\n");
    if (attrib_list) {
        for (int i = 0; attrib_list[i] != EGL_NONE; i += 2) {
            EGLint attr = attrib_list[i];
            EGLint val  = attrib_list[i + 1];
            fprintf(stderr, "[mali_egl_shim]   %s = %d\n", egl_attr_name(attr), val);

            /* Skip depth, stencil, sample buffers — Mali fbdev doesn't support them */
            if (attr == EGL_DEPTH_SIZE   && val > 0) continue;
            if (attr == EGL_STENCIL_SIZE && val > 0) continue;
            if (attr == EGL_SAMPLE_BUFFERS)           continue;
            if (attr == EGL_SAMPLES)                  continue;

            /* Replace EGL_OPENGL_BIT (8) with EGL_OPENGL_ES2_BIT (4) —
             * Mali only supports GLES, not desktop OpenGL */
            if (attr == EGL_RENDERABLE_TYPE && (val & 0x8) && !(val & 0x4)) {
                fprintf(stderr, "[mali_egl_shim] replacing RENDERABLE_TYPE 0x%x -> EGL_OPENGL_ES2_BIT\n", val);
                val = EGL_OPENGL_ES2_BIT;
            }

            if (fi + 2 < 126) {
                filtered[fi++] = attr;
                filtered[fi++] = val;
            }
        }
    }
    filtered[fi++] = EGL_NONE;

    if (!real_eglChooseConfig) {
        fprintf(stderr, "[mali_egl_shim] ERROR: real_eglChooseConfig is NULL!\n");
        return EGL_FALSE;
    }

    EGLBoolean r = real_eglChooseConfig(dpy, filtered, configs, config_size, num_config);
    fprintf(stderr, "[mali_egl_shim] eglChooseConfig (filtered) -> %d, num_configs=%d\n",
            r, num_config ? *num_config : -1);

    if (r && num_config && *num_config == 0) {
        /* Mali returned no configs — try progressively more permissive fallbacks */
        fprintf(stderr, "[mali_egl_shim] Retrying with minimal GLES2 attrib list\n");

        /* Fallback 1: GLES2 + window bit only */
        EGLint fallback1[] = {
            EGL_SURFACE_TYPE,    EGL_WINDOW_BIT,
            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
            EGL_NONE
        };
        r = real_eglChooseConfig(dpy, fallback1, configs, config_size, num_config);
        fprintf(stderr, "[mali_egl_shim] Fallback1 -> %d, num_configs=%d\n",
                r, num_config ? *num_config : -1);
    }

    if (r && num_config && *num_config == 0) {
        /* Fallback 2: absolutely minimal — let Mali pick anything */
        fprintf(stderr, "[mali_egl_shim] Retrying with empty attrib list\n");
        EGLint fallback2[] = { EGL_NONE };
        r = real_eglChooseConfig(dpy, fallback2, configs, config_size, num_config);
        fprintf(stderr, "[mali_egl_shim] Fallback2 -> %d, num_configs=%d\n",
                r, num_config ? *num_config : -1);
    }

    return r;
}

/* Replace whatever native window Qt passes with a Mali fbdev_window */
EGLSurface eglCreateWindowSurface(EGLDisplay dpy, EGLConfig config,
                                   EGLNativeWindowType win,
                                   const EGLint *attrib_list)
{
    resolve_egl();
    fprintf(stderr, "[mali_egl_shim] eglCreateWindowSurface: using fbdev_window %dx%d\n",
            g_mali_window.width, g_mali_window.height);
    if (!real_eglCreateWindowSurface) {
        fprintf(stderr, "[mali_egl_shim] ERROR: real_eglCreateWindowSurface is NULL!\n");
        return EGL_NO_SURFACE;
    }
    if (real_eglGetConfigAttrib) {
        EGLint id = -1, red = -1, green = -1, blue = -1, alpha = -1;
        real_eglGetConfigAttrib(dpy, config, EGL_CONFIG_ID, &id);
        real_eglGetConfigAttrib(dpy, config, EGL_RED_SIZE, &red);
        real_eglGetConfigAttrib(dpy, config, EGL_GREEN_SIZE, &green);
        real_eglGetConfigAttrib(dpy, config, EGL_BLUE_SIZE, &blue);
        real_eglGetConfigAttrib(dpy, config, EGL_ALPHA_SIZE, &alpha);
        fprintf(stderr, "[mali_egl_shim] window config id=%d RGBA=%d%d%d%d\n",
                id, red, green, blue, alpha);
    }

    EGLSurface surface = real_eglCreateWindowSurface(dpy, config,
                (EGLNativeWindowType)&g_mali_window, attrib_list);
    EGLint error = surface == EGL_NO_SURFACE && real_eglGetError
            ? real_eglGetError() : EGL_SUCCESS;
    fprintf(stderr, "[mali_egl_shim] eglCreateWindowSurface -> %p (error=0x%x)\n",
            surface, error);
    return surface;
}

EGLContext eglCreateContext(EGLDisplay dpy, EGLConfig config,
                            EGLContext share_context,
                            const EGLint *attrib_list)
{
    resolve_egl();
    if (!real_eglCreateContext) {
        fprintf(stderr, "[mali_egl_shim] ERROR: real_eglCreateContext is NULL!\n");
        return EGL_NO_CONTEXT;
    }

    EGLint client_version = 0;
    if (attrib_list) {
        for (int i = 0; attrib_list[i] != EGL_NONE; i += 2) {
            if (attrib_list[i] == EGL_CONTEXT_CLIENT_VERSION)
                client_version = attrib_list[i + 1];
        }
    }

    EGLContext context = real_eglCreateContext(dpy, config, share_context,
                                                attrib_list);
    EGLint error = context == EGL_NO_CONTEXT && real_eglGetError
            ? real_eglGetError() : EGL_SUCCESS;
    fprintf(stderr, "[mali_egl_shim] eglCreateContext(es=%d share=%p) -> %p"
            " (error=0x%x)\n", client_version, share_context, context, error);
    return context;
}

EGLBoolean eglMakeCurrent(EGLDisplay dpy, EGLSurface draw,
                          EGLSurface read, EGLContext context)
{
    static unsigned long call_count = 0;
    resolve_egl();
    if (!real_eglMakeCurrent) {
        fprintf(stderr, "[mali_egl_shim] ERROR: real_eglMakeCurrent is NULL!\n");
        return EGL_FALSE;
    }

    call_count++;
    EGLBoolean result = real_eglMakeCurrent(dpy, draw, read, context);
    EGLint error = !result && real_eglGetError ? real_eglGetError() : EGL_SUCCESS;
    if (call_count <= 6 || !result) {
        fprintf(stderr, "[mali_egl_shim] eglMakeCurrent[%lu](draw=%p read=%p"
                " context=%p) -> %d (error=0x%x)\n", call_count, draw, read,
                context, result, error);
    }
    return result;
}

EGLBoolean eglSwapBuffers(EGLDisplay dpy, EGLSurface surface)
{
    static unsigned long call_count = 0;
    resolve_egl();
    if (!real_eglSwapBuffers) {
        fprintf(stderr, "[mali_egl_shim] ERROR: real_eglSwapBuffers is NULL!\n");
        return EGL_FALSE;
    }

    call_count++;
    if (call_count <= 4 && getenv("MALI_EGL_SHIM_INSPECT_FRAME")
            && real_glReadPixels) {
        size_t pixel_count = (size_t)g_mali_window.width * g_mali_window.height;
        unsigned char *pixels = malloc(pixel_count * 4);
        if (pixels) {
            real_glReadPixels(0, 0, g_mali_window.width, g_mali_window.height,
                              0x1908, 0x1401, pixels); /* GL_RGBA, GL_UNSIGNED_BYTE */
            unsigned int gl_error = real_glGetError ? real_glGetError() : 0;
            unsigned int minimum[4] = { 255, 255, 255, 255 };
            unsigned int maximum[4] = { 0, 0, 0, 0 };
            unsigned long long sums[4] = { 0, 0, 0, 0 };
            size_t non_black = 0, alpha_zero = 0, alpha_opaque = 0;
            for (size_t i = 0; i < pixel_count; i++) {
                for (int channel = 0; channel < 4; channel++) {
                    unsigned int value = pixels[i * 4 + channel];
                    if (value < minimum[channel]) minimum[channel] = value;
                    if (value > maximum[channel]) maximum[channel] = value;
                    sums[channel] += value;
                }
                if (pixels[i * 4] || pixels[i * 4 + 1] || pixels[i * 4 + 2])
                    non_black++;
                if (pixels[i * 4 + 3] == 0) alpha_zero++;
                if (pixels[i * 4 + 3] == 255) alpha_opaque++;
            }
            fprintf(stderr, "[mali_egl_shim] frame[%lu] pixels:"
                    " R=%u-%u/%llu G=%u-%u/%llu B=%u-%u/%llu A=%u-%u/%llu"
                    " nonblack=%zu alpha0=%zu alpha255=%zu gl_error=0x%x\n",
                    call_count,
                    minimum[0], maximum[0], sums[0],
                    minimum[1], maximum[1], sums[1],
                    minimum[2], maximum[2], sums[2],
                    minimum[3], maximum[3], sums[3],
                    non_black, alpha_zero, alpha_opaque, gl_error);
            free(pixels);
        }
    }

    if (getenv("MALI_EGL_SHIM_FORCE_OPAQUE") && real_glColorMask
            && real_glClearColor && real_glClear) {
        real_glColorMask(0, 0, 0, 1);
        real_glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        real_glClear(0x00004000); /* GL_COLOR_BUFFER_BIT */
        real_glColorMask(1, 1, 1, 1);
        if (call_count == 1)
            fprintf(stderr, "[mali_egl_shim] forced framebuffer alpha opaque\n");
    }

    if (getenv("MALI_EGL_SHIM_TEST_CLEAR") && real_glClearColor && real_glClear) {
        real_glClearColor(1.0f, 0.0f, 1.0f, 1.0f);
        real_glClear(0x00004000); /* GL_COLOR_BUFFER_BIT */
        if (call_count == 1)
            fprintf(stderr, "[mali_egl_shim] injected opaque magenta test frame\n");
    }
    EGLBoolean result = real_eglSwapBuffers(dpy, surface);
    EGLint error = !result && real_eglGetError ? real_eglGetError() : EGL_SUCCESS;
    if (call_count <= 6 || call_count % 120 == 0 || !result) {
        fprintf(stderr, "[mali_egl_shim] eglSwapBuffers[%lu](surface=%p) -> %d"
                " (error=0x%x)\n", call_count, surface, result, error);
    }
    return result;
}
