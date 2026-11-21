// Runtime-loaded libmpv. The app does not link libmpv; cmpv_load() dlopens it
// (from Homebrew by default) and the cmpv_* wrappers forward to it.
#pragma once
#include "client.h"
#include "render.h"
#include "render_gl.h"

/// Loads libmpv. Returns the path that was loaded, or NULL if none was found.
const char *cmpv_load(void);
/// Address of an OpenGL function, for MPV_RENDER_PARAM_OPENGL_INIT_PARAMS.
void *cmpv_gl_get_proc_address(void *ctx, const char *name);

const char *cmpv_error_string(int error);
void cmpv_free(void *data);
mpv_handle *cmpv_create(void);
int cmpv_initialize(mpv_handle *ctx);
void cmpv_terminate_destroy(mpv_handle *ctx);
int cmpv_set_option_string(mpv_handle *ctx, const char *name, const char *data);
int cmpv_command(mpv_handle *ctx, const char **args);
int cmpv_command_async(mpv_handle *ctx, uint64_t reply_userdata, const char **args);
int cmpv_set_property(mpv_handle *ctx, const char *name, mpv_format format, void *data);
int cmpv_set_property_string(mpv_handle *ctx, const char *name, const char *data);
int cmpv_get_property(mpv_handle *ctx, const char *name, mpv_format format, void *data);
int cmpv_observe_property(mpv_handle *mpv, uint64_t reply_userdata, const char *name, mpv_format format);
mpv_event *cmpv_wait_event(mpv_handle *ctx, double timeout);
void cmpv_set_wakeup_callback(mpv_handle *ctx, void (*cb)(void *d), void *d);

int cmpv_render_context_create(mpv_render_context **res, mpv_handle *mpv, mpv_render_param *params);
void cmpv_render_context_set_update_callback(mpv_render_context *ctx, mpv_render_update_fn callback, void *callback_ctx);
uint64_t cmpv_render_context_update(mpv_render_context *ctx);
int cmpv_render_context_render(mpv_render_context *ctx, mpv_render_param *params);
void cmpv_render_context_report_swap(mpv_render_context *ctx);
void cmpv_render_context_free(mpv_render_context *ctx);
