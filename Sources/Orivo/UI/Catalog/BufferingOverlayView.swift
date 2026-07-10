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
                .overlay(Color.black.opacity(0.3))
                .ignoresSafeArea()
            
            VStack(spacing: 14) {
                // Header (Title & Filename)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(filename)
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                    Spacer()
                    
                    Button(action: {
                        stopTimer()
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
                    ProgressView(value: progress)
                        .tint(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .scaleEffect(x: 1, y: 1.5, anchor: .center)
                    
                    HStack {
                        Text(statusString)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text(String(format: "%.0f%%", progress * 100))
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
                        Text(speedString)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .foregroundColor(.purple)
                            .font(.system(size: 11))
                        Text("\(peersCount) / \(totalPeers)")
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
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("CloseCatalogSheets"), object: nil)
            AppStateManager.shared.play(url: playURL, title: title, mediaId: mediaId, kinoriumID: kinoriumId)
            onClose()
        }
    }
}
