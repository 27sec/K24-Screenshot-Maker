import AppKit
import CMpv
import OpenGL.GL3
import SwiftUI

/// Thin wrapper around libmpv. mpv decodes .ts / MPEG-2 / AC-3 directly, so files play
/// immediately without the rewrap/transcode step AVPlayer needed.
@MainActor
final class MPVPlayer {
    /// Path of the loaded libmpv, or nil when it is not installed.
    let libraryPath: String?
    nonisolated(unsafe) private(set) var handle: OpaquePointer?

    // Callbacks (always on the main actor).
    var onTimePos: (Double) -> Void = { _ in }
    var onDuration: (Double) -> Void = { _ in }
    var onPlayingChanged: (Bool) -> Void = { _ in }
    var onFileLoaded: () -> Void = {}
    var onFileFailed: (String) -> Void = { _ in }

    private(set) var hasFile = false
    private(set) var paused = true
    private(set) var eofReached = false
    var isPlaying: Bool { hasFile && !paused && !eofReached }

    init() {
        libraryPath = cmpv_load().map { String(cString: $0) }
        guard libraryPath != nil, let h = cmpv_create() else { return }
        handle = h
        let options: [(String, String)] = [
            ("config", "no"), ("terminal", "no"), ("input-default-bindings", "no"),
            ("input-vo-keyboard", "no"), ("osc", "no"), ("idle", "yes"),
            ("keep-open", "yes"),            // stay on the last frame at the end, like AVPlayer
            ("vo", "libmpv"),
            ("hwdec", "auto-copy-safe"),     // hardware decode, frames copied back so filters work
            ("deinterlace", "auto"),         // only frames flagged interlaced (TV recordings)
            ("hr-seek", "yes"),              // exact seeks for frame capture
            ("audio-client-name", "K24 Screenshot Maker"),
        ]
        for (k, v) in options { _ = cmpv_set_option_string(h, k, v) }
        guard cmpv_initialize(h) >= 0 else { cmpv_terminate_destroy(h); handle = nil; return }

        cmpv_observe_property(h, 0, "time-pos", MPV_FORMAT_DOUBLE)
        cmpv_observe_property(h, 0, "duration", MPV_FORMAT_DOUBLE)
        cmpv_observe_property(h, 0, "pause", MPV_FORMAT_FLAG)
        cmpv_observe_property(h, 0, "eof-reached", MPV_FORMAT_FLAG)

        cmpv_set_wakeup_callback(h, { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { AppModel.shared.player.drainEvents() } }
        }, nil)
    }

    var isAvailable: Bool { handle != nil }

    // MARK: Commands

    func load(_ url: URL) {
        hasFile = false
        eofReached = false
        command(["loadfile", url.path, "replace"])
        setFlag("pause", false)
    }

    func stop() {
        hasFile = false
        command(["stop"])
        onPlayingChanged(false)
    }

    func play() {
        if eofReached { seek(to: 0, exact: true) }
        setFlag("pause", false)
    }

    func pause() { setFlag("pause", true) }

    func seek(to seconds: Double, exact: Bool) {
        command(["seek", String(format: "%.3f", max(0, seconds)), exact ? "absolute+exact" : "absolute+keyframes"],
                async: true)
    }

    func setVolume(_ v: Float) {
        var d = Double(max(0, min(1, v)) * 100)
        if let h = handle { cmpv_set_property(h, "volume", MPV_FORMAT_DOUBLE, &d) }
    }

    func setMuted(_ m: Bool) { setFlag("mute", m) }

    func shutdown() {
        guard let h = handle else { return }
        handle = nil
        MPVOpenGLLayer.current?.freeRenderContext()
        cmpv_terminate_destroy(h)
    }

    private func setFlag(_ name: String, _ value: Bool) {
        guard let h = handle else { return }
        var f: Int32 = value ? 1 : 0
        cmpv_set_property(h, name, MPV_FORMAT_FLAG, &f)
    }

    private func command(_ args: [String], async: Bool = false) {
        guard let h = handle else { return }
        var cargs: [UnsafePointer<CChar>?] = args.map { UnsafePointer(strdup($0)) }
        cargs.append(nil)
        defer { for p in cargs { free(UnsafeMutablePointer(mutating: p)) } }
        if async { cmpv_command_async(h, 0, &cargs) } else { cmpv_command(h, &cargs) }
    }

    // MARK: Events

    fileprivate func drainEvents() {
        guard let h = handle else { return }
        while let ev = cmpv_wait_event(h, 0) {
            let e = ev.pointee
            if e.event_id == MPV_EVENT_NONE { break }
            switch e.event_id {
            case MPV_EVENT_PROPERTY_CHANGE:
                guard let p = e.data?.assumingMemoryBound(to: mpv_event_property.self).pointee else { break }
                let name = String(cString: p.name)
                if p.format == MPV_FORMAT_DOUBLE, let data = p.data {
                    let v = data.assumingMemoryBound(to: Double.self).pointee
                    if name == "time-pos" { onTimePos(v) } else if name == "duration" { onDuration(v) }
                } else if p.format == MPV_FORMAT_FLAG, let data = p.data {
                    let v = data.assumingMemoryBound(to: Int32.self).pointee != 0
                    if name == "pause" { paused = v } else if name == "eof-reached" { eofReached = v }
                    onPlayingChanged(isPlaying)
                }
            case MPV_EVENT_FILE_LOADED:
                hasFile = true
                onFileLoaded()
                onPlayingChanged(isPlaying)
            case MPV_EVENT_END_FILE:
                guard let end = e.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee,
                      end.reason == MPV_END_FILE_REASON_ERROR else { break }
                hasFile = false
                onFileFailed(String(cString: cmpv_error_string(end.error)))
                onPlayingChanged(false)
            default:
                break
            }
        }
    }
}

// MARK: - Video output

/// OpenGL layer that libmpv renders into.
final class MPVOpenGLLayer: CAOpenGLLayer {
    nonisolated(unsafe) static weak var current: MPVOpenGLLayer?
    private var cglContext: CGLContextObj?
    private var renderContext: OpaquePointer?
    weak var hostView: NSView?

    override init() {
        super.init()
        isAsynchronous = false
        needsDisplayOnBoundsChange = true
        backgroundColor = NSColor.black.cgColor
        MPVOpenGLLayer.current = self
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        let attrs: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(UInt32(kCGLOGLPVersion_3_2_Core.rawValue)),
            kCGLPFAAccelerated, kCGLPFADoubleBuffer, kCGLPFAAllowOfflineRenderers,
            kCGLPFAColorSize, CGLPixelFormatAttribute(24), _CGLPixelFormatAttribute(rawValue: 0),
        ]
        var pf: CGLPixelFormatObj?
        var count: GLint = 0
        CGLChoosePixelFormat(attrs, &pf, &count)
        return pf ?? super.copyCGLPixelFormat(forDisplayMask: mask)
    }

    override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj {
        let ctx = super.copyCGLContext(forPixelFormat: pf)
        cglContext = ctx
        CGLSetCurrentContext(ctx)
        createRenderContext()
        return ctx
    }

    private func createRenderContext() {
        guard renderContext == nil else { return }
        let mpv = MainActor.assumeIsolated { AppModel.shared.player }.handle
        guard let mpv else { return }
        do {
            var initParams = mpv_opengl_init_params(get_proc_address: cmpv_gl_get_proc_address,
                                                    get_proc_address_ctx: nil)
            let api = strdup(MPV_RENDER_API_TYPE_OPENGL)
            defer { free(api) }
            var rc: OpaquePointer?
            withUnsafeMutablePointer(to: &initParams) { ip in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(api)),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(ip)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                _ = cmpv_render_context_create(&rc, mpv, &params)
            }
            guard let rc else { return }
            renderContext = rc
            cmpv_render_context_set_update_callback(rc, { ctx in
                guard let ctx else { return }
                let layer = Unmanaged<MPVOpenGLLayer>.fromOpaque(ctx).takeUnretainedValue()
                DispatchQueue.main.async { layer.frameReady() }
            }, Unmanaged.passUnretained(self).toOpaque())
        }
    }

    /// Draw through Core Animation when visible. When the window is hidden or covered, CA stops
    /// drawing, which would stall mpv; consume the frame without rendering so playback keeps going.
    private func frameReady() {
        if let w = hostView?.window, w.occlusionState.contains(.visible), !w.isMiniaturized {
            setNeedsDisplay()
            return
        }
        guard let rc = renderContext, let cglContext else { return }
        CGLLockContext(cglContext)
        defer { CGLUnlockContext(cglContext) }
        CGLSetCurrentContext(cglContext)
        guard cmpv_render_context_update(rc) & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 else { return }
        var fbo = mpv_opengl_fbo(fbo: 0, w: 1, h: 1, internal_format: 0)
        var skip: Int32 = 1
        withUnsafeMutablePointer(to: &fbo) { fp in
            withUnsafeMutablePointer(to: &skip) { sp in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(fp)),
                    mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: UnsafeMutableRawPointer(sp)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                _ = cmpv_render_context_render(rc, &params)
            }
        }
    }

    func freeRenderContext() {
        guard let rc = renderContext else { return }
        if let cglContext { CGLSetCurrentContext(cglContext) }
        cmpv_render_context_set_update_callback(rc, nil, nil)
        cmpv_render_context_free(rc)
        renderContext = nil
    }

    override func canDraw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj,
                          forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) -> Bool { true }

    override func draw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj,
                       forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) {
        CGLSetCurrentContext(ctx)
        guard let rc = renderContext else {
            glClearColor(0, 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            super.draw(inCGLContext: ctx, pixelFormat: pf, forLayerTime: t, displayTime: ts)
            return
        }
        _ = cmpv_render_context_update(rc)
        var fboID: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &fboID)
        var viewport = [GLint](repeating: 0, count: 4)
        glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)
        var fbo = mpv_opengl_fbo(fbo: Int32(fboID), w: viewport[2], h: viewport[3], internal_format: 0)
        var flip: Int32 = 1
        withUnsafeMutablePointer(to: &fbo) { fp in
            withUnsafeMutablePointer(to: &flip) { flp in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(fp)),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(flp)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                _ = cmpv_render_context_render(rc, &params)
            }
        }
        super.draw(inCGLContext: ctx, pixelFormat: pf, forLayerTime: t, displayTime: ts)
        cmpv_render_context_report_swap(rc)
    }
}

/// SwiftUI host for the mpv video layer.
struct MPVVideoView: NSViewRepresentable {
    final class HostView: NSView {
        let videoLayer = MPVOpenGLLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            layer = videoLayer
            wantsLayer = true
            videoLayer.hostView = self
        }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            // Repaint the current frame as soon as the window becomes visible again.
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.videoLayer.setNeedsDisplay() }
            }
        }
        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            videoLayer.contentsScale = window?.backingScaleFactor ?? 2
            videoLayer.setNeedsDisplay()
        }
    }

    func makeNSView(context: Context) -> HostView { HostView() }
    func updateNSView(_ nsView: HostView, context: Context) {}
}
