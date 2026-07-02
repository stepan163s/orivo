import SwiftUI

public struct BufferingOverlayView: View {
    let hash: String
    let fileIndex: Int
    let filename: String
    let title: String
    let onClose: () -> Void
    
    @State private var progress: Double = 0.0
    @State private var speedString: String = "0 КБ/с"
    @State private var peersCount: Int = 0
    @State private var totalPeers: Int = 0
    @State private var statusString: String = "Подключение..."
    
    @State private var statusTimer: Timer? = nil
    
    public var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Movie metadata
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(filename)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                        .frame(maxWidth: 320)
                }
                
                // Circular Progress Indicator
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 10)
                        .frame(width: 140, height: 140)
                    
                    Circle()
                        .trim(from: 0.0, to: CGFloat(progress))
                        .stroke(
                            AngularGradient(
                                colors: [.blue, .cyan, .blue],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(Angle(degrees: -90))
                        .frame(width: 140, height: 140)
                        .animation(.linear(duration: 0.5), value: progress)
                    
                    VStack(spacing: 4) {
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text(statusString)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                
                // Download Stats
                HStack(spacing: 32) {
                    VStack(alignment: .center, spacing: 4) {
                        Text("Скорость")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                        Text(speedString)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .center, spacing: 4) {
                        Text("Пиры")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                        Text("\(peersCount) / \(totalPeers)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.04))
                .cornerRadius(8)
                
                // Cancel Button
                Button(action: {
                    stopTimer()
                    onClose()
                }) {
                    Text("Отмена")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.red.opacity(0.4), lineWidth: 1)
                        )
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(32)
        }
        .frame(width: 400, height: 400)
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    private func startTimer() {
        // Query status immediately
        queryStatus()
        
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                queryStatus()
            }
        }
    }
    
    private func stopTimer() {
        statusTimer?.invalidate()
        statusTimer = nil
    }
    
    private func queryStatus() {
        Task {
            do {
                let statusResponse = try await TorrServerClient.shared.getTorrentStatus(hash: hash)
                
                // Update stats
                self.progress = statusResponse.bufferingProgress
                self.speedString = statusResponse.formattedSpeed
                self.peersCount = statusResponse.active_peers ?? 0
                self.totalPeers = statusResponse.total_peers ?? 0
                
                switch statusResponse.status {
                case 1:
                    self.statusString = "Поиск пиров..."
                case 2:
                    self.statusString = "Буферизация..."
                case 3:
                    // Preload complete! Play video!
                    self.statusString = "Готово"
                    stopTimer()
                    playVideo()
                default:
                    self.statusString = "Подключение..."
                }
                
                // Fallback: if progress hits 100%, trigger play
                if statusResponse.bufferingProgress >= 1.0 {
                    stopTimer()
                    playVideo()
                }
            } catch {
                print("TorrServer buffering status check error: \(error.localizedDescription)")
            }
        }
    }
    
    private func playVideo() {
        let playURL = TorrServerClient.shared.getPlayURL(hash: hash, fileIndex: fileIndex, filename: filename)
        
        DispatchQueue.main.async {
            // Post notification to dismiss parent sheets first so player isn't covered
            NotificationCenter.default.post(name: NSNotification.Name("CloseCatalogSheets"), object: nil)
            
            // Launch native full-screen PlayerView
            AppStateManager.shared.play(url: playURL, title: title)
            // Close buffer overlay sheet
            onClose()
        }
    }
}
