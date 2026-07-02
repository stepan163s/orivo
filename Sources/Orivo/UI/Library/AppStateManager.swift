import SwiftUI

@MainActor
public class AppStateManager: ObservableObject {
    public static let shared = AppStateManager()
    
    @Published public var activePlayer: MpvPlayer? = nil
    @Published public var activePlayerTitle: String = ""
    
    public var onPlayerProgress: (@MainActor @Sendable (Double, Double) -> Void)? = nil
    public var onPlayerStateChanged: (@MainActor @Sendable (Bool) -> Void)? = nil
    public var onClosePlayerRequested: (@MainActor @Sendable () -> Void)? = nil
    
    private init() {}
    
    public func play(url: String, title: String) {
        LogManager.shared.log(serviceId: "system", text: "AppStateManager: play called, URL: \(url), Title: \(title)")
        // Destroy the old player instance if any
        if let player = activePlayer {
            player.destroy()
        }
        
        let player = MpvPlayer()
        self.activePlayerTitle = title
        self.activePlayer = player
        
        player.onPlaybackProgress = { [weak self] current, total in
            DispatchQueue.main.async {
                self?.onPlayerProgress?(current, total)
            }
        }
        
        player.onPlaybackStateChanged = { [weak self] playing in
            DispatchQueue.main.async {
                self?.onPlayerStateChanged?(playing)
            }
        }
        
        player.play(url: url)
    }
    
    public func closePlayer() {
        if let player = activePlayer {
            player.destroy()
            self.activePlayer = nil
            self.onClosePlayerRequested?()
        }
    }
}
