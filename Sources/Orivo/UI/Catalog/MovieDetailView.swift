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
    @Environment(\.dismiss) var dismiss
    
    @State private var details: TMDBMediaDetail? = nil
    @State private var selectedSeason: Int = 1
    @State private var seasonDetail: TMDBSeasonDetail? = nil
    @State private var isLoading: Bool = false
    @State private var isLoadingSeason: Bool = false
    
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
            if let details = details {
                CachedAsyncImage(url: details.backdropURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.black
                }
                .frame(minWidth: 800, minHeight: 600)
                .ignoresSafeArea()
                .blur(radius: 40)
                .overlay(Color.black.opacity(0.6))
            } else {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()
            }
            
            // Detail Scroll container
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header Bar with Close Button
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
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
                    
                    if isLoading {
                        VStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .frame(minHeight: 400)
                    } else if let details = details {
                        // Main info row
                        HStack(alignment: .top, spacing: 24) {
                            // Poster
                            CachedAsyncImage(url: details.posterURL) { image in
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
                                Text(details.computedTitle)
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                
                                HStack(spacing: 12) {
                                    if let rating = details.voteAverage, rating > 0 {
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
                                    
                                    Text(details.computedReleaseYear)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                    
                                    if !details.runtimeString.isEmpty {
                                        Text(details.runtimeString)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }
                                
                                Text(details.genresString)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                                
                                Text(details.overview ?? "Описание отсутствует.")
                                    .font(.system(size: 14, weight: .regular, design: .rounded))
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineSpacing(4)
                                    .padding(.top, 8)
                                
                                // Watch / Bookmark Actions Row
                                HStack(spacing: 12) {
                                    if details.numberOfSeasons == nil {
                                        Button(action: {
                                            LibraryManager.shared.addToHistory(media: media)
                                            activeSearchQuery = SearchQuery(text: details.computedTitle)
                                            activeSearchTitle = details.computedTitle
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
                        if let seasonsCount = details.numberOfSeasons, seasonsCount > 0 {
                            VStack(alignment: .leading, spacing: 16) {
                                Divider()
                                    .background(Color.white.opacity(0.1))
                                
                                HStack {
                                    Text("Серии")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    // Season Picker Dropdown menu
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
                                
                                if isLoadingSeason {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                        Spacer()
                                    }
                                    .frame(height: 150)
                                } else if let season = seasonDetail {
                                    LazyVStack(spacing: 12) {
                                        ForEach(season.episodes) { ep in
                                            HStack(alignment: .top, spacing: 16) {
                                                // Still Thumbnail
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
                                                
                                                // Episode Info
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("\(ep.episodeNumber). \(ep.name)")
                                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                                        .foregroundColor(.white)
                                                    
                                                    Text(ep.overview ?? "")
                                                        .font(.system(size: 11, weight: .regular))
                                                        .foregroundColor(.white.opacity(0.7))
                                                        .lineLimit(3)
                                                }
                                                
                                                Spacer()
                                                
                                                // Play Episode Button
                                                Button(action: {
                                                    LibraryManager.shared.addToHistory(media: media)
                                                    // Search for Series SxxExx torrents
                                                    let sStr = String(format: "%02d", selectedSeason)
                                                    let eStr = String(format: "%02d", ep.episodeNumber)
                                                    activeSearchQuery = SearchQuery(text: "\(details.computedTitle) S\(sStr)E\(eStr)")
                                                    activeSearchTitle = "\(details.computedTitle) - С\(selectedSeason)Э\(ep.episodeNumber) \"\(ep.name)\""
                                                }) {
                                                    Image(systemName: "play.circle.fill")
                                                        .font(.system(size: 28))
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
                        }
                        
                        // Cast list
                        if let cast = details.credits?.cast, !cast.isEmpty {
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
                        }
                    }
                }
                .padding(.bottom, 40)
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
            dismiss()
        }
        .task {
            await loadDetails()
        }
    }
    
    private func loadDetails() async {
        isLoading = true
        do {
            let isTV = media.mediaType == "tv" || media.releaseDate == nil
            if isTV {
                self.details = try await TMDBClient.shared.fetchTVShowDetails(id: media.id)
                await loadSeasonEpisodes()
            } else {
                self.details = try await TMDBClient.shared.fetchMovieDetails(id: media.id)
            }
        } catch {
            print("Failed to load TMDB details: \(error.localizedDescription)")
        }
        isLoading = false
    }
    
    private func loadSeasonEpisodes() async {
        isLoadingSeason = true
        do {
            self.seasonDetail = try await TMDBClient.shared.fetchTVSeasonDetails(tvShowId: media.id, seasonNumber: selectedSeason)
        } catch {
            print("Failed to load TMDB season details: \(error.localizedDescription)")
        }
        isLoadingSeason = false
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
