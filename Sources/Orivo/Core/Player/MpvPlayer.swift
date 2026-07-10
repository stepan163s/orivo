import Foundation
import Cmpv
import AppKit

public struct MpvTrack: Identifiable, Hashable, Sendable {
    public var id: Int { trackId }
    public let trackId: Int
    public let type: String // "audio", "sub", "video"
    public let lang: String?
    public let title: String?
    public let isSelected: Bool
    
    public var displayName: String {
        var parts: [String] = []
        if let title = title, !title.isEmpty {
            parts.append(title)
        }
        if let lang = lang, !lang.isEmpty {
            parts.append("[\(lang.uppercased())]")
        }
        if parts.isEmpty {
            if type == "audio" {
                return "Аудиодорожка \(trackId)"
            } else if type == "sub" {
                return "Субтитры \(trackId)"
            } else {
                return "Дорожка \(trackId)"
            }
        }
        return parts.joined(separator: " ")
    }
}

public class MpvPlayer: NSObject, @unchecked Sendable {
    private var handle: OpaquePointer?
    private var eventThread: Thread?
    private var isRunning = false
    
    // Render API context
    nonisolated(unsafe) private var renderContext: OpaquePointer?
    
    public var onPlaybackProgress: ((Double, Double) -> Void)? // currentTime, totalTime
    public var onPlaybackStateChanged: ((Bool) -> Void)? // isPlaying
    public var onRenderUpdate: (() -> Void)?
    
    // Playback state cache
    public private(set) var currentTime: Double = 0.0
    public private(set) var duration: Double = 0.0
    
    private var pendingPlayUrl: String? = nil
    
    private let eventLoopSemaphore = DispatchSemaphore(value: 0)
    
    public override init() {
        AppPerfTracker.shared.start("MpvPlayer Init")
        defer { AppPerfTracker.shared.stop("MpvPlayer Init") }
        
        super.init()
        guard let handle = mpv_create() else {
            LogManager.shared.log(serviceId: "system", text: "MpvPlayer error: Failed to create mpv handle", isError: true)
            return
        }
        self.handle = handle
        
        // Enable VideoToolbox hardware decoding via copy-back to prevent OpenGL NV12 FBO texture corruption
        let hwdec = "videotoolbox-copy"
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
        
        // Disable youtube-dl checks to speed up opening local stream links
        let ytdl = "no"
        _ = ytdl.withCString { ptr in
            mpv_set_option_string(handle, "ytdl", ptr)
        }
        
        // Do not pause on initial cache loading to start playing instantly
        let cachePauseInitial = "no"
        _ = cachePauseInitial.withCString { ptr in
            mpv_set_option_string(handle, "cache-pause-initial", ptr)
        }
        
        // Set network buffer cache size to 60 seconds
        let cacheSecs = "60"
        _ = cacheSecs.withCString { ptr in
            mpv_set_option_string(handle, "cache-secs", ptr)
        }
        
        // Read ahead up to 60 seconds of video
        let readaheadSecs = "60"
        _ = readaheadSecs.withCString { ptr in
            mpv_set_option_string(handle, "demuxer-readahead-secs", ptr)
        }
        
        // Increase maximum demuxer cache bytes to 500MB (524288000 bytes)
        let maxBytes = "524288000"
        _ = maxBytes.withCString { ptr in
            mpv_set_option_string(handle, "demuxer-max-bytes", ptr)
        }
        
        // Force libmpv video output for render API usage
        let vo = "libmpv"
        _ = vo.withCString { ptr in
            mpv_set_option_string(handle, "vo", ptr)
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
        var flipY: Int32 = 1
        
        withUnsafeMutablePointer(to: &openglFbo) { fboPtr in
            withUnsafeMutablePointer(to: &flipY) { flipYPtr in
                var apiName = "opengl".cString(using: .utf8)!
                apiName.withUnsafeMutableBufferPointer { apiNameBuffer in
                    var renderParams: [mpv_render_param] = [
                        mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiNameBuffer.baseAddress),
                        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
                        mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipYPtr),
                        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                    ]
                    
                    mpv_render_context_render(renderContext, &renderParams)
                }
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
    
    public func getTracks(type: String) -> [MpvTrack] {
        guard let handle = handle else { return [] }
        var count: Int64 = 0
        let status = mpv_get_property(handle, "track-list/count", MPV_FORMAT_INT64, &count)
        guard status >= 0 else { return [] }
        
        var tracks: [MpvTrack] = []
        for i in 0..<Int(count) {
            guard let typeCStr = mpv_get_property_string(handle, "track-list/\(i)/type") else { continue }
            let trackType = String(cString: typeCStr)
            mpv_free(typeCStr)
            
            guard trackType == type else { continue }
            
            var trackId: Int64 = 0
            mpv_get_property(handle, "track-list/\(i)/id", MPV_FORMAT_INT64, &trackId)
            
            var lang: String? = nil
            if let langCStr = mpv_get_property_string(handle, "track-list/\(i)/lang") {
                lang = String(cString: langCStr)
                mpv_free(langCStr)
            }
            
            var title: String? = nil
            if let titleCStr = mpv_get_property_string(handle, "track-list/\(i)/title") {
                title = String(cString: titleCStr)
                mpv_free(titleCStr)
            }
            
            var selected: Int32 = 0
            mpv_get_property(handle, "track-list/\(i)/selected", MPV_FORMAT_FLAG, &selected)
            
            tracks.append(MpvTrack(
                trackId: Int(trackId),
                type: trackType,
                lang: lang,
                title: title,
                isSelected: selected != 0
            ))
        }
        return tracks
    }
    
    public func selectTrack(type: String, id: Int?) {
        guard let handle = handle else { return }
        let propName = type == "audio" ? "aid" : "sid"
        let valStr = id != nil ? "\(id!)" : "no"
        _ = valStr.withCString { valPtr in
            mpv_set_property_string(handle, propName, valPtr)
        }
    }
    
    public func getCurrentTrackId(type: String) -> Int? {
        guard let handle = handle else { return nil }
        let propName = type == "audio" ? "aid" : "sid"
        var val: Int64 = 0
        let status = mpv_get_property(handle, propName, MPV_FORMAT_INT64, &val)
        guard status >= 0 && val > 0 else { return nil }
        return Int(val)
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
                            self.currentTime = value
                            self.onPlaybackProgress?(timePos, duration)
                        } else if name == "duration" {
                            duration = value
                            self.duration = value
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
