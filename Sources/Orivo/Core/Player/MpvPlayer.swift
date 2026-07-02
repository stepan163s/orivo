import Foundation
import Cmpv
import AppKit

public class MpvPlayer: NSObject, @unchecked Sendable {
    private var handle: OpaquePointer?
    private var eventThread: Thread?
    private var isRunning = false
    
    // Render API context
    nonisolated(unsafe) private var renderContext: OpaquePointer?
    
    public var onPlaybackProgress: ((Double, Double) -> Void)? // currentTime, totalTime
    public var onPlaybackStateChanged: ((Bool) -> Void)? // isPlaying
    public var onRenderUpdate: (() -> Void)?
    
    private var pendingPlayUrl: String? = nil
    
    private let eventLoopSemaphore = DispatchSemaphore(value: 0)
    
    public override init() {
        super.init()
        guard let handle = mpv_create() else {
            LogManager.shared.log(serviceId: "system", text: "MpvPlayer error: Failed to create mpv handle", isError: true)
            return
        }
        self.handle = handle
        
        // Configure options
        // Disable hardware decoding to prevent NV12 FBO texture corruption on Apple Silicon
        let hwdec = "no"
        _ = hwdec.withCString { ptr in
            mpv_set_option_string(handle, "hwdec", ptr)
        }
        
        // Disable terminal output spam since we're redirecting via callback
        let terminal = "no"
        _ = terminal.withCString { ptr in
            mpv_set_option_string(handle, "terminal", ptr)
        }
        
        // Enable cache explicitly (so loopback HTTP streams are cached)
        let cache = "yes"
        _ = cache.withCString { ptr in
            mpv_set_option_string(handle, "cache", ptr)
        }
        
        // Set maximum demuxer cache bytes to 150MB
        let maxBytes = "157286400"
        _ = maxBytes.withCString { ptr in
            mpv_set_option_string(handle, "demuxer-max-bytes", ptr)
        }
        
        // Force libmpv video output for render API usage
        let vo = "libmpv"
        _ = vo.withCString { ptr in
            mpv_set_option_string(handle, "vo", ptr)
        }
        
        // Flip video vertically because OpenGL has inverted Y axis compared to Core Animation layers
        let vf = "vflip"
        _ = vf.withCString { ptr in
            mpv_set_option_string(handle, "vf", ptr)
        }
        
        // Request internal logs from mpv at info level
        mpv_request_log_messages(handle, "info")
        
        // Start initialization
        let status = mpv_initialize(handle)
        if status < 0 {
            let errString = String(cString: mpv_error_string(status))
            LogManager.shared.log(serviceId: "system", text: "MpvPlayer error: Failed to initialize mpv: \(errString)", isError: true)
            return
        }
        
        self.isRunning = true
        startEventLoop()
    }
    
    deinit {
        destroy()
    }
    
    public func destroy() {
        self.isRunning = false
        
        // Wait for the event thread to exit safely before destroying the handle
        _ = eventLoopSemaphore.wait(timeout: .now() + 0.5)
        
        if let renderContext = renderContext {
            mpv_render_context_free(renderContext)
            self.renderContext = nil
        }
        
        if let handle = handle {
            mpv_terminate_destroy(handle)
            self.handle = nil
        }
    }
    
    public func getHandle() -> OpaquePointer? {
        return handle
    }
    
    public func setupRenderContext(glContext: NSOpenGLContext) {
        guard let handle = handle else { return }
        if renderContext != nil { return }
        
        glContext.makeCurrentContext()
        
        // C-compatible function pointer for OpenGL dynamic loading
        let getProcAddress: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? = { _, name in
            guard let name = name else { return nil }
            return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
        }
        
        var glParams = mpv_opengl_init_params(
            get_proc_address: getProcAddress,
            get_proc_address_ctx: nil
        )
        
        withUnsafeMutablePointer(to: &glParams) { glParamsPtr in
            var apiName = "opengl".cString(using: .utf8)!
            apiName.withUnsafeMutableBufferPointer { apiNameBuffer in
                var params: [mpv_render_param] = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiNameBuffer.baseAddress),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: glParamsPtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                ]
                
                let status = mpv_render_context_create(&self.renderContext, handle, &params)
                if status < 0 {
                    let errString = String(cString: mpv_error_string(status))
                    LogManager.shared.log(serviceId: "system", text: "MpvPlayer error: Failed to create render context: \(errString)", isError: true)
                } else {
                    LogManager.shared.log(serviceId: "system", text: "MpvPlayer successfully initialized render context")
                    
                    // Set update callback to trigger redraws when new video frames arrive
                    let updateCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { ctx in
                        guard let ctx = ctx else { return }
                        let player = Unmanaged<MpvPlayer>.fromOpaque(ctx).takeUnretainedValue()
                        player.onRenderUpdate?()
                    }
                    
                    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
                    mpv_render_context_set_update_callback(self.renderContext, updateCallback, selfPtr)
                    
                    // If we had a deferred play request, trigger it now
                    if let pendingUrl = self.pendingPlayUrl {
                        self.pendingPlayUrl = nil
                        self.play(url: pendingUrl)
                    }
                }
            }
        }
    }
    
    public func render(fbo: Int32, width: Int32, height: Int32) {
        guard let renderContext = renderContext else { return }
        
        var openglFbo = mpv_opengl_fbo(fbo: fbo, w: width, h: height, internal_format: 0)
        
        withUnsafeMutablePointer(to: &openglFbo) { fboPtr in
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
    }
    
    public func play(url: String) {
        guard self.handle != nil else { return }
        
        if self.renderContext == nil {
            LogManager.shared.log(serviceId: "system", text: "MpvPlayer play: deferring URL load until render context is setup: \(url)")
            self.pendingPlayUrl = url
            return
        }
        
        LogManager.shared.log(serviceId: "system", text: "MpvPlayer loading URL: \(url)")
        
        let command = ["loadfile", url, "replace"]
        execute(command: command)
        
        // Start observing vital player properties
        observeProperty(name: "time-pos", format: MPV_FORMAT_DOUBLE)
        observeProperty(name: "duration", format: MPV_FORMAT_DOUBLE)
        observeProperty(name: "pause", format: MPV_FORMAT_FLAG)
    }
    
    public func play() {
        guard let handle = handle else { return }
        var pause: Int32 = 0
        mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &pause)
    }
    
    public func pause() {
        guard let handle = handle else { return }
        var pause: Int32 = 1
        mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &pause)
    }
    
    public func togglePause() {
        guard let handle = handle else { return }
        var pause: Int32 = 0
        mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &pause)
        var newPause: Int32 = (pause == 0) ? 1 : 0
        mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &newPause)
    }
    
    public func setSpeed(_ speed: Double) {
        guard let handle = handle else { return }
        var val = speed
        mpv_set_property(handle, "speed", MPV_FORMAT_DOUBLE, &val)
    }
    
    public func seek(to seconds: Double) {
        let command = ["seek", String(seconds), "absolute"]
        execute(command: command)
    }
    
    public func setVolume(_ volume: Int) {
        guard let handle = handle else { return }
        var vol = Double(volume)
        mpv_set_property(handle, "volume", MPV_FORMAT_DOUBLE, &vol)
    }
    
    public func cycleSubtitles() {
        execute(command: ["cycle", "sub"])
    }
    
    public func cycleAudio() {
        execute(command: ["cycle", "audio"])
    }
    
    private func observeProperty(name: String, format: mpv_format) {
        guard let handle = handle else { return }
        name.withCString { ptr in
            let id = UInt64(abs(name.hashValue))
            mpv_observe_property(handle, id, ptr, format)
        }
    }
    
    private func execute(command: [String]) {
        guard let handle = handle else { return }
        
        let cStrings = command.map { strdup($0) }
        defer {
            for ptr in cStrings {
                if let ptr = ptr {
                    free(ptr)
                }
            }
        }
        
        var ptrs = cStrings.map { UnsafePointer<CChar>($0) } + [nil]
        
        ptrs.withUnsafeMutableBufferPointer { buffer in
            if let baseAddress = buffer.baseAddress {
                let status = mpv_command(handle, baseAddress)
                if status < 0 {
                    let errString = String(cString: mpv_error_string(status))
                    LogManager.shared.log(serviceId: "system", text: "MpvPlayer command failed: \(errString)", isError: true)
                }
            }
        }
    }
    
    private func startEventLoop() {
        eventThread = Thread { [weak self] in
            defer {
                self?.eventLoopSemaphore.signal()
            }
            guard let self = self else { return }
            var duration: Double = 0.0
            var timePos: Double = 0.0
            
            while self.isRunning, let handle = self.handle {
                let eventPtr = mpv_wait_event(handle, 0.1)
                guard let event = eventPtr?.pointee else { continue }
                
                if event.event_id == MPV_EVENT_SHUTDOWN {
                    break
                }
                
                if event.event_id == MPV_EVENT_LOG_MESSAGE {
                    let log = event.data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
                    let prefix = String(cString: log.prefix)
                    let text = String(cString: log.text).trimmingCharacters(in: .whitespacesAndNewlines)
                    let level = String(cString: log.level)
                    LogManager.shared.log(serviceId: "system", text: "[mpv] [\(level)] [\(prefix)] \(text)")
                }
                
                if event.event_id == MPV_EVENT_PROPERTY_CHANGE {
                    let prop = event.data.assumingMemoryBound(to: mpv_event_property.self).pointee
                    let name = String(cString: prop.name)
                    
                    if prop.format == MPV_FORMAT_DOUBLE {
                        let value = prop.data.assumingMemoryBound(to: Double.self).pointee
                        if name == "time-pos" {
                            timePos = value
                            self.onPlaybackProgress?(timePos, duration)
                        } else if name == "duration" {
                            duration = value
                            self.onPlaybackProgress?(timePos, duration)
                        }
                    } else if prop.format == MPV_FORMAT_FLAG {
                        let paused = prop.data.assumingMemoryBound(to: Int32.self).pointee
                        self.onPlaybackStateChanged?(paused == 0)
                    }
                }
            }
        }
        eventThread?.name = "com.orivo.player.events"
        eventThread?.start()
    }
}
