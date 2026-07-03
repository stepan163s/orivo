import SwiftUI

public struct SettingsView: View {
    @ObservedObject var settingsManager = SettingsManager.shared
    @ObservedObject var serviceManager = ServiceManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @Binding var showSettings: Bool
    
    @AppStorage("catalogInterfaceMode") private var catalogInterfaceMode: String = "lampa"
    
    @State private var activeCategory: SettingsCategory = .general
    @State private var showingAdvanced = false
    @State private var showingParserSettings = false
    @State private var showingExternalSettings = false
    @State private var selectedLogServiceId: String? = nil
    
    // CUB Pairing state
    @State private var cubPairingCode: String = ""
    @State private var cubPairingStatusText: String = ""
    @State private var isPollingCUB = false
    
    // Trakt Pairing state
    @State private var traktPairingCode: String = ""
    @State private var traktPairingStatusText: String = ""
    @State private var isPollingTrakt = false
    
    // Kinorium state
    @State private var kinoriumInputEmail = ""
    @State private var kinoriumInputPassword = ""
    @State private var kinoriumStatusText = ""
    @State private var isLoggingInKinorium = false
    @State private var showingKinoriumLoginSheet = false
    @State private var kinoriumLoginURL: URL? = nil
    
    @State private var indexers: [JackettIndexer] = []
    @State private var isLoadingIndexers = false
    
    public init(showSettings: Binding<Bool>) {
        self._showSettings = showSettings
    }
    
    enum SettingsCategory: String, CaseIterable, Identifiable {
        case general = "general"
        case parser = "parser"
        case components = "components"
        case sync = "sync"
        case external = "external"
        
        var id: String { self.rawValue }
        
        @MainActor
        func title(loc: LocalizationManager) -> String {
            switch self {
            case .general:
                return loc.tr("general")
            case .parser:
                return loc.currentLanguage == "ru" ? "Парсер и Jackett" : "Parser & Jackett"
            case .components:
                return loc.tr("components")
            case .sync:
                return loc.currentLanguage == "ru" ? "Синхронизация" : "Synchronization"
            case .external:
                return loc.currentLanguage == "ru" ? "Внешние сервера" : "External Servers"
            }
        }
        
        var icon: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .parser: return "network"
            case .components: return "cpu"
            case .sync: return "arrow.triangle.2.circlepath"
            case .external: return "server.rack"
            }
        }
    }
    
    public var body: some View {
        GeometryReader { geo in
            if geo.size.width >= 600 {
                // Wide, spacious, macOS native-style settings pane
                largeTwoPaneLayout
            } else {
                // Original compact settings list for small window dashboard
                compactSettingsView
            }
        }
        .sheet(isPresented: $showingKinoriumLoginSheet) {
            if let url = kinoriumLoginURL {
                KinoriumLoginSheet(url: url) { result in
                    showingKinoriumLoginSheet = false
                    
                    switch result {
                    case .cookie(let cookiesString, let cookies):
                        let extractedEmail = cookies.first(where: { 
                            let name = $0.name.lowercased()
                            return name.contains("mail") || name.contains("login") || name.contains("user") || name.contains("name")
                        })?.value ?? "OAuth Profile"
                        
                        settingsManager.updateSetting(\.kinoriumToken, value: cookiesString)
                        settingsManager.updateSetting(\.kinoriumEmail, value: extractedEmail)
                        settingsManager.saveSettings()
                        kinoriumStatusText = "Успешно авторизовано!"
                        
                    case .deepLink(_, let parameters):
                        let email = parameters["access_token[email]"] ?? "Apple OAuth Profile"
                        let token = parameters["access_token[id]"] ?? ""
                        let secret = parameters["secret"] ?? ""
                        
                        kinoriumStatusText = "Завершаем авторизацию через Apple ID..."
                        isLoggingInKinorium = true
                        Task {
                            do {
                                try await KinoriumClient.shared.authenticateWithApple(accessTokenID: token, email: email, secret: secret)
                                await MainActor.run {
                                    self.kinoriumStatusText = "Успешно авторизовано через Apple ID!"
                                    self.isLoggingInKinorium = false
                                }
                            } catch {
                                await MainActor.run {
                                    self.kinoriumStatusText = "Ошибка: \(error.localizedDescription)"
                                    self.isLoggingInKinorium = false
                                }
                            }
                        }
                    }
                } onCancel: {
                    showingKinoriumLoginSheet = false
                }
            }
        }
    }
    
    // MARK: - Large Two-Pane Layout
    private var largeTwoPaneLayout: some View {
        HStack(spacing: 0) {
            // Sidebar Navigation Pane
            VStack(alignment: .leading, spacing: 6) {
                Text(loc.tr("settings"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                
                ForEach(SettingsCategory.allCases) { category in
                    Button(action: {
                        selectedLogServiceId = nil
                        activeCategory = category
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: category.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 18, alignment: .leading)
                            Text(category.title(loc: loc))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                            Spacer()
                        }
                        .foregroundColor(activeCategory == category && selectedLogServiceId == nil ? .white : .white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(activeCategory == category && selectedLogServiceId == nil ? Color.white.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 8)
                
                Spacer()
            }
            .frame(width: 220)
            .background(Color.white.opacity(0.02))
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Details Pane Content area
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                
                if let serviceId = selectedLogServiceId {
                    // Logs view inside details pane
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button(action: { selectedLogServiceId = nil }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("Назад к службам")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Spacer()
                            
                            Button(action: triggerClearLogs) {
                                Text(loc.tr("clear"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.bottom, 4)
                        
                        LogConsoleView(serviceId: serviceId, activeLogServiceId: $selectedLogServiceId)
                    }
                    .padding(24)
                    .transition(.move(edge: .trailing))
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(activeCategory.title(loc: loc))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.bottom, 8)
                            
                            switch activeCategory {
                            case .general:
                                largeGeneralCategory
                            case .parser:
                                largeParserCategory
                            case .components:
                                largeComponentsCategory
                            case .sync:
                                largeSyncCategory
                            case .external:
                                largeExternalCategory
                            }
                        }
                        .padding(24)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Category Sections
    @ViewBuilder
    private var largeGeneralCategory: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Box 1: Startup & Window policies
            VStack(alignment: .leading, spacing: 12) {
                Text("Запуск и закрытие")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                
                Toggle(loc.tr("launch_login"), isOn: Binding(
                    get: { settingsManager.settings.launchAtLogin },
                    set: { settingsManager.updateSetting(\.launchAtLogin, value: $0) }
                ))
                .toggleStyle(CheckboxToggleStyle())
                
                Toggle(loc.tr("open_library_launch"), isOn: Binding(
                    get: { settingsManager.settings.openLibraryOnLaunch },
                    set: { settingsManager.updateSetting(\.openLibraryOnLaunch, value: $0) }
                ))
                .toggleStyle(CheckboxToggleStyle())
                
                Toggle(loc.tr("quit_on_close"), isOn: Binding(
                    get: { settingsManager.settings.quitOnClose },
                    set: { settingsManager.updateSetting(\.quitOnClose, value: $0) }
                ))
                .toggleStyle(CheckboxToggleStyle())
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            
            // Box 2: Interface config
            VStack(alignment: .leading, spacing: 14) {
                Text("Язык и интерфейс")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                
                HStack {
                    Text(loc.tr("language"))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Picker("", selection: $loc.currentLanguage) {
                        Text(loc.tr("english")).tag("en")
                        Text(loc.tr("russian")).tag("ru")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 140)
                }
                
                Divider()
                    .background(Color.white.opacity(0.08))
                
                HStack {
                    Text(loc.currentLanguage == "ru" ? "Интерфейс каталога" : "Catalog Interface")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Picker("", selection: $catalogInterfaceMode) {
                        Text(loc.currentLanguage == "ru" ? "Нативный" : "Native").tag("native")
                        Text("Lampa Web").tag("lampa")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 160)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
        }
        .font(.system(size: 13))
    }
    
    @ViewBuilder
    private var largeParserCategory: some View {
        VStack(alignment: .leading, spacing: 20) {
            // TorrServer group
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Встроенный TorrServer")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    Button("Открыть Web UI") {
                        openServiceWebUI(serviceId: "torrserver")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.blue)
                    .buttonStyle(PlainButtonStyle())
                }
                
                Toggle(loc.currentLanguage == "ru" ? "Использовать встроенный TorrServer" : "Use TorrServer", isOn: Binding(
                    get: { settingsManager.settings.useTorrServer },
                    set: { settingsManager.updateSetting(\.useTorrServer, value: $0) }
                ))
                .toggleStyle(CheckboxToggleStyle())
                
                if settingsManager.settings.useTorrServer {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.currentLanguage == "ru" ? "Адрес TorrServer" : "TorrServer Host URL")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        
                        TextField("http://127.0.0.1:8090", text: Binding(
                            get: { settingsManager.settings.torrserverHost },
                            set: { settingsManager.updateSetting(\.torrserverHost, value: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 12))
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            
            // Jackett group
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Интеграция Jackett")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    Button("Открыть Web UI") {
                        openServiceWebUI(serviceId: "jackett")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.blue)
                    .buttonStyle(PlainButtonStyle())
                }
                
                Toggle(loc.currentLanguage == "ru" ? "Использовать Jackett" : "Use Jackett", isOn: Binding(
                    get: { settingsManager.settings.useJackett },
                    set: { settingsManager.updateSetting(\.useJackett, value: $0) }
                ))
                .toggleStyle(CheckboxToggleStyle())
                
                if settingsManager.settings.useJackett {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.currentLanguage == "ru" ? "Адрес Jackett" : "Jackett Host URL")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        
                        TextField("http://127.0.0.1:9117", text: Binding(
                            get: { settingsManager.settings.jackettHost },
                            set: { settingsManager.updateSetting(\.jackettHost, value: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 12))
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            
            // Jackett Indexers
            if settingsManager.settings.useJackett {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(loc.currentLanguage == "ru" ? "Активные индексаторы Jackett" : "Active Jackett Indexers")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                        Button(action: loadIndexers) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    if isLoadingIndexers {
                        HStack {
                            Spacer()
                            ProgressView().scaleEffect(0.8)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else if indexers.isEmpty {
                        Text(loc.currentLanguage == "ru" ? "Индексаторы не найдены." : "No indexers found.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    } else {
                        VStack(spacing: 6) {
                            ForEach(indexers) { indexer in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill((indexer.configured ?? false) ? Color.green : Color.gray)
                                        .frame(width: 6, height: 6)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(indexer.name ?? "Без названия")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white)
                                        
                                        if let desc = indexer.description, !desc.isEmpty {
                                            Text(desc)
                                                .font(.system(size: 10))
                                                .foregroundColor(.white.opacity(0.5))
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Text((indexer.configured ?? false) ? (loc.currentLanguage == "ru" ? "Активен" : "Active") : (loc.currentLanguage == "ru" ? "Не активен" : "Inactive"))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor((indexer.configured ?? false) ? Color.green : .white.opacity(0.4))
                                }
                                .padding(8)
                                .background(Color.white.opacity(0.03))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.04))
                .cornerRadius(12)
                .task {
                    loadIndexers()
                }
            }
        }
        .font(.system(size: 13))
    }
    
    @ViewBuilder
    private var largeComponentsCategory: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Box 1: Services statuses
            VStack(alignment: .leading, spacing: 12) {
                Text("Статус служб")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                
                ForEach(serviceManager.services) { service in
                    let status = serviceManager.statuses[service.id] ?? .stopped
                    HStack {
                        Text(service.name)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(status.isRunning ? Color.green : Color.red)
                                .frame(width: 6, height: 6)
                            Text(loc.tr(status.rawValue.lowercased()))
                                .foregroundColor(status.isRunning ? .green : .white.opacity(0.5))
                        }
                    }
                    .padding(.vertical, 2)
                }
                
                Divider()
                    .background(Color.white.opacity(0.08))
                
                HStack {
                    Text(loc.tr("mac_ip"))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(getLocalIPAddress())
                        .foregroundColor(.white)
                        .textSelection(.enabled)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            
            // Box 2: Logs
            VStack(alignment: .leading, spacing: 10) {
                Text("Логирование и отладка")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 2)
                
                ForEach(serviceManager.services) { service in
                    Button(action: { selectedLogServiceId = service.id }) {
                        HStack {
                            Text("\(service.name) - Лог работы")
                                .foregroundColor(.blue)
                            Spacer()
                            Image(systemName: "terminal")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
        }
        .font(.system(size: 13))
    }
    
    @ViewBuilder
    private var largeExternalCategory: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Box 1: Toggle
            VStack(alignment: .leading, spacing: 12) {
                Text(loc.currentLanguage == "ru" ? "Использование внешних серверов" : "Use External Servers")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                
                Toggle(loc.currentLanguage == "ru" ? "Использовать внешние сервера" : "Use External Servers", isOn: Binding(
                    get: { settingsManager.settings.useExternalServers },
                    set: { newValue in
                        settingsManager.updateSetting(\.useExternalServers, value: newValue)
                        if newValue {
                            serviceManager.stopAllServices()
                        } else {
                            serviceManager.startAllAutoStartServices()
                        }
                    }
                ))
                .toggleStyle(CheckboxToggleStyle())
                
                Text(loc.currentLanguage == "ru" 
                    ? "При включении локальные службы Jackett и TorrServer будут полностью остановлены для экономии ресурсов." 
                    : "When enabled, local Jackett and TorrServer services will be stopped to save system resources.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            
            if settingsManager.settings.useExternalServers {
                // Box 2: Configuration inputs
                VStack(alignment: .leading, spacing: 14) {
                    Text(loc.currentLanguage == "ru" ? "Настройка подключения" : "Connection Configuration")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.bottom, 2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.currentLanguage == "ru" ? "Адрес внешнего веб-сервиса Lampa (опционально)" : "External Lampa Web URL (Optional)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        TextField("Например, http://lampa.mx или локальный адрес сервера", text: Binding(
                            get: { settingsManager.settings.externalLampaURL },
                            set: { settingsManager.updateSetting(\.externalLampaURL, value: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 12))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.currentLanguage == "ru" ? "Адрес внешнего TorrServer" : "External TorrServer URL")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        TextField("http://192.168.1.100:8090", text: Binding(
                            get: { settingsManager.settings.externalTorrServerHost },
                            set: { settingsManager.updateSetting(\.externalTorrServerHost, value: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 12))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.currentLanguage == "ru" ? "Адрес внешнего Jackett" : "External Jackett URL")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        TextField("http://192.168.1.100:9117", text: Binding(
                            get: { settingsManager.settings.externalJackettHost },
                            set: { settingsManager.updateSetting(\.externalJackettHost, value: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 12))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.currentLanguage == "ru" ? "API-ключ внешнего Jackett" : "External Jackett API Key")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        TextField("Введите API-ключ", text: Binding(
                            get: { settingsManager.settings.externalJackettApiKey },
                            set: { settingsManager.updateSetting(\.externalJackettApiKey, value: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 12))
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.04))
                .cornerRadius(12)
            }
        }
        .font(.system(size: 13))
    }
    
    // MARK: - Synchronization Category
    @ViewBuilder
    private var largeSyncCategory: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Box 1: CUB Sync Settings
            VStack(alignment: .leading, spacing: 14) {
                Text(loc.currentLanguage == "ru" ? "Синхронизация CUB (Lampa)" : "CUB (Lampa) Synchronization")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                
                Text(loc.currentLanguage == "ru" 
                    ? "Позволяет синхронизировать нативное Избранное и Историю с серверами CUB (или вашим зеркалом)." 
                    : "Allows synchronizing native Favorites & History with CUB.red servers (or your mirror).")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.currentLanguage == "ru" ? "Адрес зеркала CUB (опционально)" : "CUB Mirror URL (Optional)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        TextField("Например, https://cub.red или https://cub.rip", text: Binding(
                            get: { settingsManager.settings.cubMirrorURL },
                            set: { settingsManager.updateSetting(\.cubMirrorURL, value: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 12))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.currentLanguage == "ru" ? "Токен авторизации CUB" : "CUB Access Token")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        SecureField("Введите токен (или получите по PIN ниже)", text: Binding(
                            get: { settingsManager.settings.cubToken },
                            set: { settingsManager.updateSetting(\.cubToken, value: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 12))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.currentLanguage == "ru" ? "ID профиля CUB (опционально)" : "CUB Profile ID (Optional)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        TextField("Оставьте пустым для профиля по умолчанию", text: Binding(
                            get: { settingsManager.settings.cubProfileID },
                            set: { settingsManager.updateSetting(\.cubProfileID, value: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 12))
                    }
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                HStack(spacing: 12) {
                    Button(action: startCUBPairing) {
                        HStack {
                            Image(systemName: "key.fill")
                            Text(isPollingCUB ? "Ожидание..." : (loc.currentLanguage == "ru" ? "Связать устройство" : "Pair Device"))
                        }
                    }
                    .disabled(isPollingCUB)
                    
                    Button(action: {
                        Task {
                            await LibraryManager.shared.syncWithCUB()
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text(loc.currentLanguage == "ru" ? "Синхронизировать сейчас" : "Sync Now")
                        }
                    }
                    .disabled(settingsManager.settings.cubToken.isEmpty)
                }
                
                if !cubPairingStatusText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if !cubPairingCode.isEmpty {
                            HStack(spacing: 8) {
                                Text(loc.currentLanguage == "ru" ? "Код сопряжения:" : "Pairing PIN:")
                                    .font(.system(size: 12, weight: .bold))
                                Text(cubPairingCode)
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundColor(.yellow)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.12))
                                    .cornerRadius(6)
                            }
                        }
                        Text(cubPairingStatusText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(8)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            
            // Box 2: Trakt.tv settings
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Синхронизация Trakt.tv")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    if !settingsManager.settings.traktToken.isEmpty {
                        Text(loc.currentLanguage == "ru" ? "Активен" : "Active")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(6)
                    }
                }
                
                Text(loc.currentLanguage == "ru"
                    ? "Отмечает просмотренные фильмы и прогресс воспроизведения на Trakt.tv при использовании нативного плеера."
                    : "Automatically marks watched movies and tracks playback progress on Trakt.tv within Orivo's player.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trakt Client ID:")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        TextField("Получить на trakt.tv/oauth/applications", text: Binding(
                            get: { settingsManager.settings.traktClientID },
                            set: { settingsManager.updateSetting(\.traktClientID, value: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 12))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trakt Client Secret:")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        SecureField("Client Secret", text: Binding(
                            get: { settingsManager.settings.traktClientSecret },
                            set: { settingsManager.updateSetting(\.traktClientSecret, value: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 12))
                    }
                }
                
                HStack(spacing: 12) {
                    Button(action: startTraktPairing) {
                        HStack {
                            Image(systemName: "key.fill")
                            Text(isPollingTrakt ? "Ожидание..." : (loc.currentLanguage == "ru" ? "Связать устройство" : "Pair Device"))
                        }
                    }
                    .disabled(isPollingTrakt)
                    
                    if !settingsManager.settings.traktToken.isEmpty {
                        Button(action: {
                            settingsManager.updateSetting(\.traktToken, value: "")
                        }) {
                            Text(loc.currentLanguage == "ru" ? "Выйти" : "Sign Out")
                        }
                    }
                }
                
                if !traktPairingStatusText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if !traktPairingCode.isEmpty {
                            HStack(spacing: 8) {
                                Text(loc.currentLanguage == "ru" ? "Код сопряжения:" : "Pairing PIN:")
                                    .font(.system(size: 12, weight: .bold))
                                Text(traktPairingCode)
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundColor(.yellow)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.12))
                                    .cornerRadius(6)
                            }
                        }
                        Text(traktPairingStatusText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(8)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            
            // Box 3: TMDB Key
            VStack(alignment: .leading, spacing: 12) {
                Text(loc.currentLanguage == "ru" ? "Ключ TMDB (Каталог)" : "TMDB API Key (Catalog)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                
                Text(loc.currentLanguage == "ru"
                    ? "Укажите ваш персональный API-ключ v3 (по умолчанию используется встроенный ключ Orivo)."
                    : "Specify your custom v3 API key (defaults to Orivo's built-in key).")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.currentLanguage == "ru" ? "API-ключ v3 (опционально)" : "API Key v3 (Optional)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                    TextField(loc.currentLanguage == "ru" ? "Введите API-ключ" : "Enter API key", text: Binding(
                        get: { settingsManager.settings.tmdbApiKey },
                        set: { settingsManager.updateSetting(\.tmdbApiKey, value: $0) }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 12))
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            
            // Box 4: HDRezka Mirror
            VStack(alignment: .leading, spacing: 12) {
                Text(loc.currentLanguage == "ru" ? "Зеркало HDRezka (Онлайн фильмы)" : "HDRezka Mirror (Online Movies)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                
                Text(loc.currentLanguage == "ru"
                    ? "Если онлайн-фильмы не запускаются или выдают ошибку, пропишите рабочий адрес зеркала HDRezka."
                    : "If streams fail to search or load, specify a working HDRezka mirror domain.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.currentLanguage == "ru" ? "Адрес зеркала (домен)" : "Mirror Domain")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                    TextField("https://rezka.ag", text: Binding(
                        get: { settingsManager.settings.rezkaMirrorURL },
                        set: { settingsManager.updateSetting(\.rezkaMirrorURL, value: $0) }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 12))
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            
            // Box 5: Kinorium integration
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(loc.currentLanguage == "ru" ? "Интеграция Кинориум" : "Kinorium Integration")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    if !settingsManager.settings.kinoriumEmail.isEmpty {
                        Text(loc.currentLanguage == "ru" ? "Вошли в \(settingsManager.settings.kinoriumEmail)" : "Active (\(settingsManager.settings.kinoriumEmail))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(6)
                    }
                }
                
                Text(loc.currentLanguage == "ru"
                    ? "Позволяет импортировать оценки, историю просмотров и списки из вашего профиля на Кинориуме."
                    : "Allows importing ratings, watch history, and lists from your Kinorium profile.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                
                if settingsManager.settings.kinoriumEmail.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Button(action: {
                                kinoriumLoginURL = URL(string: "https://api.kinorium.com/api/google/?action=auth")
                                showingKinoriumLoginSheet = true
                            }) {
                                HStack {
                                    Image(systemName: "g.circle.fill")
                                    Text(loc.currentLanguage == "ru" ? "Вход через Google" : "Sign in with Google")
                                }
                            }
                            
                            Button(action: {
                                kinoriumLoginURL = URL(string: "https://api.kinorium.com/api/apple/?action=auth")
                                showingKinoriumLoginSheet = true
                            }) {
                                HStack {
                                    Image(systemName: "applelogo")
                                    Text(loc.currentLanguage == "ru" ? "Вход через Apple" : "Sign in with Apple")
                                }
                            }
                        }
                        
                        Divider()
                            .background(Color.white.opacity(0.1))
                            .padding(.vertical, 4)
                        
                        Text(loc.currentLanguage == "ru" ? "Или по логину и паролю:" : "Or use email and password:")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Email:")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                            TextField("example@gmail.com", text: $kinoriumInputEmail)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.system(size: 12))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(loc.currentLanguage == "ru" ? "Пароль:" : "Password:")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                            SecureField("Password", text: $kinoriumInputPassword)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.system(size: 12))
                        }
                        
                        Button(action: loginToKinorium) {
                            HStack {
                                if isLoggingInKinorium {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 12, height: 12)
                                }
                                Text(loc.currentLanguage == "ru" ? "Войти по Email" : "Log In by Email")
                            }
                        }
                        .disabled(isLoggingInKinorium || kinoriumInputEmail.isEmpty || kinoriumInputPassword.isEmpty)
                    }
                } else {
                    Button(action: {
                        settingsManager.updateSetting(\.kinoriumToken, value: "")
                        settingsManager.updateSetting(\.kinoriumEmail, value: "")
                        kinoriumInputEmail = ""
                        kinoriumInputPassword = ""
                        kinoriumStatusText = ""
                    }) {
                        Text(loc.currentLanguage == "ru" ? "Выйти" : "Log Out")
                    }
                }
                
                if !kinoriumStatusText.isEmpty {
                    Text(kinoriumStatusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(kinoriumStatusText.contains("Ошибка") || kinoriumStatusText.contains("Failed") ? .red.opacity(0.8) : .white.opacity(0.8))
                        .padding(8)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(6)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
        }
        .font(.system(size: 13))
    }
    
    private func startCUBPairing() {
        cubPairingCode = ""
        cubPairingStatusText = "Запрос кода сопряжения..."
        isPollingCUB = true
        
        Task {
            do {
                let pairing = try await CUBClient.shared.requestPairingCode()
                await MainActor.run {
                    self.cubPairingCode = pairing.user_code
                    self.cubPairingStatusText = "Перейдите на \(pairing.verification_url) и введите указанный выше код."
                }
                
                var attempts = 0
                let maxAttempts = 60
                while isPollingCUB && attempts < maxAttempts {
                    try await Task.sleep(nanoseconds: UInt64(pairing.interval * 1_000_000_000))
                    attempts += 1
                    
                    let tokenRes = try await CUBClient.shared.pollPairingStatus(deviceCode: pairing.device_code)
                    if let token = tokenRes.token, !token.isEmpty {
                        await MainActor.run {
                            settingsManager.settings.cubToken = token
                            settingsManager.saveSettings()
                            self.cubPairingStatusText = "Устройство успешно связано!"
                            self.isPollingCUB = false
                            
                            Task {
                                await LibraryManager.shared.syncWithCUB()
                            }
                        }
                        break
                    } else if tokenRes.error == "expired_token" {
                        await MainActor.run {
                            self.cubPairingStatusText = "Срок действия кода истек. Попробуйте еще раз."
                            self.isPollingCUB = false
                        }
                        break
                    }
                }
            } catch {
                await MainActor.run {
                    self.cubPairingStatusText = "Ошибка: \(error.localizedDescription)"
                    self.isPollingCUB = false
                }
            }
        }
    }
    
    private func startTraktPairing() {
        traktPairingCode = ""
        traktPairingStatusText = "Запрос кода сопряжения..."
        isPollingTrakt = true
        
        Task {
            do {
                let pairing = try await TraktClient.shared.requestPairingCode()
                await MainActor.run {
                    self.traktPairingCode = pairing.user_code
                    self.traktPairingStatusText = "Перейдите на \(pairing.verification_url) и введите указанный выше код."
                }
                
                var attempts = 0
                let maxAttempts = 60
                while isPollingTrakt && attempts < maxAttempts {
                    try await Task.sleep(nanoseconds: UInt64(pairing.interval * 1_000_000_000))
                    attempts += 1
                    
                    let tokenRes = try await TraktClient.shared.pollPairingStatus(deviceCode: pairing.device_code)
                    if let token = tokenRes.access_token, !token.isEmpty {
                        await MainActor.run {
                            settingsManager.settings.traktToken = token
                            settingsManager.saveSettings()
                            self.traktPairingStatusText = "Устройство успешно связано!"
                            self.isPollingTrakt = false
                        }
                        break
                    }
                }
            } catch {
                await MainActor.run {
                    self.traktPairingStatusText = "Ошибка: \(error.localizedDescription)"
                    self.isPollingTrakt = false
                }
            }
        }
    }
    
    private func loginToKinorium() {
        kinoriumStatusText = "Авторизация..."
        isLoggingInKinorium = true
        
        Task {
            do {
                try await KinoriumClient.shared.authenticate(email: kinoriumInputEmail, password: kinoriumInputPassword)
                await MainActor.run {
                    self.kinoriumStatusText = "Успешно авторизовано!"
                    self.isLoggingInKinorium = false
                }
            } catch {
                await MainActor.run {
                    self.kinoriumStatusText = "Ошибка: \(error.localizedDescription)"
                    self.isLoggingInKinorium = false
                }
            }
        }
    }
    
    // MARK: - Compact Settings View
    private var compactSettingsView: some View {
        VStack(spacing: 0) {
            navigationHeader
            
            Divider()
                .background(OrivoTheme.borderDefault)
            
            ZStack {
                if let serviceId = selectedLogServiceId {
                    LogConsoleView(serviceId: serviceId, activeLogServiceId: $selectedLogServiceId)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .transition(.move(edge: .trailing))
                } else if showingParserSettings {
                    ScrollView(.vertical, showsIndicators: false) {
                        parserSettingsView
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                    }
                    .transition(.move(edge: .trailing))
                } else if showingExternalSettings {
                    ScrollView(.vertical, showsIndicators: false) {
                        compactExternalSettingsView
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                    }
                    .transition(.move(edge: .trailing))
                } else if showingAdvanced {
                    ScrollView(.vertical, showsIndicators: false) {
                        advancedView
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        mainSettingsView
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                    }
                    .transition(.move(edge: .leading))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 340, height: 400)
        .background(OrivoTheme.bgWindow)
        .animation(.easeInOut(duration: 0.25), value: showingAdvanced)
        .animation(.easeInOut(duration: 0.25), value: showingParserSettings)
        .animation(.easeInOut(duration: 0.25), value: showingExternalSettings)
        .animation(.easeInOut(duration: 0.25), value: selectedLogServiceId)
    }
    
    private var navigationHeader: some View {
        ZStack {
            Text(currentTitle)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(OrivoTheme.textPrimary)
            
            HStack {
                Button(action: handleBackAction) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(OrivoTheme.accentColor)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.leading, 70)
                
                Spacer()
            }
            
            if selectedLogServiceId != nil {
                HStack {
                    Spacer()
                    Button(action: triggerClearLogs) {
                        Text(loc.tr("clear"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(OrivoTheme.accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.trailing, 24)
                }
            }
        }
        .frame(height: 48)
        .padding(.top, 16)
    }
    
    private var mainSettingsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(loc.tr("general"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(OrivoTheme.textTertiary)
                
                Toggle(loc.tr("launch_login"), isOn: Binding(
                    get: { settingsManager.settings.launchAtLogin },
                    set: { settingsManager.updateSetting(\.launchAtLogin, value: $0) }
                ))
                .toggleStyle(CheckboxToggleStyle())
                
                Toggle(loc.tr("check_updates"), isOn: .constant(true))
                .toggleStyle(CheckboxToggleStyle())
                .disabled(true)
                
                Toggle(loc.tr("open_library_launch"), isOn: Binding(
                    get: { settingsManager.settings.openLibraryOnLaunch },
                    set: { settingsManager.updateSetting(\.openLibraryOnLaunch, value: $0) }
                ))
                .toggleStyle(CheckboxToggleStyle())
                
                Toggle(loc.tr("quit_on_close"), isOn: Binding(
                    get: { settingsManager.settings.quitOnClose },
                    set: { settingsManager.updateSetting(\.quitOnClose, value: $0) }
                ))
                .toggleStyle(CheckboxToggleStyle())
            }
            .font(.system(size: 13))
            
            HStack {
                Text(loc.tr("language"))
                    .foregroundColor(OrivoTheme.textSecondary)
                Spacer()
                Picker("", selection: $loc.currentLanguage) {
                    Text(loc.tr("english")).tag("en")
                    Text(loc.tr("russian")).tag("ru")
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 140)
            }
            .font(.system(size: 13))
            .padding(.top, 2)
            
            HStack {
                Text(loc.currentLanguage == "ru" ? "Каталог" : "Catalog")
                    .foregroundColor(OrivoTheme.textSecondary)
                Spacer()
                Picker("", selection: $catalogInterfaceMode) {
                    Text(loc.currentLanguage == "ru" ? "Нативный" : "Native").tag("native")
                    Text("Lampa Web").tag("lampa")
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 160)
            }
            .font(.system(size: 13))
            .padding(.top, 2)
            
            Button(action: { showingParserSettings = true }) {
                HStack {
                    Text(loc.currentLanguage == "ru" ? "Источники и Парсер (API)" : "Sources & Parser (API)")
                        .foregroundColor(OrivoTheme.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(OrivoTheme.textTertiary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .font(.system(size: 13))
            .padding(.top, 2)
            
            Button(action: { showingExternalSettings = true }) {
                HStack {
                    Text(loc.currentLanguage == "ru" ? "Внешние сервера" : "External Servers")
                        .foregroundColor(OrivoTheme.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(OrivoTheme.textTertiary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .font(.system(size: 13))
            .padding(.top, 2)
            
            Divider()
                .background(OrivoTheme.borderDefault)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(loc.tr("components"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(OrivoTheme.textTertiary)
                
                ForEach(serviceManager.services) { service in
                    let status = serviceManager.statuses[service.id] ?? .stopped
                    HStack {
                        Button(action: { openServiceWebUI(serviceId: service.id) }) {
                            HStack(spacing: 4) {
                                Text(service.name)
                                    .underline()
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(OrivoTheme.accentColor)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Spacer()
                        
                        Text(loc.tr(status.rawValue.lowercased()))
                            .foregroundColor(status.isRunning ? .green : OrivoTheme.textTertiary)
                    }
                    .font(.system(size: 13))
                    .padding(.vertical, 1)
                }
            }
            
            Divider()
                .background(OrivoTheme.borderDefault)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(loc.tr("local_network"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(OrivoTheme.textTertiary)
                
                HStack {
                    Text(loc.tr("mac_ip"))
                        .foregroundColor(OrivoTheme.textSecondary)
                    Spacer()
                    Text(getLocalIPAddress())
                        .foregroundColor(OrivoTheme.textPrimary)
                        .textSelection(.enabled)
                }
                .font(.system(size: 13))
            }
            
            Divider()
                .background(OrivoTheme.borderDefault)
            
            Button(action: { showingAdvanced = true }) {
                HStack {
                    Text(loc.tr("advanced_dots"))
                        .font(.system(size: 12))
                        .foregroundColor(OrivoTheme.accentColor)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(OrivoTheme.textTertiary)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var advancedView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc.tr("system_logs"))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(OrivoTheme.textTertiary)
            
            ForEach(serviceManager.services) { service in
                Button(action: { selectedLogServiceId = service.id }) {
                    HStack {
                        Text("\(service.name) " + loc.tr("log_stream"))
                            .foregroundColor(OrivoTheme.textSecondary)
                        Spacer()
                        Image(systemName: "terminal")
                            .foregroundColor(OrivoTheme.textTertiary)
                    }
                    .font(.system(size: 13))
                    .padding(.vertical, 4)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private var parserSettingsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(loc.currentLanguage == "ru" ? "НАСТРОЙКИ TORRSERVER" : "TORRSERVER SETTINGS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(OrivoTheme.textTertiary)
                
                Toggle(loc.currentLanguage == "ru" ? "Использовать TorrServer" : "Use TorrServer", isOn: Binding(
                    get: { settingsManager.settings.useTorrServer },
                    set: { settingsManager.updateSetting(\.useTorrServer, value: $0) }
                ))
                .toggleStyle(CheckboxToggleStyle())
                .font(.system(size: 13))
                
                if settingsManager.settings.useTorrServer {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.currentLanguage == "ru" ? "Адрес TorrServer" : "TorrServer Host URL")
                            .font(.system(size: 11))
                            .foregroundColor(OrivoTheme.textSecondary)
                        
                        TextField("http://127.0.0.1:8090", text: Binding(
                            get: { settingsManager.settings.torrserverHost },
                            set: { settingsManager.updateSetting(\.torrserverHost, value: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 12))
                    }
                    .padding(.leading, 18)
                }
            }
            
            Divider()
                .background(OrivoTheme.borderDefault)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(loc.currentLanguage == "ru" ? "НАСТРОЙКИ JACKETT" : "JACKETT SETTINGS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(OrivoTheme.textTertiary)
                
                Toggle(loc.currentLanguage == "ru" ? "Использовать Jackett" : "Use Jackett", isOn: Binding(
                    get: { settingsManager.settings.useJackett },
                    set: { settingsManager.updateSetting(\.useJackett, value: $0) }
                ))
                .toggleStyle(CheckboxToggleStyle())
                .font(.system(size: 13))
                
                if settingsManager.settings.useJackett {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.currentLanguage == "ru" ? "Адрес Jackett" : "Jackett Host URL")
                            .font(.system(size: 11))
                            .foregroundColor(OrivoTheme.textSecondary)
                        
                        TextField("http://127.0.0.1:9117", text: Binding(
                            get: { settingsManager.settings.jackettHost },
                            set: { settingsManager.updateSetting(\.jackettHost, value: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 12))
                    }
                    .padding(.leading, 18)
                }
            }
            
            Divider()
                .background(OrivoTheme.borderDefault)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(loc.currentLanguage == "ru" ? "АКТИВНЫЕ ИНДЕКСАТОРЫ JACKETT" : "ACTIVE JACKETT INDEXERS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(OrivoTheme.textTertiary)
                
                if isLoadingIndexers {
                    HStack {
                        Spacer()
                        ProgressView().scaleEffect(0.8)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else if indexers.isEmpty {
                    Text(loc.currentLanguage == "ru" ? "Индексаторы не найдены." : "No indexers found.")
                        .font(.system(size: 11))
                        .foregroundColor(OrivoTheme.textSecondary)
                } else {
                    ForEach(indexers) { indexer in
                        HStack(spacing: 8) {
                            Circle()
                                .fill((indexer.configured ?? false) ? Color.green : Color.gray)
                                .frame(width: 6, height: 6)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(indexer.name ?? "Без названия")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(OrivoTheme.textPrimary)
                                
                                if let desc = indexer.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.system(size: 10))
                                        .foregroundColor(OrivoTheme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text((indexer.configured ?? false) ? (loc.currentLanguage == "ru" ? "Активен" : "Active") : (loc.currentLanguage == "ru" ? "Не активен" : "Inactive"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor((indexer.configured ?? false) ? Color.green : OrivoTheme.textTertiary)
                        }
                        .padding(6)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(4)
                    }
                }
            }
        }
        .task {
            loadIndexers()
        }
    }
    
    private var compactExternalSettingsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(loc.currentLanguage == "ru" ? "РЕЖИМ ВНЕШНИХ СЕРВЕРОВ" : "EXTERNAL SERVERS MODE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(OrivoTheme.textTertiary)
                
                Toggle(loc.currentLanguage == "ru" ? "Использовать внешние сервера" : "Use External Servers", isOn: Binding(
                    get: { settingsManager.settings.useExternalServers },
                    set: { newValue in
                        settingsManager.updateSetting(\.useExternalServers, value: newValue)
                        if newValue {
                            serviceManager.stopAllServices()
                        } else {
                            serviceManager.startAllAutoStartServices()
                        }
                    }
                ))
                .toggleStyle(CheckboxToggleStyle())
                .font(.system(size: 13))
                
                Text(loc.currentLanguage == "ru" 
                    ? "Локальные службы будут остановлены." 
                    : "Local services will be stopped.")
                    .font(.system(size: 10))
                    .foregroundColor(OrivoTheme.textSecondary)
                    .padding(.leading, 18)
            }
            
            if settingsManager.settings.useExternalServers {
                Divider()
                    .background(OrivoTheme.borderDefault)
                
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.currentLanguage == "ru" ? "Внешняя Lampa URL (опция)" : "External Lampa URL (Optional)")
                            .font(.system(size: 11))
                            .foregroundColor(OrivoTheme.textSecondary)
                        TextField("http://lampa.mx", text: Binding(
                            get: { settingsManager.settings.externalLampaURL },
                            set: { settingsManager.updateSetting(\.externalLampaURL, value: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 11))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.currentLanguage == "ru" ? "Внешний TorrServer URL" : "External TorrServer URL")
                            .font(.system(size: 11))
                            .foregroundColor(OrivoTheme.textSecondary)
                        TextField("http://192.168.1.100:8090", text: Binding(
                            get: { settingsManager.settings.externalTorrServerHost },
                            set: { settingsManager.updateSetting(\.externalTorrServerHost, value: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 11))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.currentLanguage == "ru" ? "Внешний Jackett URL" : "External Jackett URL")
                            .font(.system(size: 11))
                            .foregroundColor(OrivoTheme.textSecondary)
                        TextField("http://192.168.1.100:9117", text: Binding(
                            get: { settingsManager.settings.externalJackettHost },
                            set: { settingsManager.updateSetting(\.externalJackettHost, value: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 11))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.currentLanguage == "ru" ? "API-ключ Jackett" : "Jackett API Key")
                            .font(.system(size: 11))
                            .foregroundColor(OrivoTheme.textSecondary)
                        TextField("API-ключ", text: Binding(
                            get: { settingsManager.settings.externalJackettApiKey },
                            set: { settingsManager.updateSetting(\.externalJackettApiKey, value: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 11))
                    }
                }
            }
        }
    }
    
    
    private var currentTitle: String {
        if let serviceId = selectedLogServiceId {
            let name = serviceManager.services.first(where: { $0.id == serviceId })?.name ?? "Service"
            return "\(name) Log"
        } else if showingParserSettings {
            return loc.currentLanguage == "ru" ? "Парсер и Jackett" : "Parser & Jackett"
        } else if showingExternalSettings {
            return loc.currentLanguage == "ru" ? "Внешние сервера" : "External Servers"
        } else if showingAdvanced {
            return loc.tr("advanced")
        } else {
            return loc.tr("settings")
        }
    }
    
    private func loadIndexers() {
        isLoadingIndexers = true
        Task {
            do {
                self.indexers = try await JackettClient.shared.fetchIndexers()
            } catch {
                print("Failed to load indexers: \(error.localizedDescription)")
            }
            isLoadingIndexers = false
        }
    }
    
    private func handleBackAction() {
        if selectedLogServiceId != nil {
            selectedLogServiceId = nil
        } else if showingParserSettings {
            showingParserSettings = false
        } else if showingExternalSettings {
            showingExternalSettings = false
        } else if showingAdvanced {
            showingAdvanced = false
        } else {
            showSettings = false
        }
    }
    
    private func triggerClearLogs() {
        if let serviceId = selectedLogServiceId {
            NotificationCenter.default.post(name: NSNotification.Name("ClearLogs"), object: serviceId)
        }
    }
    
    private func openServiceWebUI(serviceId: String) {
        let port = serviceId == "torrserver" ? ServiceManager.shared.resolvedTorrServerPort : ServiceManager.shared.resolvedJackettPort
        if let url = URL(string: "http://127.0.0.1:\(port)/") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func getLocalIPAddress() -> String {
        var address: String = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return address }
        guard let firstAddr = ifaddr else { return address }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            var addr = ptr.pointee.ifa_addr.pointee
            
            if addr.sa_family == UInt8(AF_INET) {
                if (flags & IFF_UP) != 0 && (flags & IFF_LOOPBACK) == 0 {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(&addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        address = String(cString: hostname)
                        break
                    }
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}
