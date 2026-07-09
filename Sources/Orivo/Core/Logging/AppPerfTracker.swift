import Foundation

public final class AppPerfTracker: @unchecked Sendable {
    public static let shared = AppPerfTracker()
    
    private var timestamps: [String: Double] = [:]
    private let lock = NSLock()
    
    private init() {}
    
    public func start(_ event: String) {
        lock.lock()
        timestamps[event] = ProcessInfo.processInfo.systemUptime
        lock.unlock()
        LogManager.shared.log(serviceId: "system", text: "[PERF_START] \(event)")
    }
    
    public func stop(_ event: String) {
        lock.lock()
        let startTime = timestamps[event]
        lock.unlock()
        
        if let start = startTime {
            let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
            LogManager.shared.log(serviceId: "system", text: String(format: "[PERF_END] %@ took %.2f ms", event, elapsed))
        } else {
            LogManager.shared.log(serviceId: "system", text: "[PERF_END] \(event) (start time unknown)")
        }
    }
}
