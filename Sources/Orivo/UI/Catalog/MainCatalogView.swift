import SwiftUI

public enum CatalogTab: String, CaseIterable, Identifiable {
    case search = "Поиск"
    case trending = "Главная"
    case movies = "Фильмы"
    case tvShows = "Сериалы"
    case history = "История"
    case favorites = "Избранное"
    case settings = "Настройки"
    
    public var id: String { self.rawValue }
    
    public var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .trending: return "house"
        case .movies: return "film"
        case .tvShows: return "tv"
        case .history: return "clock"
        case .favorites: return "star"
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
    
    @StateObject private var library = LibraryManager.shared
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 0) {
            // Apple TV-Style Vibrancy Sidebar
            VStack(alignment: .leading, spacing: 0) {
                // Spacer for window control buttons (traffic lights)
                Spacer().frame(height: 52)
                
                // Group 1: General Navigation
                VStack(alignment: .leading, spacing: 4) {
                    sidebarItem(for: .search)
                    sidebarItem(for: .trending)
                    sidebarItem(for: .movies)
                    sidebarItem(for: .tvShows)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 20)
                
                // Group 2: Library (Медиатека)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Медиатека")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    
                    sidebarItem(for: .history)
                    sidebarItem(for: .favorites)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 20)
                
                // Group 3: Settings
                VStack(alignment: .leading, spacing: 4) {
                    Text("Система")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    
                    sidebarItem(for: .settings)
                }
                .padding(.horizontal, 8)
                
                Spacer()
                
                // Apple Account - Profile Row
                Button(action: {
                    withAnimation {
                        selectedTab = .settings
                    }
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.5))
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Orivo Account")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            Text("Настройки сервера")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
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
                        VStack(spacing: 28) {
                            if !trendingMovies.isEmpty {
                                HeroMarqueeView(items: trendingMovies) { media in
                                    selectedMedia = media
                                }
                            }
                            
                            RankSection(title: "Топ-10 фильмов на Orivo", items: trendingMovies) { media in
                                selectedMedia = media
                            }
                            .padding(.top, 10)
                            
                            HorizontalSection(title: "Сериалы в тренде", items: trendingTVShows) { media in
                                selectedMedia = media
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    .ignoresSafeArea()
                    
                case .movies:
                    ScrollView {
                        VStack(spacing: 28) {
                            if !popularMovies.isEmpty {
                                HeroMarqueeView(items: popularMovies) { media in
                                    selectedMedia = media
                                }
                            }
                            
                            HorizontalSection(title: "Популярные фильмы", items: popularMovies) { media in
                                selectedMedia = media
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    .ignoresSafeArea()
                    
                case .tvShows:
                    ScrollView {
                        VStack(spacing: 28) {
                            if !popularTVShows.isEmpty {
                                HeroMarqueeView(items: popularTVShows) { media in
                                    selectedMedia = media
                                }
                            }
                            
                            HorizontalSection(title: "Популярные сериалы", items: popularTVShows) { media in
                                selectedMedia = media
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    .ignoresSafeArea()
                    
                case .search:
                    VStack(spacing: 0) {
                        Spacer().frame(height: 52)
                        
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
                    
                case .history:
                    historyView
                        .padding(.top, 40)
                    
                case .favorites:
                    favoritesView
                        .padding(.top, 40)
                    
                case .settings:
                    SettingsView(showSettings: .constant(true))
                        .padding(.top, 40)
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseCatalogSheets"))) { _ in
            selectedMedia = nil
        }
        .task {
            await loadFeedData()
        }
    }
    
    @ViewBuilder
    private func sidebarItem(for tab: CatalogTab) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = tab
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18, alignment: .leading)
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                Spacer()
            }
            .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTab == tab ? Color.white.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private var favoritesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Избранное")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                
                let favorites = library.favorites
                if favorites.isEmpty {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 100)
                        Image(systemName: "star")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.2))
                        Text("Список избранного пуст")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                        Text("Добавляйте фильмы и сериалы в избранное для быстрого доступа")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.3))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 300)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 160), spacing: 16)], spacing: 20) {
                        ForEach(favorites) { media in
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
    }
    
    @ViewBuilder
    private var historyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("История просмотров")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if !library.history.isEmpty {
                        Button(action: {
                            library.clearHistory()
                        }) {
                            Text("Очистить")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.red.opacity(0.8))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                
                let history = library.history
                if history.isEmpty {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 100)
                        Image(systemName: "clock")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.2))
                        Text("История просмотров пуста")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                        Text("Здесь будут отображаться фильмы и сериалы, которые вы запускали")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.3))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 300)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 160), spacing: 16)], spacing: 20) {
                        ForEach(history) { media in
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

// Horizontal Rank list (Top 10 overlay numbers)
struct RankSection: View {
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
                HStack(spacing: 24) {
                    ForEach(Array(items.prefix(10).enumerated()), id: \.element.id) { index, media in
                        HStack(alignment: .bottom, spacing: -25) {
                            Text("\(index + 1)")
                                .font(.system(size: 100, weight: .black, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                                .offset(y: 15)
                                .zIndex(0)
                            
                            MovieCard(media: media, onSelect: onSelect)
                                .zIndex(1)
                        }
                        .padding(.leading, index == 0 ? 12 : 0)
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

// Banner view for prominent hero layout (Apple TV Style)
struct HeroMarqueeView: View {
    let items: [TMDBMedia]
    let onSelect: (TMDBMedia) -> Void
    
    @State private var currentIndex = 0
    @State private var isHovered = false
    @StateObject private var library = LibraryManager.shared
    
    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            let media = items[currentIndex % items.count]
            
            ZStack(alignment: .bottomLeading) {
                // Backdrop Image
                AsyncImage(url: media.backdropURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.black.opacity(0.4)
                }
                .frame(height: 420)
                .frame(maxWidth: .infinity)
                .clipped()
                
                // Vignette gradient overlays
                LinearGradient(
                    colors: [Color.black.opacity(0.8), Color.black.opacity(0.3), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 420)
                
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.2), Color(nsColor: .windowBackgroundColor)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 420)
                
                // Content Overlay
                VStack(alignment: .leading, spacing: 10) {
                    Text("ПОПУЛЯРНОЕ НА ORIVO")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(4)
                    
                    Text(media.computedTitle)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .shadow(radius: 6)
                    
                    HStack(spacing: 8) {
                        Text(media.computedReleaseYear)
                        Text("•")
                        Text(media.mediaType == "tv" ? "Сериал" : "Фильм")
                        if let rating = media.voteAverage, rating > 0 {
                            Text("•")
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text(String(format: "%.1f", rating))
                            }
                        }
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(radius: 2)
                    
                    Text(media.overview ?? "")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(3)
                        .frame(maxWidth: 520, alignment: .leading)
                        .shadow(radius: 2)
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            onSelect(media)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                Text("Подробнее")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        let isFav = library.isFavorite(media: media)
                        Button(action: {
                            library.toggleFavorite(media: media)
                        }) {
                            Image(systemName: isFav ? "checkmark" : "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.top, 8)
                }
                .padding(40)
                
                // Left & Right navigation arrows
                if isHovered {
                    HStack {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                currentIndex = (currentIndex - 1 + items.count) % items.count
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 80)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.leading, 12)
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                currentIndex = (currentIndex + 1) % items.count
                            }
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 80)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.trailing, 12)
                    }
                    .frame(height: 420)
                }
                
                // Page Indicator dots
                HStack(spacing: 6) {
                    ForEach(0..<min(items.count, 8), id: \.self) { idx in
                        Circle()
                            .fill(idx == (currentIndex % items.count) ? Color.white : Color.white.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: 420)
            .onHover { hover in
                withAnimation {
                    isHovered = hover
                }
            }
        }
    }
}
