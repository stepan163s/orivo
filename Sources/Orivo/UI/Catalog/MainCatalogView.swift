import SwiftUI

public enum CatalogTab: String, CaseIterable, Identifiable {
    case trending = "В тренде"
    case movies = "Фильмы"
    case tvShows = "Сериалы"
    case search = "Поиск"
    case settings = "Настройки"
    
    public var id: String { self.rawValue }
    
    public var icon: String {
        switch self {
        case .trending: return "flame.fill"
        case .movies: return "film"
        case .tvShows: return "tv"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape"
        }
    }
}

public struct MainCatalogView: View {
    @State private var selectedTab: CatalogTab = .trending
    @State private var searchQuery: String = ""
    @State private var searchResults: [TMDBMedia] = []
    @State private var isSearching: Bool = false
    
    // Catalog feeds
    @State private var trendingMovies: [TMDBMedia] = []
    @State private var trendingTVShows: [TMDBMedia] = []
    @State private var popularMovies: [TMDBMedia] = []
    @State private var popularTVShows: [TMDBMedia] = []
    
    @State private var selectedMedia: TMDBMedia? = nil
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 0) {
            // Translucent Glassmorphic Sidebar
            VStack(alignment: .leading, spacing: 16) {
                // App Logo
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)
                    Text("Orivo")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.horizontal, 16)
                
                // Navigation Tabs
                VStack(spacing: 4) {
                    ForEach(CatalogTab.allCases) { tab in
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTab = tab
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 14, weight: .medium))
                                    .frame(width: 20)
                                Text(tab.rawValue)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                Spacer()
                            }
                            .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedTab == tab ? Color.white.opacity(0.12) : Color.clear)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                
                Spacer()
            }
            .frame(width: 200)
            .background(
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
            )
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Main Content Area
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                
                switch selectedTab {
                case .trending:
                    ScrollView {
                        VStack(spacing: 24) {
                            if let hero = trendingMovies.first {
                                HeroMarqueeView(media: hero) {
                                    selectedMedia = hero
                                }
                            }
                            
                            HorizontalSection(title: "Фильмы в тренде", items: trendingMovies) { media in
                                selectedMedia = media
                            }
                            
                            HorizontalSection(title: "Сериалы в тренде", items: trendingTVShows) { media in
                                selectedMedia = media
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    
                case .movies:
                    ScrollView {
                        VStack(spacing: 24) {
                            if let hero = popularMovies.first {
                                HeroMarqueeView(media: hero) {
                                    selectedMedia = hero
                                }
                            }
                            
                            HorizontalSection(title: "Популярные фильмы", items: popularMovies) { media in
                                selectedMedia = media
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    
                case .tvShows:
                    ScrollView {
                        VStack(spacing: 24) {
                            if let hero = popularTVShows.first {
                                HeroMarqueeView(media: hero) {
                                    selectedMedia = hero
                                }
                            }
                            
                            HorizontalSection(title: "Популярные сериалы", items: popularTVShows) { media in
                                selectedMedia = media
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    
                case .search:
                    VStack(spacing: 0) {
                        // Search Bar Header
                        HStack(spacing: 12) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.white.opacity(0.4))
                                TextField("Поиск фильмов, сериалов...", text: $searchQuery)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .foregroundColor(.white)
                                    .font(.system(size: 14))
                                    .onSubmit {
                                        performSearch()
                                    }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                            
                            Button("Найти") {
                                performSearch()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(24)
                        
                        if isSearching {
                            Spacer()
                            ProgressView()
                            Spacer()
                        } else if searchResults.isEmpty {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white.opacity(0.3))
                                Text("Введите поисковый запрос")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            Spacer()
                        } else {
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 160), spacing: 16)], spacing: 20) {
                                    ForEach(searchResults) { media in
                                        MovieCard(media: media) { selected in
                                            selectedMedia = selected
                                        }
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.bottom, 24)
                            }
                        }
                    }
                    
                case .settings:
                    SettingsView(showSettings: .constant(true))
                }
                
                // Loading Overlay
                if isLoading {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.2)
                }
            }
        }
        .frame(minWidth: 850, minHeight: 600)
        .sheet(item: $selectedMedia) { media in
            MovieDetailView(media: media)
        }
        .task {
            await loadFeedData()
        }
    }
    
    private func loadFeedData() async {
        guard trendingMovies.isEmpty else { return }
        isLoading = true
        do {
            async let trendMovies = TMDBClient.shared.fetchTrendingMovies()
            async let trendTV = TMDBClient.shared.fetchTrendingTVShows()
            async let popMovies = TMDBClient.shared.fetchPopularMovies()
            async let popTV = TMDBClient.shared.fetchPopularTVShows()
            
            self.trendingMovies = try await trendMovies
            self.trendingTVShows = try await trendTV
            self.popularMovies = try await popMovies
            self.popularTVShows = try await popTV
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    private func performSearch() {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        Task {
            do {
                self.searchResults = try await TMDBClient.shared.searchMulti(query: searchQuery)
            } catch {
                print("Search failed: \(error.localizedDescription)")
            }
            isSearching = false
        }
    }
}

// SwiftUI Visual Effect view for macOS Translucent Sidebars
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// Horizontal Scroll section for feeds
struct HorizontalSection: View {
    let title: String
    let items: [TMDBMedia]
    let onSelect: (TMDBMedia) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(items) { media in
                        MovieCard(media: media, onSelect: onSelect)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

// Individual movie poster cell
struct MovieCard: View {
    let media: TMDBMedia
    let onSelect: (TMDBMedia) -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            onSelect(media)
        }) {
            VStack(alignment: .leading, spacing: 6) {
                // Poster Image
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: media.posterURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                Image(systemName: "film")
                                    .foregroundColor(.white.opacity(0.2))
                            )
                    }
                    .frame(width: 130, height: 195)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: isHovered ? 8 : 2)
                    .scaleEffect(isHovered ? 1.03 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
                    
                    // Rating tag
                    if let rating = media.voteAverage, rating > 0 {
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(rating >= 7.0 ? Color.green.opacity(0.85) : Color.orange.opacity(0.85))
                            )
                            .padding(6)
                    }
                }
                
                // Poster Title
                Text(media.computedTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(width: 130, alignment: .leading)
                
                // Release Year
                Text(media.computedReleaseYear)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover in
            isHovered = hover
        }
    }
}

// Banner view for prominent hero layout
struct HeroMarqueeView: View {
    let media: TMDBMedia
    let onPlay: () -> Void
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop Image
            AsyncImage(url: media.backdropURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.black.opacity(0.4)
            }
            .frame(height: 280)
            .clipped()
            
            // Vignette gradient overlay
            LinearGradient(
                colors: [Color.black.opacity(0.75), Color.black.opacity(0.0), Color(nsColor: .windowBackgroundColor)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 280)
            
            LinearGradient(
                colors: [Color.black.opacity(0.5), Color.clear, Color(nsColor: .windowBackgroundColor)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 280)
            
            // Meta description info
            VStack(alignment: .leading, spacing: 8) {
                Text(media.computedTitle)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(radius: 4)
                
                Text(media.overview ?? "")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(2)
                    .frame(maxWidth: 480, alignment: .leading)
                    .shadow(radius: 2)
                
                Button(action: onPlay) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Подробнее")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 4)
            }
            .padding(24)
        }
        .frame(height: 280)
        .cornerRadius(12)
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }
}
