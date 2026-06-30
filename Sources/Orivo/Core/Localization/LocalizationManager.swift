import Foundation

@MainActor
public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()
    
    @Published public var currentLanguage: String = "en" {
        didSet {
            SettingsManager.shared.updateSetting(\.language, value: currentLanguage)
        }
    }
    
    private init() {
        self.currentLanguage = SettingsManager.shared.settings.language
    }
    
    public func tr(_ key: String) -> String {
        let dict = currentLanguage == "ru" ? ruTranslations : enTranslations
        return dict[key] ?? key
    }
    
    private let enTranslations = [
        "app_title": "Orivo",
        "settings": "Settings",
        "advanced": "Advanced",
        "general": "General",
        "launch_login": "Launch Orivo at login",
        "check_updates": "Check for updates automatically",
        "open_library_launch": "Open library on launch",
        "quit_on_close": "Quit Orivo when closing window",
        "components": "Components",
        "installed": "Installed",
        "local_network": "Local Network",
        "mac_ip": "Mac IP Address",
        "jackett_key": "Jackett API Key",
        "advanced_dots": "Advanced...",
        "system_logs": "System Logs",
        "log_stream": "Log Stream",
        "back": "Back",
        "clear": "Clear",
        "preferences": "Preferences...",
        "background_services": "Background Services",
        "everything_ready": "Everything is ready.",
        "online": "Online",
        "open_library": "Open Lampa",
        "needs_attention": "Needs attention",
        "services_unavailable": "Some background services are unavailable.",
        "fix": "Fix",
        "no_logs": "No log entries recorded.",
        "language": "Language",
        "english": "English",
        "russian": "Русский",
        "welcome_title": "Welcome to Orivo.",
        "welcome_subtitle": "We'll prepare everything\nfor your media library.",
        "downloading": "Downloading components...",
        "installing": "Installing...",
        "starting_services": "Starting services...",
        "done_title": "Done.",
        "done_subtitle": "Your media hub is configured and running in the background.",
        "continue": "Continue",
        "error_config": "Error: Unsupported configuration."
    ]
    
    private let ruTranslations = [
        "app_title": "Orivo",
        "settings": "Настройки",
        "advanced": "Дополнительно",
        "general": "Основные",
        "launch_login": "Запускать Orivo при старте системы",
        "check_updates": "Проверять обновления автоматически",
        "open_library_launch": "Открывать медиатеку при запуске",
        "quit_on_close": "Закрывать Orivo при закрытии окна",
        "components": "Компоненты",
        "installed": "Установлено",
        "local_network": "Локальная сеть",
        "mac_ip": "IP-адрес Mac",
        "jackett_key": "API-ключ Jackett",
        "advanced_dots": "Дополнительно...",
        "system_logs": "Системные логи",
        "log_stream": "Поток логов",
        "back": "Назад",
        "clear": "Очистить",
        "preferences": "Настройки...",
        "background_services": "Фоновые службы",
        "everything_ready": "Всё готово к работе.",
        "online": "В сети",
        "open_library": "Открыть Lampa",
        "needs_attention": "Требуется внимание",
        "services_unavailable": "Некоторые фоновые службы недоступны.",
        "fix": "Исправить",
        "no_logs": "Записей в логе пока нет.",
        "language": "Язык",
        "english": "English",
        "russian": "Русский",
        "welcome_title": "Добро пожаловать в Orivo.",
        "welcome_subtitle": "Мы настроим всё необходимое\nдля работы вашей медиатеки.",
        "downloading": "Загрузка компонентов...",
        "installing": "Установка...",
        "starting_services": "Запуск служб...",
        "done_title": "Готово.",
        "done_subtitle": "Службы медиатеки настроены и запущены в фоне.",
        "continue": "Продолжить",
        "error_config": "Ошибка: конфигурация не поддерживается."
    ]
}
