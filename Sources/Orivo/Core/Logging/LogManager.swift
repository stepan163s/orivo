import Foundation

public final class LogManager: @unchecked Sendable {
    public static let shared = LogManager()
    
    private let logDirectory: URL
    private let queue = DispatchQueue(label: "com.orivo.logmanager", attributes: .concurrent)
    private var inMemoryLogs: [String: [String]] = [:] // serviceId -> list of log lines
    private let maxMemoryLines = 5000
    private var fileHandles: [String: FileHandle] = [:]
    nonisolated(unsafe) private static let dateFormatter = ISO8601DateFormatter()
    
    private init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Cannot locate Application Support directory — system is misconfigured.")
        }
        self.logDirectory = appSupport.appendingPathComponent("Orivo/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }
    
    public func log(serviceId: String, text: String, isError: Bool = false) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        
        let timestamp = Self.dateFormatter.string(from: Date())
        let typeStr = isError ? "[ERROR]" : "[INFO]"
        let line = "[\(timestamp)] \(typeStr) \(cleanText)"
        
        EventBus.shared.post(.logReceived(serviceId: serviceId, text: line, isError: isError))
        
        queue.async(flags: .barrier) {
            var current = self.inMemoryLogs[serviceId] ?? []
            current.append(line)
            if current.count > self.maxMemoryLines {
                current.removeFirst(current.count - self.maxMemoryLines)
            }
            self.inMemoryLogs[serviceId] = current
        }
        
        queue.async(flags: .barrier) {
            self.writeToDisk(serviceId: serviceId, line: line + "\n")
        }
    }
    
    public func getLogs(for serviceId: String) -> [String] {
        var result: [String] = []
        queue.sync {
            result = self.inMemoryLogs[serviceId] ?? []
        }
        return result
    }
    
    public func clearMemoryLogs(for serviceId: String) {
        queue.async(flags: .barrier) {
            self.inMemoryLogs[serviceId] = []
        }
    }
    
    private func writeToDisk(serviceId: String, line: String) {
        let fileURL = logDirectory.appendingPathComponent("\(serviceId).log")
        
        // Rotate log file if it exceeds 5 MB
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int, size > 5 * 1024 * 1024 {
            rotateLog(serviceId: serviceId, fileURL: fileURL)
        }
        
        writeToDiskDirect(serviceId: serviceId, line: line)
    }
    
    private func writeToDiskDirect(serviceId: String, line: String) {
        let fileURL = logDirectory.appendingPathComponent("\(serviceId).log")
        if fileHandles[serviceId] == nil {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                _ = try? handle.seekToEnd()
                fileHandles[serviceId] = handle
            }
        }
        
        if let handle = fileHandles[serviceId] {
            if let data = line.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        }
    }
    
    private func rotateLog(serviceId: String, fileURL: URL) {
        // Close existing handle
        try? fileHandles[serviceId]?.close()
        fileHandles[serviceId] = nil
        
        // Keep last 2000 lines
        let timestamp = Self.dateFormatter.string(from: Date())
        if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
            let lines = content.components(separatedBy: "\n")
            let kept = lines.suffix(2000).joined(separator: "\n")
            let header = "--- Log rotated at \(timestamp) (kept last 2000 lines) ---\n"
            try? (header + kept).write(to: fileURL, atomically: true, encoding: .utf8)
        }
        
        // Directly append to system memory logs and write to disk without calling LogManager.shared.log()
        // to avoid infinite recursive call loops if the system log is being rotated.
        let infoLine = "[\(timestamp)] [INFO] Log file rotated for service: \(serviceId)"
        
        var current = self.inMemoryLogs["system"] ?? []
        current.append(infoLine)
        if current.count > self.maxMemoryLines {
            current.removeFirst(current.count - self.maxMemoryLines)
        }
        self.inMemoryLogs["system"] = current
        
        EventBus.shared.post(.logReceived(serviceId: "system", text: infoLine, isError: false))
        writeToDiskDirect(serviceId: "system", line: infoLine + "\n")
    }
    
    public func closeAllHandles() {
        queue.sync(flags: .barrier) {
            for (serviceId, handle) in fileHandles {
                try? handle.close()
                fileHandles[serviceId] = nil
            }
        }
    }
}
