import SwiftUI
import AppKit
import Cmpv
import Darwin

@_silgen_name("glGetIntegerv")
private func glGetIntegerv(_ pname: UInt32, _ params: UnsafeMutablePointer<Int32>)

@_silgen_name("glViewport")
private func glViewport(_ x: Int32, _ y: Int32, _ width: Int32, _ height: Int32)

private let GL_FRAMEBUFFER_BINDING: UInt32 = 0x8CA6

public class MpvVideoView: NSOpenGLView {
    private var player: MpvPlayer?
    nonisolated(unsafe) private var displayLink: CVDisplayLink?
    
    public init() {
        let attrs: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFAColorSize), 24,
            UInt32(NSOpenGLPFAAlphaSize), 8,
            UInt32(NSOpenGLPFADepthSize), 24,
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            0
        ]
        guard let pf = NSOpenGLPixelFormat(attributes: attrs) else {
            super.init(frame: .zero, pixelFormat: nil)!
            return
        }
        super.init(frame: .zero, pixelFormat: pf)!
        
        self.wantsLayer = true
        self.wantsBestResolutionOpenGLSurface = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
        self.wantsBestResolutionOpenGLSurface = true
    }
    
    public func setPlayer(_ player: MpvPlayer) {
        self.player = player
        
        if let glContext = self.openGLContext {
            player.setupRenderContext(glContext: glContext)
        }
        
        player.onRenderUpdate = { [weak self] in
            DispatchQueue.main.async {
                self?.needsDisplay = true
            }
        }
    }
    
    public override func prepareOpenGL() {
        super.prepareOpenGL()
        if let glContext = self.openGLContext {
            glContext.makeCurrentContext()
            var swapInterval: GLint = 1
            glContext.setValues(&swapInterval, for: .swapInterval)
        }
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        guard let glContext = self.openGLContext, let player = player else {
            super.draw(dirtyRect)
            return
        }
        
        glContext.makeCurrentContext()
        
        var currentFbo: Int32 = 0
        glGetIntegerv(GL_FRAMEBUFFER_BINDING, &currentFbo)
        
        let backingSize = convertToBacking(bounds.size)
        let width = Int32(backingSize.width)
        let height = Int32(backingSize.height)
        
        glViewport(0, 0, width, height)
        
        player.render(fbo: currentFbo, width: width, height: height)
        
        glContext.flushBuffer()
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // CVDisplayLink is disabled to avoid flooding the main runloop with async redraw calls at 60Hz/120Hz.
        // We rely solely on the reactive player.onRenderUpdate callback which triggers only when new decoded frames are ready.
    }
    
    deinit {
        // Cleanup completed
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
