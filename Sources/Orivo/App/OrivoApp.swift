import SwiftUI
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupSignalHandlers()
        
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
    
    private func setupSignalHandlers() {
        let sigtermHandler: @convention(c) (Int32) -> Void = { sig in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
        signal(SIGTERM, sigtermHandler)
        signal(SIGINT, sigtermHandler)
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
        
        let openLib = SettingsManager.shared.settings.openLibraryOnLaunch
        let targetTitle = openLib ? "Library" : "Orivo"
        
        for window in NSApp.windows {
            if window.title == targetTitle {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
        
        // If target window not found, open it via notification triggers
        if openLib {
            NotificationCenter.default.post(name: NSNotification.Name("OpenLibraryWindow"), object: nil)
        } else {
            NotificationCenter.default.post(name: NSNotification.Name("OpenMainWindow"), object: nil)
        }
    }
    
    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window.title == "Orivo" || window.title == "Library" {
            // Check if there are any other visible main windows
            let visibleWindows = NSApp.windows.filter { $0.isVisible && ($0.title == "Orivo" || $0.title == "Library") }
            if visibleWindows.isEmpty {
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
            MainViewWrapper(
                isOnboardingCompleted: $isOnboardingCompleted,
                showSettings: $showSettings,
                activeLogServiceId: $activeLogServiceId
            )
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
                .ignoresSafeArea()
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}

struct MainViewWrapper: View {
    @Binding var isOnboardingCompleted: Bool
    @Binding var showSettings: Bool
    @Binding var activeLogServiceId: String?
    
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        mainView
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenMainWindow"))) { _ in
                openWindow(id: "MainWindow")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenLibraryWindow"))) { _ in
                openWindow(id: "LibraryWindow")
            }
            .onAppear {
                if isOnboardingCompleted && SettingsManager.shared.settings.openLibraryOnLaunch {
                    openWindow(id: "LibraryWindow")
                    dismiss()
                }
            }
            .onChange(of: isOnboardingCompleted) { completed in
                if completed && SettingsManager.shared.settings.openLibraryOnLaunch {
                    openWindow(id: "LibraryWindow")
                    dismiss()
                }
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
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        ZStack {
            MainCatalogView()
                .ignoresSafeArea()
            
            if let player = appState.activePlayer {
                PlayerView(player: player, url: appState.activePlayerURL, title: appState.activePlayerTitle, onClose: {
                    appState.closePlayer()
                })
                .transition(.opacity)
                .ignoresSafeArea()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenLibraryWindow"))) { _ in
            openWindow(id: "LibraryWindow")
        }
    }
}
