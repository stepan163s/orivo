import Foundation
import Combine

@MainActor
public final class Watchdog {
    public static let shared = Watchdog()
    
    private var timer: AnyCancellable?
    private var consecutiveFailures: [String: Int] = [:]
    private var restartAttempts: [String: Int] = [:]
    private let checkQueue = DispatchQueue(label: "com.orivo.watchdog", attributes: .concurrent)
    
    private init() {}
    
    public func startMonitoring() {
        guard timer == nil else { return }
        
        timer = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Call main actor method
                self.performHealthChecks()
            }
        LogManager.shared.log(serviceId: "system", text: "Watchdog service monitoring started.")
    }
    
    public func stopMonitoring() {
        timer?.cancel()
        timer = nil
        LogManager.shared.log(serviceId: "system", text: "Watchdog service monitoring stopped.")
    }
    
    private func performHealthChecks() {
        let services = ServiceManager.shared.services
        let statuses = ServiceManager.shared.statuses
        
        for service in services {
            let status = statuses[service.id] ?? .stopped
            
            guard status.isRunning else { continue }
            
            checkHealth(of: service) { isHealthy in
                DispatchQueue.main.async {
                    self.handleHealthResult(for: service, isHealthy: isHealthy)
                }
            }
        }
    }
    
    private func checkHealth(of service: Service, completion: @escaping @Sendable (Bool) -> Void) {
        guard let url = URL(string: service.healthEndpoint) else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3.0
        
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if error != nil {
                completion(false)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                // Hitting custom health check endpoints like /echo on TorrServer returns 404 Not Found,
                // which indicates the server is active, listening, and responsive.
                let healthy = (200...399).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 || httpResponse.statusCode == 405
                completion(healthy)
            } else {
                completion(false)
            }
        }
        task.resume()
    }
    
    private func handleHealthResult(for service: Service, isHealthy: Bool) {
        let serviceId = service.id
        let currentStatus = ServiceManager.shared.statuses[serviceId] ?? .stopped
        
        if isHealthy {
            consecutiveFailures[serviceId] = 0
            restartAttempts[serviceId] = 0
            if currentStatus == .starting || currentStatus == .restarting || currentStatus == .failed || currentStatus == .stopped {
                ServiceManager.shared.setStatus(serviceId: serviceId, status: .healthy)
            }
        } else {
            let failures = (consecutiveFailures[serviceId] ?? 0) + 1
            consecutiveFailures[serviceId] = failures
            
            if currentStatus != .failed && currentStatus != .stopping {
                LogManager.shared.log(serviceId: serviceId, text: "Health check unresponsive (attempt \(failures))", isError: false)
            }
            
            let hasLocalProcess = ProcessSupervisor.shared.hasProcess(serviceId: serviceId)
            let processAlive = ProcessSupervisor.shared.isAlive(serviceId: serviceId)
            
            if (hasLocalProcess && !processAlive) || failures >= 3 {
                handleServiceFailure(service: service)
            }
        }
    }
    
    private func handleServiceFailure(service: Service) {
        let serviceId = service.id
        let policy = service.restartPolicy
        let attempts = restartAttempts[serviceId] ?? 0
        let currentStatus = ServiceManager.shared.statuses[serviceId] ?? .stopped
        
        if currentStatus != .failed {
            ServiceManager.shared.setStatus(serviceId: serviceId, status: .failed)
        }
        
        if policy == .always || (policy == .onCrash && attempts < 3) {
            restartAttempts[serviceId] = attempts + 1
            LogManager.shared.log(serviceId: serviceId, text: "Watchdog triggering auto-restart (attempt \(attempts + 1) of 3) based on restart policy: \(policy.rawValue)")
            ServiceManager.shared.restart(serviceId: serviceId)
        } else if attempts >= 3 {
            LogManager.shared.log(serviceId: serviceId, text: "Watchdog stopped auto-restart to prevent infinite CPU spin (max attempts reached).", isError: true)
            EventBus.shared.post(.message(
                title: "\(service.name) Failure",
                body: "The service crashed repeatedly. Please inspect logs or reinstall.",
                isWarning: true
            ))
            
            restartAttempts[serviceId] = 0
        }
    }
}
