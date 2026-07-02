import SwiftUI
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarController.shared.setupMenuBar()
        MenuBarController.shared.onOpenDashboard = {
            self.showMainWindow()
        }
        
        // Show window and promote to regular app (shows in Dock) on startup
        self.showMainWindow()
        
        // Listen to window close events to return Orivo to background agent mode (hides from Dock)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        
        // Start Lampa auto-configuration server and native FlareSolverr
        ConfigServer.shared.start()
        SolverServer.shared.start()
        
        let hasTorr = ServiceManager.shared.isBinaryInstalled(service: ServiceManager.shared.services[0])
        let hasJackett = ServiceManager.shared.isBinaryInstalled(service: ServiceManager.shared.services[1])
        if hasTorr && hasJackett {
            ServiceManager.shared.startAllAutoStartServices()
            Watchdog.shared.startMonitoring()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Watchdog.shared.stopMonitoring()
        ConfigServer.shared.stop()
        SolverServer.shared.stop()
        ProcessSupervisor.shared.killAllSync()
        LogManager.shared.closeAllHandles()
    }
    
    private func showMainWindow() {
        // Promote to regular application (shows in Dock)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        for window in NSApp.windows {
            if window.title == "Orivo" {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
        
        if let firstWindow = NSApp.windows.first {
            firstWindow.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window.title == "Orivo" {
            let quitOnClose = SettingsManager.shared.settings.quitOnClose
            if quitOnClose {
                NSApp.terminate(nil)
            } else {
                // Demote to background agent (hides from Dock, stays in MenuBar)
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

@main
struct OrivoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @State private var isOnboardingCompleted: Bool = {
        let serviceManager = ServiceManager.shared
        guard serviceManager.services.count >= 2 else { return false }
        let hasTorr = serviceManager.isBinaryInstalled(service: serviceManager.services[0])
        let hasJackett = serviceManager.isBinaryInstalled(service: serviceManager.services[1])
        return hasTorr && hasJackett
    }()
    
    @State private var showSettings = false
    @State private var activeLogServiceId: String? = nil
    
    var body: some Scene {
        Window("Orivo", id: "MainWindow") {
            mainView
                .preferredColorScheme(.dark)
                .frame(width: isOnboardingCompleted ? 340 : 500, height: isOnboardingCompleted ? 400 : 420)
                .background(OrivoTheme.bgWindow)
                .ignoresSafeArea()
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowResizability(.contentSize)
        
        Window("Library", id: "LibraryWindow") {
            LibraryWindowView()
                .preferredColorScheme(.dark)
                .frame(minWidth: 1024, minHeight: 700)
        }
    }
    
    @ViewBuilder
    private var mainView: some View {
        if !isOnboardingCompleted {
            OnboardingView(onboardingCompleted: $isOnboardingCompleted)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
        } else {
            ZStack {
                if showSettings {
                    SettingsView(showSettings: $showSettings)
                        .transition(.move(edge: .trailing))
                } else {
                    DashboardView(showSettings: $showSettings, activeLogServiceId: $activeLogServiceId)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: showSettings)
        }
    }
}

struct LibraryWindowView: View {
    @StateObject private var appState = AppStateManager.shared
    
    var body: some View {
        ZStack {
            if let player = appState.activePlayer {
                MpvVideoViewRepresentable(player: player)
                    .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
            }
            
            LibraryWebView()
                .ignoresSafeArea()
        }
    }
}
