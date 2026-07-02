import Foundation

public final class ProcessSupervisor: @unchecked Sendable {
    public static let shared = ProcessSupervisor()
    
    private var processes: [String: Process] = [:]
    private var exitCodes: [String: Int32] = [:]
    private let queue = DispatchQueue(label: "com.orivo.supervisor", attributes: .concurrent)
    
    private init() {}
    
    public func launch(service: Service, binaryPath: String) throws {
        try queue.sync(flags: .barrier) {
            // Check if already running in supervisor
            if let existing = processes[service.id], existing.isRunning {
                LogManager.shared.log(serviceId: service.id, text: "Service is already running.")
                return
            }
            
            // Forcibly kill any running processes with the same binary name to clean up orphaned instances from previous crashes
            let killTask = Process()
            killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            killTask.arguments = ["-x", service.binaryName]
            try? killTask.run()
            killTask.waitUntilExit()
            
            // Give the OS a fraction of a second to release the bound sockets
            Thread.sleep(forTimeInterval: 0.1)
            
            LogManager.shared.log(serviceId: service.id, text: "Launching process from binary: \(binaryPath)")
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = service.arguments
            
            // Set environment
            var env = ProcessInfo.processInfo.environment
            if let serviceEnv = service.environment {
                for (key, val) in serviceEnv {
                    env[key] = val
                }
            }
            process.environment = env
            
            // Set working directory
            if let workDir = service.workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workDir)
            } else {
                process.currentDirectoryURL = URL(fileURLWithPath: (binaryPath as NSString).deletingLastPathComponent)
            }
            
            // Pipes for standard output and standard error
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            // Setup asynchronous readability handlers
            let serviceId = service.id
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let output = String(data: data, encoding: .utf8) {
                    LogManager.shared.log(serviceId: serviceId, text: output, isError: false)
                }
            }
            
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let output = String(data: data, encoding: .utf8) {
                    LogManager.shared.log(serviceId: serviceId, text: output, isError: true)
                }
            }
            
            // Setup termination handler
            process.terminationHandler = { [weak self] completedProcess in
                // Crucial: Clear readability handlers to prevent leaks and cpu spin
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                
                let exitStatus = completedProcess.terminationStatus
                LogManager.shared.log(serviceId: serviceId, text: "Process exited with code \(exitStatus)")
                
                if let supervisor = self {
                    supervisor.handleProcessExit(serviceId: serviceId, exitStatus: exitStatus)
                }
            }
            
            try process.run()
            self.processes[service.id] = process
            self.exitCodes[service.id] = nil
        }
    }
    
    private func handleProcessExit(serviceId: String, exitStatus: Int32) {
        queue.async(flags: .barrier) {
            self.processes[serviceId] = nil
            self.exitCodes[serviceId] = exitStatus
            
            // Let the watchdog / service manager handle restart or crash reporting
            EventBus.shared.post(.serviceStatusChanged(serviceId: serviceId, oldStatus: .healthy, newStatus: .failed))
        }
    }
    
    public func stop(serviceId: String) {
        queue.sync(flags: .barrier) {
            guard let process = processes[serviceId], process.isRunning else {
                LogManager.shared.log(serviceId: serviceId, text: "Cannot stop: Process is not running.")
                return
            }
            LogManager.shared.log(serviceId: serviceId, text: "Sending termination signal to process.")
            process.terminate()
        }
    }
    
    public func killProcess(serviceId: String) {
        queue.sync(flags: .barrier) {
            guard let process = processes[serviceId], process.isRunning else {
                return
            }
            LogManager.shared.log(serviceId: serviceId, text: "Forcibly killing process.")
            let pid = process.processIdentifier
            kill(pid, SIGKILL)
        }
    }
    
    public func isAlive(serviceId: String) -> Bool {
        var alive = false
        queue.sync {
            if let process = processes[serviceId] {
                alive = process.isRunning
            }
        }
        return alive
    }
    
    public func hasProcess(serviceId: String) -> Bool {
        var has = false
        queue.sync {
            has = processes[serviceId] != nil
        }
        return has
    }
    
    public func getExitCode(serviceId: String) -> Int32? {
        var code: Int32?
        queue.sync {
            code = exitCodes[serviceId]
        }
        return code
    }
    
    public func killAllSync() {
        queue.sync(flags: .barrier) {
            for (serviceId, process) in processes {
                if process.isRunning {
                    LogManager.shared.log(serviceId: serviceId, text: "Synchronously terminating process.")
                    process.terminate()
                }
            }
            
            // Wait up to 1 second for processes to shut down gracefully
            let start = Date()
            while Date().timeIntervalSince(start) < 1.0 {
                let anyAlive = processes.values.contains { $0.isRunning }
                if !anyAlive { break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            
            for (serviceId, process) in processes {
                if process.isRunning {
                    LogManager.shared.log(serviceId: serviceId, text: "Synchronously killing process (SIGKILL).")
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            
            processes.removeAll()
        }
    }
}
