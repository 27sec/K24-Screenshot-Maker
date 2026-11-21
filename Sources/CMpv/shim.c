#include "CMpv.h"
#include <dlfcn.h>
#include <stddef.h>

static void *lib;
static void *gl;

#define FN(ret, name, params, args)                          \
    static ret(*p_##name) params;                            \
    ret c##name params { return p_##name args; }
#define VFN(name, params, args)                              \
    static void(*p_##name) params;                           \
    void c##name params { p_##name args; }

FN(const char *, mpv_error_string, (int e), (e))
VFN(mpv_free, (void *d), (d))
FN(mpv_handle *, mpv_create, (void), ())
FN(int, mpv_initialize, (mpv_handle *c), (c))
VFN(mpv_terminate_destroy, (mpv_handle *c), (c))
FN(int, mpv_set_option_string, (mpv_handle *c, const char *n, const char *d), (c, n, d))
FN(int, mpv_command, (mpv_handle *c, const char **a), (c, a))
FN(int, mpv_command_async, (mpv_handle *c, uint64_t u, const char **a), (c, u, a))
FN(int, mpv_set_property, (mpv_handle *c, const char *n, mpv_format f, void *d), (c, n, f, d))
FN(int, mpv_set_property_string, (mpv_handle *c, const char *n, const char *d), (c, n, d))
FN(int, mpv_get_property, (mpv_handle *c, const char *n, mpv_format f, void *d), (c, n, f, d))
FN(int, mpv_observe_property, (mpv_handle *c, uint64_t u, const char *n, mpv_format f), (c, u, n, f))
FN(mpv_event *, mpv_wait_event, (mpv_handle *c, double t), (c, t))
VFN(mpv_set_wakeup_callback, (mpv_handle *c, void (*cb)(void *), void *d), (c, cb, d))
FN(int, mpv_render_context_create, (mpv_render_context **r, mpv_handle *c, mpv_render_param *p), (r, c, p))
VFN(mpv_render_context_set_update_callback, (mpv_render_context *r, mpv_render_update_fn f, void *d), (r, f, d))
FN(uint64_t, mpv_render_context_update, (mpv_render_context *r), (r))
FN(int, mpv_render_context_render, (mpv_render_context *r, mpv_render_param *p), (r, p))
VFN(mpv_render_context_report_swap, (mpv_render_context *r), (r))
VFN(mpv_render_context_free, (mpv_render_context *r), (r))

#define LOAD(name) if (!(p_##name = dlsym(lib, #name))) goto fail;

const char *cmpv_load(void) {
    static const char *loaded;
    if (loaded) return loaded;
    static const char *paths[] = {
        "@executable_path/../Frameworks/libmpv.2.dylib",
        "/opt/homebrew/opt/mpv/lib/libmpv.2.dylib",
        "/opt/homebrew/lib/libmpv.2.dylib",
        "/usr/local/opt/mpv/lib/libmpv.2.dylib",
        "/usr/local/lib/libmpv.2.dylib",
        "/opt/local/lib/libmpv.2.dylib",
    };
    for (size_t i = 0; i < sizeof(paths) / sizeof(*paths); i++) {
        lib = dlopen(paths[i], RTLD_NOW | RTLD_LOCAL);
        if (!lib) continue;
        LOAD(mpv_error_string) LOAD(mpv_free) LOAD(mpv_create) LOAD(mpv_initialize)
        LOAD(mpv_terminate_destroy) LOAD(mpv_set_option_string) LOAD(mpv_command)
        LOAD(mpv_command_async) LOAD(mpv_set_property) LOAD(mpv_set_property_string)
        LOAD(mpv_get_property) LOAD(mpv_observe_property) LOAD(mpv_wait_event)
        LOAD(mpv_set_wakeup_callback) LOAD(mpv_render_context_create)
        LOAD(mpv_render_context_set_update_callback) LOAD(mpv_render_context_update)
        LOAD(mpv_render_context_render) LOAD(mpv_render_context_report_swap)
        LOAD(mpv_render_context_free)
        loaded = paths[i];
        return loaded;
    fail:
        dlclose(lib);
        lib = NULL;
    }
    return NULL;
}

void *cmpv_gl_get_proc_address(void *ctx, const char *name) {
    (void)ctx;
    if (!gl) gl = dlopen("/System/Library/Frameworks/OpenGL.framework/OpenGL", RTLD_LAZY | RTLD_LOCAL);
    return gl ? dlsym(gl, name) : NULL;
}
