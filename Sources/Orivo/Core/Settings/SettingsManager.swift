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
        let directory = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        if FileManager.default.fileExists(atPath: configURL.path) {
            do {
                let data = try Data(contentsOf: configURL)
                let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
                self.settings = decoded
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
