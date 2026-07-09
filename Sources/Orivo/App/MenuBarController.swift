import AppKit
import SwiftUI
import Combine

@MainActor
public final class MenuBarController: NSObject {
    public static let shared = MenuBarController()
    
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var cancellables = Set<AnyCancellable>()
    
    public var onOpenDashboard: (() -> Void)?
    
    private override init() {
        super.init()
    }
    
    public func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Orivo")
            button.imagePosition = .imageLeft
        }
        
        menu = NSMenu()
        menu?.delegate = self
        statusItem?.menu = menu
        
        updateMenu()
        
        // Observe EventBus to update menu on status changes
        EventBus.shared.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateMenu()
            }
            .store(in: &cancellables)
    }
    
    public func updateMenu() {
        guard let menu = menu, let button = statusItem?.button else { return }
        menu.removeAllItems()
        
        let allHealthy = ServiceManager.shared.services.allSatisfy {
            ServiceManager.shared.statuses[$0.id] == .healthy
        }
        
        if allHealthy {
            button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Orivo")
            button.contentTintColor = nil
            
            let statusItem = NSMenuItem(title: "Everything is ready", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
        } else {
            button.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Orivo")
            button.contentTintColor = .systemRed
            
            let statusItem = NSMenuItem(title: "Needs attention", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let openLibItem = NSMenuItem(title: "Open Library", action: #selector(openLibraryClicked), keyEquivalent: "l")
        openLibItem.target = self
        menu.addItem(openLibItem)
        
        let restartItem = NSMenuItem(title: "Restart Services", action: #selector(restartClicked), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)
        
        let checkUpdatesItem = NSMenuItem(title: "Check Updates", action: #selector(checkUpdatesClicked), keyEquivalent: "u")
        checkUpdatesItem.target = self
        menu.addItem(checkUpdatesItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit Orivo", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc private func openLibraryClicked() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        for window in NSApp.windows {
            if window.title == "Library" {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
        NotificationCenter.default.post(name: NSNotification.Name("OpenLibraryWindow"), object: nil)
    }
    
    @objc private func restartClicked() {
        ServiceManager.shared.stopAllServices()
        // Wait and start
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            ServiceManager.shared.startAllAutoStartServices()
        }
    }
    
    @objc private func checkUpdatesClicked() {
        LogManager.shared.log(serviceId: "system", text: "Checking for Orivo system service updates...")
        OrivoUpdater.shared.checkForUpdates()
    }
    
    @objc private func quitClicked() {
        LogManager.shared.log(serviceId: "system", text: "Shutting down Orivo services for quit.")
        Watchdog.shared.stopMonitoring()
        ConfigServer.shared.stop()
        SolverServer.shared.stop()
        ProcessSupervisor.shared.killAllSync()
        LogManager.shared.closeAllHandles()
        NSApp.terminate(nil)
    }
}

extension MenuBarController: NSMenuDelegate {
    public func menuWillOpen(_ menu: NSMenu) {
        updateMenu()
    }
}
