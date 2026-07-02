import SwiftUI
import AppKit
import Cmpv
import Darwin

@_silgen_name("glGetIntegerv")
private func glGetIntegerv(_ pname: UInt32, _ params: UnsafeMutablePointer<Int32>)

@_silgen_name("glViewport")
private func glViewport(_ x: Int32, _ y: Int32, _ width: Int32, _ height: Int32)

private let GL_FRAMEBUFFER_BINDING: UInt32 = 0x8CA6

public class MpvVideoView: NSView {
    private var glContext: NSOpenGLContext?
    private var pixelFormat: NSOpenGLPixelFormat?
    private var player: MpvPlayer?
    nonisolated(unsafe) private var displayLink: CVDisplayLink?
    private var isConfigured = false
    
    public func setPlayer(_ player: MpvPlayer) {
        self.player = player
        setupGL()
        
        player.onRenderUpdate = { [weak self] in
            DispatchQueue.main.async {
                self?.needsDisplay = true
            }
        }
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            setupDisplayLink()
        } else {
            stopDisplayLinkInternal()
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
        
        // Let the player setup its rendering context with our OpenGL context
        if let player = player {
            player.setupRenderContext(glContext: glContext)
        }
    }
    
    private func triggerRedraw() {
        DispatchQueue.main.async { [weak self] in
            self?.needsDisplay = true
        }
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        guard let glContext = glContext, let player = player else {
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
        
        // Set OpenGL viewport to match the backing scale size
        glViewport(0, 0, width, height)
        
        // Tell player to render the frame into our active FBO
        player.render(fbo: currentFbo, width: width, height: height)
        
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
    
    private func stopDisplayLinkInternal() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            self.displayLink = nil
        }
    }
    
    deinit {
        if let link = displayLink {
            CVDisplayLinkStop(link)
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
