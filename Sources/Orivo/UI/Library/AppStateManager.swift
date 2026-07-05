import SwiftUI

public struct KinoriumRatingTarget: Identifiable, Sendable {
    public var id: String { kinoriumID }
    public let kinoriumID: String
    public let title: String
}

@MainActor
public class AppStateManager: ObservableObject {
    public static let shared = AppStateManager()
    
    @Published public var activePlayer: MpvPlayer? = nil
    @Published public var activePlayerTitle: String = ""
    @Published public var activePlayerURL: String = ""
    @Published public var activePlayerMediaId: Int? = nil
    @Published public var activePlayerKinoriumID: String? = nil
    @Published public var kinoriumRatingTarget: KinoriumRatingTarget? = nil
    
    @Published public var hudMessage: String? = nil
    @Published public var hudIsSuccess: Bool = true
    
    public var onPlayerProgress: (@MainActor @Sendable (Double, Double) -> Void)? = nil
    public var onPlayerStateChanged: (@MainActor @Sendable (Bool) -> Void)? = nil
    public var onClosePlayerRequested: (@MainActor @Sendable () -> Void)? = nil
    
    private init() {}
    
    private var hasSentWatching = false
    private var lastSyncTime = Date.distantPast
    private var hudDismissTask: Task<Void, Never>? = nil
    
    public func showHUD(message: String, isSuccess: Bool) {
        hudDismissTask?.cancel()
        self.hudMessage = message
        self.hudIsSuccess = isSuccess
        
        hudDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            guard !Task.isCancelled else { return }
            self.hudMessage = nil
        }
    }
    
    public func play(url: String, title: String, mediaId: Int? = nil, kinoriumID: String? = nil) {
        LogManager.shared.log(serviceId: "system", text: "AppStateManager: play called, URL: \(url), Title: \(title), mediaId: \(mediaId ?? -1), kinoriumID: \(kinoriumID ?? "nil")")
        // Destroy the old player instance if any
        if let player = activePlayer {
            player.destroy()
        }
        
        let player = MpvPlayer()
        self.activePlayerTitle = title
        self.activePlayerURL = url
        self.activePlayerMediaId = mediaId
        self.activePlayerKinoriumID = kinoriumID
        self.activePlayer = player
        self.hasSentWatching = false
        self.lastSyncTime = Date.distantPast
        
        // Resolve Kinorium ID dynamically in the background if not provided
        if kinoriumID == nil {
            Task {
                var cleanTitle = title
                // Remove quality qualifiers like " [1080p]" or similar
                if let idx = title.range(of: " [")?.lowerBound {
                    cleanTitle = String(title[..<idx])
                }
                
                LogManager.shared.log(serviceId: "system", text: "AppStateManager: kinoriumID is nil. Attempting to resolve via search for '\(cleanTitle)'...")
                if let resolved = await KinoriumClient.shared.searchMovieID(title: cleanTitle, year: nil) {
                    LogManager.shared.log(serviceId: "system", text: "AppStateManager: Resolved kinoriumID '\(resolved)' for movie '\(cleanTitle)'")
                    await MainActor.run {
                        // Check if we are still playing this movie
                        if self.activePlayerTitle == title {
                            self.activePlayerKinoriumID = resolved
                        }
                    }
                } else {
                    LogManager.shared.log(serviceId: "system", text: "AppStateManager: Failed to resolve kinoriumID for '\(cleanTitle)'")
                }
            }
        }
        
        player.onPlaybackProgress = { [weak self] current, total in
            DispatchQueue.main.async {
                self?.updateProgress(current: current, total: total)
            }
        }
        
        player.onPlaybackStateChanged = { [weak self] playing in
            DispatchQueue.main.async {
                self?.onPlayerStateChanged?(playing)
            }
        }
        
        player.play(url: url)
    }
    
    public func updateProgress(current: Double, total: Double) {
        self.onPlayerProgress?(current, total)
        
        // Track 5 minutes (300 seconds) watch time for Kinorium "watching" status
        if let kinoriumID = self.activePlayerKinoriumID, !hasSentWatching, current >= 300.0 {
            hasSentWatching = true
            Task {
                do {
                    try await KinoriumClient.shared.setMovieStatus(movieID: kinoriumID, status: .watching)
                    LogManager.shared.log(serviceId: "system", text: "Kinorium: Successfully set status to 'watching' for movie \(kinoriumID)")
                    await MainActor.run {
                        self.showHUD(message: "Кинориум: Смотрю", isSuccess: true)
                    }
                } catch {
                    LogManager.shared.log(serviceId: "system", text: "Kinorium: Failed to set status to 'watching' for movie \(kinoriumID): \(error.localizedDescription)", isError: true)
                    await MainActor.run {
                        self.showHUD(message: "Кинориум: Ошибка статуса 'Смотрю'", isSuccess: false)
                    }
                }
            }
        }
        
        if let mediaId = self.activePlayerMediaId {
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
    
    public func closePlayer() {
        if let player = activePlayer {
            let current = player.currentTime
            let duration = player.duration
            let progressPct = duration > 0 ? (current / duration) : 0.0
            
            // If they watched 90% or more of the movie, and it is a Kinorium movie
            if let kinoriumID = activePlayerKinoriumID, progressPct >= 0.90 {
                let title = activePlayerTitle
                
                // Automatically mark as watched on Kinorium
                Task {
                    do {
                        try await KinoriumClient.shared.setMovieStatus(movieID: kinoriumID, status: .watched)
                        LogManager.shared.log(serviceId: "system", text: "Kinorium: Automatically set status to 'watched' for movie \(kinoriumID)")
                        await MainActor.run {
                            self.showHUD(message: "Кинориум: Просмотрено", isSuccess: true)
                        }
                    } catch {
                        LogManager.shared.log(serviceId: "system", text: "Kinorium: Failed to set status to 'watched' for movie \(kinoriumID): \(error.localizedDescription)", isError: true)
                        await MainActor.run {
                            self.showHUD(message: "Кинориум: Ошибка статуса 'Просмотрено'", isSuccess: false)
                        }
                    }
                }
                
                // Trigger the rating & comment dialog!
                self.kinoriumRatingTarget = KinoriumRatingTarget(kinoriumID: kinoriumID, title: title)
            }
            
            if let mediaId = activePlayerMediaId {
                Task {
                    await TraktClient.shared.scrobbleStop(mediaId: mediaId, progress: 100.0)
                }
            }
            player.destroy()
            self.activePlayer = nil
            self.activePlayerMediaId = nil
            self.activePlayerKinoriumID = nil
            self.onClosePlayerRequested?()
        }
    }
}
