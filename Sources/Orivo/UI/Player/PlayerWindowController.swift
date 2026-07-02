import AppKit
import SwiftUI

@MainActor
public class PlayerWindowController: NSObject, NSWindowDelegate {
    public static let shared = PlayerWindowController()
    
    private var window: NSWindow?
    private var player: MpvPlayer?
    
    private var windowCheckTimer: Timer?
    private var hijackedMpvWindow: NSWindow?
    private var isClosing = false
    
    private override init() {
        super.init()
    }
    
    public func play(url: String, title: String) {
        close()
        isClosing = false
        
        let player = MpvPlayer()
        self.player = player
        
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let windowWidth: CGFloat = 1280
        let windowHeight: CGFloat = 720
        let windowRect = NSRect(
            x: screenRect.origin.x + (screenRect.width - windowWidth) / 2,
            y: screenRect.origin.y + (screenRect.height - windowHeight) / 2,
            width: windowWidth,
            height: windowHeight
        )
        
        let newWindow = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = title
        newWindow.minSize = NSSize(width: 640, height: 360)
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.backgroundColor = .clear // Transparent to let video show from below
        newWindow.isOpaque = false
        newWindow.collectionBehavior = [.fullScreenPrimary, .managed]
        
        let playerView = PlayerView(player: player, title: title) { [weak self] in
            self?.close()
        }
        let hostingView = NSHostingView(rootView: playerView)
        newWindow.contentView = hostingView
        
        self.window = newWindow
        
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Start monitoring for libmpv window creation
        startMpvWindowTracking(parentWindow: newWindow)
        
        player.play(url: url)
    }
    
    public func close() {
        guard !isClosing else { return }
        isClosing = true
        
        windowCheckTimer?.invalidate()
        windowCheckTimer = nil
        
        NotificationCenter.default.removeObserver(self)
        
        if let mpv = hijackedMpvWindow {
            mpv.close()
            self.hijackedMpvWindow = nil
        }
        if let window = window {
            window.close()
            self.window = nil
        }
        if let player = player {
            player.destroy()
            self.player = nil
        }
    }
    
    // MARK: - Window Hijacking Mechanism
    private func startMpvWindowTracking(parentWindow: NSWindow) {
        windowCheckTimer?.invalidate()
        windowCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self, weak parentWindow] _ in
            Task { @MainActor in
                guard let self = self, let parent = parentWindow else { return }
                
                for win in NSApp.windows {
                    // Find any other visible window in our process that is not the parent and not the main dashboard window
                    if win !== parent && win.isVisible && win.parent == nil && win.className.contains("Window") {
                        self.hijackMpvWindow(win, parentWindow: parent)
                        self.windowCheckTimer?.invalidate()
                        self.windowCheckTimer = nil
                        break
                    }
                }
            }
        }
    }
    
    private func hijackMpvWindow(_ mpvWindow: NSWindow, parentWindow: NSWindow) {
        LogManager.shared.log(serviceId: "system", text: "PlayerWindowController: Hijacking mpv window \(mpvWindow.title)")
        self.hijackedMpvWindow = mpvWindow
        
        // Make the mpv window borderless
        mpvWindow.styleMask = [.borderless]
        mpvWindow.backgroundColor = .black
        mpvWindow.isOpaque = true
        mpvWindow.hasShadow = false
        
        // Place it directly BELOW our parent window, so our SwiftUI view draws on top!
        parentWindow.addChildWindow(mpvWindow, ordered: .below)
        
        // Sync frame size immediately
        mpvWindow.setFrame(parentWindow.frame, display: true)
        
        // Observe movement and resize notifications to keep frames in sync
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(syncMpvWindowFrame),
            name: NSWindow.didResizeNotification,
            object: parentWindow
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(syncMpvWindowFrame),
            name: NSWindow.didMoveNotification,
            object: parentWindow
        )
    }
    
    @objc private func syncMpvWindowFrame(notification: Notification) {
        guard let parent = notification.object as? NSWindow,
              let mpv = hijackedMpvWindow else { return }
        mpv.setFrame(parent.frame, display: true)
    }
    
    // MARK: - NSWindowDelegate
    public func windowWillClose(_ notification: Notification) {
        close()
        LogManager.shared.log(serviceId: "system", text: "PlayerWindowController window closed, player destroyed")
    }
}
