import SwiftUI
import AppKit
import Cmpv
import Darwin

@_silgen_name("glGetIntegerv")
private func glGetIntegerv(_ pname: UInt32, _ params: UnsafeMutablePointer<Int32>)

@_silgen_name("glViewport")
private func glViewport(_ x: Int32, _ y: Int32, _ width: Int32, _ height: Int32)

private let GL_FRAMEBUFFER_BINDING: UInt32 = 0x8CA6

private final class MpvGLView: NSOpenGLView {
    private weak var parent: MpvVideoView?
    
    init?(pixelFormat pf: NSOpenGLPixelFormat, parent: MpvVideoView) {
        self.parent = parent
        super.init(frame: .zero, pixelFormat: pf)
        self.wantsBestResolutionOpenGLSurface = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareOpenGL() {
        super.prepareOpenGL()
        if let glContext = self.openGLContext {
            glContext.makeCurrentContext()
            var swapInterval: GLint = 1
            glContext.setValues(&swapInterval, for: .swapInterval)
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        guard let glContext = self.openGLContext, let parent = parent, let player = parent.player else {
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
}

public class MpvVideoView: NSView {
    fileprivate var player: MpvPlayer?
    private var glView: MpvGLView?
    
    public init() {
        super.init(frame: .zero)
        self.wantsLayer = true
        
        let attrs: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFAColorSize), 24,
            UInt32(NSOpenGLPFAAlphaSize), 8,
            UInt32(NSOpenGLPFADepthSize), 24,
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            0
        ]
        
        if let pf = NSOpenGLPixelFormat(attributes: attrs) {
            if let glView = MpvGLView(pixelFormat: pf, parent: self) {
                glView.autoresizingMask = [.width, .height]
                self.addSubview(glView)
                self.glView = glView
            }
        }
        
        if self.glView == nil {
            LogManager.shared.log(serviceId: "system", text: "MpvVideoView error: Failed to initialize OpenGL context. Video rendering will be unavailable.", isError: true)
        }
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
    }
    
    public override func layout() {
        super.layout()
        glView?.frame = self.bounds
    }
    
    public func setPlayer(_ player: MpvPlayer) {
        self.player = player
        
        if let glView = self.glView, let glContext = glView.openGLContext {
            player.setupRenderContext(glContext: glContext)
        }
        
        player.onRenderUpdate = { [weak self] in
            DispatchQueue.main.async {
                self?.glView?.needsDisplay = true
            }
        }
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
