import Foundation
import ServiceManagement
import Combine

@MainActor
public final class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()
    
    @Published public var settings: AppSettings = .defaultSettings
    
    private let configURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.configURL = appSupport.appendingPathComponent("Orivo/config/settings.json")
        loadSettings()
    }
    
    public func loadSettings() {
        AppPerfTracker.shared.start("Load Settings")
        defer { AppPerfTracker.shared.stop("Load Settings") }
        
        let directory = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        if FileManager.default.fileExists(atPath: configURL.path) {
            do {
                let data = try Data(contentsOf: configURL)
                let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
                self.settings = decoded
                
                // Migrate credentials from settings.json if present
                var needsSave = false
                if let rawJSON = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    let sensitiveKeys = [
                        "externalJackettApiKey",
                        "cubToken",
                        "tmdbApiKey",
                        "traktToken",
                        "traktClientSecret",
                        "kinoriumToken"
                    ]
                    
                    for key in sensitiveKeys {
                        if let plaintextVal = rawJSON[key] as? String, !plaintextVal.isEmpty {
                            if KeychainHelper.shared.load(key: key) == nil {
                                KeychainHelper.shared.save(key: key, value: plaintextVal)
                            }
                            needsSave = true
                        }
                    }
                }
                
                // Load credentials from Keychain
                self.settings.externalJackettApiKey = KeychainHelper.shared.load(key: "externalJackettApiKey") ?? ""
                self.settings.cubToken = KeychainHelper.shared.load(key: "cubToken") ?? ""
                self.settings.tmdbApiKey = KeychainHelper.shared.load(key: "tmdbApiKey") ?? ""
                self.settings.traktToken = KeychainHelper.shared.load(key: "traktToken") ?? ""
                self.settings.traktClientSecret = KeychainHelper.shared.load(key: "traktClientSecret") ?? ""
                self.settings.kinoriumToken = KeychainHelper.shared.load(key: "kinoriumToken") ?? ""
                
                if needsSave {
                    saveSettings() // This will rewrite settings.json without plaintext secrets
                }
            } catch {
                LogManager.shared.log(serviceId: "system", text: "Failed to load settings: \(error.localizedDescription)", isError: true)
                self.settings = .defaultSettings
            }
        } else {
            self.settings = .defaultSettings
            saveSettings()
        }
    }
    
    public func saveSettings() {
        let set = settings
        let url = configURL
        
        // Save sensitive keys to Keychain
        KeychainHelper.shared.save(key: "externalJackettApiKey", value: set.externalJackettApiKey)
        KeychainHelper.shared.save(key: "cubToken", value: set.cubToken)
        KeychainHelper.shared.save(key: "tmdbApiKey", value: set.tmdbApiKey)
        KeychainHelper.shared.save(key: "traktToken", value: set.traktToken)
        KeychainHelper.shared.save(key: "traktClientSecret", value: set.traktClientSecret)
        KeychainHelper.shared.save(key: "kinoriumToken", value: set.kinoriumToken)
        
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(set) {
                try? data.write(to: url, options: .atomic)
            }
        }
        updateLaunchAtLogin()
    }
    
    public func updateSetting<T>(_ keyPath: WritableKeyPath<AppSettings, T>, value: T) {
        self.settings[keyPath: keyPath] = value
        saveSettings()
    }
    
    private func updateLaunchAtLogin() {
        let enabled = settings.launchAtLogin
        let appService = SMAppService.mainApp
        
        do {
            if enabled {
                switch appService.status {
                case .enabled:
                    break
                default:
                    try appService.register()
                    LogManager.shared.log(serviceId: "system", text: "Successfully registered Orivo for Launch at Login.")
                }
            } else {
                switch appService.status {
                case .notRegistered:
                    break
                default:
                    try appService.unregister()
                    LogManager.shared.log(serviceId: "system", text: "Successfully unregistered Orivo for Launch at Login.")
                }
            }
        } catch {
            LogManager.shared.log(serviceId: "system", text: "SMAppService registration warning: \(error.localizedDescription). This is expected if the binary is run standalone rather than inside an installed Orivo.app package.", isError: false)
        }
    }
}
