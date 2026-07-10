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
    let targetEpisodeNumber: Int?
    let onClose: () -> Void
    
    public init(query: String, title: String, mediaId: Int? = nil, kinoriumId: String? = nil, targetEpisodeNumber: Int? = nil, onClose: @escaping () -> Void) {
        self.query = query
        self.title = title
        self.mediaId = mediaId
        self.kinoriumId = kinoriumId
        self.targetEpisodeNumber = targetEpisodeNumber
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
    @State private var bufferingTorrentHash: String? = nil
    @State private var bufferingTimer: Task<Void, Never>? = nil
    @State private var activeTorrentId: String? = nil
    
    public var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            
            mainContent
            
            loadingFilesOverlay
            
            filePickerOverlay
            
            bufferingOverlay
        }
        .frame(width: 700, height: 500)
        .task {
            await performSearch()
        }
        .onDisappear {
            bufferingTimer?.cancel()
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            headerPanel
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            categoryPills
            
            if isLoading {
                loadingSpinner
            } else if let err = errorMessage {
                errorView(err: err)
            } else if torrents.isEmpty {
                emptyView
            } else {
                torrentsList
            }
        }
    }
    
    @ViewBuilder
    private var headerPanel: some View {
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
    }
    
    @ViewBuilder
    private var categoryPills: some View {
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
    }
    
    @ViewBuilder
    private var loadingSpinner: some View {
        Spacer()
        if showSpinner {
            ProgressView()
                .transition(.opacity)
        }
        Spacer()
    }
    
    @ViewBuilder
    private func errorView(err: String) -> some View {
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
    }
    
    @ViewBuilder
    private var emptyView: some View {
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
    }
    
    @ViewBuilder
    private var torrentsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredTorrents) { tor in
                    TorrentRowView(
                        tor: tor,
                        isBuffering: activeTorrentId == tor.id,
                        onSelect: { selectTorrent(tor) }
                    )
                }
            }
            .padding(20)
        }
        .transition(.opacity)
    }
    
    @ViewBuilder
    private var filePickerOverlay: some View {
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
    }
    
    @ViewBuilder
    private var loadingFilesOverlay: some View {
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
    }
    
    @ViewBuilder
    private var bufferingOverlay: some View {
        if let buffer = activeBufferHash {
            BufferingOverlayView(
                hash: buffer.hash,
                fileIndex: activeBufferFileIndex,
                filename: activeBufferFilename,
                title: title,
                mediaId: mediaId,
                kinoriumId: kinoriumId,
                onClose: {
                    withAnimation {
                        activeBufferHash = nil
                        bufferingTorrentHash = nil
                    }
                    bufferingTimer?.cancel()
                }
            )
            .transition(.opacity)
            .zIndex(20)
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
        
        withAnimation {
            self.activeTorrentId = torrent.id
        }
        loadingFilesText = "Загрузка метаданных торрента..."
        isLoadingFiles = false
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
                        
                        if let statusFiles = status.files, !statusFiles.isEmpty {
                            files = statusFiles
                            break
                        }
                    }
                }
                
                if files.isEmpty {
                    await MainActor.run {
                        withAnimation {
                            self.activeTorrentId = nil
                        }
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
                        withAnimation {
                            self.activeTorrentId = nil
                        }
                        self.errorMessage = "В раздаче не найдены поддерживаемые видеофайлы."
                    }
                } else if videoFiles.count == 1 {
                    LogManager.shared.log(serviceId: "system", text: "TorrentSelectorView: Single video pack, auto play: \(videoFiles[0].filename)")
                    startBuffering(hash: hash, fileIndex: videoFiles[0].index, filename: videoFiles[0].filename)
                } else {
                    // Try to auto-match the specific episode the user clicked
                    let matchedFile: TorrServerFile? = targetEpisodeNumber.flatMap { epNum in
                        videoFiles.first { fileMatchesEpisode(path: $0.path, episodeNum: epNum) }
                    }
                    
                    if let matched = matchedFile {
                        LogManager.shared.log(serviceId: "system", text: "TorrentSelectorView: Auto-matched episode \(targetEpisodeNumber!): \(matched.filename)")
                        startBuffering(hash: hash, fileIndex: matched.index, filename: matched.filename)
                    } else {
                        LogManager.shared.log(serviceId: "system", text: "TorrentSelectorView: Multi-file pack, prompting file picker")
                        await MainActor.run {
                            withAnimation {
                                self.activeTorrentId = nil
                            }
                            self.resolvedFiles = videoFiles
                            self.resolvedHash = hash
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                self.showFilePicker = true
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        self.activeTorrentId = nil
                    }
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
        
        withAnimation {
            self.bufferingTorrentHash = hash
        }
        
        self.bufferingTimer?.cancel()
        
        let checkTask = Task {
            var attempts = 0
            while !Task.isCancelled {
                do {
                    let statusResponse = try await TorrServerClient.shared.getTorrentStatus(hash: hash)
                    if statusResponse.status == 3 || statusResponse.bufferingProgress >= 1.0 {
                        await MainActor.run {
                            self.bufferingTimer?.cancel()
                            withAnimation {
                                self.activeTorrentId = nil
                                self.bufferingTorrentHash = nil
                                self.activeBufferHash = nil
                            }
                            let playURL = TorrServerClient.shared.getPlayURL(hash: hash, fileIndex: fileIndex, filename: filename)
                            NotificationCenter.default.post(name: NSNotification.Name("CloseCatalogSheets"), object: nil)
                            AppStateManager.shared.play(url: playURL, title: title, mediaId: mediaId, kinoriumID: kinoriumId)
                        }
                        break
                    }
                } catch {
                    // Ignore errors during quick polling
                }
                
                try? await Task.sleep(nanoseconds: 500_000_000) // Poll every 500ms
                attempts += 1
                
                if attempts >= 2 && !Task.isCancelled && self.activeBufferHash == nil {
                    await MainActor.run {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            self.activeBufferHash = BufferHash(hash: hash)
                        }
                        self.bufferingTimer?.cancel()
                    }
                    break
                }
            }
        }
        self.bufferingTimer = checkTask
    }
    
    // MARK: - Title Parsing and Filtering Helpers
    
    private struct ParsedTorrentInfo {
        let title: String
        let quality: String?
        let isHDR: Bool
        let translation: String?
    }
    
    private static func parseTorrentTitle(_ title: String) -> ParsedTorrentInfo {
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
            let parsed = Self.parseTorrentTitle(tor.computedTitle)
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
    
    struct TorrentRowView: View {
        let tor: JackettResult
        let isBuffering: Bool
        let onSelect: () -> Void
        
        var body: some View {
            Button(action: onSelect) {
                HStack(spacing: 16) {
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
                            
                            let parsed = TorrentSelectorView.parseTorrentTitle(tor.computedTitle)
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
                    
                    TorrentRowPeersView(
                        seeders: tor.seedersCount,
                        peers: tor.peersCount,
                        isBuffering: isBuffering
                    )
                }
                .padding(12)
                .background(Color.white.opacity(0.04))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private func fileMatchesEpisode(path: String, episodeNum: Int) -> Bool {
        let filename = (path as NSString).lastPathComponent.lowercased()
        
        // 1. SxxExx format: s01e01, s01.01, s01-01, s01_01
        let sPattern = "s\\d+[.\\-_]?e?(\\d+)"
        if let regex = try? NSRegularExpression(pattern: sPattern),
           let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
           let range = Range(match.range(at: 1), in: filename),
           let num = Int(filename[range]), num == episodeNum {
            return true
        }
        
        // 2. Standalone ep/e prefix: e01, ep01, ep_01
        let ePattern = "(?:^|[^s])(?:ep_?|e)(\\d+)\\b"
        if let regex = try? NSRegularExpression(pattern: ePattern),
           let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
           let range = Range(match.range(at: 1), in: filename),
           let num = Int(filename[range]), num == episodeNum {
            return true
        }
        
        // 3. NxNN format: 1x01
        let xPattern = "\\d+x(\\d+)"
        if let regex = try? NSRegularExpression(pattern: xPattern),
           let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
           let range = Range(match.range(at: 1), in: filename),
           let num = Int(filename[range]), num == episodeNum {
            return true
        }
        
        return false
    }
}

struct TorrentRowPeersView: View {
    let seeders: Int
    let peers: Int
    let isBuffering: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            if isBuffering {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.green)
                    Text("\(seeders)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.orange)
                    Text("\(peers)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                }
            }
        }
        .frame(width: 100)
    }
}
