import Foundation

public enum RestartPolicy: String, Codable, CaseIterable, Sendable {
    case never = "never"
    case onCrash = "onCrash"
    case always = "always"
}

public enum ServiceStatus: String, Codable, CaseIterable, Sendable {
    case installing = "Installing"
    case starting = "Starting"
    case healthy = "Healthy"
    case restarting = "Restarting"
    case updating = "Updating"
    case stopping = "Stopping"
    case stopped = "Stopped"
    case failed = "Failed"
    case repairing = "Repairing"
    
    public var isRunning: Bool {
        switch self {
        case .starting, .healthy, .restarting, .updating:
            return true
        default:
            return false
        }
    }
}

public struct Service: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let binaryName: String
    public var arguments: [String]
    public var workingDirectory: String?
    public var environment: [String: String]?
    public let healthEndpoint: String
    public var restartPolicy: RestartPolicy
    public var autoStart: Bool
    
    public init(
        id: String,
        name: String,
        binaryName: String,
        arguments: [String],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        healthEndpoint: String,
        restartPolicy: RestartPolicy = .onCrash,
        autoStart: Bool = true
    ) {
        self.id = id
        self.name = name
        self.binaryName = binaryName
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.healthEndpoint = healthEndpoint
        self.restartPolicy = restartPolicy
        self.autoStart = autoStart
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var launchAtLogin: Bool
    public var player: String
    public var theme: String
    public var openLibraryOnLaunch: Bool
    public var quitOnClose: Bool
    public var language: String
    
    public static let defaultSettings = AppSettings(
        launchAtLogin: false,
        player: "IINA",
        theme: "system",
        openLibraryOnLaunch: true,
        quitOnClose: false,
        language: "en"
    )
}

public struct ServiceRelease: Codable, Hashable, Sendable {
    public let version: String
    public let sha256: String
    public let url: String
    
    public init(version: String, sha256: String, url: String) {
        self.version = version
        self.sha256 = sha256
        self.url = url
    }
}

public typealias UpdateManifest = [String: ServiceRelease]
