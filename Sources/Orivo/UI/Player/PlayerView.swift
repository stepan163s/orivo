import SwiftUI

public struct PlayerView: View {
    let player: MpvPlayer
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
    
    public init(player: MpvPlayer, title: String, onClose: @escaping () -> Void) {
        self.player = player
        self.title = title
        self.onClose = onClose
    }
    
    public var body: some View {
        ZStack {
            // Video view
            MpvVideoViewRepresentable(player: player)
                .ignoresSafeArea()
            
            // Hover overlay
            if isOverlayVisible {
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
                                    if audioTracks.isEmpty {
                                        Text("Нет доступных дорожек")
                                    } else {
                                        ForEach(audioTracks, id: \.self) { track in
                                            Button(action: {
                                                player.selectTrack(type: "audio", id: track.trackId)
                                                showOverlayTemporarily()
                                            }) {
                                                HStack {
                                                    if track.isSelected {
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
                                
                                // Subtitle Track Menu Picker
                                Menu {
                                    let subtitleTracks = player.getTracks(type: "sub")
                                    
                                    Button(action: {
                                        player.selectTrack(type: "sub", id: nil)
                                        showOverlayTemporarily()
                                    }) {
                                        HStack {
                                            if !subtitleTracks.contains(where: { $0.isSelected }) {
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
                                                showOverlayTemporarily()
                                            }) {
                                                HStack {
                                                    if track.isSelected {
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
        }
        .background(Color.black)
        .onContinuousHover { _ in
            showOverlayTemporarily()
        }
        .onAppear {
            setupPlayerCallbacks()
            showOverlayTemporarily()
        }
    }
    
    private func setupPlayerCallbacks() {
        player.onPlaybackProgress = { current, total in
            DispatchQueue.main.async {
                if !self.isDraggingSlider {
                    self.currentTime = current
                }
                self.duration = total
            }
        }
        
        player.onPlaybackStateChanged = { playing in
            DispatchQueue.main.async {
                self.isPlaying = playing
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
