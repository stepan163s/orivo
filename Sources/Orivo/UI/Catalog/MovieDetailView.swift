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
    
    public var body: some View {
        ZStack {
            // Blurred backdrop background
            if let details = details {
                AsyncImage(url: details.backdropURL) { image in
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
                            AsyncImage(url: details.posterURL) { image in
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
                                
                                // Show "Watch Movie" button if not a TV Show
                                if details.numberOfSeasons == nil {
                                    Button(action: {
                                        activeSearchQuery = SearchQuery(text: details.computedTitle)
                                        activeSearchTitle = details.computedTitle
                                    }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "play.fill")
                                            Text("Смотреть фильм")
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                        }
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 12)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                        .shadow(radius: 5)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .padding(.top, 12)
                                }
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
                                                AsyncImage(url: ep.stillURL) { image in
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
                                                AsyncImage(url: actor.profileURL) { image in
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
        }
        .frame(width: 800, height: 600)
        .sheet(item: $activeSearchQuery) { q in
            TorrentSelectorView(
                query: q.text,
                title: activeSearchTitle ?? media.computedTitle,
                onClose: {
                    activeSearchQuery = nil
                }
            )
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
