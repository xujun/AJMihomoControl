import Foundation

/// 语言管理
enum AppLanguage: String, Codable, CaseIterable {
    case system = "system"
    case zh = "zh"
    case en = "en"

    var displayName: String {
        switch self {
        case .system: return String(localized: "跟随系统")
        case .zh: return "中文"
        case .en: return "English"
        }
    }

    /// 获取当前实际使用的语言
    static var current: AppLanguage {
        if let saved = UserDefaults.standard.string(forKey: "AppLanguage"),
           let lang = AppLanguage(rawValue: saved) {
            return lang
        }
        return .system
    }

    /// 设置语言
    static func set(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: "AppLanguage")
    }

    /// 检测系统语言是否为中文
    private static var isSystemChinese: Bool {
        let preferred = Locale.preferredLanguages.first ?? ""
        return preferred.hasPrefix("zh")
    }

    /// 返回当前是否中文
    static var isChinese: Bool {
        switch current {
        case .system: return isSystemChinese
        case .zh: return true
        case .en: return false
        }
    }
}

// MARK: - 本地化字符串
struct L10n {
    private static let isZh = AppLanguage.isChinese

    // 菜单栏
    static let appTitle = isZh ? "Mihomo Control" : "Mihomo Control"
    static let closeProxy = isZh ? "关闭系统代理" : "Disable System Proxy"
    static let openProxy = isZh ? "开启系统代理" : "Enable System Proxy"
    static let mihomoRunning = isZh ? "Mihomo 运行中" : "Mihomo Running"
    static let mihomoStopped = isZh ? "Mihomo 已停止" : "Mihomo Stopped"
    static let restartMihomo = isZh ? "重启 Mihomo" : "Restart Mihomo"
    static let stopMihomo = isZh ? "停止 Mihomo" : "Stop Mihomo"
    static let startMihomo = isZh ? "启动 Mihomo" : "Start Mihomo"
    static let mihomoConfig = isZh ? "Mihomo配置" : "Mihomo Config"
    static let openConfigFolder = isZh ? "打开配置目录" : "Open Config Folder"
    static let openControlPanel = isZh ? "打开控制面板" : "Open Control Panel"
    static let about = isZh ? "关于" : "About"
    static let language = isZh ? "语言" : "Language"
    static let quit = isZh ? "退出" : "Quit"

    // 控制面板
    static let controlPanelTitle = isZh ? "控制面板" : "Control Panel"
    static let proxySection = isZh ? "系统代理" : "System Proxy"
    static let proxyOn = isZh ? "代理中" : "Proxy On"
    static let proxyOff = isZh ? "未代理" : "Proxy Off"
    static let enable = isZh ? "启用" : "Enable"
    static let disable = isZh ? "停用" : "Disable"
    static let mihomoSection = isZh ? "Mihomo" : "Mihomo"
    static let running = isZh ? "运行中" : "Running"
    static let stopped = isZh ? "已停止" : "Stopped"
    static let restart = isZh ? "重启" : "Restart"
    static let stop = isZh ? "停止" : "Stop"
    static let start = isZh ? "启动" : "Start"

    // 配置窗口
    static let mihomoConfigTitle = isZh ? "Mihomo配置" : "Mihomo Config"
    static let mihomoConfigSection = isZh ? "Mihomo 配置" : "Mihomo Configuration"
    static let binaryPath = isZh ? "程序路径" : "Binary Path"
    static let configPath = isZh ? "配置文件" : "Config File"
    static let workingDir = isZh ? "工作目录" : "Working Directory"
    static let select = isZh ? "选择" : "Browse"
    static let saveSettings = isZh ? "保存设置" : "Save Settings"
    static let settingsSaved = isZh ? "设置已保存" : "Settings saved"

    // 关于窗口
    static let aboutTitle = isZh ? "关于" : "About"
    static let version = isZh ? "版本" : "Version"
    static let appDescription = isZh ? "一个 macOS 菜单栏应用\n用于控制 mihomo 代理和系统代理设置" : "A macOS menu bar app\nfor controlling mihomo proxy and system proxy settings."
    static let authorLabel = isZh ? "作者" : "Author"
    static let authorName = "xujun"
    static let authorLink = "https://github.com/xujun"
    static let contactEmail = "5798473@qq.com"
    static let quickStart = isZh ? "快速开始" : "Quick Start"
    static let step1 = isZh ? "1. 安装 mihomo：`brew install mihomo`" : "1. Install mihomo: `brew install mihomo`"
    static let step2 = isZh ? "2. 配置文件位于 `/usr/local/etc/mihomo/config.yaml`" : "2. Config file at `/usr/local/etc/mihomo/config.yaml`"
    static let step3 = isZh ? "3. 启动本应用 — 自动启动 mihomo 并开启代理" : "3. Launch this app — auto-starts mihomo and proxy"

    // 提示
    static let proxyOnTip = isZh ? "Mihomo Control - 代理已开启" : "Mihomo Control - Proxy ON"
    static let proxyOffTip = isZh ? "Mihomo Control - 代理未开启" : "Mihomo Control - Proxy OFF"

    // 代理切换
    static let proxySwitcherSection = isZh ? "代理服务器" : "Proxy Servers"
    static let refreshProxyList = isZh ? "刷新列表" : "Refresh"
    static let testAllDelays = isZh ? "测试延迟" : "Test Delays"
    static let noProxyGroups = isZh ? "无可用服务器" : "No available servers"
    static let apiUnreachable = isZh ? "无法连接到 mihomo API" : "Cannot connect to mihomo API"
    static let retry = isZh ? "重试" : "Retry"
    static let switching = isZh ? "切换中..." : "Switching..."
    static let apiSecretLabel = isZh ? "API 密钥" : "API Secret"
    static let proxyTypeSelect = isZh ? "选择" : "Select"
    static let proxyTypeFallback = isZh ? "回退" : "Fallback"
    static let proxyTypeURLTest = isZh ? "自动测速" : "URLTest"
    static let delayMs = isZh ? "毫秒" : "ms"
    static let delayTimeout = isZh ? "超时" : "Timeout"
    static let noDelay = isZh ? "未测试" : "Not tested"
}
