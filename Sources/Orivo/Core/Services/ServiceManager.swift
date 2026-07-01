import Foundation
import Combine

@MainActor
public final class ServiceManager: ObservableObject {
    public static let shared = ServiceManager()
    
    @Published var services: [Service] = []
    @Published var statuses: [String: ServiceStatus] = [:]
    
    private let appSupportDir: URL
    private let configURL: URL
    public let servicesDir: URL
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.appSupportDir = appSupport.appendingPathComponent("Orivo", isDirectory: true)
        self.configURL = appSupportDir.appendingPathComponent("config/services.json")
        self.servicesDir = appSupportDir.appendingPathComponent("services", isDirectory: true)
        
        setupDirectories()
        loadServices()
        observeEvents()
    }
    
    private func setupDirectories() {
        try? FileManager.default.createDirectory(at: appSupportDir.appendingPathComponent("config"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: servicesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: appSupportDir.appendingPathComponent("cache"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: appSupportDir.appendingPathComponent("logs"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: appSupportDir.appendingPathComponent("updates"), withIntermediateDirectories: true)
    }
    
    public func loadServices() {
        if FileManager.default.fileExists(atPath: configURL.path) {
            do {
                let data = try Data(contentsOf: configURL)
                var decoded = try JSONDecoder().decode([Service].self, from: data)
                
                // Migration: Correct old Jackett command line arguments if present
                for i in 0..<decoded.count {
                    if decoded[i].id == "jackett" {
                        if decoded[i].arguments.contains("--port") || decoded[i].arguments.contains("--NoBrowser") {
                            LogManager.shared.log(serviceId: "system", text: "Migrating old Jackett arguments to support the latest version.")
                            decoded[i].arguments = ["--Port", "9117", "--NoUpdates"]
                        }
                    }
                }
                
                // Migration: Correct TorrServer port to 8090 and set database path
                for i in 0..<decoded.count {
                    if decoded[i].id == "torrserver" {
                        let torrDbPath = self.servicesDir.appendingPathComponent("torrserver").path
                        if decoded[i].arguments.contains("8091") || !decoded[i].arguments.contains("-d") {
                            LogManager.shared.log(serviceId: "system", text: "Migrating TorrServer port and database path to default 8090.")
                            decoded[i].arguments = ["-p", "8090", "-d", torrDbPath]
                            decoded[i].healthEndpoint = "http://127.0.0.1:8090/echo"
                        }
                    }
                }
                
                self.services = decoded
                saveServices()
            } catch {
                LogManager.shared.log(serviceId: "system", text: "Failed to load services.json: \(error.localizedDescription). Reverting to default.", isError: true)
                loadDefaultServices()
            }
        } else {
            loadDefaultServices()
        }
        
        for service in services {
            if statuses[service.id] == nil {
                statuses[service.id] = isBinaryInstalled(service: service) ? .stopped : .failed
            }
        }
    }
    
    private func loadDefaultServices() {
        let torrDbPath = servicesDir.appendingPathComponent("torrserver").path
        let torrserver = Service(
            id: "torrserver",
            name: "TorrServer",
            binaryName: "TorrServer",
            arguments: ["-p", "8090", "-d", torrDbPath],
            workingDirectory: nil,
            environment: nil,
            healthEndpoint: "http://127.0.0.1:8090/echo",
            restartPolicy: .onCrash,
            autoStart: true
        )
        
        let jackett = Service(
            id: "jackett",
            name: "Jackett",
            binaryName: "jackett",
            arguments: ["--Port", "9117", "--NoUpdates"],
            workingDirectory: nil,
            environment: nil,
            healthEndpoint: "http://127.0.0.1:9117/UI/Dashboard",
            restartPolicy: .onCrash,
            autoStart: true
        )
        
        self.services = [torrserver, jackett]
        saveServices()
    }
    
    public func saveServices() {
        do {
            let data = try JSONEncoder().encode(services)
            try data.write(to: configURL)
        } catch {
            LogManager.shared.log(serviceId: "system", text: "Failed to save services.json: \(error.localizedDescription)", isError: true)
        }
    }
    
    public func isBinaryInstalled(service: Service) -> Bool {
        let path = getBinaryPath(for: service)
        return FileManager.default.fileExists(atPath: path)
    }
    
    public func getBinaryPath(for service: Service) -> String {
        let folder = servicesDir.appendingPathComponent(service.id, isDirectory: true)
        return folder.appendingPathComponent(service.binaryName).path
    }
    
    public func setStatus(serviceId: String, status: ServiceStatus) {
        let old = statuses[serviceId] ?? .stopped
        guard old != status else { return }
        
        statuses[serviceId] = status
        LogManager.shared.log(serviceId: serviceId, text: "Status changed from \(old.rawValue) to \(status.rawValue)")
        EventBus.shared.post(.serviceStatusChanged(serviceId: serviceId, oldStatus: old, newStatus: status))
    }
    
    public func start(serviceId: String) {
        guard let service = services.first(where: { $0.id == serviceId }) else { return }
        
        let path = getBinaryPath(for: service)
        guard FileManager.default.fileExists(atPath: path) else {
            setStatus(serviceId: serviceId, status: .failed)
            LogManager.shared.log(serviceId: serviceId, text: "Binary not found. Please run installation or repair.", isError: true)
            return
        }
        
        if serviceId == "jackett" {
            configureJackettFlareSolverr()
        }
        
        setStatus(serviceId: serviceId, status: .starting)
        
        // Asynchronously check if the port is already active (adopting a running system/brew copy)
        checkIfPortActive(endpoint: service.healthEndpoint) { [weak self] isActive in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if isActive {
                    LogManager.shared.log(serviceId: serviceId, text: "Detected active external instance already running on the target port. Adopting it.")
                    self.setStatus(serviceId: serviceId, status: .healthy)
                } else {
                    // Try to launch Orivo's own child process copy
                    do {
                        try ProcessSupervisor.shared.launch(service: service, binaryPath: path)
                    } catch {
                        self.setStatus(serviceId: serviceId, status: .failed)
                        LogManager.shared.log(serviceId: serviceId, text: "Failed to launch service: \(error.localizedDescription)", isError: true)
                    }
                }
            }
        }
    }
    
    public func repairAndStart(serviceId: String) {
        guard let release = UpdateManager.shared.getOnboardingRelease(for: serviceId) else { return }
        UpdateManager.shared.startInstallation(serviceId: serviceId, urlString: release.url, sha256: release.sha256) { success in
            if success {
                self.start(serviceId: serviceId)
            }
        }
    }
    
    private func checkIfPortActive(endpoint: String, completion: @escaping @Sendable (Bool) -> Void) {
        guard let url = URL(string: endpoint) else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.0
        
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if error != nil {
                completion(false)
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                completion((200...399).contains(httpResponse.statusCode))
            } else {
                completion(false)
            }
        }
        task.resume()
    }
    
    public func stop(serviceId: String) {
        setStatus(serviceId: serviceId, status: .stopping)
        ProcessSupervisor.shared.stop(serviceId: serviceId)
        
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if ProcessSupervisor.shared.isAlive(serviceId: serviceId) {
                ProcessSupervisor.shared.killProcess(serviceId: serviceId)
            }
            self.setStatus(serviceId: serviceId, status: .stopped)
        }
    }
    
    public func restart(serviceId: String) {
        setStatus(serviceId: serviceId, status: .restarting)
        stop(serviceId: serviceId)
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            self.start(serviceId: serviceId)
        }
    }
    
    public func startAllAutoStartServices() {
        for service in services where service.autoStart {
            if isBinaryInstalled(service: service) {
                start(serviceId: service.id)
            } else {
                LogManager.shared.log(serviceId: service.id, text: "AutoStart skipped: binary not installed.")
            }
        }
    }
    
    public func stopAllServices() {
        for service in services {
            if statuses[service.id]?.isRunning ?? false {
                stop(serviceId: service.id)
            }
        }
    }
    
    private func observeEvents() {
        EventBus.shared.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                switch event {
                case .serviceStatusChanged(let serviceId, _, let newStatus):
                    if newStatus == .failed {
                        let currentStatus = self?.statuses[serviceId] ?? .stopped
                        if currentStatus != .stopped && currentStatus != .stopping {
                            self?.statuses[serviceId] = .failed
                        }
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    private func configureJackettFlareSolverr() {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let configPath = home.appendingPathComponent("Library/Application Support/Jackett/ServerConfig.json")
        
        guard fileManager.fileExists(atPath: configPath.path) else { return }
        
        do {
            let data = try Data(contentsOf: configPath)
            if var json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                json["FlareSolverrUrl"] = "http://127.0.0.1:8191/"
                let updatedData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
                try updatedData.write(to: configPath)
                LogManager.shared.log(serviceId: "system", text: "Jackett FlareSolverr URL auto-configured to http://127.0.0.1:8191/")
            }
        } catch {
            LogManager.shared.log(serviceId: "system", text: "Failed to auto-configure Jackett FlareSolverr: \(error.localizedDescription)", isError: true)
        }
    }
}
