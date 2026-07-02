import SwiftUI
import AppKit
import Cmpv
import Darwin

@_silgen_name("glGetIntegerv")
private func glGetIntegerv(_ pname: UInt32, _ params: UnsafeMutablePointer<Int32>)

private let GL_FRAMEBUFFER_BINDING: UInt32 = 0x8CA6

public class MpvVideoView: NSView {
    private var glContext: NSOpenGLContext?
    private var pixelFormat: NSOpenGLPixelFormat?
    nonisolated(unsafe) private var renderContext: OpaquePointer?
    private var player: MpvPlayer?
    nonisolated(unsafe) private var displayLink: CVDisplayLink?
    private var isConfigured = false
    
    public func setPlayer(_ player: MpvPlayer) {
        self.player = player
        setupGL()
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            setupDisplayLink()
        } else {
            // View is leaving the window hierarchy - clean up rendering resources immediately.
            // This MUST happen before MpvPlayer.destroy() is called on the main handle,
            // otherwise libmpv will crash with SIGABRT due to dangling client render contexts.
            if let link = displayLink {
                CVDisplayLinkStop(link)
                self.displayLink = nil
            }
            if let renderContext = renderContext {
                mpv_render_context_free(renderContext)
                self.renderContext = nil
            }
        }
    }
    
    private func setupGL() {
        guard !isConfigured else { return }
        isConfigured = true
        
        let attrs: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFAColorSize), 24,
            UInt32(NSOpenGLPFAAlphaSize), 8,
            UInt32(NSOpenGLPFADepthSize), 24,
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            0
        ]
        
        guard let pixelFormat = NSOpenGLPixelFormat(attributes: attrs) else {
            LogManager.shared.log(serviceId: "system", text: "MpvVideoView error: Failed to create OpenGL pixel format", isError: true)
            return
        }
        self.pixelFormat = pixelFormat
        
        guard let glContext = NSOpenGLContext(format: pixelFormat, share: nil) else {
            LogManager.shared.log(serviceId: "system", text: "MpvVideoView error: Failed to create OpenGL context", isError: true)
            return
        }
        self.glContext = glContext
        glContext.view = self
        
        // Make it current
        glContext.makeCurrentContext()
        
        // Setup libmpv render API context
        setupMpvRender()
    }
    
    private func setupMpvRender() {
        guard let player = player, let mpvHandle = player.getHandle() else { return }
        
        // C-compatible function pointer for OpenGL dynamic loading
        let getProcAddress: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? = { _, name in
            guard let name = name else { return nil }
            return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
        }
        
        var glParams = mpv_opengl_init_params(
            get_proc_address: getProcAddress,
            get_proc_address_ctx: nil
        )
        
        // Swift requires using withUnsafeMutablePointer or direct address-of
        withUnsafeMutablePointer(to: &glParams) { glParamsPtr in
            var apiName = "opengl".cString(using: .utf8)!
            apiName.withUnsafeMutableBufferPointer { apiNameBuffer in
                var params: [mpv_render_param] = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiNameBuffer.baseAddress),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: glParamsPtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                ]
                
                let status = mpv_render_context_create(&self.renderContext, mpvHandle, &params)
                if status < 0 {
                    let errString = String(cString: mpv_error_string(status))
                    LogManager.shared.log(serviceId: "system", text: "MpvVideoView error: Failed to create mpv render context: \(errString)", isError: true)
                } else {
                    LogManager.shared.log(serviceId: "system", text: "MpvVideoView successfully initialized mpv_render_context")
                    
                    // Set update callback to trigger redraws when new video frames arrive
                    let updateCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { ctx in
                        guard let ctx = ctx else { return }
                        let view = Unmanaged<MpvVideoView>.fromOpaque(ctx).takeUnretainedValue()
                        view.triggerRedraw()
                    }
                    
                    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
                    mpv_render_context_set_update_callback(self.renderContext, updateCallback, selfPtr)
                }
            }
        }
    }
    
    private func triggerRedraw() {
        DispatchQueue.main.async { [weak self] in
            self?.needsDisplay = true
        }
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        guard let glContext = glContext, let renderContext = renderContext else {
            super.draw(dirtyRect)
            return
        }
        
        glContext.makeCurrentContext()
        
        // Query the active framebuffer bound by AppKit/CoreAnimation for this view's layer
        var currentFbo: Int32 = 0
        glGetIntegerv(GL_FRAMEBUFFER_BINDING, &currentFbo)
        
        // Determine backend viewport scale (for Retina displays backing bounds)
        let backingSize = convertToBacking(bounds.size)
        let width = Int32(backingSize.width)
        let height = Int32(backingSize.height)
        
        var fbo = mpv_opengl_fbo(fbo: currentFbo, w: width, h: height, internal_format: 0)
        
        withUnsafeMutablePointer(to: &fbo) { fboPtr in
            var apiName = "opengl".cString(using: .utf8)!
            apiName.withUnsafeMutableBufferPointer { apiNameBuffer in
                var renderParams: [mpv_render_param] = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiNameBuffer.baseAddress),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                ]
                
                mpv_render_context_render(renderContext, &renderParams)
            }
        }
        
        glContext.flushBuffer()
    }
    
    private func setupDisplayLink() {
        guard displayLink == nil else { return }
        
        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, ctx in
            guard let ctx = ctx else { return kCVReturnSuccess }
            let view = Unmanaged<MpvVideoView>.fromOpaque(ctx).takeUnretainedValue()
            view.triggerRedraw()
            return kCVReturnSuccess
        }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        if let link = displayLink {
            CVDisplayLinkSetOutputCallback(link, callback, selfPtr)
            CVDisplayLinkStart(link)
        }
    }
    
    deinit {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        if let renderContext = renderContext {
            mpv_render_context_free(renderContext)
        }
    }
}

public struct MpvVideoViewRepresentable: NSViewRepresentable {
    let player: MpvPlayer
    
    public func makeNSView(context: Context) -> MpvVideoView {
        let view = MpvVideoView()
        view.setPlayer(player)
        return view
    }
    
    public func updateNSView(_ nsView: MpvVideoView, context: Context) {}
}
