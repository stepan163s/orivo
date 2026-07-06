import Foundation
import Sparkle
import Combine

@MainActor
public final class OrivoUpdater: ObservableObject {
    public static let shared = OrivoUpdater()
    
    private let updaterController: SPUStandardUpdaterController
    
    @Published public var automaticallyChecksForUpdates: Bool = true
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Initialize SPUStandardUpdaterController. Sparkle will automatically check for updates on launch.
        self.updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        
        // Load initial state
        self.automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
        
        // Sync setting changes back to Sparkle's updater
        $automaticallyChecksForUpdates
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if self.updaterController.updater.automaticallyChecksForUpdates != enabled {
                    self.updaterController.updater.automaticallyChecksForUpdates = enabled
                }
            }
            .store(in: &cancellables)
    }
    
    public func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
