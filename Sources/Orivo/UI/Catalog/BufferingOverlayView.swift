import SwiftUI

public struct BufferingOverlayView: View {
    let hash: String
    let fileIndex: Int
    let filename: String
    let title: String
    let mediaId: Int?
    let kinoriumId: String?
    let onClose: () -> Void
    
    public init(hash: String, fileIndex: Int, filename: String, title: String, mediaId: Int? = nil, kinoriumId: String? = nil, onClose: @escaping () -> Void) {
        self.hash = hash
        self.fileIndex = fileIndex
        self.filename = filename
        self.title = title
        self.mediaId = mediaId
        self.kinoriumId = kinoriumId
        self.onClose = onClose
    }
    
    @State private var progress: Double = 0.0
    @State private var speedString: String = "0 КБ/с"
    @State private var peersCount: Int = 0
    @State private var totalPeers: Int = 0
    @State private var statusString: String = "Подключение..."
    
    @State private var statusTimer: Timer? = nil
    
    public var body: some View {
        ZStack {
            // Dark glassmorphic background
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .overlay(Color.black.opacity(0.4))
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header / Movie Title
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(filename)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                        .frame(maxWidth: 320)
                }
                
                // Ring with glowing progress indicator
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 8)
                        .frame(width: 140, height: 140)
                    
                    Circle()
                        .trim(from: 0.0, to: CGFloat(progress))
                        .stroke(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(Angle(degrees: -90))
                        .frame(width: 140, height: 140)
                        .shadow(color: Color.blue.opacity(0.35), radius: 6)
                        .animation(.linear(duration: 0.4), value: progress)
                    
                    VStack(spacing: 6) {
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text(statusString)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .textCase(.uppercase)
                            .tracking(1.0)
                    }
                }
                .padding(.vertical, 8)
                
                // Stats HUD bar
                HStack(spacing: 0) {
                    // Speed
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.blue)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("СКОРОСТЬ")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                            Text(speedString)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    
                    Spacer()
                    
                    Divider()
                        .frame(height: 24)
                        .background(Color.white.opacity(0.1))
                    
                    Spacer()
                    
                    // Peers
                    HStack(spacing: 8) {
                        Image(systemName: "person.2")
                            .foregroundColor(.purple)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("ПИРЫ")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                            Text("\(peersCount) / \(totalPeers)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
                .frame(width: 320)
                
                // Frosted Cancel Button
                Button(action: {
                    stopTimer()
                    onClose()
                }) {
                    Text("Отмена")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 32)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(24)
        }
        .frame(width: 380, height: 410)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    private func startTimer() {
        LogManager.shared.log(serviceId: "system", text: "BufferingOverlayView: startTimer called for hash \(hash), fileIndex \(fileIndex)")
        // Query status immediately
        queryStatus()
        
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                queryStatus()
            }
        }
    }
    
    private func stopTimer() {
        LogManager.shared.log(serviceId: "system", text: "BufferingOverlayView: stopTimer called")
        statusTimer?.invalidate()
        statusTimer = nil
    }
    
    @MainActor
    private func queryStatus() {
        Task {
            do {
                let statusResponse = try await TorrServerClient.shared.getTorrentStatus(hash: hash)
                LogManager.shared.log(serviceId: "system", text: "BufferingOverlayView: queryStatus - status: \(statusResponse.status ?? -1), progress: \(statusResponse.bufferingProgress), peers: \(statusResponse.active_peers ?? 0)/\(statusResponse.total_peers ?? 0)")
                
                // Update stats
                self.progress = statusResponse.bufferingProgress
                self.speedString = statusResponse.formattedSpeed
                self.peersCount = statusResponse.active_peers ?? 0
                self.totalPeers = statusResponse.total_peers ?? 0
                
                if statusResponse.status == 3 || statusResponse.bufferingProgress >= 1.0 {
                    self.statusString = "Готово"
                    stopTimer()
                    playVideo()
                } else {
                    switch statusResponse.status {
                    case 1:
                        self.statusString = "Поиск пиров..."
                    case 2:
                        self.statusString = "Буферизация..."
                    default:
                        self.statusString = "Подключение..."
                    }
                }
            } catch {
                LogManager.shared.log(serviceId: "system", text: "BufferingOverlayView: TorrServer buffering status check error: \(error.localizedDescription)", isError: true)
            }
        }
    }
    
    private func playVideo() {
        let playURL = TorrServerClient.shared.getPlayURL(hash: hash, fileIndex: fileIndex, filename: filename)
        LogManager.shared.log(serviceId: "system", text: "BufferingOverlayView: playVideo called. URL: \(playURL)")
        
        DispatchQueue.main.async {
            // Post notification to dismiss parent sheets first so player isn't covered
            NotificationCenter.default.post(name: NSNotification.Name("CloseCatalogSheets"), object: nil)
            
            // Launch native full-screen PlayerView
            AppStateManager.shared.play(url: playURL, title: title, mediaId: mediaId, kinoriumID: kinoriumId)
            // Close buffer overlay sheet
            onClose()
        }
    }
}
