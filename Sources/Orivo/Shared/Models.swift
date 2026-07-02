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
    public var healthEndpoint: String
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
    public var torrserverHost: String
    public var jackettHost: String
    public var useTorrServer: Bool
    public var useJackett: Bool
    
    // External servers configuration
    public var useExternalServers: Bool
    public var externalLampaURL: String
    public var externalTorrServerHost: String
    public var externalJackettHost: String
    public var externalJackettApiKey: String
    
    public init(
        launchAtLogin: Bool,
        player: String,
        theme: String,
        openLibraryOnLaunch: Bool,
        quitOnClose: Bool,
        language: String,
        torrserverHost: String = "http://127.0.0.1:8090",
        jackettHost: String = "http://127.0.0.1:9117",
        useTorrServer: Bool = true,
        useJackett: Bool = true,
        useExternalServers: Bool = false,
        externalLampaURL: String = "",
        externalTorrServerHost: String = "",
        externalJackettHost: String = "",
        externalJackettApiKey: String = ""
    ) {
        self.launchAtLogin = launchAtLogin
        self.player = player
        self.theme = theme
        self.openLibraryOnLaunch = openLibraryOnLaunch
        self.quitOnClose = quitOnClose
        self.language = language
        self.torrserverHost = torrserverHost
        self.jackettHost = jackettHost
        self.useTorrServer = useTorrServer
        self.useJackett = useJackett
        self.useExternalServers = useExternalServers
        self.externalLampaURL = externalLampaURL
        self.externalTorrServerHost = externalTorrServerHost
        self.externalJackettHost = externalJackettHost
        self.externalJackettApiKey = externalJackettApiKey
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.player = try container.decodeIfPresent(String.self, forKey: .player) ?? "IINA"
        self.theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? "system"
        self.openLibraryOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .openLibraryOnLaunch) ?? true
        self.quitOnClose = try container.decodeIfPresent(Bool.self, forKey: .quitOnClose) ?? false
        self.language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
        self.torrserverHost = try container.decodeIfPresent(String.self, forKey: .torrserverHost) ?? "http://127.0.0.1:8090"
        self.jackettHost = try container.decodeIfPresent(String.self, forKey: .jackettHost) ?? "http://127.0.0.1:9117"
        self.useTorrServer = try container.decodeIfPresent(Bool.self, forKey: .useTorrServer) ?? true
        self.useJackett = try container.decodeIfPresent(Bool.self, forKey: .useJackett) ?? true
        
        self.useExternalServers = try container.decodeIfPresent(Bool.self, forKey: .useExternalServers) ?? false
        self.externalLampaURL = try container.decodeIfPresent(String.self, forKey: .externalLampaURL) ?? ""
        self.externalTorrServerHost = try container.decodeIfPresent(String.self, forKey: .externalTorrServerHost) ?? ""
        self.externalJackettHost = try container.decodeIfPresent(String.self, forKey: .externalJackettHost) ?? ""
        self.externalJackettApiKey = try container.decodeIfPresent(String.self, forKey: .externalJackettApiKey) ?? ""
    }
    
    public static let defaultSettings = AppSettings(
        launchAtLogin: false,
        player: "IINA",
        theme: "system",
        openLibraryOnLaunch: true,
        quitOnClose: false,
        language: "en",
        torrserverHost: "http://127.0.0.1:8090",
        jackettHost: "http://127.0.0.1:9117",
        useTorrServer: true,
        useJackett: true,
        useExternalServers: false,
        externalLampaURL: "",
        externalTorrServerHost: "",
        externalJackettHost: "",
        externalJackettApiKey: ""
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
