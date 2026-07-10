import SwiftUI

public struct SearchQuery: Identifiable {
    public let id = UUID()
    public let text: String
    
    public init(text: String) {
        self.text = text
    }
}

public struct MovieDetailView: View {
    let media: TMDBMedia
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) var dismiss
    
    @State private var details: TMDBMediaDetail? = nil
    @State private var selectedSeason: Int = 1
    @State private var seasonDetail: TMDBSeasonDetail? = nil
    @State private var isLoading: Bool = false
    @State private var isLoadingSeason: Bool = false
    @State private var showSpinner: Bool = false
    
    // Torrent Search trigger states
    @State private var activeSearchQuery: SearchQuery? = nil
    @State private var activeSearchTitle: String? = nil
    @State private var activeEpisodeIndex: Int? = nil // Index inside the torrent file list
    
    // Online Balancers state
    @State private var showOnlineSelector = false
    @State private var onlineStreams: [BalancerStream] = []
    @State private var isLoadingOnline = false
    @State private var selectedOnlineStream: BalancerStream? = nil
    
    public var body: some View {
        ZStack {
            // Blurred backdrop background
            ZStack {
                CachedAsyncImage(url: details?.posterURL ?? media.posterURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.black
                }
                .frame(width: 800, height: 600)
                .clipped()
                .ignoresSafeArea()
                .blur(radius: 40)
                .overlay(Color.black.opacity(0.6))
                .transition(.opacity)
            }
            .frame(width: 800, height: 600)
            .clipped()
            
            // Main Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Main info row
                    HStack(alignment: .top, spacing: 24) {
                        // Poster
                        CachedAsyncImage(url: details?.posterURL ?? media.posterURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.06))
                        }
                        .frame(width: 200, height: 300)
                        .cornerRadius(12)
                        .shadow(radius: 10)
                        
                        // Text Metadata Info
                        VStack(alignment: .leading, spacing: 12) {
                            Text(details?.computedTitle ?? media.computedTitle)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            HStack(spacing: 12) {
                                if let rating = details?.voteAverage ?? media.voteAverage, rating > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(.yellow)
                                        Text(String(format: "%.1f", rating))
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(6)
                                }
                                
                                Text(details?.computedReleaseYear ?? media.computedReleaseYear)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                
                                if let details = details {
                                    if !details.runtimeString.isEmpty {
                                        Text(details.runtimeString)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                } else {
                                    SkeletonBlock(width: 60, height: 16)
                                }
                            }
                            
                            if let details = details {
                                Text(details.genresString)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                            } else {
                                SkeletonBlock(width: 140, height: 16)
                            }
                            
                            Text(details?.overview ?? media.overview ?? "Описание отсутствует.")
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                                .lineSpacing(4)
                                .padding(.top, 8)
                            
                            // Watch / Bookmark Actions Row
                            HStack(spacing: 12) {
                                let isTV = media.mediaType == "tv" || media.releaseDate == nil
                                if !isTV {
                                    Button(action: {
                                        LibraryManager.shared.addToHistory(media: media)
                                        activeSearchQuery = SearchQuery(text: details?.computedTitle ?? media.computedTitle)
                                        activeSearchTitle = details?.computedTitle ?? media.computedTitle
                                    }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "play.fill")
                                            Text("Торренты")
                                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    Button(action: {
                                        fetchOnlineStreams()
                                    }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "globe")
                                            Text("Смотреть онлайн")
                                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(Color.green)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                
                                let isFav = LibraryManager.shared.isFavorite(media: media)
                                Button(action: {
                                    LibraryManager.shared.toggleFavorite(media: media)
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: isFav ? "checkmark" : "plus")
                                            .font(.system(size: 13, weight: .bold))
                                        Text(isFav ? "В избранном" : "В избранное")
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.15))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.top, 12)
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // TV Show Seasons & Episode details
                    let isTV = media.mediaType == "tv" || media.releaseDate == nil
                    if isTV {
                        if let details = details, let seasonsCount = details.numberOfSeasons, seasonsCount > 0 {
                            VStack(alignment: .leading, spacing: 16) {
                                Divider()
                                    .background(Color.white.opacity(0.1))
                                
                                HStack {
                                    Text("Серии")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Picker("Сезон", selection: $selectedSeason) {
                                        ForEach(1...seasonsCount, id: \.self) { s in
                                            Text("Сезон \(s)").tag(s)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 140)
                                    .onChange(of: selectedSeason) { _ in
                                        Task {
                                            await loadSeasonEpisodes()
                                        }
                                    }
                                }
                                
                                if let season = seasonDetail {
                                    LazyVStack(spacing: 12) {
                                        ForEach(season.episodes) { ep in
                                            HStack(alignment: .top, spacing: 16) {
                                                CachedAsyncImage(url: ep.stillURL) { image in
                                                    image
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                } placeholder: {
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .fill(Color.white.opacity(0.06))
                                                        .overlay(Image(systemName: "tv"))
                                                }
                                                .frame(width: 120, height: 75)
                                                .cornerRadius(6)
                                                .clipped()
                                                
                                                VStack(alignment: .leading, spacing: 6) {
                                                    Text("\(ep.episodeNumber). \(ep.name)")
                                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                                        .foregroundColor(.white)
                                                    
                                                    if let air = ep.airDate, !air.isEmpty {
                                                        Text(air)
                                                            .font(.system(size: 10))
                                                            .foregroundColor(.white.opacity(0.4))
                                                    }
                                                    
                                                    if let overview = ep.overview, !overview.isEmpty {
                                                        Text(overview)
                                                            .font(.system(size: 12))
                                                            .foregroundColor(.white.opacity(0.7))
                                                            .lineLimit(2)
                                                    }
                                                }
                                                Spacer()
                                                
                                                Button(action: {
                                                    LibraryManager.shared.addToHistory(media: media)
                                                    activeSearchQuery = SearchQuery(text: "\(details.computedTitle) s\(String(format: "%02d", selectedSeason))e\(String(format: "%02d", ep.episodeNumber))")
                                                    activeSearchTitle = "\(details.computedTitle) - s\(String(format: "%02d", selectedSeason))e\(String(format: "%02d", ep.episodeNumber))"
                                                }) {
                                                    Image(systemName: "play.circle.fill")
                                                        .font(.system(size: 26))
                                                        .foregroundColor(.blue)
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                                .alignCenterVertically()
                                            }
                                            .padding(10)
                                            .background(Color.white.opacity(0.04))
                                            .cornerRadius(8)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                        } else {
                            // Shimmering Season Loader placeholder
                            VStack(alignment: .leading, spacing: 16) {
                                Divider()
                                    .background(Color.white.opacity(0.1))
                                HStack {
                                    SkeletonBlock(width: 80, height: 24)
                                    Spacer()
                                    SkeletonBlock(width: 140, height: 24)
                                }
                                VStack(spacing: 12) {
                                    ForEach(0..<3) { _ in
                                        HStack(spacing: 16) {
                                            SkeletonBlock(width: 120, height: 75)
                                            VStack(alignment: .leading, spacing: 8) {
                                                SkeletonBlock(width: 150, height: 16)
                                                SkeletonBlock(width: 250, height: 30)
                                            }
                                            Spacer()
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    
                    // Cast list
                    if let details = details, let cast = details.credits?.cast, !cast.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Divider()
                                .background(Color.white.opacity(0.1))
                            
                            Text("В главных ролях")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(cast.prefix(12)) { actor in
                                        VStack {
                                            CachedAsyncImage(url: actor.profileURL) { image in
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                Circle()
                                                    .fill(Color.white.opacity(0.06))
                                                    .overlay(Image(systemName: "person.fill").foregroundColor(.white.opacity(0.2)))
                                            }
                                            .frame(width: 60, height: 60)
                                            .clipShape(Circle())
                                            
                                            Text(actor.name)
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                                .frame(width: 80)
                                            
                                            Text(actor.character)
                                                .font(.system(size: 9))
                                                .foregroundColor(.white.opacity(0.5))
                                                .lineLimit(1)
                                                .frame(width: 80)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                    } else {
                        // Shimmering Cast Loader placeholder
                        VStack(alignment: .leading, spacing: 12) {
                            Divider()
                                .background(Color.white.opacity(0.1))
                            Text("В главных ролях")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(0..<6) { _ in
                                        VStack(spacing: 8) {
                                            Circle()
                                                .fill(Color.white.opacity(0.06))
                                                .frame(width: 60, height: 60)
                                            SkeletonBlock(width: 70, height: 10)
                                            SkeletonBlock(width: 50, height: 8)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                    }
                }
                .padding(.top, 64)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
            
            // Header Bar with Close Button (Always on top)
            VStack {
                HStack {
                    Spacer()
                    Button(action: { closeView() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                Spacer()
            }
            
            // Online Stream Selector Panel Overlay
            if showOnlineSelector, let details = details {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showOnlineSelector = false
                    }
                
                VStack(spacing: 0) {
                    HStack {
                        Text("Смотреть Онлайн — \(details.computedTitle)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: { showOnlineSelector = false }) {
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
                    
                    if isLoadingOnline {
                        Spacer()
                        ProgressView()
                        Spacer()
                    } else if onlineStreams.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "globe")
                                .font(.system(size: 32))
                                .foregroundColor(.white.opacity(0.3))
                            Text("Стримы не найдены")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        Spacer()
                    } else {
                        HStack(spacing: 0) {
                            // Left list: Translators
                            ScrollView {
                                VStack(spacing: 6) {
                                    ForEach(onlineStreams) { stream in
                                        Button(action: {
                                            selectedOnlineStream = stream
                                        }) {
                                            HStack {
                                                Text(stream.translation)
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(selectedOnlineStream?.translation == stream.translation ? .blue : .white)
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.white.opacity(0.3))
                                            }
                                            .padding(10)
                                            .background(selectedOnlineStream?.translation == stream.translation ? Color.blue.opacity(0.15) : Color.white.opacity(0.04))
                                            .cornerRadius(6)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(12)
                            }
                            .frame(width: 220)
                            
                            Divider()
                                .background(Color.white.opacity(0.1))
                            
                            // Right list: Qualities
                            ScrollView {
                                VStack(spacing: 8) {
                                    if let selected = selectedOnlineStream {
                                        ForEach(selected.qualities) { qual in
                                            Button(action: {
                                                showOnlineSelector = false
                                                LogManager.shared.log(serviceId: "system", text: "Playing online stream URL: \(qual.url)")
                                                LibraryManager.shared.addToHistory(media: media)
                                                AppStateManager.shared.play(url: qual.url, title: "\(details.computedTitle) [\(qual.quality)]", mediaId: media.id, kinoriumID: media.kinoriumID)
                                            }) {
                                                HStack {
                                                    Image(systemName: "play.fill")
                                                        .foregroundColor(.green)
                                                    Text(qual.quality)
                                                        .font(.system(size: 12, weight: .bold))
                                                        .foregroundColor(.white)
                                                    Spacer()
                                                    Text("Запустить")
                                                        .font(.system(size: 11, weight: .bold))
                                                        .foregroundColor(.blue)
                                                }
                                                .padding(10)
                                                .background(Color.white.opacity(0.04))
                                                .cornerRadius(6)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    } else {
                                        Text("Выберите озвучку слева")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white.opacity(0.5))
                                            .padding(.top, 40)
                                    }
                                }
                                .padding(12)
                            }
                        }
                    }
                }
                .frame(width: 500, height: 350)
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(12)
                .shadow(radius: 15)
                .transition(.scale)
            }
        }
        .frame(width: 800, height: 600)
        .sheet(item: $activeSearchQuery) { q in
            TorrentSelectorView(
                query: q.text,
                title: activeSearchTitle ?? media.computedTitle,
                mediaId: media.id,
                kinoriumId: media.kinoriumID,
                onClose: {
                    activeSearchQuery = nil
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseCatalogSheets"))) { _ in
            activeSearchQuery = nil
            closeView()
        }
        .task {
            await loadDetails()
        }
    }
    
    static let prefetchSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 20
        config.timeoutIntervalForRequest = 10.0
        return URLSession(configuration: config)
    }()
    
    private func preloadImage(url: URL) async throws -> NSImage {
        let startTime = Date()
        if let cached = ImageCache.shared.get(for: url) {
            let duration = Date().timeIntervalSince(startTime) * 1000
            LogManager.shared.log(serviceId: "system", text: "Preload: \(url.lastPathComponent) resolved from CACHE in \(String(format: "%.1f", duration))ms")
            return cached
        }
        let (data, _) = try await MovieDetailView.prefetchSession.data(from: url)
        guard let nsImage = NSImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        ImageCache.shared.set(nsImage, for: url)
        let duration = Date().timeIntervalSince(startTime) * 1000
        LogManager.shared.log(serviceId: "system", text: "Preload: \(url.lastPathComponent) downloaded in \(String(format: "%.1f", duration))ms (size: \(data.count) bytes)")
        return nsImage
    }

    private func loadDetails() async {
        let overallStartTime = Date()
        isLoading = true
        showSpinner = false
        
        let delaySpinnerTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000) // 350ms delay
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.showSpinner = true
                    }
                }
            }
        }
        
        do {
            let isTV = media.mediaType == "tv" || media.releaseDate == nil
            let fetchedDetails: TMDBMediaDetail
            
            if let preloadedTask = PreloadTracker.shared.getPreloadedTask(for: media.id) {
                fetchedDetails = try await preloadedTask.value
                if isTV {
                    await loadSeasonEpisodes()
                }
            } else {
                if isTV {
                    fetchedDetails = try await TMDBClient.shared.fetchTVShowDetails(id: media.id)
                    await loadSeasonEpisodes()
                } else {
                    fetchedDetails = try await TMDBClient.shared.fetchMovieDetails(id: media.id)
                }
            }
            let totalDuration = Date().timeIntervalSince(overallStartTime) * 1000
            LogManager.shared.log(serviceId: "system", text: "Preload: TOTAL details load pipeline completed in \(String(format: "%.1f", totalDuration))ms")
            
            delaySpinnerTask.cancel()
            await MainActor.run {
                if let clickTime = PreloadTracker.shared.pop(for: media.id) {
                    let perceivedDuration = Date().timeIntervalSince(clickTime) * 1000
                    LogManager.shared.log(serviceId: "system", text: "Preload: PERCEIVED click-to-load duration is \(String(format: "%.1f", perceivedDuration))ms")
                }
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.details = fetchedDetails
                    self.isLoading = false
                }
            }
            
            // Pre-download all assets in the background (non-blocking)
            Task {
                await withTaskGroup(of: Void.self) { group in
                    // Preload backdrop & poster

                    if let posterURL = fetchedDetails.posterURL {
                        group.addTask {
                            _ = try? await preloadImage(url: posterURL)
                        }
                    }
                    // Preload actor avatars
                    if let cast = fetchedDetails.credits?.cast {
                        for actor in cast.prefix(12) {
                            if let profileURL = actor.profileURL {
                                group.addTask {
                                    _ = try? await preloadImage(url: profileURL)
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            delaySpinnerTask.cancel()
            print("Failed to load TMDB details: \(error.localizedDescription)")
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadSeasonEpisodes() async {
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isLoadingSeason = true
            }
        }
        do {
            let fetchedSeason = try await TMDBClient.shared.fetchTVSeasonDetails(tvShowId: media.id, seasonNumber: selectedSeason)
            
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.35)) {
                    self.seasonDetail = fetchedSeason
                }
            }
        } catch {
            print("Failed to load TMDB season details: \(error.localizedDescription)")
        }
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.35)) {
                self.isLoadingSeason = false
            }
        }
    }
    
    private func fetchOnlineStreams() {
        guard let details = details else { return }
        isLoadingOnline = true
        showOnlineSelector = true
        onlineStreams = []
        selectedOnlineStream = nil
        
        Task {
            do {
                let streams = try await BalancersClient.shared.fetchRezkaStreams(title: details.computedTitle, year: details.computedReleaseYear)
                await MainActor.run {
                    self.onlineStreams = streams
                    if !streams.isEmpty {
                        self.selectedOnlineStream = streams[0]
                    }
                    self.isLoadingOnline = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingOnline = false
                }
                print("Failed to fetch online streams: \(error.localizedDescription)")
            }
        }
    }
    
    private func closeView() {
        if let onClose = onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

// Helper extension to wrap elements in a centering HStack
extension View {
    func alignCenterVertically() -> some View {
        VStack {
            Spacer()
            self
            Spacer()
        }
    }
}

public final class PreloadTracker: @unchecked Sendable {
    public static let shared = PreloadTracker()
    private var clickTimes: [Int: Date] = [:]
    private var preloadingTasks: [Int: Task<TMDBMediaDetail, any Error>] = [:]
    private let lock = NSLock()
    
    public func start(for mediaId: Int) {
        lock.lock()
        clickTimes[mediaId] = Date()
        lock.unlock()
    }
    
    public func pop(for mediaId: Int) -> Date? {
        lock.lock()
        let time = clickTimes.removeValue(forKey: mediaId)
        lock.unlock()
        return time
    }
    
    public func startPreload(media: TMDBMedia) {
        lock.lock()
        clickTimes[media.id] = Date()
        
        // If it's already preloading, do nothing
        guard preloadingTasks[media.id] == nil else {
            lock.unlock()
            return
        }
        
        let task = Task<TMDBMediaDetail, any Error> {
            let isTV = media.mediaType == "tv" || media.releaseDate == nil
            let fetchedDetails: TMDBMediaDetail
            if isTV {
                fetchedDetails = try await TMDBClient.shared.fetchTVShowDetails(id: media.id)
            } else {
                fetchedDetails = try await TMDBClient.shared.fetchMovieDetails(id: media.id)
            }
            
            // Prefetch the poster in background immediately
            if let posterURL = fetchedDetails.posterURL {
                Task {
                    _ = try? await PreloadTracker.preloadImage(url: posterURL)
                }
            }
            
            return fetchedDetails
        }
        preloadingTasks[media.id] = task
        lock.unlock()
    }
    
    public func getPreloadedTask(for mediaId: Int) -> Task<TMDBMediaDetail, any Error>? {
        lock.lock()
        let task = preloadingTasks.removeValue(forKey: mediaId)
        lock.unlock()
        return task
    }
    
    public static func preloadImage(url: URL) async throws -> NSImage {
        if let cached = ImageCache.shared.get(for: url) {
            return cached
        }
        let (data, _) = try await MovieDetailView.prefetchSession.data(from: url)
        guard let nsImage = NSImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        ImageCache.shared.set(nsImage, for: url)
        return nsImage
    }
}

struct SkeletonBlock: View {
    let width: CGFloat
    let height: CGFloat
    @State private var isAnimating = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.white.opacity(0.08))
            .frame(width: width, height: height)
            .opacity(isAnimating ? 0.35 : 1.0)
            .animation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear {
                isAnimating = true
            }
    }
}
