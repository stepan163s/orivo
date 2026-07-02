import Foundation
import Cmpv
import AppKit

public class MpvPlayer: NSObject, @unchecked Sendable {
    private var handle: OpaquePointer?
    private var eventThread: Thread?
    private var isRunning = false
    
    public var onPlaybackProgress: ((Double, Double) -> Void)? // currentTime, totalTime
    public var onPlaybackStateChanged: ((Bool) -> Void)? // isPlaying
    
    private var isInitialized = false
    private var deferredUrl: String?
    private let eventLoopSemaphore = DispatchSemaphore(value: 0)
    
    public override init() {
        super.init()
        guard let handle = mpv_create() else {
            LogManager.shared.log(serviceId: "system", text: "MpvPlayer error: Failed to create mpv handle", isError: true)
            return
        }
        self.handle = handle
        
        // Configure options
        // Enable hardware decoding for low CPU usage
        let hwdec = "auto"
        _ = hwdec.withCString { ptr in
            mpv_set_option_string(handle, "hwdec", ptr)
        }
        
        // Disable terminal output spam
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
        
        // Cache up to 300 seconds ahead
        let cacheSecs = "300"
        _ = cacheSecs.withCString { ptr in
            mpv_set_option_string(handle, "cache-secs", ptr)
        }
        
        // Force OpenGL API on macOS to prevent Vulkan/MoltenVK context initialization crashes
        let gpuApi = "opengl"
        _ = gpuApi.withCString { ptr in
            mpv_set_option_string(handle, "gpu-api", ptr)
        }
        
        // Force Cocoa OpenGL context wrapper for rendering inside NSView (wid)
        let gpuContext = "cocoa"
        _ = gpuContext.withCString { ptr in
            mpv_set_option_string(handle, "gpu-context", ptr)
        }
    }
    
    deinit {
        destroy()
    }
    
    public func destroy() {
        guard let handle = self.handle else { return }
        self.isRunning = false
        
        // Wait for the event thread to exit safely before destroying the handle
        _ = eventLoopSemaphore.wait(timeout: .now() + 0.5)
        
        mpv_terminate_destroy(handle)
        self.handle = nil
    }
    
    @MainActor
    public func attach(to nsView: NSView) {
        guard let handle = handle else { return }
        guard nsView.window != nil else {
            LogManager.shared.log(serviceId: "system", text: "MpvPlayer: Deferring attach because NSView is not in a window yet")
            return
        }
        if isInitialized {
            LogManager.shared.log(serviceId: "system", text: "MpvPlayer: Already attached and initialized")
            return
        }
        
        // Ensure the view is layer-backed
        nsView.wantsLayer = true
        guard let layer = nsView.layer else {
            LogManager.shared.log(serviceId: "system", text: "MpvPlayer error: NSView has no CALayer", isError: true)
            return
        }
        
        // On macOS, the "wid" option takes the raw pointer address to the CALayer.
        // MUST be set before mpv_initialize() to prevent mpv from creating a fallback standalone window.
        var layerAddress = Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque())
        let status = mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &layerAddress)
        if status < 0 {
            let errString = String(cString: mpv_error_string(status))
            LogManager.shared.log(serviceId: "system", text: "MpvPlayer error: Failed to set CALayer option (wid): \(errString)", isError: true)
        }
        
        // Start initialization with options fully loaded and wid bound
        let initStatus = mpv_initialize(handle)
        if initStatus < 0 {
            let errString = String(cString: mpv_error_string(initStatus))
            LogManager.shared.log(serviceId: "system", text: "MpvPlayer error: Failed to initialize mpv: \(errString)", isError: true)
            return
        }
        
        self.isInitialized = true
        self.isRunning = true
        startEventLoop()
        LogManager.shared.log(serviceId: "system", text: "MpvPlayer successfully attached and initialized with NSView")
        
        if let url = deferredUrl {
            deferredUrl = nil
            play(url: url)
        }
    }
    
    public func play(url: String) {
        guard self.handle != nil else { return }
        if !isInitialized {
            LogManager.shared.log(serviceId: "system", text: "MpvPlayer: play() called before initialization, deferring URL: \(url)")
            self.deferredUrl = url
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
    
    public func togglePause() {
        guard let handle = handle else { return }
        var pause: Int32 = 0
        mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &pause)
        var newPause: Int32 = (pause == 0) ? 1 : 0
        mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &newPause)
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
