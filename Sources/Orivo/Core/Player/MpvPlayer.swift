import Foundation
import Cmpv
import AppKit

public class MpvPlayer: NSObject, @unchecked Sendable {
    private var handle: OpaquePointer?
    private var eventThread: Thread?
    private var isRunning = false
    
    public var onPlaybackProgress: ((Double, Double) -> Void)? // currentTime, totalTime
    public var onPlaybackStateChanged: ((Bool) -> Void)? // isPlaying
    
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
        isRunning = false
        if let handle = handle {
            mpv_terminate_destroy(handle)
            self.handle = nil
        }
    }
    
    public func attach(to nsView: NSView) {
        guard let handle = handle else { return }
        
        // On macOS, the "wid" option takes the raw pointer address to the NSView
        var viewAddress = Int(bitPattern: Unmanaged.passUnretained(nsView).toOpaque())
        let status = mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &viewAddress)
        if status < 0 {
            let errString = String(cString: mpv_error_string(status))
            LogManager.shared.log(serviceId: "system", text: "MpvPlayer error: Failed to attach NSView (wid): \(errString)", isError: true)
        } else {
            LogManager.shared.log(serviceId: "system", text: "MpvPlayer successfully attached to NSView")
        }
    }
    
    public func play(url: String) {
        guard self.handle != nil else { return }
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
