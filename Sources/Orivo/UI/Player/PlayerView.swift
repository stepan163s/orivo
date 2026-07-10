import SwiftUI

public struct PlayerView: View {
    let player: MpvPlayer
    let url: String
    let title: String
    let onClose: () -> Void
    
    @State private var currentTime: Double = 0.0
    @State private var duration: Double = 0.0
    @State private var isPlaying: Bool = true
    @State private var volume: Double = 100.0
    @State private var isOverlayVisible: Bool = true
    @State private var hideTimer: Timer?
    @State private var isDraggingSlider: Bool = false
    @State private var dragTime: Double = 0.0
    @State private var trackSelectionVersion: Int = 0
    
    // TorrServer buffering properties
    @State private var bufferingProgress: Double = 0.0
    @State private var bufferingSpeed: String = ""
    @State private var bufferingPeers: String = ""
    @State private var isTorrServerBuffering: Bool = false
    @State private var bufferTimer: Timer? = nil
    
    public init(player: MpvPlayer, url: String, title: String, onClose: @escaping () -> Void) {
        self.player = player
        self.url = url
        self.title = title
        self.onClose = onClose
    }
    
    public var body: some View {
        ZStack {
            // Video view
            MpvVideoViewRepresentable(player: player)
                .ignoresSafeArea()
            
            // Hover overlay (Controls)
            if isOverlayVisible && !isTorrServerBuffering {
                ZStack {
                    // Top Bar
                    VStack {
                        HStack {
                            Text(title)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.4).cornerRadius(8))
                            
                            Spacer()
                            
                            Button(action: {
                                bufferTimer?.invalidate()
                                bufferTimer = nil
                                onClose()
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.black.opacity(0.4))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.top, 24)
                        .padding(.horizontal, 24)
                        
                        Spacer()
                    }
                    
                    // Center Controls
                    Button(action: {
                        player.togglePause()
                    }) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.white)
                            .frame(width: 80, height: 80)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                            .shadow(radius: 10)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Bottom Controls Bar
                    VStack {
                        Spacer()
                        
                        VStack(spacing: 8) {
                            // Timeline slider
                            HStack(spacing: 12) {
                                Text(formatTime(isDraggingSlider ? dragTime : currentTime))
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white)
                                
                                Slider(value: Binding(
                                    get: { isDraggingSlider ? dragTime : currentTime },
                                    set: { newValue in
                                        isDraggingSlider = true
                                        dragTime = newValue
                                    }
                                ), in: 0...max(duration, 1), onEditingChanged: { editing in
                                    if !editing {
                                        player.seek(to: dragTime)
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            isDraggingSlider = false
                                        }
                                    }
                                })
                                .accentColor(.blue)
                                
                                Text(formatTime(duration))
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            
                            // Bottom row
                            HStack {
                                Button(action: {
                                    if volume > 0 {
                                        volume = 0
                                        player.setVolume(0)
                                    } else {
                                        volume = 100
                                        player.setVolume(100)
                                    }
                                }) {
                                    Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Slider(value: $volume, in: 0...100, onEditingChanged: { _ in
                                    player.setVolume(Int(volume))
                                })
                                .frame(width: 100)
                                .accentColor(.blue)
                                
                                Spacer()
                                
                                // Audio Track Menu Picker
                                Menu {
                                    let audioTracks = player.getTracks(type: "audio")
                                    let currentAudioId = player.getCurrentTrackId(type: "audio")
                                    if audioTracks.isEmpty {
                                        Text("Нет доступных дорожек")
                                    } else {
                                        ForEach(audioTracks, id: \.self) { track in
                                            Button(action: {
                                                player.selectTrack(type: "audio", id: track.trackId)
                                                trackSelectionVersion += 1
                                                showOverlayTemporarily()
                                            }) {
                                                HStack {
                                                    if currentAudioId == track.trackId {
                                                        Text("✓  \(track.displayName)")
                                                    } else {
                                                        Text("      \(track.displayName)")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "waveform")
                                            .font(.system(size: 14))
                                        Text("Аудио")
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.15))
                                    .cornerRadius(6)
                                    .foregroundColor(.white)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .id("audio-\(trackSelectionVersion)")
                                
                                // Subtitle Track Menu Picker
                                Menu {
                                    let subtitleTracks = player.getTracks(type: "sub")
                                    let currentSubId = player.getCurrentTrackId(type: "sub")
                                    
                                    Button(action: {
                                        player.selectTrack(type: "sub", id: nil)
                                        trackSelectionVersion += 1
                                        showOverlayTemporarily()
                                    }) {
                                        HStack {
                                            if currentSubId == nil {
                                                Text("✓  Выключить")
                                            } else {
                                                Text("      Выключить")
                                            }
                                        }
                                    }
                                    
                                    if !subtitleTracks.isEmpty {
                                        Divider()
                                        
                                        ForEach(subtitleTracks, id: \.self) { track in
                                            Button(action: {
                                                player.selectTrack(type: "sub", id: track.trackId)
                                                trackSelectionVersion += 1
                                                showOverlayTemporarily()
                                            }) {
                                                HStack {
                                                    if currentSubId == track.trackId {
                                                        Text("✓  \(track.displayName)")
                                                    } else {
                                                        Text("      \(track.displayName)")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "captions.bubble.fill")
                                            .font(.system(size: 14))
                                        Text("Субтитры")
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.15))
                                    .cornerRadius(6)
                                    .foregroundColor(.white)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .id("sub-\(trackSelectionVersion)")
                            }
                        }
                        .padding(.all, 16)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                }
                .transition(.opacity)
            }
            
            // Translucent Buffering Overlay
            if isTorrServerBuffering {
                ZStack {
                    Color.black.opacity(0.8)
                        .ignoresSafeArea()
                    
                    // Sleek Glassmorphic Buffer Card
                    ZStack {
                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                            .overlay(Color.black.opacity(0.4))
                        
                        VStack(spacing: 14) {
                            // Header
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text("Загрузка и буферизация торрента...")
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                Spacer()
                                
                                Button(action: {
                                    bufferTimer?.invalidate()
                                    bufferTimer = nil
                                    onClose()
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white.opacity(0.6))
                                        .frame(width: 20, height: 20)
                                        .background(Color.white.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            // Horizontal Progress Bar
                            VStack(spacing: 4) {
                                ProgressView(value: bufferingProgress)
                                    .tint(
                                        LinearGradient(
                                            colors: [Color.blue, Color.purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .scaleEffect(x: 1, y: 1.5, anchor: .center)
                                
                                HStack {
                                    Text(bufferingProgress >= 0.01 ? "Заполнение буфера..." : "Подключение к пирам...")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white.opacity(0.5))
                                    Spacer()
                                    Text(String(format: "%.0f%%", bufferingProgress * 100))
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }
                            }
                            
                            // Speed & Peers stats row
                            HStack {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 11))
                                    Text(bufferingSpeed.isEmpty ? "0 КБ/с" : bufferingSpeed)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "person.2")
                                        .foregroundColor(.purple)
                                        .font(.system(size: 11))
                                    Text(bufferingPeers.isEmpty ? "0 / 0" : bufferingPeers)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(6)
                        }
                        .padding(16)
                    }
                    .frame(width: 340, height: 130)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.12),
                                        Color.white.opacity(0.03)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 8)
                }
                .transition(.opacity)
                .zIndex(10)
            }
            
            // Translucent spinner fallback while waiting for player metadata to load
            if duration == 0.0 && !isTorrServerBuffering {
                ZStack {
                    Color.black.opacity(0.85)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Подготовка видеопотока...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .transition(.opacity)
                .zIndex(9)
            }
        }
        .background(Color.black)
        .onContinuousHover { _ in
            showOverlayTemporarily()
        }
        .onAppear {
            setupPlayerCallbacks()
            showOverlayTemporarily()
            checkForTorrServerBuffering()
        }
        .onDisappear {
            bufferTimer?.invalidate()
            bufferTimer = nil
        }
    }
    
    private func setupPlayerCallbacks() {
        player.onPlaybackProgress = { current, total in
            DispatchQueue.main.async {
                if !self.isDraggingSlider {
                    self.currentTime = current
                }
                self.duration = total
                
                // Forward progress to AppStateManager for scrobbling and Kinorium status sync
                AppStateManager.shared.updateProgress(current: current, total: total)
            }
        }
        
        player.onPlaybackStateChanged = { playing in
            DispatchQueue.main.async {
                self.isPlaying = playing
                AppStateManager.shared.onPlayerStateChanged?(playing)
            }
        }
    }
    
    private func showOverlayTemporarily() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isOverlayVisible = true
        }
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.35)) {
                    self.isOverlayVisible = false
                }
            }
        }
    }
    
    private func checkForTorrServerBuffering() {
        guard let torrentHash = extractTorrentHash(from: url) else {
            return
        }
        
        // Pause playback temporarily during initial buffering phase
        player.pause()
        isTorrServerBuffering = true
        
        bufferTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                do {
                    let status = try await TorrServerClient.shared.getTorrentStatus(hash: torrentHash)
                    self.bufferingProgress = status.bufferingProgress
                    self.bufferingSpeed = status.formattedSpeed
                    self.bufferingPeers = "\(status.active_peers ?? 0) / \(status.total_peers ?? 0)"
                    
                    let isReady = status.status == 3 || status.bufferingProgress >= 1.0
                    
                    if isReady {
                        // Buffer is complete. Tell mpv to start loading stream & reading headers
                        self.player.play()
                        
                        // Wait until mpv actually reads stream headers and gets a valid duration
                        if self.duration > 0 {
                            self.isTorrServerBuffering = false
                            self.bufferTimer?.invalidate()
                            self.bufferTimer = nil
                        }
                    }
                } catch {
                    print("Buffering check query error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func extractTorrentHash(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }
        return queryItems.first(where: { $0.name == "link" })?.value
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && seconds.isFinite else { return "00:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}
