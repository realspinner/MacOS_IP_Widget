import Foundation

/// Tiny built-in localization table. The widget follows the system language and
/// falls back to English for anything other than Russian.
public enum L10n {
    public enum Key: String, Sendable {
        case ipRating
        case preferredIPProvider
        case ipRatingExplanation
        case openApp
        case startApp
        case dataExpired
        case noConnection
        case checkNetwork
        case noResponse
        case serviceUnavailable
        case updatingData
        case checking
        case refreshing
        case network
        case unknownCountry
        case refreshNow
        case showWidget
        case hideWidget
        case launchAtLogin
        case openSite
        case quit
        case statusChecking
        case loginItemFailedTitle
        case loginItemFailedMessage
        case loginItemApprovalTitle
        case loginItemApprovalMessage
        case openSettings
        case cancel
        case addWidgetMenu
        case addWidgetTitle
        case addWidgetMessage
        case ok
    }

    public static var languageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    public static func t(_ key: Key, languageCode: String? = nil) -> String {
        let code = languageCode ?? self.languageCode
        let table = code == "ru" ? russian : english
        return table[key] ?? english[key] ?? key.rawValue
    }

    private static let english: [Key: String] = [
        .preferredIPProvider: "Preferred IP service",
        .ipRating: "IP rating",
        .ipRatingExplanation: "Synthetic IP reputation from ProxyCheck; not a guarantee of Claude access.",
        .openApp: "Open IP Widget",
        .startApp: "Launch the menu bar app",
        .dataExpired: "Data expired",
        .noConnection: "No connection",
        .checkNetwork: "Check your Wi-Fi or cable",
        .noResponse: "No response",
        .serviceUnavailable: "IP services are unavailable",
        .updatingData: "Updating data...",
        .checking: "Checking connection…",
        .refreshing: "Updating…",
        .network: "network",
        .unknownCountry: "Unknown country",
        .refreshNow: "Refresh Now",
        .showWidget: "Show Widget",
        .hideWidget: "Hide Widget",
        .launchAtLogin: "Launch at Login",
        .openSite: "Open 2ip.io",
        .quit: "Quit IP Widget",
        .statusChecking: "Checking…",
        .loginItemFailedTitle: "Could not change the login item",
        .loginItemFailedMessage: "Move IPWidget.app to /Applications and try again, or add it manually in System Settings → General → Login Items.",
        .loginItemApprovalTitle: "Allow IP Widget to start automatically",
        .loginItemApprovalMessage: "Open System Settings → General → Login Items and enable IP Widget.",
        .openSettings: "Open Settings",
        .cancel: "Cancel",
        .addWidgetMenu: "How to Add the Widget…",
        .addWidgetTitle: "Add the widget to your desktop",
        .addWidgetMessage: "1. Right-click an empty area of the desktop.\n2. Choose “Edit Widgets…”.\n3. Find “IP Widget” and add it.\n\nThe widget refreshes every 5 minutes, and immediately when the network changes while the helper app is running.",
        .ok: "Done",
    ]

    private static let russian: [Key: String] = [
        .preferredIPProvider: "Приоритетный сервис IP",
        .ipRating: "Рейтинг IP",
        .ipRatingExplanation: "Синтетическая оценка репутации IP по данным ProxyCheck; не гарантирует доступ к Claude.",
        .openApp: "Откройте IP Widget",
        .startApp: "Запустите приложение",
        .dataExpired: "Данные устарели",
        .noConnection: "Нет соединения",
        .checkNetwork: "Проверьте Wi-Fi или кабель",
        .noResponse: "Нет ответа",
        .serviceUnavailable: "Сервисы IP недоступны",
        .updatingData: "Обновление данных...",
        .checking: "Проверяем соединение…",
        .refreshing: "Обновление…",
        .network: "сеть",
        .unknownCountry: "Неизвестная страна",
        .refreshNow: "Обновить сейчас",
        .showWidget: "Показать виджет",
        .hideWidget: "Скрыть виджет",
        .launchAtLogin: "Запускать при входе",
        .openSite: "Открыть 2ip.io",
        .quit: "Выйти из IP Widget",
        .statusChecking: "Проверка…",
        .loginItemFailedTitle: "Не удалось изменить автозапуск",
        .loginItemFailedMessage: "Переместите IPWidget.app в «Программы» и попробуйте снова или добавьте его вручную в «Системные настройки → Основные → Элементы входа».",
        .loginItemApprovalTitle: "Разрешите автозапуск IP Widget",
        .loginItemApprovalMessage: "Откройте «Системные настройки → Основные → Элементы входа» и включите IP Widget.",
        .openSettings: "Открыть настройки",
        .cancel: "Отмена",
        .addWidgetMenu: "Как добавить виджет…",
        .addWidgetTitle: "Добавьте виджет на рабочий стол",
        .addWidgetMessage: "1. Нажмите правой кнопкой мыши на свободном месте рабочего стола.\n2. Выберите «Изменить виджеты…».\n3. Найдите «IP Widget» и добавьте его.\n\nВиджет обновляется каждые 5 минут, а при запущенном приложении — сразу при смене сети.",
        .ok: "Готово",
    ]
}
