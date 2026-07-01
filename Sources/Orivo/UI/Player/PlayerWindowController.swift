import AppKit
import SwiftUI

@MainActor
public class PlayerWindowController: NSObject, NSWindowDelegate {
    public static let shared = PlayerWindowController()
    
    private var window: NSWindow?
    private var player: MpvPlayer?
    
    private override init() {
        super.init()
    }
    
    public func play(url: String, title: String) {
        close()
        
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
        newWindow.backgroundColor = .black
        newWindow.collectionBehavior = [.fullScreenPrimary, .managed]
        
        let playerView = PlayerView(player: player, title: title) { [weak self] in
            self?.close()
        }
        let hostingView = NSHostingView(rootView: playerView)
        newWindow.contentView = hostingView
        
        self.window = newWindow
        
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        player.play(url: url)
    }
    
    public func close() {
        if let window = window {
            window.close()
            self.window = nil
        }
        if let player = player {
            player.destroy()
            self.player = nil
        }
    }
    
    // MARK: - NSWindowDelegate
    public func windowWillClose(_ notification: Notification) {
        if let player = player {
            player.destroy()
            self.player = nil
        }
        self.window = nil
        LogManager.shared.log(serviceId: "system", text: "PlayerWindowController window closed, player destroyed")
    }
}
