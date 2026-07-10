import SwiftUI

public struct BufferHash: Identifiable {
    public let id = UUID()
    public let hash: String
    
    public init(hash: String) {
        self.hash = hash
    }
}

public struct TorrentSelectorView: View {
    let query: String
    let title: String
    let mediaId: Int?
    let kinoriumId: String?
    let onClose: () -> Void
    
    public init(query: String, title: String, mediaId: Int? = nil, kinoriumId: String? = nil, onClose: @escaping () -> Void) {
        self.query = query
        self.title = title
        self.mediaId = mediaId
        self.kinoriumId = kinoriumId
        self.onClose = onClose
    }
    
    @State private var torrents: [JackettResult] = []
    @State private var isLoading: Bool = true
    @State private var showSpinner: Bool = false
    @State private var errorMessage: String? = nil
    @State private var sortBySeeders: Bool = true
    @State private var selectedCategory: String = "Все"
    
    // File list selection states
    @State private var resolvedFiles: [TorrServerFile] = []
    @State private var resolvedHash: String? = nil
    @State private var isLoadingFiles: Bool = false
    @State private var loadingFilesText: String = "Загрузка метаданных торрента..."
    @State private var showFilePicker: Bool = false
    
    // Active Buffering states
    @State private var activeBufferHash: BufferHash? = nil
    @State private var activeBufferFileIndex: Int = 0
    @State private var activeBufferFilename: String = ""
    
    public var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header Panel
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Раздачи для")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                        Text(title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Sort options toggle
                    Picker("Сортировка", selection: $sortBySeeders) {
                        Text("По сидам").tag(true)
                        Text("По размеру").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .onChange(of: sortBySeeders) { _ in
                        sortTorrents()
                    }
                    .padding(.trailing, 12)
                    
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(20)
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Category Pills
                HStack(spacing: 8) {
                    ForEach(["Все", "4K", "1080p", "720p", "HDR"], id: \.self) { category in
                        Button(action: {
                            selectedCategory = category
                        }) {
                            Text(category)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(selectedCategory == category ? .white : .white.opacity(0.6))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedCategory == category ? Color.blue : Color.white.opacity(0.08))
                                .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 10)
                
                if isLoading {
                    Spacer()
                    if showSpinner {
                        ProgressView()
                            .transition(.opacity)
                    }
                    Spacer()
                } else if let err = errorMessage {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundColor(.red)
                        Text(err)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        Button("Повторить") {
                            Task {
                                await performSearch()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                } else if torrents.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.3))
                        Text("Ничего не найдено")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                } else {
                    // Torrents Grid list
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredTorrents) { tor in
                                Button(action: {
                                    selectTorrent(tor)
                                }) {
                                    HStack(spacing: 16) {
                                        // Resolution label or tag indicator
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(tor.computedTitle)
                                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            
                                            HStack(spacing: 12) {
                                                Text(tor.tracker ?? "Неизвестный")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(.blue.opacity(0.9))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.blue.opacity(0.15))
                                                    .cornerRadius(4)
                                                
                                                let parsed = parseTorrentTitle(tor.computedTitle)
                                                if let q = parsed.quality {
                                                    Text(q)
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(.white)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.purple.opacity(0.7))
                                                        .cornerRadius(4)
                                                }
                                                if parsed.isHDR {
                                                    Text("HDR")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(.white)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.orange.opacity(0.8))
                                                        .cornerRadius(4)
                                                }
                                                if let t = parsed.translation {
                                                    Text(t)
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(.white)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.green.opacity(0.7))
                                                        .cornerRadius(4)
                                                }
                                                
                                                Text(tor.formattedSize)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundColor(.white.opacity(0.6))
                                                
                                                if tor.magnetUri != nil {
                                                    HStack(spacing: 3) {
                                                        Image(systemName: "magnet")
                                                            .font(.system(size: 9))
                                                        Text("Magnet")
                                                            .font(.system(size: 9, weight: .bold))
                                                    }
                                                    .foregroundColor(.pink)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.pink.opacity(0.15))
                                                    .cornerRadius(4)
                                                }
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        // Peers count details
                                        HStack(spacing: 12) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.up.circle.fill")
                                                    .foregroundColor(.green)
                                                Text("\(tor.seedersCount)")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(.green)
                                            }
                                            
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.down.circle.fill")
                                                    .foregroundColor(.orange)
                                                Text("\(tor.peersCount)")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(.orange)
                                            }
                                        }
                                        .frame(width: 100)
                                    }
                                    .padding(12)
                                    .background(Color.white.opacity(0.04))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(20)
                    }
                    .transition(.opacity)
                }
            }
            
            // Sub-sheet: Multiple File Picker inside Torrent
            if showFilePicker, let hash = resolvedHash {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
                VStack(spacing: 0) {
                    HStack {
                        Text("Выберите файл для воспроизведения")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: { showFilePicker = false }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(20)
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(resolvedFiles) { file in
                                Button(action: {
                                    LogManager.shared.log(serviceId: "system", text: "TorrentSelectorView: File selected from picker: \(file.filename), index: \(file.index)")
                                    showFilePicker = false
                                    startBuffering(hash: hash, fileIndex: file.index, filename: file.filename)
                                }) {
                                    HStack {
                                        Image(systemName: "play.circle")
                                            .foregroundColor(.blue)
                                        Text(file.filename)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(file.formattedSize)
                                            .font(.system(size: 11))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                    .padding(10)
                                    .background(Color.white.opacity(0.04))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(20)
                    }
                }
                .frame(width: 500, height: 350)
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(12)
                .shadow(radius: 15)
                .transition(.scale)
            }
            
            // Loading Overlay when resolving torrent metadata files
            if isLoadingFiles {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                    Text(loadingFilesText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            // Buffering Overlay View
            if let buffer = activeBufferHash {
                BufferingOverlayView(
                    hash: buffer.hash,
                    fileIndex: activeBufferFileIndex,
                    filename: activeBufferFilename,
                    title: title,
                    mediaId: mediaId,
                    kinoriumId: kinoriumId,
                    onClose: {
                        activeBufferHash = nil
                    }
                )
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .frame(width: 700, height: 500)
        .task {
            await performSearch()
        }
    }
    
    private func performSearch() async {
        isLoading = true
        showSpinner = false
        
        let delaySpinnerTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms delay
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.showSpinner = true
                    }
                }
            }
        }
        
        errorMessage = nil
        do {
            let results: [JackettResult]
            if let mediaId = mediaId, let preloadedTorrentTask = PreloadTracker.shared.getPreloadedTorrentTask(for: mediaId) {
                results = try await preloadedTorrentTask.value
            } else {
                results = try await JackettClient.shared.search(query: query)
            }
            
            delaySpinnerTask.cancel()
            
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.35)) {
                    self.torrents = results
                    self.isLoading = false
                }
                sortTorrents()
            }
        } catch {
            delaySpinnerTask.cancel()
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func sortTorrents() {
        if sortBySeeders {
            torrents.sort { $0.seedersCount > $1.seedersCount }
        } else {
            torrents.sort { ($0.size ?? 0) > ($1.size ?? 0) }
        }
    }
    
    private func selectTorrent(_ torrent: JackettResult) {
        let targetLink = torrent.magnetUri ?? torrent.link ?? ""
        guard !targetLink.isEmpty else { return }
        LogManager.shared.log(serviceId: "system", text: "TorrentSelectorView: selectTorrent called for \(torrent.computedTitle) using link: \(targetLink.prefix(80))...")
        
        loadingFilesText = "Загрузка метаданных торрента..."
        isLoadingFiles = true
        errorMessage = nil
        
        Task {
            do {
                let addResponse = try await TorrServerClient.shared.addTorrent(link: targetLink, title: torrent.computedTitle)
                let hash = addResponse.hash
                LogManager.shared.log(serviceId: "system", text: "TorrentSelectorView: TorrServer added torrent, hash: \(hash)")
                
                var files = addResponse.files ?? []
                
                if files.isEmpty {
                    // Start polling for metadata since TorrServer is fetching it from the DHT swarm
                    LogManager.shared.log(serviceId: "system", text: "TorrentSelectorView: Torrent file list is empty. Starting DHT swarm metadata poll...")
                    
                    var attempts = 0
                    let maxAttempts = 30 // Wait up to 30 seconds
                    
                    while files.isEmpty && attempts < maxAttempts {
                        try await Task.sleep(nanoseconds: 1_000_000_000) // Sleep 1s
                        attempts += 1
                        
                        let status = try await TorrServerClient.shared.getTorrentStatus(hash: hash)
                        let peersCount = status.active_peers ?? 0
                        LogManager.shared.log(serviceId: "system", text: "TorrentSelectorView: Polling status: \(status.status ?? -1), peers: \(peersCount), files count: \(status.files?.count ?? 0)")
                        
                        // Update loading visual status to user
                        await MainActor.run {
                            if status.status == 1 {
                                loadingFilesText = "Поиск пиров и метаданных (пиры: \(peersCount))..."
                            } else {
                                loadingFilesText = "Загрузка файлов торрента..."
                            }
                        }
                        
                        if let statusFiles = status.files, !statusFiles.isEmpty {
                            files = statusFiles
                            break
                        }
                    }
                }
                
                isLoadingFiles = false
                
                if files.isEmpty {
                    await MainActor.run {
                        self.errorMessage = "Не удалось загрузить файлы торрента. Нет доступных пиров."
                    }
                    LogManager.shared.log(serviceId: "system", text: "TorrentSelectorView: Metadata resolution timed out (0 peers)", isError: true)
                    return
                }
                
                // Filter out non-video files
                let videoExtensions = ["mkv", "mp4", "avi", "mov", "ts"]
                let videoFiles = files.filter { file in
                    let ext = (file.path as NSString).pathExtension.lowercased()
                    return videoExtensions.contains(ext)
                }
                LogManager.shared.log(serviceId: "system", text: "TorrentSelectorView: Filtered \(videoFiles.count) video files")
                
                if videoFiles.isEmpty {
                    await MainActor.run {
                        self.errorMessage = "В раздаче не найдены поддерживаемые видеофайлы."
                    }
                } else if videoFiles.count == 1 {
                    LogManager.shared.log(serviceId: "system", text: "TorrentSelectorView: Single video pack, auto play: \(videoFiles[0].filename)")
                    startBuffering(hash: hash, fileIndex: videoFiles[0].index, filename: videoFiles[0].filename)
                } else {
                    LogManager.shared.log(serviceId: "system", text: "TorrentSelectorView: Multi-file pack, prompting file picker")
                    await MainActor.run {
                        self.resolvedFiles = videoFiles
                        self.resolvedHash = hash
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            self.showFilePicker = true
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingFiles = false
                    let desc = error.localizedDescription
                    if desc.contains("connection was lost") || desc.contains("соединение разорвано") || desc.contains("Network connection lost") {
                        self.errorMessage = "Соединение разорвано. Возможно, сайт раздачи заблокирован вашим провайдером или требует VPN. Попробуйте выбрать раздачу со значком Magnet (они подключаются без скачивания файлов с сайта) или смените сеть."
                    } else {
                        self.errorMessage = "Не удалось добавить торрент: \(desc)"
                    }
                }
                LogManager.shared.log(serviceId: "system", text: "TorrentSelectorView: TorrServer add failed: \(error.localizedDescription)", isError: true)
            }
        }
    }
    
    private func startBuffering(hash: String, fileIndex: Int, filename: String) {
        LogManager.shared.log(serviceId: "system", text: "TorrentSelectorView: startBuffering called for hash \(hash), index \(fileIndex), file \(filename)")
        self.activeBufferFileIndex = fileIndex
        self.activeBufferFilename = filename
        self.activeBufferHash = BufferHash(hash: hash)
    }
    
    // MARK: - Title Parsing and Filtering Helpers
    
    private struct ParsedTorrentInfo {
        let title: String
        let quality: String?
        let isHDR: Bool
        let translation: String?
    }
    
    private func parseTorrentTitle(_ title: String) -> ParsedTorrentInfo {
        let lower = title.lowercased()
        
        var quality: String? = nil
        if lower.contains("2160p") || lower.contains("4k") || lower.contains("uhd") {
            quality = "4K"
        } else if lower.contains("1080p") || lower.contains("fhd") {
            quality = "1080p"
        } else if lower.contains("720p") || lower.contains("hd") {
            quality = "720p"
        }
        
        let isHDR = lower.contains("hdr") || lower.contains("dovi") || lower.contains("dolby vision")
        
        var translation: String? = nil
        if lower.contains("dub") || lower.contains("дублиров") || lower.contains("полное дублир") {
            translation = "DUB"
        } else if lower.contains("mvo") || lower.contains("многоголос") {
            translation = "MVO"
        } else if lower.contains("lvo") || lower.contains("одноголос") {
            translation = "LVO"
        } else if lower.contains("sub") || lower.contains("субтитр") {
            translation = "SUB"
        }
        
        return ParsedTorrentInfo(title: title, quality: quality, isHDR: isHDR, translation: translation)
    }
    
    private var filteredTorrents: [JackettResult] {
        if selectedCategory == "Все" {
            return torrents
        }
        return torrents.filter { tor in
            let parsed = parseTorrentTitle(tor.computedTitle)
            if selectedCategory == "4K" {
                return parsed.quality == "4K"
            } else if selectedCategory == "1080p" {
                return parsed.quality == "1080p"
            } else if selectedCategory == "720p" {
                return parsed.quality == "720p"
            } else if selectedCategory == "HDR" {
                return parsed.isHDR
            }
            return true
        }
    }
}
