import SwiftUI

@MainActor
public class AppStateManager: ObservableObject {
    public static let shared = AppStateManager()
    
    @Published public var activePlayer: MpvPlayer? = nil
    @Published public var activePlayerTitle: String = ""
    @Published public var activePlayerURL: String = ""
    @Published public var activePlayerMediaId: Int? = nil
    
    public var onPlayerProgress: (@MainActor @Sendable (Double, Double) -> Void)? = nil
    public var onPlayerStateChanged: (@MainActor @Sendable (Bool) -> Void)? = nil
    public var onClosePlayerRequested: (@MainActor @Sendable () -> Void)? = nil
    
    private init() {}
    
    public func play(url: String, title: String, mediaId: Int? = nil) {
        LogManager.shared.log(serviceId: "system", text: "AppStateManager: play called, URL: \(url), Title: \(title), mediaId: \(mediaId ?? -1)")
        // Destroy the old player instance if any
        if let player = activePlayer {
            player.destroy()
        }
        
        let player = MpvPlayer()
        self.activePlayerTitle = title
        self.activePlayerURL = url
        self.activePlayerMediaId = mediaId
        self.activePlayer = player
        
        var lastSyncTime = Date.distantPast
        player.onPlaybackProgress = { [weak self] current, total in
            DispatchQueue.main.async {
                self?.onPlayerProgress?(current, total)
                
                if let mediaId = self?.activePlayerMediaId {
                    let now = Date()
                    if now.timeIntervalSince(lastSyncTime) >= 10.0 {
                        lastSyncTime = now
                        
                        Task {
                            await CUBClient.shared.updateTimeline(mediaId: mediaId, time: current, duration: total)
                        }
                        
                        let progressPct = total > 0 ? (current / total) * 100 : 0
                        Task {
                            await TraktClient.shared.scrobbleProgress(mediaId: mediaId, progress: progressPct)
                        }
                    }
                }
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
            if let mediaId = activePlayerMediaId {
                Task {
                    await TraktClient.shared.scrobbleStop(mediaId: mediaId, progress: 100.0)
                }
            }
            player.destroy()
            self.activePlayer = nil
            self.activePlayerMediaId = nil
            self.onClosePlayerRequested?()
        }
    }
}
